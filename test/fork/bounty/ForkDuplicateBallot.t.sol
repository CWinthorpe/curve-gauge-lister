// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BountyForkFixture, Kit} from "./BountyForkFixture.sol";
import {ForkFixture, FVm, IErc20Venue, IFdVenue, IGaugeVenue} from "../ForkFixture.sol";
import {ICurveGaugeListerV2} from "../../../contracts/interfaces/ICurveGaugeListerV2.sol";
import {ReportView, Phase, StakeState, BountyConfig} from "../../../contracts/bounty/BountyTypes.sol";
import {BountyScripts} from "../../../contracts/libraries/BountyScripts.sol";
import {IGaugeBounty} from "../../../contracts/interfaces/IGaugeBounty.sol";

/// @dev V02-W1 fork acceptance witness (plans/BOUNTY-V02-PLAN.md §4 fork
/// identity, ruling review/BOUNTY-V02-AUTHORITY.md). One native identity
/// executes the same distinct-P/Q, exact-script, one-report, genuinely
/// passed duplicate-first chronology through the ACTUAL pinned Ownership
/// Voting, Agent, CallsScript and kill proxy: duplicate-first
/// no-winner/NoAward with the real protective kill and P.executed unchanged
/// until its own later execution, the fixed-recipient exact once-only bond
/// refund, the all-FD actual-remainder settlement through BOTH seizure
/// entrypoints, and a fresh bound-first control with the exact half split,
/// an authorized unkill-mid duplicate while R stays positive, and no second
/// allocation. Ballots are created twice through the real
/// `_createForkBallot` route (never submitted twice); only P is bound. The
/// original fork fixture's disclosed local role seating/impersonation is
/// retained (crvUSD holder funding, creator/voter pranks, controller
/// seating, proxy-route unkill) and is never promoted to production
/// authorization. No storage overrides, no block-pin moves, no broadcasts,
/// no faked balances.
interface IVotingDup {
    function vote(uint256 voteId, bool option, bool autoExecute) external;
    function canExecute(uint256 voteId) external view returns (bool);
    function executeVote(uint256 voteId) external;
    function getVote(uint256 _id)
        external
        view
        returns (bool, bool, uint256, uint256, uint256, uint256, uint256, uint256, uint256, bytes memory);
}

interface IVotingExecutorFacts {
    function getEVMScriptExecutor(bytes calldata script) external view returns (address);
}

interface IVeSnapF {
    function balanceOfAt(address, uint256) external view returns (uint256);
}

abstract contract ForkDuplicateBallotScenarios is BountyForkFixture {
    uint256 internal _fdupSeq;

    struct DupF {
        Kit k;
        address g;
        address rep;
        address claimant;
        bytes32 id;
        uint256 pidP;
        uint256 pidQ;
        uint256 startP;
        uint256 startQ;
        uint256 voteEndP;
        uint256 executeByP;
        uint256 x;
    }

    struct Frozen {
        uint256 coreBal;
        uint256 bountyBal;
        uint256 fdBal;
        uint256 repBal;
        uint256 claimantBal;
        uint256 held;
        uint256 credits;
        uint256 dao;
        uint256 fdCursor;
        bytes32 listingHash;
    }

    function setUp() public virtual {
        _freshFork();
    }

    // ---------------------------------------------------------------- scaffold

    function _freezeF(DupF memory d) internal view returns (Frozen memory f) {
        f.coreBal = IErc20Venue(CRVUSD).balanceOf(address(d.k.core_));
        f.bountyBal = IErc20Venue(CRVUSD).balanceOf(address(d.k.b));
        f.fdBal = IErc20Venue(CRVUSD).balanceOf(FEEDIST);
        f.repBal = IErc20Venue(CRVUSD).balanceOf(d.rep);
        f.claimantBal = IErc20Venue(CRVUSD).balanceOf(d.claimant);
        (f.held, f.credits, f.dao) = d.k.b.accounting();
        f.fdCursor = IFdVenue(FEEDIST).last_token_time();
        f.listingHash = keccak256(abi.encode(d.k.core_.getListing(d.g)));
    }

    function _assertNoCallbackDriftF(Frozen memory pre, Frozen memory post, string memory label) internal pure {
        assertEq(post.coreBal, pre.coreBal, string.concat(label, ": lister custody unmoved by callbacks"));
        assertEq(post.bountyBal, pre.bountyBal, string.concat(label, ": bounty custody unmoved by callbacks"));
        assertEq(post.fdBal, pre.fdBal, string.concat(label, ": FD unmoved by callbacks"));
        assertEq(post.repBal, pre.repBal, string.concat(label, ": reporter unmoved by callbacks"));
        assertEq(post.claimantBal, pre.claimantBal, string.concat(label, ": claimant unmoved by callbacks"));
        assertEq(post.held, pre.held, string.concat(label, ": heldStakes unmoved by callbacks"));
        assertEq(post.credits, pre.credits, string.concat(label, ": no reward created by callbacks"));
        assertEq(post.dao, pre.dao, string.concat(label, ": dao liability unmoved by callbacks"));
        assertEq(post.fdCursor, pre.fdCursor, string.concat(label, ": callbacks never touched the FD cursor"));
        assertEq(post.listingHash, pre.listingHash, string.concat(label, ": listing allocation fields unmoved"));
    }

    /// @dev Real snapshot voters cast YES through the deployed app API while
    /// each ballot is open (frozen F03/F05 discipline; no tally/flag writes).
    function _castYesF(uint256 voteId) internal returns (uint256 accumulated) {
        address[] memory voters = forkVoters();
        require(voters.length > 0, "v02 fork fixture blocked: no discovered voting set");
        (,,, uint256 snapBlock,,,,,,) = IVotingDup(THIN_VOTING_APP).getVote(voteId);
        for (uint256 i = 0; i < voters.length; ++i) {
            uint256 pw = IVeSnapF(THIN_VE_CRV).balanceOfAt(voters[i], snapBlock);
            assertTrue(pw > 0, "V02_FORK_TALLY: voter has real veCRV at the snapshot");
            fvm.prank(voters[i]);
            IVotingDup(THIN_VOTING_APP).vote(voteId, true, false);
            accumulated += pw;
        }
        assertTrue(accumulated >= QUORUM_POWER_MIN, "V02_FORK_TALLY: YES clears the 30% acceptance quorum");
    }

    function _bytesEqF(bytes memory a, bytes memory b, string memory label) internal pure {
        require(keccak256(a) == keccak256(b), label);
    }

    /// @dev Fresh kit + primary listing + the identical-bytes P/Q pair, one
    /// stake, one submission binding only P, both ballots genuinely passed,
    /// parked at the common executable instant.
    function _mkDupF() internal returns (DupF memory d) {
        _mkDupStage(d);
        _dupVoteWindowF(d);
    }

    function _mkDupStage(DupF memory d) internal {
        d.k = _deployThinKit();
        d.g = _listPrimary(d.k);
        d.rep = reporter_();
        d.claimant = rando();
        _fdupSeq += 1;
        bytes32 eh = keccak256(abi.encode("v02-fork-dup", d.g, _fdupSeq));
        uint256 nonce = 91000 + _fdupSeq;

        // Creation twice through the real route; submission once, binding P.
        (bytes32 idP, uint256 pidP) = _createForkBallot(d.k, d.g, d.rep, nonce, eh);
        (bytes32 idQ, uint256 pidQ) = _createForkBallot(d.k, d.g, d.rep, nonce, eh);
        d.id = idP;
        d.pidP = pidP;
        d.pidQ = pidQ;
        assertTrue(pidP != pidQ, "V02_FORK_DISTINCT_IDS: P and Q are distinct actual proposal ids");
        assertEq(idP, idQ, "V02_FORK_ONE_REPORT: both real ballots carry the single deterministic report id");

        // Assert the identical COMPLETE bytes, not only identical visible
        // selectors/beneficiaries, and that they are the canonical script.
        bytes memory sp = _scriptOf(pidP);
        bytes memory sq = _scriptOf(pidQ);
        _bytesEqF(sp, sq, "V02_FORK_IDENTICAL_SCRIPT_BYTES: complete stored bytes of P and Q are identical");
        bytes memory canonical =
            BountyScripts.buildKillScript(THIN_AGENT, address(d.k.b), THIN_KILL_PROXY, d.g, idP, d.rep);
        _bytesEqF(sp, canonical, "V02_FORK_CANONICAL_BYTES: stored bytes equal the full canonical three-action script");
        assertEq(sp.length, 696, "V02_FORK_CANONICAL_BYTES: canonical 696-byte framing retained");
        emit log_named_bytes32("V02_FORK scriptHashP", keccak256(sp));
        emit log_named_bytes32("V02_FORK scriptHashQ", keccak256(sq));

        _fundReporter(d.k, d.rep, 1);
        fvm.prank(d.rep);
        bytes32 sid = d.k.b.submit(d.g, pidP, eh, nonce);
        assertEq(sid, idP, "V02_FORK_BOUND_ONLY_P: the single paid submission binds P");
        assertEq(IErc20Venue(CRVUSD).balanceOf(address(d.k.b)), STAKE, "V02_FORK_ONE_STAKE: exactly one bond");
    }

    function _dupVoteWindowF(DupF memory d) internal {
        // Genuinely pass BOTH ballots with the real funded snapshot voters.
        _castYesF(d.pidP);
        _castYesF(d.pidQ);

        (,, d.startP,,,,,,,) = IVotingDup(THIN_VOTING_APP).getVote(d.pidP);
        (,, d.startQ,,,,,,,) = IVotingDup(THIN_VOTING_APP).getVote(d.pidQ);
        ReportView memory rv = d.k.b.getReport(d.id);
        d.voteEndP = rv.voteEnd;
        d.executeByP = rv.executeBy;
        assertEq(rv.proposalId, d.pidP, "V02_FORK_BOUND_ONLY_P: stored proposal id is P's actual id");
        assertEq(d.voteEndP, d.startP + VOTE_TIME, "V02_FORK_CLOCK_BOUND: voteEnd is P's actual start + ballot");

        d.x = d.startQ + VOTE_TIME;
        assertEq(d.startQ, d.startP + COOLDOWN, "V02_FORK_COOLDOWN: real per-creator interval kept");
        assertTrue(d.x >= d.voteEndP, "V02_FORK_WINDOW: executes at or after both vote ends");
        assertTrue(d.x <= d.executeByP, "V02_FORK_WINDOW: executes no later than P.executeBy");
        assertTrue(d.executeByP > d.x, "V02_FORK_WINDOW: remaining execution margin is positive");
        fvm.warp(d.x);
        emit log_named_uint("V02_FORK pidP", d.pidP);
        emit log_named_uint("V02_FORK pidQ", d.pidQ);
        emit log_named_uint("V02_FORK startP", d.startP);
        emit log_named_uint("V02_FORK startQ", d.startQ);
        emit log_named_uint("V02_FORK executeByP", d.executeByP);
        emit log_named_address("V02_FORK beneficiary", d.rep);
        emit log_named_address("V02_FORK real-veCRV creator", forkBallotCreator());

        // Both canExecute observations true before the first execution; both
        // executed flags initially false; real gauge genuinely live.
        (bool pOpen, bool pExec,,,,,,,,) = IVotingDup(THIN_VOTING_APP).getVote(d.pidP);
        (bool qOpen, bool qExec,,,,,,,,) = IVotingDup(THIN_VOTING_APP).getVote(d.pidQ);
        assertFalse(pOpen, "V02_FORK_CLOSED: P closed at x");
        assertFalse(qOpen, "V02_FORK_CLOSED: Q closed at x");
        assertFalse(pExec, "V02_FORK_FLAGS_FALSE: P.executed false before any execution");
        assertFalse(qExec, "V02_FORK_FLAGS_FALSE: Q.executed false before any execution");
        assertTrue(IVotingDup(THIN_VOTING_APP).canExecute(d.pidP), "V02_FORK_EXECUTABLE: P genuinely passed");
        assertTrue(IVotingDup(THIN_VOTING_APP).canExecute(d.pidQ), "V02_FORK_EXECUTABLE: Q genuinely passed");
        assertFalse(IGaugeVenue(d.g).is_killed(), "V02_FORK_LIVE_BEFORE: real flag false");

        // Disclosed role/identity provenance for the receipt.
        BountyConfig memory cfg = d.k.b.config();
        assertEq(cfg.ownershipVoting, THIN_VOTING_APP, "V02_FORK_ROUTES: pinned real Voting app");
        assertEq(cfg.ownershipAgent, THIN_AGENT, "V02_FORK_ROUTES: pinned real Ownership Agent");
        assertEq(cfg.killProxy, THIN_KILL_PROXY, "V02_FORK_ROUTES: pinned real kill proxy");
        assertEq(cfg.callsScriptExecutor, THIN_CALLS_SCRIPT, "V02_FORK_ROUTES: pinned real CallsScript");
        assertEq(
            IVotingExecutorFacts(THIN_VOTING_APP).getEVMScriptExecutor(abi.encodePacked(bytes4(0x00000001))),
            THIN_CALLS_SCRIPT,
            "V02_FORK_ROUTES: live Voting binds the CallsScript executor for script type 0x00000001"
        );
    }

    function _scriptOf(uint256 voteId) internal view returns (bytes memory) {
        (,,,,,,,,, bytes memory s) = IVotingDup(THIN_VOTING_APP).getVote(voteId);
        return s;
    }

    // -------------------------------------------------- duplicate-first cells

    function _dupFirstCallbacksF(DupF memory d) internal {
        // NotAgent gate first: the callbacks cannot be forged externally.
        fvm.prank(rando());
        vm.expectRevert(IGaugeBounty.NotAgent.selector);
        d.k.b.creditBallot(d.id, d.rep);

        Frozen memory pre = _freezeF(d);
        fvm.recordLogs();
        fvm.prank(d.claimant); // outsider executes the duplicate
        IVotingDup(THIN_VOTING_APP).executeVote(d.pidQ);
        FVm.Log[] memory logs = fvm.getRecordedLogs();
        _assertNoCallbackDriftF(pre, _freezeF(d), "V02_FORK_CALLBACKS_NO_MONEY: Q's execution");
        assertTrue(
            _hasLog(logs, address(d.k.b), keccak256("ReportStateChanged(bytes32,uint8)")),
            "V02_FORK_SOURCE_PATH: the phase transition was emitted BY the bounty inside the real executeVote transaction"
        );

        (, bool pExec1,,,,,,,,) = IVotingDup(THIN_VOTING_APP).getVote(d.pidP);
        (, bool qExec1,,,,,,,,) = IVotingDup(THIN_VOTING_APP).getVote(d.pidQ);
        assertTrue(qExec1, "V02_FORK_FLAGS: Q.executed true after its execution");
        assertFalse(pExec1, "V02_FORK_FLAGS: the bound P remains unexecuted until its own later execution");
        assertTrue(IGaugeVenue(d.g).is_killed(), "V02_FORK_PROTECTIVE_KILL: the duplicate's real proxy kill landed");

        (bytes32 wid, address wrep, bool wel) = d.k.b.rewardTerms(d.g);
        assertEq(wid, bytes32(0), "V02_FORK_UNBOUND_HAS_NO_WINNER: no same-block Armed latch, winner stays empty");
        assertEq(wrep, address(0), "V02_FORK_UNBOUND_HAS_NO_WINNER: no reporter is attached");
        assertFalse(wel, "V02_FORK_UNBOUND_HAS_NO_WINNER: the listing is not eligible");

        ReportView memory rv = d.k.b.getReport(d.id);
        assertEq(
            uint256(rv.phase), uint256(Phase.NoAward), "V02_FORK_UNBOUND_CONSUMES_OFFER: pending report closes NoAward"
        );
        assertEq(
            uint256(rv.stakeState),
            uint256(StakeState.Refundable),
            "V02_FORK_UNBOUND_CONSUMES_OFFER: bond becomes Refundable"
        );
        assertEq(rv.rewardCredit, 0, "V02_FORK_UNBOUND_CONSUMES_OFFER: no credit created");
        assertEq(rv.voteEnd, d.voteEndP, "V02_FORK_CLOCK_BOUND: P's original stored voteEnd unchanged");
        assertEq(rv.executeBy, d.executeByP, "V02_FORK_CLOCK_BOUND: P's original stored executeBy unchanged");
        (uint256 held, uint256 credits, uint256 dao) = d.k.b.accounting();
        assertEq(held, STAKE, "V02_FORK_UNBOUND_CONSUMES_OFFER: the one bond is still held");
        assertEq(credits, 0, "V02_FORK_UNBOUND_CONSUMES_OFFER: no reward exists to fund");
        assertEq(dao, 0, "V02_FORK_UNBOUND_CONSUMES_OFFER: no liability invented");
    }

    function _lateBoundPThenRefundF(DupF memory d) internal {
        // Late bound execution while still killed cannot recognize.
        fvm.prank(d.claimant);
        IVotingDup(THIN_VOTING_APP).executeVote(d.pidP);
        (, bool pExec2,,,,,,,,) = IVotingDup(THIN_VOTING_APP).getVote(d.pidP);
        assertTrue(pExec2, "V02_FORK_FLAGS: P.executed true after its own execution");
        assertEq(
            uint256(d.k.b.getReport(d.id).phase),
            uint256(Phase.NoAward),
            "V02_FORK_UNBOUND_CONSUMES_OFFER: late P cannot revive the consumed report"
        );
        (bytes32 wid,, bool wel) = d.k.b.rewardTerms(d.g);
        assertEq(wid, bytes32(0), "V02_FORK_UNBOUND_HAS_NO_WINNER: still no winner after P's real execution");
        assertFalse(wel, "V02_FORK_UNBOUND_HAS_NO_WINNER: still ineligible after P's real execution");

        // Fixed-recipient exact once-only bond refund by an outsider.
        uint256 rep0 = IErc20Venue(CRVUSD).balanceOf(d.rep);
        uint256 claimant0 = IErc20Venue(CRVUSD).balanceOf(d.claimant);
        fvm.prank(d.claimant);
        (uint256 s, uint256 r) = d.k.b.claim(d.id);
        assertEq(s, STAKE, "V02_FORK_REFUND_FIXED_RECIPIENT: the non-forfeited stake pays once");
        assertEq(r, 0, "V02_FORK_NO_INVENTED_REWARD: the refund carries no invented reward");
        assertEq(
            IErc20Venue(CRVUSD).balanceOf(d.rep) - rep0,
            STAKE,
            "V02_FORK_REFUND_FIXED_RECIPIENT: exact stake to stored A"
        );
        assertEq(
            IErc20Venue(CRVUSD).balanceOf(d.claimant), claimant0, "V02_FORK_REFUND_FIXED_RECIPIENT: never msg.sender"
        );
        fvm.prank(d.claimant);
        (uint256 s2, uint256 r2) = d.k.b.claim(d.id);
        assertEq(s2 + r2, 0, "V02_FORK_REFUND_ONCE: a repeated claim is zero");
        (uint256 held2, uint256 credits2, uint256 dao2) = d.k.b.accounting();
        assertEq(held2 + credits2 + dao2, 0, "V02_FORK_CONSERVATION: liabilities discharged");
        assertEq(
            IErc20Venue(CRVUSD).balanceOf(address(d.k.b)),
            held2 + credits2 + dao2,
            "V02_FORK_CONSERVATION: bounty backs its liabilities exactly"
        );
    }

    function _settleAllFdF(DupF memory d, bool viaCheckpoint) internal {
        uint256 rActual = d.k.core_.getListing(d.g).remaining;
        assertTrue(rActual > 0, "V02_FORK_POSITIVE_REMAINDER: positive actual remainder");
        uint256 fd0 = IErc20Venue(CRVUSD).balanceOf(FEEDIST);
        uint256 core0 = IErc20Venue(CRVUSD).balanceOf(address(d.k.core_));
        uint256 bounty0 = IErc20Venue(CRVUSD).balanceOf(address(d.k.b));
        if (viaCheckpoint) {
            fvm.prank(d.claimant);
            (uint256 rel, uint256 conf) = d.k.core_.checkpoint(d.g);
            assertEq(rel, 0, "V02_FORK_ALL_FD_EXACT: a killed listing releases nothing at seizure");
            assertEq(conf, rActual, "V02_FORK_ALL_FD_EXACT: checkpoint seizure pays out actual R");
        } else {
            fvm.prank(d.claimant);
            uint256 conf = d.k.core_.confiscate(d.g);
            assertEq(conf, rActual, "V02_FORK_ALL_FD_EXACT: confiscate seizure pays out actual R");
        }
        ICurveGaugeListerV2.ListingV2 memory ls = d.k.core_.getListing(d.g);
        assertEq(uint256(ls.status), 3, "V02_FORK_ALL_FD_EXACT: listing terminal Confiscated");
        assertEq(ls.confiscated, rActual, "V02_FORK_ALL_FD_EXACT: gross is the actual remainder");
        assertEq(ls.reporterReward, 0, "V02_FORK_ALL_FD_EXACT: reporter half is zero without a winner");
        assertEq(ls.fdConfiscated, rActual, "V02_FORK_ALL_FD_EXACT: all actual R goes to the pinned FD");
        assertEq(ls.rewardReportId, 0, "V02_FORK_ALL_FD_EXACT: no report id attached to the seizure");
        assertEq(
            IErc20Venue(CRVUSD).allowance(address(d.k.core_), address(d.k.b)),
            0,
            "V02_FORK_ALL_FD_EXACT: no V2-to-bounty allowance"
        );
        assertEq(
            IErc20Venue(CRVUSD).balanceOf(FEEDIST) - fd0, rActual, "V02_FORK_ALL_FD_EXACT: real FD received exactly R"
        );
        assertEq(
            IErc20Venue(CRVUSD).balanceOf(address(d.k.b)),
            bounty0,
            "V02_FORK_NO_INVENTED_REWARD: no phantom half funded"
        );
        assertEq(
            IErc20Venue(CRVUSD).balanceOf(address(d.k.core_)),
            core0 - rActual,
            "V02_FORK_ALL_FD_EXACT: escrow drained exactly"
        );
        assertEq(d.k.core_.totalEscrow(), 0, "V02_FORK_ALL_FD_EXACT: escrow fully accounted");
        assertEq(IFdVenue(FEEDIST).last_token_time(), block.timestamp, "V02_FORK_ALL_FD_EXACT: FD accounting ran");
        assertEq(
            IFdVenue(FEEDIST).token_last_balance(),
            IErc20Venue(CRVUSD).balanceOf(FEEDIST),
            "V02_FORK_ALL_FD_EXACT: FD accounted == custody"
        );
        (, uint256 credits,) = d.k.b.accounting();
        assertEq(credits, 0, "V02_FORK_NO_INVENTED_REWARD: no reward credit ever funded");
    }

    /// @dev Subcell A: duplicate-first through the confiscate entrypoint.
    function _forkCellDuplicateFirstConfiscate() private {
        _freshFork();
        DupF memory d = _mkDupF();
        _dupFirstCallbacksF(d);
        _lateBoundPThenRefundF(d);
        _settleAllFdF(d, false);
    }

    /// @dev Subcell B: the mirror duplicate-first cell through the
    /// checkpoint entrypoint (fresh fork, fresh everything).
    function _forkCellDuplicateFirstCheckpoint() private {
        _freshFork();
        DupF memory d = _mkDupF();
        _dupFirstCallbacksF(d);
        _lateBoundPThenRefundF(d);
        _settleAllFdF(d, true);
    }

    // ------------------------------------------------- bound-first control

    /// @dev Subcell C: fresh bound-first control. P executes first and wins
    /// permanently; the disclosed authorized unkill restores the flag with R
    /// positive; Q's later duplicate cannot erase the winner; the settlement
    /// splits exactly B=floor(R/2)/F=R-B once; later attempts add nothing.
    function _forkCellBoundFirstControl() private {
        _freshFork();
        DupF memory d = _mkDupF();
        _boundFirstRecognitionF(d);
        _duplicateAfterWinnerF(d);
        uint256 rActual = d.k.core_.getListing(d.g).remaining;
        assertTrue(rActual > 0, "V02_FORK_POSITIVE_REMAINDER: bound-first settlement R positive");
        uint256 fd0 = IErc20Venue(CRVUSD).balanceOf(FEEDIST);
        uint256 bounty0 = IErc20Venue(CRVUSD).balanceOf(address(d.k.b));
        assertTrue(
            block.timestamp > IFdVenue(FEEDIST).last_token_time() + 86_400,
            "V02_FORK_FD_READY: settlement sits past the strict public checkpoint cooldown"
        );
        fvm.prank(d.claimant);
        uint256 gross = d.k.core_.confiscate(d.g);
        assertEq(gross, rActual, "V02_FORK_BOUND_FIRST: confiscate seizes actual R");
        _assertBoundSplitOracles(d, rActual, fd0, bounty0);
    }

    function _boundFirstRecognitionF(DupF memory d) internal {
        fvm.prank(rando());
        vm.expectRevert(IGaugeBounty.NotAgent.selector);
        d.k.b.recognizeKill(d.id);

        Frozen memory pre = _freezeF(d);
        fvm.recordLogs();
        fvm.prank(d.claimant);
        IVotingDup(THIN_VOTING_APP).executeVote(d.pidP);
        FVm.Log[] memory logs = fvm.getRecordedLogs();
        _assertNoCallbackDriftF(pre, _freezeF(d), "V02_FORK_CALLBACKS_NO_MONEY: bound-first P execution");
        assertTrue(
            _hasLog(logs, address(d.k.b), keccak256("ReportStateChanged(bytes32,uint8)")),
            "V02_FORK_SOURCE_PATH: recognition emitted by the bounty inside the real executeVote transaction"
        );
        (, bool pExec,,,,,,,,) = IVotingDup(THIN_VOTING_APP).getVote(d.pidP);
        assertTrue(pExec, "V02_FORK_FLAGS: bound P executed");
        assertTrue(IGaugeVenue(d.g).is_killed(), "V02_FORK_PROTECTIVE_KILL: bound execution kills");
        ReportView memory rv = d.k.b.getReport(d.id);
        assertEq(
            uint256(rv.phase), uint256(Phase.Recognized), "V02_FORK_BOUND_FIRST_HALF_FUNDED: bound-first recognition"
        );
        (bytes32 wid, address wrep, bool wel) = d.k.b.rewardTerms(d.g);
        assertEq(wid, d.id, "V02_FORK_SINGLE_ALLOCATION: the correct permanent winner is latched");
        assertEq(wrep, d.rep, "V02_FORK_SINGLE_ALLOCATION: the winner names the stored reporter");
        assertTrue(wel, "V02_FORK_BOUND_FIRST_HALF_FUNDED: recognized and unfunded is eligible");
        (, uint256 credits0,) = d.k.b.accounting();
        assertEq(credits0, 0, "V02_FORK_BOUND_FIRST_HALF_FUNDED: no funded credit before settlement");
    }

    function _duplicateAfterWinnerF(DupF memory d) internal {
        // Disclosed authorized unkill while R remains positive, then Q's
        // duplicate execution is a real false->true kill that must not erase
        // the winner.
        _unkillViaDirectAdmin(d.g);
        ICurveGaugeListerV2.ListingV2 memory ls = d.k.core_.getListing(d.g);
        assertEq(uint256(ls.status), 1, "V02_FORK_SINGLE_ALLOCATION: unkill keeps the listing Active");
        assertTrue(ls.remaining > 0, "V02_FORK_SINGLE_ALLOCATION: R stays positive through the unkill");

        Frozen memory pre = _freezeF(d);
        fvm.prank(d.claimant);
        IVotingDup(THIN_VOTING_APP).executeVote(d.pidQ);
        _assertNoCallbackDriftF(pre, _freezeF(d), "V02_FORK_CALLBACKS_NO_MONEY: post-recognition duplicate");
        (, bool qExec,,,,,,,,) = IVotingDup(THIN_VOTING_APP).getVote(d.pidQ);
        assertTrue(qExec, "V02_FORK_FLAGS: Q executed after the winner");
        assertTrue(IGaugeVenue(d.g).is_killed(), "V02_FORK_PROTECTIVE_KILL: the duplicate's later kill still protects");
        (bytes32 wid,, bool wel) = d.k.b.rewardTerms(d.g);
        assertEq(wid, d.id, "V02_FORK_SINGLE_ALLOCATION: the winner cannot be erased by the duplicate");
        assertTrue(wel, "V02_FORK_SINGLE_ALLOCATION: entitlement intact before settlement");
        assertEq(
            uint256(d.k.b.getReport(d.id).phase),
            uint256(Phase.Recognized),
            "V02_FORK_SINGLE_ALLOCATION: phase survives the duplicate"
        );
    }

    /// @dev Exact allocation amounts asserted BEFORE the Rewarded phase so an
    /// allocation mutant reaches the money oracle (§5 ordering), then the
    /// once-only permissionless claim and the inertness of every later
    /// callback/claim/seizure attempt.
    function _assertBoundSplitOracles(DupF memory d, uint256 rActual, uint256 fd0, uint256 bounty0) internal {
        ICurveGaugeListerV2.ListingV2 memory ls = d.k.core_.getListing(d.g);
        assertEq(ls.reporterReward, rActual / 2, "V02_FORK_BOUND_FIRST_HALF_FUNDED: B = floor(actual R/2) exactly");
        assertEq(ls.fdConfiscated, rActual - rActual / 2, "V02_FORK_BOUND_FIRST_HALF_FUNDED: F = R - B exactly");
        assertEq(
            ls.rewardReportId,
            bytes32(uint256(d.id)),
            "V02_FORK_BOUND_FIRST_HALF_FUNDED: the matching report id is allocated"
        );
        assertEq(uint256(ls.status), 3, "V02_FORK_BOUND_FIRST_HALF_FUNDED: terminal Confiscated");
        assertEq(
            IErc20Venue(CRVUSD).allowance(address(d.k.core_), address(d.k.b)),
            0,
            "V02_FORK_BOUND_FIRST_HALF_FUNDED: V2-to-bounty allowance cleared"
        );
        assertEq(
            IErc20Venue(CRVUSD).balanceOf(FEEDIST) - fd0,
            rActual - rActual / 2,
            "V02_FORK_BOUND_FIRST_HALF_FUNDED: exact FD receipt above baseline"
        );
        assertEq(
            IErc20Venue(CRVUSD).balanceOf(address(d.k.b)),
            bounty0 + rActual / 2,
            "V02_FORK_BOUND_FIRST_HALF_FUNDED: exact B pulled into bounty custody"
        );
        assertEq(d.k.core_.totalEscrow(), 0, "V02_FORK_BOUND_FIRST_HALF_FUNDED: escrow fully accounted");
        (, uint256 credits,) = d.k.b.accounting();
        assertEq(credits, rActual / 2, "V02_FORK_BOUND_FIRST_HALF_FUNDED: exactly the funded half credited");
        // Phase assertion deliberately AFTER the exact allocation asserts.
        assertEq(
            uint256(d.k.b.getReport(d.id).phase),
            uint256(Phase.Rewarded),
            "V02_FORK_BOUND_FIRST_HALF_FUNDED: Rewarded after funding"
        );
        _forkClaimOnceInert(d, rActual);
    }

    function _forkClaimOnceInert(DupF memory d, uint256 rActual) internal {
        uint256 rep0 = IErc20Venue(CRVUSD).balanceOf(d.rep);
        uint256 claimant0 = IErc20Venue(CRVUSD).balanceOf(d.claimant);
        fvm.prank(d.claimant);
        (uint256 s, uint256 r) = d.k.b.claim(d.id);
        assertEq(s, STAKE, "V02_FORK_SINGLE_ALLOCATION: bond paid with the reward");
        assertEq(r, rActual / 2, "V02_FORK_SINGLE_ALLOCATION: the funded half paid once");
        assertEq(
            IErc20Venue(CRVUSD).balanceOf(d.rep) - rep0,
            STAKE + rActual / 2,
            "V02_FORK_SINGLE_ALLOCATION: fixed recipient, exact total"
        );
        assertEq(
            IErc20Venue(CRVUSD).balanceOf(d.claimant), claimant0, "V02_FORK_SINGLE_ALLOCATION: claimant paid nothing"
        );
        (uint256 held, uint256 credits2, uint256 dao) = d.k.b.accounting();
        assertEq(held + credits2 + dao, 0, "V02_FORK_CONSERVATION: all liabilities discharged");
        assertEq(
            IErc20Venue(CRVUSD).balanceOf(address(d.k.b)), 0, "V02_FORK_CONSERVATION: custody matches discharged ledger"
        );

        // Later attempts add no reward.
        fvm.prank(THIN_AGENT);
        d.k.b.recognizeKill(d.id);
        fvm.prank(THIN_AGENT);
        d.k.b.creditBallot(d.id, d.rep);
        (bytes32 wid,, bool wel) = d.k.b.rewardTerms(d.g);
        assertEq(wid, d.id, "V02_FORK_SINGLE_ALLOCATION: the winner remains latched forever");
        assertFalse(wel, "V02_FORK_SINGLE_ALLOCATION: the consumed allocation is not re-eligible");
        fvm.prank(d.claimant);
        (uint256 s3, uint256 r3) = d.k.b.claim(d.id);
        assertEq(s3 + r3, 0, "V02_FORK_SINGLE_ALLOCATION: no second payment");
        fvm.prank(d.claimant);
        assertEq(d.k.core_.confiscate(d.g), 0, "V02_FORK_SINGLE_ALLOCATION: no second seizure");
        (, uint256 credits4,) = d.k.b.accounting();
        assertEq(credits4, 0, "V02_FORK_SINGLE_ALLOCATION: no reward added by any replay");
    }

    // ------------------------------------------------------------ identity

    function test_Fork_Rework_DuplicateCanonicalBallotDisposition() public {
        _forkCellDuplicateFirstConfiscate();
        _forkCellDuplicateFirstCheckpoint();
        _forkCellBoundFirstControl();
    }
}
