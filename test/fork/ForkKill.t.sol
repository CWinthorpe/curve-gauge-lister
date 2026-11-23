// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {
    ForkFixture,
    FVm,
    IControllerVenue,
    IGaugeVenue,
    IFactoryVenue,
    IProxyVenue,
    IFdVenue,
    IVotiumVenue,
    ILaPosteVenue,
    IErc20Venue
} from "./ForkFixture.sol";
import {CurveGaugeLister} from "../../contracts/CurveGaugeLister.sol";

/// @notice Abstract real-kill/FD specification, plans/FORK-PLAN.md §7 runner
/// `Kill` (lean-audit2 reduced set as amended by auditfix001 §7: kill
/// authority, mid-drip kill with mandatory accounting, FD freshness/
/// cooldown). Concrete only in fork/Kill.t.sol.
abstract contract ForkKillSpec is ForkFixture {
    function setUp() public virtual {
        _freshFork();
    }

    // ------------------------------------------------------------------
    // 15
    // ------------------------------------------------------------------

    /// @dev §7.15 Kill authority is the gauge's factory admin (the AMM owner
    /// proxy); the proxy accepts DAO or Emergency Agent. Payer, outsider and
    /// even DAO directly on the gauge all fail; weight/admin/ledger untouched.
    function test_Fork_RealGaugeKillRequiresItsActualAuthority() public {
        Trio memory t = _seedStandard(10_000);

        // Authority bindings at this pin.
        assertEq(IFactoryVenue(FACTORY).admin(), AMM_PROXY, "gauge kill authority is the factory admin (proxy)");
        assertEq(IProxyVenue(AMM_PROXY).dao(), DAO, "proxy dao");
        assertEq(IProxyVenue(AMM_PROXY).emergency_dao(), EMERGENCY_DAO, "proxy emergency agent");
        assertTrue(DAO != AMM_PROXY, "DAO is not the direct gauge admin");

        Snap memory pre = _snap(t);
        assertFalse(IGaugeVenue(GAUGE_PRIMARY).is_killed(), "alive");

        // Payer's DIRECT gauge call and proxy call reject.
        _probeAnyRevertKill(payer(), false);
        _probeAnyRevertKill(payer(), true);
        // DAO's DIRECT gauge call also rejects (DAO is not factory.admin).
        _probeAnyRevertKill(DAO, false);
        // An unrelated outsider too.
        _probeAnyRevertKill(rando(), true);

        // No flag, weight, balances or ledger change from any failure.
        assertFalse(IGaugeVenue(GAUGE_PRIMARY).is_killed(), "still alive after unauthorized attempts");
        assertEq(IControllerVenue(CONTROLLER).get_gauge_weight(GAUGE_PRIMARY), 0, "weight unchanged");
        assertEq(IControllerVenue(CONTROLLER).admin(), address(t.lister), "controller admin unchanged");
        _assertSnapEq(pre, _snap(t), "unauthorized kill no side effects");

        // DAO through the real proxy succeeds.
        _killViaProxy(DAO, GAUGE_PRIMARY);
        assertTrue(IGaugeVenue(GAUGE_PRIMARY).is_killed(), "killed by DAO via proxy");
        assertEq(IControllerVenue(CONTROLLER).get_gauge_weight(GAUGE_PRIMARY), 0, "kill did not touch weight");
        assertEq(IControllerVenue(CONTROLLER).admin(), address(t.lister), "kill did not touch admin");

        // Independent fresh fork: Emergency Agent through the proxy succeeds.
        _freshFork();
        Trio memory t2 = _seedStandard(10_000);
        assertFalse(IGaugeVenue(GAUGE_PRIMARY).is_killed(), "alive on new fork");
        _killViaProxy(EMERGENCY_DAO, GAUGE_PRIMARY);
        assertTrue(IGaugeVenue(GAUGE_PRIMARY).is_killed(), "killed by Emergency Agent via proxy");
        assertEq(IControllerVenue(CONTROLLER).admin(), address(t2.lister), "admin unchanged (fresh fork)");
    }

    /// @dev Permission failure on either kill surface must revert (any data);
    /// the load-bearing proof is the surrounding no-state-change assertions.
    function _probeAnyRevertKill(address from, bool viaProxy) internal {
        if (viaProxy) {
            fvm.prank(from);
            try IProxyVenue(AMM_PROXY).set_killed(GAUGE_PRIMARY) {
                assertTrue(false, "unauthorized proxy kill must revert");
            } catch (bytes memory) {}
        } else {
            fvm.prank(from);
            try IGaugeVenue(GAUGE_PRIMARY).set_killed(true) {
                assertTrue(false, "unauthorized direct gauge kill must revert");
            } catch (bytes memory) {}
        }
    }

    // ------------------------------------------------------------------
    // 17
    // ------------------------------------------------------------------

    /// @dev §7.17 Mid-drip kill (genuine kill between weekly settlements):
    /// later tranches stop, remainder seizes at nonzero controller weight,
    /// committed platform money is never clawed back, unkill stays terminal.
    function test_Fork_MidDripKillStopsLaterTranchesAndSeizesRemainder() public {
        Trio memory t = _seedStandard(6500);
        _topUpVm(t, FIXTURE_ETH_FLOAT);
        uint256 votiumGross = 1625e18;
        uint256 vmGross = 875e18;

        // Quarter one funds both real venues; the successful checkpoint's
        // receipts and events are bound here exactly like the VoteMarket
        // runner's prover (R8-2): keyed and chronological adapter records,
        // CampaignDeposit and both per-leg PlatformDeposit events.
        fvm.warp(_maturity(0));
        Snap memory q0 = _snap(t);
        fvm.recordLogs();
        (uint256 rel,) = _keeperCheckpoint(t, GAUGE_PRIMARY);
        assertEq(rel, QUARTER, "quarter one released");
        FVm.Log[] memory q0Logs = fvm.getRecordedLogs();
        assertEq(IVotiumVenue(VOTIUM).incentivesLength(136, GAUGE_PRIMARY), q0.len136 + 1, "one incentive");
        assertEq(IErc20Venue(CRVUSD).balanceOf(TOKEN_FACTORY), q0.tfCrv + vmGross, "one campaign locked");
        assertEq(ILaPosteVenue(LA_POSTE).sentNonces(VM_DEST_CHAIN_ID), q0.lpNonce + 1, "one message");
        _assertAdapterRecord(t, _maturity(0), vmGross, 1);
        _assertCampaignDepositLog(q0Logs, t.vma, _maturity(0), vmGross, 1);
        _assertListerPlatformDeposit(
            q0Logs,
            address(t.lister),
            address(t.vma),
            _maturity(0),
            vmGross,
            keccak256(abi.encode(GAUGE_PRIMARY, _maturity(0), vmGross, 1))
        );
        _assertListerPlatformDeposit(
            q0Logs,
            address(t.lister),
            address(t.va),
            _maturity(0),
            votiumGross,
            keccak256(abi.encode(GAUGE_PRIMARY, _maturity(0), votiumGross, 136))
        );
        _assertLedger(t, GAUGE_PRIMARY, 1, false);

        // Verified nonzero raw weight via the §5.2 fixture admin simulation
        // (fork-only upstream-admin simulation, not a callable lister feature).
        address cadmin = IControllerVenue(CONTROLLER).admin();
        fvm.prank(cadmin);
        IControllerVenue(CONTROLLER).change_gauge_weight(GAUGE_PRIMARY, 1_000_000);
        assertEq(IControllerVenue(CONTROLLER).get_gauge_weight(GAUGE_PRIMARY), 1_000_000, "nonzero bias set");

        // Kill via the actual proxy without changing that weight.
        Snap memory pre = _snap(t);
        _killViaProxy(DAO, GAUGE_PRIMARY);
        assertEq(IControllerVenue(CONTROLLER).get_gauge_weight(GAUGE_PRIMARY), 1_000_000, "weight unchanged by kill");

        // Permissionless confiscation immediately seizes exactly 7500e18 with
        // two-sided custody deltas, the decoded confiscation event and the
        // ACTUAL checkpoint outcome (R8-2).
        _seizeRemainderAndAssert(t, pre);

        // One representative later terminal check (offline tests cover the
        // full terminal-state matrix and repeated same-timestamp settlement).
        _assertLaterNoOps(t, _maturity(3));

        // First-quarter incentive and message persist; later ones absent.
        Snap memory post = _snap(t);
        assertEq(post.len136, q0.len136 + 1, "first incentive persists");
        assertEq(post.len137, q0.len137, "no second/third incentive");
        assertEq(post.len138, q0.len138, "no fourth incentive");
        assertEq(post.lpNonce, q0.lpNonce + 1, "exactly one message");
        assertEq(post.vmaDeposits, q0.vmaDeposits + 1, "exactly one adapter deposit");
        assertEq(post.tfCrv, q0.tfCrv + vmGross, "committed platform money survives");
        assertEq(post.votiumCrv - q0.votiumCrv, votiumGross - (votiumGross * 200) / 10_000, "votium net persists");

        // Clear the flag via the verified direct factory admin: Confiscated
        // still cannot reopen.
        _unkillViaDirectAdmin(GAUGE_PRIMARY);
        assertFalse(IGaugeVenue(GAUGE_PRIMARY).is_killed(), "unkilled via direct factory admin (fork control)");
        Snap memory termU = _snap(t);
        fvm.recordLogs();
        (uint256 rU, uint256 cU) = _keeperCheckpoint(t, GAUGE_PRIMARY);
        assertEq(rU, 0, "terminal after unkill: release zero");
        assertEq(cU, 0, "terminal after unkill: confiscate zero");
        assertEq(_keeperConfiscate(t, GAUGE_PRIMARY), 0, "terminal after unkill: confiscate call zero");
        _assertNoSettlementEvents(fvm.getRecordedLogs(), t);
        _assertSnapEq(termU, _snap(t), "unkilled terminal quiet");
        assertEq(IErc20Venue(CRVUSD).balanceOf(FEEDIST), pre.fdCrv + 7500e18, "no additional transfer");
        assertEq(uint256(t.lister.getListing(GAUGE_PRIMARY).status), 3, "still Confiscated");
    }

    /// @dev §7.17 mid-drip seizure block (split out of the test for stack
    /// headroom), strengthened per auditfix001 §7: proves a safe pre-cursor,
    /// the successful MANDATORY checkpoint (post-cursor at now and accounted
    /// balance equal to actual custody) and exactly 7500e18 confiscated with
    /// two-sided custody deltas, the decoded EscrowConfiscated, the ACTUAL
    /// FeeCheckpointResult outcome and the terminal ledger (R8-2).
    function _seizeRemainderAndAssert(Trio memory t, Snap memory pre) internal {
        bool fdOk = _expectedFdCheckpointOk();
        uint256 preCursor = IFdVenue(FEEDIST).last_token_time();
        assertTrue(preCursor < block.timestamp, "safe pre-cursor strictly before now");
        fvm.recordLogs();
        (uint256 conf) = _keeperConfiscate(t, GAUGE_PRIMARY);
        assertEq(conf, 7500e18, "exact remainder confiscated");
        FVm.Log[] memory confLogs = fvm.getRecordedLogs();
        assertEq(IErc20Venue(CRVUSD).balanceOf(FEEDIST), pre.fdCrv + 7500e18, "FD got the remainder");
        assertEq(
            IErc20Venue(CRVUSD).balanceOf(address(t.lister)),
            pre.listerCrv - 7500e18,
            "lister debited the same remainder"
        );
        assertEq(t.lister.totalEscrow(), 0, "escrow cleared");
        _assertEscrowConfiscated(confLogs, address(t.lister), 7500e18, _maturity(0));
        assertTrue(fdOk, "live FD law permits the public checkpoint here");
        // auditfix001 §3: seizure proves immediate accounting over a covered
        // interval — cursor at now and accounted balance == actual custody.
        assertEq(IFdVenue(FEEDIST).last_token_time(), block.timestamp, "mandatory checkpoint advanced the cursor");
        assertEq(
            IFdVenue(FEEDIST).token_last_balance(),
            IErc20Venue(CRVUSD).balanceOf(FEEDIST),
            "accounted balance equals custody"
        );
        _assertFeeCheckpointResult(confLogs, address(t.lister), fdOk, "mid-drip confiscation");
        // Complete terminal Confiscated record (R8-2): full financials
        // (released quarter kept, remainder seized, deposited identity);
        // immutable metadata stays bound at initial admission.
        _assertConfiscatedLedger(t, GAUGE_PRIMARY, 2500e18, 7500e18);
        _assertZeroApprovals(t);
    }

    /// @dev §7.17 terminal no-op after the mid-drip kill: zero returns, zero
    /// releasable, NO new receipts or settlement events AND the complete
    /// terminal state unchanged at the representative later maturity.
    function _assertLaterNoOps(Trio memory t, uint256 maturity) internal {
        fvm.warp(maturity);
        Snap memory termI = _snap(t);
        fvm.recordLogs();
        (uint256 rN, uint256 cN) = _keeperCheckpoint(t, GAUGE_PRIMARY);
        assertEq(rN, 0, "later checkpoint zero");
        assertEq(cN, 0, "later confiscate zero");
        assertEq(_keeperConfiscate(t, GAUGE_PRIMARY), 0, "later confiscate call zero");
        assertEq(t.lister.releasable(GAUGE_PRIMARY), 0, "later releasable zero");
        _assertNoSettlementEvents(fvm.getRecordedLogs(), t);
        _assertSnapEq(termI, _snap(t), "later maturity terminal quiet");
    }

    // ------------------------------------------------------------------
    // 19 (auditfix001 §7 replacement slot)
    // ------------------------------------------------------------------

    /// @dev §7.19 as amended by auditfix001 §7: confiscation requires a
    /// fresh, accountable FeeDistributor. One extended test in two fresh-fork
    /// subcases (same public inventory, internal helpers for stack headroom):
    /// (1) the real strict cooldown REVERTS same-timestamp and +86400
    /// confiscation and killed checkpoint with complete state equality —
    /// including when the lister itself is invoked BY the FD admin (the inner
    /// caller is the lister) — standalone checkpointFees stays false, and the
    /// +86401 DIRECT confiscation commits with exact transfer, post-cursor/
    /// accounted balance and success events; (2) a 40-week-stale destination
    /// is rejected before transfer on both paths, a separate ZERO-DELTA
    /// checkpointFees refresh advances the cursor, cooldown rejects again,
    /// and the +86401 direct confiscation allocates the FULL fee over the
    /// affected interval with exact custody/accounted balances.
    function test_Fork_ConfiscationRequiresFreshAccountableFeeDistributor() public {
        _forkCooldownRevertsUntilEligible();
        _forkStaleHorizonRecovery();
    }

    /// @dev Subcase 1: live admin sync, kill through the actual proxy path,
    /// cooldown matrix, admin-outer-caller control, +86401 direct commit.
    function _forkCooldownRevertsUntilEligible() internal {
        Trio memory t = _seedStandard(10_000);

        // Read the actual FD admin on the fork; prank THAT account.
        address fdAdmin = IFdVenue(FEEDIST).admin();
        emit log_named_address("fd.admin", fdAdmin);
        assertEq(fdAdmin, DAO, "pinned FD admin identity");
        assertTrue(fdAdmin != address(0), "FD admin present");
        assertTrue(IFdVenue(FEEDIST).can_checkpoint_token(), "public checkpoint flag enabled at pin");

        fvm.prank(fdAdmin);
        IFdVenue(FEEDIST).checkpoint_token();
        uint256 sync = IFdVenue(FEEDIST).last_token_time();
        assertEq(sync, block.timestamp, "admin sync moved the cursor to now");

        // Kill through the actual gauge-admin/proxy path.
        _killViaProxy(DAO, GAUGE_PRIMARY);

        Snap memory pre = _snap(t);
        uint256 preAcc = IFdVenue(FEEDIST).token_last_balance();

        // Same-timestamp: confiscation AND killed checkpoint revert with
        // complete pre/post state equality including the accounting reads.
        _probeKeeperConfiscateRevert(t, "same-timestamp confiscation");
        _probeKeeperKilledCheckpointRevert(t, "same-timestamp killed checkpoint");
        _assertConfiscationStateEq(t, pre, preAcc, sync, "same-timestamp");
        assertFalse(_keeperCheckpointFees(t), "standalone checkpointFees false during cooldown");

        // Exactly +86400: the strict guard still refuses both entrypoints.
        fvm.warp(sync + 86400);
        _probeKeeperConfiscateRevert(t, "+86400 confiscation");
        _probeKeeperKilledCheckpointRevert(t, "+86400 killed checkpoint");
        _assertConfiscationStateEq(t, pre, preAcc, sync, "+86400");
        assertFalse(_keeperCheckpointFees(t), "standalone checkpointFees false at +86400");

        // Calling the lister AS the FD admin does not bypass the cooldown:
        // the inner checkpoint caller is the lister, not the outer sender.
        fvm.prank(fdAdmin);
        try t.lister.confiscate(GAUGE_PRIMARY) returns (uint256 x) {
            assertTrue(false, string.concat("admin-outer confiscation must revert, succeeded ", _u(x)));
        } catch (bytes memory) {}
        _assertConfiscationStateEq(t, pre, preAcc, sync, "admin-outer");

        // At +86401 the DIRECT confiscation commits exactly once: exact
        // transfer, post-cursor/accounted balance and success events.
        fvm.warp(sync + 86401);
        fvm.recordLogs();
        (uint256 conf) = _keeperConfiscate(t, GAUGE_PRIMARY);
        assertEq(conf, FEE, "full fee confiscated at +86401");
        FVm.Log[] memory logs = fvm.getRecordedLogs();
        assertEq(IErc20Venue(CRVUSD).balanceOf(FEEDIST), pre.fdCrv + FEE, "exact custody transfer");
        assertEq(IErc20Venue(CRVUSD).balanceOf(address(t.lister)), pre.listerCrv - FEE, "core drained");
        assertEq(IFdVenue(FEEDIST).last_token_time(), block.timestamp, "post-cursor == now");
        assertEq(
            IFdVenue(FEEDIST).token_last_balance(),
            IErc20Venue(CRVUSD).balanceOf(FEEDIST),
            "accounted balance == custody"
        );
        assertEq(uint256(t.lister.getListing(GAUGE_PRIMARY).status), 3, "Confiscated terminal");
        assertEq(t.lister.totalEscrow(), 0, "escrow cleared");
        _assertEscrowConfiscated(logs, address(t.lister), FEE, (block.timestamp / WEEK) * WEEK);
        _assertFeeCheckpointResult(logs, address(t.lister), true, "+86401 direct confiscation");
        _assertZeroApprovals(t);
    }

    /// @dev Subcase 2 (fresh fork): 40-week stale destination rejected before
    /// transfer; zero-delta refresh; cooldown rejection; +86401 direct
    /// confiscation with the full fee allocated over the affected interval.
    function _forkStaleHorizonRecovery() internal {
        _freshFork();
        address fdAdmin = IFdVenue(FEEDIST).admin();
        assertTrue(IFdVenue(FEEDIST).can_checkpoint_token(), "public flag enabled (fresh fork)");

        // Synchronize the healthy pinned FD through its actual admin and
        // prove the accounted balance equals custody before anything else.
        fvm.prank(fdAdmin);
        IFdVenue(FEEDIST).checkpoint_token();
        uint256 sync = IFdVenue(FEEDIST).last_token_time();
        assertEq(sync, block.timestamp, "admin sync at the fork timestamp");
        assertEq(
            IFdVenue(FEEDIST).token_last_balance(),
            IErc20Venue(CRVUSD).balanceOf(FEEDIST),
            "healthy FD: accounted == custody"
        );

        Trio memory t = _seedStandard(10_000);
        _killViaProxy(DAO, GAUGE_PRIMARY);

        // Warp 40 weeks from that cursor with no added unaccounted funds.
        fvm.warp(sync + 40 * WEEK);
        assertTrue(block.timestamp - (sync / WEEK) * WEEK > 20 * WEEK, "beyond the 20-week horizon");
        Snap memory pre = _snap(t);
        uint256 preAcc = IFdVenue(FEEDIST).token_last_balance();
        emit log_named_uint("stale cursor", sync);
        emit log_named_uint("stale now", block.timestamp);
        emit log_named_uint("horizon", (sync / WEEK) * WEEK + 20 * WEEK);
        _probeKeeperConfiscateRevert(t, "40-week-stale confiscation");
        _probeKeeperKilledCheckpointRevert(t, "40-week-stale killed checkpoint");
        _assertConfiscationStateEq(t, pre, preAcc, sync, "40-week stale");

        // Separate ZERO-DELTA checkpointFees refresh; verify cursor
        // advancement with no new accounting.
        assertTrue(_keeperCheckpointFees(t), "zero-delta refresh succeeds");
        uint256 refresh = IFdVenue(FEEDIST).last_token_time();
        assertEq(refresh, block.timestamp, "cursor advanced to now");
        assertEq(IFdVenue(FEEDIST).token_last_balance(), preAcc, "no new accounting on refresh");

        // Cooldown rejection again immediately after the refresh.
        Snap memory mid = _snap(t);
        _probeKeeperConfiscateRevert(t, "post-refresh cooldown confiscation");
        _assertConfiscationStateEq(t, mid, preAcc, refresh, "post-refresh cooldown");

        // Direct confiscation after +86401: record before/after
        // tokens_per_week over the affected interval and its sum — the FULL
        // fee is allocated for this pinned recovery timing (at most two
        // buckets; the FD's historical buckets are not assumed zero).
        uint256 wFrom = (refresh / WEEK) * WEEK;
        uint256 b0 = IFdVenue(FEEDIST).tokens_per_week(wFrom);
        uint256 b1 = IFdVenue(FEEDIST).tokens_per_week(wFrom + WEEK);
        fvm.warp(refresh + 86401);
        fvm.recordLogs();
        (uint256 conf) = _keeperConfiscate(t, GAUGE_PRIMARY);
        assertEq(conf, FEE, "full fee seized after refresh + cooldown");
        FVm.Log[] memory logs = fvm.getRecordedLogs();
        uint256 a0 = IFdVenue(FEEDIST).tokens_per_week(wFrom);
        uint256 a1 = IFdVenue(FEEDIST).tokens_per_week(wFrom + WEEK);
        assertEq((a0 - b0) + (a1 - b1), FEE, "entire fee allocated over the affected interval");
        assertEq(IFdVenue(FEEDIST).last_token_time(), block.timestamp, "post-cursor == now");
        assertEq(
            IFdVenue(FEEDIST).token_last_balance(),
            IErc20Venue(CRVUSD).balanceOf(FEEDIST),
            "accounted balance == custody"
        );
        assertEq(IErc20Venue(CRVUSD).balanceOf(FEEDIST), pre.fdCrv + FEE, "exact custody transfer");
        assertEq(IErc20Venue(CRVUSD).balanceOf(address(t.lister)), pre.listerCrv - FEE, "core drained");
        assertEq(uint256(t.lister.getListing(GAUGE_PRIMARY).status), 3, "Confiscated terminal");
        _assertEscrowConfiscated(logs, address(t.lister), FEE, (block.timestamp / WEEK) * WEEK);
        _assertFeeCheckpointResult(logs, address(t.lister), true, "post-refresh direct confiscation");
        _assertZeroApprovals(t);
    }

    /// @dev Keeper confiscation must revert (any revert data); the test
    /// continues for state-equality assertions.
    function _probeKeeperConfiscateRevert(Trio memory t, string memory label) internal {
        fvm.prank(keeper());
        try t.lister.confiscate(GAUGE_PRIMARY) returns (uint256 x) {
            assertTrue(false, string.concat(label, ": expected revert, succeeded ", _u(x)));
        } catch (bytes memory) {}
    }

    /// @dev Keeper killed-gauge checkpoint must revert (any revert data).
    function _probeKeeperKilledCheckpointRevert(Trio memory t, string memory label) internal {
        fvm.prank(keeper());
        try t.lister.checkpoint(GAUGE_PRIMARY) returns (uint256 a, uint256 b) {
            assertTrue(false, string.concat(label, ": expected revert, succeeded ", _u(a), "/", _u(b)));
        } catch (bytes memory) {}
    }

    /// @dev Complete pre/post equality for a refused seizure: whole Snap
    /// equality (custody/ledger/listing hash) plus the FD accounting reads
    /// and the still-killed, still-Active listing.
    function _assertConfiscationStateEq(
        Trio memory t,
        Snap memory pre,
        uint256 preAcc,
        uint256 preCursor,
        string memory label
    ) internal view {
        _assertSnapEq(pre, _snap(t), label);
        assertEq(IFdVenue(FEEDIST).last_token_time(), preCursor, string.concat(label, ": cursor unchanged"));
        assertEq(IFdVenue(FEEDIST).token_last_balance(), preAcc, string.concat(label, ": accounted balance unchanged"));
        assertTrue(IGaugeVenue(GAUGE_PRIMARY).is_killed(), string.concat(label, ": flag stays true"));
        assertEq(uint256(t.lister.getListing(GAUGE_PRIMARY).status), 1, string.concat(label, ": still Active"));
    }
}
