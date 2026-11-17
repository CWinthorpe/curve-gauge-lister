// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BountyFixture} from "../BountyFixture.sol";
import {GaugeBounty} from "../../../contracts/GaugeBounty.sol";
import {CurveGaugeListerV2} from "../../../contracts/CurveGaugeListerV2.sol";
import {ICurveGaugeListerV2} from "../../../contracts/interfaces/ICurveGaugeListerV2.sol";
import {ReportView, Phase, StakeState} from "../../../contracts/bounty/BountyTypes.sol";
import {GovernanceGauge, MockSupportedFactory} from "../mocks/MockBountyGovernance.sol";

/// @notice V02-W1 acceptance witness for the ruled V-02 duplicate-canonical-
/// ballot disposition (plans/BOUNTY-V02-PLAN.md §4/§5, ruling
/// review/BOUNTY-V02-AUTHORITY.md). One native identity
/// `test_Rework_DuplicateCanonicalBallotDisposition()` executing the required
/// cells as private subcases: duplicate-first with unchanged killed state
/// through BOTH seizure entrypoints, consumed-offer isolation after an
/// authorized unkill, and the inverse bound-first positive control through
/// both entrypoints plus the unkill-mid duplicate. Everything is the real
/// local route: actual Voting creation/tally/executeVote -> CallsScript ->
/// Agent -> proxy -> gauge on the unchanged production bounty/V2. P and Q are
/// two DISTINCT actual proposal ids whose stored complete script bytes are
/// byte-identical (one `createBeneficiaryBallot` call each — creation twice,
/// never submission twice); only P is bound and exactly one stake is paid.
/// No setScriptFor, no forged executed reads, no callback pranks to build the
/// transition, no mockCall, no storage writes, no malformed fixture.
/// The authorised proxy-route unkill is a separately disclosed LOCAL fixture
/// action, never production repair guidance.
contract ReworkDuplicateBallotTest is BountyFixture {
    uint256 internal _seq;

    function setUp() public {
        setupBountyWorld();
    }

    // ---------------------------------------------------------------- scaffold

    /// @dev Full non-token custody/accounting fingerprint captured AROUND the
    /// callback-bearing executions: tokens must not move and no reward may be
    /// created by creditBallot/recognizeKill.
    struct Frozen {
        uint256 coreBal;
        uint256 bountyBal;
        uint256 fdBal;
        uint256 repBal;
        uint256 strangerBal;
        uint256 held;
        uint256 credits;
        uint256 dao;
        uint256 fdCursor;
        uint256 fdCalls;
        bytes32 listingHash;
    }

    struct Dup {
        CurveGaugeListerV2 core_;
        GaugeBounty b;
        address g;
        address rep;
        bytes32 id;
        uint256 pidP;
        uint256 pidQ;
        uint256 startP;
        uint256 startQ;
        uint256 voteEndP;
        uint256 executeByP;
        uint256 x; // common executable instant
    }

    struct Split {
        uint256 r; // actual read remainder seized
        uint256 b; // floor(r/2)
    }

    function _freeze(Dup memory d) internal view returns (Frozen memory f) {
        f.coreBal = crvUSD.balanceOf(address(d.core_));
        f.bountyBal = crvUSD.balanceOf(address(d.b));
        f.fdBal = crvUSD.balanceOf(address(fd));
        f.repBal = crvUSD.balanceOf(d.rep);
        f.strangerBal = crvUSD.balanceOf(stranger);
        (f.held, f.credits, f.dao) = d.b.accounting();
        f.fdCursor = fd.last_token_time();
        f.fdCalls = fd.checkpointCalls();
        f.listingHash = keccak256(abi.encode(d.core_.getListing(d.g)));
    }

    function _assertNoCallbackDrift(Frozen memory pre, Frozen memory post, string memory label) internal pure {
        assertEq(post.coreBal, pre.coreBal, string.concat(label, ": lister custody unmoved by callbacks"));
        assertEq(post.bountyBal, pre.bountyBal, string.concat(label, ": bounty custody unmoved by callbacks"));
        assertEq(post.fdBal, pre.fdBal, string.concat(label, ": FD unmoved by callbacks"));
        assertEq(post.repBal, pre.repBal, string.concat(label, ": reporter unmoved by callbacks"));
        assertEq(post.strangerBal, pre.strangerBal, string.concat(label, ": claimant unmoved by callbacks"));
        assertEq(post.held, pre.held, string.concat(label, ": heldStakes unmoved by callbacks"));
        assertEq(post.credits, pre.credits, string.concat(label, ": no reward created by callbacks"));
        assertEq(post.dao, pre.dao, string.concat(label, ": dao liability unmoved by callbacks"));
        assertEq(post.fdCursor, pre.fdCursor, string.concat(label, ": callbacks never touched the FD cursor"));
        assertEq(post.fdCalls, pre.fdCalls, string.concat(label, ": callbacks never called the FD"));
        assertEq(post.listingHash, pre.listingHash, string.concat(label, ": listing allocation fields unmoved"));
    }

    /// @dev Fresh bound pair + paid eligible live gauge with positive actual
    /// remainder; create P and Q with identical creation arguments (so the
    /// stored complete bytes are byte-identical and the report id is the same
    /// deterministic r), bind only P with exactly one stake, genuinely pass
    /// both closed ballots with one dominant voter, and park the clock at the
    /// common executable instant x = Q.voteEnd.
    function _mkDup() internal returns (Dup memory d) {
        d = _mkDupCreate();
        _dupVoteAndWindow(d);
    }

    function _mkDupCreate() internal returns (Dup memory d) {
        (d.core_, d.b) = deployBoundPair();
        (, d.g,) = listBountyEligible(d.core_);
        d.rep = reporter;
        assertEq(d.core_.getListing(d.g).remaining, FEE, "V02_POSITIVE_REMAINDER: fresh listing fully funded");
        assertEq(uint8(d.core_.getListing(d.g).status), 1, "V02_POSITIVE_REMAINDER: Active");

        _seq += 1;
        bytes32 eh = keccak256(abi.encode("v02-dup", d.g, _seq));
        uint256 nonce = 90000 + _seq;
        (bytes32 idP, uint256 pidP) = createBeneficiaryBallot(d.b, address(d.core_), d.g, d.rep, d.rep, nonce, eh);
        (bytes32 idQ, uint256 pidQ) = createBeneficiaryBallot(d.b, address(d.core_), d.g, d.rep, d.rep, nonce, eh);
        d.id = idP;
        d.pidP = pidP;
        d.pidQ = pidQ;
        assertTrue(pidP != pidQ, "V02_DISTINCT_ACTUAL_IDS: P and Q are distinct proposal ids");
        assertEq(idP, idQ, "V02_ONE_REPORT: both ballots carry the single deterministic report id");

        // Assert the identical COMPLETE bytes, not only identical visible
        // selectors/beneficiaries, and that they are the canonical script.
        bytes memory sp = voting.scriptOf(pidP);
        bytes memory sq = voting.scriptOf(pidQ);
        bytesEq(sp, sq, "V02_IDENTICAL_SCRIPT_BYTES: the complete stored bytes of P and Q are identical");
        bytes memory canonical = canonicalKillScript(d.b, d.g, idP, d.rep);
        bytesEq(sp, canonical, "V02_CANONICAL_BYTES: stored bytes equal the full canonical three-action script");
        assertEq(sp.length, 696, "V02_CANONICAL_BYTES: canonical 696-byte framing retained");
        assertTrue(sq.length == sp.length, "V02_IDENTICAL_SCRIPT_BYTES: length agrees");

        // Bind ONLY P; pay EXACTLY one stake.
        fundStake(d.b, d.rep);
        vm.prank(d.rep);
        bytes32 sid = d.b.submit(d.g, pidP, eh, nonce);
        assertEq(sid, idP, "V02_BOUND_ONLY_P: the single paid submission binds P");
        assertEq(crvUSD.balanceOf(address(d.b)), STAKE, "V02_ONE_STAKE: exactly one 1,000 stake paid");
    }

    /// @dev Clock observation, one dominant voter for BOTH genuinely passed
    /// ballots, and the forward-only common executable window.
    function _dupVoteAndWindow(Dup memory d) internal {
        // Observe the ORIGINAL stored clocks (never modified by this test).
        ReportView memory rv = d.b.getReport(d.id);
        d.voteEndP = rv.voteEnd;
        d.executeByP = rv.executeBy;
        (,, d.startP,,,,,,,) = voting.getVote(d.pidP);
        (,, d.startQ,,,,,,,) = voting.getVote(d.pidQ);
        assertEq(rv.proposalId, d.pidP, "V02_BOUND_ONLY_P: stored proposal id is P's actual id");
        assertEq(d.voteEndP, d.startP + VOTE_TIME, "V02_ORIGINAL_CLOCK_BOUND: voteEnd is P's actual start + ballot");

        // Genuinely pass BOTH closed ballots with one dominant voter per
        // local fixture (upstream rights and tally predicates untouched).
        address whale = address(uint160(0xD0DE0000 + _seq));
        giveVePower(whale, (escrow.totalSupply() + 1e18) * 3);
        vm.prank(whale);
        voting.vote(d.pidP, true);
        vm.prank(whale);
        voting.vote(d.pidQ, true);

        // Forward-only executable instant: no earlier than BOTH vote ends and
        // no later than P.executeBy; Q's own end is the binding edge.
        d.x = d.startQ + VOTE_TIME;
        assertEq(d.startQ, d.startP + COOLDOWN, "V02_CREATOR_COOLDOWN_HONOURED: real per-creator interval kept");
        assertTrue(d.x >= d.voteEndP, "V02_WINDOW: executes at or after both vote ends");
        assertTrue(d.x <= d.executeByP, "V02_WINDOW: executes no later than P.executeBy");
        assertTrue(d.executeByP > d.x, "V02_WINDOW: remaining execution margin is positive");
        vm.warp(d.x);

        // Both canExecute observations true before the first execution; both
        // executed flags initially false; gauge genuinely live.
        (bool pOpen0, bool pExec0,,,,,,,,) = voting.getVote(d.pidP);
        (bool qOpen0, bool qExec0,,,,,,,,) = voting.getVote(d.pidQ);
        assertFalse(pExec0, "V02_FLAGS_INITIALLY_FALSE: P.executed false before any execution");
        assertFalse(qExec0, "V02_FLAGS_INITIALLY_FALSE: Q.executed false before any execution");
        assertFalse(pOpen0, "V02_BOTH_CLOSED: P's ballot is closed at x");
        assertFalse(qOpen0, "V02_BOTH_CLOSED: Q's ballot is closed at x");
        assertTrue(voting.canExecute(d.pidP), "V02_BOTH_EXECUTABLE: P genuinely passed and is executable");
        assertTrue(voting.canExecute(d.pidQ), "V02_BOTH_EXECUTABLE: Q genuinely passed and is executable");
        assertFalse(GovernanceGauge(d.g).is_killed(), "V02_LIVE_BEFORE: kill flag false initially");
    }

    // -------------------------------------------------- duplicate-first cells

    /// @dev Execute Q (the duplicate) first as an outsider while P stays
    /// unexecuted, then assert the ruled disposition in the §5 order:
    /// flags/kill, then the empty winner, then the NoAward closure, then the
    /// zero-money/liability outcome around the callbacks.
    function _duplicateFirstThroughCallbacks(Dup memory d) internal {
        Frozen memory pre = _freeze(d);
        vm.prank(stranger);
        voting.executeVote(d.pidQ); // outsider executes the duplicate
        _assertNoCallbackDrift(pre, _freeze(d), "V02_CALLBACKS_NO_MONEY: Q's execution");

        (, bool pExec1,,,,,,,,) = voting.getVote(d.pidP);
        (, bool qExec1,,,,,,,,) = voting.getVote(d.pidQ);
        assertTrue(qExec1, "V02_FLAGS: Q.executed true after its execution");
        assertFalse(pExec1, "V02_FLAGS: the bound P remains unexecuted");
        assertTrue(GovernanceGauge(d.g).is_killed(), "V02_PROTECTIVE_KILL: the duplicate's real kill landed");

        // Empty winner BEFORE any resolve/claim/settlement call.
        (bytes32 wid, address wrep, bool wel) = d.b.rewardTerms(d.g);
        assertEq(wid, bytes32(0), "V02_UNBOUND_HAS_NO_WINNER: no same-block Armed latch, winner stays empty");
        assertEq(wrep, address(0), "V02_UNBOUND_HAS_NO_WINNER: no reporter is attached");
        assertFalse(wel, "V02_UNBOUND_HAS_NO_WINNER: the listing is not eligible");

        // Then the consumed closure and its zero-money outcome.
        ReportView memory rv = d.b.getReport(d.id);
        assertEq(uint256(rv.phase), uint256(Phase.NoAward), "V02_UNBOUND_CONSUMES_OFFER: pending report closes NoAward");
        assertEq(
            uint256(rv.stakeState),
            uint256(StakeState.Refundable),
            "V02_UNBOUND_CONSUMES_OFFER: bond becomes Refundable"
        );
        assertEq(rv.rewardCredit, 0, "V02_UNBOUND_CONSUMES_OFFER: no credit was created");
        (uint256 held, uint256 credits, uint256 dao) = d.b.accounting();
        assertEq(credits, 0, "V02_UNBOUND_CONSUMES_OFFER: no reward exists to fund");
        assertEq(dao, 0, "V02_UNBOUND_CONSUMES_OFFER: no liability invented");
        assertEq(held, STAKE, "V02_UNBOUND_CONSUMES_OFFER: the one bond is still held");
        // Original clocks survive the consumption.
        assertEq(rv.voteEnd, d.voteEndP, "V02_ORIGINAL_CLOCK_BOUND: voteEnd unchanged");
        assertEq(rv.executeBy, d.executeByP, "V02_ORIGINAL_CLOCK_BOUND: executeBy unchanged");
    }

    /// @dev Execute the bound P later while the gauge is still killed: the
    /// false->true observation window is gone and the terminal phase is
    /// load-bearing — recognition cannot arrive afterwards.
    function _lateBoundExecutionCannotRecognize(Dup memory d) internal {
        Frozen memory pre = _freeze(d);
        vm.prank(stranger);
        voting.executeVote(d.pidP); // still-killed gauge; P now genuinely executes
        _assertNoCallbackDrift(pre, _freeze(d), "V02_CALLBACKS_NO_MONEY: late P execution");
        (, bool pExec2,,,,,,,,) = voting.getVote(d.pidP);
        assertTrue(pExec2, "V02_FLAGS: P.executed true after its own execution");
        ReportView memory rv = d.b.getReport(d.id);
        assertEq(
            uint256(rv.phase),
            uint256(Phase.NoAward),
            "V02_UNBOUND_CONSUMES_OFFER: late P cannot revive the consumed report"
        );
        (bytes32 wid,, bool wel) = d.b.rewardTerms(d.g);
        assertEq(wid, bytes32(0), "V02_UNBOUND_HAS_NO_WINNER: still no winner after P's real execution");
        assertFalse(wel, "V02_UNBOUND_HAS_NO_WINNER: still ineligible after P's real execution");
        (, uint256 credits2,) = d.b.accounting();
        assertEq(credits2, 0, "V02_NO_INVENTED_REWARD: P's late callbacks created no reward");
    }

    /// @dev Fixed-recipient once-only bond refund paid by a stranger.
    function _claimRefundFixedOnce(Dup memory d) internal {
        uint256 rep0 = crvUSD.balanceOf(d.rep);
        uint256 claimant0 = crvUSD.balanceOf(stranger);
        vm.prank(stranger);
        (uint256 s, uint256 r) = d.b.claim(d.id);
        assertEq(s, STAKE, "V02_REFUND_FIXED_RECIPIENT: the non-forfeited stake pays once");
        assertEq(r, 0, "V02_NO_INVENTED_REWARD: the refund carries no invented reward");
        assertEq(crvUSD.balanceOf(d.rep) - rep0, STAKE, "V02_REFUND_FIXED_RECIPIENT: exact stake goes to stored A");
        assertEq(crvUSD.balanceOf(stranger), claimant0, "V02_REFUND_FIXED_RECIPIENT: never msg.sender");
        vm.prank(stranger);
        (uint256 s2, uint256 r2) = d.b.claim(d.id);
        assertEq(s2 + r2, 0, "V02_REFUND_ONCE: a repeated claim is zero");
        assertEq(crvUSD.balanceOf(d.rep), rep0 + STAKE, "V02_REFUND_ONCE: no second payment");
        assertEq(crvUSD.balanceOf(address(d.b)), 0, "V02_REFUND_ONCE: refund clears the bond liability");
        (uint256 held2, uint256 credits3, uint256 dao2) = d.b.accounting();
        assertEq(held2 + credits3 + dao2, 0, "V02_REFUND_ONCE: liabilities discharged, conservation holds");
    }

    /// @dev Terminal all-FD settlement of the consumed duplicate-first case
    /// through one of the two permissionless entrypoints, against the ACTUAL
    /// read remainder.
    function _settleAllFd(Dup memory d, bool viaCheckpoint) internal {
        _spaceFdCursorForDup();
        ICurveGaugeListerV2.ListingV2 memory lsPre = d.core_.getListing(d.g);
        uint256 rActual = lsPre.remaining;
        assertTrue(rActual > 0, "V02_POSITIVE_REMAINDER: seizure has a positive actual remainder");
        uint256 fd0 = crvUSD.balanceOf(address(fd));
        uint256 bounty0 = crvUSD.balanceOf(address(d.b));
        uint256 core0 = crvUSD.balanceOf(address(d.core_));
        if (viaCheckpoint) {
            vm.prank(stranger);
            (uint256 rel, uint256 conf) = d.core_.checkpoint(d.g);
            assertEq(rel, 0, "V02_DUPLICATE_ALL_FD_EXACT: a killed listing releases nothing at seizure");
            assertEq(conf, rActual, "V02_DUPLICATE_ALL_FD_EXACT: checkpoint seizure pays out actual R");
        } else {
            vm.prank(stranger);
            uint256 conf = d.core_.confiscate(d.g);
            assertEq(conf, rActual, "V02_DUPLICATE_ALL_FD_EXACT: confiscate seizure pays out actual R");
        }
        ICurveGaugeListerV2.ListingV2 memory ls = d.core_.getListing(d.g);
        assertEq(uint256(ls.status), 3, "V02_DUPLICATE_ALL_FD_EXACT: listing terminal Confiscated");
        assertEq(ls.confiscated, rActual, "V02_DUPLICATE_ALL_FD_EXACT: gross is the actual remainder");
        assertEq(ls.reporterReward, 0, "V02_DUPLICATE_ALL_FD_EXACT: reporter half is zero without a winner");
        assertEq(ls.fdConfiscated, rActual, "V02_DUPLICATE_ALL_FD_EXACT: all actual R goes to the pinned FD");
        assertEq(ls.rewardReportId, 0, "V02_DUPLICATE_ALL_FD_EXACT: no report id attached to the seizure");
        assertEq(
            crvUSD.allowance(address(d.core_), address(d.b)), 0, "V02_DUPLICATE_ALL_FD_EXACT: no V2-to-bounty allowance"
        );
        assertEq(crvUSD.balanceOf(address(fd)) - fd0, rActual, "V02_DUPLICATE_ALL_FD_EXACT: FD received exactly R");
        assertEq(crvUSD.balanceOf(address(d.b)), bounty0, "V02_NO_INVENTED_REWARD: bounty funds no phantom half");
        assertEq(
            crvUSD.balanceOf(address(d.core_)), core0 - rActual, "V02_DUPLICATE_ALL_FD_EXACT: escrow drained exactly"
        );
        assertEq(d.core_.totalEscrow(), 0, "V02_DUPLICATE_ALL_FD_EXACT: escrow fully accounted");
        assertEq(fd.last_token_time(), block.timestamp, "V02_DUPLICATE_ALL_FD_EXACT: FD accounting ran");
        assertEq(
            fd.token_last_balance(),
            crvUSD.balanceOf(address(fd)),
            "V02_DUPLICATE_ALL_FD_EXACT: FD accounted == custody"
        );
        (uint256 held, uint256 credits, uint256 dao) = d.b.accounting();
        assertEq(credits, 0, "V02_NO_INVENTED_REWARD: no reward credit was ever funded");
        assertEq(
            crvUSD.balanceOf(address(d.b)),
            held + credits + dao,
            "V02_CONSERVATION: bounty backs its liabilities exactly"
        );
        vm.prank(stranger);
        (uint256 s3, uint256 r3) = d.b.claim(d.id);
        assertEq(s3 + r3, 0, "V02_REFUND_ONCE: settlement invents no second payment");
    }

    function _spaceFdCursorForDup() internal {
        if (block.timestamp <= fd.last_token_time() + 86_400) {
            fd.setLastTokenTime(block.timestamp - 86_401);
        }
    }

    /// @dev Cell 1 (fresh world, confiscate entry): duplicate-first with the
    /// unchanged killed state, late bound execution, fixed once-only refund
    /// and the terminal all-FD settlement.
    function _cellDuplicateFirstConfiscate() private {
        Dup memory d = _mkDup();
        _duplicateFirstThroughCallbacks(d);
        _lateBoundExecutionCannotRecognize(d);
        _claimRefundFixedOnce(d);
        _settleAllFd(d, false);
    }

    /// @dev Cell 1 mirror (fresh otherwise-equivalent world, checkpoint
    /// entry): the same duplicate-first disposition, terminal all-FD R.
    function _cellDuplicateFirstCheckpoint() private {
        Dup memory d = _mkDup();
        _duplicateFirstThroughCallbacks(d);
        _lateBoundExecutionCannotRecognize(d);
        _claimRefundFixedOnce(d);
        _settleAllFd(d, true);
    }

    // ------------------------------------------------ cell 2: consumed offer

    /// @dev Consumed-offer isolation: refund and authorized unkill FIRST,
    /// then execute P with a real false->true kill. The listing is positive
    /// and healthy and P is closed+passed+unexecuted inside its deadline, so
    /// only the terminal phase can refuse recognition: it still cannot reopen
    /// the consumed report or fill a winner — asserted BEFORE any settlement.
    function _cellConsumedOfferIsolation() private {
        Dup memory d = _mkDup();
        _duplicateFirstThroughCallbacks(d); // immediate no-winner/NoAward first
        _isolationRefundAndUnkill(d);
        _isolationRealKillAndOracles(d);
        _isolationRefundInvariant(d);
    }

    function _isolationRefundAndUnkill(Dup memory d) private {
        // Refund the stake, then the disclosed local authorized unkill.
        uint256 rep0 = crvUSD.balanceOf(d.rep);
        vm.prank(stranger);
        (uint256 s0,) = d.b.claim(d.id);
        assertEq(s0, STAKE, "V02_REFUND_FIXED_RECIPIENT: isolation refund pays A the exact stake");
        assertEq(
            crvUSD.balanceOf(d.rep) - rep0, STAKE, "V02_REFUND_FIXED_RECIPIENT: isolation refund is fixed-recipient"
        );
        unkillGaugeViaRoute(d.g); // DISCLOSED fixture action, not repair guidance

        // Healthy world: listing Active with positive R, route intact, P
        // closed+passed+unexecuted, deadline still inclusive.
        ICurveGaugeListerV2.ListingV2 memory ls = d.core_.getListing(d.g);
        assertEq(uint256(ls.status), 1, "V02_ISOLATION_HEALTHY: listing remains Active");
        assertTrue(ls.remaining > 0, "V02_ISOLATION_HEALTHY: positive actual remainder");
        assertEq(GovernanceGauge(d.g).factory(), address(factory), "V02_ISOLATION_HEALTHY: supported factory route");
        assertEq(
            MockSupportedFactory(address(factory)).admin(),
            address(killProxy),
            "V02_ISOLATION_HEALTHY: factory admin is the proxy"
        );
        assertEq(killProxy.dao(), address(agent), "V02_ISOLATION_HEALTHY: proxy dao is the Agent");
        assertFalse(GovernanceGauge(d.g).is_killed(), "V02_ISOLATION_HEALTHY: kill flag restored false");
    }

    function _isolationRealKillAndOracles(Dup memory d) private {
        (bool pOpen, bool pExec,,,,,,,,) = voting.getVote(d.pidP);
        assertFalse(pOpen, "V02_ISOLATION_HEALTHY: P closed");
        assertFalse(pExec, "V02_ISOLATION_HEALTHY: P passed but unexecuted");
        assertTrue(voting.canExecute(d.pidP), "V02_ISOLATION_HEALTHY: P is executable (passed, closed, unexecuted)");
        assertTrue(block.timestamp <= d.executeByP, "V02_ISOLATION_HEALTHY: P deadline still inclusive");

        // Execute P with a REAL false->true kill; the terminal phase alone
        // must refuse reopening, before any settlement happens.
        Frozen memory pre = _freeze(d);
        vm.prank(stranger);
        voting.executeVote(d.pidP);
        _assertNoCallbackDrift(pre, _freeze(d), "V02_CALLBACKS_NO_MONEY: isolation P execution");
        assertTrue(GovernanceGauge(d.g).is_killed(), "V02_REAL_FALSE_TO_TRUE_KILL: P's kill genuinely flips the flag");
        ReportView memory rv = d.b.getReport(d.id);
        assertEq(
            uint256(rv.phase),
            uint256(Phase.NoAward),
            "V02_CONSUMED_OFFER_NEVER_RECOGNIZES: positive R, valid deadline and healthy reads leave the consumed report terminal"
        );
        (bytes32 wid, address wrep, bool wel) = d.b.rewardTerms(d.g);
        assertEq(wid, bytes32(0), "V02_CONSUMED_OFFER_NEVER_RECOGNIZES: the winner stays empty");
        assertEq(wrep, address(0), "V02_CONSUMED_OFFER_NEVER_RECOGNIZES: no reporter attached");
        assertFalse(wel, "V02_CONSUMED_OFFER_NEVER_RECOGNIZES: no eligibility invented");
    }

    function _isolationRefundInvariant(Dup memory d) private {
        // The earlier refund is not a second refund and no credit was
        // invented by P's real execution.
        uint256 repNow = crvUSD.balanceOf(d.rep);
        vm.prank(stranger);
        (uint256 s1, uint256 r1) = d.b.claim(d.id);
        assertEq(s1 + r1, 0, "V02_REFUND_ONCE: isolation refund never pays twice");
        assertEq(crvUSD.balanceOf(d.rep), repNow, "V02_REFUND_ONCE: reporter received exactly one stake");
        (uint256 held, uint256 credits, uint256 dao) = d.b.accounting();
        assertEq(held + credits + dao, 0, "V02_CONSERVATION: liabilities discharged, nothing invented");
        assertEq(crvUSD.balanceOf(address(d.b)), 0, "V02_CONSERVATION: bounty custody is exactly the liabilities");
        // Inert replay after P's real execution: still cannot arm/recognize.
        vm.prank(address(agent));
        d.b.creditBallot(d.id, d.rep);
        vm.prank(address(agent));
        d.b.recognizeKill(d.id);
        assertEq(
            uint256(d.b.getReport(d.id).phase),
            uint256(Phase.NoAward),
            "V02_CONSUMED_OFFER_NEVER_RECOGNIZES: callbacks stay inert on the consumed case"
        );
        // No settlement was reached in this cell: the listing is still Active.
        assertEq(uint256(d.core_.getListing(d.g).status), 1, "V02_ISOLATION_HEALTHY: asserted before any settlement");
    }

    // ------------------------------------------------- cell 3: bound-first

    /// @dev Execute P first: real false->canonical recognition with the
    /// correct permanent winner and no funded credit yet.
    function _boundFirstThroughRecognition(Dup memory d) internal {
        Frozen memory pre = _freeze(d);
        vm.prank(stranger);
        voting.executeVote(d.pidP);
        _assertNoCallbackDrift(pre, _freeze(d), "V02_CALLBACKS_NO_MONEY: bound-first P execution");
        (, bool pExec,,,,,,,,) = voting.getVote(d.pidP);
        assertTrue(pExec, "V02_FLAGS: bound P executed");
        assertTrue(GovernanceGauge(d.g).is_killed(), "V02_PROTECTIVE_KILL: bound execution kills");
        ReportView memory rv = d.b.getReport(d.id);
        assertEq(uint256(rv.phase), uint256(Phase.Recognized), "V02_BOUND_FIRST_HALF_FUNDED: bound-first recognition");
        assertEq(
            uint256(rv.stakeState),
            uint256(StakeState.Refundable),
            "V02_BOUND_FIRST_HALF_FUNDED: bond refundable at recognition"
        );
        (bytes32 wid, address wrep, bool wel) = d.b.rewardTerms(d.g);
        assertEq(wid, d.id, "V02_SINGLE_ALLOCATION: the correct permanent winner is latched");
        assertEq(wrep, d.rep, "V02_SINGLE_ALLOCATION: the winner names the stored reporter");
        assertTrue(wel, "V02_BOUND_FIRST_HALF_FUNDED: recognized and unfunded is eligible");
        (, uint256 credits0,) = d.b.accounting();
        assertEq(credits0, 0, "V02_BOUND_FIRST_HALF_FUNDED: no funded credit before settlement");
    }

    /// @dev Q (the duplicate) later cannot erase the winner/phase or allocate
    /// twice; `unkillMid` performs the disclosed authorized unkill first so
    /// Q's own kill is a real false->true while R remains positive.
    function _duplicateAfterRecognition(Dup memory d, bool unkillMid) internal {
        if (unkillMid) {
            unkillGaugeViaRoute(d.g); // DISCLOSED fixture action
            ICurveGaugeListerV2.ListingV2 memory ls = d.core_.getListing(d.g);
            assertEq(uint256(ls.status), 1, "V02_SINGLE_ALLOCATION: unkill keeps the listing Active");
            assertTrue(ls.remaining > 0, "V02_SINGLE_ALLOCATION: R stays positive through the unkill");
            assertFalse(GovernanceGauge(d.g).is_killed(), "V02_SINGLE_ALLOCATION: flag genuinely restored");
        }
        Frozen memory pre = _freeze(d);
        vm.prank(stranger);
        voting.executeVote(d.pidQ);
        _assertNoCallbackDrift(pre, _freeze(d), "V02_CALLBACKS_NO_MONEY: post-recognition duplicate");
        (, bool qExec,,,,,,,,) = voting.getVote(d.pidQ);
        assertTrue(qExec, "V02_FLAGS: Q executed after the winner");
        assertTrue(GovernanceGauge(d.g).is_killed(), "V02_PROTECTIVE_KILL: the duplicate's later kill still protects");
        (bytes32 wid, address wrep, bool wel) = d.b.rewardTerms(d.g);
        assertEq(wid, d.id, "V02_SINGLE_ALLOCATION: the winner cannot be erased by the duplicate");
        assertEq(wrep, d.rep, "V02_SINGLE_ALLOCATION: the winner identity cannot be rewritten");
        assertTrue(wel, "V02_SINGLE_ALLOCATION: entitlement intact before settlement");
        ReportView memory rv = d.b.getReport(d.id);
        assertEq(uint256(rv.phase), uint256(Phase.Recognized), "V02_SINGLE_ALLOCATION: phase survives the duplicate");
        (, uint256 credits, uint256 dao) = d.b.accounting();
        assertEq(credits, 0, "V02_SINGLE_ALLOCATION: no second reward created");
        assertEq(dao, 0, "V02_SINGLE_ALLOCATION: no liability invented");
    }

    /// @dev Seize the actual read remainder through one entrypoint and bind
    /// the exact split BEFORE the resulting Rewarded phase, so an allocation
    /// mutant reaches the money oracle first.
    function _seizeSplit(Dup memory d, bool viaCheckpoint) internal returns (Split memory x) {
        _spaceFdCursorForDup();
        x.r = d.core_.getListing(d.g).remaining;
        assertTrue(x.r > 0, "V02_POSITIVE_REMAINDER: split seizure has positive actual R");
        x.b = x.r / 2;
        uint256 fd0 = crvUSD.balanceOf(address(fd));
        uint256 bounty0 = crvUSD.balanceOf(address(d.b));
        uint256 core0 = crvUSD.balanceOf(address(d.core_));
        if (viaCheckpoint) {
            vm.prank(stranger);
            (uint256 rel, uint256 conf) = d.core_.checkpoint(d.g);
            assertEq(rel, 0, "V02_BOUND_FIRST_HALF_FUNDED: killed listing releases nothing at seizure");
            assertEq(conf, x.r, "V02_BOUND_FIRST_HALF_FUNDED: checkpoint seizes actual R");
        } else {
            vm.prank(stranger);
            uint256 conf = d.core_.confiscate(d.g);
            assertEq(conf, x.r, "V02_BOUND_FIRST_HALF_FUNDED: confiscate seizes actual R");
        }
        ICurveGaugeListerV2.ListingV2 memory ls = d.core_.getListing(d.g);
        assertEq(ls.reporterReward, x.b, "V02_BOUND_FIRST_HALF_FUNDED: B = floor(actual R/2) exactly");
        assertEq(ls.fdConfiscated, x.r - x.b, "V02_BOUND_FIRST_HALF_FUNDED: F = R - B exactly");
        assertEq(
            ls.rewardReportId,
            bytes32(uint256(d.id)),
            "V02_BOUND_FIRST_HALF_FUNDED: the matching report id is allocated"
        );
        assertEq(uint256(ls.status), 3, "V02_BOUND_FIRST_HALF_FUNDED: terminal Confiscated");
        (, uint256 credits, uint256 dao) = d.b.accounting();
        assertEq(credits, x.b, "V02_BOUND_FIRST_HALF_FUNDED: exactly the funded half credited");
        assertEq(dao, 0, "V02_BOUND_FIRST_HALF_FUNDED: no liability invented by settlement");
        assertEq(
            crvUSD.balanceOf(address(d.b)),
            bounty0 + x.b,
            "V02_BOUND_FIRST_HALF_FUNDED: exact B pulled into bounty custody"
        );
        assertEq(crvUSD.balanceOf(address(fd)) - fd0, x.r - x.b, "V02_BOUND_FIRST_HALF_FUNDED: exact FD receipt");
        assertEq(crvUSD.balanceOf(address(d.core_)), core0 - x.r, "V02_BOUND_FIRST_HALF_FUNDED: escrow drained exactly");
        assertEq(
            crvUSD.allowance(address(d.core_), address(d.b)),
            0,
            "V02_BOUND_FIRST_HALF_FUNDED: V2-to-bounty allowance cleared"
        );
        assertEq(fd.last_token_time(), block.timestamp, "V02_BOUND_FIRST_HALF_FUNDED: FD accounting ran");
        assertEq(
            fd.token_last_balance(),
            crvUSD.balanceOf(address(fd)),
            "V02_BOUND_FIRST_HALF_FUNDED: FD accounted == custody"
        );
        // Phase assertion deliberately AFTER the exact allocation asserts.
        assertEq(
            uint256(d.b.getReport(d.id).phase),
            uint256(Phase.Rewarded),
            "V02_BOUND_FIRST_HALF_FUNDED: Rewarded after funding"
        );
    }

    /// @dev Permissionless claim pays stake plus the funded B to A exactly once.
    function _claimSplitOnce(Dup memory d, Split memory x) internal {
        uint256 rep0 = crvUSD.balanceOf(d.rep);
        uint256 claimant0 = crvUSD.balanceOf(stranger);
        vm.prank(stranger);
        (uint256 s, uint256 r) = d.b.claim(d.id);
        assertEq(s, STAKE, "V02_SINGLE_ALLOCATION: bond paid with the reward");
        assertEq(r, x.b, "V02_SINGLE_ALLOCATION: the funded half paid once");
        assertEq(crvUSD.balanceOf(d.rep) - rep0, STAKE + x.b, "V02_SINGLE_ALLOCATION: fixed recipient, exact total");
        assertEq(crvUSD.balanceOf(stranger), claimant0, "V02_SINGLE_ALLOCATION: the claimant is paid nothing");
        (uint256 held, uint256 credits2, uint256 dao2) = d.b.accounting();
        assertEq(held + credits2 + dao2, 0, "V02_CONSERVATION: all liabilities discharged");
        assertEq(crvUSD.balanceOf(address(d.b)), 0, "V02_CONSERVATION: custody matches the discharged ledger");
    }

    /// @dev Later callback/claim/seizure attempts never add reward.
    function _replayInert(Dup memory d) internal {
        vm.prank(address(agent));
        d.b.creditBallot(d.id, d.rep);
        vm.prank(address(agent));
        d.b.recognizeKill(d.id);
        (bytes32 wid,, bool wel) = d.b.rewardTerms(d.g);
        assertEq(wid, d.id, "V02_SINGLE_ALLOCATION: the winner remains latched forever");
        assertFalse(wel, "V02_SINGLE_ALLOCATION: the consumed allocation is not re-eligible");
        assertEq(
            uint256(d.b.getReport(d.id).phase),
            uint256(Phase.Rewarded),
            "V02_SINGLE_ALLOCATION: Rewarded survives replays"
        );
        vm.prank(stranger);
        (uint256 s2, uint256 r2) = d.b.claim(d.id);
        assertEq(s2 + r2, 0, "V02_SINGLE_ALLOCATION: no second payment");
        vm.prank(stranger);
        assertEq(d.core_.confiscate(d.g), 0, "V02_SINGLE_ALLOCATION: no second seizure");
        (, uint256 credits3,) = d.b.accounting();
        assertEq(credits3, 0, "V02_SINGLE_ALLOCATION: no reward added by any replay");
    }

    /// @dev Cell 3a (confiscate entry): bound-first recognition, the
    /// duplicate later while still killed, one exact split, once-only claim.
    function _cellBoundFirstConfiscate() private {
        Dup memory d = _mkDup();
        _boundFirstThroughRecognition(d);
        _duplicateAfterRecognition(d, false);
        Split memory x = _seizeSplit(d, false);
        _claimSplitOnce(d, x);
        _replayInert(d);
    }

    /// @dev Cell 3b (checkpoint entry, fresh world): release ONE real quarter
    /// while the flag is still false so the seizure splits the actual reduced
    /// remainder, then the same bound-first disposition through checkpoint().
    function _cellBoundFirstCheckpoint() private {
        Dup memory d = _mkDup();
        // Mature and release exactly one quarter before any kill (flag false,
        // ordinary release path), so B/F are computed against a non-trivial
        // actual remainder rather than the fresh-fee constant.
        vm.prank(stranger);
        (uint256 rel, uint256 confPre) = d.core_.checkpoint(d.g);
        assertEq(rel, QUARTER, "V02_BOUND_FIRST_HALF_FUNDED: one genuine quarter released pre-kill");
        assertEq(confPre, 0, "V02_BOUND_FIRST_HALF_FUNDED: no seizure while the flag is false");
        assertEq(
            d.core_.getListing(d.g).remaining,
            FEE - QUARTER,
            "V02_POSITIVE_REMAINDER: actual R reduced by the funded quarter"
        );
        _boundFirstThroughRecognition(d);
        _duplicateAfterRecognition(d, false);
        Split memory x2 = _seizeSplit(d, true);
        _claimSplitOnce(d, x2);
        _replayInert(d);
    }

    /// @dev Cell 3c (confiscate entry, fresh world): the duplicate executes
    /// after an authorized unkill while R remains positive; the winner/phase
    /// survive and exactly one allocation is ever made.
    function _cellBoundFirstUnkillDuplicate() private {
        Dup memory d = _mkDup();
        _boundFirstThroughRecognition(d);
        _duplicateAfterRecognition(d, true);
        Split memory x3 = _seizeSplit(d, false);
        _claimSplitOnce(d, x3);
        _replayInert(d);
    }

    // ------------------------------------------------------------ identity

    function test_Rework_DuplicateCanonicalBallotDisposition() public {
        // §4 cell 1: duplicate-first, unchanged killed state, both entries.
        _cellDuplicateFirstConfiscate();
        _cellDuplicateFirstCheckpoint();
        // §4 cell 2: consumed-offer isolation (terminal finality, not the
        // pre-killed flag, not terminal escrow).
        _cellConsumedOfferIsolation();
        // §4 cell 3: bound-first positive controls (both entries + the
        // unkill-mid duplicate).
        _cellBoundFirstConfiscate();
        _cellBoundFirstCheckpoint();
        _cellBoundFirstUnkillDuplicate();
    }
}
