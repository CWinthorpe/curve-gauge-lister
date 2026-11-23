// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {TestBase} from "./TestBase.sol";
import {CurveGaugeLister} from "../contracts/CurveGaugeLister.sol";
import {IERC20Minimal} from "../contracts/interfaces/IERC20Minimal.sol";
import {MockERC20} from "../contracts/mocks/MockERC20.sol";
import {MockPool} from "../contracts/mocks/MockPool.sol";
import {MockGauge} from "../contracts/mocks/MockGauge.sol";
import {MockCurveRegistry} from "../contracts/mocks/MockCurveRegistry.sol";
import {MockListingController} from "../contracts/mocks/MockListingController.sol";
import {MockFeeDistributor} from "../contracts/mocks/MockFeeDistributor.sol";
import {MockIncentivePlatform} from "../contracts/mocks/MockIncentivePlatform.sol";
import {AlwaysTrueTrustedValidator} from "./mocks/TrustedFactoryMocks.sol";

/// @dev Test-only faulty deployment (plan §9): add_gauge does nothing so the
/// product's membership postcondition must reject a lying integration instead
/// of silently accepting an unfunded registration. No additional external
/// functions or storage.
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

/// @notice Business/admission/roles matrix (plan §9 R1, R4, R5, R6 rows).
contract CurveGaugeListerTest is TestBase {
    uint256 internal constant FEE = 10_000e18;
    uint256 internal constant QUARTER = 2_500e18;
    uint256 internal constant WEEK = 604800;
    /// @notice Thursday 2026-11-12 00:00 UTC (plan §5 concrete vector).
    uint256 internal constant T0 = 1794441600;
    address internal constant NATIVE = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    MockERC20 internal token;
    MockERC20 internal otherToken;
    MockCurveRegistry internal registry;
    MockCurveRegistry internal registry2;
    MockListingController internal controller;
    MockFeeDistributor internal fd;
    MockIncentivePlatform internal votium;
    MockIncentivePlatform internal voteMarket;
    CurveGaugeLister internal lister;

    address internal daoOwner;
    address internal controllerDao;
    address internal fdAdmin;
    address internal payer;
    address internal stranger;

    function setUp() public virtual {
        daoOwner = actor("daoMultisig");
        controllerDao = actor("controllerDao");
        fdAdmin = actor("fdAdmin");
        payer = actor("payer");
        stranger = actor("stranger");

        token = new MockERC20(18);
        otherToken = new MockERC20(18);
        registry = new MockCurveRegistry();
        registry2 = new MockCurveRegistry();
        controller = new MockListingController(controllerDao, int128(2));
        vm.warp(T0);
        fd = new MockFeeDistributor(address(token), fdAdmin, T0);
        votium = new MockIncentivePlatform(address(token));
        voteMarket = new MockIncentivePlatform(address(token));

        // Explicit chain 1 before ordinary deployment: the amended
        // constructor checks WrongChain FIRST (V1ALIGN §2.1).
        vm.chainId(1);
        lister = new CurveGaugeLister(
            daoOwner,
            address(token),
            address(controller),
            address(fd),
            CurveGaugeLister.AdmissionConfig(address(registry), 8),
            CurveGaugeLister.PlatformConfig(address(votium), address(voteMarket), 5000),
            address(new AlwaysTrueTrustedValidator())
        );

        vm.prank(controllerDao);
        controller.setLister(address(lister));
        votium.setLister(address(lister));
        voteMarket.setLister(address(lister));

        // V1ALIGN §1.3: the fresh core starts paused. Observe that shipped
        // state, then the owner unpauses after binding so every retained
        // downstream obligation runs on its original path.
        assertTrue(lister.paused(), "core starts paused");
        vm.prank(daoOwner);
        lister.setPaused(false);

        token.mint(payer, FEE * 16);
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
        lister.listGauge(pool, gauge, gaugeIndex, handlerId);
    }

    function listDao(address pool, address gauge, uint256 gaugeIndex, uint256 handlerId, uint256 weight) internal {
        vm.prank(daoOwner);
        lister.listGaugeNoEscrow(pool, gauge, gaugeIndex, handlerId, weight);
    }

    /// @dev Kill the gauge for settlement via its admin-side flag (A2): flip
    /// MockGauge's independent killed switch. Weight is never touched.
    function killGauge(address gauge) internal {
        MockGauge(gauge).setKilled(true);
    }

    // ---------------------------------------------------------------
    // R1 — paid listing, immediate addition, atomicity, provenance
    // ---------------------------------------------------------------

    function test_PaidListingTransfersExactFeeIntoEscrow() public {
        (address pool, address gauge, address lp) = deployAuthenticatedPool(0, 0);
        uint256 payerBefore = token.balanceOf(payer);

        vm.expectEmit(true, true, true, true);
        emit GaugeListed(gauge, pool, payer, int128(0), T0, FEE, false);
        listPaid(pool, gauge, 0, 0);

        assertEq(token.balanceOf(payer), payerBefore - FEE, "unrelated caller loses FEE");
        assertEq(token.balanceOf(address(lister)), FEE, "lister gained FEE");
        assertEq(lister.totalEscrow(), FEE, "totalEscrow gained FEE");
        assertEq(token.balanceOf(address(votium)), 0, "votium gained zero");
        assertEq(token.balanceOf(address(voteMarket)), 0, "votemarket gained zero");
        assertEq(token.balanceOf(address(fd)), 0, "feeDistributor gained zero");

        CurveGaugeLister.Listing memory rec = lister.getListing(gauge);
        assertEq(uint8(rec.status), uint8(CurveGaugeLister.Status.Active), "Active");
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
    }

    // Shared fixture state for the split atomicity sub-scenarios (stack-depth
    // relief only; every assertion stays in place inside the named test).
    address internal negPoolA;
    address internal negGaugeA;
    address internal negPoolB;
    address internal negGaugeB;
    address internal poorPayerActor;
    address internal unapprovedPayerActor;

    /// @dev exec7 (A2.3/E7.2): paid listing stamps weight 0 with a
    /// membership-only postcondition; no weight read is needed, and a lying
    /// integration still rolls the fee/record/registration back atomically.
    function test_PaidListingUsesZeroWeightAndMembershipOnly() public {
        // (a) Standard controller: constant and actual add argument are both
        // zero; membership is the derived type; the exact fee was received.
        (address pool, address gauge,) = deployAuthenticatedPool(0, 0);
        uint256 payerBefore = token.balanceOf(payer);
        listPaid(pool, gauge, 0, 0);
        assertEq(lister.INITIAL_WEIGHT(), 0, "paid initial weight constant is zero");
        assertEq(controller.get_gauge_weight(gauge), 0, "actual add argument was zero");
        assertEq(controller.gauge_types(gauge), int128(0), "immediate derived-type membership");
        assertEq(controller.effectiveWeight(gauge, T0 + WEEK), 0, "scheduled point bias is the zero argument");
        assertEq(token.balanceOf(address(lister)), FEE, "exact fee receipt");
        assertEq(token.balanceOf(payer), payerBefore - FEE, "payer lost exactly FEE");

        // (b) Narrow deployment whose ONLY fault is a reverting weight getter
        // (add/membership stay functional): zero-weight paid admission succeeds
        // with no weight read anywhere on the path. auditfix001 §5: each of
        // these cores gets its own FRESH mock adapter pair, bound after that
        // core's construction (reusing adapters bound to the default core
        // would now fail paid-admission readiness).
        MockIncentivePlatform bVotium = new MockIncentivePlatform(address(token));
        MockIncentivePlatform bVoteMarket = new MockIncentivePlatform(address(token));
        WeightReaderRevertingController badReader = new WeightReaderRevertingController(controllerDao, int128(2));
        vm.chainId(1);
        CurveGaugeLister noWeightLister = new CurveGaugeLister(
            daoOwner,
            address(token),
            address(badReader),
            address(fd),
            CurveGaugeLister.AdmissionConfig(address(registry), 8),
            CurveGaugeLister.PlatformConfig(address(bVotium), address(bVoteMarket), 5000),
            address(new AlwaysTrueTrustedValidator())
        );
        vm.prank(controllerDao);
        badReader.setLister(address(noWeightLister));
        bVotium.setLister(address(noWeightLister));
        bVoteMarket.setLister(address(noWeightLister));
        // Owner unpause after binding (V1ALIGN §1.3 fixture wiring).
        vm.prank(daoOwner);
        noWeightLister.setPaused(false);
        (address poolB, address gaugeB,) = deployAuthenticatedPool(5, 0);
        vm.startPrank(payer);
        token.approve(address(noWeightLister), FEE);
        noWeightLister.listGauge(poolB, gaugeB, 0, 5);
        vm.stopPrank();
        assertEq(
            uint8(noWeightLister.getListing(gaugeB).status),
            uint8(CurveGaugeLister.Status.Active),
            "zero-weight admission succeeds without weight reads"
        );
        assertEq(noWeightLister.totalEscrow(), FEE, "escrow taken without a weight read");
        assertEq(badReader.addCalls(), 1, "addition still functional on the faulty reader");
        assertEq(badReader.gauge_types(gaugeB), int128(0), "membership still functional on the faulty reader");
        vm.expectRevert(WeightReaderRevertingController.WeightReadFailed.selector);
        badReader.get_gauge_weight(gaugeB);

        // (c) No-op addition: the membership postcondition rejects a lying
        // integration and the whole paid listing rolls back.
        MockIncentivePlatform cVotium = new MockIncentivePlatform(address(token));
        MockIncentivePlatform cVoteMarket = new MockIncentivePlatform(address(token));
        NoOpListingController noOp = new NoOpListingController(controllerDao, int128(2));
        vm.chainId(1);
        CurveGaugeLister noOpLister = new CurveGaugeLister(
            daoOwner,
            address(token),
            address(noOp),
            address(fd),
            CurveGaugeLister.AdmissionConfig(address(registry), 8),
            CurveGaugeLister.PlatformConfig(address(cVotium), address(cVoteMarket), 5000),
            address(new AlwaysTrueTrustedValidator())
        );
        vm.prank(controllerDao);
        noOp.setLister(address(noOpLister));
        cVotium.setLister(address(noOpLister));
        cVoteMarket.setLister(address(noOpLister));
        // Owner unpause after binding (V1ALIGN §1.3 fixture wiring).
        vm.prank(daoOwner);
        noOpLister.setPaused(false);
        (address poolC, address gaugeC,) = deployAuthenticatedPool(6, 0);
        uint256 payerBeforeC = token.balanceOf(payer);
        vm.startPrank(payer);
        token.approve(address(noOpLister), FEE);
        vm.expectRevert(MockListingController.GaugeNotAdded.selector);
        noOpLister.listGauge(poolC, gaugeC, 0, 6);
        vm.stopPrank();
        assertEq(
            uint8(noOpLister.getListing(gaugeC).status),
            uint8(CurveGaugeLister.Status.Unlisted),
            "no-op addition: no record"
        );
        assertEq(token.balanceOf(payer), payerBeforeC, "no-op addition: fee rolled back");
        assertEq(token.balanceOf(address(noOpLister)), 0, "no-op addition: no custody");

        // (d) Wrong-type addition: registered under a different type, the
        // membership read exposes the lie and everything rolls back.
        MockIncentivePlatform dVotium = new MockIncentivePlatform(address(token));
        MockIncentivePlatform dVoteMarket = new MockIncentivePlatform(address(token));
        WrongTypeListingController wrongType = new WrongTypeListingController(controllerDao, int128(2));
        vm.chainId(1);
        CurveGaugeLister wrongTypeLister = new CurveGaugeLister(
            daoOwner,
            address(token),
            address(wrongType),
            address(fd),
            CurveGaugeLister.AdmissionConfig(address(registry), 8),
            CurveGaugeLister.PlatformConfig(address(dVotium), address(dVoteMarket), 5000),
            address(new AlwaysTrueTrustedValidator())
        );
        vm.prank(controllerDao);
        wrongType.setLister(address(wrongTypeLister));
        dVotium.setLister(address(wrongTypeLister));
        dVoteMarket.setLister(address(wrongTypeLister));
        // Owner unpause after binding (V1ALIGN §1.3 fixture wiring).
        vm.prank(daoOwner);
        wrongTypeLister.setPaused(false);
        (address poolD, address gaugeD,) = deployAuthenticatedPool(7, 0);
        uint256 payerBeforeD = token.balanceOf(payer);
        vm.startPrank(payer);
        token.approve(address(wrongTypeLister), FEE);
        vm.expectRevert(CurveGaugeLister.MembershipFailed.selector);
        wrongTypeLister.listGauge(poolD, gaugeD, 0, 7);
        vm.stopPrank();
        assertEq(
            uint8(wrongTypeLister.getListing(gaugeD).status),
            uint8(CurveGaugeLister.Status.Unlisted),
            "wrong-type addition: no record"
        );
        assertEq(token.balanceOf(payer), payerBeforeD, "wrong-type addition: fee rolled back");
        assertEq(token.balanceOf(address(wrongTypeLister)), 0, "wrong-type addition: no custody");
        // The in-flight wrong-type registration rolled back with the listing:
        // the controller no longer knows the gauge at all.
        vm.expectRevert(MockListingController.GaugeNotAdded.selector);
        wrongType.gauge_types(gaugeD);
    }

    function test_ListingFailureRollsBackFeeAndRegistration() public {
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
        token.approve(address(lister), FEE);
        vm.expectRevert();
        lister.listGauge(negPoolA, negGaugeA, 0, 1);
        vm.stopPrank();
        assertNoRecord(negGaugeA);
        assertEq(token.balanceOf(address(lister)), 0, "no fee from unfunded payer");
        assertEq(lister.totalEscrow(), 0, "no escrow from unfunded payer");

        // (b) insufficient allowance (funded but never approved).
        (negPoolB, negGaugeB,) = deployAuthenticatedPool(2, 0);
        unapprovedPayerActor = actor("unapprovedPayer");
        token.mint(unapprovedPayerActor, FEE);
        vm.prank(unapprovedPayerActor);
        vm.expectRevert();
        lister.listGauge(negPoolB, negGaugeB, 0, 2);
        assertNoRecord(negGaugeB);
        assertEq(token.balanceOf(address(lister)), 0, "no fee from unapproved payer");
    }

    function _controllerFailureRollback() internal {
        // (c) injected controller addition failure.
        (address poolC, address gaugeC,) = deployAuthenticatedPool(3, 0);
        uint256 allowanceBefore = token.allowance(payer, address(lister));
        uint256 payerBefore = token.balanceOf(payer);
        controller.setAddRevert(true);
        vm.prank(payer);
        vm.expectRevert();
        lister.listGauge(poolC, gaugeC, 0, 3);
        controller.setAddRevert(false);
        assertNoRecord(gaugeC);
        assertEq(token.balanceOf(payer), payerBefore, "fee rolled back");
        assertEq(token.allowance(payer, address(lister)), allowanceBefore, "allowance rolled back");
        assertEq(controller.addCalls(), 0, "no addition");
        assertEq(lister.totalEscrow(), 0, "no escrow");
    }

    function _feePullPositiveControls() internal {
        // Positive controls (review1 finding 4): with the missing piece
        // supplied, the identical (a)/(b) calls succeed — the earlier failures
        // were the balance/allowance paths specifically, not fixture accidents
        // or an otherwise-invalid registration.
        token.mint(poorPayerActor, FEE);
        vm.prank(poorPayerActor);
        lister.listGauge(negPoolA, negGaugeA, 0, 1);
        assertEq(
            uint8(lister.getListing(negGaugeA).status),
            uint8(CurveGaugeLister.Status.Active),
            "unfunded payer lists once funded"
        );
        assertEq(lister.getListing(negGaugeA).deposited, FEE, "control (a) deposited FEE");
        vm.startPrank(unapprovedPayerActor);
        token.approve(address(lister), FEE);
        lister.listGauge(negPoolB, negGaugeB, 0, 2);
        vm.stopPrank();
        assertEq(
            uint8(lister.getListing(negGaugeB).status),
            uint8(CurveGaugeLister.Status.Active),
            "unapproved payer lists once allowed"
        );
        assertEq(lister.getListing(negGaugeB).deposited, FEE, "control (b) deposited FEE");
        assertEq(lister.totalEscrow(), 2 * FEE, "both controls hold FEE each");
        assertEq(controller.addCalls(), 2, "both controls added");
    }

    function assertNoRecord(address gauge) internal view {
        CurveGaugeLister.Listing memory rec = lister.getListing(gauge);
        assertEq(uint8(rec.status), uint8(CurveGaugeLister.Status.Unlisted), "unlisted");
        assertEq(rec.deposited, 0, "deposited zero");
        assertEq(rec.remaining, 0, "remaining zero");
        assertEq(rec.payer, address(0), "payer zero");
    }

    function test_AdmissionRejectsUnknownPoolAndSpoofGauge() public {
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
        lister.listGauge(pool, gauge, gaugeIndex, handlerId);
    }

    function test_AdmissionRejectsInvalidAddressesLpAndKilledGauge() public {
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
        assertTrue(lister.getListing(gaugeW).status == CurveGaugeLister.Status.Active, "control listed");
    }

    function test_AdmissionValidatesCoinCountAndAddresses() public {
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
        lister.setAdmissionConfig(CurveGaugeLister.AdmissionConfig(address(registry), 4));
        (address p6, address g6) = deployFullCoinPool(3, 6);
        listPaidExpectRevert(p6, g6, 0, 3);
        vm.prank(daoOwner);
        lister.setAdmissionConfig(CurveGaugeLister.AdmissionConfig(address(registry), 8));

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
    /// (CurveGaugeLister.IndexOutOfRange), never incidentally, with a full
    /// rollback of fee, escrow and controller additions.
    function expectIndexOutOfRangeReject(address pool, address gauge, uint256 gaugeIndex, uint256 handlerId) internal {
        uint256 payerBefore = token.balanceOf(payer);
        uint256 listerBefore = token.balanceOf(address(lister));
        uint256 escrowBefore = lister.totalEscrow();
        uint256 addsBefore = controller.addCalls();
        vm.prank(payer);
        vm.expectRevert(abi.encodeWithSelector(CurveGaugeLister.IndexOutOfRange.selector));
        lister.listGauge(pool, gauge, gaugeIndex, handlerId);
        assertNoRecord(gauge);
        assertEq(token.balanceOf(payer), payerBefore, "no fee on index rejection");
        assertEq(token.balanceOf(address(lister)), listerBefore, "no custody gain on index rejection");
        assertEq(lister.totalEscrow(), escrowBefore, "no liability change on index rejection");
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

    function test_AdmissionAllowsNativeCoinAndUnfundedPool() public {
        // native sentinel + arbitrary ERC20 coin.
        (address pN, address gN, address lpN) =
            deployAuthenticatedPoolWith(0, 0, NATIVE, address(new MockERC20(18)), 2, 0);
        listPaid(pN, gN, 0, 0);
        assertTrue(lister.getListing(gN).status == CurveGaugeLister.Status.Active, "native coin admitted");

        // zero-liquidity/zero-supply LP fixture (no mint, no reserves).
        assertEq(IERC20Minimal(lpN).balanceOf(address(0)), 0, "lp unused");
        (address pZ, address gZ, address lpZ) = deployAuthenticatedPool(1, 0);
        assertEq(IERC20Minimal(lpZ).balanceOf(pZ), 0, "pool holds no LP");
        listPaid(pZ, gZ, 0, 1);
        assertTrue(lister.getListing(gZ).status == CurveGaugeLister.Status.Active, "unfunded pool admitted");

        // pool that IS its LP token: MockERC20 used as both addresses.
        MockERC20 selfPool = new MockERC20(18);
        address selfGauge = address(new MockGauge(address(selfPool)));
        registry.setPool(address(selfPool), 2, address(selfPool), _coins(address(new MockERC20(18)), NATIVE), 2);
        registry.setGauge(address(selfPool), 2, 0, selfGauge, 1);
        listPaid(address(selfPool), selfGauge, 0, 2);
        assertEq(lister.getListing(selfGauge).gaugeType, int128(1), "pool==LP admitted");

        // unrelated payer (no relationship to pool/gauge/lister) with only the
        // fee: no voter-overlap check exists to block it.
        address randomPayer = actor("randomPayer");
        (address pR, address gR) = deployCoinPool(3, 2, address(new MockERC20(18)), address(new MockERC20(18)));
        token.mint(randomPayer, FEE);
        vm.startPrank(randomPayer);
        token.approve(address(lister), FEE);
        lister.listGauge(pR, gR, 0, 3);
        vm.stopPrank();
        assertEq(lister.getListing(gR).payer, randomPayer, "unrelated lister accepted");
    }

    function test_DoubleListingRejectedAcrossAllPathsAndTerminalStates() public {
        // paid -> paid and paid -> DAO on one gauge.
        (address poolA, address gaugeA,) = deployAuthenticatedPool(0, 0);
        listPaid(poolA, gaugeA, 0, 0);
        uint256 payerBefore = token.balanceOf(payer);
        listPaidExpectRevert(poolA, gaugeA, 0, 0);
        listDaoExpectRevert(poolA, gaugeA, 0, 0, 0);
        assertEq(token.balanceOf(payer), payerBefore, "no second fee (paid repeats)");
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
        (uint256 r, uint256 c) = lister.checkpoint(gaugeC);
        assertEq(r, FEE, "exhausted");
        assertEq(c, 0, "no confiscation");
        listPaidExpectRevert(poolC, gaugeC, 0, 2);
        listDaoExpectRevert(poolC, gaugeC, 0, 2, 0);

        // After confiscation: terminal, never re-admittable.
        (address poolD, address gaugeD,) = deployAuthenticatedPool(3, 0);
        listPaid(poolD, gaugeD, 0, 3);
        killGauge(gaugeD);
        lister.confiscate(gaugeD);
        listPaidExpectRevert(poolD, gaugeD, 0, 3);
        listDaoExpectRevert(poolD, gaugeD, 0, 3, 0);

        // Externally controller-listed gauge: the controller's permanent
        // registry rejects it on both paths. CX-NEG: name the exact checked
        // rejection (occupied controller registry, with the gauge argument)
        // on BOTH admission lanes instead of a bare revert; the full-
        // rollback fee assertion below stays.
        (address poolE, address gaugeE,) = deployAuthenticatedPool(4, 0);
        vm.prank(controllerDao);
        controller.add_gauge(gaugeE, int128(0), 3);
        uint256 payerBeforeE = token.balanceOf(payer);
        vm.prank(payer);
        vm.expectRevert(abi.encodeWithSelector(CurveGaugeLister.ControllerRegistryOccupied.selector, gaugeE));
        lister.listGauge(poolE, gaugeE, 0, 4);
        vm.prank(daoOwner);
        vm.expectRevert(abi.encodeWithSelector(CurveGaugeLister.ControllerRegistryOccupied.selector, gaugeE));
        lister.listGaugeNoEscrow(poolE, gaugeE, 0, 4, 0);
        assertEq(token.balanceOf(payer), payerBeforeE, "no fee for controller-listed rejection");
    }

    function listDaoExpectRevert(address pool, address gauge, uint256 gaugeIndex, uint256 handlerId, uint256 weight)
        internal
    {
        vm.prank(daoOwner);
        vm.expectRevert();
        lister.listGaugeNoEscrow(pool, gauge, gaugeIndex, handlerId, weight);
    }

    function test_DistinctAuthenticatedGaugesForSamePoolCanList() public {
        address lp = address(new MockERC20(18));
        address pool = address(new MockPool());
        address gauge1 = address(new MockGauge(lp));
        address gauge2 = address(new MockGauge(lp));
        registry.setPool(pool, 0, lp, _coins(address(new MockERC20(18)), address(new MockERC20(18))), 2);
        registry.setGauge(pool, 0, 0, gauge1, 0);
        registry.setGauge(pool, 0, 1, gauge2, 1);

        listPaid(pool, gauge1, 0, 0);
        listPaid(pool, gauge2, 1, 0);

        assertEq(lister.totalEscrow(), 2 * FEE, "both fees held");
        assertEq(token.balanceOf(address(lister)), 2 * FEE, "both fees in");
        assertEq(uint8(lister.getListing(gauge1).status), uint8(CurveGaugeLister.Status.Active), "g1 active");
        assertEq(uint8(lister.getListing(gauge2).status), uint8(CurveGaugeLister.Status.Active), "g2 active");
        assertEq(lister.getListing(gauge2).gaugeType, int128(1), "per-gauge type");
    }

    // ---------------------------------------------------------------
    // R4 — DAO no-escrow path
    // ---------------------------------------------------------------

    function test_DaoZeroFeeListingNeverDrips() public {
        // Owner holds no fee tokens at all: zero balance, zero allowance.
        assertEq(token.balanceOf(daoOwner), 0, "owner unfunded");
        assertEq(token.allowance(daoOwner, address(lister)), 0, "owner no allowance");

        // A stranger cannot choose the free path (absorbed from the retired
        // standalone non-owner test).
        (address poolN, address gaugeN,) = deployAuthenticatedPool(9, 0);
        vm.prank(stranger);
        vm.expectRevert();
        lister.listGaugeNoEscrow(poolN, gaugeN, 0, 9, 0);
        assertNoRecord(gaugeN);
        assertEq(controller.addCalls(), 0, "no addition from the free-attempt");

        (address poolA, address gaugeA,) = deployAuthenticatedPool(0, 0);
        listDao(poolA, gaugeA, 0, 0, 0);
        (address poolB, address gaugeB,) = deployAuthenticatedPool(1, 0);
        listDao(poolB, gaugeB, 0, 1, 3);

        CurveGaugeLister.Listing memory recA = lister.getListing(gaugeA);
        assertEq(uint8(recA.status), uint8(CurveGaugeLister.Status.DaoExempt), "DaoExempt");
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

        uint256 listerBefore = token.balanceOf(address(lister));
        vm.warp(T0 + 10 * WEEK);
        (uint256 r, uint256 c) = lister.checkpoint(gaugeA);
        assertEq(r + c, 0, "never drips");
        (r, c) = lister.checkpoint(gaugeB);
        assertEq(r + c, 0, "never drips (nonzero weight)");
        assertEq(lister.confiscate(gaugeB), 0, "no confiscation on DAO record");
        killGauge(gaugeA);
        // still a no-op after a DAO kill attempt on the DAO-exempt record
        (r, c) = lister.checkpoint(gaugeA);
        assertEq(r + c, 0, "still no-op after kill attempt");

        assertEq(token.balanceOf(address(lister)), listerBefore, "no token movement");
        assertEq(token.balanceOf(address(votium)) + token.balanceOf(address(voteMarket)), 0, "no deposits");
        assertEq(votium.depositCount() + voteMarket.depositCount(), 0, "no receipts");
        assertEq(token.balanceOf(address(fd)), 0, "no confiscation money");
        assertEq(lister.epochsElapsed(gaugeA), 0, "epochsElapsed 0 for DaoExempt");
        assertEq(lister.releasable(gaugeA), 0, "releasable 0 for DaoExempt");
        assertEq(lister.totalEscrow(), 0, "no escrow liability");
        assertEq(uint8(lister.getListing(gaugeA).status), uint8(CurveGaugeLister.Status.DaoExempt), "lifetime status");

        // review1 finding 3: lifetime re-read of ALL financial/platform fields
        // after the warps/kills/checkpoints, not just at creation.
        recA = lister.getListing(gaugeA);
        assertEq(uint8(recA.status), uint8(CurveGaugeLister.Status.DaoExempt), "lifetime DaoExempt status");
        assertEq(recA.payer, address(0), "lifetime payer zero");
        assertEq(recA.deposited, 0, "lifetime deposited zero");
        assertEq(recA.remaining, 0, "lifetime remaining zero");
        assertEq(recA.released, 0, "lifetime released zero");
        assertEq(recA.confiscated, 0, "lifetime confiscated zero");
        assertEq(uint256(recA.epochsReleased), 0, "lifetime counter zero");
        assertEq(recA.votium, address(0), "lifetime votium zero");
        assertEq(recA.voteMarket, address(0), "lifetime voteMarket zero");
        assertEq(uint256(recA.votiumBps), 0, "lifetime bps zero");
        CurveGaugeLister.Listing memory recBChk = lister.getListing(gaugeB);
        assertEq(recBChk.deposited + recBChk.remaining + recBChk.released + recBChk.confiscated, 0, "lifetime B zero");
        assertEq(uint256(recBChk.epochsReleased), 0, "lifetime B counter zero");
    }

    // ---------------------------------------------------------------
    // R5 — pause, configuration, custody, registry, ownership, drain surface
    // ---------------------------------------------------------------

    function test_OwnerPauseOnlyBlocksPermissionlessAdmission() public {
        (address poolLive, address gaugeLive,) = deployAuthenticatedPool(0, 0);
        listPaid(poolLive, gaugeLive, 0, 0);
        (address poolKill, address gaugeKill,) = deployAuthenticatedPool(1, 0);
        listPaid(poolKill, gaugeKill, 0, 1);

        vm.prank(stranger);
        vm.expectRevert();
        lister.setPaused(true);
        assertTrue(lister.paused() == false, "stranger cannot pause");

        vm.prank(daoOwner);
        lister.setPaused(true);
        assertTrue(lister.paused(), "paused");

        // paid admission blocked
        (address poolC, address gaugeC) = deployCoinPool(3, 2, address(new MockERC20(18)), address(new MockERC20(18)));
        listPaidExpectRevert(poolC, gaugeC, 0, 3);

        // DAO-free addition continues
        (address poolD, address gaugeD,) = deployAuthenticatedPool(4, 0);
        listDao(poolD, gaugeD, 0, 4, 2);
        assertEq(
            uint8(lister.getListing(gaugeD).status), uint8(CurveGaugeLister.Status.DaoExempt), "dao path while paused"
        );

        // releases continue
        vm.warp(T0 + WEEK);
        (uint256 r,) = lister.checkpoint(gaugeLive);
        assertEq(r, QUARTER, "release while paused");

        // zero-weight confiscation continues
        killGauge(gaugeKill);
        uint256 seized = lister.confiscate(gaugeKill);
        assertEq(seized, FEE, "confiscation while paused");
        assertEq(token.balanceOf(address(fd)), FEE, "distributor paid while paused");

        // unpause restores admission
        vm.prank(daoOwner);
        lister.setPaused(false);
        listPaid(poolC, gaugeC, 0, 3);
        assertEq(uint8(lister.getListing(gaugeC).status), uint8(CurveGaugeLister.Status.Active), "unpaused admission");
    }

    function test_OnlyOwnerCanConfigureAdmissionAndPlatforms() public {
        CurveGaugeLister.AdmissionConfig memory goodAdmission = CurveGaugeLister.AdmissionConfig(address(registry), 8);
        CurveGaugeLister.PlatformConfig memory goodPlatforms =
            CurveGaugeLister.PlatformConfig(address(votium), address(voteMarket), 5000);

        // unauthorized
        vm.prank(stranger);
        vm.expectRevert();
        lister.setAdmissionConfig(goodAdmission);
        vm.prank(stranger);
        vm.expectRevert();
        lister.setPlatformConfig(goodPlatforms);

        // invalid admission configs reject atomically
        vm.startPrank(daoOwner);
        vm.expectRevert();
        lister.setAdmissionConfig(CurveGaugeLister.AdmissionConfig(address(registry), 1));
        vm.expectRevert();
        lister.setAdmissionConfig(CurveGaugeLister.AdmissionConfig(address(registry), 9));
        vm.expectRevert();
        lister.setAdmissionConfig(CurveGaugeLister.AdmissionConfig(address(0), 8));
        vm.expectRevert();
        lister.setAdmissionConfig(CurveGaugeLister.AdmissionConfig(actor("eoaRegistry"), 8));
        vm.stopPrank();
        CurveGaugeLister.AdmissionConfig memory stillAdm = lister.getAdmissionConfig();
        assertEq(stillAdm.registry, address(registry), "admission atomic");
        assertEq(uint256(stillAdm.maxCoins), 8, "maxCoins atomic");

        // valid admission change affects new admissions only
        (address poolNew,) = deployCoinPool(5, 2, address(new MockERC20(18)), address(new MockERC20(18)));
        (, address gaugeNew, address lpNew) = deployAuthenticatedPool(6, 0);
        registry2.setPool(poolNew, 6, lpNew, _coins(address(new MockERC20(18)), address(new MockERC20(18))), 2);
        registry2.setGauge(poolNew, 6, 0, gaugeNew, 0);
        vm.prank(daoOwner);
        lister.setAdmissionConfig(CurveGaugeLister.AdmissionConfig(address(registry2), 8));
        assertEq(lister.getAdmissionConfig().registry, address(registry2), "config stored");
        // the old-registry pool no longer admits
        (address poolOld, address gaugeOld) =
            deployCoinPool(7, 2, address(new MockERC20(18)), address(new MockERC20(18)));
        listPaidExpectRevert(poolOld, gaugeOld, 0, 7);
        // the registry2-authenticated gauge does
        listPaid(poolNew, gaugeNew, 0, 6);

        // invalid platform configs reject atomically
        vm.startPrank(daoOwner);
        vm.expectRevert();
        lister.setPlatformConfig(CurveGaugeLister.PlatformConfig(address(votium), address(voteMarket), 10001));
        vm.expectRevert();
        lister.setPlatformConfig(CurveGaugeLister.PlatformConfig(address(0), address(voteMarket), 5000));
        vm.expectRevert();
        lister.setPlatformConfig(CurveGaugeLister.PlatformConfig(actor("eoaVotium"), address(voteMarket), 5000));
        MockIncentivePlatform wrongToken = new MockIncentivePlatform(address(otherToken));
        vm.expectRevert();
        lister.setPlatformConfig(CurveGaugeLister.PlatformConfig(address(wrongToken), address(voteMarket), 5000));
        // review1 finding 9 (absorbed from the retired setter-only test): a
        // mixed split onto identical endpoints is refused by the shared
        // validator; every aliased combination rejects atomically.
        vm.expectRevert(abi.encodeWithSelector(CurveGaugeLister.BadPlatformConfig.selector));
        lister.setPlatformConfig(CurveGaugeLister.PlatformConfig(address(votium), address(votium), 5000));
        vm.expectRevert(abi.encodeWithSelector(CurveGaugeLister.BadPlatformConfig.selector));
        lister.setPlatformConfig(CurveGaugeLister.PlatformConfig(address(voteMarket), address(voteMarket), 1));
        vm.expectRevert(abi.encodeWithSelector(CurveGaugeLister.BadPlatformConfig.selector));
        lister.setPlatformConfig(CurveGaugeLister.PlatformConfig(address(votium), address(votium), 9999));
        vm.stopPrank();
        CurveGaugeLister.PlatformConfig memory stillPlat = lister.getPlatformConfig();
        assertEq(stillPlat.votium, address(votium), "platform atomic");
        assertEq(stillPlat.voteMarket, address(voteMarket), "platform atomic 2");
        assertEq(uint256(stillPlat.votiumBps), 5000, "platform atomic 3");

        // zero-share side may be the zero address
        vm.prank(daoOwner);
        lister.setPlatformConfig(CurveGaugeLister.PlatformConfig(address(0), address(voteMarket), 0));
        assertEq(uint256(lister.getPlatformConfig().votiumBps), 0, "zero-share accepted");
        vm.prank(daoOwner);
        lister.setPlatformConfig(CurveGaugeLister.PlatformConfig(address(votium), address(0), 10000));
        assertEq(lister.getPlatformConfig().voteMarket, address(0), "zero-share complement accepted");
        // A single-share config keeps even an aliased never-called side
        // acceptable (absorbed from the retired setter-only test).
        vm.prank(daoOwner);
        lister.setPlatformConfig(CurveGaugeLister.PlatformConfig(address(votium), address(votium), 0));
        assertEq(lister.getPlatformConfig().votium, address(votium), "aliased single share accepted");
    }

    // review1 finding 9: a mixed split onto identical endpoints makes the
    // frozen listing unreleasable (the shared adapter rejects the second
    // same-gauge/same-epoch deposit). The shared validator rejects it at
    // configuration time; 0/10000 single-share configs keep working.

    function test_ConstructorRejectsAliasedEndpoints() public {
        CurveGaugeLister.AdmissionConfig memory adm = CurveGaugeLister.AdmissionConfig(address(registry), 8);
        // Created BEFORE the armed reverts: the validator CREATE would
        // otherwise consume the next-call expectation.
        address okValidator = address(new AlwaysTrueTrustedValidator());

        vm.expectRevert(abi.encodeWithSelector(CurveGaugeLister.BadPlatformConfig.selector));
        new CurveGaugeLister(
            daoOwner,
            address(token),
            address(controller),
            address(fd),
            adm,
            CurveGaugeLister.PlatformConfig(address(votium), address(votium), 5000),
            // Healthy code-bearing validator (created before the armed
            // reverts): the NoCode(validator) guard runs before platform
            // validation, so these probes must supply code to keep
            // discriminating BadPlatformConfig.
            okValidator
        );
        vm.expectRevert(abi.encodeWithSelector(CurveGaugeLister.BadPlatformConfig.selector));
        new CurveGaugeLister(
            daoOwner,
            address(token),
            address(controller),
            address(fd),
            adm,
            CurveGaugeLister.PlatformConfig(address(voteMarket), address(voteMarket), 1),
            okValidator
        );
        vm.expectRevert(abi.encodeWithSelector(CurveGaugeLister.BadPlatformConfig.selector));
        new CurveGaugeLister(
            daoOwner,
            address(token),
            address(controller),
            address(fd),
            adm,
            CurveGaugeLister.PlatformConfig(address(votium), address(votium), 9999),
            okValidator
        );

        // Single-share constructions keep working, zero address allowed unused.
        CurveGaugeLister soloVm = new CurveGaugeLister(
            daoOwner,
            address(token),
            address(controller),
            address(fd),
            adm,
            CurveGaugeLister.PlatformConfig(address(0), address(voteMarket), 0),
            okValidator
        );
        assertEq(soloVm.owner(), daoOwner, "0-bps single-share constructor ok");
        CurveGaugeLister soloVotium = new CurveGaugeLister(
            daoOwner,
            address(token),
            address(controller),
            address(fd),
            adm,
            CurveGaugeLister.PlatformConfig(address(votium), address(0), 10000),
            okValidator
        );
        assertEq(soloVotium.owner(), daoOwner, "10000-bps single-share constructor ok");
    }

    function test_PlatformChangesCannotRedirectExistingEscrow() public {
        (address poolA, address gaugeA,) = deployAuthenticatedPool(0, 0);
        listPaid(poolA, gaugeA, 0, 0);

        MockIncentivePlatform votium2 = new MockIncentivePlatform(address(token));
        MockIncentivePlatform voteMarket2 = new MockIncentivePlatform(address(token));
        uint256 listerBefore = token.balanceOf(address(lister));
        vm.prank(daoOwner);
        lister.setPlatformConfig(CurveGaugeLister.PlatformConfig(address(votium2), address(voteMarket2), 2500));
        assertEq(token.balanceOf(address(lister)), listerBefore, "setter moved no tokens");
        assertEq(token.allowance(address(lister), address(votium)), 0, "setter created no allowance");
        assertEq(token.allowance(address(lister), address(voteMarket)), 0, "setter created no allowance 2");
        assertEq(token.allowance(address(lister), address(votium2)), 0, "setter created no allowance 3");

        vm.warp(T0 + WEEK);
        (uint256 r,) = lister.checkpoint(gaugeA);
        assertEq(r, QUARTER, "old escrow releases");
        // Original endpoints and original 5000/5000 split, not the new config.
        (uint256 amtA, uint256 execA, bytes32 receiptA) = votium.getDeposit(gaugeA, T0 + WEEK);
        assertEq(amtA, QUARTER / 2, "old votium share");
        assertTrue(execA == T0 + WEEK, "execution epoch");
        assertTrue(receiptA != bytes32(0), "receipt A");
        (, uint256 execB, bytes32 receiptB) = voteMarket.getDeposit(gaugeA, T0 + WEEK);
        assertTrue(receiptB != bytes32(0) && execB == T0 + WEEK, "old voteMarket share");
        assertEq(token.balanceOf(address(votium2)), 0, "new votium untouched");
        assertEq(token.balanceOf(address(voteMarket2)), 0, "new voteMarket untouched");

        // New listing pays the NEW defaults/split.
        votium2.setLister(address(lister));
        voteMarket2.setLister(address(lister));
        (address poolB, address gaugeB,) = deployAuthenticatedPool(1, 0);
        listPaid(poolB, gaugeB, 0, 1);
        assertEq(lister.getListing(gaugeB).votium, address(votium2), "new snapshot");
        assertEq(uint256(lister.getListing(gaugeB).votiumBps), 2500, "new bps snapshot");

        vm.warp(T0 + 2 * WEEK);
        (uint256 rB,) = lister.checkpoint(gaugeB);
        assertEq(rB, QUARTER, "new gauge releases");
        assertEq(token.balanceOf(address(votium2)), (QUARTER * 2500) / 10000, "new split votium");
        assertEq(token.balanceOf(address(voteMarket2)), QUARTER - (QUARTER * 2500) / 10000, "new split votemarket");
    }

    function test_AdmissionChangeDoesNotRevalidateExistingEscrow() public {
        (address poolA, address gaugeA,) = deployAuthenticatedPool(0, 0);
        listPaid(poolA, gaugeA, 0, 0);

        // Swap to a registry that does not know poolA at all.
        vm.prank(daoOwner);
        lister.setAdmissionConfig(CurveGaugeLister.AdmissionConfig(address(registry2), 8));

        vm.warp(T0 + WEEK);
        (uint256 r,) = lister.checkpoint(gaugeA);
        assertEq(r, QUARTER, "existing escrow settles under dead registry");
        assertEq(token.balanceOf(address(votium)) + token.balanceOf(address(voteMarket)), QUARTER, "funded");

        // New listings follow the new policy.
        (address poolB, address gaugeB,) = deployAuthenticatedPool(1, 0);
        listPaidExpectRevert(poolB, gaugeB, 0, 1);
        (address poolC, address gaugeC, address lpC) = deployAuthenticatedPool(2, 0);
        registry2.setPool(poolC, 0, lpC, _coins(address(new MockERC20(18)), address(new MockERC20(18))), 2);
        registry2.setGauge(poolC, 0, 0, gaugeC, 0);
        listPaid(poolC, gaugeC, 0, 0);
        assertEq(lister.getListing(gaugeC).admissionRegistry, address(registry2), "new policy recorded");
    }

    function test_TwoStepOwnershipTransfer() public {
        assertEq(lister.owner(), daoOwner, "explicit owner, not deployer");
        assertTrue(lister.owner() != address(this), "no silent deployer privilege");
        assertTrue(lister.pendingOwner() == address(0), "no pending initially");

        address newOwner = actor("nextDao");
        vm.prank(stranger);
        vm.expectRevert();
        lister.transferOwnership(newOwner);
        vm.prank(daoOwner);
        vm.expectRevert();
        lister.transferOwnership(address(0));

        vm.prank(daoOwner);
        vm.expectEmit(true, true, false, false);
        emit OwnershipTransferStarted(daoOwner, newOwner);
        lister.transferOwnership(newOwner);
        assertEq(lister.owner(), daoOwner, "owner unchanged until acceptance");
        assertEq(lister.pendingOwner(), newOwner, "nonzero pending owner");

        // Old owner keeps rights pre-acceptance but cannot be the accepter.
        vm.prank(daoOwner);
        lister.setPaused(true);
        assertTrue(lister.paused(), "old owner retains rights until accept");
        vm.prank(daoOwner);
        lister.setPaused(false);

        vm.prank(stranger);
        vm.expectRevert();
        lister.acceptOwnership();
        vm.prank(newOwner);
        vm.expectEmit(true, true, false, false);
        emit OwnershipTransferred(daoOwner, newOwner);
        lister.acceptOwnership();
        assertEq(lister.owner(), newOwner, "new owner active");
        assertEq(lister.pendingOwner(), address(0), "pending cleared");

        vm.prank(daoOwner);
        vm.expectRevert();
        lister.setPaused(true);
        vm.prank(newOwner);
        lister.setPaused(true);
        assertTrue(lister.paused(), "new owner configures");
        // The old owner cannot list for free either.
        (address pool, address gauge,) = deployAuthenticatedPool(3, 0);
        vm.prank(daoOwner);
        vm.expectRevert();
        lister.listGaugeNoEscrow(pool, gauge, 0, 3, 0);
        vm.prank(newOwner);
        lister.listGaugeNoEscrow(pool, gauge, 0, 3, 0);
        assertEq(uint8(lister.getListing(gauge).status), uint8(CurveGaugeLister.Status.DaoExempt), "new owner path");
    }

    function test_NoOwnerWithdrawalOrArbitraryExecutionSurface() public {
        (address pool, address gauge,) = deployAuthenticatedPool(0, 0);
        listPaid(pool, gauge, 0, 0);
        uint256 listerBal = token.balanceOf(address(lister));
        uint256 ownerBal = token.balanceOf(daoOwner);

        // No owner withdrawal/sweep/rescue/execute/mark-killed surface exists:
        // review1 finding 4 (the same capabilities with COMPLETE, correctly
        // ABI-encoded payloads — real token, valid recipient, spendable
        // amount, properly encoded dynamic arguments — executed AS OWNER and
        // again as a stranger), plus the full setKilled(address,bool) probe
        // from the retired mock-controller permission test. Nothing can pass
        // on a bare-selector decoding accident, and an owner-only function
        // cannot hide behind its argument shape.
        bytes[] memory innerCalls = new bytes[](1);
        innerCalls[0] = abi.encodeWithSignature("transfer(address,uint256)", address(stranger), uint256(1e18));
        bytes[] memory payloads = new bytes[](13);
        payloads[0] = abi.encodeWithSignature("withdraw()");
        payloads[1] = abi.encodeWithSignature("withdraw(uint256)", uint256(1));
        payloads[2] = abi.encodeWithSignature("sweep(address)", address(token));
        payloads[3] = abi.encodeWithSignature("rescue(address)", address(token));
        payloads[4] = abi.encodeWithSignature(
            "rescue(address,address,uint256)", address(token), address(stranger), uint256(1e18)
        );
        payloads[5] = abi.encodeWithSignature(
            "execute(address,bytes)",
            address(token),
            abi.encodeWithSignature("transfer(address,uint256)", address(stranger), uint256(1e18))
        );
        payloads[6] = abi.encodeWithSignature("multicall(bytes[])", innerCalls);
        payloads[7] = abi.encodeWithSignature("markKilled(address)", gauge);
        payloads[8] = abi.encodeWithSignature("change_gauge_weight(address,uint256)", gauge, uint256(0));
        payloads[9] = abi.encodeWithSignature("setKilled(address,bool)", gauge, true);
        payloads[10] = abi.encodeWithSignature("removeGauge(address)", gauge);
        payloads[11] = abi.encodeWithSignature("setFeeDistributor(address)", address(fd));
        payloads[12] = abi.encodeWithSignature("refund(address)", payer);
        bool ok;
        for (uint256 i = 0; i < payloads.length; ++i) {
            vm.prank(daoOwner);
            (ok,) = address(lister).call(payloads[i]);
            assertFalse(ok, "full-ABI forbidden payload must fail as owner");
            vm.prank(stranger);
            (ok,) = address(lister).call(payloads[i]);
            assertFalse(ok, "full-ABI forbidden payload must fail as stranger");
        }
        // No receive/fallback: raw value transfer fails.
        (ok,) = address(lister).call{value: 1}("");
        assertFalse(ok, "no receive");

        assertEq(token.balanceOf(address(lister)), listerBal, "balances unchanged");
        assertEq(token.balanceOf(daoOwner), ownerBal, "owner gained nothing");
        assertEq(address(lister).balance, 0, "no ETH custody");

        // Full read surface of plan §3.1 exists with exact constants.
        assertEq(lister.WEEK(), WEEK, "WEEK");
        assertEq(lister.FEE(), FEE, "FEE");
        assertEq(lister.QUARTER(), QUARTER, "QUARTER");
        assertEq(lister.EPOCHS(), 4, "EPOCHS");
        assertEq(lister.BPS(), 10_000, "BPS");
        assertEq(lister.INITIAL_WEIGHT(), 0, "INITIAL_WEIGHT");
        assertEq(lister.epochStart(T0 + 123), T0, "epochStart floors");
        assertEq(lister.crvUSD(), address(token), "crvUSD immutable");
        assertEq(lister.controller(), address(controller), "controller immutable");
        assertEq(lister.feeDistributor(), address(fd), "feeDistributor immutable");
    }

    /// @dev auditfix001 §2/§5 (V-H01 admission defense): paid positive-share
    /// admissions fail for missing, reverting and malformed readiness getters
    /// with the failure traced AT the readiness read (exact propagated
    /// selector, no fee/custody/record/controller/receipt effect); both
    /// single-share extremes skip the unused faulty endpoint; the DAO-free
    /// path stays independent of readiness; a healthy paid admission calls
    /// no deposit and performs no FeeDistributor checkpoint.
    function test_AuditH01_ReadinessGetterFailuresAndZeroShareExemption() public {
        uint256 payerBefore = token.balanceOf(payer);
        uint256 listerBefore = token.balanceOf(address(lister));
        uint256 addsBefore = controller.addCalls();

        // (a) Missing getter: no lister() on the endpoint at all; the
        // staticcall reverts with empty returndata and the hard failure
        // propagates.
        NoListerGetterPlatform missing = new NoListerGetterPlatform(address(token));
        vm.prank(daoOwner);
        lister.setPlatformConfig(CurveGaugeLister.PlatformConfig(address(missing), address(voteMarket), 5000));
        (address poolA, address gaugeA,) = deployAuthenticatedPool(4, 0);
        vm.prank(payer);
        vm.expectRevert();
        lister.listGauge(poolA, gaugeA, 0, 4);

        // (b) Reverting getter: the fault's own selector propagates — proof
        // the revert IS the readiness read, before fee pull, listing effects
        // or controller addition.
        FaultyListerGetterPlatform reverting = new FaultyListerGetterPlatform(address(token), 1);
        vm.prank(daoOwner);
        lister.setPlatformConfig(CurveGaugeLister.PlatformConfig(address(reverting), address(voteMarket), 5000));
        (address poolB, address gaugeB,) = deployAuthenticatedPool(5, 0);
        vm.prank(payer);
        vm.expectRevert(FaultyListerGetterPlatform.ListerReadFailed.selector);
        lister.listGauge(poolB, gaugeB, 0, 5);

        // (c) Malformed short-return getter: ABI-decode failure reverts.
        FaultyListerGetterPlatform shortRet = new FaultyListerGetterPlatform(address(token), 2);
        vm.prank(daoOwner);
        lister.setPlatformConfig(CurveGaugeLister.PlatformConfig(address(shortRet), address(voteMarket), 5000));
        (address poolC, address gaugeC,) = deployAuthenticatedPool(6, 0);
        vm.prank(payer);
        vm.expectRevert();
        lister.listGauge(poolC, gaugeC, 0, 6);

        // Nothing persisted through any failed admission.
        assertEq(token.balanceOf(payer), payerBefore, "readiness failures moved no fee");
        assertEq(token.balanceOf(address(lister)), listerBefore, "readiness failures moved no custody");
        assertEq(lister.totalEscrow(), 0, "no liability created");
        assertNoRecord(gaugeA);
        assertNoRecord(gaugeB);
        assertNoRecord(gaugeC);
        assertEq(controller.addCalls(), addsBefore, "no controller addition on readiness failure");
        assertEq(votium.depositCount() + voteMarket.depositCount(), 0, "no platform deposit attempted");
        assertEq(token.balanceOf(address(fd)), 0, "no FeeDistributor interaction");
        assertEq(token.allowance(payer, address(lister)), type(uint256).max, "allowance untouched");

        // (d) listGaugeNoEscrow stays independent of platform readiness.
        listDao(poolA, gaugeA, 0, 4, 0);
        assertEq(
            uint8(lister.getListing(gaugeA).status),
            uint8(CurveGaugeLister.Status.DaoExempt),
            "DAO path needs no platform readiness"
        );

        // (e) Zero-share exemption: each single-share extreme skips the
        // unused faulty endpoint entirely.
        vm.prank(daoOwner);
        lister.setPlatformConfig(CurveGaugeLister.PlatformConfig(address(missing), address(voteMarket), 0));
        (address poolD, address gaugeD,) = deployAuthenticatedPool(7, 0);
        listPaid(poolD, gaugeD, 0, 7);
        assertEq(
            uint8(lister.getListing(gaugeD).status), uint8(CurveGaugeLister.Status.Active), "0-bps skips faulty votium"
        );
        vm.prank(daoOwner);
        lister.setPlatformConfig(CurveGaugeLister.PlatformConfig(address(votium), address(reverting), 10_000));
        (address poolE, address gaugeE,) = deployAuthenticatedPool(8, 0);
        listPaid(poolE, gaugeE, 0, 8);
        assertEq(
            uint8(lister.getListing(gaugeE).status),
            uint8(CurveGaugeLister.Status.Active),
            "10000-bps skips faulty votemarket"
        );

        // (f) Healthy paid admission calls no deposit and no FD checkpoint.
        vm.prank(daoOwner);
        lister.setPlatformConfig(CurveGaugeLister.PlatformConfig(address(votium), address(voteMarket), 5000));
        uint256 fdCalls = fd.checkpointCalls();
        uint256 deposits = votium.depositCount() + voteMarket.depositCount();
        (address poolF, address gaugeF,) = deployAuthenticatedPool(9, 0);
        listPaid(poolF, gaugeF, 0, 9);
        assertEq(fd.checkpointCalls(), fdCalls, "admission performs no FeeDistributor checkpoint");
        assertEq(votium.depositCount() + voteMarket.depositCount(), deposits, "admission calls no platform deposit");
    }
}
