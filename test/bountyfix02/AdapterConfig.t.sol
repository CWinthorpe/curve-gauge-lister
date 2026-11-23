// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {TestBase, Vm} from "../TestBase.sol";
import {CurveGaugeLister} from "../../contracts/CurveGaugeLister.sol";
import {AlwaysTrueTrustedValidator} from "../mocks/TrustedFactoryMocks.sol";
import {IERC20Minimal} from "../../contracts/interfaces/IERC20Minimal.sol";
import {IIncentivePlatform} from "../../contracts/interfaces/IIncentivePlatform.sol";
import {SafeToken} from "../../contracts/libraries/SafeToken.sol";
import {VotiumAdapter} from "../../contracts/adapters/VotiumAdapter.sol";
import {VoteMarketAdapter} from "../../contracts/adapters/VoteMarketAdapter.sol";
import {AdapterOwnable} from "../../contracts/libraries/AdapterOwnable.sol";
import {MockERC20} from "../../contracts/mocks/MockERC20.sol";
import {MockPool} from "../../contracts/mocks/MockPool.sol";
import {MockGauge} from "../../contracts/mocks/MockGauge.sol";
import {MockCurveRegistry} from "../../contracts/mocks/MockCurveRegistry.sol";
import {MockListingController} from "../../contracts/mocks/MockListingController.sol";
import {MockFeeDistributor} from "../../contracts/mocks/MockFeeDistributor.sol";
import {MockVotiumV2} from "../../contracts/mocks/MockVotiumV2.sol";
import {MockCampaignRemoteManager} from "../../contracts/mocks/MockCampaignRemoteManager.sol";

/// @dev Minimal extra cheatcodes this suite needs; same dispatcher as the
/// other suites, no forge-std (plans/BOUNTY-FIX2-PLAN.md §9: the standalone
/// AdapterConfigR2Test may not inherit a concrete existing suite).
interface VmExt {
    function deal(address who, uint256 newBalance) external;
}

/// @notice Test-only stand-in for the lister side of `IIncentivePlatform.deposit`
/// used by the constructor-witness deposit controls: mirrors core
/// `_fundPlatform` (exact approval, deposit, nonzero-receipt and exact-debit
/// checks, clear to zero). Deliberately distinct from any other suite's
/// helper (plans/BOUNTY-FIX2-PLAN.md §9: test-only helpers live in this file).
contract AdapterDepositCaller {
    error ReceiptMissing();
    error DeltaMismatch();

    address private token;

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
}

/// @notice BOUNTY-FIX2-PLAN §9 A01–A05: CGL-V-L01 constructor code-presence
/// guards on the two real-venue adapters (A01/A02) and CGL-V-L06 worst-case
/// gas-setting overflow rejection through the existing BadGasSettings error
/// (A03/A04/A05). Standalone suite on the frozen TestBase and the existing
/// deployed venue mocks; product behavior only — no mock or TestBase edits.
contract AdapterConfigR2Test is TestBase {
    VmExt internal constant vmx = VmExt(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    uint256 internal constant U = type(uint256).max;
    uint256 internal constant N = 50; // MAX_EXCLUDED on both adapters
    uint256 internal constant FEE = 10_000e18;
    uint256 internal constant QUARTER = 2_500e18;
    uint256 internal constant HALF = 1_250e18;
    uint256 internal constant WEEK = 604800;
    uint256 internal constant T0 = 1794441600; // Thu 2026-11-12 00:00 UTC
    uint256 internal constant GWEI = 1 gwei;
    /// @notice Mixed-share split used by the A05 V1 listing (adapter-manager
    /// configuration choice, not a product constant).
    uint16 internal constant VOTIUM_BPS = 4000;
    uint256 internal constant VOTIUM_SHARE = QUARTER * VOTIUM_BPS / 10_000; // 1,000e18
    uint256 internal constant VM_SHARE = QUARTER - QUARTER * VOTIUM_BPS / 10_000; // 1,500e18
    address internal constant VM_L2 = 0x8c2c5A295450DDFf4CB360cA73FCCC12243D14D9;

    MockERC20 internal token;
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
        payer = actor("feePayer");
        stranger = actor("stranger");

        token = new MockERC20(18);
        registry = new MockCurveRegistry();
        controller = new MockListingController(controllerDao, int128(2));
        vm.warp(T0);
        // The verified CampaignRemoteManager ingress guard requires
        // block.chainid == 1, so succeeding campaign fixtures run at the real
        // source chain (same convention as the frozen adapter suite).
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
            CurveGaugeLister.PlatformConfig(address(votiumAdapter), address(vmAdapter), VOTIUM_BPS),
            address(new AlwaysTrueTrustedValidator())
        );

        vm.prank(controllerDao);
        controller.setLister(address(lister));
        vm.prank(adapterManager);
        votiumAdapter.setLister(address(lister));
        vm.prank(adapterManager);
        vmAdapter.setLister(address(lister));

        // V1ALIGN §1.3: the fresh core starts paused. Observe that shipped
        // state, then the owner unpauses after binding so the retained
        // funded-checkpoint paths run as originally specified.
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

    // --------------------------------------------------------------- helpers

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

    // ------------------------------------------------------------------ A01

    /// @notice CGL-V-L01/Votium: a nonzero but code-less token or local
    /// Votium ingress is rejected with exactly Error("no code") while the
    /// other arguments are valid; the pre-existing zero-argument rule keeps
    /// precedence. A code-bearing token/venue pair with a nonzero EOA owner
    /// constructs and returns the exact pins, and a funded ordinary deposit
    /// through the bound caller still succeeds with the exact pull and zero
    /// allowances.
    function test_R2_VotiumConstructorRejectsCodeLessPins() public {
        address noCodeToken = actor("codeless-token");
        address noCodeIngress = actor("codeless-ingress");
        assertTrue(noCodeToken.code.length == 0 && noCodeIngress.code.length == 0, "fixtures are code-less");

        // Code-less token, all other arguments valid.
        vm.expectRevert(bytes("no code"));
        new VotiumAdapter(noCodeToken, adapterManager, address(votiumMock));
        // Code-less local ingress, all other arguments valid.
        vm.expectRevert(bytes("no code"));
        new VotiumAdapter(address(token), adapterManager, noCodeIngress);

        // Zero-argument precedence: the "zero arg" require still fires FIRST,
        // including when a non-zero argument is also code-less.
        vm.expectRevert(bytes("zero arg"));
        new VotiumAdapter(address(0), adapterManager, noCodeIngress);
        vm.expectRevert(bytes("zero arg"));
        new VotiumAdapter(noCodeToken, address(0), address(votiumMock));
        vm.expectRevert(bytes("zero arg"));
        new VotiumAdapter(address(token), adapterManager, address(0));

        // Success control: code-bearing token and venue, nonzero EOA owner.
        VotiumAdapter okAdapter = new VotiumAdapter(address(token), adapterManager, address(votiumMock));
        assertEq(okAdapter.crvUSD(), address(token), "exact token pin");
        assertEq(okAdapter.owner(), adapterManager, "exact EOA owner pin");
        assertEq(okAdapter.votium(), address(votiumMock), "exact local ingress pin");

        // Funded ordinary deposit remains a success control: exact pull,
        // zero allowances left behind.
        AdapterDepositCaller caller = new AdapterDepositCaller();
        caller.setToken(address(token));
        token.mint(address(caller), HALF);
        vm.prank(adapterManager);
        okAdapter.setLister(address(caller));
        (, address freshGauge,) = deployAuthenticatedPool(5, 5);
        uint256 balBefore = token.balanceOf(address(caller));
        bytes32 receipt = caller.deposit(okAdapter, freshGauge, T0 + WEEK, HALF);
        assertTrue(receipt != bytes32(0), "deterministic nonzero receipt");
        assertEq(balBefore - token.balanceOf(address(caller)), HALF, "exact pull");
        assertEq(token.balanceOf(address(votiumMock)), HALF, "venue custody exact");
        assertEq(token.balanceOf(address(okAdapter)), 0, "adapter retains nothing");
        assertEq(token.allowance(address(caller), address(okAdapter)), 0, "caller allowance cleared");
        assertEq(token.allowance(address(okAdapter), address(votiumMock)), 0, "venue allowance cleared");
    }

    // ------------------------------------------------------------------ A02

    /// @notice CGL-V-L01/VoteMarket: code-less crvUSD or local
    /// CampaignRemoteManager is rejected with exactly Error("no code");
    /// zero-argument precedence is retained; a valid local pair with a
    /// nonzero EOA owner and a remote VoteMarket address WITHOUT L1 code
    /// succeeds (the remote is checked on its destination chain, not here);
    /// the remote zero still fails; all pins return exactly; and a real mock
    /// CRM deposit with the registered remote platform preserves
    /// receipt/funding with zero allowances.
    function test_R2_VoteMarketConstructorDistinguishesLocalAndRemotePins() public {
        address noCodeToken = actor("codeless-token");
        address noCodeCrm = actor("codeless-crm");
        assertTrue(noCodeToken.code.length == 0 && noCodeCrm.code.length == 0, "fixtures are code-less");
        assertTrue(VM_L2.code.length == 0, "remote VoteMarket has no L1 code in this fixture");

        // Code-less token / code-less local CRM, other arguments valid.
        vm.expectRevert(bytes("no code"));
        new VoteMarketAdapter(noCodeToken, adapterManager, address(crmMock), VM_L2);
        vm.expectRevert(bytes("no code"));
        new VoteMarketAdapter(address(token), adapterManager, noCodeCrm, VM_L2);

        // Zero-argument precedence, including zero + code-less combinations.
        vm.expectRevert(bytes("zero arg"));
        new VoteMarketAdapter(address(0), adapterManager, noCodeCrm, VM_L2);
        vm.expectRevert(bytes("zero arg"));
        new VoteMarketAdapter(noCodeToken, address(0), address(crmMock), VM_L2);
        // Remote zero still fails: the destination address keeps its nonzero
        // requirement even though it never needs L1 code.
        vm.expectRevert(bytes("zero arg"));
        new VoteMarketAdapter(address(token), adapterManager, address(crmMock), address(0));

        // Success control: local contracts with code, EOA owner, and a
        // code-less remote — remote code is NOT required.
        VoteMarketAdapter okAdapter = new VoteMarketAdapter(address(token), adapterManager, address(crmMock), VM_L2);
        assertEq(okAdapter.crvUSD(), address(token), "exact token pin");
        assertEq(okAdapter.campaignRemoteManager(), address(crmMock), "exact local CRM pin");
        assertEq(okAdapter.votemarket(), VM_L2, "remote pinned without requiring L1 code");
        assertEq(okAdapter.owner(), adapterManager, "exact EOA owner pin");

        // Real mock CRM deposit with the registered remote platform:
        // receipt/funding preserved and every allowance cleared.
        AdapterDepositCaller caller = new AdapterDepositCaller();
        caller.setToken(address(token));
        token.mint(address(caller), HALF);
        vmx.deal(address(okAdapter), 1 ether);
        vm.prank(adapterManager);
        okAdapter.setLister(address(caller));
        (, address freshGauge,) = deployAuthenticatedPool(6, 6);
        uint256 balBefore = token.balanceOf(address(caller));
        uint256 ethBefore = address(okAdapter).balance;
        bytes32 receipt = caller.deposit(okAdapter, freshGauge, T0 + WEEK, HALF);
        assertTrue(receipt != bytes32(0), "deterministic nonzero receipt");
        assertEq(balBefore - token.balanceOf(address(caller)), HALF, "exact pull");
        assertEq(crmMock.campaignCount(), 1, "one recorded campaign");
        MockCampaignRemoteManager.Campaign memory c = crmMock.campaignAt(0);
        assertEq(c.params.gauge, freshGauge, "campaign bound to the gauge");
        assertEq(c.params.manager, address(okAdapter), "adapter is campaign manager");
        assertEq(c.params.rewardToken, address(token), "campaign token is crvUSD");
        assertEq(c.params.totalRewardAmount, HALF, "recorded amount exact");
        assertEq(c.destinationChainId, 42161, "destination chain");
        assertEq(c.additionalGasLimit, 2_000_000, "default base gas");
        assertEq(c.value, 2_000_000 * GWEI, "default pricing paid");
        (uint256 amount, uint256 executionEpoch, bytes32 recorded) = okAdapter.getDeposit(freshGauge, T0 + WEEK);
        assertEq(amount, HALF, "keyed record amount");
        assertEq(executionEpoch, T0 / WEEK * WEEK, "keyed record execution epoch");
        assertEq(recorded, receipt, "keyed record is the returned receipt");
        assertEq(token.balanceOf(address(crmMock)), HALF, "CRM custody exact");
        assertEq(token.balanceOf(address(okAdapter)), 0, "adapter retains nothing");
        assertEq(token.allowance(address(caller), address(okAdapter)), 0, "caller allowance cleared");
        assertEq(token.allowance(address(okAdapter), address(crmMock)), 0, "CRM allowance cleared");
        assertEq(ethBefore - address(okAdapter).balance, 2_000_000 * GWEI, "float spent exactly");
    }

    // ------------------------------------------------------- shared helpers

    bytes32 internal constant GAS_SETTINGS_SET_SIG = keccak256("GasSettingsSet(uint256,uint256,uint256)");

    struct GasSnap {
        uint256 b;
        uint256 x;
        uint256 p;
        uint256 excl;
        uint256 adapterToken;
        uint256 crmToken;
        uint256 eth;
    }

    function _gasSnap() private view returns (GasSnap memory s) {
        s.b = vmAdapter.campaignCreationGas();
        s.x = vmAdapter.blacklistedAddressGas();
        s.p = vmAdapter.gasPrice();
        s.excl = vmAdapter.excluded().length;
        s.adapterToken = token.balanceOf(address(vmAdapter));
        s.crmToken = token.balanceOf(address(crmMock));
        s.eth = address(vmAdapter).balance;
    }

    /// @dev As the actual manager, the triple must revert with exactly
    /// BadGasSettings (never an arithmetic Panic), store nothing and emit
    /// nothing: every getter, the exclusion list, token custody and the ETH
    /// float are byte-for-byte the pre-request snapshot.
    function _assertGasSettingsRejected(uint256 b, uint256 x, uint256 p) private {
        GasSnap memory pre = _gasSnap();
        vm.prank(adapterManager);
        vm.recordLogs();
        vm.expectRevert(VoteMarketAdapter.BadGasSettings.selector);
        vmAdapter.setGasSettings(b, x, p);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(countEvents(logs, address(vmAdapter), GAS_SETTINGS_SET_SIG), 0, "no GasSettingsSet on rejection");
        GasSnap memory post = _gasSnap();
        assertEq(post.b, pre.b, "campaignCreationGas unchanged");
        assertEq(post.x, pre.x, "blacklistedAddressGas unchanged");
        assertEq(post.p, pre.p, "gasPrice unchanged");
        assertEq(post.excl, pre.excl, "exclusion list unchanged");
        assertEq(post.adapterToken, pre.adapterToken, "adapter token balance unchanged");
        assertEq(post.crmToken, pre.crmToken, "CRM custody unchanged");
        assertEq(post.eth, pre.eth, "adapter ETH float unchanged");
    }

    function _acceptGasTriple(uint256 b, uint256 x, uint256 p) private {
        vm.prank(adapterManager);
        vmAdapter.setGasSettings(b, x, p);
        assertEq(vmAdapter.campaignCreationGas(), b, "accepted base stored");
        assertEq(vmAdapter.blacklistedAddressGas(), x, "accepted per-exclusion stored");
        assertEq(vmAdapter.gasPrice(), p, "accepted price stored");
        // Non-panicking query at a positive amount; the zero-amount query
        // reports zero irrespective of the triple.
        uint256 d = vmAdapter.ethDeficit(1);
        assertTrue(d <= U, "positive-amount query returns without panic");
        assertEq(vmAdapter.ethDeficit(0), 0, "zero-amount query is zero");
    }

    // ------------------------------------------------------------------ A03

    /// @notice CGL-V-L06: the actual manager's overflow-inducing triples are
    /// rejected with exactly BadGasSettings — never a Panic(0x11) arithmetic
    /// abort — before ANY storage or event, with the initially empty list
    /// retained throughout to prove the FUTURE maximum exclusion length is
    /// checked, not the current one. An otherwise-valid request from a
    /// non-manager still reverts NotOwner.
    function test_R2_GasSettingsRejectOverflowWithoutMutation() public {
        assertEq(vmAdapter.excluded().length, 0, "initial empty list retained");
        assertEq(vmAdapter.campaignCreationGas(), 2_000_000, "default base");
        assertEq(vmAdapter.blacklistedAddressGas(), 50_000, "default per-exclusion");
        assertEq(vmAdapter.gasPrice(), GWEI, "default price");

        _assertGasSettingsRejected(U, 0, 2); // price product overflow
        _assertGasSettingsRejected(1, U / N + 1, 1); // blacklistedAddressGas * N overflow
        _assertGasSettingsRejected(U, 1, 1); // base + X*N overflow
        _assertGasSettingsRejected(U - N, 1, 2); // exact budget U, price product overflow
        _assertGasSettingsRejected(0, 1, GWEI); // existing: zero base rejected
        _assertGasSettingsRejected(1, 1, 0); // existing: zero price rejected

        // Unauthorized otherwise-valid request: still NotOwner, no mutation.
        GasSnap memory pre = _gasSnap();
        vm.prank(stranger);
        vm.expectRevert(AdapterOwnable.NotOwner.selector);
        vmAdapter.setGasSettings(1, 1, 1);
        GasSnap memory post = _gasSnap();
        assertEq(post.b, pre.b, "base untouched by NotOwner");
        assertEq(post.x, pre.x, "per-exclusion untouched by NotOwner");
        assertEq(post.p, pre.p, "price untouched by NotOwner");

        // Final state is exactly the pre-request baseline.
        assertEq(vmAdapter.campaignCreationGas(), 2_000_000, "defaults after all rejections");
        assertEq(vmAdapter.blacklistedAddressGas(), 50_000, "defaults after all rejections (X)");
        assertEq(vmAdapter.gasPrice(), GWEI, "defaults after all rejections (P)");
        assertEq(vmAdapter.excluded().length, 0, "empty list after all rejections");
    }

    // ------------------------------------------------------------------ A04

    /// @notice CGL-V-L06: worst-case boundaries. Accepts the arithmetically
    /// safe extremes `(U,0,1)`, `(U-50,1,1)` and `(1,0,U)`; independently
    /// accepts P=floor(U/(B+50X)) and rejects P+1; independently accepts the
    /// exact X bound (U-B)/50 and rejects it plus one. Growth of the
    /// exclusion list from empty to the maximum AFTER setting the triple
    /// keeps ethDeficit exact at zero/partial/sufficient float with realistic
    /// values — arithmetic is validated for all 0..50 lengths, never against
    /// the current count alone.
    function test_R2_GasSettingsWorstCaseBoundariesAndExclusionGrowth() public {
        _acceptGasTriple(U, 0, 1);
        _acceptGasTriple(U - N, 1, 1);
        _acceptGasTriple(1, 0, U);

        // Positive affordable B/X triple: exact P boundary at U/(B+50X).
        uint256 b = 1_000_000;
        uint256 x = 1_000;
        assertTrue(x <= (U - b) / N, "test-local X bound established");
        uint256 g = b + x * N;
        assertTrue(g > 0 && g <= U, "test-local budget bound established");
        uint256 pMax = U / g;
        _acceptGasTriple(b, x, pMax);
        vm.prank(adapterManager);
        vm.expectRevert(VoteMarketAdapter.BadGasSettings.selector);
        vmAdapter.setGasSettings(b, x, pMax + 1);

        // Exact X boundary at P=1 for a positive base.
        b = 2_000_000;
        uint256 xBound = (U - b) / N;
        _acceptGasTriple(b, xBound, 1);
        vm.prank(adapterManager);
        vm.expectRevert(VoteMarketAdapter.BadGasSettings.selector);
        vmAdapter.setGasSettings(b, xBound + 1, 1);

        _exclusionGrowthDeficits();
    }

    /// @dev Realistic triple, then lengths 0..50 set AFTER the triple: exact
    /// deficit at zero, partial and sufficient float. Test-local expected
    /// budgets are computed only after the bounds are independently asserted.
    function _exclusionGrowthDeficits() private {
        uint256 b = 2_000_000;
        uint256 x = 50_000;
        uint256 p = GWEI;
        assertTrue(x <= (U - b) / N, "growth cell X bound");
        uint256 g = b + x * N;
        assertTrue(p <= U / g, "growth cell price bound");
        _acceptGasTriple(b, x, p);

        for (uint256 k = 0; k <= N; ++k) {
            address[] memory list = new address[](k);
            for (uint256 i = 0; i < k; ++i) {
                list[i] = address(uint160(i + 1)); // unique, nonzero, valid
            }
            vm.prank(adapterManager);
            vmAdapter.setExcluded(list);
            assertEq(vmAdapter.excluded().length, k, "list length applied");
            uint256 required = (b + x * k) * p;

            vmx.deal(address(vmAdapter), required); // sufficient (exact)
            assertEq(vmAdapter.ethDeficit(HALF), 0, "sufficient float: no deficit");
            vmx.deal(address(vmAdapter), required / 2); // partial
            assertEq(vmAdapter.ethDeficit(HALF), required - required / 2, "partial float: exact deficit");
            vmx.deal(address(vmAdapter), 0); // zero
            assertEq(vmAdapter.ethDeficit(HALF), required, "zero float: full required");
        }
        assertEq(vmAdapter.excluded().length, N, "moved from empty to maximum list");
    }

    // ------------------------------------------------------------------ A05

    /// @notice CGL-V-L06 integration: a fresh mixed-share V1 listing through
    /// the real two adapters and the existing venue mocks. The malicious
    /// triple is rejected before storage (safe settings and the live deficit
    /// unchanged, no event); the quarter then actually funds and checkpoints
    /// one maturity with exact per-share receipts, custody and cleared
    /// allowances. A separate insufficient-float attempt still rolls back the
    /// healthy first (Votium) leg and ALL quarter state; refilling and
    /// retrying the same maturity settles it.
    function test_R2_RejectedGasSettingsPreserveFundedCheckpoint() public {
        (address pool, address gauge,) = deployAuthenticatedPool(7, 7);
        listPaid(pool, gauge, 7, 7);

        // Safe triple (price stays at the controlled messenger's 1 gwei
        // billing so funded deposits keep succeeding).
        vm.prank(adapterManager);
        vmAdapter.setGasSettings(1_500_000, 20_000, GWEI);
        vmx.deal(address(vmAdapter), 1_000_000 * GWEI); // partial float
        uint256 deficit = vmAdapter.ethDeficit(HALF);
        assertEq(deficit, 1_500_000 * GWEI - 1_000_000 * GWEI, "live nonzero deficit");

        // Rejected malicious triples mutate nothing.
        _assertGasSettingsRejected(U, 0, 2);
        _assertGasSettingsRejected(1, U / N + 1, 1);
        _assertGasSettingsRejected(U - N, 1, 2);
        assertEq(vmAdapter.campaignCreationGas(), 1_500_000, "safe base preserved");
        assertEq(vmAdapter.blacklistedAddressGas(), 20_000, "safe X preserved");
        assertEq(vmAdapter.gasPrice(), GWEI, "safe P preserved");
        assertEq(vmAdapter.ethDeficit(HALF), deficit, "deficit unchanged by rejections");

        // Fund the float and checkpoint one due quarter through both real
        // adapters at the mixed split.
        vmx.deal(address(vmAdapter), 1 ether);
        votiumMock.setActiveRound(1);
        vm.warp(T0 + WEEK);
        (uint256 released, uint256 confiscated) = lister.checkpoint(gauge);
        assertEq(released, QUARTER, "one quarter released");
        assertEq(confiscated, 0, "nothing confiscated");
        assertEq(token.balanceOf(address(votiumMock)), VOTIUM_SHARE, "votium share exact");
        assertEq(token.balanceOf(address(crmMock)), VM_SHARE, "votemarket share exact");
        assertEq(votiumMock.deposited(1, gauge, address(token)), VOTIUM_SHARE, "votium per-round record");
        assertEq(crmMock.campaignCount(), 1, "one campaign");
        CurveGaugeLister.Listing memory rec = lister.getListing(gauge);
        assertEq(uint256(rec.epochsReleased), 1, "exactly one epoch advancement");
        assertEq(rec.remaining, FEE - QUARTER, "remaining decremented by one quarter");
        assertEq(token.allowance(address(lister), address(votiumAdapter)), 0, "core->votium cleared");
        assertEq(token.allowance(address(lister), address(vmAdapter)), 0, "core->votemarket cleared");
        assertEq(token.allowance(address(votiumAdapter), address(votiumMock)), 0, "votium->venue cleared");
        assertEq(token.allowance(address(vmAdapter), address(crmMock)), 0, "votemarket->CRM cleared");

        // Insufficient-float attempt: the whole checkpoint reverts, rolling
        // back the healthy first leg and all quarter state (never a skip).
        vm.warp(T0 + 2 * WEEK);
        votiumMock.setActiveRound(2);
        vmx.deal(address(vmAdapter), 1_500_000 * GWEI - 1);
        vm.expectRevert(VoteMarketAdapter.InsufficientEth.selector);
        lister.checkpoint(gauge);
        assertEq(votiumMock.incentiveCount(), 1, "healthy Votium leg rolled back");
        assertEq(crmMock.campaignCount(), 1, "no campaign from the failed attempt");
        assertEq(uint256(lister.getListing(gauge).epochsReleased), 1, "quarter state unchanged");
        assertEq(lister.getListing(gauge).remaining, FEE - QUARTER, "escrow unchanged by rollback");
        assertEq(token.balanceOf(address(votiumMock)), VOTIUM_SHARE, "votium custody unchanged");
        assertEq(token.balanceOf(address(crmMock)), VM_SHARE, "CRM custody unchanged");

        // Refill and retry the same maturity.
        vmx.deal(address(vmAdapter), 1 ether);
        lister.checkpoint(gauge);
        rec = lister.getListing(gauge);
        assertEq(uint256(rec.epochsReleased), 2, "same maturity settled on retry");
        assertEq(rec.remaining, FEE - 2 * QUARTER, "two quarters released");
        assertEq(votiumMock.incentiveCount(), 2, "second votium deposit");
        assertEq(crmMock.campaignCount(), 2, "second campaign");
        assertEq(token.balanceOf(address(votiumMock)), 2 * VOTIUM_SHARE, "cumulative votium custody");
        assertEq(token.balanceOf(address(crmMock)), 2 * VM_SHARE, "cumulative CRM custody");
    }
}
