// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ForkFixture, FVm, IControllerVenue, IGaugeVenue, IVotiumVenue, IErc20Venue} from "./ForkFixture.sol";

/// @notice Abstract Votium specification, plans/FORK-PLAN.md §7 runner
/// `Votium` (lean-audit2 reduced set: four weekly tranches, late catch-up).
/// Concrete only in fork/Votium.t.sol.
abstract contract ForkVotiumSpec is ForkFixture {
    function setUp() public virtual {
        _freshFork();
    }

    // ------------------------------------------------------------------
    // 8
    // ------------------------------------------------------------------

    /// @dev §7.8 Pure Votium: four weekly settlements land one real incentive
    /// each in the actual time-derived active round (136/137/137/138), with
    /// exact gross/net/fee reconciliation and no FD funding.
    function test_Fork_VotiumFourWeeklyTranchesFundRealActiveRounds() public {
        Trio memory t = _seedStandard(10_000);
        _assertVotiumPins();

        // Before first maturity (including L+W-1): zero return, no change.
        fvm.warp(LISTING_EPOCH + WEEK - 1);
        Snap memory preDue = _snap(t);
        (uint256 r0, uint256 c0) = _keeperCheckpoint(t, GAUGE_PRIMARY);
        assertEq(r0, 0, "no release before maturity");
        assertEq(c0, 0, "no confiscation while alive");
        _assertSnapEq(preDue, _snap(t), "pre-maturity quiet");
        assertEq(t.lister.releasable(GAUGE_PRIMARY), 0, "releasable zero pre-due");

        for (uint256 k = 0; k < 4; ++k) {
            _proveVotiumQuarter(t, k);
        }

        // Fourth release was Exhausted; later settlement emits nothing, FD
        // received zero throughout.
        fvm.warp(LISTING_EPOCH + 5 * WEEK);
        Snap memory fin = _snap(t);
        fvm.recordLogs();
        (uint256 rL, uint256 cL) = _keeperCheckpoint(t, GAUGE_PRIMARY);
        assertEq(rL, 0, "exhausted release zero");
        assertEq(cL, 0, "exhausted confiscate zero");
        assertEq(_keeperConfiscate(t, GAUGE_PRIMARY), 0, "exhausted confiscate call zero");
        _assertNoSettlementEvents(fvm.getRecordedLogs(), t);
        _assertSnapEq(fin, _snap(t), "post-exhaustion quiet");
        assertEq(fin.fdCrv, preDue.fdCrv, "FD received zero throughout the run");
    }

    /// @dev One weekly boundary: exact return, appended real incentive, gross
    /// net/fee reconciliation, ledger and pinned events (test 8 loop body;
    /// split out for stack headroom). The same-timestamp no-op repeat is not
    /// re-proven per quarter: the representative post-exhaustion check in
    /// test 8 and offline same-timestamp settlement cover it.
    struct QPre {
        uint256 ts;
        uint256 round;
        Snap s;
        uint256 lenBefore;
        bool gaugeNewInRound;
        uint256 roundLenBefore;
    }

    function _proveVotiumQuarter(Trio memory t, uint256 k) internal {
        QPre memory q;
        q.ts = _maturity(k);
        q.round = _maturityRound(k);
        fvm.warp(q.ts);
        assertEq(IVotiumVenue(VOTIUM).activeRound(), q.round, "time-derived active round");
        q.s = _snap(t);
        q.lenBefore = IVotiumVenue(VOTIUM).incentivesLength(q.round, GAUGE_PRIMARY);
        q.gaugeNewInRound = !IVotiumVenue(VOTIUM).inRoundGauges(q.round, GAUGE_PRIMARY);
        q.roundLenBefore = IVotiumVenue(VOTIUM).gaugesLength(q.round);

        // R8-1: the EXACT venue deposit call (token, live round, single gauge
        // and gross arrays, default maxPerVote/exclusions) is expected here,
        // not inferred from balance deltas or final-zero allowances.
        _expectVotiumDeposit(q.round, QUARTER);
        fvm.recordLogs();
        (uint256 rel, uint256 conf) = _keeperCheckpoint(t, GAUGE_PRIMARY);
        assertEq(rel, QUARTER, "one quarter released");
        assertEq(conf, 0, "no confiscation");
        FVm.Log[] memory logs = fvm.getRecordedLogs();

        _assertQuarterVenue(t, q);
        _assertQuarterEvents(t, k, logs, q);
    }

    function _assertQuarterVenue(Trio memory t, QPre memory q) internal view {
        // Exactly one real incentive appended at the pre-read index.
        assertEq(IVotiumVenue(VOTIUM).incentivesLength(q.round, GAUGE_PRIMARY), q.lenBefore + 1, "exactly one appended");
        _assertIncentive(address(t.va), q.round, q.lenBefore, QUARTER);
        assertTrue(IVotiumVenue(VOTIUM).inRoundGauges(q.round, GAUGE_PRIMARY), "in round gauges");
        if (q.gaugeNewInRound) {
            assertEq(IVotiumVenue(VOTIUM).gaugesLength(q.round), q.roundLenBefore + 1, "gauge array grew");
            assertEq(IVotiumVenue(VOTIUM).roundGauges(q.round, q.roundLenBefore), GAUGE_PRIMARY, "array membership");
        }
        _assertVotiumDeltas(q.s, _snap(t), QUARTER);
        assertEq(IErc20Venue(CRVUSD).balanceOf(address(t.lister)), q.s.listerCrv - QUARTER, "lister debited gross");
        _assertAdaptersEmpty(t);
        _assertZeroApprovals(t);
        assertEq(IControllerVenue(CONTROLLER).get_gauge_weight(GAUGE_PRIMARY), 0, "raw weight still 0");
        assertFalse(IGaugeVenue(GAUGE_PRIMARY).is_killed(), "flag still false");
    }

    function _assertQuarterEvents(Trio memory t, uint256 k, FVm.Log[] memory logs, QPre memory q) internal view {
        assertEq(_countLogs(logs, address(t.lister), T_QUARTER_RELEASED), 1, "one QuarterReleased");
        assertEq(_countLogs(logs, address(t.lister), T_PLATFORM_DEPOSIT), 1, "one PlatformDeposit");
        assertEq(_countLogs(logs, VOTIUM, T_NEW_INCENTIVE), 1, "real NewIncentive");
        assertEq(_countLogs(logs, address(t.va), T_VOTIUM_DEPOSIT), 1, "adapter VotiumDeposit once");
        _assertPlatformDepositLog(logs, address(t.lister), k, address(t.va));
        _assertLedger(t, GAUGE_PRIMARY, uint8(k + 1), k == 3);
        // R8-1: exact Votium-side approval/transfer amounts for this gross
        // share and its net/fee split (bounded-approval proof).
        _assertVotiumLegEvents(t, logs, QUARTER, 1);
        // §6.1: the lister routes GROSS to the adapter; Votium itself splits
        // net/fee. PlatformDeposit data.amount and the receipt use gross.
        _assertReceipt(
            logs,
            address(t.lister),
            q.ts,
            QUARTER,
            keccak256(abi.encode(GAUGE_PRIMARY, q.ts, QUARTER, q.round)),
            q.round,
            address(t.va)
        );
    }

    /// @dev Pins of the live venue that this proof depends on (§6.1).
    function _assertVotiumPins() internal view {
        IVotiumVenue votium = IVotiumVenue(VOTIUM);
        assertTrue(votium.requireAllowlist(), "requireAllowlist");
        assertTrue(votium.tokenAllowed(CRVUSD), "crvUSD allowed");
        assertEq(votium.platformFee(), VOTIUM_PLATFORM_FEE, "platform fee 2%");
        assertEq(votium.DENOMINATOR(), VOTIUM_DENOMINATOR, "denominator");
        assertEq(votium.feeAddress(), VOTIUM_FEE_ADDRESS, "fee address");
    }

    /// @dev Assert lister's PlatformDeposit event carries the expected
    /// execution epoch, gross amount and receipt; Votium-side receipt value
    /// is net after the venue fee.
    function _assertPlatformDepositLog(FVm.Log[] memory logs, address emitter, uint256 k, address adapterAddr)
        internal
        pure
    {
        bool seen;
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].emitter == emitter && logs[i].topics.length == 4 && logs[i].topics[0] == T_PLATFORM_DEPOSIT) {
                assertEq(address(uint160(uint256(logs[i].topics[1]))), GAUGE_PRIMARY, "deposit gauge");
                assertEq(address(uint160(uint256(logs[i].topics[2]))), adapterAddr, "deposit platform = adapter");
                assertEq(uint256(logs[i].topics[3]), _maturity(k), "deposit scheduled epoch");
                seen = true;
            }
        }
        assertTrue(seen, "PlatformDeposit topics");
    }

    function _assertReceipt(
        FVm.Log[] memory logs,
        address emitter,
        uint256 scheduledEpoch,
        uint256 routedAmount,
        bytes32 wantReceipt,
        uint256 round,
        address adapterAddr
    ) internal pure {
        bool seen;
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].emitter == emitter && logs[i].topics.length == 4 && logs[i].topics[0] == T_PLATFORM_DEPOSIT) {
                (uint256 executionEpoch, uint256 amount, bytes32 receipt) =
                    abi.decode(logs[i].data, (uint256, uint256, bytes32));
                assertEq(executionEpoch, scheduledEpoch, "execution epoch (matured boundary)");
                assertEq(
                    amount, routedAmount, "adapter deposit equals the routed gross (plan 6.1: core release = GROSS)"
                );
                assertEq(receipt, wantReceipt, "receipt = keccak(gauge, scheduled, gross, round)");
                seen = true;
            }
            if (logs[i].emitter == VOTIUM && logs[i].topics.length == 4 && logs[i].topics[0] == T_NEW_INCENTIVE) {
                assertEq(uint256(logs[i].topics[1]), round, "NewIncentive round topic");
                assertEq(address(uint160(uint256(logs[i].topics[2]))), GAUGE_PRIMARY, "NewIncentive gauge topic");
                assertEq(address(uint160(uint256(logs[i].topics[3]))), adapterAddr, "NewIncentive depositor = adapter");
            }
        }
        assertTrue(seen, "PlatformDeposit receipt");
    }

    // ------------------------------------------------------------------
    // 9
    // ------------------------------------------------------------------

    /// @dev §7.9 Pure Votium late catch-up in ONE checkpoint at L+4W: four
    /// 2500e18 deposits into the execution-time round 138, four distinct
    /// original scheduled epochs and receipts; Exhausted with no fifth.
    function test_Fork_VotiumLateCatchUpPreservesScheduleNotHistoricalRounds() public {
        Trio memory t = _seedStandard(10_000);
        _assertVotiumPins();

        // No earlier release: warp straight to L+4W.
        fvm.warp(LISTING_EPOCH + 4 * WEEK);
        assertEq(IVotiumVenue(VOTIUM).activeRound(), 138, "execution round 138");
        Snap memory before = _snap(t);
        uint256 len138Before = IVotiumVenue(VOTIUM).incentivesLength(138, GAUGE_PRIMARY);
        assertEq(t.lister.epochsElapsed(GAUGE_PRIMARY), 4, "four elapsed");
        assertEq(t.lister.releasable(GAUGE_PRIMARY), 4 * QUARTER, "full releasable");

        // R8-1: the exact venue deposit call lands in the execution-time
        // round 138; the four occurrences are pinned by the per-leg log
        // counts below (expectCall is at-least-once with exact data).
        _expectVotiumDeposit(138, QUARTER);
        fvm.recordLogs();
        (uint256 rel, uint256 conf) = _keeperCheckpoint(t, GAUGE_PRIMARY);
        assertEq(rel, 4 * QUARTER, "four quarters in one checkpoint");
        assertEq(conf, 0, "no confiscation");

        // Four appended incentives in the actual execution round.
        assertEq(
            IVotiumVenue(VOTIUM).incentivesLength(138, GAUGE_PRIMARY), len138Before + 4, "four incentives in round 138"
        );
        for (uint256 j = 0; j < 4; ++j) {
            _assertIncentive(address(t.va), 138, len138Before + j, QUARTER);
        }

        // Four ordered QuarterReleased/PlatformDeposit pairs, original k=1..4
        // scheduled epochs, current execution epoch, distinct correct receipts.
        FVm.Log[] memory logs = fvm.getRecordedLogs();
        assertEq(_countLogs(logs, address(t.lister), T_QUARTER_RELEASED), 4, "four QuarterReleased");
        assertEq(_countLogs(logs, address(t.lister), T_PLATFORM_DEPOSIT), 4, "four PlatformDeposit");
        assertEq(_countLogs(logs, VOTIUM, T_NEW_INCENTIVE), 4, "four NewIncentive");
        uint256 qr;
        uint256 pd;
        for (uint256 i = 0; i < logs.length; ++i) {
            if (
                logs[i].emitter == address(t.lister) && logs[i].topics.length == 3
                    && logs[i].topics[0] == T_QUARTER_RELEASED
            ) {
                assertEq(address(uint160(uint256(logs[i].topics[1]))), GAUGE_PRIMARY, "qr gauge");
                assertEq(uint256(logs[i].topics[2]), _maturity(qr), "qr scheduled epoch ordered");
                (uint256 amount, uint256 remaining) = abi.decode(logs[i].data, (uint256, uint256));
                assertEq(amount, QUARTER, "qr amount");
                assertEq(remaining, QUARTER * (3 - qr), "qr remaining ladder");
                qr += 1;
            }
            if (
                logs[i].emitter == address(t.lister) && logs[i].topics.length == 4
                    && logs[i].topics[0] == T_PLATFORM_DEPOSIT
            ) {
                assertEq(uint256(logs[i].topics[3]), _maturity(pd), "pd scheduled epoch ordered (k=1..4)");
                (uint256 executionEpoch, uint256 amount, bytes32 receipt) =
                    abi.decode(logs[i].data, (uint256, uint256, bytes32));
                assertEq(executionEpoch, LISTING_EPOCH + 4 * WEEK, "execution epoch = now week");
                assertEq(amount, QUARTER, "adapter debit is gross (plan 6.1)");
                assertEq(
                    receipt,
                    keccak256(abi.encode(GAUGE_PRIMARY, _maturity(pd), QUARTER, 138)),
                    "distinct gross-based receipt"
                );
                pd += 1;
            }
        }
        assertEq(qr, 4, "qr loop");
        assertEq(pd, 4, "pd loop");

        // Full gross/net/fee reconciliation: 10000 gross = 9800 net + 200 fee.
        _assertVotiumDeltas(before, _snap(t), 4 * QUARTER);
        // R8-1: four exact Votium-side pulls/approvals/transfers, one per
        // appended incentive (per-gross-share amounts, not aggregate only).
        _assertVotiumLegEvents(t, logs, QUARTER, 4);
        assertEq(IErc20Venue(CRVUSD).balanceOf(address(t.lister)), before.listerCrv - 4 * QUARTER, "gross left core");
        _assertLedger(t, GAUGE_PRIMARY, 4, true);
        _assertAdaptersEmpty(t);
        _assertZeroApprovals(t);

        // Retry: no fifth quarter — with a complete terminal-state
        // comparison, not just returns/events/count (R8-2).
        Snap memory term9 = _snap(t);
        fvm.recordLogs();
        (uint256 r2, uint256 c2) = _keeperCheckpoint(t, GAUGE_PRIMARY);
        assertEq(r2, 0, "no fifth quarter");
        assertEq(c2, 0, "still no confiscation");
        assertEq(IVotiumVenue(VOTIUM).incentivesLength(138, GAUGE_PRIMARY), len138Before + 4, "still four incentives");
        assertEq(_keeperConfiscate(t, GAUGE_PRIMARY), 0, "exhausted confiscate zero");
        _assertNoSettlementEvents(fvm.getRecordedLogs(), t);
        _assertSnapEq(term9, _snap(t), "exhausted retry terminal quiet");
    }
}
