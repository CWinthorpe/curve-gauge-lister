// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {TestBase, Vm} from "./TestBase.sol";
import {CurveGaugeLister} from "../contracts/CurveGaugeLister.sol";
import {IERC20Minimal} from "../contracts/interfaces/IERC20Minimal.sol";
import {IIncentivePlatform} from "../contracts/interfaces/IIncentivePlatform.sol";
import {SafeToken} from "../contracts/libraries/SafeToken.sol";
import {VotiumAdapter} from "../contracts/adapters/VotiumAdapter.sol";
import {VoteMarketAdapter} from "../contracts/adapters/VoteMarketAdapter.sol";
import {AdapterOwnable} from "../contracts/libraries/AdapterOwnable.sol";
import {MockERC20} from "../contracts/mocks/MockERC20.sol";
import {MockPool} from "../contracts/mocks/MockPool.sol";
import {MockGauge} from "../contracts/mocks/MockGauge.sol";
import {MockCurveRegistry} from "../contracts/mocks/MockCurveRegistry.sol";
import {MockListingController} from "../contracts/mocks/MockListingController.sol";
import {MockFeeDistributor} from "../contracts/mocks/MockFeeDistributor.sol";
import {MockVotiumV2} from "../contracts/mocks/MockVotiumV2.sol";
import {MockCampaignRemoteManager} from "../contracts/mocks/MockCampaignRemoteManager.sol";
import {AlwaysTrueTrustedValidator} from "./mocks/TrustedFactoryMocks.sol";

/// @dev Minimal extra cheatcodes this suite needs; same cheatcode dispatcher,
/// no forge-std dependency (TestBase Vm stays untouched for other suites).
interface VmExt {
    function deal(address who, uint256 newBalance) external;
}

/// @notice Test-only stand-in for the lister side of `IIncentivePlatform.deposit`
/// used in direct adapter unit tests: mirrors core `_fundPlatform` (exact
/// approval, deposit, nonzero-receipt and exact-debit checks, clear to zero).
/// Its reverts therefore roll the whole call back, so callers can assert
/// no-partial-state after a rejected deposit.
contract ListerCaller {
    error ReceiptMissing();
    error DeltaMismatch();

    address public token;

    function setToken(address token_) external {
        token = token_;
    }

    function deposit(IIncentivePlatform platform, address gauge, uint256 scheduledEpoch, uint256 amount)
        external
        returns (bytes32 receipt)
    {
        uint256 balBefore = IERC20Minimal(token).balanceOf(address(this));
        SafeToken.forceApprove(token, address(platform), amount);
        receipt = platform.deposit(gauge, scheduledEpoch, amount);
        if (receipt == bytes32(0)) revert ReceiptMissing();
        uint256 balAfter = IERC20Minimal(token).balanceOf(address(this));
        // Directional exact-delta check: direction before subtracting, so an
        // opposite-direction observation surfaces via DeltaMismatch, never a
        // Panic (mirrors core `_fundPlatform`).
        if (balAfter > balBefore || balBefore - balAfter != amount) revert DeltaMismatch();
        SafeToken.forceApprove(token, address(platform), 0);
    }

    receive() external payable {}
}

/// @notice Test-only ETH forwarder exercising the VoteMarket adapter's
/// `receive()` ops-float path (anyone can send; nothing can take back).
contract EthSink {
    receive() external payable {}

    function fund(address target) external payable {
        (bool ok,) = target.call{value: msg.value}("");
        require(ok, "eth send failed");
    }
}

/// @notice Real-platform adapters (docs/INTEL-YB-HELPERS.md §3) against the
/// faithful IVotiumV2 / ICampaignRemoteManager mocks, plus a full-listing
/// integration through lister.checkpoint.
contract AdaptersTest is TestBase {
    /// @dev Adapter-side binding receipt event (auditfix001 §1 expectEmit).
    event ListerSet(address indexed lister);

    uint256 internal constant FEE = 10_000e18;
    uint256 internal constant QUARTER = 2_500e18;
    uint256 internal constant HALF = 1_250e18;
    uint256 internal constant WEEK = 604800;
    uint256 internal constant T0 = 1794441600; // Thu 2026-11-12 00:00 UTC
    uint256 internal constant GWEI = 1 gwei;
    uint256 internal constant CREATION_GAS = 2_000_000;
    uint256 internal constant BLACKLIST_GAS = 50_000;
    /// @notice campaignCreationGas * gasPrice at the defaults of both the
    /// adapter and the CRM mock (the ops ETH float per quarter).
    uint256 internal constant REQUIRED_ETH = CREATION_GAS * GWEI;
    address internal constant VM_L2 = 0x8c2c5A295450DDFf4CB360cA73FCCC12243D14D9;
    bytes32 internal constant PLATFORM_DEPOSIT_SIG =
        keccak256("PlatformDeposit(address,address,uint256,uint256,uint256,bytes32)");

    VmExt internal constant vmx = VmExt(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    MockERC20 internal token;
    MockERC20 internal otherToken;
    MockCurveRegistry internal registry;
    MockListingController internal controller;
    MockFeeDistributor internal fd;
    MockVotiumV2 internal votiumMock;
    MockCampaignRemoteManager internal crmMock;
    VotiumAdapter internal votiumAdapter;
    VoteMarketAdapter internal vmAdapter;
    CurveGaugeLister internal lister;

    address internal daoOwner;
    address internal adapterManager;
    address internal controllerDao;
    address internal fdAdmin;
    address internal payer;
    address internal stranger;

    function setUp() public {
        daoOwner = actor("daoMultisig");
        adapterManager = actor("adapterManager");
        controllerDao = actor("controllerDao");
        fdAdmin = actor("fdAdmin");
        payer = actor("payer");
        stranger = actor("stranger");

        token = new MockERC20(18);
        otherToken = new MockERC20(18);
        registry = new MockCurveRegistry();
        controller = new MockListingController(controllerDao, int128(2));
        vm.warp(T0);
        // The verified CampaignRemoteManager ingress guard (C1:1749) requires
        // block.chainid == 1, so every campaign fixture that must SUCCEED runs
        // explicitly at the real source chain; the rejection case in
        // test_Adapter_VoteMarketCampaignRequiresSourceChain flips it away.
        vm.chainId(1);
        fd = new MockFeeDistributor(address(token), fdAdmin, T0);

        address[] memory allowed = new address[](1);
        allowed[0] = address(token);
        votiumMock = new MockVotiumV2(allowed);
        address[] memory platforms = new address[](1);
        platforms[0] = VM_L2;
        crmMock = new MockCampaignRemoteManager(GWEI, platforms);

        votiumAdapter = new VotiumAdapter(address(token), adapterManager, address(votiumMock));
        vmAdapter = new VoteMarketAdapter(address(token), adapterManager, address(crmMock), VM_L2);

        lister = new CurveGaugeLister(
            daoOwner,
            address(token),
            address(controller),
            address(fd),
            CurveGaugeLister.AdmissionConfig(address(registry), 8),
            CurveGaugeLister.PlatformConfig(address(votiumAdapter), address(vmAdapter), 5000),
            address(new AlwaysTrueTrustedValidator())
        );

        vm.prank(controllerDao);
        controller.setLister(address(lister));
        // auditfix001 §1: production adapters bind owner-authenticated; prank
        // the actual adapter owner, narrowly scoped to each call.
        vm.prank(adapterManager);
        votiumAdapter.setLister(address(lister));
        vm.prank(adapterManager);
        vmAdapter.setLister(address(lister));
        assertEq(votiumAdapter.lister(), address(lister), "votium adapter bound in setUp");
        assertEq(vmAdapter.lister(), address(lister), "votemarket adapter bound in setUp");

        // V1ALIGN §1.3: the fresh core starts paused. Observe that shipped
        // state, then the owner unpauses after binding so every retained
        // downstream obligation runs on its original path.
        assertTrue(lister.paused(), "core starts paused");
        vm.prank(daoOwner);
        lister.setPaused(false);

        // Ops ETH float for the cross-chain campaign messages.
        vmx.deal(address(vmAdapter), 1 ether);

        token.mint(payer, 40 * FEE);
        vm.startPrank(payer);
        token.approve(address(lister), type(uint256).max);
        vm.stopPrank();
    }

    // ---------------------------------------------------------------
    // fixtures
    // ---------------------------------------------------------------

    function _coins(address a, address b) internal pure returns (address[8] memory c) {
        c[0] = a;
        c[1] = b;
    }

    function deployAuthenticatedPool(uint256 handlerId, uint256 gaugeIndex)
        internal
        returns (address pool, address gauge, address lp)
    {
        lp = address(new MockERC20(18));
        pool = address(new MockPool());
        gauge = address(new MockGauge(lp));
        registry.setPool(pool, handlerId, lp, _coins(address(new MockERC20(18)), address(new MockERC20(18))), 2);
        registry.setGauge(pool, handlerId, gaugeIndex, gauge, 0);
    }

    function listPaid(address pool, address gauge, uint256 gaugeIndex, uint256 handlerId) internal {
        vm.prank(payer);
        lister.listGauge(pool, gauge, gaugeIndex, handlerId);
    }

    /// @dev Kill the gauge for settlement via its admin-side flag (A2):
    /// flip MockGauge's independent killed switch; weight is never touched.
    function killGauge(address gauge) internal {
        MockGauge(gauge).setKilled(true);
    }

    struct VotiumKit {
        VotiumAdapter adapter_;
        ListerCaller caller;
    }

    /// @dev Fresh caller-bound Votium adapter (direct-deposit unit tests).
    /// Binding is owner-authenticated (auditfix001 §1): prank the actual
    /// adapterManager, narrowly scoped.
    function freshVotiumKit(address votiumEndpoint) internal returns (VotiumKit memory kit) {
        kit.adapter_ = new VotiumAdapter(address(token), adapterManager, votiumEndpoint);
        kit.caller = new ListerCaller();
        kit.caller.setToken(address(token));
        token.mint(address(kit.caller), 100 * HALF);
        vm.prank(adapterManager);
        kit.adapter_.setLister(address(kit.caller));
        assertEq(kit.adapter_.lister(), address(kit.caller), "kit votium bound to its caller");
    }

    struct VmKit {
        VoteMarketAdapter adapter_;
        ListerCaller caller;
    }

    /// @dev Fresh caller-bound VoteMarket adapter against a given CRM endpoint,
    /// funded with a comfortable ops ETH float. Binding is owner-authenticated
    /// (auditfix001 §1): prank the actual adapterManager, narrowly scoped.
    function freshVmKit(address crmEndpoint) internal returns (VmKit memory kit) {
        kit.adapter_ = new VoteMarketAdapter(address(token), adapterManager, crmEndpoint, VM_L2);
        kit.caller = new ListerCaller();
        kit.caller.setToken(address(token));
        token.mint(address(kit.caller), 100 * HALF);
        vmx.deal(address(kit.adapter_), 10 ether);
        vm.prank(adapterManager);
        kit.adapter_.setLister(address(kit.caller));
        assertEq(kit.adapter_.lister(), address(kit.caller), "kit votemarket bound to its caller");
    }

    // ---------------------------------------------------------------
    // Votium adapter
    // ---------------------------------------------------------------

    function test_Adapter_VotiumDeterministicNonzeroReceipts() public {
        VotiumKit memory kit = freshVotiumKit(address(votiumMock));
        address g = actor("gaugeA");
        uint256 e = T0 + WEEK;

        bytes32 r1 = kit.caller.deposit(IIncentivePlatform(address(kit.adapter_)), g, e, HALF);
        bytes32 r2 = kit.caller.deposit(IIncentivePlatform(address(kit.adapter_)), g, e, HALF);
        assertTrue(r1 != bytes32(0), "zero receipt impossible");
        assertEq(r1, r2, "receipt deterministic in (gauge,scheduledEpoch,amount,round)");

        // Different gauge → different receipt.
        bytes32 r3 = kit.caller.deposit(IIncentivePlatform(address(kit.adapter_)), actor("gaugeB"), e, HALF);
        assertTrue(r3 != r1 && r3 != bytes32(0), "gauge-keyed receipt");

        // Same tuple, new round → new receipt (round participates).
        votiumMock.setActiveRound(42);
        bytes32 r4 = kit.caller.deposit(IIncentivePlatform(address(kit.adapter_)), g, e, HALF);
        assertTrue(r4 != r1 && r4 != bytes32(0), "round-bound receipt");
        assertEq(r4, keccak256(abi.encode(g, e, HALF, 42)), "receipt equals the documented keccak tuple");

        // Different amount → different receipt.
        bytes32 r5 = kit.caller.deposit(IIncentivePlatform(address(kit.adapter_)), g, e, HALF + 1);
        assertEq(r5, keccak256(abi.encode(g, e, HALF + 1, 42)), "amount participates");
    }

    function test_Adapter_VotiumNonListerAndBindingRejects() public {
        VotiumKit memory kit = freshVotiumKit(address(votiumMock));
        address g = actor("gaugeA");
        uint256 e = T0 + WEEK;

        // Bound lister is the caller: a stranger's direct call reverts.
        vm.prank(stranger);
        vm.expectRevert(VotiumAdapter.NotLister.selector);
        kit.adapter_.deposit(g, e, HALF);

        // Authorized rebinding is impossible: ListerAlreadySet even for the
        // actual owner (auditfix001 §1: no reset/rebind path).
        vm.prank(adapterManager);
        vm.expectRevert(VotiumAdapter.ListerAlreadySet.selector);
        kit.adapter_.setLister(actor("secondLister"));

        // auditfix001 §1 / V-H01: on a fresh UNBOUND production adapter an
        // outsider targets an existing deployed contract; the exact revert is
        // NotOwner, the getter stays zero and no ListerSet is emitted.
        VotiumAdapter fresh = new VotiumAdapter(address(token), adapterManager, address(votiumMock));
        vm.recordLogs();
        vm.prank(stranger);
        vm.expectRevert(AdapterOwnable.NotOwner.selector);
        fresh.setLister(address(token));
        Vm.Log[] memory bindLogs = vm.getRecordedLogs();
        assertFalse(
            hasEventFrom(bindLogs, address(fresh), keccak256("ListerSet(address)")), "no ListerSet on outsider binding"
        );
        assertEq(fresh.lister(), address(0), "outsider binding left adapter unbound");

        // Authorized invalid targets still fail BadLister (called as the
        // owner so NotOwner cannot mask the intended check).
        vm.prank(adapterManager);
        vm.expectRevert(VotiumAdapter.BadLister.selector);
        fresh.setLister(stranger);
        vm.prank(adapterManager);
        vm.expectRevert(VotiumAdapter.BadLister.selector);
        fresh.setLister(address(0));
        vm.expectRevert(VotiumAdapter.NotLister.selector);
        fresh.deposit(g, e, HALF);

        // Authorized valid binding succeeds exactly once, emits the existing
        // event and sets the getter to that value.
        vm.expectEmit(true, false, false, true);
        emit ListerSet(address(kit.caller));
        vm.prank(adapterManager);
        fresh.setLister(address(kit.caller));
        assertEq(fresh.lister(), address(kit.caller), "owner binding set the getter");
        // Owner rebinding after the successful bind fails.
        vm.prank(adapterManager);
        vm.expectRevert(VotiumAdapter.ListerAlreadySet.selector);
        fresh.setLister(actor("secondLister"));

        // Deposit shape guards.
        vm.expectRevert(VotiumAdapter.BadDeposit.selector);
        kit.caller.deposit(IIncentivePlatform(address(kit.adapter_)), address(0), e, HALF);
        vm.expectRevert(VotiumAdapter.BadDeposit.selector);
        kit.caller.deposit(IIncentivePlatform(address(kit.adapter_)), g, e, 0);
    }

    function test_Adapter_WrongTokenRejectedEverywhere() public {
        // (a) Core platform validation rejects a non-crvUSD adapter.
        VotiumAdapter wrongTok = new VotiumAdapter(address(otherToken), adapterManager, address(votiumMock));
        vm.prank(daoOwner);
        vm.expectRevert(CurveGaugeLister.BadPlatformConfig.selector);
        lister.setPlatformConfig(CurveGaugeLister.PlatformConfig(address(wrongTok), address(vmAdapter), 5000));
        VoteMarketAdapter wrongTokVm =
            new VoteMarketAdapter(address(otherToken), adapterManager, address(crmMock), VM_L2);
        vm.prank(daoOwner);
        vm.expectRevert(CurveGaugeLister.BadPlatformConfig.selector);
        lister.setPlatformConfig(CurveGaugeLister.PlatformConfig(address(votiumAdapter), address(wrongTokVm), 5000));

        // (b) Votium-side token allowlist: unapproved reward token reverts
        // before any funding is recorded, and nothing moves.
        MockVotiumV2 strict = new MockVotiumV2(new address[](0));
        VotiumKit memory kit = freshVotiumKit(address(strict));
        assertEq(kit.adapter_.rewardToken(), address(token), "rewardToken is crvUSD");
        uint256 callerBefore = token.balanceOf(address(kit.caller));
        vm.expectRevert(MockVotiumV2.UnsupportedToken.selector);
        kit.caller.deposit(IIncentivePlatform(address(kit.adapter_)), actor("gaugeA"), T0 + WEEK, HALF);
        assertEq(token.balanceOf(address(kit.caller)), callerBefore, "failed pull fully rolled back");
        assertEq(strict.incentiveCount(), 0, "no incentive recorded");
        assertEq(token.balanceOf(address(kit.adapter_)), 0, "adapter holds nothing after revert");
    }

    function test_Adapter_VotiumConfigOwnerOnlyAndPassedThrough() public {
        VotiumKit memory kit = freshVotiumKit(address(votiumMock));

        vm.prank(stranger);
        vm.expectRevert(AdapterOwnable.NotOwner.selector);
        kit.adapter_.setMaxPerVote(777);
        address[] memory one = new address[](1);
        one[0] = actor("voterX");
        vm.prank(stranger);
        vm.expectRevert(AdapterOwnable.NotOwner.selector);
        kit.adapter_.setExcluded(one);

        address[] memory badZero = new address[](1);
        badZero[0] = address(0);
        vm.prank(adapterManager);
        vm.expectRevert(VotiumAdapter.BadExclusion.selector);
        kit.adapter_.setExcluded(badZero);
        address[] memory badDup = new address[](2);
        badDup[0] = actor("voterX");
        badDup[1] = actor("voterX");
        vm.prank(adapterManager);
        vm.expectRevert(VotiumAdapter.BadExclusion.selector);
        kit.adapter_.setExcluded(badDup);
        address[] memory tooBig = new address[](kit.adapter_.MAX_EXCLUDED() + 1);
        for (uint256 i = 0; i < tooBig.length; ++i) {
            tooBig[i] = address(uint160(i + 1));
        }
        vm.prank(adapterManager);
        vm.expectRevert(VotiumAdapter.BadExclusion.selector);
        kit.adapter_.setExcluded(tooBig);

        vm.prank(adapterManager);
        kit.adapter_.setMaxPerVote(777);
        // The venue must open an exclusion budget (real default is 0,
        // Votium.sol:31), and the configured list must be strictly increasing
        // (venue `!sorted`, Votium.sol:658-665): actor("voterY")
        // (0x070968b5...) sorts BELOW actor("voterX") (0x5dfda268...).
        votiumMock.setMaxExclusions(2);
        address[] memory excl = new address[](2);
        excl[0] = actor("voterY");
        excl[1] = actor("voterX");
        vm.prank(adapterManager);
        kit.adapter_.setExcluded(excl);
        assertEq(kit.adapter_.maxPerVote(), 777, "cap stored");
        assertEq(kit.adapter_.excluded().length, 2, "exclusions stored");

        uint256 before = votiumMock.incentiveCount();
        kit.caller.deposit(IIncentivePlatform(address(kit.adapter_)), actor("gaugeA"), T0 + WEEK, HALF);
        MockVotiumV2.Incentive memory rec = votiumMock.incentiveAt(before);
        assertEq(rec.maxPerVote, 777, "configured cap reaches the platform call");
        assertEq(rec.excluded.length, 2, "configured exclusions reach the platform call");
        assertEq(rec.excluded[0], actor("voterY"), "sorted exclusion passthrough 0");
        assertEq(rec.excluded[1], actor("voterX"), "sorted exclusion passthrough 1");
        // Recorded incentive custody is GROSS funding: the real venue would
        // additionally split this into a platform fee + net reward (README
        // mock-fidelity note); it is not the venue's net incentive accounting.
        assertEq(rec.amount, HALF, "recorded gross funding equals the pull");
    }

    function test_Adapter_VotiumRejectsUnsortedExclusions() public {
        // The adapter must refuse to store what the real venue refuses to
        // accept (`!sorted`, Votium.sol:658-665): a descending pair is
        // rejected (one descending vector is enough), as are duplicates and
        // zero entries.
        VotiumKit memory kit = freshVotiumKit(address(votiumMock));
        votiumMock.setMaxExclusions(4); // venue budget open: order is what fails
        address lo = address(uint160(1000));
        address hi = address(uint160(2000));

        address[] memory unsorted = new address[](2);
        unsorted[0] = hi;
        unsorted[1] = lo;
        vm.prank(adapterManager);
        vm.expectRevert(VotiumAdapter.BadExclusion.selector);
        kit.adapter_.setExcluded(unsorted);
        // Duplicates are rejected by the same strict-increase check.
        address[] memory dup = new address[](2);
        dup[0] = lo;
        dup[1] = lo;
        vm.prank(adapterManager);
        vm.expectRevert(VotiumAdapter.BadExclusion.selector);
        kit.adapter_.setExcluded(dup);
        // A zero entry cannot start a strictly increasing list.
        address[] memory zero = new address[](2);
        zero[0] = lo;
        zero[1] = address(0);
        vm.prank(adapterManager);
        vm.expectRevert(VotiumAdapter.BadExclusion.selector);
        kit.adapter_.setExcluded(zero);
        assertEq(kit.adapter_.excluded().length, 0, "no rejected configuration stored");

        // Positive control: correcting the order funds successfully.
        address[] memory sorted = new address[](2);
        sorted[0] = lo;
        sorted[1] = hi;
        vm.prank(adapterManager);
        kit.adapter_.setExcluded(sorted);
        uint256 before = votiumMock.incentiveCount();
        kit.caller.deposit(IIncentivePlatform(address(kit.adapter_)), actor("gaugeA"), T0 + WEEK, HALF);
        MockVotiumV2.Incentive memory rec = votiumMock.incentiveAt(before);
        assertEq(rec.amount, HALF, "corrected configuration funds");
        assertEq(rec.excluded[0], lo, "sorted entry 0");
        assertEq(rec.excluded[1], hi, "sorted entry 1");
    }

    function test_Adapter_VotiumRejectsCapBeyondRealBound() public {
        // Real Votium.sol:344 requires `maxPerVote < type(uint256).max /
        // (100000000 * 10**18)` ("!highMax"); the adapter must not store an
        // out-of-bound cap that would block every later deposit.
        VotiumKit memory kit = freshVotiumKit(address(votiumMock));
        // Pre-read the bound: an expectRevert armed BEFORE an argument-side
        // staticcall would be consumed by that getter, not the probe.
        uint256 bound = kit.adapter_.MAX_MAX_PER_VOTE();
        assertEq(
            bound,
            MockVotiumV2(address(votiumMock)).MAX_MAX_PER_VOTE(),
            "adapter and venue model the same overflow bound"
        );

        vm.prank(adapterManager);
        vm.expectRevert(VotiumAdapter.BadMaxPerVote.selector);
        kit.adapter_.setMaxPerVote(type(uint256).max);
        vm.prank(adapterManager);
        vm.expectRevert(VotiumAdapter.BadMaxPerVote.selector);
        kit.adapter_.setMaxPerVote(bound);
        assertEq(kit.adapter_.maxPerVote(), 0, "rejected cap not stored");

        // Positive control: the largest venue-acceptable cap funds.
        vm.prank(adapterManager);
        kit.adapter_.setMaxPerVote(bound - 1);
        uint256 before = votiumMock.incentiveCount();
        kit.caller.deposit(IIncentivePlatform(address(kit.adapter_)), actor("gaugeA"), T0 + WEEK, HALF);
        assertEq(votiumMock.incentiveAt(before).maxPerVote, bound - 1, "in-bound cap reaches the venue call");
        assertEq(votiumMock.incentiveAt(before).amount, HALF, "corrected cap funds");
    }

    function test_Adapter_VotiumHonorsVenueExclusionLimit() public {
        // The local MAX_EXCLUDED=50 is a calldata bound, NOT venue
        // compatibility: the venue's own `maxExclusions` (`!excluded`,
        // Votium.sol:345,659) governs, and its real default is 0.
        VotiumKit memory kit = freshVotiumKit(address(votiumMock));
        assertEq(votiumMock.maxExclusions(), 0, "venue default mirrors real source");
        address lo = address(uint160(1000));
        address hi = address(uint160(2000));
        address[] memory one = new address[](1);
        one[0] = lo;
        address[] memory two = new address[](2);
        two[0] = lo;
        two[1] = hi;

        // Venue closed: even one sorted entry exceeds the limit.
        vm.prank(adapterManager);
        vm.expectRevert(VotiumAdapter.BadVenueExclusions.selector);
        kit.adapter_.setExcluded(one);
        // The default no-exclusion path is unaffected by a closed venue limit.
        vm.prank(adapterManager);
        kit.adapter_.setExcluded(new address[](0));
        kit.caller.deposit(IIncentivePlatform(address(kit.adapter_)), actor("gaugeA"), T0 + WEEK, HALF);
        assertEq(votiumMock.incentiveCount(), 1, "default empty-exclusion path funds at venue limit 0");

        // Venue opens to 1: one entry configures, two are refused.
        votiumMock.setMaxExclusions(1);
        vm.prank(adapterManager);
        kit.adapter_.setExcluded(one);
        assertEq(kit.adapter_.excluded().length, 1, "within-limit list stored");
        vm.prank(adapterManager);
        vm.expectRevert(VotiumAdapter.BadVenueExclusions.selector);
        kit.adapter_.setExcluded(two);
        assertEq(kit.adapter_.excluded().length, 1, "over-limit list not stored");

        // Positive control: opening the venue to 2 makes the same config fund.
        votiumMock.setMaxExclusions(2);
        vm.prank(adapterManager);
        kit.adapter_.setExcluded(two);
        kit.caller.deposit(IIncentivePlatform(address(kit.adapter_)), actor("gaugeB"), T0 + WEEK, HALF);
        MockVotiumV2.Incentive memory rec = votiumMock.incentiveAt(1);
        assertEq(rec.excluded.length, 2, "corrected venue limit funds");
        assertEq(rec.amount, HALF, "gross funding recorded");
    }

    // ---------------------------------------------------------------
    // VoteMarket adapter
    // ---------------------------------------------------------------

    function test_Adapter_VoteMarketExactPullRecordedCampaignParams() public {
        (address pool, address gauge,) = deployAuthenticatedPool(0, 0);
        listPaid(pool, gauge, 0, 0);
        uint256 listerBefore = token.balanceOf(address(lister));
        uint256 floatBefore = address(vmAdapter).balance;

        vm.warp(T0 + WEEK);
        lister.checkpoint(gauge);

        // Exact pull from the lister, adapter never retains, custody exact.
        assertEq(listerBefore - token.balanceOf(address(lister)), QUARTER, "lister debited gross quarter");
        assertEq(token.balanceOf(address(crmMock)), HALF, "CRM custody exact");
        assertEq(token.balanceOf(address(vmAdapter)), 0, "adapter never retains tokens");
        assertEq(address(crmMock).balance, REQUIRED_ETH, "bridge gas paid once");
        assertEq(crmMock.ethPaid(), REQUIRED_ETH, "paid-gas ledger");
        assertEq(floatBefore - address(vmAdapter).balance, REQUIRED_ETH, "float debited exactly");

        // Params fidelity, per brief: every field bound.
        assertEq(crmMock.campaignCount(), 1, "one campaign");
        MockCampaignRemoteManager.Campaign memory c = crmMock.campaignAt(0);
        assertEq(c.params.chainId, block.chainid, "chainId = block.chainid");
        assertEq(c.params.gauge, gauge, "gauge binding");
        assertEq(c.params.manager, address(vmAdapter), "manager = adapter");
        assertEq(c.params.rewardToken, address(token), "rewardToken = crvUSD");
        assertEq(uint256(c.params.numberOfPeriods), 2, "numberOfPeriods = 2");
        assertEq(c.params.maxRewardPerVote, type(uint256).max, "default unbounded per-vote cap");
        assertEq(c.params.totalRewardAmount, HALF, "totalRewardAmount = amount");
        assertEq(c.params.addresses.length, 0, "default no exclusions");
        assertEq(c.params.hook, address(0), "no hook");
        assertFalse(c.params.isWhitelist, "public campaign");
        assertEq(c.destinationChainId, 42161, "destination Arbitrum one");
        assertEq(c.additionalGasLimit, CREATION_GAS, "default creation gas");
        assertEq(c.value, REQUIRED_ETH, "value = additionalGasLimit * gasPrice");
        assertEq(c.caller, address(vmAdapter), "CRM caller is the adapter");

        // Adapter-side durable record + cleared approvals at both layers.
        (uint256 amount, uint256 executionEpoch, bytes32 receipt) = vmAdapter.getDeposit(gauge, T0 + WEEK);
        assertEq(amount, HALF, "recorded amount");
        assertEq(executionEpoch, T0 + WEEK, "recorded execution epoch");
        assertTrue(receipt != bytes32(0), "recorded receipt nonzero");
        assertEq(vmAdapter.depositCount(), 1, "one deposit log");
        VoteMarketAdapter.DepositRecord memory d = vmAdapter.depositAt(0);
        assertEq(d.gauge, gauge, "log gauge");
        assertEq(d.scheduledEpoch, T0 + WEEK, "log scheduledEpoch");
        assertEq(d.receipt, receipt, "log receipt matches keyed record");
        assertEq(token.allowance(address(lister), address(vmAdapter)), 0, "lister approval cleared");
        assertEq(token.allowance(address(vmAdapter), address(crmMock)), 0, "adapter approval cleared");
    }

    function test_Adapter_VoteMarketEthShortfallRevertsAndRollsBack() public {
        // (a) Direct: unfunded adapter reverts with the whole deposit rolled
        // back; ethDeficit guides the top-up.
        VoteMarketAdapter bare = new VoteMarketAdapter(address(token), adapterManager, address(crmMock), VM_L2);
        ListerCaller caller = new ListerCaller();
        caller.setToken(address(token));
        token.mint(address(caller), 100 * HALF);
        vm.prank(adapterManager);
        bare.setLister(address(caller));
        address g = actor("gaugeA");
        uint256 e = T0 + WEEK;

        assertEq(address(bare).balance, 0, "unfunded");
        assertEq(bare.ethDeficit(HALF), REQUIRED_ETH, "deficit equals per-call gas value");
        assertEq(bare.ethDeficit(0), 0, "zero-amount query needs no gas");
        vmx.deal(address(bare), REQUIRED_ETH / 2);
        assertEq(bare.ethDeficit(HALF), REQUIRED_ETH / 2, "partial float, partial deficit");
        uint256 crmsBefore = crmMock.campaignCount();
        uint256 callerBefore = token.balanceOf(address(caller));
        vm.expectRevert(VoteMarketAdapter.InsufficientEth.selector);
        caller.deposit(IIncentivePlatform(address(bare)), g, e, HALF);
        assertEq(token.balanceOf(address(caller)), callerBefore, "no pull survived the revert");
        assertEq(crmMock.campaignCount(), crmsBefore, "no campaign survived");
        assertEq(token.allowance(address(caller), address(bare)), 0, "approval rolled back with the call");
        vmx.deal(address(bare), REQUIRED_ETH);
        assertEq(bare.ethDeficit(HALF), 0, "funded");
        caller.deposit(IIncentivePlatform(address(bare)), g, e, HALF);
        assertEq(crmMock.campaignCount(), crmsBefore + 1, "succeeds after top-up");

        // (b) Through the lister: an overpriced gas setting makes the quarter
        // revert, and the checkpoint state is untouched (never a silent skip).
        vm.prank(adapterManager);
        vmAdapter.setGasSettings(CREATION_GAS, BLACKLIST_GAS, 1 ether); // absurd pricing
        (address pool, address gauge,) = deployAuthenticatedPool(1, 1);
        listPaid(pool, gauge, 1, 1);
        vm.warp(T0 + WEEK);
        vm.expectRevert(VoteMarketAdapter.InsufficientEth.selector);
        lister.checkpoint(gauge);
        CurveGaugeLister.Listing memory rec = lister.getListing(gauge);
        assertEq(uint256(rec.epochsReleased), 0, "quarter not counted");
        assertEq(rec.released, 0, "nothing released");
        assertEq(rec.remaining, FEE, "escrow intact");
        assertEq(lister.totalEscrow(), FEE, "reserve intact");
        assertEq(token.balanceOf(address(lister)), FEE, "no partial debit");
        assertEq(votiumMock.incentiveCount(), 0, "first-side deposit also rolled back");
        assertEq(token.balanceOf(address(votiumMock)), 0, "no votium custody");
        assertEq(crmMock.campaignCount(), crmsBefore + 1, "no campaign");

        // Restore sane pricing: the same checkpoint now settles normally.
        vm.prank(adapterManager);
        vmAdapter.setGasSettings(CREATION_GAS, BLACKLIST_GAS, GWEI);
        lister.checkpoint(gauge);
        assertEq(uint256(lister.getListing(gauge).epochsReleased), 1, "settles after ops fix");
    }

    function test_Adapter_VoteMarketDuplicateGuardAndNonceReceipts() public {
        VmKit memory kit = freshVmKit(address(crmMock));
        address g = actor("gaugeA");
        uint256 e1 = T0 + WEEK;
        uint256 e2 = T0 + 2 * WEEK;

        bytes32 r1 = kit.caller.deposit(IIncentivePlatform(address(kit.adapter_)), g, e1, HALF);
        assertTrue(r1 != bytes32(0), "nonzero");
        uint256 callerBefore = token.balanceOf(address(kit.caller));

        // Same (gauge, scheduledEpoch) is refused BEFORE any second pull.
        vm.expectRevert(VoteMarketAdapter.DuplicateDeposit.selector);
        kit.caller.deposit(IIncentivePlatform(address(kit.adapter_)), g, e1, HALF);
        vm.expectRevert(VoteMarketAdapter.DuplicateDeposit.selector);
        kit.caller.deposit(IIncentivePlatform(address(kit.adapter_)), g, e1, HALF + 100);
        assertEq(token.balanceOf(address(kit.caller)), callerBefore, "duplicate guard pulls nothing");

        // New epochs get distinct receipts (nonce-keyed): a repeat of an
        // already-funded (gauge, scheduledEpoch) key is refused BEFORE any
        // second pull (the cell above), so recorded tuples are pairwise
        // distinct by construction and the local ordinal simply separates the
        // receipt domain across the adapter's own log (S09 — unlike Votium's
        // tuple-determinism).
        bytes32 r2 = kit.caller.deposit(IIncentivePlatform(address(kit.adapter_)), g, e2, HALF);
        bytes32 r3 = kit.caller.deposit(IIncentivePlatform(address(kit.adapter_)), g, e2 + WEEK, HALF);
        bytes32 r4 = kit.caller.deposit(IIncentivePlatform(address(kit.adapter_)), g, e2 + 2 * WEEK, HALF);
        assertTrue(r2 != r1 && r3 != r2 && r4 != r3 && r4 != bytes32(0), "nonce-distinct receipts");
        assertEq(kit.adapter_.depositCount(), 4, "four records");
        (,, bytes32 stored) = kit.adapter_.getDeposit(g, e1);
        assertEq(stored, r1, "keyed record survives");

        // An absent key returns (0,0,0), never array element zero (item 2's
        // index+1 encoding absorbed here from the audit work order).
        (uint256 amt0, uint256 exec0, bytes32 rec0) = kit.adapter_.getDeposit(actor("neverDeposited"), e1);
        assertEq(amt0 + exec0 + uint256(rec0), 0, "absent key returns zeros");
    }

    function test_Adapter_VoteMarketConfigParamsFidelityAndMockGuards() public {
        // Adapter priced at 2 gwei against a CRM mock priced at 2 gwei.
        address[] memory platforms = new address[](1);
        platforms[0] = VM_L2;
        MockCampaignRemoteManager crm2 = new MockCampaignRemoteManager(2 * GWEI, platforms);
        VmKit memory kit = freshVmKit(address(crm2));
        VoteMarketAdapter adapterX = kit.adapter_;
        ListerCaller caller = kit.caller;

        vm.prank(stranger);
        vm.expectRevert(AdapterOwnable.NotOwner.selector);
        adapterX.setGasSettings(1, 1, 1);
        vm.prank(adapterManager);
        vm.expectRevert(VoteMarketAdapter.BadGasSettings.selector);
        adapterX.setGasSettings(0, BLACKLIST_GAS, GWEI);
        vm.prank(adapterManager);
        vm.expectRevert(VoteMarketAdapter.BadGasSettings.selector);
        adapterX.setGasSettings(CREATION_GAS, BLACKLIST_GAS, 0);
        vm.prank(stranger);
        vm.expectRevert(AdapterOwnable.NotOwner.selector);
        adapterX.setMaxRewardPerVote(123);
        address[] memory badZero = new address[](1);
        badZero[0] = address(0);
        vm.prank(adapterManager);
        vm.expectRevert(VoteMarketAdapter.BadExclusion.selector);
        adapterX.setExcluded(badZero);
        vm.prank(adapterManager);
        vm.expectRevert(VoteMarketAdapter.BadRewardCap.selector);
        adapterX.setMaxRewardPerVote(0);

        vm.prank(adapterManager);
        adapterX.setGasSettings(1_500_000, 40_000, 2 * GWEI);
        vm.prank(adapterManager);
        adapterX.setMaxRewardPerVote(123);
        address[] memory excl = new address[](2);
        excl[0] = actor("voterX");
        excl[1] = actor("voterY");
        vm.prank(adapterManager);
        adapterX.setExcluded(excl);

        uint256 required = (1_500_000 + 40_000 * 2) * (2 * GWEI);
        assertEq(adapterX.ethDeficit(HALF), 0, "float covers the priced message");
        address g = actor("gaugeA");
        uint256 e = T0 + WEEK;
        caller.deposit(IIncentivePlatform(address(adapterX)), g, e, HALF);

        MockCampaignRemoteManager.Campaign memory c = crm2.campaignAt(0);
        assertEq(c.additionalGasLimit, 1_580_000, "gas = base + per-excluded * count");
        assertEq(c.value, required, "value = additionalGasLimit * gasPrice");
        assertEq(address(crm2).balance, required, "CRM received exactly the gas value");
        assertEq(crm2.ethPaid(), required, "CRM paid-gas ledger tracks the value");
        assertEq(c.params.maxRewardPerVote, 123, "configured cap reaches params");
        assertEq(c.params.addresses.length, 2, "exclusions reach params.addresses");
        assertEq(c.params.addresses[0], actor("voterX"), "exclusion order 0");
        assertEq(c.params.addresses[1], actor("voterY"), "exclusion order 1");
        assertEq(uint256(c.params.numberOfPeriods), 2, "periods stay 2");
        assertEq(c.params.manager, address(adapterX), "manager is the adapter");
        assertEq(c.destinationChainId, 42161, "destination stays 42161");

        // Mispricing is caught by the manager-side check: an adapter priced
        // 2 gwei against a 1-gwei CRM mock reverts on value before anything
        // moves.
        VmKit memory mismatched = freshVmKit(address(crmMock));
        vm.prank(adapterManager);
        mismatched.adapter_.setGasSettings(CREATION_GAS, BLACKLIST_GAS, 2 * GWEI);
        vm.expectRevert(MockCampaignRemoteManager.BadGasValue.selector);
        mismatched.caller.deposit(IIncentivePlatform(address(mismatched.adapter_)), g, T0 + 2 * WEEK, HALF);
        assertEq(token.balanceOf(address(mismatched.caller)), 100 * HALF, "mispriced deposit fully rolled back");
    }

    function test_Adapter_VoteMarketCampaignRequiresSourceChain() public {
        // review2 finding 2: the verified CampaignRemoteManager rejects any
        // non-mainnet source chain (C1:1749 `InvalidChainId`) BEFORE its
        // other guards. The suite's successful campaign fixtures run at
        // chainId 1 (setUp); this test flips the chain away and back.
        VmKit memory kit = freshVmKit(address(crmMock));
        address g = actor("gaugeA");
        uint256 e = T0 + WEEK;
        uint256 campaignsBefore = crmMock.campaignCount();
        uint256 callerBefore = token.balanceOf(address(kit.caller));
        uint256 crmCustodyBefore = token.balanceOf(address(crmMock));
        uint256 floatBefore = address(kit.adapter_).balance;

        vm.chainId(31337);
        assertEq(crmMock.SOURCE_CHAIN_ID(), 1, "fixture pins the real source chain");
        vm.expectRevert(MockCampaignRemoteManager.InvalidChainId.selector);
        kit.caller.deposit(IIncentivePlatform(address(kit.adapter_)), g, e, HALF);
        assertEq(crmMock.campaignCount(), campaignsBefore, "no campaign record off L1");
        assertEq(token.balanceOf(address(kit.caller)), callerBefore, "funded deposit fully rolled back");
        assertEq(token.balanceOf(address(crmMock)), crmCustodyBefore, "no CRM custody off L1");
        assertEq(address(kit.adapter_).balance, floatBefore, "no float spent off L1");
        assertEq(token.allowance(address(kit.caller), address(kit.adapter_)), 0, "approval rolled back");

        // Positive control: the same funded deposit at chainId 1 succeeds and
        // binds params to the real source chain.
        vm.chainId(1);
        bytes32 r = kit.caller.deposit(IIncentivePlatform(address(kit.adapter_)), g, e, HALF);
        assertTrue(r != bytes32(0), "chain-1 control funds");
        assertEq(crmMock.campaignCount(), campaignsBefore + 1, "campaign recorded at L1");
        MockCampaignRemoteManager.Campaign memory c = crmMock.campaignAt(campaignsBefore);
        assertEq(c.params.chainId, 1, "params bound to source chain 1");
        assertEq(token.balanceOf(address(crmMock)), crmCustodyBefore + HALF, "gross funding custody at L1");
    }

    // ---------------------------------------------------------------
    // surface and ownership
    // ---------------------------------------------------------------

    function test_Adapter_NoDrainFullPayloadsAsActualOwner() public {
        // review2 finding 5: the no-drain evidence must not hide behind
        // wrong-caller authorization or selector-only decoding failures.
        // Execute COMPLETE, correctly ABI-encoded forbidden payloads — with
        // the real YB signatures — as each adapter's ACTUAL owner
        // (adapterManager), against spendable token and ETH balances and
        // valid recipients/amounts/dynamic data. The synthetic CRM mock is
        // not a deployed product custody contract and is not targeted.
        token.mint(address(votiumAdapter), 5 * HALF);
        token.mint(address(vmAdapter), 5 * HALF);
        vmx.deal(address(votiumAdapter), 1 ether);
        uint256 vtTok = token.balanceOf(address(votiumAdapter));
        uint256 vmTok = token.balanceOf(address(vmAdapter));
        uint256 vtEth = address(votiumAdapter).balance;
        uint256 vmEth = address(vmAdapter).balance;
        uint256 strangerTok = token.balanceOf(stranger);
        uint256 strangerEth = stranger.balance;
        assertTrue(vtTok > 0 && vtEth > 0, "probe balances are spendable");

        bytes[] memory transferInner = new bytes[](1);
        transferInner[0] = abi.encodeWithSignature("transfer(address,uint256)", address(stranger), uint256(HALF));
        bytes memory tokenDrainCall =
            abi.encodeWithSignature("transfer(address,uint256)", address(stranger), uint256(HALF));
        bytes memory emptyData = new bytes(0);

        bytes[] memory payloads = new bytes[](11);
        // The actual YB capabilities, fully encoded (INTEL H1/H2).
        payloads[0] =
            abi.encodeWithSignature("execute(address,uint256,bytes)", address(token), uint256(0), tokenDrainCall);
        payloads[1] =
            abi.encodeWithSignature("execute(address,uint256,bytes)", address(stranger), uint256(0.5 ether), emptyData);
        payloads[2] = abi.encodeWithSignature("withdrawEther(uint256,address)", uint256(0.5 ether), address(stranger));
        payloads[3] = abi.encodeWithSignature("withdrawEther(uint256,address)", uint256(0), address(stranger));
        payloads[4] = abi.encodeWithSignature("execute(address,bytes)", address(token), tokenDrainCall);
        payloads[5] = abi.encodeWithSignature("withdrawEther()");
        // Token-rescue shapes with the REAL token address, valid recipient and
        // spendable amount.
        payloads[6] = abi.encodeWithSignature("sweep(address)", address(token));
        payloads[7] = abi.encodeWithSignature("refund(address)", address(stranger));
        payloads[8] = abi.encodeWithSignature("recoverERC20(address,uint256)", address(token), uint256(HALF));
        payloads[9] = abi.encodeWithSignature("withdraw(uint256)", uint256(HALF));
        payloads[10] = abi.encodeWithSignature("multicall(bytes[])", transferInner);

        address[2] memory targets = [address(votiumAdapter), address(vmAdapter)];
        bool ok;
        for (uint256 t = 0; t < targets.length; ++t) {
            for (uint256 p = 0; p < payloads.length; ++p) {
                vm.prank(adapterManager);
                (ok,) = targets[t].call(payloads[p]);
                assertFalse(ok, "full-ABI forbidden payload must fail as the actual adapter owner");
            }
        }
        // Nothing drained: every spendable balance stayed put, the intended
        // recipient gained nothing.
        assertEq(token.balanceOf(address(votiumAdapter)), vtTok, "votium token custody frozen");
        assertEq(token.balanceOf(address(vmAdapter)), vmTok, "vm token custody frozen");
        assertEq(address(votiumAdapter).balance, vtEth, "votium eth frozen");
        assertEq(address(vmAdapter).balance, vmEth, "vm eth float frozen");
        assertEq(token.balanceOf(stranger), strangerTok, "intended recipient gained no tokens");
        assertEq(stranger.balance, strangerEth, "intended recipient gained no ETH");
    }

    function test_Adapter_CompiledAbiSurfaceMatchesAllowlist() public {
        // review2 finding 5 / review3 finding 1 / review4 finding 1, with
        // the S16 attestation boundary stated precisely: this body compares
        // the FRESH artifact's complete methodIdentifiers map — parsed from
        // the artifact JSON, independent of selector-pattern recognition —
        // against the intended allowlist as a SET in both directions, and
        // probes ONE junk selector to show no fallback arm executes. It is
        // a compiled-surface check: it does NOT compare deployed runtime
        // bytes or walk the dispatcher. The exact runtime/immutables byte
        // comparison is a DISTINCT release gate (recorded with the
        // candidate's release evidence package), and no extra callable
        // surface may be claimed from this test alone.
        string[] memory votiumAllowed = new string[](16);
        votiumAllowed[0] = "crvUSD()";
        votiumAllowed[1] = "votium()";
        votiumAllowed[2] = "owner()";
        votiumAllowed[3] = "pendingOwner()";
        votiumAllowed[4] = "maxPerVote()";
        votiumAllowed[5] = "MAX_EXCLUDED()";
        votiumAllowed[6] = "MAX_MAX_PER_VOTE()";
        votiumAllowed[7] = "rewardToken()";
        votiumAllowed[8] = "excluded()";
        votiumAllowed[9] = "setLister(address)";
        votiumAllowed[10] = "deposit(address,uint256,uint256)";
        votiumAllowed[11] = "setMaxPerVote(uint256)";
        votiumAllowed[12] = "setExcluded(address[])";
        votiumAllowed[13] = "transferOwnership(address)";
        votiumAllowed[14] = "acceptOwnership()";
        votiumAllowed[15] = "lister()";
        _assertCompiledAbiAllowlist(address(votiumAdapter), "VotiumAdapter.sol:VotiumAdapter", votiumAllowed);

        string[] memory vmAllowed = new string[](26);
        vmAllowed[0] = "crvUSD()";
        vmAllowed[1] = "campaignRemoteManager()";
        vmAllowed[2] = "votemarket()";
        vmAllowed[3] = "owner()";
        vmAllowed[4] = "pendingOwner()";
        vmAllowed[5] = "maxRewardPerVote()";
        vmAllowed[6] = "campaignCreationGas()";
        vmAllowed[7] = "blacklistedAddressGas()";
        vmAllowed[8] = "gasPrice()";
        vmAllowed[9] = "DESTINATION_CHAIN_ID()";
        vmAllowed[10] = "NUMBER_OF_PERIODS()";
        vmAllowed[11] = "MAX_EXCLUDED()";
        vmAllowed[12] = "rewardToken()";
        vmAllowed[13] = "excluded()";
        vmAllowed[14] = "setLister(address)";
        vmAllowed[15] = "deposit(address,uint256,uint256)";
        vmAllowed[16] = "ethDeficit(uint256)";
        vmAllowed[17] = "getDeposit(address,uint256)";
        vmAllowed[18] = "depositCount()";
        vmAllowed[19] = "depositAt(uint256)";
        vmAllowed[20] = "setMaxRewardPerVote(uint256)";
        vmAllowed[21] = "setExcluded(address[])";
        vmAllowed[22] = "setGasSettings(uint256,uint256,uint256)";
        vmAllowed[23] = "transferOwnership(address)";
        vmAllowed[24] = "acceptOwnership()";
        vmAllowed[25] = "lister()";
        _assertCompiledAbiAllowlist(address(vmAdapter), "VoteMarketAdapter.sol:VoteMarketAdapter", vmAllowed);
    }

    /// @dev Compiled-ABI allowlist comparison (review2 finding 5 → review3
    /// finding 1 → review4 finding 1; S16 wording). The AUTHORITATIVE
    /// function inventory here is the fresh compiled artifact's complete
    /// `methodIdentifiers` map, parsed directly from the artifact JSON this
    /// very build writes under out/ (vm.readFile + JSON cheatcodes). The
    /// complete signature-KEY set and count is compared against the intended
    /// allowlist in BOTH directions: every compiled signature must be
    /// allowlisted and every allowlisted signature must be present. JSON
    /// object keys are unique, so a compiled signature string cannot repeat.
    /// A newly added function — whatever selector width or opcode shape its
    /// dispatcher arm takes — is still an extra artifact signature and fails
    /// the comparison. The single trailing calldata probe only shows that a
    /// junk-selector call does not execute a payable-less fallback; full
    /// dispatcher/runtime-byte equality remains the separate release gate.
    function _assertCompiledAbiAllowlist(address target, string memory artifactId, string[] memory signatures)
        internal
    {
        string memory json = vm.readFile(_artifactJsonPath(artifactId));
        assertTrue(vm.keyExistsJson(json, ".methodIdentifiers"), "artifact has a methodIdentifiers map");
        string[] memory sigs = vm.parseJsonKeys(json, ".methodIdentifiers");
        assertEq(sigs.length, signatures.length, "compiled signature count matches the allowlist");
        for (uint256 i = 0; i < sigs.length; ++i) {
            bool allowedSig;
            for (uint256 j = 0; j < signatures.length; ++j) {
                if (keccak256(bytes(sigs[i])) == keccak256(bytes(signatures[j]))) {
                    allowedSig = true;
                    break;
                }
            }
            assertTrue(allowedSig, "compiled artifact signature outside the allowlist");
        }
        for (uint256 j = 0; j < signatures.length; ++j) {
            bool present;
            for (uint256 i = 0; i < sigs.length; ++i) {
                if (keccak256(bytes(sigs[i])) == keccak256(bytes(signatures[j]))) {
                    present = true;
                    break;
                }
            }
            assertTrue(present, "allowlisted signature missing from the artifact");
        }
        // No fallback: a junk selector with nonzero-length calldata and no
        // value must hit the invalid jump (a fallback would execute).
        (bool ok,) = target.call(hex"deadbeef01");
        assertFalse(ok, "adapters must have no fallback");
    }

    /// @dev `out/<File.sol>/<Contract>.json` — where this build writes the
    /// artifact for an artifactId of the form "<File.sol>:<Contract>".
    function _artifactJsonPath(string memory artifactId) internal pure returns (string memory) {
        bytes memory id = bytes(artifactId);
        uint256 colon = id.length;
        for (uint256 i = 0; i < id.length; ++i) {
            if (id[i] == ":") {
                colon = i;
                break;
            }
        }
        assertTrue(colon > 0 && colon + 1 < id.length, "artifactId must be <file.sol>:<contract>");
        return string.concat(
            "out/", _substring(artifactId, 0, colon), "/", _substring(artifactId, colon + 1, id.length), ".json"
        );
    }

    /// @dev id[start:end] of an ASCII string.
    function _substring(string memory s, uint256 start, uint256 end) internal pure returns (string memory) {
        bytes memory b = bytes(s);
        bytes memory r = new bytes(end - start);
        for (uint256 i = start; i < end; ++i) {
            r[i - start] = b[i];
        }
        return string(r);
    }

    function test_Adapter_VoteMarketNonListerRejection() public {
        // review2 finding 5: the Votium adapter has an explicit NotLister
        // regression; the VoteMarket adapter needs its own, with a
        // bound-lister success control and no-record/no-movement proof.
        VmKit memory kit = freshVmKit(address(crmMock));
        address g = actor("gaugeA");
        uint256 e = T0 + WEEK;
        uint256 campaignsBefore = crmMock.campaignCount();
        uint256 depositsBefore = kit.adapter_.depositCount();
        uint256 callerBefore = token.balanceOf(address(kit.caller));
        uint256 adapterTokBefore = token.balanceOf(address(kit.adapter_));
        uint256 floatBefore = address(kit.adapter_).balance;

        vm.prank(stranger);
        vm.expectRevert(VoteMarketAdapter.NotLister.selector);
        kit.adapter_.deposit(g, e, HALF);
        assertEq(crmMock.campaignCount(), campaignsBefore, "rejection creates no campaign record");
        assertEq(kit.adapter_.depositCount(), depositsBefore, "rejection writes no deposit record");
        (,, bytes32 stored) = kit.adapter_.getDeposit(g, e);
        assertEq(uint256(stored), 0, "rejection leaves no keyed receipt");
        assertEq(token.balanceOf(address(kit.caller)), callerBefore, "no token movement on rejection");
        assertEq(token.balanceOf(address(kit.adapter_)), adapterTokBefore, "no token custody on rejection");
        assertEq(address(kit.adapter_).balance, floatBefore, "no ETH movement on rejection");
        assertEq(token.allowance(address(kit.caller), address(kit.adapter_)), 0, "no approval residue");

        // auditfix001 §1: one-time binding is owner-gated; a second
        // authorized setLister is permanently refused (absorbed from the
        // retired fork constructor test). Called as the actual owner so
        // NotOwner cannot mask the ListerAlreadySet check.
        vm.prank(adapterManager);
        vm.expectRevert(VoteMarketAdapter.ListerAlreadySet.selector);
        kit.adapter_.setLister(actor("secondLister"));

        // V-H01 binding capture on a fresh unbound production adapter: an
        // outsider targets an existing deployed contract; the exact revert is
        // NotOwner, the getter stays zero and no ListerSet is emitted.
        VoteMarketAdapter fresh = new VoteMarketAdapter(address(token), adapterManager, address(crmMock), VM_L2);
        vmx.deal(address(fresh), 1 ether);
        vm.recordLogs();
        vm.prank(stranger);
        vm.expectRevert(AdapterOwnable.NotOwner.selector);
        fresh.setLister(address(crmMock));
        Vm.Log[] memory bindLogs = vm.getRecordedLogs();
        assertFalse(
            hasEventFrom(bindLogs, address(fresh), keccak256("ListerSet(address)")), "no ListerSet on outsider binding"
        );
        assertEq(fresh.lister(), address(0), "outsider binding left adapter unbound");
        vm.prank(adapterManager);
        vm.expectRevert(VoteMarketAdapter.BadLister.selector);
        fresh.setLister(stranger);
        vm.prank(adapterManager);
        vm.expectRevert(VoteMarketAdapter.BadLister.selector);
        fresh.setLister(address(0));
        vm.expectEmit(true, false, false, true);
        emit ListerSet(address(kit.caller));
        vm.prank(adapterManager);
        fresh.setLister(address(kit.caller));
        assertEq(fresh.lister(), address(kit.caller), "owner binding set the getter");
        vm.prank(adapterManager);
        vm.expectRevert(VoteMarketAdapter.ListerAlreadySet.selector);
        fresh.setLister(actor("secondLister"));

        // Bound-lister success control.
        bytes32 r = kit.caller.deposit(IIncentivePlatform(address(kit.adapter_)), g, e, HALF);
        assertTrue(r != bytes32(0), "bound lister funds");
        assertEq(crmMock.campaignCount(), campaignsBefore + 1, "control records the campaign");
        assertEq(kit.adapter_.depositCount(), depositsBefore + 1, "control writes the deposit record");
        assertEq(token.balanceOf(address(kit.caller)), callerBefore - HALF, "control pulls exactly the amount");
        assertEq(floatBefore - address(kit.adapter_).balance, REQUIRED_ETH, "control spends exactly the bridge value");
    }

    function test_Adapter_VoteMarketReceiveIsOneWayFloat() public {
        // Ops top-up path: anyone can send; nothing can take back.
        EthSink sink = new EthSink();
        vmx.deal(address(this), 1 ether);
        vmx.deal(stranger, 1 ether);
        uint256 before = address(vmAdapter).balance;
        sink.fund{value: 0.5 ether}(address(vmAdapter));
        assertEq(address(vmAdapter).balance, before + 0.5 ether, "receive() accepts float");
        bool ok;
        vm.prank(stranger);
        (ok,) = address(vmAdapter).call{value: 0.25 ether}("");
        assertTrue(ok, "plain sends work");
        assertEq(address(vmAdapter).balance, before + 0.75 ether, "anyone can top up");
        vm.prank(daoOwner);
        (ok,) = address(vmAdapter).call(abi.encodeWithSignature("withdrawAll()"));
        assertFalse(ok, "no withdrawal surface even for the core owner");
        assertEq(address(vmAdapter).balance, before + 0.75 ether, "float still intact after probe");
    }

    function test_Adapter_OwnershipTransferTwoStep() public {
        VotiumKit memory kit = freshVotiumKit(address(votiumMock));
        vm.prank(stranger);
        vm.expectRevert(AdapterOwnable.NotOwner.selector);
        kit.adapter_.transferOwnership(stranger);
        vm.prank(adapterManager);
        vm.expectRevert();
        kit.adapter_.transferOwnership(address(0));

        address newMgr = actor("newManager");
        vm.prank(adapterManager);
        kit.adapter_.transferOwnership(newMgr);
        assertEq(kit.adapter_.owner(), adapterManager, "proposal does not move authority");

        // auditfix001 §1 (CX-BIND-TEST ordering): a PENDING owner cannot
        // bind a still-unbound adapter. The proposal is made ON THE TESTED
        // INSTANCE first, so the rejection below is the actual pending-owner
        // state, not merely an unrelated address hitting NotOwner before
        // this instance ever had a proposal.
        VotiumAdapter freshVotium = new VotiumAdapter(address(token), adapterManager, address(votiumMock));
        vm.prank(adapterManager);
        freshVotium.transferOwnership(newMgr);
        assertEq(freshVotium.owner(), adapterManager, "pending proposal does not move authority");
        assertEq(freshVotium.pendingOwner(), newMgr, "tested instance is in pending state");
        vm.prank(newMgr);
        vm.expectRevert(AdapterOwnable.NotOwner.selector);
        freshVotium.setLister(address(kit.caller));
        // Rejection of an unrelated outsider on the same instance stays.
        vm.prank(stranger);
        vm.expectRevert(AdapterOwnable.NotOwner.selector);
        freshVotium.setLister(address(kit.caller));
        // Acceptance happens on the SAME instance that carried the pending
        // state (below, before any binding by the new owner).

        // Before acceptance the OLD owner still cannot rebind a successful
        // binding, and the pending owner cannot accept for a stranger.
        vm.prank(adapterManager);
        vm.expectRevert(VotiumAdapter.ListerAlreadySet.selector);
        kit.adapter_.setLister(actor("secondLister"));
        vm.prank(stranger);
        vm.expectRevert();
        kit.adapter_.acceptOwnership();
        vm.prank(newMgr);
        kit.adapter_.acceptOwnership();
        assertEq(kit.adapter_.owner(), newMgr, "accepted");

        // After acceptance NEITHER owner can change a previously successful
        // binding: the new owner hits ListerAlreadySet, the old owner
        // NotOwner.
        vm.prank(newMgr);
        vm.expectRevert(VotiumAdapter.ListerAlreadySet.selector);
        kit.adapter_.setLister(actor("secondLister"));
        vm.prank(adapterManager);
        vm.expectRevert(AdapterOwnable.NotOwner.selector);
        kit.adapter_.setLister(actor("secondLister"));

        vm.prank(adapterManager);
        vm.expectRevert(AdapterOwnable.NotOwner.selector);
        kit.adapter_.setMaxPerVote(1);
        vm.prank(newMgr);
        kit.adapter_.setMaxPerVote(1);
        assertEq(kit.adapter_.maxPerVote(), 1, "new manager configures");

        // After acceptance only the NEW owner can bind a still-unbound
        // adapter: the fresh adapter is already in the pending state above;
        // the pending owner now accepts ON THAT SAME INSTANCE, the old
        // owner is then refused and the new owner binds exactly once.
        vm.prank(newMgr);
        freshVotium.acceptOwnership();
        assertEq(freshVotium.owner(), newMgr, "pending instance acceptance moved authority");
        assertEq(freshVotium.lister(), address(0), "acceptance alone bound nothing");
        vm.prank(adapterManager);
        vm.expectRevert(AdapterOwnable.NotOwner.selector);
        freshVotium.setLister(address(kit.caller));
        vm.expectEmit(true, false, false, true);
        emit ListerSet(address(kit.caller));
        vm.prank(newMgr);
        freshVotium.setLister(address(kit.caller));
        assertEq(freshVotium.lister(), address(kit.caller), "new owner bound the votium adapter");
        // Separate bound-instance no-rebind control on the fresh adapter:
        // after a successful bind neither the new nor the old owner can
        // replace it.
        vm.prank(newMgr);
        vm.expectRevert(VotiumAdapter.ListerAlreadySet.selector);
        freshVotium.setLister(actor("secondLister"));

        // Both adapter classes share the same two-step binding law.
        VoteMarketAdapter va = new VoteMarketAdapter(address(token), adapterManager, address(crmMock), VM_L2);
        vm.prank(adapterManager);
        va.transferOwnership(newMgr);
        vm.prank(newMgr);
        vm.expectRevert(AdapterOwnable.NotOwner.selector);
        va.setLister(address(kit.caller));
        vm.prank(newMgr);
        va.acceptOwnership();
        vm.prank(adapterManager);
        vm.expectRevert(AdapterOwnable.NotOwner.selector);
        va.setLister(address(kit.caller));
        vm.prank(newMgr);
        va.setLister(address(kit.caller));
        assertEq(va.lister(), address(kit.caller), "new owner bound the votemarket adapter");
        // Neither owner can rebind: old owner is no longer owner, new owner
        // hits the one-time-binding refusal.
        vm.prank(adapterManager);
        vm.expectRevert(AdapterOwnable.NotOwner.selector);
        va.setLister(actor("secondLister"));
        vm.prank(newMgr);
        vm.expectRevert(VoteMarketAdapter.ListerAlreadySet.selector);
        va.setLister(actor("secondLister"));
        vm.prank(adapterManager);
        vm.expectRevert(AdapterOwnable.NotOwner.selector);
        va.setGasSettings(1, 1, 1);
        vm.prank(newMgr);
        va.setGasSettings(2, 2, 2);
    }

    // ---------------------------------------------------------------
    // integration through the core lister
    // ---------------------------------------------------------------

    function test_Adapter_EndToEndFourQuartersSettleViaCheckpoint() public {
        (address pool, address gauge,) = deployAuthenticatedPool(0, 0);
        listPaid(pool, gauge, 0, 0);
        uint256 floatBefore = address(vmAdapter).balance;

        for (uint256 q = 1; q <= 4; ++q) {
            vm.warp(T0 + q * WEEK);
            votiumMock.setActiveRound(q); // rounds advance like the live venue
            lister.checkpoint(gauge);
        }

        // Core terminal state.
        CurveGaugeLister.Listing memory rec = lister.getListing(gauge);
        assertEq(uint256(rec.status), uint256(CurveGaugeLister.Status.Exhausted), "exhausted");
        assertEq(uint256(rec.epochsReleased), 4, "four funded quarters");
        assertEq(rec.released, FEE, "gross released");
        assertEq(rec.remaining, 0, "nothing left");
        assertEq(rec.confiscated, 0, "no confiscation");
        assertEq(lister.totalEscrow(), 0, "reserve fully released");
        assertEq(token.balanceOf(address(lister)), 0, "escrow drained exactly to the venues");

        // Votium side: four single-gauge quarterly deposits, real custody
        // (absorbing the retired one-quarter fixture's default-field and
        // zero-balance/allowance checks).
        assertEq(votiumMock.incentiveCount(), 4, "four incentives");
        assertEq(token.balanceOf(address(votiumMock)), FEE / 2, "votium custody = 50% of fee");
        for (uint256 q = 1; q <= 4; ++q) {
            assertEq(votiumMock.deposited(q, gauge, address(token)), HALF, "per-round exact funding");
            MockVotiumV2.Incentive memory inc = votiumMock.incentiveAt(q - 1);
            assertEq(inc.round, q, "round read at deposit time");
            assertEq(inc.amount, HALF, "quarter gross half exact");
            assertEq(inc.token, address(token), "incentive token is crvUSD");
            assertEq(inc.gauge, gauge, "per-gauge binding");
            assertEq(inc.maxPerVote, 0, "default unbounded cap (YB mirror)");
            assertEq(inc.excluded.length, 0, "default empty exclusions");
            assertEq(inc.depositor, address(votiumAdapter), "depositor adapter");
        }
        assertEq(token.balanceOf(address(votiumAdapter)), 0, "adapter never retains tokens");
        assertEq(token.allowance(address(lister), address(votiumAdapter)), 0, "lister approval cleared");
        assertEq(token.allowance(address(votiumAdapter), address(votiumMock)), 0, "adapter approval cleared");

        // VoteMarket side: four recorded campaigns + adapter deposit log.
        assertEq(crmMock.campaignCount(), 4, "four campaigns");
        assertEq(token.balanceOf(address(crmMock)), FEE / 2, "CRM custody = 50% of fee");
        assertEq(crmMock.ethPaid(), 4 * REQUIRED_ETH, "four bridge messages paid");
        assertEq(floatBefore - address(vmAdapter).balance, 4 * REQUIRED_ETH, "float spent exactly");
        assertEq(vmAdapter.depositCount(), 4, "four deposit records");
        for (uint256 q = 1; q <= 4; ++q) {
            MockCampaignRemoteManager.Campaign memory c = crmMock.campaignAt(q - 1);
            assertEq(c.params.gauge, gauge, "same gauge each quarter");
            assertEq(c.params.totalRewardAmount, HALF, "exact amount at platform side");
            assertEq(c.params.manager, address(vmAdapter), "campaign manager is the adapter");
            (uint256 amount, uint256 executionEpoch, bytes32 receipt) = vmAdapter.getDeposit(gauge, T0 + q * WEEK);
            assertEq(amount, HALF, "recorded amount");
            assertEq(executionEpoch, T0 + q * WEEK, "recorded execution epoch");
            assertTrue(receipt != bytes32(0), "recorded receipt nonzero");
            VoteMarketAdapter.DepositRecord memory d = vmAdapter.depositAt(q - 1);
            assertEq(d.receipt, receipt, "chronological log matches keyed record");
        }

        // Lister settlement-event fidelity: the VM-side PlatformDeposit data
        // must carry the adapter's own receipt (recorded with log capture on a
        // separate fresh gauge so counts here stay exact).
        (address pool2, address gauge2,) = deployAuthenticatedPool(2, 2);
        vm.warp(T0 + 4 * WEEK);
        listPaid(pool2, gauge2, 2, 2);
        vm.warp(T0 + 5 * WEEK);
        votiumMock.setActiveRound(6);
        vm.recordLogs();
        lister.checkpoint(gauge2);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 vmEvents;
        uint256 votiumEvents;
        for (uint256 i = 0; i < logs.length; ++i) {
            if (
                logs[i].emitter != address(lister) || logs[i].topics.length < 4
                    || logs[i].topics[0] != PLATFORM_DEPOSIT_SIG
            ) {
                continue;
            }
            address platform = address(uint160(uint256(logs[i].topics[2])));
            (, uint256 amount, bytes32 receipt) = abi.decode(logs[i].data, (uint256, uint256, bytes32));
            assertEq(amount, HALF, "event amount exact");
            assertTrue(receipt != bytes32(0), "event receipt nonzero");
            if (platform == address(vmAdapter)) {
                (,, bytes32 recorded) = vmAdapter.getDeposit(gauge2, uint256(logs[i].topics[3]));
                assertEq(receipt, recorded, "event receipt is the adapter record");
                vmEvents += 1;
            } else if (platform == address(votiumAdapter)) {
                votiumEvents += 1;
            }
        }
        assertEq(vmEvents, 1, "one VM-side PlatformDeposit for the replayed quarter");
        assertEq(votiumEvents, 1, "one Votium-side PlatformDeposit for the replayed quarter");
    }

    function test_Adapter_ConfiscationMidCatchUpWithRealAdapters() public {
        (address pool, address gauge,) = deployAuthenticatedPool(0, 0);
        listPaid(pool, gauge, 0, 0);
        vm.warp(T0 + WEEK);
        lister.checkpoint(gauge);
        assertEq(votiumMock.incentiveCount(), 1, "quarter one funded");
        assertEq(crmMock.campaignCount(), 1, "quarter one campaign live");

        killGauge(gauge);
        vm.warp(T0 + 3 * WEEK);
        (uint256 releasedNow, uint256 confiscatedNow) = lister.checkpoint(gauge);
        assertEq(releasedNow, 0, "nothing released after kill");
        assertEq(confiscatedNow, FEE - QUARTER, "remainder confiscated");

        CurveGaugeLister.Listing memory rec = lister.getListing(gauge);
        assertEq(uint256(rec.status), uint256(CurveGaugeLister.Status.Confiscated), "confiscated");
        assertEq(rec.confiscated, FEE - QUARTER, "confiscation ledger");
        assertEq(token.balanceOf(address(fd)), FEE - QUARTER, "fee distributor custody");
        assertEq(lister.totalEscrow(), 0, "reserve cleared");

        // Adapters were never called again after the kill.
        assertEq(votiumMock.incentiveCount(), 1, "no post-kill votium deposits");
        assertEq(crmMock.campaignCount(), 1, "no post-kill campaigns");
        assertEq(token.balanceOf(address(votiumAdapter)) + token.balanceOf(address(vmAdapter)), 0, "no stranding");
        assertEq(address(vmAdapter).balance, 1 ether - REQUIRED_ETH, "float only spent on the funded quarter");
    }

    // ---------------------------------------------------------------
    // auditfix001 §2 — paid admission refuses unbound/misbound adapters
    // ---------------------------------------------------------------

    struct H01Core {
        CurveGaugeLister lister;
        MockListingController controller;
    }

    /// @dev Fresh core with a seated controller and a funded/approved payer,
    /// constructed against the given (possibly unbound) production adapters.
    /// Construction legitimately works before binding (auditfix001 §2).
    function _h01Core(VotiumAdapter va_, VoteMarketAdapter vma_, uint16 bps) internal returns (H01Core memory k) {
        k.controller = new MockListingController(controllerDao, int128(2));
        // Explicit chain 1 before ordinary deployment (V1ALIGN §2.1): some
        // callers run after the deliberate wrong-chain venue phase flipped it.
        vm.chainId(1);
        k.lister = new CurveGaugeLister(
            daoOwner,
            address(token),
            address(k.controller),
            address(fd),
            CurveGaugeLister.AdmissionConfig(address(registry), 8),
            CurveGaugeLister.PlatformConfig(address(va_), address(vma_), bps),
            address(new AlwaysTrueTrustedValidator())
        );
        vm.prank(controllerDao);
        k.controller.setLister(address(k.lister));
        // Owner unpause after binding (V1ALIGN §1.3): readiness remains an
        // independent backstop — the retained PlatformNotReady/expectations
        // below are what gate the paid call, exactly as originally asserted.
        vm.prank(daoOwner);
        k.lister.setPaused(false);
        vm.startPrank(payer);
        token.approve(address(k.lister), type(uint256).max);
        vm.stopPrank();
    }

    struct H01Snap {
        uint256 payerBal;
        uint256 payerAllow;
        uint256 coreBal;
        uint256 escrow;
        uint256 adds;
        uint256 incentives;
        uint256 campaigns;
        uint256 votiumVenueBal;
        uint256 crmBal;
        uint256 vmEth;
    }

    /// @dev Paid admission against the not-ready endpoint `badPlatform` must
    /// revert exactly PlatformNotReady(badPlatform) with the COMPLETE
    /// pre-state preserved: payer balance/allowance, core custody,
    /// totalEscrow, an all-zero Unlisted record, controller membership and
    /// addCalls, venue receipts/balances, adapter ETH and all relevant
    /// allowances. No fee, listing or upstream registration may persist.
    function _h01ExpectAdmissionRefused(
        H01Core memory k,
        VotiumAdapter va_,
        VoteMarketAdapter vma_,
        address badPlatform
    ) internal {
        (address pool, address gauge,) = deployAuthenticatedPool(0, 0);
        H01Snap memory pre = _h01Snap(k, vma_);

        vm.prank(payer);
        vm.expectRevert(abi.encodeWithSelector(CurveGaugeLister.PlatformNotReady.selector, badPlatform));
        k.lister.listGauge(pool, gauge, 0, 0);

        _h01AssertUnchanged(k, va_, vma_, pre);
        CurveGaugeLister.Listing memory rec = k.lister.getListing(gauge);
        assertEq(uint8(rec.status), uint8(CurveGaugeLister.Status.Unlisted), "H01: no record");
        assertEq(rec.deposited + rec.remaining + rec.released + rec.confiscated, 0, "H01: zero financials");
        assertEq(rec.payer, address(0), "H01: zero payer field");
        vm.expectRevert(MockListingController.GaugeNotAdded.selector);
        k.controller.gauge_types(gauge);
    }

    function _h01Snap(H01Core memory k, VoteMarketAdapter vma_) internal view returns (H01Snap memory s) {
        s.payerBal = token.balanceOf(payer);
        s.payerAllow = token.allowance(payer, address(k.lister));
        s.coreBal = token.balanceOf(address(k.lister));
        s.escrow = k.lister.totalEscrow();
        s.adds = k.controller.addCalls();
        s.incentives = votiumMock.incentiveCount();
        s.campaigns = crmMock.campaignCount();
        s.votiumVenueBal = token.balanceOf(address(votiumMock));
        s.crmBal = token.balanceOf(address(crmMock));
        s.vmEth = address(vma_).balance;
    }

    function _h01AssertUnchanged(H01Core memory k, VotiumAdapter va_, VoteMarketAdapter vma_, H01Snap memory s)
        internal
        view
    {
        assertEq(token.balanceOf(payer), s.payerBal, "H01: no attacker/payer token loss");
        assertEq(token.allowance(payer, address(k.lister)), s.payerAllow, "H01: no allowance consumed");
        assertEq(token.balanceOf(address(k.lister)), s.coreBal, "H01: no core custody");
        assertEq(k.lister.totalEscrow(), s.escrow, "H01: no liability");
        assertEq(k.controller.addCalls(), s.adds, "H01: no controller addition");
        assertEq(votiumMock.incentiveCount(), s.incentives, "H01: no votium funding");
        assertEq(crmMock.campaignCount(), s.campaigns, "H01: no campaign funding");
        assertEq(token.balanceOf(address(votiumMock)), s.votiumVenueBal, "H01: no votium custody");
        assertEq(token.balanceOf(address(crmMock)), s.crmBal, "H01: no CRM custody");
        assertEq(address(vma_).balance, s.vmEth, "H01: no adapter ETH spent");
        assertEq(token.allowance(address(k.lister), address(va_)), 0, "H01: no lister->votium allowance");
        assertEq(token.allowance(address(k.lister), address(vma_)), 0, "H01: no lister->votemarket allowance");
        assertEq(token.allowance(address(k.lister), address(fd)), 0, "H01: no FD allowance");
    }

    /// @dev Success control: after replacing a refused configuration with
    /// freshly owner-bound adapters, paid admission succeeds with the exact
    /// fee/escrow/record effects and still no venue interaction.
    function _h01ExpectAdmissionSucceeds(H01Core memory k, VotiumAdapter va_, VoteMarketAdapter vma_) internal {
        (address pool, address gauge,) = deployAuthenticatedPool(0, 0);
        uint256 payerBal = token.balanceOf(payer);
        uint256 incentives = votiumMock.incentiveCount();
        uint256 campaigns = crmMock.campaignCount();
        vm.prank(payer);
        k.lister.listGauge(pool, gauge, 0, 0);
        assertEq(token.balanceOf(payer), payerBal - FEE, "H01 success: exact fee paid");
        assertEq(token.balanceOf(address(k.lister)), FEE, "H01 success: escrow custody");
        assertEq(k.lister.totalEscrow(), FEE, "H01 success: liability recorded");
        CurveGaugeLister.Listing memory rec = k.lister.getListing(gauge);
        assertEq(uint8(rec.status), uint8(CurveGaugeLister.Status.Active), "H01 success: Active record");
        assertEq(rec.deposited, FEE, "H01 success: deposited FEE");
        assertEq(rec.votium, address(va_), "H01 success: votium snapshot");
        assertEq(rec.voteMarket, address(vma_), "H01 success: votemarket snapshot");
        assertEq(uint256(rec.votiumBps), 5000, "H01 success: bps snapshot");
        assertEq(uint256(int256(k.controller.gauge_types(gauge))), 0, "H01 success: controller membership");
        assertEq(votiumMock.incentiveCount(), incentives, "H01 success: admission funds no venue");
        assertEq(crmMock.campaignCount(), campaigns, "H01 success: admission creates no campaign");
    }

    function test_AuditH01_PaidAdmissionRejectsUnboundOrMisboundAdapters() public {
        // (1) Positive-share Votium-only, MISBOUND: the ACTUAL OWNER
        // successfully binds a production adapter to another deployed
        // contract, then the intended core is constructed against it. An
        // outsider's failed binding attempt alone would not prove this
        // defense. The unused zero-share VoteMarket side carries the
        // default-core-bound adapter: if it were read, the revert would name
        // the wrong platform.
        VotiumAdapter vaMis = new VotiumAdapter(address(token), adapterManager, address(votiumMock));
        vm.prank(adapterManager);
        vaMis.setLister(address(votiumMock));
        assertEq(vaMis.lister(), address(votiumMock), "actual owner misbound the votium adapter");
        H01Core memory k1 = _h01Core(vaMis, vmAdapter, 10_000);
        _h01ExpectAdmissionRefused(k1, vaMis, vmAdapter, address(vaMis));

        // (2) VoteMarket-only (0 bps), UNBOUND fresh adapter.
        VoteMarketAdapter vmUnbound = new VoteMarketAdapter(address(token), adapterManager, address(crmMock), VM_L2);
        H01Core memory k2 = _h01Core(votiumAdapter, vmUnbound, 0);
        _h01ExpectAdmissionRefused(k2, votiumAdapter, vmUnbound, address(vmUnbound));

        // (3) Mixed split: a CORRECTLY bound first leg is not enough when the
        // positive-share VoteMarket second leg is owner-misbound; BOTH must
        // pass.
        VotiumAdapter vaGood = new VotiumAdapter(address(token), adapterManager, address(votiumMock));
        VoteMarketAdapter vmMis = new VoteMarketAdapter(address(token), adapterManager, address(crmMock), VM_L2);
        H01Core memory k3 = _h01Core(vaGood, vmMis, 5000);
        vm.prank(adapterManager);
        vaGood.setLister(address(k3.lister));
        vm.prank(adapterManager);
        vmMis.setLister(address(crmMock));
        _h01ExpectAdmissionRefused(k3, vaGood, vmMis, address(vmMis));

        // (4) Misbound FUTURE configuration installed through
        // setPlatformConfig: the core was constructed against healthy unbound
        // adapters (permitted), then the owner stages a configuration whose
        // votium leg the adapter owner has misbound. Refused at admission.
        VotiumAdapter vaStaged = new VotiumAdapter(address(token), adapterManager, address(votiumMock));
        VoteMarketAdapter vmStaged = new VoteMarketAdapter(address(token), adapterManager, address(crmMock), VM_L2);
        H01Core memory k4 = _h01Core(vaStaged, vmStaged, 5000);
        vm.prank(adapterManager);
        vaStaged.setLister(address(votiumMock));
        vm.prank(daoOwner);
        k4.lister.setPlatformConfig(CurveGaugeLister.PlatformConfig(address(vaStaged), address(vmStaged), 5000));
        _h01ExpectAdmissionRefused(k4, vaStaged, vmStaged, address(vaStaged));

        // (5) Replace with freshly owner-bound adapters and prove paid
        // admission succeeds. There is no rebinding shortcut: the misbound
        // adapter cannot be rebound by anyone.
        vm.prank(adapterManager);
        vm.expectRevert(VotiumAdapter.ListerAlreadySet.selector);
        vaStaged.setLister(address(k4.lister));
        vm.prank(daoOwner);
        vm.expectRevert(AdapterOwnable.NotOwner.selector); // the core owner is not the adapter owner
        vaStaged.setLister(address(k4.lister));
        VotiumAdapter vaFresh = new VotiumAdapter(address(token), adapterManager, address(votiumMock));
        VoteMarketAdapter vmFresh = new VoteMarketAdapter(address(token), adapterManager, address(crmMock), VM_L2);
        vm.prank(adapterManager);
        vaFresh.setLister(address(k4.lister));
        vm.prank(adapterManager);
        vmFresh.setLister(address(k4.lister));
        vm.prank(daoOwner);
        k4.lister.setPlatformConfig(CurveGaugeLister.PlatformConfig(address(vaFresh), address(vmFresh), 5000));
        _h01ExpectAdmissionSucceeds(k4, vaFresh, vmFresh);
    }

    /// @dev auditfix001 §5 / V-H01: replay of the audit's VoteMarket capture
    /// — an outsider binding the adapter to a funded/approved attacker
    /// caller, then TWO distinct scheduled-epoch campaign attempts against a
    /// fully operational adapter (float funded, chain 1, whitelisted
    /// destination, default manager/gas configuration). Under owner-gated
    /// binding the capture reverts NotOwner and both deposits revert
    /// NotLister with zero residue; the legitimate owner binding plus one
    /// authorized deposit is the success control. Wrong-chain/bad-calldata/
    /// float-shortfall failures could not substitute for this authorization
    /// evidence.
    function test_AuditH01_VoteMarketCaptureCannotSpendEthFloat() public {
        // Fully operational victim adapter (audit fixture: 2 * REQUIRED_ETH
        // float) and a funded attacker lister-caller.
        VoteMarketAdapter victim = new VoteMarketAdapter(address(token), adapterManager, address(crmMock), VM_L2);
        vmx.deal(address(victim), 2 * REQUIRED_ETH);
        ListerCaller attacker = new ListerCaller();
        attacker.setToken(address(token));
        token.mint(address(attacker), 2 * QUARTER);
        address attackGauge = address(0xBEEF);
        uint256 e1 = T0 + WEEK;
        uint256 e2 = T0 + 2 * WEEK;

        uint256 attackerTok = token.balanceOf(address(attacker));
        uint256 float = address(victim).balance;
        uint256 campaigns = crmMock.campaignCount();
        uint256 ethPaid = crmMock.ethPaid();
        uint256 deposits = victim.depositCount();

        // The outsider's binding attempt reverts exactly NotOwner; the
        // getter stays zero and no ListerSet is emitted.
        vm.recordLogs();
        vm.prank(address(attacker));
        vm.expectRevert(AdapterOwnable.NotOwner.selector);
        victim.setLister(address(attacker));
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertFalse(hasEventFrom(logs, address(victim), keccak256("ListerSet(address)")), "no ListerSet on capture");
        assertEq(victim.lister(), address(0), "adapter still unbound after capture attempt");

        // Both distinct scheduled-epoch deposit attempts revert NotLister —
        // directly and through the armed-approval caller wrapper.
        vm.prank(address(attacker));
        vm.expectRevert(VoteMarketAdapter.NotLister.selector);
        victim.deposit(attackGauge, e1, QUARTER);
        vm.prank(address(attacker));
        vm.expectRevert(VoteMarketAdapter.NotLister.selector);
        victim.deposit(attackGauge, e2, QUARTER);
        vm.expectRevert(VoteMarketAdapter.NotLister.selector);
        attacker.deposit(IIncentivePlatform(address(victim)), attackGauge, e1, QUARTER);

        // Zero residue: no attacker token loss, no float spent, no CRM
        // ethPaid/campaign movement, no adapter receipt or approval residue.
        assertEq(token.balanceOf(address(attacker)), attackerTok, "no attacker token loss");
        assertEq(address(victim).balance, float, "ETH float intact");
        assertEq(crmMock.campaignCount(), campaigns, "no campaign created");
        assertEq(crmMock.ethPaid(), ethPaid, "no bridge gas paid");
        assertEq(victim.depositCount(), deposits, "no adapter deposit record");
        assertEq(token.allowance(address(attacker), address(victim)), 0, "no approval residue");
        assertEq(token.allowance(address(victim), address(crmMock)), 0, "no venue approval residue");

        // Legitimate owner binding and authorized deposit success control.
        vm.expectEmit(true, false, false, true);
        emit ListerSet(address(attacker));
        vm.prank(adapterManager);
        victim.setLister(address(attacker));
        assertEq(victim.lister(), address(attacker), "owner bound the adapter");
        bytes32 r = attacker.deposit(IIncentivePlatform(address(victim)), attackGauge, e1, QUARTER);
        assertTrue(r != bytes32(0), "authorized deposit funds");
        assertEq(crmMock.campaignCount(), campaigns + 1, "control records one campaign");
        assertEq(crmMock.ethPaid(), ethPaid + REQUIRED_ETH, "control pays exactly one bridge value");
        assertEq(address(victim).balance, float - REQUIRED_ETH, "control spends exactly the bridge value");
        assertEq(token.balanceOf(address(attacker)), attackerTok - QUARTER, "control pulls exactly the amount");
    }
}
