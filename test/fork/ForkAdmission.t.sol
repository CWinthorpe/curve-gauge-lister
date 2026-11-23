// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ForkFixture, IControllerVenue, IGaugeVenue, IErc20Venue, FVm} from "./ForkFixture.sol";
import {CurveGaugeLister} from "../../contracts/CurveGaugeLister.sol";

/// @notice Abstract admission/roles specification, plans/FORK-PLAN.md §7
/// runner `Admission` (lean-audit2 reduced set: controller seating, paid
/// admission, DAO free listing). Concrete instantiation happens only in
/// fork/Admission.t.sol (outside the default source roots).
abstract contract ForkAdmissionSpec is ForkFixture {
    function setUp() public virtual {
        _freshFork();
    }

    // ------------------------------------------------------------------
    // 3
    // ------------------------------------------------------------------

    /// @dev §7.3 real controller admin check pre-seating, unauthorized
    /// ownership changes rejected, DAO commit/apply seating, then the SAME
    /// payer/candidate succeeds once; raw NewGauge and membership observed.
    function test_Fork_ControllerSeatingAndUnseatedRollback() public {
        _assertActorsDistinct();
        Trio memory t = _deployTrio(10_000);
        _fundPayer(payer(), 1);
        _approveFee(t);
        // S05: explicit final activation after the applicable prerequisites
        // (bindings read back in _deployTrio; funding and approval here). The
        // deliberate UNSEATED negative case below stays: the admin rejection
        // must come from the controller check itself, never from the pause
        // gate masking it.
        _activatePaidAdmission(t);

        uint256 nGaugesBefore = uint256(int256(IControllerVenue(CONTROLLER).n_gauges()));
        assertEq(nGaugesBefore, N_GAUGES_PINNED, "count before");
        address futureBefore = IControllerVenue(CONTROLLER).future_admin();

        // 1. Funded/approved listing BEFORE seating reverts on the REAL
        // controller admin check (bare Vyper assert -> empty revert data),
        // atomically restoring balances, membership and the record.
        Snap memory unseatedPre = _snap(t);
        _probeListGaugeRevert(t, bytes(""), "unseated listing reverts on controller admin check");
        // R8-2: complete-state rollback — every destination balance and
        // custody/receipt counter plus the complete Listing record (bound by
        // one hash in the flattened Snap) — on top of the explicit fields
        // below.
        _assertSnapEq(unseatedPre, _snap(t), "unseated listing full rollback");
        assertEq(IErc20Venue(CRVUSD).balanceOf(payer()), FEE, "fee restored");
        assertEq(IErc20Venue(CRVUSD).allowance(payer(), address(t.lister)), FEE, "approval restored");
        assertEq(IErc20Venue(CRVUSD).balanceOf(address(t.lister)), 0, "lister unfunded");
        assertEq(t.lister.totalEscrow(), 0, "escrow untouched");
        CurveGaugeLister.Listing memory ghost = t.lister.getListing(GAUGE_PRIMARY);
        assertEq(uint256(ghost.status), 0, "no record written");
        assertEq(ghost.pool, address(0), "record pool zero");
        assertEq(ghost.deposited, 0, "record deposited zero");
        assertEq(uint256(int256(IControllerVenue(CONTROLLER).n_gauges())), nGaugesBefore, "count untouched");

        // Unauthorized controller ownership change attempts fail.
        _probeControllerCommitRevert(payer(), bytes(""), "non-admin commit rejected");
        _probeControllerApplyRevert(rando(), bytes(""), "non-admin apply rejected");
        assertEq(IControllerVenue(CONTROLLER).admin(), DAO, "admin still DAO");
        assertEq(IControllerVenue(CONTROLLER).future_admin(), futureBefore, "future_admin untouched");

        // 2. DAO executes BOTH steps of the real two-step transfer.
        _seat(t.lister);

        // 3. New admin, and membership/count unchanged until the listing.
        assertEq(IControllerVenue(CONTROLLER).admin(), address(t.lister), "lister seated");
        assertEq(uint256(int256(IControllerVenue(CONTROLLER).n_gauges())), nGaugesBefore, "count unchanged");
        try IControllerVenue(CONTROLLER).gauge_types(GAUGE_PRIMARY) returns (int128 ty0) {
            assertTrue(false, "seating must not register the gauge");
        } catch (bytes memory ret) {
            assertEq(uint256(ret.length), 0, "still absent after seating");
        }

        // The SAME payer/candidate successfully retries once. The public
        // paid call invokes the real add_gauge(gauge, 0, 0) from the lister.
        fvm.expectCall(CONTROLLER, abi.encodeCall(IControllerVenue.add_gauge, (GAUGE_PRIMARY, DERIVED_TYPE, 0)));
        fvm.recordLogs();
        fvm.prank(payer());
        t.lister.listGauge(POOL_PRIMARY, GAUGE_PRIMARY, GAUGE_INDEX, HANDLER_ID);
        FVm.Log[] memory logs = fvm.getRecordedLogs();

        // Raw NewGauge from the real controller: all three params non-indexed.
        assertEq(_countLogs(logs, CONTROLLER, T_NEW_GAUGE), 1, "one raw NewGauge");
        bool decoded;
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].emitter == CONTROLLER && logs[i].topics.length == 1 && logs[i].topics[0] == T_NEW_GAUGE) {
                (address g, int128 ty, uint256 w) = abi.decode(logs[i].data, (address, int128, uint256));
                assertEq(g, GAUGE_PRIMARY, "NewGauge addr");
                assertEq(ty, DERIVED_TYPE, "NewGauge type");
                assertEq(w, 0, "NewGauge weight zero");
                decoded = true;
            }
        }
        assertTrue(decoded, "NewGauge decoded");

        // Count +1, gauges(oldCount) = gauge, immediate type membership.
        assertEq(uint256(int256(IControllerVenue(CONTROLLER).n_gauges())), nGaugesBefore + 1, "count +1");
        assertEq(IControllerVenue(CONTROLLER).gauges(nGaugesBefore), GAUGE_PRIMARY, "gauges[oldCount]");
        _assertI128Eq(IControllerVenue(CONTROLLER).gauge_types(GAUGE_PRIMARY), int128(0), "type membership");
    }

    // ------------------------------------------------------------------
    // 4
    // ------------------------------------------------------------------

    /// @dev §7.4 paid listing transfers exactly FEE from an unrelated payer
    /// and escrows it centrally; full Active Listing snapshot verified.
    function test_Fork_PaidListingTransfersExactFeeAtZeroWeight() public {
        _assertActorsDistinct();
        Trio memory t = _deployTrio(10_000);
        _seat(t.lister);
        _fundPayer(payer(), 1);
        _approveFee(t);
        // S05: paid admission enabled only after seating/funding/approval.
        _activatePaidAdmission(t);

        // Baselines captured AFTER funding.
        Snap memory pre = _snap(t);
        uint256 holderBefore = IErc20Venue(CRVUSD).balanceOf(CRVUSD_HOLDER);
        assertEq(holderBefore, HOLDER_PINNED_BALANCE - FEE, "holder after funding");
        assertEq(IControllerVenue(CONTROLLER).admin(), address(t.lister), "admin is lister");

        fvm.expectCall(CONTROLLER, abi.encodeCall(IControllerVenue.add_gauge, (GAUGE_PRIMARY, DERIVED_TYPE, 0)));
        fvm.recordLogs();
        fvm.prank(payer());
        t.lister.listGauge(POOL_PRIMARY, GAUGE_PRIMARY, GAUGE_INDEX, HANDLER_ID);
        FVm.Log[] memory logs = fvm.getRecordedLogs();

        // Exact fee debits/credits, nothing else moved.
        assertEq(IErc20Venue(CRVUSD).balanceOf(payer()), 0, "payer debited exactly FEE");
        assertEq(IErc20Venue(CRVUSD).balanceOf(address(t.lister)), pre.listerCrv + FEE, "core funded FEE");
        assertEq(IErc20Venue(CRVUSD).balanceOf(CRVUSD_HOLDER), holderBefore, "holder idle");
        Snap memory post = _snap(t);
        assertEq(post.fdCrv, pre.fdCrv, "FD unfunded");
        assertEq(post.votiumCrv, pre.votiumCrv, "votium unfunded");
        assertEq(post.feeCrv, pre.feeCrv, "fee address unfunded");
        assertEq(post.tfCrv, pre.tfCrv, "token factory unfunded");
        assertEq(post.crmCrv, pre.crmCrv, "crm unfunded");
        assertEq(post.lpNonce, pre.lpNonce, "nonce untouched");
        assertEq(post.totalEscrow, FEE, "total escrow FEE");
        _assertAdaptersEmpty(t);

        // Real controller state after the synchronous add.
        _assertI128Eq(IControllerVenue(CONTROLLER).gauge_types(GAUGE_PRIMARY), int128(0), "immediate membership");
        assertEq(IControllerVenue(CONTROLLER).get_gauge_weight(GAUGE_PRIMARY), 0, "raw weight zero");
        assertFalse(IGaugeVenue(GAUGE_PRIMARY).is_killed(), "flag false");

        // Complete Active Listing snapshot.
        CurveGaugeLister.Listing memory rec = t.lister.getListing(GAUGE_PRIMARY);
        assertEq(rec.pool, POOL_PRIMARY, "record pool");
        assertEq(rec.lpToken, POOL_PRIMARY, "record LP");
        assertEq(rec.payer, payer(), "record payer");
        assertEq(rec.admissionRegistry, METAREGISTRY, "record registry");
        _assertI128Eq(rec.gaugeType, int128(0), "record type");
        assertEq(rec.listingEpoch, LISTING_EPOCH, "record L");
        assertEq(uint256(rec.status), 1, "status Active");
        assertEq(uint256(rec.epochsReleased), 0, "epochs 0");
        assertEq(rec.deposited, FEE, "deposited FEE");
        assertEq(rec.remaining, FEE, "remaining FEE");
        assertEq(rec.released, 0, "released 0");
        assertEq(rec.confiscated, 0, "confiscated 0");
        assertEq(rec.votium, address(t.va), "platform snapshot votium");
        assertEq(rec.voteMarket, address(t.vma), "platform snapshot votemarket");
        assertEq(uint256(rec.votiumBps), 10_000, "platform snapshot split");
        _assertLedger(t, GAUGE_PRIMARY, 0, false);

        // GaugeListed decoded (3 indexed: gauge, pool, payer; data: type,
        // listingEpoch, fee, daoExempt); payer allowance consumed to zero.
        assertEq(_countLogs(logs, address(t.lister), T_GAUGE_LISTED), 1, "one GaugeListed");
        bool listedSeen;
        for (uint256 i = 0; i < logs.length; ++i) {
            if (
                logs[i].emitter == address(t.lister) && logs[i].topics.length == 4
                    && logs[i].topics[0] == T_GAUGE_LISTED
            ) {
                assertEq(address(uint160(uint256(logs[i].topics[1]))), GAUGE_PRIMARY, "GaugeListed gauge");
                assertEq(address(uint160(uint256(logs[i].topics[2]))), POOL_PRIMARY, "GaugeListed pool");
                assertEq(address(uint160(uint256(logs[i].topics[3]))), payer(), "GaugeListed payer");
                (int128 ty, uint256 lep, uint256 f, bool daoExempt) =
                    abi.decode(logs[i].data, (int128, uint256, uint256, bool));
                _assertI128Eq(ty, int128(0), "GaugeListed type");
                assertEq(lep, LISTING_EPOCH, "GaugeListed listing epoch");
                assertEq(f, FEE, "GaugeListed fee");
                assertFalse(daoExempt, "paid not daoExempt");
                listedSeen = true;
            }
        }
        assertTrue(listedSeen, "GaugeListed decoded");
        assertEq(IErc20Venue(CRVUSD).allowance(payer(), address(t.lister)), 0, "payer allowance zero");
    }

    // ------------------------------------------------------------------
    // 5
    // ------------------------------------------------------------------

    /// @dev §7.5 DAO-free listing never escrows or drips; supplyable weight;
    /// terminal-quiet after weeks plus a real kill (the paused subcase was
    /// cut; pause immunity stays covered offline).
    function test_Fork_DaoFreeListingNeverEscrowsOrDrips() public {
        _assertActorsDistinct();
        Trio memory t = _deployTrio(10_000);
        _seat(t.lister);

        uint256 daoCrvBefore = IErc20Venue(CRVUSD).balanceOf(DAO);
        emit log_named_uint("DAO crvUSD (observation)", daoCrvBefore);
        assertEq(IErc20Venue(CRVUSD).allowance(DAO, address(t.lister)), 0, "no owner approval needed");

        fvm.recordLogs();
        fvm.prank(DAO);
        t.lister.listGaugeNoEscrow(POOL_PRIMARY, GAUGE_PRIMARY, GAUGE_INDEX, HANDLER_ID, 0);
        assertEq(_countLogs(fvm.getRecordedLogs(), CRVUSD, T_TRANSFER), 0, "no token movement");
        assertEq(IErc20Venue(CRVUSD).balanceOf(DAO), daoCrvBefore, "owner balance unchanged");
        assertEq(IErc20Venue(CRVUSD).allowance(DAO, address(t.lister)), 0, "owner allowance still zero");

        // Membership with the supplied raw weight; DaoExempt and all
        // financial/platform fields zero.
        _assertI128Eq(IControllerVenue(CONTROLLER).gauge_types(GAUGE_PRIMARY), int128(0), "member");
        assertEq(IControllerVenue(CONTROLLER).get_gauge_weight(GAUGE_PRIMARY), 0, "supplied weight 0");
        CurveGaugeLister.Listing memory rec = t.lister.getListing(GAUGE_PRIMARY);
        assertEq(uint256(rec.status), 4, "DaoExempt");
        assertEq(rec.payer, address(0), "payer zero");
        assertEq(rec.deposited, 0, "deposited zero");
        assertEq(rec.remaining, 0, "remaining zero");
        assertEq(rec.released, 0, "released zero");
        assertEq(rec.confiscated, 0, "confiscated zero");
        assertEq(uint256(rec.epochsReleased), 0, "epochs zero");
        assertEq(rec.votium, address(0), "platform zero");
        assertEq(rec.voteMarket, address(0), "platform zero 2");
        assertEq(uint256(rec.votiumBps), 0, "bps zero");
        assertEq(t.lister.totalEscrow(), 0, "escrow untouched");
        assertEq(t.lister.epochsElapsed(GAUGE_PRIMARY), 0, "elapsed zero");

        // After four weeks and a real gauge kill, nothing drips or seizes.
        Snap memory pre = _snap(t);
        fvm.warp(LISTING_EPOCH + 4 * WEEK);
        _killViaProxy(DAO, GAUGE_PRIMARY);
        fvm.recordLogs();
        (uint256 rel, uint256 conf) = _keeperCheckpoint(t, GAUGE_PRIMARY);
        assertEq(rel, 0, "checkpoint zero");
        assertEq(conf, 0, "confiscate zero");
        assertEq(_keeperConfiscate(t, GAUGE_PRIMARY), 0, "confiscate call zero");
        assertEq(t.lister.releasable(GAUGE_PRIMARY), 0, "releasable zero");
        // R8-2: the terminal calls are also recorded and rejected for new
        // settlement events, not only compared as unchanged Snap state.
        _assertNoSettlementEvents(fvm.getRecordedLogs(), t);
        _assertSnapEq(pre, _snap(t), "dao-free drip");
        assertEq(uint256(t.lister.getListing(GAUGE_PRIMARY).status), 4, "record unchanged");
    }
}
