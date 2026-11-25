// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {TestBase, Vm} from "./TestBase.sol";
import {CurveGaugeLister} from "../contracts/CurveGaugeLister.sol";
import {IERC20Minimal} from "../contracts/interfaces/IERC20Minimal.sol";
import {MockERC20} from "../contracts/mocks/MockERC20.sol";
import {MockPool} from "../contracts/mocks/MockPool.sol";
import {MockGauge} from "../contracts/mocks/MockGauge.sol";
import {MockCurveRegistry} from "../contracts/mocks/MockCurveRegistry.sol";
import {MockFeeDistributor} from "../contracts/mocks/MockFeeDistributor.sol";
import {MockIncentivePlatform} from "../contracts/mocks/MockIncentivePlatform.sol";
import {AlwaysTrueTrustedValidator} from "./mocks/TrustedFactoryMocks.sol";
import {GaugeControllerAdmin} from "../contracts/GaugeControllerAdmin.sol";
import {RouterControllerMock, RouterDaoShim, RouterVm} from "./router/RouterMocks.sol";

/// @notice Integration matrix rows I01–I06 (plans/ROUTERPLAN-WITNESSES.json):
/// the ACTUAL unchanged CurveGaugeLister composed behind GaugeControllerAdmin
/// on a local mock controller (hostile-C modelling only; the fork rows bind
/// the real controller separately). Every falsifier-targeted subcase asserts
/// at its matrix named label.
contract GaugeControllerAdminIntegrationTest is TestBase {
    RouterVm internal constant rv = RouterVm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    uint256 internal constant FEE = 10_000e18;
    uint256 internal constant QUARTER = 2_500e18;
    uint256 internal constant WEEK = 604800;
    uint256 internal constant T0 = 1794441600; // Thursday 2026-11-12 00:00 UTC

    RouterControllerMock internal c;
    GaugeControllerAdmin internal r;
    RouterDaoShim internal dao; // the literal D pinned in R and in L.owner
    MockERC20 internal token;
    MockCurveRegistry internal registry;
    MockFeeDistributor internal fd;
    MockIncentivePlatform internal votium;
    MockIncentivePlatform internal voteMarket;
    CurveGaugeLister internal lister;
    AlwaysTrueTrustedValidator internal validator;

    address internal payer;
    address internal stranger;

    // ------------------------------------------------------------------
    // composition fixture
    // ------------------------------------------------------------------

    function _compose() internal {
        payer = actor("int-payer");
        stranger = actor("int-stranger");

        token = new MockERC20(18);
        registry = new MockCurveRegistry();
        dao = new RouterDaoShim();
        c = new RouterControllerMock(address(dao), 2);
        r = new GaugeControllerAdmin(address(c), address(dao));
        dao.setRouter(r);
        // seat R as C admin by the raw D→C two-step (the installed composition)
        vm.startPrank(address(dao));
        c.commit_transfer_ownership(address(r));
        c.apply_transfer_ownership();
        vm.stopPrank();
        require(c.admin() == address(r), "I seat");

        vm.warp(T0);
        fd = new MockFeeDistributor(address(token), actor("int-fdAdmin"), T0);
        votium = new MockIncentivePlatform(address(token));
        voteMarket = new MockIncentivePlatform(address(token));
        validator = new AlwaysTrueTrustedValidator();

        vm.chainId(1);
        lister = new CurveGaugeLister(
            address(dao), // owner_ = D
            address(token),
            address(r), // controller_ = R
            address(fd),
            CurveGaugeLister.AdmissionConfig(address(registry), 8),
            CurveGaugeLister.PlatformConfig(address(votium), address(voteMarket), 5000),
            address(validator)
        );
        require(lister.controller() == address(r), "L endpoint is R");
        require(lister.owner() == address(dao), "L owner is D");
        votium.setLister(address(lister));
        voteMarket.setLister(address(lister));
        token.mint(payer, 40 * FEE);
        vm.startPrank(payer);
        token.approve(address(lister), type(uint256).max);
        vm.stopPrank();
    }

    function _coins(address a, address b) internal pure returns (address[8] memory out) {
        out[0] = a;
        out[1] = b;
    }

    function _pool(uint256 handlerId, uint256 gaugeIndex, int128 gaugeType)
        internal
        returns (address pool, address gauge)
    {
        address lp = address(new MockERC20(18));
        pool = address(new MockPool());
        gauge = address(new MockGauge(lp));
        registry.setPool(pool, handlerId, lp, _coins(address(new MockERC20(18)), address(new MockERC20(18))), 2);
        registry.setGauge(pool, handlerId, gaugeIndex, gauge, gaugeType);
    }

    function _grantLister(bool enabled) internal {
        vm.prank(address(dao));
        r.grant(address(lister), enabled);
    }

    function _unpause() internal {
        vm.prank(address(dao));
        lister.setPaused(false);
    }

    // ------------------------------------------------------------------
    // whole-record state snapshot for rollback equality
    // ------------------------------------------------------------------

    struct World {
        uint256 payerBal;
        uint256 payerAllow;
        uint256 listerBal;
        uint256 routerBal;
        uint256 votiumBal;
        uint256 voteMarketBal;
        uint256 fdBal;
        uint256 escrow;
        uint256 cAdds;
        uint256 cAttempts;
        uint256 vDeposits;
        uint256 vmDeposits;
        bytes32 listingA;
        bytes32 listingB;
        int128 nGauges;
    }

    function _world(address gaugeA, address gaugeB) internal view returns (World memory w) {
        w.payerBal = token.balanceOf(payer);
        w.payerAllow = token.allowance(payer, address(lister));
        w.listerBal = token.balanceOf(address(lister));
        w.routerBal = token.balanceOf(address(r));
        w.votiumBal = token.balanceOf(address(votium));
        w.voteMarketBal = token.balanceOf(address(voteMarket));
        w.fdBal = token.balanceOf(address(fd));
        w.escrow = lister.totalEscrow();
        w.cAdds = c.addCalls();
        w.cAttempts = c.addAttempts();
        w.vDeposits = votium.depositCount();
        w.vmDeposits = voteMarket.depositCount();
        w.listingA = keccak256(abi.encode(lister.getListing(gaugeA)));
        w.listingB = keccak256(abi.encode(lister.getListing(gaugeB)));
        w.nGauges = c.n_gauges();
    }

    function _assertWorldEq(World memory a, World memory b, string memory label) internal pure {
        require(keccak256(abi.encode(a)) == keccak256(abi.encode(b)), label);
    }

    // ------------------------------------------------------------------
    // I01
    // ------------------------------------------------------------------

    function test_PaidZeroWeightCanonical() public {
        _compose();
        _grantLister(true);
        _unpause();
        c.setDefaultInitialWeight(777); // mock's own 2-arg default is nonzero

        (address poolA, address gaugeA) = _pool(0, 0, 0);
        World memory before = _world(address(0), address(0));
        uint256 payerBefore = token.balanceOf(payer);

        vm.prank(payer);
        lister.listGauge(poolA, gaugeA, 0, 0);

        // raw C received zero weight for the exact gauge and type
        require(c.lastAddSender() == address(r), "PAID_RAW_WEIGHT_ZERO sender R");
        require(c.get_gauge_weight(gaugeA) == 0, "PAID_RAW_WEIGHT_ZERO");
        require(c.gauge_types(gaugeA) == 0, "membership immediate");
        // exact fee accounting
        require(token.balanceOf(payer) == payerBefore - FEE, "fee charged");
        require(token.balanceOf(address(lister)) == FEE, "fee custody L");
        require(token.balanceOf(address(r)) == 0, "PAID_RAW_WEIGHT_ZERO R receives no fee");
        require(lister.totalEscrow() == FEE, "escrow reserved");
        CurveGaugeLister.Listing memory rec = lister.getListing(gaugeA);
        require(uint8(rec.status) == uint8(CurveGaugeLister.Status.Active), "Active");
        require(rec.payer == payer && rec.deposited == FEE && rec.remaining == FEE, "record exact");
        before;

        // owner-paid subcase: D itself pays and STILL gets raw zero weight
        token.mint(address(dao), 4 * FEE);
        vm.prank(address(dao));
        token.approve(address(lister), type(uint256).max);
        (address poolB, address gaugeB) = _pool(1, 1, 1);
        vm.prank(address(dao));
        lister.listGauge(poolB, gaugeB, 1, 1);
        require(c.get_gauge_weight(gaugeB) == 0, "PAID_RAW_WEIGHT_ZERO owner-paid");
        require(lister.getListing(gaugeB).payer == address(dao), "owner is the payer here");
        // mock's nonzero 2-arg default remains available (so zero is L's
        // doing, not a mock accident): the raw default path stamps 777.
        vm.prank(address(dao));
        r.execute(abi.encodeWithSignature("add_gauge(address,int128)", actor("g-def"), int128(0)));
        require(c.get_gauge_weight(actor("g-def")) == 777, "PAID_RAW_WEIGHT_ZERO nonzero default exists");
    }

    // ------------------------------------------------------------------
    // I02
    // ------------------------------------------------------------------

    function test_DaoFreeSuppliedWeightWhilePaused() public {
        _compose();
        _grantLister(true);
        require(lister.paused(), "I02 paid lane stays paused");

        (address poolA, address gaugeA) = _pool(0, 0, 1);
        uint256 payerBefore = token.balanceOf(payer);
        World memory before = _world(gaugeA, address(0));

        // D owner forwards a supplied NONZERO weight while paused.
        vm.prank(address(dao));
        lister.listGaugeNoEscrow(poolA, gaugeA, 0, 0, 4242);
        require(c.lastAddSender() == address(r), "DAO_FREE_SUPPLIED_WEIGHT sender R");
        require(c.get_gauge_weight(gaugeA) == 4242, "DAO_FREE_SUPPLIED_WEIGHT");
        require(c.gauge_types(gaugeA) == 1, "type preserved");
        require(lister.totalEscrow() == 0, "no escrow");
        require(token.balanceOf(payer) == payerBefore, "no fee");
        require(votium.depositCount() == 0 && voteMarket.depositCount() == 0, "no platform call");
        require(lister.getListing(gaugeA).pool == poolA, "record exists");
        require(lister.getListing(gaugeA).status == CurveGaugeLister.Status.DaoExempt, "DaoExempt");

        // zero weight is equally valid on this lane
        (address poolB, address gaugeB) = _pool(1, 0, 0);
        vm.prank(address(dao));
        lister.listGaugeNoEscrow(poolB, gaugeB, 0, 1, 0);
        require(c.get_gauge_weight(gaugeB) == 0, "DAO_FREE_SUPPLIED_WEIGHT zero ok");
        before;

        // Negative: non-owner lane fails as existing L requires.
        (address poolC, address gaugeC) = _pool(2, 0, 0);
        vm.prank(payer);
        vm.expectRevert(CurveGaugeLister.NotOwner.selector);
        lister.listGaugeNoEscrow(poolC, gaugeC, 0, 2, 1);
        require(!c.registered(gaugeC), "rejected lane no effect");
    }

    // ------------------------------------------------------------------
    // I03
    // ------------------------------------------------------------------

    function test_PreGrantAndRevokedBothLanesRollback() public {
        // Positive granted control first (same fixtures).
        _compose();
        _grantLister(true);
        _unpause();
        (address poolOk, address gaugeOk) = _pool(0, 0, 0);
        vm.prank(payer);
        lister.listGauge(poolOk, gaugeOk, 0, 0);
        require(c.registered(gaugeOk), "granted control adds");

        _preGrantRollback();
        _revokedRollback();
    }

    function _notAdderOnLister() internal view returns (bytes memory) {
        return abi.encodeWithSelector(GaugeControllerAdmin.NotAdder.selector, address(lister));
    }

    function _preGrantRollback() internal {
        // A fresh composition where L was never granted.
        _compose();
        _unpause();
        (address poolA, address gaugeA) = _pool(0, 0, 0);
        (address poolB, address gaugeB) = _pool(1, 0, 1);
        World memory pre = _world(gaugeA, gaugeB);
        (bool paidOk, bytes memory paidRet) = _lane(payer, poolA, gaugeA, 0, 0);
        require(!paidOk, "LISTER_AUTH_FRAME_AND_FULL_ROLLBACK paid");
        _revertMatches(paidRet, _notAdderOnLister(), "LISTER_AUTH_FRAME_AND_FULL_ROLLBACK paid frame");
        (bool daoOk, bytes memory daoRet) = _laneDao(poolB, gaugeB, 0, 1, 9);
        require(!daoOk, "LISTER_AUTH_FRAME_AND_FULL_ROLLBACK dao-free");
        _revertMatches(daoRet, _notAdderOnLister(), "LISTER_AUTH_FRAME_AND_FULL_ROLLBACK dao-free frame");
        _assertWorldEq(pre, _world(gaugeA, gaugeB), "LISTER_AUTH_FRAME_AND_FULL_ROLLBACK whole-tx rollback");
        require(c.addAttempts() == 0, "no C add attempted");
        require(!c.registered(gaugeA) && !c.registered(gaugeB), "no membership");
    }

    function _revokedRollback() internal {
        _compose();
        _unpause();
        _grantLister(true);
        (address poolC, address gaugeC) = _pool(2, 0, 0);
        vm.prank(payer);
        lister.listGauge(poolC, gaugeC, 0, 2);
        _grantLister(false);
        (address poolD, address gaugeD) = _pool(3, 0, 0);
        (address poolE, address gaugeE) = _pool(4, 0, 0);
        World memory pre2 = _world(gaugeD, gaugeE);
        (bool roOk, bytes memory roRet) = _lane(payer, poolD, gaugeD, 0, 3);
        require(!roOk, "revoked paid");
        _revertMatches(roRet, _notAdderOnLister(), "revoked paid frame");
        (bool rdOk, bytes memory rdRet) = _laneDao(poolE, gaugeE, 0, 4, 3);
        require(!rdOk, "revoked dao-free");
        _revertMatches(rdRet, _notAdderOnLister(), "revoked dao-free frame");
        _assertWorldEq(pre2, _world(gaugeD, gaugeE), "LISTER_AUTH_FRAME_AND_FULL_ROLLBACK revoked rollback");
        // the earlier committed listing is untouched by the revocation
        require(c.gauge_types(gaugeC) == 0, "committed listing kept");
    }

    function _lane(address who, address pool, address gauge, uint256 gaugeIndex, uint256 handlerId)
        internal
        returns (bool, bytes memory)
    {
        vm.prank(who);
        (bool ok, bytes memory ret) = address(lister)
            .call(abi.encodeWithSelector(CurveGaugeLister.listGauge.selector, pool, gauge, gaugeIndex, handlerId));
        return (ok, ret);
    }

    function _laneDao(address pool, address gauge, uint256 gaugeIndex, uint256 handlerId, uint256 weight)
        internal
        returns (bool, bytes memory)
    {
        vm.prank(address(dao));
        (bool ok, bytes memory ret) = address(lister)
            .call(
                abi.encodeWithSelector(
                    CurveGaugeLister.listGaugeNoEscrow.selector, pool, gauge, gaugeIndex, handlerId, weight
                )
            );
        return (ok, ret);
    }

    // ------------------------------------------------------------------
    // I04
    // ------------------------------------------------------------------

    function test_ControllerFailureAndPostcheckRollback() public {
        _compose();
        _grantLister(true);
        _unpause();

        // Ordinary synchronous positive with readback.
        (address poolOk, address gaugeOk) = _pool(0, 0, 0);
        vm.prank(payer);
        lister.listGauge(poolOk, gaugeOk, 0, 0);
        require(c.gauge_types(gaugeOk) == 0, "positive control");

        // Raw C failure bubbles through R unchanged.
        (address poolA, address gaugeA) = _pool(0, 1, 0);
        World memory pre = _world(gaugeA, address(0));
        c.setAddMode(1);
        (bool a1, bytes memory r1) = _lane(payer, poolA, gaugeA, 1, 0);
        c.setAddMode(0);
        require(!a1, "LISTER_POSTCHECK_FULL_ROLLBACK raw fail");
        require(_isErr(r1, RouterControllerMock.MockRejected.selector, ""), "raw failure bubbles exact");
        _assertWorldEq(pre, _world(gaugeA, address(0)), "LISTER_POSTCHECK_FULL_ROLLBACK raw fail");

        // Malformed membership read reverts the whole admission.
        (address poolB, address gaugeB) = _pool(0, 2, 0);
        pre = _world(gaugeB, address(0));
        c.setTypesMode(2);
        (bool a2,) = _lane(payer, poolB, gaugeB, 2, 0);
        c.setTypesMode(0);
        require(!a2, "LISTER_POSTCHECK_FULL_ROLLBACK malformed");
        _assertWorldEq(pre, _world(gaugeB, address(0)), "LISTER_POSTCHECK_FULL_ROLLBACK malformed");

        // Lying membership after add forces L's postcheck (MembershipFailed).
        (address poolC, address gaugeC) = _pool(0, 3, 0);
        pre = _world(gaugeC, address(0));
        c.setTypesMode(1); // gauge_types lies +100 once registered
        (bool a3, bytes memory r3) = _lane(payer, poolC, gaugeC, 3, 0);
        c.setTypesMode(0);
        require(!a3, "LISTER_POSTCHECK_FULL_ROLLBACK lying");
        require(_isErr(r3, CurveGaugeLister.MembershipFailed.selector, ""), "postcheck error");
        _assertWorldEq(pre, _world(gaugeC, address(0)), "LISTER_POSTCHECK_FULL_ROLLBACK lying");
        require(!c.registered(gaugeC), "registration rolled back");
    }

    function _revertMatches(bytes memory actual, bytes memory expected, string memory label) internal pure {
        require(keccak256(actual) == keccak256(expected), label);
    }

    function _isErr(bytes memory ret, bytes4 sel, bytes memory args) internal pure returns (bool) {
        if (ret.length != 4 + args.length) return false;
        bytes memory head = abi.encodePacked(sel);
        for (uint256 i = 0; i < 4; ++i) {
            if (head[i] != ret[i]) return false;
        }
        for (uint256 i = 0; i < args.length; ++i) {
            if (args[i] != ret[4 + i]) return false;
        }
        return true;
    }

    // ------------------------------------------------------------------
    // I05
    // ------------------------------------------------------------------

    function test_IndependentDaoRouteBypassesListerRestrictions() public {
        _compose();
        _unpause();
        _grantLister(false); // L revoked; its lane is dead

        // structurally unacceptable to L: pool absent from the registry
        address badPool = address(new MockPool());
        address badGauge = address(new MockGauge(address(new MockERC20(18))));

        // D's independent R.add_gauge works with the exact supplied weight.
        vm.prank(address(dao));
        r.add_gauge(badGauge, int128(1), uint256(4242));
        require(c.lastAddSender() == address(r), "DAO_ROUTE_NO_LISTER_DEPENDENCY sender");
        require(c.get_gauge_weight(badGauge) == 4242, "DAO_ROUTE_NO_LISTER_DEPENDENCY weight");
        require(c.gauge_types(badGauge) == 1, "membership");

        // D's raw execute administration works too (type weight).
        (bool eok,) = _callDao(
            address(r),
            abi.encodeWithSelector(
                GaugeControllerAdmin.execute.selector,
                abi.encodeWithSignature("add_type(string,uint256)", "indep", uint256(31337))
            )
        );
        require(eok && c.type_weight(2) == 31337, "DAO_ROUTE_NO_LISTER_DEPENDENCY add_type");

        // no L fee/state change at all
        require(token.balanceOf(address(lister)) == 0, "L gained nothing");
        require(lister.totalEscrow() == 0, "no escrow");
        require(lister.getListing(badGauge).status == CurveGaugeLister.Status.Unlisted, "no listing record");

        // L lanes still fail their real gates: unregistered pool.
        (bool l1, bytes memory lr1) = _lane(payer, badPool, badGauge, 0, 0);
        require(!l1, "paid lane accepted an already-registered gauge");
        require(_isErr(lr1, CurveGaugeLister.ControllerRegistryOccupied.selector, abi.encode(badGauge)), "L gate kept");

        // non-D cannot borrow the independent DAO route
        (bool n1, bytes memory nr1) = _call(
            actor("int-stranger"),
            address(r),
            abi.encodeWithSelector(
                GaugeControllerAdmin.execute.selector, abi.encodeWithSignature("add_type(string)", "nope")
            )
        );
        require(!n1, "non-D execute accepted");
        require(
            _isErr(nr1, GaugeControllerAdmin.NotDao.selector, abi.encode(actor("int-stranger"))),
            "DAO_ROUTE_NO_LISTER_DEPENDENCY gate"
        );
    }

    function _call(address from, address target, bytes memory data) internal returns (bool, bytes memory) {
        vm.prank(from);
        (bool ok, bytes memory ret) = target.call(data);
        return (ok, ret);
    }

    function _callDao(address target, bytes memory data) internal returns (bool, bytes memory) {
        return _call(address(dao), target, data);
    }

    // ------------------------------------------------------------------
    // I06
    // ------------------------------------------------------------------

    function test_ExistingEscrowSettlesAfterRevocationAndHandback() public {
        _compose();
        _grantLister(true);
        _unpause();

        (address poolA, address gaugeA) = _pool(0, 0, 0); // settles
        vm.prank(payer);
        lister.listGauge(poolA, gaugeA, 0, 0);
        (address poolB, address gaugeB) = _pool(1, 0, 0); // legitimately killed
        vm.prank(payer);
        lister.listGauge(poolB, gaugeB, 0, 1);

        // revoke + handback to D: R retires, C admin returns to D
        _grantLister(false);
        vm.startPrank(address(dao));
        r.commit_transfer_ownership(address(dao));
        r.apply_transfer_ownership();
        vm.stopPrank();
        require(r.retired() && c.admin() == address(dao), "SETTLEMENT_NO_ROUTER_DEPENDENCY retired");

        // separately legitimate kill (gauge flag, not router action)
        MockGauge(gaugeB).setKilled(true);

        // two matured quarters then settle
        vm.warp(T0 + 2 * WEEK + 1);
        uint256 cAddsBefore = c.addAttempts();
        uint256 marksBefore = c.markCalls();

        // freeze all router/controller activity: settlement must not touch R.
        // Lying membership reads would corrupt any controller-dependent
        // settlement; counters prove no controller interaction at all.
        c.setTypesMode(1);

        (uint256 releasedA, uint256 confiscatedA) = lister.checkpoint(gaugeA);
        require(releasedA == 2 * QUARTER && confiscatedA == 0, "SETTLEMENT_NO_ROUTER_DEPENDENCY release");
        (uint256 releasedB, uint256 confiscatedB) = lister.checkpoint(gaugeB);
        require(releasedB == 0 && confiscatedB == FEE, "confiscation to FD");
        require(token.balanceOf(address(fd)) == FEE, "FD custody exact");
        require(
            token.balanceOf(address(votium)) + token.balanceOf(address(voteMarket)) == 2 * QUARTER,
            "platforms funded exactly"
        );
        c.setTypesMode(0);
        require(lister.totalEscrow() == 2 * QUARTER, "remaining escrow kept");
        require(
            c.addAttempts() == cAddsBefore && c.markCalls() == marksBefore,
            "SETTLEMENT_NO_ROUTER_DEPENDENCY no controller calls"
        );
        require(c.n_gauges() == 2 && c.get_gauge_weight(gaugeA) == 0, "no membership/refund caused");
        require(r.retired(), "SETTLEMENT_NO_ROUTER_DEPENDENCY still retired");
        require(rv.load(address(r), bytes32(uint256(2))) == bytes32(uint256(1)), "router lock idle");
    }
}
