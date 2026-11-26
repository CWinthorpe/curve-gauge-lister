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

/// @dev routerfix5 (h)/I02: zero-count expectCall form (foundry's
/// expectCall(address,bytes,uint64); count 0 asserts NON-occurrence).
/// Declared locally — the shared Vm/RouterVm interfaces are not edited.
interface ExpectCallVm {
    function expectCall(address callee, bytes calldata data, uint64 expectedCount) external;
}

/// @notice Integration matrix rows I01–I06 (plans/ROUTERPLAN-WITNESSES.json):
/// the ACTUAL unchanged CurveGaugeLister composed behind GaugeControllerAdmin
/// on a local mock controller (hostile-C modelling only; the fork rows bind
/// the real controller separately). Every falsifier-targeted subcase asserts
/// at its matrix named label.
contract GaugeControllerAdminIntegrationTest is TestBase {
    RouterVm internal constant rv = RouterVm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
    ExpectCallVm internal constant cc = ExpectCallVm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

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
        // CONF-04: complete keyed observations — membership weight/state of
        // the SELECTED candidates and the lister's platform allowances.
        uint256 weightA;
        uint256 weightB;
        bool regA;
        bool regB;
        int128 typeA;
        int128 typeB;
        uint256 allowListerVotium;
        uint256 allowListerVoteMarket;
        // routerfix5 (f) per plans/ROUTERPLAN-WITNESSES.md:10: router
        // grants/pending/retired lifecycle, adapter keyed AND chronological
        // receipts (ordered ladder digest over both venues x both gauges x
        // three scheduled quarters) and the remaining platform approvals.
        bool adderLister;
        bool adderStranger;
        address pendingR;
        bool retiredR;
        bytes32 lockWord;
        bytes32 adapterReceiptsDigest;
        uint256 allowPayerVotium;
        uint256 allowPayerVoteMarket;
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
        w.weightA = c.get_gauge_weight(gaugeA);
        w.weightB = c.get_gauge_weight(gaugeB);
        w.regA = c.registered(gaugeA);
        w.regB = c.registered(gaugeB);
        if (w.regA) w.typeA = c.gauge_types(gaugeA);
        if (w.regB) w.typeB = c.gauge_types(gaugeB);
        w.allowListerVotium = token.allowance(address(lister), address(votium));
        w.allowListerVoteMarket = token.allowance(address(lister), address(voteMarket));
        // routerfix5 (f): full snapshot completion.
        w.adderLister = r.isAdder(address(lister));
        w.adderStranger = r.isAdder(stranger);
        w.pendingR = r.pendingControllerAdmin();
        w.retiredR = r.retired();
        w.lockWord = rv.load(address(r), bytes32(uint256(2)));
        uint256 eq0 = (block.timestamp / WEEK) * WEEK;
        address[2] memory ladderGauges = [gaugeA, gaugeB];
        bytes memory ladder;
        for (uint256 gi = 0; gi < 2; ++gi) {
            for (uint256 ei = 0; ei < 3; ++ei) {
                (uint256 va, uint256 vex, bytes32 vrc) = votium.getDeposit(ladderGauges[gi], eq0 + ei * WEEK);
                (uint256 ma, uint256 mex, bytes32 mrc) = voteMarket.getDeposit(ladderGauges[gi], eq0 + ei * WEEK);
                ladder = abi.encodePacked(ladder, va, vex, vrc, ma, mex, mrc);
            }
        }
        w.adapterReceiptsDigest = keccak256(ladder);
        w.allowPayerVotium = token.allowance(payer, address(votium));
        w.allowPayerVoteMarket = token.allowance(payer, address(voteMarket));
    }

    function _assertWorldEq(World memory a, World memory b, string memory label) internal pure {
        require(keccak256(abi.encode(a)) == keccak256(abi.encode(b)), label);
    }

    /// @dev routerfix5 (f)/(h): complete single-log lookup — emitter, FULL
    /// topics array and exact data bytes.
    function _countExactLogUnit(RouterVm.Log[] memory logs, address emitter, bytes32[] memory topics, bytes memory data)
        internal
        pure
        returns (uint256 hits)
    {
        bytes32 wantDataHash = keccak256(data);
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].emitter != emitter) continue;
            if (logs[i].topics.length != topics.length) continue;
            bool same = true;
            for (uint256 j = 0; j < topics.length; ++j) {
                if (logs[i].topics[j] != topics[j]) {
                    same = false;
                    break;
                }
            }
            if (!same) continue;
            if (keccak256(logs[i].data) != wantDataHash) continue;
            hits += 1;
        }
    }

    /// @dev routerfix5 (f)/(h): the complete committed receipt set of one
    /// admission — real C mock NewGauge, router GaugeAdded and lister
    /// GaugeListed, each compared as full payload (not counts).
    function _assertAdmissionLogs(
        RouterVm.Log[] memory logs,
        address gauge,
        address pool,
        address payerAddr,
        int128 wantType,
        uint256 wantWeight,
        uint256 listingEpoch,
        uint256 fee,
        bool daoExempt,
        string memory tag
    ) internal view {
        bytes32[] memory cT = new bytes32[](1);
        cT[0] = keccak256("NewGauge(address,int128,uint256)");
        require(
            _countExactLogUnit(logs, address(c), cT, abi.encode(gauge, wantType, wantWeight)) == 1,
            string.concat(tag, " C NewGauge full payload")
        );
        bytes32[] memory rT = new bytes32[](3);
        rT[0] = keccak256("GaugeAdded(address,address,int128,uint256)");
        rT[1] = bytes32(uint256(uint160(address(lister))));
        rT[2] = bytes32(uint256(uint160(gauge)));
        require(
            _countExactLogUnit(logs, address(r), rT, abi.encode(wantType, wantWeight)) == 1,
            string.concat(tag, " R GaugeAdded full payload")
        );
        bytes32[] memory gT = new bytes32[](4);
        gT[0] = keccak256("GaugeListed(address,address,address,int128,uint256,uint256,bool)");
        gT[1] = bytes32(uint256(uint160(gauge)));
        gT[2] = bytes32(uint256(uint160(pool)));
        gT[3] = bytes32(uint256(uint160(payerAddr)));
        require(
            _countExactLogUnit(logs, address(lister), gT, abi.encode(wantType, listingEpoch, fee, daoExempt)) == 1,
            string.concat(tag, " L GaugeListed full payload")
        );
    }

    /// @dev routerfix5 (h)/I01: the ENTIRE admission record, field by field
    /// (15 fields), not three selected members.
    function _assertFullRecord(
        CurveGaugeLister.Listing memory rec,
        address pool,
        address payerAddr,
        int128 wantType,
        uint256 fee,
        CurveGaugeLister.Status wantStatus,
        uint256 handlerId,
        string memory tag
    ) internal view {
        require(rec.pool == pool, string.concat(tag, " pool"));
        require(rec.lpToken == registry.get_lp_token(pool, handlerId), string.concat(tag, " lpToken"));
        require(rec.payer == payerAddr, string.concat(tag, " payer"));
        require(rec.admissionRegistry == address(registry), string.concat(tag, " admissionRegistry"));
        require(rec.gaugeType == wantType, string.concat(tag, " gaugeType"));
        require(rec.listingEpoch == lister.epochStart(block.timestamp), string.concat(tag, " listingEpoch"));
        require(rec.status == wantStatus, string.concat(tag, " status"));
        require(rec.epochsReleased == 0, string.concat(tag, " epochsReleased"));
        require(rec.deposited == fee, string.concat(tag, " deposited"));
        require(rec.remaining == fee, string.concat(tag, " remaining"));
        require(rec.released == 0, string.concat(tag, " released"));
        require(rec.confiscated == 0, string.concat(tag, " confiscated"));
        // the paid lane freezes the platform snapshot into the record; the
        // DAO lane stamps it zero (DaoExempt keeps zero venue endpoints).
        if (wantStatus == CurveGaugeLister.Status.Active) {
            require(rec.votium == address(votium), string.concat(tag, " votium snapshot"));
            require(rec.voteMarket == address(voteMarket), string.concat(tag, " voteMarket snapshot"));
            require(rec.votiumBps == 5000, string.concat(tag, " votiumBps snapshot"));
        } else {
            require(
                rec.votium == address(0) && rec.voteMarket == address(0) && rec.votiumBps == 0,
                string.concat(tag, " zero venue snapshot")
            );
        }
    }

    /// @dev routerfix5 (h): full before/after comparison of the untouched
    /// World fields (everything except the caller-pinned per-row deltas,
    /// which each row asserts explicitly against the 'before' snapshot).
    function _assertMoneyUntouched(World memory pre, World memory post, string memory tag) internal pure {
        require(post.routerBal == pre.routerBal && post.routerBal == 0, string.concat(tag, " R holds nothing"));
        require(post.fdBal == pre.fdBal, string.concat(tag, " FD untouched"));
        require(
            post.votiumBal == pre.votiumBal && post.voteMarketBal == pre.voteMarketBal,
            string.concat(tag, " venues funded nothing")
        );
        require(
            post.vDeposits == pre.vDeposits && post.vmDeposits == pre.vmDeposits,
            string.concat(tag, " no platform deposits")
        );
        require(
            post.adapterReceiptsDigest == pre.adapterReceiptsDigest,
            string.concat(tag, " adapter receipt ladder untouched")
        );
        require(
            post.allowListerVotium == pre.allowListerVotium && post.allowListerVoteMarket == pre.allowListerVoteMarket,
            string.concat(tag, " lister approvals untouched")
        );
        require(
            post.allowPayerVotium == pre.allowPayerVotium && post.allowPayerVoteMarket == pre.allowPayerVoteMarket,
            string.concat(tag, " payer venue approvals untouched")
        );
        require(
            post.adderLister == pre.adderLister && post.adderStranger == pre.adderStranger
                && post.pendingR == pre.pendingR && post.retiredR == pre.retiredR && post.lockWord == pre.lockWord,
            string.concat(tag, " router lifecycle untouched")
        );
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
        World memory before = _world(gaugeA, address(0));
        uint256 payerBefore = token.balanceOf(payer);

        // routerfix5 (h)/I01 (review/ROUTERCONF.md:319-321; ROUTERCONF2.md:
        // 266-267): the 'before' snapshot is now USED — full comparison with
        // exact expected deltas around the paid admission, the COMPLETE
        // committed-log payload set (NewGauge/GaugeAdded/GaugeListed, not
        // counts) and the validator frame bound to exactly one call on this
        // lane (its zero-occurrence counterpart is asserted in I02).
        cc.expectCall(address(validator), abi.encodeWithSignature("validateGauge(address)", gaugeA), 1);
        rv.recordLogs();
        vm.prank(payer);
        lister.listGauge(poolA, gaugeA, 0, 0);
        RouterVm.Log[] memory logsA = rv.getRecordedLogs();

        // raw C received zero weight for the exact gauge and type
        require(c.lastAddSender() == address(r), "PAID_RAW_WEIGHT_ZERO sender R");
        require(c.get_gauge_weight(gaugeA) == 0, "PAID_RAW_WEIGHT_ZERO");
        require(c.gauge_types(gaugeA) == 0, "membership immediate");
        // exact fee accounting
        require(token.balanceOf(payer) == payerBefore - FEE, "fee charged");
        require(token.balanceOf(address(lister)) == FEE, "fee custody L");
        require(token.balanceOf(address(r)) == 0, "PAID_RAW_WEIGHT_ZERO R receives no fee");
        require(lister.totalEscrow() == FEE, "escrow reserved");
        CurveGaugeLister.Listing memory recA = lister.getListing(gaugeA);
        _assertFullRecord(
            recA, poolA, payer, int128(0), FEE, CurveGaugeLister.Status.Active, 0, "PAID_RAW_WEIGHT_ZERO recA"
        );

        // whole-snapshot comparison against 'before': ONLY the documented
        // paid-lane effects differ.
        _i01PaidDeltas(before, _world(gaugeA, address(0)), "I01");
        require(logsA.length == 3, "PAID_RAW_WEIGHT_ZERO paid A committed log set");
        _assertAdmissionLogs(
            logsA, gaugeA, poolA, payer, int128(0), 0, recA.listingEpoch, FEE, false, "PAID_RAW_WEIGHT_ZERO paid A"
        );

        // owner-paid subcase: D itself pays and STILL gets raw zero weight
        token.mint(address(dao), 4 * FEE);
        vm.prank(address(dao));
        token.approve(address(lister), type(uint256).max);
        (address poolB, address gaugeB) = _pool(1, 1, 1);
        World memory beforeB = _world(gaugeB, gaugeA);
        uint256 daoBefore = token.balanceOf(address(dao));
        cc.expectCall(address(validator), abi.encodeWithSignature("validateGauge(address)", gaugeB), 1);
        rv.recordLogs();
        vm.prank(address(dao));
        lister.listGauge(poolB, gaugeB, 1, 1);
        RouterVm.Log[] memory logsB = rv.getRecordedLogs();
        require(c.get_gauge_weight(gaugeB) == 0, "PAID_RAW_WEIGHT_ZERO owner-paid");
        require(c.gauge_types(gaugeB) == 1, "PAID_RAW_WEIGHT_ZERO owner-paid type forwarded");
        CurveGaugeLister.Listing memory recB = lister.getListing(gaugeB);
        require(recB.payer == address(dao), "owner is the payer here");
        _assertFullRecord(
            recB, poolB, address(dao), int128(1), FEE, CurveGaugeLister.Status.Active, 1, "PAID_RAW_WEIGHT_ZERO recB"
        );
        _i01OwnerPaidDeltas(beforeB, _world(gaugeB, gaugeA));
        require(logsB.length == 3, "PAID_RAW_WEIGHT_ZERO paid B committed log set");
        _assertAdmissionLogs(
            logsB,
            gaugeB,
            poolB,
            address(dao),
            int128(1),
            0,
            recB.listingEpoch,
            FEE,
            false,
            "PAID_RAW_WEIGHT_ZERO paid B"
        );
        // and the actual fee movements of the owner-paid subcase:
        require(token.balanceOf(address(dao)) == daoBefore - FEE, "I01 owner fee exact");
        require(token.balanceOf(address(lister)) == 2 * FEE, "I01 lister holds both fees");

        // mock's nonzero 2-arg default remains available (so zero is L's
        // doing, not a mock accident): the raw default path stamps 777.
        vm.prank(address(dao));
        r.execute(abi.encodeWithSignature("add_gauge(address,int128)", actor("g-def"), int128(0)));
        require(c.get_gauge_weight(actor("g-def")) == 777, "PAID_RAW_WEIGHT_ZERO nonzero default exists");
    }

    /// @dev routerfix5 (h)/I01: complete before/after comparison for one
    /// paid admission (stack-lean: every delta assertion lives here).
    function _i01PaidDeltas(World memory pre, World memory post, string memory tag) internal pure {
        require(post.payerBal == pre.payerBal - FEE, string.concat(tag, " payer balance delta exact"));
        require(post.payerAllow == pre.payerAllow - FEE, string.concat(tag, " payer approval consumption exact"));
        require(post.listerBal == pre.listerBal + FEE, string.concat(tag, " lister custody delta exact"));
        require(post.escrow == pre.escrow + FEE, string.concat(tag, " escrow delta exact"));
        require(
            post.cAdds == pre.cAdds + 1 && post.cAttempts == pre.cAttempts + 1,
            string.concat(tag, " controller add deltas")
        );
        require(post.nGauges == pre.nGauges + 1, string.concat(tag, " gauge count delta"));
        require(post.regA && post.typeA == 0 && post.weightA == 0, string.concat(tag, " keyed zero membership"));
        require(post.listingA != pre.listingA, string.concat(tag, " listing record written"));
        require(post.listingB == pre.listingB, string.concat(tag, " other listing untouched"));
        _assertMoneyUntouched(pre, post, tag);
    }

    /// @dev routerfix5 (h)/I01 owner-paid subcase: same full comparison with
    /// the earlier record's fields pinned unchanged.
    function _i01OwnerPaidDeltas(World memory pre, World memory post) internal pure {
        // snapshot slots: A = the new owner-paid gauge, B = the earlier one.
        require(post.payerBal == pre.payerBal, "I01 owner-paid leaves payer alone");
        require(post.payerAllow == pre.payerAllow, "I01 owner-paid leaves payer approval alone");
        require(post.listingB == pre.listingB, "I01 earlier record untouched");
        require(post.cAdds == pre.cAdds + 1 && post.cAttempts == pre.cAttempts + 1, "I01 owner-paid add delta");
        require(post.nGauges == pre.nGauges + 1, "I01 owner-paid count delta");
        require(post.listingA != pre.listingA, "I01 owner-paid record written");
        require(post.regA && post.typeA == 1 && post.weightA == 0, "I01 owner-paid keyed zero membership");
        _assertMoneyUntouched(pre, post, "I01 owner-paid");
    }

    // ------------------------------------------------------------------
    // I02
    // ------------------------------------------------------------------

    function test_DaoFreeSuppliedWeightWhilePaused() public {
        _compose();
        _grantLister(true);
        require(lister.paused(), "I02 paid lane stays paused");

        (address poolA, address gaugeA) = _pool(0, 0, 1);
        (address poolB, address gaugeB) = _pool(1, 0, 0);
        (address poolC, address gaugeC) = _pool(2, 0, 0);
        uint256 payerBefore = token.balanceOf(payer);
        World memory before = _world(gaugeA, gaugeB);

        // routerfix5 (h)/I02 (review/ROUTERCONF.md:319-321; ROUTERCONF2.md:
        // 268-270): VALIDATOR-CALL NON-OCCURRENCE is now asserted for every
        // DAO-free candidate (zero-count expectCall), the 'before' snapshot
        // drives a FULL comparison, and the paid-lane control at the end of
        // this row proves the zero-count oracle discriminates occurrence
        // from absence.
        cc.expectCall(address(validator), abi.encodeWithSignature("validateGauge(address)", gaugeA), 0);
        cc.expectCall(address(validator), abi.encodeWithSignature("validateGauge(address)", gaugeB), 0);
        cc.expectCall(address(validator), abi.encodeWithSignature("validateGauge(address)", gaugeC), 0);

        // D owner forwards a supplied NONZERO weight while paused.
        rv.recordLogs();
        vm.prank(address(dao));
        lister.listGaugeNoEscrow(poolA, gaugeA, 0, 0, 4242);
        RouterVm.Log[] memory logsA = rv.getRecordedLogs();
        require(c.lastAddSender() == address(r), "DAO_FREE_SUPPLIED_WEIGHT sender R");
        require(c.get_gauge_weight(gaugeA) == 4242, "DAO_FREE_SUPPLIED_WEIGHT");
        require(c.gauge_types(gaugeA) == 1, "type preserved");
        require(lister.totalEscrow() == 0, "no escrow");
        require(token.balanceOf(payer) == payerBefore, "no fee");
        require(votium.depositCount() == 0 && voteMarket.depositCount() == 0, "no platform call");
        CurveGaugeLister.Listing memory recA = lister.getListing(gaugeA);
        require(recA.pool == poolA, "record exists");
        require(recA.status == CurveGaugeLister.Status.DaoExempt, "DaoExempt");
        _assertFullRecord(
            recA, poolA, address(0), int128(1), 0, CurveGaugeLister.Status.DaoExempt, 0, "DAO_FREE_SUPPLIED_WEIGHT recA"
        );
        require(logsA.length == 3, "DAO_FREE_SUPPLIED_WEIGHT A committed log set");
        _assertAdmissionLogs(logsA, gaugeA, poolA, address(0), int128(1), 4242, recA.listingEpoch, 0, true, "I02 A");

        // zero weight is equally valid on this lane
        vm.prank(address(dao));
        lister.listGaugeNoEscrow(poolB, gaugeB, 0, 1, 0);
        RouterVm.Log[] memory logsB = rv.getRecordedLogs();
        require(c.get_gauge_weight(gaugeB) == 0, "DAO_FREE_SUPPLIED_WEIGHT zero ok");
        require(c.gauge_types(gaugeB) == 0, "DAO_FREE_SUPPLIED_WEIGHT B type kept");
        require(logsB.length == 3, "DAO_FREE_SUPPLIED_WEIGHT B committed log set");
        CurveGaugeLister.Listing memory recB = lister.getListing(gaugeB);
        _assertAdmissionLogs(logsB, gaugeB, poolB, address(0), int128(0), 0, recB.listingEpoch, 0, true, "I02 B");

        // Full comparison against the 'before' snapshot: exactly the two
        // DAO-free admissions moved; nothing monetary, platform- or
        // router-lifecycle-related did.
        _i02DaoFreeDeltas(before, _world(gaugeA, gaugeB));

        // Negative: non-owner lane fails as existing L requires.
        World memory preC = _world(gaugeC, address(0));
        vm.prank(payer);
        vm.expectRevert(CurveGaugeLister.NotOwner.selector);
        lister.listGaugeNoEscrow(poolC, gaugeC, 0, 2, 1);
        require(!c.registered(gaugeC), "rejected lane no effect");
        _assertWorldEq(preC, _world(gaugeC, address(0)), "I02 rejected lane full rollback incl receipts");

        // Non-occurrence CONTROL for the oracle above: the PAID lane does
        // read the pinned validator for its own candidate.
        (address poolP, address gaugeP) = _pool(4, 0, 0);
        cc.expectCall(address(validator), abi.encodeWithSignature("validateGauge(address)", gaugeP), 1);
        _unpause();
        vm.prank(payer);
        lister.listGauge(poolP, gaugeP, 0, 4);
        require(c.get_gauge_weight(gaugeP) == 0, "I02 paid control admitted at raw zero");
    }

    /// @dev routerfix5 (h)/I02: the full before/after comparison for the two
    /// DAO-free admissions (stack-lean helper).
    function _i02DaoFreeDeltas(World memory pre, World memory post) internal pure {
        require(post.payerBal == pre.payerBal, "I02 no fee touched payer");
        require(post.payerAllow == pre.payerAllow, "I02 payer approval untouched");
        require(post.listerBal == pre.listerBal && post.listerBal == 0, "I02 lister took no fee");
        require(post.escrow == pre.escrow && post.escrow == 0, "I02 no escrow");
        require(post.cAdds == pre.cAdds + 2 && post.cAttempts == pre.cAttempts + 2, "I02 add deltas exact");
        require(post.nGauges == pre.nGauges + 2, "I02 count delta exact");
        require(post.regA && post.typeA == 1 && post.weightA == 4242, "I02 literal supplied weight kept");
        require(post.regB && post.typeB == 0 && post.weightB == 0, "I02 literal zero weight kept");
        require(post.listingA != pre.listingA && post.listingB != pre.listingB, "I02 records written");
        _assertMoneyUntouched(pre, post, "I02");
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
        require(!pre.adderLister, "I03 pre-grant baseline: L ungranted");
        require(
            pre.pendingR == address(0) && !pre.retiredR && pre.lockWord == bytes32(uint256(1)),
            "I03 router lifecycle baseline"
        );
        // Trace-frame inspection per WITNESSES:10: the fee transfer frame
        // DOES execute inside the rejected admission and then rolls back
        // with the whole transaction — observed as a call frame (raw
        // expectation), while the committed oracle is the state equality.
        cc.expectCall(
            address(token),
            abi.encodeWithSignature("transferFrom(address,address,uint256)", payer, address(lister), FEE),
            1
        );
        rv.recordLogs();
        (bool paidOk, bytes memory paidRet) = _lane(payer, poolA, gaugeA, 0, 0);
        require(!paidOk, "LISTER_AUTH_FRAME_AND_FULL_ROLLBACK paid");
        _revertMatches(paidRet, _notAdderOnLister(), "LISTER_AUTH_FRAME_AND_FULL_ROLLBACK paid frame");
        (bool daoOk, bytes memory daoRet) = _laneDao(poolB, gaugeB, 0, 1, 9);
        require(!daoOk, "LISTER_AUTH_FRAME_AND_FULL_ROLLBACK dao-free");
        _revertMatches(daoRet, _notAdderOnLister(), "LISTER_AUTH_FRAME_AND_FULL_ROLLBACK dao-free frame");
        // routerfix5 (f): the rejection happened at R's gate before any
        // emit — zero log delta from ANY emitter, not just a filter.
        require(rv.getRecordedLogs().length == 0, "LISTER_AUTH_FRAME_AND_FULL_ROLLBACK no logs from any emitter");
        _assertWorldEq(pre, _world(gaugeA, gaugeB), "LISTER_AUTH_FRAME_AND_FULL_ROLLBACK whole-tx rollback");
        require(c.addAttempts() == 0, "no C add attempted");
        require(!c.registered(gaugeA) && !c.registered(gaugeB), "no membership");

        // Enclosing catch/batch pair: the SAME lane commits once genuinely
        // granted — recorder liveness plus the full committed receipt set.
        _grantLister(true);
        _i03PreGrantControl(pre, gaugeA, gaugeB);
    }

    /// @dev routerfix5 (f): pre-grant fixture's committed control (stack-
    /// lean helper). Everything that moved post-control is accounted for;
    /// the two rejected candidates remain absent from every field.
    function _i03PreGrantControl(World memory pre, address gaugeA, address gaugeB) internal {
        rv.recordLogs();
        (address poolPc, address gaugePc) = _pool(5, 0, 0);
        vm.prank(address(dao));
        lister.listGaugeNoEscrow(poolPc, gaugePc, 0, 5, 7);
        RouterVm.Log[] memory ctl = rv.getRecordedLogs();
        require(ctl.length == 3, "I03 committed control logged three");
        CurveGaugeLister.Listing memory recPc = lister.getListing(gaugePc);
        _assertAdmissionLogs(ctl, gaugePc, poolPc, address(0), int128(0), 7, recPc.listingEpoch, 0, true, "I03 control");
        World memory postCtl = _world(gaugeA, gaugeB);
        require(!postCtl.regA && !postCtl.regB, "I03 rejected candidates never appeared");
        require(postCtl.listingA == pre.listingA && postCtl.listingB == pre.listingB, "I03 rejected listings absent");
        require(postCtl.cAdds == pre.cAdds + 1 && postCtl.nGauges == pre.nGauges + 1, "I03 only the control committed");
        require(postCtl.adderLister, "I03 grant committed");
        require(postCtl.adapterReceiptsDigest == pre.adapterReceiptsDigest, "I03 receipts still untouched");
    }

    function _revokedRollback() internal {
        _compose();
        _unpause();
        _grantLister(true);
        (address poolC, address gaugeC) = _pool(2, 0, 0);
        // fee frames: the committed control add plus the rolled-back revoked
        // paid attempt (registered before both; counted from here).
        cc.expectCall(
            address(token),
            abi.encodeWithSignature("transferFrom(address,address,uint256)", payer, address(lister), FEE),
            2
        );
        rv.recordLogs();
        vm.prank(payer);
        lister.listGauge(poolC, gaugeC, 0, 2);
        bytes32 recCHash = _i03RevokedControl(rv.getRecordedLogs(), poolC, gaugeC);
        _grantLister(false);
        _i03RevokedNegatives(recCHash, poolC, gaugeC);
    }

    /// @dev routerfix5 (f): the genuinely admitted FIRST member of the
    /// revoked subfixture, fully observed (record + complete committed log
    /// payloads) BEFORE the revocation; returns its byte-for-byte record
    /// hash for the kept-state comparison.
    function _i03RevokedControl(RouterVm.Log[] memory logsC, address poolC, address gaugeC)
        internal
        view
        returns (bytes32)
    {
        require(logsC.length == 3, "I03 revoked-fixture control logged three");
        CurveGaugeLister.Listing memory recC = lister.getListing(gaugeC);
        _assertFullRecord(recC, poolC, payer, int128(0), FEE, CurveGaugeLister.Status.Active, 2, "I03 gaugeC");
        _assertAdmissionLogs(logsC, gaugeC, poolC, payer, int128(0), 0, recC.listingEpoch, FEE, false, "I03 gaugeC");
        return keccak256(abi.encode(recC));
    }

    function _i03RevokedNegatives(bytes32 recCHash, address poolC, address gaugeC) internal {
        (address poolD, address gaugeD) = _pool(3, 0, 0);
        (address poolE, address gaugeE) = _pool(4, 0, 0);
        World memory pre2 = _world(gaugeD, gaugeE);
        require(!pre2.adderLister, "I03 revoked baseline: flag cleared");
        rv.recordLogs();
        (bool roOk, bytes memory roRet) = _lane(payer, poolD, gaugeD, 0, 3);
        require(!roOk, "revoked paid");
        _revertMatches(roRet, _notAdderOnLister(), "revoked paid frame");
        (bool rdOk, bytes memory rdRet) = _laneDao(poolE, gaugeE, 0, 4, 3);
        require(!rdOk, "revoked dao-free");
        _revertMatches(rdRet, _notAdderOnLister(), "revoked dao-free frame");
        require(
            rv.getRecordedLogs().length == 0, "LISTER_AUTH_FRAME_AND_FULL_ROLLBACK revoked no logs from any emitter"
        );
        _assertWorldEq(pre2, _world(gaugeD, gaugeE), "LISTER_AUTH_FRAME_AND_FULL_ROLLBACK revoked rollback");
        _i03CommittedKept(recCHash, poolC, gaugeC);
    }

    /// @dev routerfix5 (f): the earlier committed listing is untouched by the
    /// revocation — complete record, membership, weight and counters, not a
    /// selected-field spot check.
    function _i03CommittedKept(bytes32 recCHash, address poolC, address gaugeC) internal view {
        CurveGaugeLister.Listing memory recC2 = lister.getListing(gaugeC);
        require(keccak256(abi.encode(recC2)) == recCHash, "committed listing kept byte-for-byte");
        _assertFullRecord(recC2, poolC, payer, int128(0), FEE, CurveGaugeLister.Status.Active, 2, "I03 gaugeC kept");
        require(c.gauge_types(gaugeC) == 0 && c.get_gauge_weight(gaugeC) == 0, "committed listing kept");
        require(c.registered(gaugeC), "committed membership kept");
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

        // Ordinary synchronous positive with readback — logged completely
        // (routerfix5 (f): full committed receipt set for the positive too).
        (address poolOk, address gaugeOk) = _pool(0, 0, 0);
        rv.recordLogs();
        vm.prank(payer);
        lister.listGauge(poolOk, gaugeOk, 0, 0);
        RouterVm.Log[] memory logsOk = rv.getRecordedLogs();
        require(c.gauge_types(gaugeOk) == 0, "positive control");
        require(logsOk.length == 3, "I04 positive committed log set");
        CurveGaugeLister.Listing memory recOk = lister.getListing(gaugeOk);
        _assertFullRecord(recOk, poolOk, payer, int128(0), FEE, CurveGaugeLister.Status.Active, 0, "I04 ok");
        _assertAdmissionLogs(
            logsOk, gaugeOk, poolOk, payer, int128(0), 0, recOk.listingEpoch, FEE, false, "I04 positive"
        );

        // Raw C failure bubbles through R unchanged.
        (address poolA, address gaugeA) = _pool(0, 1, 0);
        World memory pre = _world(gaugeA, address(0));
        c.setAddMode(1);
        // the fee frame runs inside EVERY rejected paid admission below
        // (the pull precedes the controller seat in listGauge): raw fail,
        // malformed read and lying membership = 3 executed-then-rolled-back
        // transferFrom frames. The committed oracle stays the full-state
        // equality; this is the WITNESSES:10 trace-frame inspection.
        cc.expectCall(
            address(token),
            abi.encodeWithSignature("transferFrom(address,address,uint256)", payer, address(lister), FEE),
            3
        );
        rv.recordLogs();
        (bool a1, bytes memory r1) = _lane(payer, poolA, gaugeA, 1, 0);
        c.setAddMode(0);
        require(!a1, "LISTER_POSTCHECK_FULL_ROLLBACK raw fail");
        require(_isErr(r1, RouterControllerMock.MockRejected.selector, ""), "raw failure bubbles exact");
        // routerfix5 (f): the add attempt failed inside C BEFORE any emit —
        // the whole rejected admission leaves no log entry from ANY emitter
        // (not a lister/venue filter), and the World equality (incl. R
        // lifecycle and the receipt ladder) is the committed oracle.
        require(rv.getRecordedLogs().length == 0, "LISTER_POSTCHECK_FULL_ROLLBACK raw fail no logs from any emitter");
        _assertWorldEq(pre, _world(gaugeA, address(0)), "LISTER_POSTCHECK_FULL_ROLLBACK raw fail");

        // Malformed membership read reverts the whole admission.
        (address poolB, address gaugeB) = _pool(0, 2, 0);
        pre = _world(gaugeB, address(0));
        c.setTypesMode(2);
        rv.recordLogs();
        (bool a2,) = _lane(payer, poolB, gaugeB, 2, 0);
        c.setTypesMode(0);
        require(!a2, "LISTER_POSTCHECK_FULL_ROLLBACK malformed");
        {
            // routerfix5 (f) / WITNESSES:10 committed-vs-trace oracle: the
            // inner frames DID execute (their trace logs are captured, with
            // raw payloads compared) while the enclosing low-level failure
            // plus the complete World equality prove nothing committed —
            // recorder trace entries are never treated as committed logs.
            RouterVm.Log[] memory lg2 = rv.getRecordedLogs();
            require(lg2.length == 2, "malformed window shows exactly the rolled-back inner frames");
            bytes32[] memory nT = new bytes32[](1);
            nT[0] = keccak256("NewGauge(address,int128,uint256)");
            require(
                _countExactLogUnit(lg2, address(c), nT, abi.encode(gaugeB, int128(0), uint256(0))) == 1,
                "malformed window C NewGauge trace payload"
            );
            bytes32[] memory rT = new bytes32[](3);
            rT[0] = keccak256("GaugeAdded(address,address,int128,uint256)");
            rT[1] = bytes32(uint256(uint160(address(lister))));
            rT[2] = bytes32(uint256(uint160(gaugeB)));
            require(
                _countExactLogUnit(lg2, address(r), rT, abi.encode(int128(0), uint256(0))) == 1,
                "malformed window R GaugeAdded trace payload"
            );
            require(
                _countEmitter(lg2, address(lister)) == 0, "LISTER_POSTCHECK_FULL_ROLLBACK malformed no lister event"
            );
            require(
                _countEmitter(lg2, address(votium)) + _countEmitter(lg2, address(voteMarket)) == 0,
                "LISTER_POSTCHECK_FULL_ROLLBACK malformed no venue receipt event"
            );
        }
        _assertWorldEq(pre, _world(gaugeB, address(0)), "LISTER_POSTCHECK_FULL_ROLLBACK malformed");
        require(!c.registered(gaugeB), "malformed registration rolled back");

        // Lying membership after add forces L's postcheck (MembershipFailed).
        (address poolC, address gaugeC) = _pool(0, 3, 0);
        pre = _world(gaugeC, address(0));
        c.setTypesMode(1); // gauge_types lies +100 once registered
        rv.recordLogs();
        (bool a3, bytes memory r3) = _lane(payer, poolC, gaugeC, 3, 0);
        c.setTypesMode(0);
        require(!a3, "LISTER_POSTCHECK_FULL_ROLLBACK lying");
        require(_isErr(r3, CurveGaugeLister.MembershipFailed.selector, ""), "postcheck error");
        {
            // same oracle shape as the malformed case: executed-then-
            // rolled-back inner frames are visible as trace only; nothing
            // committed anywhere — C counters, membership, balances,
            // allowances, receipt ladder, R lifecycle all unchanged.
            RouterVm.Log[] memory lg3 = rv.getRecordedLogs();
            require(lg3.length == 2, "lying window shows exactly the rolled-back inner frames");
            bytes32[] memory nT = new bytes32[](1);
            nT[0] = keccak256("NewGauge(address,int128,uint256)");
            require(
                _countExactLogUnit(lg3, address(c), nT, abi.encode(gaugeC, int128(0), uint256(0))) == 1,
                "lying window C NewGauge trace payload"
            );
            bytes32[] memory rT = new bytes32[](3);
            rT[0] = keccak256("GaugeAdded(address,address,int128,uint256)");
            rT[1] = bytes32(uint256(uint160(address(lister))));
            rT[2] = bytes32(uint256(uint160(gaugeC)));
            require(
                _countExactLogUnit(lg3, address(r), rT, abi.encode(int128(0), uint256(0))) == 1,
                "lying window R GaugeAdded trace payload"
            );
            require(_countEmitter(lg3, address(lister)) == 0, "LISTER_POSTCHECK_FULL_ROLLBACK lying no lister event");
            require(
                _countEmitter(lg3, address(votium)) + _countEmitter(lg3, address(voteMarket)) == 0,
                "LISTER_POSTCHECK_FULL_ROLLBACK lying no venue receipt event"
            );
        }
        _assertWorldEq(pre, _world(gaugeC, address(0)), "LISTER_POSTCHECK_FULL_ROLLBACK lying");
        require(!c.registered(gaugeC), "registration rolled back");
    }

    function _revertMatches(bytes memory actual, bytes memory expected, string memory label) internal pure {
        require(keccak256(actual) == keccak256(expected), label);
    }

    function _countEmitter(RouterVm.Log[] memory logs, address emitter) internal pure returns (uint256 n) {
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].emitter == emitter) n += 1;
        }
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
        // CONF-04 required positive start: L is PAUSED and REVOKED before
        // the independent D route runs. The grant/revoke pair exercises the
        // actual state transition, not just a never-granted default.
        _grantLister(true);
        _grantLister(false);
        assertTrue(lister.paused(), "DAO_ROUTE_NO_LISTER_DEPENDENCY positive starts paused");
        assertFalse(r.isAdder(address(lister)), "DAO_ROUTE_NO_LISTER_DEPENDENCY positive starts revoked");

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

        // CONF-04: the full restriction contrast on the actual lanes.
        _i05Contrasts(badPool, badGauge);

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

    /// @dev CONF-04 restriction contrasts on I05's own composition:
    /// (a) paid lane while paused → ListingsPaused; (b) unpaused but still
    /// revoked paid lane → R's real NotAdder(L); (c) DAO-free from non-owner
    /// → NotOwner; (d) structurally unacceptable candidate → PoolNotRegistered
    /// (gauge absent from C, so occupancy is not the cause); (e) the
    /// already-occupied-membership contrast on D's independently added gauge.
    function _i05Contrasts(address badPool, address badGauge) internal {
        _i05PausedGate();
        _i05RevokedLaneAndOwnerGate();
        _i05StructuralGates(badPool, badGauge);
    }

    function _i05PausedGate() internal {
        (address poolA, address gaugeA) = _pool(2, 0, 0);
        (bool p1, bytes memory pr1) = _lane(payer, poolA, gaugeA, 0, 2);
        require(!p1, "paused paid lane admitted");
        require(_isErr(pr1, CurveGaugeLister.ListingsPaused.selector, ""), "paid pause gate");
    }

    function _i05RevokedLaneAndOwnerGate() internal {
        _unpause();
        (address poolB, address gaugeB) = _pool(2, 1, 0);
        (bool p2, bytes memory pr2) = _lane(payer, poolB, gaugeB, 1, 2);
        require(!p2, "revoked paid lane admitted");
        require(
            _isErr(pr2, GaugeControllerAdmin.NotAdder.selector, abi.encode(address(lister))), "paid lane reaches R gate"
        );
        require(!c.registered(gaugeB), "revoked paid never reached C");

        (bool p3, bytes memory pr3) = _laneDaoFrom(payer, poolB, gaugeB, 1, 2, 7);
        require(!p3, "non-owner dao-free admitted");
        require(_isErr(pr3, CurveGaugeLister.NotOwner.selector, ""), "dao-free owner gate");
    }

    function _i05StructuralGates(address badPool, address badGauge) internal {
        // (d1) pool the registry has never seen: the provenance read itself
        // reverts (UnknownPool from the configured registry) — L's structural
        // gate, exact cause, not a pause/auth artifact.
        address freeGauge = address(new MockGauge(address(new MockERC20(18))));
        (bool p4, bytes memory pr4) = _lane(payer, badPool, freeGauge, 9, 9);
        require(!p4, "L accepted structurally unacceptable candidate");
        require(_isErr(pr4, MockCurveRegistry.UnknownPool.selector, ""), "L registry provenance gate");

        // (d2) pool registered but explicitly not approved: L's own
        // PoolNotRegistered fires.
        (address poolD2, address gaugeD2) = _pool(3, 0, 0);
        registry.setRegistered(poolD2, 3, false);
        (bool p5, bytes memory pr5) = _lane(payer, poolD2, gaugeD2, 0, 3);
        require(!p5, "L accepted an unapproved pool");
        require(_isErr(pr5, CurveGaugeLister.PoolNotRegistered.selector, ""), "L approval gate kept");

        (bool l1, bytes memory lr1) = _lane(payer, badPool, badGauge, 0, 0);
        require(!l1, "paid lane accepted an already-registered gauge");
        require(_isErr(lr1, CurveGaugeLister.ControllerRegistryOccupied.selector, abi.encode(badGauge)), "L gate kept");
    }

    function _call(address from, address target, bytes memory data) internal returns (bool, bytes memory) {
        vm.prank(from);
        (bool ok, bytes memory ret) = target.call(data);
        return (ok, ret);
    }

    function _callDao(address target, bytes memory data) internal returns (bool, bytes memory) {
        return _call(address(dao), target, data);
    }

    function _laneDaoFrom(
        address who,
        address pool,
        address gauge,
        uint256 gaugeIndex,
        uint256 handlerId,
        uint256 weight
    ) internal returns (bool, bytes memory) {
        vm.prank(who);
        (bool ok, bytes memory ret) = address(lister)
            .call(
                abi.encodeWithSelector(
                    CurveGaugeLister.listGaugeNoEscrow.selector, pool, gauge, gaugeIndex, handlerId, weight
                )
            );
        return (ok, ret);
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
