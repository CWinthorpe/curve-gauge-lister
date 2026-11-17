// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BountyFixture} from "../bounty/BountyFixture.sol";
import {CurveGaugeListerV2} from "../../contracts/CurveGaugeListerV2.sol";
import {IERC20Minimal} from "../../contracts/interfaces/IERC20Minimal.sol";
import {ICurveGaugeListerV2} from "../../contracts/interfaces/ICurveGaugeListerV2.sol";
import {MockERC20} from "../../contracts/mocks/MockERC20.sol";
import {MockPool} from "../../contracts/mocks/MockPool.sol";
import {MockGauge} from "../../contracts/mocks/MockGauge.sol";
import {MockCurveRegistry} from "../../contracts/mocks/MockCurveRegistry.sol";
import {MockListingController} from "../../contracts/mocks/MockListingController.sol";
import {MockFeeDistributor} from "../../contracts/mocks/MockFeeDistributor.sol";
import {MockIncentivePlatform} from "../../contracts/mocks/MockIncentivePlatform.sol";
import {MockBountyHook} from "../bounty/mocks/MockBountyHook.sol";

/// @dev Test-only faulty deployment (plan §9): add_gauge does nothing so the
/// product's membership postcondition must reject a lying integration instead
/// of silently accepting an unfunded registration. No additional external
/// functions or storage. Mirrors the frozen baseline's test-local deployment.
contract NoOpListingController is MockListingController {
    constructor(address dao_, int128 gaugeTypeCount_) MockListingController(dao_, gaugeTypeCount_) {}

    function add_gauge(address, int128, uint256) public override {}
}

/// @dev exec7 narrow faulty deployment: ONLY the weight getter reverts, while
/// add_gauge and membership remain functional. Proves paid admission performs
/// no weight read and holds no nonzero-weight postcondition — without a global
/// failing-reader shortcut that would also break membership.
contract WeightReaderRevertingController is MockListingController {
    error WeightReadFailed();

    constructor(address dao_, int128 gaugeTypeCount_) MockListingController(dao_, gaugeTypeCount_) {}

    function get_gauge_weight(address) external view override returns (uint256) {
        revert WeightReadFailed();
    }
}

/// @dev exec7 narrow faulty deployment: registers the gauge under a DIFFERENT
/// type than the admission derived type, so only the membership postcondition
/// can catch the lie. Registered type stays inside the valid type range.
contract WrongTypeListingController is MockListingController {
    constructor(address dao_, int128 gaugeTypeCount_) MockListingController(dao_, gaugeTypeCount_) {}

    function add_gauge(address gauge, int128 gaugeType, uint256 weight) public override {
        super.add_gauge(gauge, gaugeType + 1, weight);
    }
}

/// @dev auditfix001 §4/§5: small test-local platform getter-fault endpoints
/// for the readiness cases. Each keeps a VALID reward-token identity (and
/// code) so core platform validation passes and the fault is isolated to the
/// readiness read itself. These are faults, not claimed upstream features.
contract NoListerGetterPlatform {
    address private immutable _token;

    constructor(address token_) {
        _token = token_;
    }

    function rewardToken() external view returns (address) {
        return _token;
    }

    // No lister() at all and no fallback: the readiness staticcall reverts
    // with empty returndata — a hard failure that must propagate.
}

contract FaultyListerGetterPlatform {
    error ListerReadFailed();

    address private immutable _token;
    uint8 private immutable _mode; // 1 revert, 2 short return

    constructor(address token_, uint8 mode_) {
        require(mode_ == 1 || mode_ == 2, "mode");
        _token = token_;
        _mode = mode_;
    }

    function rewardToken() external view returns (address) {
        return _token;
    }

    function lister() external view returns (address) {
        if (_mode == 1) revert ListerReadFailed();
        // Malformed: fewer than 32 bytes of returndata.
        address value = address(0xA11CE);
        assembly {
            mstore(0, value)
            return(0, 31)
        }
    }
}

/// @title V2AdmissionTest
/// @notice Business/admission/roles matrix mirrored COMPLETELY onto
/// CurveGaugeListerV2 (plans/BOUNTY-PLAN.md §5.5 V2Admission, 18 tests). Every
/// baseline `test_X` of test/CurveGaugeLister.t.sol has exactly one
/// `test_V2_X` here with the same subcases, assertions and helper semantics;
/// only the tuple shape (18-field ListingV2), the versioned confiscation
/// event, the paused start and the reciprocal bounty/adapter wiring differ.
/// The suite never instantiates V1: every core is a fresh V2 deployed through
/// the BountyFixture helpers, with a fresh controller, fresh platform mocks
/// and a fresh strict MockBountyHook bound to that core (X02 stand-in until
/// real GaugeBounty integration).
contract V2AdmissionTest is BountyFixture {
    address internal constant NATIVE = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    // Extra fixtures the baseline declared in its own file (test-local).
    MockERC20 internal otherToken;
    MockCurveRegistry internal registry2;

    // Shared fixture state for the split atomicity sub-scenarios (stack-depth
    // relief only; every assertion stays in place inside the named test).
    address internal negPoolA;
    address internal negGaugeA;
    address internal negPoolB;
    address internal negGaugeB;
    address internal poorPayerActor;
    address internal unapprovedPayerActor;

    function setUp() public {
        // V2 pins Ethereum mainnet (§1.2 `WrongChain`); the offline executor
        // environment defaults to chain 31337, so the parity world explicitly
        // sets the mainnet chain id BEFORE any V2 construction. The fork
        // profile already pins chain_id = 1.
        vm.chainId(1);
        setupBountyWorld();
        otherToken = new MockERC20(18);
        registry2 = new MockCurveRegistry();

        // Fresh seated controller, fresh platform mocks, fresh hook bound to
        // the core, unpaused, payer approved max (§1.2 wiring order).
        deployDefaultV2();

        // The fee token needs real payer custody before any admission.
        crvUSD.mint(payer, FEE * 16);
    }

    // ---------------------------------------------------------------
    // fixtures
    // ---------------------------------------------------------------

    function deployAuthenticatedPool(uint256 handlerId, uint256 gaugeIndex)
        internal
        returns (address pool, address gauge, address lp)
    {
        return deployAuthenticatedPoolWith(
            handlerId, gaugeIndex, address(new MockERC20(18)), address(new MockERC20(18)), 2, 0
        );
    }

    function deployAuthenticatedPoolWith(
        uint256 handlerId,
        uint256 gaugeIndex,
        address coin0,
        address coin1,
        uint256 nCoins,
        int128 gaugeType
    ) internal returns (address pool, address gauge, address lp) {
        lp = address(new MockERC20(18));
        pool = address(new MockPool());
        gauge = address(new MockGauge(lp));
        registry.setPool(pool, handlerId, lp, _coins(coin0, coin1), nCoins);
        registry.setGauge(pool, handlerId, gaugeIndex, gauge, gaugeType);
    }

    function listPaid(address pool, address gauge, uint256 gaugeIndex, uint256 handlerId) internal {
        vm.prank(payer);
        v2.listGauge(pool, gauge, gaugeIndex, handlerId);
    }

    function listDao(address pool, address gauge, uint256 gaugeIndex, uint256 handlerId, uint256 weight) internal {
        vm.prank(daoOwner);
        v2.listGaugeNoEscrow(pool, gauge, gaugeIndex, handlerId, weight);
    }

    /// @dev Kill the gauge for settlement via its admin-side flag (A2): flip
    /// MockGauge's independent killed switch. Weight is never touched.
    function killGauge(address gauge) internal {
        MockGauge(gauge).setKilled(true);
    }

    /// @dev Construct one V2 core with an explicit platform config/bounty on
    /// the default dependency addresses (constructor-negative relief).
    function newV2With(CurveGaugeListerV2.PlatformConfig memory platforms_, address bounty_)
        internal
        returns (CurveGaugeListerV2)
    {
        return new CurveGaugeListerV2(
            daoOwner,
            address(crvUSD),
            address(controller),
            address(fd),
            CurveGaugeListerV2.AdmissionConfig(address(registry), 8),
            platforms_,
            bounty_,
            address(tfValidator)
        );
    }

    /// @dev Fresh unbound bounty stand-in matching the world's token/FD.
    function freshHook() internal returns (MockBountyHook) {
        return new MockBountyHook(address(crvUSD), address(fd));
    }

    // ---------------------------------------------------------------
    // R1 — paid listing, immediate addition, atomicity, provenance
    // ---------------------------------------------------------------

    function test_V2_PaidListingTransfersExactFeeIntoEscrow() public {
        (address pool, address gauge, address lp) = deployAuthenticatedPool(0, 0);
        uint256 payerBefore = crvUSD.balanceOf(payer);

        vm.expectEmit(true, true, true, true);
        emit GaugeListed(gauge, pool, payer, int128(0), T0, FEE, false);
        listPaid(pool, gauge, 0, 0);

        assertEq(crvUSD.balanceOf(payer), payerBefore - FEE, "unrelated caller loses FEE");
        assertEq(crvUSD.balanceOf(address(v2)), FEE, "lister gained FEE");
        assertEq(v2.totalEscrow(), FEE, "totalEscrow gained FEE");
        assertEq(crvUSD.balanceOf(address(votium)), 0, "votium gained zero");
        assertEq(crvUSD.balanceOf(address(voteMarket)), 0, "votemarket gained zero");
        assertEq(crvUSD.balanceOf(address(fd)), 0, "feeDistributor gained zero");

        ICurveGaugeListerV2.ListingV2 memory rec = v2.getListing(gauge);
        assertEq(uint256(rec.status), uint256(CurveGaugeListerV2.Status.Active), "Active");
        assertEq(rec.pool, pool, "pool");
        assertEq(rec.lpToken, lp, "lpToken");
        assertEq(rec.payer, payer, "payer");
        assertEq(rec.admissionRegistry, address(registry), "admissionRegistry");
        assertEq(rec.gaugeType, int128(0), "gaugeType");
        assertEq(rec.listingEpoch, T0, "listingEpoch floored timestamp");
        assertEq(uint256(rec.epochsReleased), 0, "epochsReleased");
        assertEq(rec.deposited, FEE, "deposited");
        assertEq(rec.remaining, FEE, "remaining");
        assertEq(rec.released, 0, "released");
        assertEq(rec.confiscated, 0, "confiscated");
        assertEq(rec.votium, address(votium), "snapshot votium");
        assertEq(rec.voteMarket, address(voteMarket), "snapshot voteMarket");
        assertEq(uint256(rec.votiumBps), 5000, "snapshot bps");
        // V2 tuple: the appended allocation fields are populated only when
        // Confiscated, so a fresh Active record keeps them zero.
        assertEq(rec.reporterReward, 0, "no reporter reward before seizure");
        assertEq(rec.fdConfiscated, 0, "no FD share before seizure");
        assertEq(rec.rewardReportId, bytes32(0), "no report id before seizure");
    }

    /// @dev exec7 (A2.3/E7.2): paid listing stamps weight 0 with a
    /// membership-only postcondition; no weight read is needed, and a lying
    /// integration still rolls the fee/record/registration back atomically.
    function test_V2_PaidListingUsesZeroWeightAndMembershipOnly() public {
        // (a) Standard controller: constant and actual add argument are both
        // zero; membership is the derived type; the exact fee was received.
        (address pool, address gauge,) = deployAuthenticatedPool(0, 0);
        uint256 payerBefore = crvUSD.balanceOf(payer);
        listPaid(pool, gauge, 0, 0);
        assertEq(v2.INITIAL_WEIGHT(), 0, "paid initial weight constant is zero");
        assertEq(controller.get_gauge_weight(gauge), 0, "actual add argument was zero");
        assertEq(controller.gauge_types(gauge), int128(0), "immediate derived-type membership");
        assertEq(controller.effectiveWeight(gauge, T0 + WEEK), 0, "scheduled point bias is the zero argument");
        assertEq(crvUSD.balanceOf(address(v2)), FEE, "exact fee receipt");
        assertEq(crvUSD.balanceOf(payer), payerBefore - FEE, "payer lost exactly FEE");

        // (b) Narrow deployment whose ONLY fault is a reverting weight getter
        // (add/membership stay functional): zero-weight paid admission succeeds
        // with no weight read anywhere on the path. auditfix001 §5: each of
        // these cores gets its own FRESH mock adapter pair AND its own fresh
        // bounty stand-in, bound after that core's construction (reusing
        // adapters bound to the default core would now fail paid-admission
        // readiness).
        MockIncentivePlatform bVotium = new MockIncentivePlatform(address(crvUSD));
        MockIncentivePlatform bVoteMarket = new MockIncentivePlatform(address(crvUSD));
        WeightReaderRevertingController badReader = new WeightReaderRevertingController(controllerDao, int128(2));
        MockBountyHook bHook = freshHook();
        CurveGaugeListerV2 noWeightLister =
            deployV2Core(address(badReader), address(bVotium), address(bVoteMarket), address(bHook));
        bindAndUnpause(noWeightLister, badReader, address(bVotium), address(bVoteMarket), bHook);
        (address poolB, address gaugeB,) = deployAuthenticatedPool(5, 0);
        vm.startPrank(payer);
        crvUSD.approve(address(noWeightLister), FEE);
        noWeightLister.listGauge(poolB, gaugeB, 0, 5);
        vm.stopPrank();
        assertEq(
            uint256(noWeightLister.getListing(gaugeB).status),
            uint256(CurveGaugeListerV2.Status.Active),
            "zero-weight admission succeeds without weight reads"
        );
        assertEq(noWeightLister.totalEscrow(), FEE, "escrow taken without a weight read");
        assertEq(badReader.addCalls(), 1, "addition still functional on the faulty reader");
        assertEq(badReader.gauge_types(gaugeB), int128(0), "membership still functional on the faulty reader");
        vm.expectRevert(WeightReaderRevertingController.WeightReadFailed.selector);
        badReader.get_gauge_weight(gaugeB);

        // (c) No-op addition: the membership postcondition rejects a lying
        // integration and the whole paid listing rolls back.
        MockIncentivePlatform cVotium = new MockIncentivePlatform(address(crvUSD));
        MockIncentivePlatform cVoteMarket = new MockIncentivePlatform(address(crvUSD));
        NoOpListingController noOp = new NoOpListingController(controllerDao, int128(2));
        MockBountyHook cHook = freshHook();
        CurveGaugeListerV2 noOpLister =
            deployV2Core(address(noOp), address(cVotium), address(cVoteMarket), address(cHook));
        bindAndUnpause(noOpLister, noOp, address(cVotium), address(cVoteMarket), cHook);
        (address poolC, address gaugeC,) = deployAuthenticatedPool(6, 0);
        uint256 payerBeforeC = crvUSD.balanceOf(payer);
        vm.startPrank(payer);
        crvUSD.approve(address(noOpLister), FEE);
        vm.expectRevert(MockListingController.GaugeNotAdded.selector);
        noOpLister.listGauge(poolC, gaugeC, 0, 6);
        vm.stopPrank();
        assertEq(
            uint256(noOpLister.getListing(gaugeC).status),
            uint256(CurveGaugeListerV2.Status.Unlisted),
            "no-op addition: no record"
        );
        assertEq(crvUSD.balanceOf(payer), payerBeforeC, "no-op addition: fee rolled back");
        assertEq(crvUSD.balanceOf(address(noOpLister)), 0, "no-op addition: no custody");

        // (d) Wrong-type addition: registered under a different type, the
        // membership read exposes the lie and everything rolls back.
        MockIncentivePlatform dVotium = new MockIncentivePlatform(address(crvUSD));
        MockIncentivePlatform dVoteMarket = new MockIncentivePlatform(address(crvUSD));
        WrongTypeListingController wrongType = new WrongTypeListingController(controllerDao, int128(2));
        MockBountyHook dHook = freshHook();
        CurveGaugeListerV2 wrongTypeLister =
            deployV2Core(address(wrongType), address(dVotium), address(dVoteMarket), address(dHook));
        bindAndUnpause(wrongTypeLister, wrongType, address(dVotium), address(dVoteMarket), dHook);
        (address poolD, address gaugeD,) = deployAuthenticatedPool(7, 0);
        uint256 payerBeforeD = crvUSD.balanceOf(payer);
        vm.startPrank(payer);
        crvUSD.approve(address(wrongTypeLister), FEE);
        vm.expectRevert(CurveGaugeListerV2.MembershipFailed.selector);
        wrongTypeLister.listGauge(poolD, gaugeD, 0, 7);
        vm.stopPrank();
        assertEq(
            uint256(wrongTypeLister.getListing(gaugeD).status),
            uint256(CurveGaugeListerV2.Status.Unlisted),
            "wrong-type addition: no record"
        );
        assertEq(crvUSD.balanceOf(payer), payerBeforeD, "wrong-type addition: fee rolled back");
        assertEq(crvUSD.balanceOf(address(wrongTypeLister)), 0, "wrong-type addition: no custody");
        // The in-flight wrong-type registration rolled back with the listing:
        // the controller no longer knows the gauge at all.
        vm.expectRevert(MockListingController.GaugeNotAdded.selector);
        wrongType.gauge_types(gaugeD);
    }

    function test_V2_ListingFailureRollsBackFeeAndRegistration() public {
        _feePullNegatives();
        _controllerFailureRollback();
        _feePullPositiveControls();
    }

    function _feePullNegatives() internal {
        // (a) insufficient FUNDS: payer holds zero but has a valid FEE
        // allowance, so the pull reaches — and fails on — the balance path
        // specifically (review1 finding 4: approve FEE for the unfunded payer
        // before the insufficient-balance expectRevert).
        poorPayerActor = actor("poorPayer");
        (negPoolA, negGaugeA,) = deployAuthenticatedPool(1, 0);
        vm.startPrank(poorPayerActor);
        crvUSD.approve(address(v2), FEE);
        vm.expectRevert();
        v2.listGauge(negPoolA, negGaugeA, 0, 1);
        vm.stopPrank();
        assertNoRecord(negGaugeA);
        assertEq(crvUSD.balanceOf(address(v2)), 0, "no fee from unfunded payer");
        assertEq(v2.totalEscrow(), 0, "no escrow from unfunded payer");

        // (b) insufficient allowance (funded but never approved).
        (negPoolB, negGaugeB,) = deployAuthenticatedPool(2, 0);
        unapprovedPayerActor = actor("unapprovedPayer");
        crvUSD.mint(unapprovedPayerActor, FEE);
        vm.prank(unapprovedPayerActor);
        vm.expectRevert();
        v2.listGauge(negPoolB, negGaugeB, 0, 2);
        assertNoRecord(negGaugeB);
        assertEq(crvUSD.balanceOf(address(v2)), 0, "no fee from unapproved payer");
    }

    function _controllerFailureRollback() internal {
        // (c) injected controller addition failure.
        (address poolC, address gaugeC,) = deployAuthenticatedPool(3, 0);
        uint256 allowanceBefore = crvUSD.allowance(payer, address(v2));
        uint256 payerBefore = crvUSD.balanceOf(payer);
        controller.setAddRevert(true);
        vm.prank(payer);
        vm.expectRevert();
        v2.listGauge(poolC, gaugeC, 0, 3);
        controller.setAddRevert(false);
        assertNoRecord(gaugeC);
        assertEq(crvUSD.balanceOf(payer), payerBefore, "fee rolled back");
        assertEq(crvUSD.allowance(payer, address(v2)), allowanceBefore, "allowance rolled back");
        assertEq(controller.addCalls(), 0, "no addition");
        assertEq(v2.totalEscrow(), 0, "no escrow");
    }

    function _feePullPositiveControls() internal {
        // Positive controls (review1 finding 4): with the missing piece
        // supplied, the identical (a)/(b) calls succeed — the earlier failures
        // were the balance/allowance paths specifically, not fixture accidents
        // or an otherwise-invalid registration.
        crvUSD.mint(poorPayerActor, FEE);
        vm.prank(poorPayerActor);
        v2.listGauge(negPoolA, negGaugeA, 0, 1);
        assertEq(
            uint256(v2.getListing(negGaugeA).status),
            uint256(CurveGaugeListerV2.Status.Active),
            "unfunded payer lists once funded"
        );
        assertEq(v2.getListing(negGaugeA).deposited, FEE, "control (a) deposited FEE");
        vm.startPrank(unapprovedPayerActor);
        crvUSD.approve(address(v2), FEE);
        v2.listGauge(negPoolB, negGaugeB, 0, 2);
        vm.stopPrank();
        assertEq(
            uint256(v2.getListing(negGaugeB).status),
            uint256(CurveGaugeListerV2.Status.Active),
            "unapproved payer lists once allowed"
        );
        assertEq(v2.getListing(negGaugeB).deposited, FEE, "control (b) deposited FEE");
        assertEq(v2.totalEscrow(), 2 * FEE, "both controls hold FEE each");
        assertEq(controller.addCalls(), 2, "both controls added");
    }

    function assertNoRecord(address gauge) internal view {
        ICurveGaugeListerV2.ListingV2 memory rec = v2.getListing(gauge);
        assertEq(uint256(rec.status), uint256(CurveGaugeListerV2.Status.Unlisted), "unlisted");
        assertEq(rec.deposited, 0, "deposited zero");
        assertEq(rec.remaining, 0, "remaining zero");
        assertEq(rec.payer, address(0), "payer zero");
    }

    function test_V2_AdmissionRejectsUnknownPoolAndSpoofGauge() public {
        // (a) registry says not registered.
        (address poolA, address gaugeA,) = deployAuthenticatedPool(0, 0);
        registry.setRegistered(poolA, 0, false);
        listPaidExpectRevert(poolA, gaugeA, 0, 0);
        assertNoRecord(gaugeA);

        // (b) registry reads revert entirely.
        (address poolB, address gaugeB,) = deployAuthenticatedPool(1, 0);
        registry.setReadsRevert(true);
        listPaidExpectRevert(poolB, gaugeB, 0, 1);
        registry.setReadsRevert(false);
        assertNoRecord(gaugeB);

        // (c) fake gauge copying the genuine LP-token return without registry
        // gauge provenance.
        (address poolC, address gaugeC, address lpC) = deployAuthenticatedPool(2, 0);
        address spoof = address(new MockGauge(lpC));
        listPaidExpectRevert(poolC, spoof, 0, 2);
        assertNoRecord(spoof);
        // the authentic one still works
        listPaid(poolC, gaugeC, 0, 2);

        // (d) mismatched handler: pool authenticated under handler 3 only.
        (address poolD, address gaugeD,) = deployAuthenticatedPool(3, 0);
        listPaidExpectRevert(poolD, gaugeD, 0, 4);
        assertNoRecord(gaugeD);

        // (e) unknown gauge index.
        (address poolE, address gaugeE,) = deployAuthenticatedPool(5, 0);
        listPaidExpectRevert(poolE, gaugeE, 7, 5);
        assertNoRecord(gaugeE);
    }

    function listPaidExpectRevert(address pool, address gauge, uint256 gaugeIndex, uint256 handlerId) internal {
        vm.prank(payer);
        vm.expectRevert();
        v2.listGauge(pool, gauge, gaugeIndex, handlerId);
    }

    function test_V2_AdmissionRejectsInvalidAddressesLpAndKilledGauge() public {
        (address pool, address gauge, address lp) = deployAuthenticatedPool(0, 0);

        listPaidExpectRevert(address(0), gauge, 0, 0);
        listPaidExpectRevert(pool, address(0), 0, 0);
        // EOA pool and EOA gauge.
        listPaidExpectRevert(actor("eoaPool"), gauge, 0, 0);
        listPaidExpectRevert(pool, actor("eoaGauge"), 0, 0);

        // LP token zero.
        (address pZ, address gZ) = (address(new MockPool()), address(new MockGauge(actor("someLp"))));
        registry.setPool(pZ, 1, address(0), _coins(address(new MockERC20(18)), address(new MockERC20(18))), 2);
        registry.setGauge(pZ, 1, 0, gZ, 0);
        listPaidExpectRevert(pZ, gZ, 0, 1);

        // LP token is an EOA.
        (address pE, address gE) = (address(new MockPool()), address(new MockGauge(actor("eoaLp"))));
        registry.setPool(pE, 2, actor("eoaLp2"), _coins(address(new MockERC20(18)), address(new MockERC20(18))), 2);
        registry.setGauge(pE, 2, 0, gE, 0);
        listPaidExpectRevert(pE, gE, 0, 2);

        // LP mismatch: registry LP differs from gauge's lp_token.
        (address pM, address gM) = (address(new MockPool()), address(new MockGauge(lp)));
        registry.setPool(
            pM, 3, address(new MockERC20(18)), _coins(address(new MockERC20(18)), address(new MockERC20(18))), 2
        );
        registry.setGauge(pM, 3, 0, gM, 0);
        listPaidExpectRevert(pM, gM, 0, 3);

        // killed at admission.
        MockGauge(gauge).setKilled(true);
        listPaidExpectRevert(pool, gauge, 0, 0);

        // invalid derived type: out of range both ways.
        (address pT, address gT,) =
            deployAuthenticatedPoolWith(4, 0, address(new MockERC20(18)), address(new MockERC20(18)), 2, int128(7));
        listPaidExpectRevert(pT, gT, 0, 4);
        (address pU, address gU,) =
            deployAuthenticatedPoolWith(5, 0, address(new MockERC20(18)), address(new MockERC20(18)), 2, int128(-1));
        listPaidExpectRevert(pU, gU, 0, 5);
        // control: a fresh valid fixture still lists after the negatives.
        (address poolW, address gaugeW,) = deployAuthenticatedPool(9, 0);
        listPaid(poolW, gaugeW, 0, 9);
        assertTrue(v2.getListing(gaugeW).status == uint8(CurveGaugeListerV2.Status.Active), "control listed");
    }

    function test_V2_AdmissionValidatesCoinCountAndAddresses() public {
        // n below 2.
        (address p1, address g1) = deployCoinPool(0, 1, address(new MockERC20(18)), address(new MockERC20(18)));
        listPaidExpectRevert(p1, g1, 0, 0);
        // n above the fixed array bound.
        (address p9, address g9) = deployCoinPool(1, 9, address(new MockERC20(18)), address(new MockERC20(18)));
        listPaidExpectRevert(p9, g9, 0, 1);
        // n == 8 accepted under the default bound (all eight slots live).
        (address p8, address g8) = deployFullCoinPool(2, 8);
        listPaid(p8, g8, 0, 2);
        // n above a narrowed owner config.
        vm.prank(daoOwner);
        v2.setAdmissionConfig(CurveGaugeListerV2.AdmissionConfig(address(registry), 4));
        (address p6, address g6) = deployFullCoinPool(3, 6);
        listPaidExpectRevert(p6, g6, 0, 3);
        vm.prank(daoOwner);
        v2.setAdmissionConfig(CurveGaugeListerV2.AdmissionConfig(address(registry), 8));

        // duplicate coins.
        MockERC20 dup = new MockERC20(18);
        (address pd, address gd) = deployCoinPool(4, 2, address(dup), address(dup));
        listPaidExpectRevert(pd, gd, 0, 4);
        // zero coin inside n.
        (address pz, address gz) = deployCoinPool(5, 2, address(new MockERC20(18)), address(0));
        listPaidExpectRevert(pz, gz, 0, 5);
        // EOA coin.
        (address pe, address ge) = deployCoinPool(6, 2, address(new MockERC20(18)), actor("eoaCoin"));
        listPaidExpectRevert(pe, ge, 0, 6);
        // invalid indices.
        listPaidExpectRevert(p8, g8, 0, 10);
        (address pBig, address gBig) = deployCoinPool(7, 2, address(new MockERC20(18)), address(new MockERC20(18)));
        listPaidExpectRevert(pBig, gBig, 10, 7);
        _indexBoundRejections(pBig, gBig);

        // padded zero slots after n are ignored (fixture keeps slots 2..7 zero).
        (address pp, address pg) = deployCoinPool(8, 2, address(new MockERC20(18)), address(new MockERC20(18)));
        listPaid(pp, pg, 0, 8);
    }

    function deployCoinPool(uint256 handlerId, uint256 nCoins, address c0, address c1)
        internal
        returns (address pool, address gauge)
    {
        address lp = address(new MockERC20(18));
        pool = address(new MockPool());
        gauge = address(new MockGauge(lp));
        registry.setPool(pool, handlerId, lp, _coins(c0, c1), nCoins);
        registry.setGauge(pool, handlerId, 0, gauge, 0);
    }

    /// @dev review1 finding 4: fresh records authenticated UNDER the
    /// out-of-range indices, so only the product's explicit bound can reject;
    /// the rejection is isolated to IndexOutOfRange with full rollback.
    function _indexBoundRejections(address pBig, address gBig) internal {
        (address pH, address gH) = deployCoinPool(10, 2, address(new MockERC20(18)), address(new MockERC20(18)));
        expectIndexOutOfRangeReject(pH, gH, 0, 10);
        registry.setGauge(pBig, 7, 10, gBig, 0); // authenticate at index 10
        expectIndexOutOfRangeReject(pBig, gBig, 10, 7);
    }

    /// @dev List must be rejected by the plan's explicit index bound
    /// (CurveGaugeListerV2.IndexOutOfRange), never incidentally, with a full
    /// rollback of fee, escrow and controller additions.
    function expectIndexOutOfRangeReject(address pool, address gauge, uint256 gaugeIndex, uint256 handlerId) internal {
        uint256 payerBefore = crvUSD.balanceOf(payer);
        uint256 listerBefore = crvUSD.balanceOf(address(v2));
        uint256 escrowBefore = v2.totalEscrow();
        uint256 addsBefore = controller.addCalls();
        vm.prank(payer);
        vm.expectRevert(abi.encodeWithSelector(CurveGaugeListerV2.IndexOutOfRange.selector));
        v2.listGauge(pool, gauge, gaugeIndex, handlerId);
        assertNoRecord(gauge);
        assertEq(crvUSD.balanceOf(payer), payerBefore, "no fee on index rejection");
        assertEq(crvUSD.balanceOf(address(v2)), listerBefore, "no custody gain on index rejection");
        assertEq(v2.totalEscrow(), escrowBefore, "no liability change on index rejection");
        assertEq(controller.addCalls(), addsBefore, "no addition on index rejection");
    }

    /// @dev Pool whose FIRST n slots all hold distinct live ERC20s (fixtures
    /// for the valid full-width arities).
    function deployFullCoinPool(uint256 handlerId, uint256 n) internal returns (address pool, address gauge) {
        address lp = address(new MockERC20(18));
        pool = address(new MockPool());
        gauge = address(new MockGauge(lp));
        address[8] memory coins;
        for (uint256 i = 0; i < n; ++i) {
            coins[i] = address(new MockERC20(18));
        }
        registry.setPool(pool, handlerId, lp, coins, n);
        registry.setGauge(pool, handlerId, 0, gauge, 0);
    }

    function test_V2_AdmissionAllowsNativeCoinAndUnfundedPool() public {
        // native sentinel + arbitrary ERC20 coin.
        (address pN, address gN, address lpN) =
            deployAuthenticatedPoolWith(0, 0, NATIVE, address(new MockERC20(18)), 2, 0);
        listPaid(pN, gN, 0, 0);
        assertTrue(v2.getListing(gN).status == uint8(CurveGaugeListerV2.Status.Active), "native coin admitted");

        // zero-liquidity/zero-supply LP fixture (no mint, no reserves).
        assertEq(IERC20Minimal(lpN).balanceOf(address(0)), 0, "lp unused");
        (address pZ, address gZ, address lpZ) = deployAuthenticatedPool(1, 0);
        assertEq(IERC20Minimal(lpZ).balanceOf(pZ), 0, "pool holds no LP");
        listPaid(pZ, gZ, 0, 1);
        assertTrue(v2.getListing(gZ).status == uint8(CurveGaugeListerV2.Status.Active), "unfunded pool admitted");

        // pool that IS its LP token: MockERC20 used as both addresses.
        MockERC20 selfPool = new MockERC20(18);
        address selfGauge = address(new MockGauge(address(selfPool)));
        registry.setPool(address(selfPool), 2, address(selfPool), _coins(address(new MockERC20(18)), NATIVE), 2);
        registry.setGauge(address(selfPool), 2, 0, selfGauge, 1);
        listPaid(address(selfPool), selfGauge, 0, 2);
        assertEq(v2.getListing(selfGauge).gaugeType, int128(1), "pool==LP admitted");

        // unrelated payer (no relationship to pool/gauge/lister) with only the
        // fee: no voter-overlap check exists to block it.
        address randomPayer = actor("randomPayer");
        (address pR, address gR) = deployCoinPool(3, 2, address(new MockERC20(18)), address(new MockERC20(18)));
        crvUSD.mint(randomPayer, FEE);
        vm.startPrank(randomPayer);
        crvUSD.approve(address(v2), FEE);
        v2.listGauge(pR, gR, 0, 3);
        vm.stopPrank();
        assertEq(v2.getListing(gR).payer, randomPayer, "unrelated lister accepted");
    }

    function test_V2_DoubleListingRejectedAcrossAllPathsAndTerminalStates() public {
        // paid -> paid and paid -> DAO on one gauge.
        (address poolA, address gaugeA,) = deployAuthenticatedPool(0, 0);
        listPaid(poolA, gaugeA, 0, 0);
        uint256 payerBefore = crvUSD.balanceOf(payer);
        listPaidExpectRevert(poolA, gaugeA, 0, 0);
        listDaoExpectRevert(poolA, gaugeA, 0, 0, 0);
        assertEq(crvUSD.balanceOf(payer), payerBefore, "no second fee (paid repeats)");
        assertEq(controller.addCalls(), 1, "no second addition");

        // DAO -> paid and DAO -> DAO on another gauge.
        (address poolB, address gaugeB,) = deployAuthenticatedPool(1, 0);
        listDao(poolB, gaugeB, 0, 1, 0);
        listPaidExpectRevert(poolB, gaugeB, 0, 1);
        listDaoExpectRevert(poolB, gaugeB, 0, 1, 3);
        assertEq(controller.addCalls(), 2, "no additions from rejected paths");

        // After exhaustion: re-listing both ways is rejected.
        (address poolC, address gaugeC,) = deployAuthenticatedPool(2, 0);
        listPaid(poolC, gaugeC, 0, 2);
        vm.warp(T0 + 4 * WEEK);
        (uint256 r, uint256 c) = v2.checkpoint(gaugeC);
        assertEq(r, FEE, "exhausted");
        assertEq(c, 0, "no confiscation");
        listPaidExpectRevert(poolC, gaugeC, 0, 2);
        listDaoExpectRevert(poolC, gaugeC, 0, 2, 0);

        // After confiscation: terminal, never re-admittable.
        (address poolD, address gaugeD,) = deployAuthenticatedPool(3, 0);
        listPaid(poolD, gaugeD, 0, 3);
        killGauge(gaugeD);
        v2.confiscate(gaugeD);
        listPaidExpectRevert(poolD, gaugeD, 0, 3);
        listDaoExpectRevert(poolD, gaugeD, 0, 3, 0);

        // Externally controller-listed gauge: the controller's permanent
        // registry rejects it on both paths.
        (address poolE, address gaugeE,) = deployAuthenticatedPool(4, 0);
        vm.prank(controllerDao);
        controller.add_gauge(gaugeE, int128(0), 3);
        uint256 payerBeforeE = crvUSD.balanceOf(payer);
        listPaidExpectRevert(poolE, gaugeE, 0, 4);
        listDaoExpectRevert(poolE, gaugeE, 0, 4, 0);
        assertEq(crvUSD.balanceOf(payer), payerBeforeE, "no fee for controller-listed rejection");
    }

    function listDaoExpectRevert(address pool, address gauge, uint256 gaugeIndex, uint256 handlerId, uint256 weight)
        internal
    {
        vm.prank(daoOwner);
        vm.expectRevert();
        v2.listGaugeNoEscrow(pool, gauge, gaugeIndex, handlerId, weight);
    }

    function test_V2_DistinctAuthenticatedGaugesForSamePoolCanList() public {
        address lp = address(new MockERC20(18));
        address pool = address(new MockPool());
        address gauge1 = address(new MockGauge(lp));
        address gauge2 = address(new MockGauge(lp));
        registry.setPool(pool, 0, lp, _coins(address(new MockERC20(18)), address(new MockERC20(18))), 2);
        registry.setGauge(pool, 0, 0, gauge1, 0);
        registry.setGauge(pool, 0, 1, gauge2, 1);

        listPaid(pool, gauge1, 0, 0);
        listPaid(pool, gauge2, 1, 0);

        assertEq(v2.totalEscrow(), 2 * FEE, "both fees held");
        assertEq(crvUSD.balanceOf(address(v2)), 2 * FEE, "both fees in");
        assertEq(uint256(v2.getListing(gauge1).status), uint256(CurveGaugeListerV2.Status.Active), "g1 active");
        assertEq(uint256(v2.getListing(gauge2).status), uint256(CurveGaugeListerV2.Status.Active), "g2 active");
        assertEq(v2.getListing(gauge2).gaugeType, int128(1), "per-gauge type");
    }

    // ---------------------------------------------------------------
    // R4 — DAO no-escrow path
    // ---------------------------------------------------------------

    function test_V2_DaoZeroFeeListingNeverDrips() public {
        // Owner holds no fee tokens at all: zero balance, zero allowance.
        assertEq(crvUSD.balanceOf(daoOwner), 0, "owner unfunded");
        assertEq(crvUSD.allowance(daoOwner, address(v2)), 0, "owner no allowance");

        // A stranger cannot choose the free path (absorbed from the retired
        // standalone non-owner test).
        (address poolN, address gaugeN,) = deployAuthenticatedPool(9, 0);
        vm.prank(stranger);
        vm.expectRevert();
        v2.listGaugeNoEscrow(poolN, gaugeN, 0, 9, 0);
        assertNoRecord(gaugeN);
        assertEq(controller.addCalls(), 0, "no addition from the free-attempt");

        (address poolA, address gaugeA,) = deployAuthenticatedPool(0, 0);
        listDao(poolA, gaugeA, 0, 0, 0);
        (address poolB, address gaugeB,) = deployAuthenticatedPool(1, 0);
        listDao(poolB, gaugeB, 0, 1, 3);

        ICurveGaugeListerV2.ListingV2 memory recA = v2.getListing(gaugeA);
        assertEq(uint256(recA.status), uint256(CurveGaugeListerV2.Status.DaoExempt), "DaoExempt");
        assertEq(recA.payer, address(0), "free payer zero");
        assertEq(recA.deposited, 0, "deposited zero");
        assertEq(recA.remaining, 0, "remaining zero");
        assertEq(recA.released, 0, "released zero");
        assertEq(recA.confiscated, 0, "confiscated zero");
        assertEq(uint256(recA.epochsReleased), 0, "epochsReleased zero");
        assertEq(recA.votium, address(0), "votium snapshot zero");
        assertEq(recA.voteMarket, address(0), "voteMarket snapshot zero");
        assertEq(uint256(recA.votiumBps), 0, "bps snapshot zero");
        assertEq(controller.get_gauge_weight(gaugeA), 0, "zero initial weight valid on this path");
        assertEq(controller.get_gauge_weight(gaugeB), 3, "nonzero weight stored");

        uint256 listerBefore = crvUSD.balanceOf(address(v2));
        vm.warp(T0 + 10 * WEEK);
        (uint256 r, uint256 c) = v2.checkpoint(gaugeA);
        assertEq(r + c, 0, "never drips");
        (r, c) = v2.checkpoint(gaugeB);
        assertEq(r + c, 0, "never drips (nonzero weight)");
        assertEq(v2.confiscate(gaugeB), 0, "no confiscation on DAO record");
        killGauge(gaugeA);
        // still a no-op after a DAO kill attempt on the DAO-exempt record
        (r, c) = v2.checkpoint(gaugeA);
        assertEq(r + c, 0, "still no-op after kill attempt");

        assertEq(crvUSD.balanceOf(address(v2)), listerBefore, "no token movement");
        assertEq(crvUSD.balanceOf(address(votium)) + crvUSD.balanceOf(address(voteMarket)), 0, "no deposits");
        assertEq(votium.depositCount() + voteMarket.depositCount(), 0, "no receipts");
        assertEq(crvUSD.balanceOf(address(fd)), 0, "no confiscation money");
        assertEq(v2.epochsElapsed(gaugeA), 0, "epochsElapsed 0 for DaoExempt");
        assertEq(v2.releasable(gaugeA), 0, "releasable 0 for DaoExempt");
        assertEq(v2.totalEscrow(), 0, "no escrow liability");
        assertEq(uint256(v2.getListing(gaugeA).status), uint256(CurveGaugeListerV2.Status.DaoExempt), "lifetime status");

        // review1 finding 3: lifetime re-read of ALL financial/platform fields
        // after the warps/kills/checkpoints, not just at creation.
        recA = v2.getListing(gaugeA);
        assertEq(uint256(recA.status), uint256(CurveGaugeListerV2.Status.DaoExempt), "lifetime DaoExempt status");
        assertEq(recA.payer, address(0), "lifetime payer zero");
        assertEq(recA.deposited, 0, "lifetime deposited zero");
        assertEq(recA.remaining, 0, "lifetime remaining zero");
        assertEq(recA.released, 0, "lifetime released zero");
        assertEq(recA.confiscated, 0, "lifetime confiscated zero");
        assertEq(uint256(recA.epochsReleased), 0, "lifetime counter zero");
        assertEq(recA.votium, address(0), "lifetime votium zero");
        assertEq(recA.voteMarket, address(0), "lifetime voteMarket zero");
        assertEq(uint256(recA.votiumBps), 0, "lifetime bps zero");
        assertEq(recA.reporterReward, 0, "lifetime reporter reward zero");
        assertEq(recA.fdConfiscated, 0, "lifetime FD share zero");
        assertEq(recA.rewardReportId, bytes32(0), "lifetime report id zero");
        ICurveGaugeListerV2.ListingV2 memory recBChk = v2.getListing(gaugeB);
        assertEq(recBChk.deposited + recBChk.remaining + recBChk.released + recBChk.confiscated, 0, "lifetime B zero");
        assertEq(uint256(recBChk.epochsReleased), 0, "lifetime B counter zero");
    }

    // ---------------------------------------------------------------
    // R5 — pause, configuration, custody, registry, ownership, drain surface
    // ---------------------------------------------------------------

    function test_V2_OwnerPauseOnlyBlocksPermissionlessAdmission() public {
        // V2 starts PAUSED: an unwired fresh core must report paused=true and
        // refuse paid admission until the owner completes wiring.
        MockListingController unwiredCtl = new MockListingController(controllerDao, int128(2));
        MockIncentivePlatform unwiredVotium = new MockIncentivePlatform(address(crvUSD));
        MockIncentivePlatform unwiredVoteMarket = new MockIncentivePlatform(address(crvUSD));
        MockBountyHook unwiredHook = freshHook();
        CurveGaugeListerV2 freshCore =
            deployV2Core(address(unwiredCtl), address(unwiredVotium), address(unwiredVoteMarket), address(unwiredHook));
        assertTrue(freshCore.paused(), "fresh V2 starts paused before unpause");

        (address poolLive, address gaugeLive,) = deployAuthenticatedPool(0, 0);
        listPaid(poolLive, gaugeLive, 0, 0);
        (address poolKill, address gaugeKill,) = deployAuthenticatedPool(1, 0);
        listPaid(poolKill, gaugeKill, 0, 1);

        vm.prank(stranger);
        vm.expectRevert();
        v2.setPaused(true);
        assertTrue(v2.paused() == false, "stranger cannot pause");

        vm.prank(daoOwner);
        v2.setPaused(true);
        assertTrue(v2.paused(), "paused");

        // paid admission blocked
        (address poolC, address gaugeC) = deployCoinPool(3, 2, address(new MockERC20(18)), address(new MockERC20(18)));
        listPaidExpectRevert(poolC, gaugeC, 0, 3);

        // DAO-free addition continues
        (address poolD, address gaugeD,) = deployAuthenticatedPool(4, 0);
        listDao(poolD, gaugeD, 0, 4, 2);
        assertEq(
            uint256(v2.getListing(gaugeD).status), uint256(CurveGaugeListerV2.Status.DaoExempt), "dao path while paused"
        );

        // releases continue
        vm.warp(T0 + WEEK);
        (uint256 r,) = v2.checkpoint(gaugeLive);
        assertEq(r, QUARTER, "release while paused");

        // zero-weight confiscation continues
        killGauge(gaugeKill);
        uint256 seized = v2.confiscate(gaugeKill);
        assertEq(seized, FEE, "confiscation while paused");
        assertEq(crvUSD.balanceOf(address(fd)), FEE, "distributor paid while paused");

        // unpause restores admission
        vm.prank(daoOwner);
        v2.setPaused(false);
        listPaid(poolC, gaugeC, 0, 3);
        assertEq(uint256(v2.getListing(gaugeC).status), uint256(CurveGaugeListerV2.Status.Active), "unpaused admission");
    }

    function test_V2_OnlyOwnerCanConfigureAdmissionAndPlatforms() public {
        CurveGaugeListerV2.AdmissionConfig memory goodAdmission =
            CurveGaugeListerV2.AdmissionConfig(address(registry), 8);
        CurveGaugeListerV2.PlatformConfig memory goodPlatforms =
            CurveGaugeListerV2.PlatformConfig(address(votium), address(voteMarket), 5000);

        // unauthorized
        vm.prank(stranger);
        vm.expectRevert();
        v2.setAdmissionConfig(goodAdmission);
        vm.prank(stranger);
        vm.expectRevert();
        v2.setPlatformConfig(goodPlatforms);

        // invalid admission configs reject atomically
        vm.startPrank(daoOwner);
        vm.expectRevert();
        v2.setAdmissionConfig(CurveGaugeListerV2.AdmissionConfig(address(registry), 1));
        vm.expectRevert();
        v2.setAdmissionConfig(CurveGaugeListerV2.AdmissionConfig(address(registry), 9));
        vm.expectRevert();
        v2.setAdmissionConfig(CurveGaugeListerV2.AdmissionConfig(address(0), 8));
        vm.expectRevert();
        v2.setAdmissionConfig(CurveGaugeListerV2.AdmissionConfig(actor("eoaRegistry"), 8));
        vm.stopPrank();
        CurveGaugeListerV2.AdmissionConfig memory stillAdm = v2.getAdmissionConfig();
        assertEq(stillAdm.registry, address(registry), "admission atomic");
        assertEq(uint256(stillAdm.maxCoins), 8, "maxCoins atomic");

        // valid admission change affects new admissions only
        (address poolNew,) = deployCoinPool(5, 2, address(new MockERC20(18)), address(new MockERC20(18)));
        (, address gaugeNew, address lpNew) = deployAuthenticatedPool(6, 0);
        registry2.setPool(poolNew, 6, lpNew, _coins(address(new MockERC20(18)), address(new MockERC20(18))), 2);
        registry2.setGauge(poolNew, 6, 0, gaugeNew, 0);
        vm.prank(daoOwner);
        v2.setAdmissionConfig(CurveGaugeListerV2.AdmissionConfig(address(registry2), 8));
        assertEq(v2.getAdmissionConfig().registry, address(registry2), "config stored");
        // the old-registry pool no longer admits
        (address poolOld, address gaugeOld) =
            deployCoinPool(7, 2, address(new MockERC20(18)), address(new MockERC20(18)));
        listPaidExpectRevert(poolOld, gaugeOld, 0, 7);
        // the registry2-authenticated gauge does
        listPaid(poolNew, gaugeNew, 0, 6);

        // invalid platform configs reject atomically
        vm.startPrank(daoOwner);
        vm.expectRevert();
        v2.setPlatformConfig(CurveGaugeListerV2.PlatformConfig(address(votium), address(voteMarket), 10001));
        vm.expectRevert();
        v2.setPlatformConfig(CurveGaugeListerV2.PlatformConfig(address(0), address(voteMarket), 5000));
        vm.expectRevert();
        v2.setPlatformConfig(CurveGaugeListerV2.PlatformConfig(actor("eoaVotium"), address(voteMarket), 5000));
        MockIncentivePlatform wrongToken = new MockIncentivePlatform(address(otherToken));
        vm.expectRevert();
        v2.setPlatformConfig(CurveGaugeListerV2.PlatformConfig(address(wrongToken), address(voteMarket), 5000));
        // review1 finding 9 (absorbed from the retired setter-only test): a
        // mixed split onto identical endpoints is refused by the shared
        // validator; every aliased combination rejects atomically.
        vm.expectRevert(abi.encodeWithSelector(CurveGaugeListerV2.BadPlatformConfig.selector));
        v2.setPlatformConfig(CurveGaugeListerV2.PlatformConfig(address(votium), address(votium), 5000));
        vm.expectRevert(abi.encodeWithSelector(CurveGaugeListerV2.BadPlatformConfig.selector));
        v2.setPlatformConfig(CurveGaugeListerV2.PlatformConfig(address(voteMarket), address(voteMarket), 1));
        vm.expectRevert(abi.encodeWithSelector(CurveGaugeListerV2.BadPlatformConfig.selector));
        v2.setPlatformConfig(CurveGaugeListerV2.PlatformConfig(address(votium), address(votium), 9999));
        vm.stopPrank();
        CurveGaugeListerV2.PlatformConfig memory stillPlat = v2.getPlatformConfig();
        assertEq(stillPlat.votium, address(votium), "platform atomic");
        assertEq(stillPlat.voteMarket, address(voteMarket), "platform atomic 2");
        assertEq(uint256(stillPlat.votiumBps), 5000, "platform atomic 3");

        // zero-share side may be the zero address
        vm.prank(daoOwner);
        v2.setPlatformConfig(CurveGaugeListerV2.PlatformConfig(address(0), address(voteMarket), 0));
        assertEq(uint256(v2.getPlatformConfig().votiumBps), 0, "zero-share accepted");
        vm.prank(daoOwner);
        v2.setPlatformConfig(CurveGaugeListerV2.PlatformConfig(address(votium), address(0), 10000));
        assertEq(v2.getPlatformConfig().voteMarket, address(0), "zero-share complement accepted");
        // A single-share config keeps even an aliased never-called side
        // acceptable (absorbed from the retired setter-only test).
        vm.prank(daoOwner);
        v2.setPlatformConfig(CurveGaugeListerV2.PlatformConfig(address(votium), address(votium), 0));
        assertEq(v2.getPlatformConfig().votium, address(votium), "aliased single share accepted");
    }

    // review1 finding 9: a mixed split onto identical endpoints makes the
    // frozen listing unreleasable (the shared adapter rejects the second
    // same-gauge/same-epoch deposit). The shared validator rejects it at
    // configuration time; 0/10000 single-share configs keep working.
    //
    // §1.2 additions for V2: chain pin, code at bounty, bounty config token/FD
    // match and the compatible write-once lister binding are constructor
    // negatives on top of every retained baseline case.
    function test_V2_ConstructorRejectsAliasedEndpoints() public {
        CurveGaugeListerV2.PlatformConfig memory admVotiumAlias =
            CurveGaugeListerV2.PlatformConfig(address(votium), address(votium), 5000);
        CurveGaugeListerV2.PlatformConfig memory admVoteMarketAlias =
            CurveGaugeListerV2.PlatformConfig(address(voteMarket), address(voteMarket), 1);
        CurveGaugeListerV2.PlatformConfig memory admVotiumAlias9999 =
            CurveGaugeListerV2.PlatformConfig(address(votium), address(votium), 9999);

        // Hooks are created BEFORE each expectation: a CREATE from the test
        // contract would otherwise consume the armed expectRevert.
        MockBountyHook aliasHookA = freshHook();
        vm.expectRevert(abi.encodeWithSelector(CurveGaugeListerV2.BadPlatformConfig.selector));
        newV2With(admVotiumAlias, address(aliasHookA));
        MockBountyHook aliasHookB = freshHook();
        vm.expectRevert(abi.encodeWithSelector(CurveGaugeListerV2.BadPlatformConfig.selector));
        newV2With(admVoteMarketAlias, address(aliasHookB));
        MockBountyHook aliasHookC = freshHook();
        vm.expectRevert(abi.encodeWithSelector(CurveGaugeListerV2.BadPlatformConfig.selector));
        newV2With(admVotiumAlias9999, address(aliasHookC));

        // Single-share constructions keep working, zero address allowed unused.
        MockBountyHook soloVmHook = freshHook();
        CurveGaugeListerV2 soloVm =
            newV2With(CurveGaugeListerV2.PlatformConfig(address(0), address(voteMarket), 0), address(soloVmHook));
        assertEq(soloVm.owner(), daoOwner, "0-bps single-share constructor ok");
        MockBountyHook soloVotiumHook = freshHook();
        CurveGaugeListerV2 soloVotium =
            newV2With(CurveGaugeListerV2.PlatformConfig(address(votium), address(0), 10000), address(soloVotiumHook));
        assertEq(soloVotium.owner(), daoOwner, "10000-bps single-share constructor ok");

        // ---- §1.2 V2-only constructor negatives (added, none removed) ----

        // (n1) wrong chain: the pinned mainnet-only deployment refuses chain 5.
        MockBountyHook chainHook = freshHook();
        vm.chainId(5);
        vm.expectRevert(abi.encodeWithSelector(CurveGaugeListerV2.WrongChain.selector));
        newV2With(CurveGaugeListerV2.PlatformConfig(address(votium), address(voteMarket), 5000), address(chainHook));
        vm.chainId(1);
        // control: the identical construction succeeds again on chain 1.
        MockBountyHook restoredHook = freshHook();
        CurveGaugeListerV2 backOnChain = newV2With(
            CurveGaugeListerV2.PlatformConfig(address(votium), address(voteMarket), 5000), address(restoredHook)
        );
        assertEq(backOnChain.owner(), daoOwner, "chain restored");

        // (n2) zero-code bounty: no code at the immutable reverse pointer.
        vm.expectRevert(abi.encodeWithSelector(CurveGaugeListerV2.BadBounty.selector));
        newV2With(CurveGaugeListerV2.PlatformConfig(address(votium), address(voteMarket), 5000), address(0));
        vm.expectRevert(abi.encodeWithSelector(CurveGaugeListerV2.BadBounty.selector));
        newV2With(CurveGaugeListerV2.PlatformConfig(address(votium), address(voteMarket), 5000), actor("eoaBounty"));

        // (n3) bounty config mismatch on the fee token.
        MockBountyHook wrongTokenBounty = new MockBountyHook(address(otherToken), address(fd));
        vm.expectRevert(abi.encodeWithSelector(CurveGaugeListerV2.BadBounty.selector));
        newV2With(
            CurveGaugeListerV2.PlatformConfig(address(votium), address(voteMarket), 5000), address(wrongTokenBounty)
        );

        // (n4) bounty config mismatch on the fee distributor (both the config
        // tuple and the direct feeDistributor() getter are checked).
        MockFeeDistributor otherFd = new MockFeeDistributor(address(crvUSD), fdAdmin, T0);
        MockBountyHook wrongFdBounty = new MockBountyHook(address(crvUSD), address(otherFd));
        vm.expectRevert(abi.encodeWithSelector(CurveGaugeListerV2.BadBounty.selector));
        newV2With(CurveGaugeListerV2.PlatformConfig(address(votium), address(voteMarket), 5000), address(wrongFdBounty));

        // (n5) already-bound foreign lister: the write-once binding must be
        // zero or this address, never another lister.
        MockBountyHook boundElsewhere = freshHook();
        boundElsewhere.bindLister(address(votium)); // some other contract
        vm.expectRevert(abi.encodeWithSelector(CurveGaugeListerV2.BadBounty.selector));
        newV2With(
            CurveGaugeListerV2.PlatformConfig(address(votium), address(voteMarket), 5000), address(boundElsewhere)
        );

        // (n6) control: the default world's own reciprocal binding is accepted
        // (the hook is already bound to `v2`, so a clone for `v2` itself is the
        // only re-bind this stand-in would refuse — the fresh unbound hook is
        // the accepted construction path).
        MockBountyHook accepted = freshHook();
        CurveGaugeListerV2 constructed =
            newV2With(CurveGaugeListerV2.PlatformConfig(address(votium), address(voteMarket), 5000), address(accepted));
        assertEq(constructed.bounty(), address(accepted), "bounty immutable recorded");
        assertEq(constructed.paused(), true, "constructed V2 starts paused");
    }

    function test_V2_PlatformChangesCannotRedirectExistingEscrow() public {
        (address poolA, address gaugeA,) = deployAuthenticatedPool(0, 0);
        listPaid(poolA, gaugeA, 0, 0);

        MockIncentivePlatform votium2 = new MockIncentivePlatform(address(crvUSD));
        MockIncentivePlatform voteMarket2 = new MockIncentivePlatform(address(crvUSD));
        uint256 listerBefore = crvUSD.balanceOf(address(v2));
        vm.prank(daoOwner);
        v2.setPlatformConfig(CurveGaugeListerV2.PlatformConfig(address(votium2), address(voteMarket2), 2500));
        assertEq(crvUSD.balanceOf(address(v2)), listerBefore, "setter moved no tokens");
        assertEq(crvUSD.allowance(address(v2), address(votium)), 0, "setter created no allowance");
        assertEq(crvUSD.allowance(address(v2), address(voteMarket)), 0, "setter created no allowance 2");
        assertEq(crvUSD.allowance(address(v2), address(votium2)), 0, "setter created no allowance 3");

        vm.warp(T0 + WEEK);
        (uint256 r,) = v2.checkpoint(gaugeA);
        assertEq(r, QUARTER, "old escrow releases");
        // Original endpoints and original 5000/5000 split, not the new config.
        (uint256 amtA, uint256 execA, bytes32 receiptA) = votium.getDeposit(gaugeA, T0 + WEEK);
        assertEq(amtA, QUARTER / 2, "old votium share");
        assertTrue(execA == T0 + WEEK, "execution epoch");
        assertTrue(receiptA != bytes32(0), "receipt A");
        (, uint256 execB, bytes32 receiptB) = voteMarket.getDeposit(gaugeA, T0 + WEEK);
        assertTrue(receiptB != bytes32(0) && execB == T0 + WEEK, "old voteMarket share");
        assertEq(crvUSD.balanceOf(address(votium2)), 0, "new votium untouched");
        assertEq(crvUSD.balanceOf(address(voteMarket2)), 0, "new voteMarket untouched");

        // New listing pays the NEW defaults/split (and, under V2, only admits
        // once those new endpoints are actually bound to this core).
        votium2.setLister(address(v2));
        voteMarket2.setLister(address(v2));
        (address poolB, address gaugeB,) = deployAuthenticatedPool(1, 0);
        listPaid(poolB, gaugeB, 0, 1);
        assertEq(v2.getListing(gaugeB).votium, address(votium2), "new snapshot");
        assertEq(uint256(v2.getListing(gaugeB).votiumBps), 2500, "new bps snapshot");

        vm.warp(T0 + 2 * WEEK);
        (uint256 rB,) = v2.checkpoint(gaugeB);
        assertEq(rB, QUARTER, "new gauge releases");
        assertEq(crvUSD.balanceOf(address(votium2)), (QUARTER * 2500) / 10000, "new split votium");
        assertEq(crvUSD.balanceOf(address(voteMarket2)), QUARTER - (QUARTER * 2500) / 10000, "new split votemarket");
    }

    function test_V2_AdmissionChangeDoesNotRevalidateExistingEscrow() public {
        (address poolA, address gaugeA,) = deployAuthenticatedPool(0, 0);
        listPaid(poolA, gaugeA, 0, 0);

        // Swap to a registry that does not know poolA at all.
        vm.prank(daoOwner);
        v2.setAdmissionConfig(CurveGaugeListerV2.AdmissionConfig(address(registry2), 8));

        vm.warp(T0 + WEEK);
        (uint256 r,) = v2.checkpoint(gaugeA);
        assertEq(r, QUARTER, "existing escrow settles under dead registry");
        assertEq(crvUSD.balanceOf(address(votium)) + crvUSD.balanceOf(address(voteMarket)), QUARTER, "funded");

        // New listings follow the new policy.
        (address poolB, address gaugeB,) = deployAuthenticatedPool(1, 0);
        listPaidExpectRevert(poolB, gaugeB, 0, 1);
        (address poolC, address gaugeC, address lpC) = deployAuthenticatedPool(2, 0);
        registry2.setPool(poolC, 0, lpC, _coins(address(new MockERC20(18)), address(new MockERC20(18))), 2);
        registry2.setGauge(poolC, 0, 0, gaugeC, 0);
        listPaid(poolC, gaugeC, 0, 0);
        assertEq(v2.getListing(gaugeC).admissionRegistry, address(registry2), "new policy recorded");
    }

    function test_V2_TwoStepOwnershipTransfer() public {
        assertEq(v2.owner(), daoOwner, "explicit owner, not deployer");
        assertTrue(v2.owner() != address(this), "no silent deployer privilege");
        assertTrue(v2.pendingOwner() == address(0), "no pending initially");

        address newOwner = actor("nextDao");
        vm.prank(stranger);
        vm.expectRevert();
        v2.transferOwnership(newOwner);
        vm.prank(daoOwner);
        vm.expectRevert();
        v2.transferOwnership(address(0));

        vm.prank(daoOwner);
        vm.expectEmit(true, true, false, false);
        emit OwnershipTransferStarted(daoOwner, newOwner);
        v2.transferOwnership(newOwner);
        assertEq(v2.owner(), daoOwner, "owner unchanged until acceptance");
        assertEq(v2.pendingOwner(), newOwner, "nonzero pending owner");

        // Old owner keeps rights pre-acceptance but cannot be the accepter.
        vm.prank(daoOwner);
        v2.setPaused(true);
        assertTrue(v2.paused(), "old owner retains rights until accept");
        vm.prank(daoOwner);
        v2.setPaused(false);

        vm.prank(stranger);
        vm.expectRevert();
        v2.acceptOwnership();
        vm.prank(newOwner);
        vm.expectEmit(true, true, false, false);
        emit OwnershipTransferred(daoOwner, newOwner);
        v2.acceptOwnership();
        assertEq(v2.owner(), newOwner, "new owner active");
        assertEq(v2.pendingOwner(), address(0), "pending cleared");

        vm.prank(daoOwner);
        vm.expectRevert();
        v2.setPaused(true);
        vm.prank(newOwner);
        v2.setPaused(true);
        assertTrue(v2.paused(), "new owner configures");
        // The old owner cannot list for free either.
        (address pool, address gauge,) = deployAuthenticatedPool(3, 0);
        vm.prank(daoOwner);
        vm.expectRevert();
        v2.listGaugeNoEscrow(pool, gauge, 0, 3, 0);
        vm.prank(newOwner);
        v2.listGaugeNoEscrow(pool, gauge, 0, 3, 0);
        assertEq(uint256(v2.getListing(gauge).status), uint256(CurveGaugeListerV2.Status.DaoExempt), "new owner path");
    }

    function test_V2_NoOwnerWithdrawalOrArbitraryExecutionSurface() public {
        (address pool, address gauge,) = deployAuthenticatedPool(0, 0);
        listPaid(pool, gauge, 0, 0);
        uint256 listerBal = crvUSD.balanceOf(address(v2));
        uint256 ownerBal = crvUSD.balanceOf(daoOwner);

        // No owner withdrawal/sweep/rescue/execute/mark-killed surface exists:
        // review1 finding 4 (the same capabilities with COMPLETE, correctly
        // ABI-encoded payloads — real token, valid recipient, spendable
        // amount, properly encoded dynamic arguments — executed AS OWNER and
        // again as a stranger), plus the full setKilled(address,bool) probe
        // from the retired mock-controller permission test. Nothing can pass
        // on a bare-selector decoding accident, and an owner-only function
        // cannot hide behind its argument shape. V2 adds the bounty/immutable
        // rebinding payloads: no setter for any immutable exists.
        bytes[] memory innerCalls = new bytes[](1);
        innerCalls[0] = abi.encodeWithSignature("transfer(address,uint256)", address(stranger), uint256(1e18));
        bytes[] memory payloads = new bytes[](16);
        payloads[0] = abi.encodeWithSignature("withdraw()");
        payloads[1] = abi.encodeWithSignature("withdraw(uint256)", uint256(1));
        payloads[2] = abi.encodeWithSignature("sweep(address)", address(crvUSD));
        payloads[3] = abi.encodeWithSignature("rescue(address)", address(crvUSD));
        payloads[4] = abi.encodeWithSignature(
            "rescue(address,address,uint256)", address(crvUSD), address(stranger), uint256(1e18)
        );
        payloads[5] = abi.encodeWithSignature(
            "execute(address,bytes)",
            address(crvUSD),
            abi.encodeWithSignature("transfer(address,uint256)", address(stranger), uint256(1e18))
        );
        payloads[6] = abi.encodeWithSignature("multicall(bytes[])", innerCalls);
        payloads[7] = abi.encodeWithSignature("markKilled(address)", gauge);
        payloads[8] = abi.encodeWithSignature("change_gauge_weight(address,uint256)", gauge, uint256(0));
        payloads[9] = abi.encodeWithSignature("setKilled(address,bool)", gauge, true);
        payloads[10] = abi.encodeWithSignature("removeGauge(address)", gauge);
        payloads[11] = abi.encodeWithSignature("setFeeDistributor(address)", address(fd));
        payloads[12] = abi.encodeWithSignature("refund(address)", payer);
        payloads[13] = abi.encodeWithSignature("setBounty(address)", address(hook));
        payloads[14] = abi.encodeWithSignature("setController(address)", address(controller));
        payloads[15] = abi.encodeWithSignature("claimReporterReward(address)", address(gauge));
        bool ok;
        for (uint256 i = 0; i < payloads.length; ++i) {
            vm.prank(daoOwner);
            (ok,) = address(v2).call(payloads[i]);
            assertFalse(ok, "full-ABI forbidden payload must fail as owner");
            vm.prank(stranger);
            (ok,) = address(v2).call(payloads[i]);
            assertFalse(ok, "full-ABI forbidden payload must fail as stranger");
        }
        // No receive/fallback: raw value transfer fails.
        (ok,) = address(v2).call{value: 1}("");
        assertFalse(ok, "no receive");

        assertEq(crvUSD.balanceOf(address(v2)), listerBal, "balances unchanged");
        assertEq(crvUSD.balanceOf(daoOwner), ownerBal, "owner gained nothing");
        assertEq(address(v2).balance, 0, "no ETH custody");

        // Full read surface of plan §3.1 exists with exact constants.
        assertEq(v2.WEEK(), WEEK, "WEEK");
        assertEq(v2.FEE(), FEE, "FEE");
        assertEq(v2.QUARTER(), QUARTER, "QUARTER");
        assertEq(v2.EPOCHS(), 4, "EPOCHS");
        assertEq(v2.BPS(), 10_000, "BPS");
        assertEq(v2.INITIAL_WEIGHT(), 0, "INITIAL_WEIGHT");
        assertEq(v2.epochStart(T0 + 123), T0, "epochStart floors");
        assertEq(v2.crvUSD(), address(crvUSD), "crvUSD immutable");
        assertEq(v2.controller(), address(controller), "controller immutable");
        assertEq(v2.feeDistributor(), address(fd), "feeDistributor immutable");
        assertEq(v2.bounty(), address(hook), "bounty immutable");
    }

    /// @dev auditfix001 §2/§5 (V-H01 admission defense): paid positive-share
    /// admissions fail for missing, reverting and malformed readiness getters
    /// with the failure traced AT the readiness read (exact propagated
    /// selector, no fee/custody/record/controller/receipt effect); both
    /// single-share extremes skip the unused faulty endpoint; the DAO-free
    /// path stays independent of readiness; a healthy paid admission calls
    /// no deposit and performs no FeeDistributor checkpoint. Under V2 the
    /// same gate additionally covers the bounty's reciprocal binding, enforced
    /// BEFORE any fee pull, effect or controller addition.
    function test_V2_AuditH01_ReadinessGetterFailuresAndZeroShareExemption() public {
        uint256 payerBefore = crvUSD.balanceOf(payer);
        uint256 listerBefore = crvUSD.balanceOf(address(v2));
        uint256 addsBefore = controller.addCalls();

        // (a) Missing getter: no lister() on the endpoint at all; the
        // staticcall reverts with empty returndata and the hard failure
        // propagates.
        NoListerGetterPlatform missing = new NoListerGetterPlatform(address(crvUSD));
        vm.prank(daoOwner);
        v2.setPlatformConfig(CurveGaugeListerV2.PlatformConfig(address(missing), address(voteMarket), 5000));
        (address poolA, address gaugeA,) = deployAuthenticatedPool(4, 0);
        vm.prank(payer);
        vm.expectRevert();
        v2.listGauge(poolA, gaugeA, 0, 4);

        // (b) Reverting getter: the fault's own selector propagates — proof
        // the revert IS the readiness read, before fee pull, listing effects
        // or controller addition.
        FaultyListerGetterPlatform reverting = new FaultyListerGetterPlatform(address(crvUSD), 1);
        vm.prank(daoOwner);
        v2.setPlatformConfig(CurveGaugeListerV2.PlatformConfig(address(reverting), address(voteMarket), 5000));
        (address poolB, address gaugeB,) = deployAuthenticatedPool(5, 0);
        vm.prank(payer);
        vm.expectRevert(FaultyListerGetterPlatform.ListerReadFailed.selector);
        v2.listGauge(poolB, gaugeB, 0, 5);

        // (c) Malformed short-return getter: ABI-decode failure reverts.
        FaultyListerGetterPlatform shortRet = new FaultyListerGetterPlatform(address(crvUSD), 2);
        vm.prank(daoOwner);
        v2.setPlatformConfig(CurveGaugeListerV2.PlatformConfig(address(shortRet), address(voteMarket), 5000));
        (address poolC, address gaugeC,) = deployAuthenticatedPool(6, 0);
        vm.prank(payer);
        vm.expectRevert();
        v2.listGauge(poolC, gaugeC, 0, 6);

        // Nothing persisted through any failed admission.
        assertEq(crvUSD.balanceOf(payer), payerBefore, "readiness failures moved no fee");
        assertEq(crvUSD.balanceOf(address(v2)), listerBefore, "readiness failures moved no custody");
        assertEq(v2.totalEscrow(), 0, "no liability created");
        assertNoRecord(gaugeA);
        assertNoRecord(gaugeB);
        assertNoRecord(gaugeC);
        assertEq(controller.addCalls(), addsBefore, "no controller addition on readiness failure");
        assertEq(votium.depositCount() + voteMarket.depositCount(), 0, "no platform deposit attempted");
        assertEq(crvUSD.balanceOf(address(fd)), 0, "no FeeDistributor interaction");
        assertEq(crvUSD.allowance(payer, address(v2)), type(uint256).max, "allowance untouched");

        // (d) listGaugeNoEscrow stays independent of platform readiness.
        listDao(poolA, gaugeA, 0, 4, 0);
        assertEq(
            uint256(v2.getListing(gaugeA).status),
            uint256(CurveGaugeListerV2.Status.DaoExempt),
            "DAO path needs no platform readiness"
        );

        // (e) Zero-share exemption: each single-share extreme skips the
        // unused faulty endpoint entirely.
        vm.prank(daoOwner);
        v2.setPlatformConfig(CurveGaugeListerV2.PlatformConfig(address(missing), address(voteMarket), 0));
        (address poolD, address gaugeD,) = deployAuthenticatedPool(7, 0);
        listPaid(poolD, gaugeD, 0, 7);
        assertEq(
            uint256(v2.getListing(gaugeD).status),
            uint256(CurveGaugeListerV2.Status.Active),
            "0-bps skips faulty votium"
        );
        vm.prank(daoOwner);
        v2.setPlatformConfig(CurveGaugeListerV2.PlatformConfig(address(votium), address(reverting), 10_000));
        (address poolE, address gaugeE,) = deployAuthenticatedPool(8, 0);
        listPaid(poolE, gaugeE, 0, 8);
        assertEq(
            uint256(v2.getListing(gaugeE).status),
            uint256(CurveGaugeListerV2.Status.Active),
            "10000-bps skips faulty votemarket"
        );

        // (f) Healthy paid admission calls no deposit and no FD checkpoint.
        vm.prank(daoOwner);
        v2.setPlatformConfig(CurveGaugeListerV2.PlatformConfig(address(votium), address(voteMarket), 5000));
        uint256 fdCalls = fd.checkpointCalls();
        uint256 deposits = votium.depositCount() + voteMarket.depositCount();
        (address poolF, address gaugeF,) = deployAuthenticatedPool(9, 0);
        listPaid(poolF, gaugeF, 0, 9);
        assertEq(fd.checkpointCalls(), fdCalls, "admission performs no FeeDistributor checkpoint");
        assertEq(votium.depositCount() + voteMarket.depositCount(), deposits, "admission calls no platform deposit");

        // (g) V2 addition (plan §1.2): the bounty's own write-once binding is
        // part of paid-admission readiness, enforced at the SAME point as the
        // adapter checks — before fee, effects and controller addition. A core
        // whose bound bounty points at a foreign lister refuses the paid path
        // with BountyNotReady and persists nothing, while the owner-free path on
        // that same core keeps working (DAO-free admission never depends on
        // bounty readiness). The identical core with a correctly bound bounty
        // admits, proving the gate is the binding and not a fixture accident.
        MockListingController gCtl = new MockListingController(controllerDao, int128(2));
        MockIncentivePlatform gVotium = new MockIncentivePlatform(address(crvUSD));
        MockIncentivePlatform gVoteMarket = new MockIncentivePlatform(address(crvUSD));
        MockBountyHook gMisbound = freshHook();
        CurveGaugeListerV2 gCore =
            deployV2Core(address(gCtl), address(gVotium), address(gVoteMarket), address(gMisbound));
        vm.prank(controllerDao);
        gCtl.setLister(address(gCore));
        gVotium.setLister(address(gCore));
        gVoteMarket.setLister(address(gCore));
        // Adapters are honestly bound to gCore; only the bounty points elsewhere.
        gMisbound.bindLister(address(gVotium));
        vm.prank(daoOwner);
        gCore.setPaused(false);
        uint256 payerBeforeG = crvUSD.balanceOf(payer);
        uint256 coreBeforeG = crvUSD.balanceOf(address(gCore));
        (address poolG, address gaugeG,) = deployAuthenticatedPool(4, 0);
        vm.startPrank(payer);
        crvUSD.approve(address(gCore), type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(CurveGaugeListerV2.BountyNotReady.selector));
        gCore.listGauge(poolG, gaugeG, 0, 4);
        vm.stopPrank();
        assertEq(crvUSD.balanceOf(payer), payerBeforeG, "BountyNotReady moved no fee");
        assertEq(crvUSD.balanceOf(address(gCore)), coreBeforeG, "BountyNotReady took no custody");
        assertEq(gCore.totalEscrow(), 0, "BountyNotReady created no liability");
        assertEq(gCtl.addCalls(), 0, "BountyNotReady added no gauge");
        ICurveGaugeListerV2.ListingV2 memory gRec = gCore.getListing(gaugeG);
        assertEq(uint256(gRec.status), uint256(CurveGaugeListerV2.Status.Unlisted), "BountyNotReady left no record");

        // Free path on the same not-ready-bounty core still admits.
        (address poolGFree, address gaugeGFree,) = deployAuthenticatedPool(5, 0);
        vm.prank(daoOwner);
        gCore.listGaugeNoEscrow(poolGFree, gaugeGFree, 0, 5, 0);
        assertEq(
            uint256(gCore.getListing(gaugeGFree).status),
            uint256(CurveGaugeListerV2.Status.DaoExempt),
            "DAO-free admission ignores bounty readiness"
        );
        assertEq(gCore.totalEscrow(), 0, "free path took no escrow");

        // Control: a twin core with the reciprocal binding admits paid.
        MockListingController hCtl = new MockListingController(controllerDao, int128(2));
        MockIncentivePlatform hVotium = new MockIncentivePlatform(address(crvUSD));
        MockIncentivePlatform hVoteMarket = new MockIncentivePlatform(address(crvUSD));
        MockBountyHook hBound = freshHook();
        CurveGaugeListerV2 hCore = deployV2Core(address(hCtl), address(hVotium), address(hVoteMarket), address(hBound));
        bindAndUnpause(hCore, hCtl, address(hVotium), address(hVoteMarket), hBound);
        (address poolH, address gaugeH,) = deployAuthenticatedPool(6, 0);
        vm.prank(payer);
        hCore.listGauge(poolH, gaugeH, 0, 6);
        assertEq(
            uint256(hCore.getListing(gaugeH).status),
            uint256(CurveGaugeListerV2.Status.Active),
            "reciprocally bound bounty admits paid"
        );
    }
}
