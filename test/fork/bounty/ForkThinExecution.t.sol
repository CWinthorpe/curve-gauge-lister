// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BountyForkFixture, Kit} from "./BountyForkFixture.sol";
import {ForkFixture, FVm, IErc20Venue, IFdVenue} from "../ForkFixture.sol";
import {GaugeBounty} from "../../../contracts/GaugeBounty.sol";
import {CurveGaugeListerV2} from "../../../contracts/CurveGaugeListerV2.sol";
import {ReportView, Phase, StakeState} from "../../../contracts/bounty/BountyTypes.sol";
import {BountyScripts} from "../../../contracts/libraries/BountyScripts.sol";

/// @dev F03/F04 (plans/BOUNTY-THIN-PLAN.md §7.3): real executed canonical
/// recognition (actual proposals, real funded veCRV snapshot voters,
/// ballots/executeVote/Agent/proxy/gauge, executed canonical hash and
/// false->true recognition) and real losing/late-execution refunds. No
/// patched tallies, executed flags, ACL/code or flags; no mocked governance.
/// Voter set: real holders with real balance at the pin's previous-block
/// snapshot (executor fixture discovery via read-only log scan, disclosed
/// below).
interface IVotingExec {
    function vote(uint256 voteId, bool option, bool autoExecute) external;
    function canExecute(uint256 voteId) external view returns (bool);
    function executeVote(uint256 voteId) external;
    function getVote(uint256 _id)
        external
        view
        returns (bool, bool, uint256, uint256, uint256, uint256, uint256, uint256, uint256, bytes memory);
}

interface IVeSnap {
    function balanceOfAt(address, uint256) external view returns (uint256);
}

interface GovernanceProbe {
    function is_killed() external view returns (bool);
}

abstract contract ForkThinExecutionSpec is BountyForkFixture {
    // ----- discovered real veCRV whales (verified balanceOf at the pin) ----
    // Populated from the read-only VoteCast scan of live ballots around the
    // pin; each entry's pin power is asserted before use, and totals are
    // asserted to clear the 30% acceptance quorum.
    // Voters + quorum come from BountyForkFixture (forkVoters/QUORUM_POWER_MIN).

    function setUp() public virtual {
        _freshFork();
    }

    // ------------------------------------------------------------------ F03

    function test_Fork_ThinCanonicalExecution() public {
        _freshFork();
        Kit memory k = _deployThinKit();
        address g = _listPrimary(k);
        address rep = reporter_();
        _fundReporter(k, rep, 1);
        // Rework F03: the ballot is created by the disclosed REAL creator
        // (sponsor) and only the encoded BENEFICIARY submits (§7 migration).
        (bytes32 id, uint256 voteId) = _submitForkBallot(k, g, rep, 403, keccak256(abi.encode("f03", g, rep)));
        ReportView memory rv = k.b.getReport(id);
        require(uint8(rv.phase) == uint8(Phase.Proposed) && rv.reporter == rep, "F03: beneficiary admitted");

        uint256 yesPower = _f03CastYes(voteId);

        // Ballot window closes; permissionless execution runs the REAL
        // CallsScript through the REAL Agent into bounty, proxy and gauge.
        // No-token callback discipline (thin §3.1/§4.2): the whole
        // execution transaction must move ZERO crvUSD and never touch the
        // FD, while the recorded script bytes must hash to the canonical
        // three-action script for THIS case (§7.3 "executed canonical hash").
        fvm.warp(k.b.getReport(id).voteEnd);
        assertTrue(IVotingExec(THIN_VOTING_APP).canExecute(voteId), "F03: tally passed");
        assertFalse(GovernanceProbe(g).is_killed(), "F03: flag false before execution");
        uint256 fdCursorBefore = IFdVenue(FEEDIST).last_token_time();
        uint256 fdBalBefore = IErc20Venue(CRVUSD).balanceOf(FEEDIST);
        fvm.recordLogs();
        fvm.prank(rep); // any outsider may execute; reporter here
        IVotingExec(THIN_VOTING_APP).executeVote(voteId);
        FVm.Log[] memory execLogs = fvm.getRecordedLogs();
        assertEq(_countCrvUsdTransfers(execLogs), 0, "F03: canonical execution moved no crvUSD");
        assertEq(IFdVenue(FEEDIST).last_token_time(), fdCursorBefore, "F03: recognition never touched the FD");
        assertEq(IErc20Venue(CRVUSD).balanceOf(FEEDIST), fdBalBefore, "F03: no FD payment before settlement");

        _f03RecordChecks(voteId, yesPower, g, k, id);
        ReportView memory rv2 = k.b.getReport(id);
        assertEq(uint8(rv2.phase), uint8(Phase.Recognized), "F03: false->true canonical recognition");
        assertEq(uint8(rv2.stakeState), uint8(StakeState.Refundable), "F03: bond refundable at recognition");
        _f03SettleAndClaim(k, id, g, rep);
    }

    function _f03CastYes(uint256 voteId) private returns (uint256 yesPower) {
        (,,,,,, uint256 yeaBefore,,,) = IVotingExec(THIN_VOTING_APP).getVote(voteId);
        require(yeaBefore == 0, "F03: fresh ballot has no votes");
        // Real snapshot voters, real vote API, real prior-block balances.
        address[] memory voters = forkVoters();
        require(voters.length > 0, "F03 fixture blocked: no discovered voting set");
        (,, uint256 startDate, uint256 snapBlock,,,,,,) = IVotingExec(THIN_VOTING_APP).getVote(voteId);
        startDate;
        for (uint256 i = 0; i < voters.length; ++i) {
            address v = voters[i];
            // Accumulate the ballot's own snapshot oracle (balanceOfAt at
            // the recorded preceding block) — identical input the contract
            // charges the tally with; the live pinned read is only a gate.
            uint256 pw = IVeSnap(THIN_VE_CRV).balanceOfAt(v, snapBlock);
            assertTrue(pw > 0, "F03: voter has real veCRV at the snapshot");
            fvm.prank(v);
            IVotingExec(THIN_VOTING_APP).vote(voteId, true, false);
            yesPower += pw;
        }
        assertTrue(yesPower >= QUORUM_POWER_MIN, "F03: YES clears the 30% acceptance quorum");
    }

    function _f03RecordChecks(uint256 voteId, uint256 yesPower, address g, Kit memory k, bytes32 id) private {
        (bool open, bool executed,,,,, uint256 yea,,,) = IVotingExec(THIN_VOTING_APP).getVote(voteId);
        assertFalse(open, "F03: ballot closed by execution");
        assertTrue(executed, "F03: ballot executed on the real app");
        assertEq(yea, yesPower, "F03: yea is the sum of real snapshot powers");
        (,,,,,,,,, bytes memory script) = IVotingExec(THIN_VOTING_APP).getVote(voteId);
        // The executed script bytes are the canonical three-action script
        // bound at creation: equality over the COMPLETE bytes (targets,
        // values, calldata, report/domain, no trailing surface).
        bytes memory canonical =
            BountyScripts.buildKillScript(THIN_AGENT, address(k.b), THIN_KILL_PROXY, g, id, k.b.getReport(id).reporter);
        assertEq(keccak256(script), keccak256(canonical), "F03: executed script is the canonical bytes");
        assertTrue(GovernanceProbe(g).is_killed(), "F03: canonical execution flipped the real flag");
    }

    bytes32 private constant T_CRVUSD_TRANSFER = keccak256("Transfer(address,address,uint256)");

    function _countCrvUsdTransfers(FVm.Log[] memory logs) private pure returns (uint256 n) {
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].emitter == CRVUSD && logs[i].topics.length == 3 && logs[i].topics[0] == T_CRVUSD_TRANSFER) {
                ++n;
            }
        }
    }

    function _f03SettleAndClaim(Kit memory k, bytes32 id, address g, address rep) private {
        // Real safe settlement: the V2 confiscate hook credits exactly B and
        // routes F to the real FD — settlement is self-funding: the core's
        // fee escrow delivers B to the bounty via creditReward's pull and F
        // to the FD (no donation; donations are never required or credited).
        (uint256 held0, uint256 credits0, uint256 dao0) = k.b.accounting();
        require(credits0 == 0, "F03: no credit before settlement");
        assertEq(held0, STAKE, "F03: refundable bond still held");
        dao0;
        assertEq(IErc20Venue(CRVUSD).balanceOf(address(k.core_)), FEE, "F03: full escrow in the V2 pre-settlement");
        assertEq(IErc20Venue(CRVUSD).balanceOf(address(k.b)), STAKE, "F03: bounty custody is exactly the bond");
        uint256 fdBefore = IErc20Venue(CRVUSD).balanceOf(FEEDIST);
        uint256 repBefore = IErc20Venue(CRVUSD).balanceOf(rep);
        fvm.prank(rep);
        uint256 gross = k.core_.confiscate(g);
        require(gross == FEE, "F03: full remainder confiscated");
        _f03SettleOracles(k, g, fdBefore);
        _f03ClaimAndReplays(k, id, g, rep, repBefore);
    }

    function _f03SettleOracles(Kit memory k, address g, uint256 fdBefore) private {
        (uint256 held1, uint256 credits1, uint256 dao1) = k.b.accounting();
        assertEq(credits1, FEE / 2, "F03: exactly the half credited");
        assertEq(held1, STAKE, "F03: bond still held until claimed");
        assertEq(dao1, 0, "F03: nothing forfeited");
        assertEq(IErc20Venue(CRVUSD).balanceOf(address(k.core_)), 0, "F03: escrow emptied exactly");
        assertEq(IErc20Venue(CRVUSD).balanceOf(address(k.b)), STAKE + FEE / 2, "F03: B pulled into bounty custody");
        assertEq(IErc20Venue(CRVUSD).balanceOf(FEEDIST) - fdBefore, FEE / 2, "F03: real FD received F");
        assertEq(IFdVenue(FEEDIST).last_token_time(), block.timestamp, "F03: mandatory checkpoint advanced the cursor");
        assertEq(
            IFdVenue(FEEDIST).token_last_balance(),
            IErc20Venue(CRVUSD).balanceOf(FEEDIST),
            "F03: FD accounted balance == custody"
        );
        g;
    }

    function _f03ClaimAndReplays(Kit memory k, bytes32 id, address g, address rep, uint256 repBefore) private {
        (uint256 stake, uint256 reward) = k.b.claim(id);
        assertEq(stake, STAKE, "F03: bond paid");
        assertEq(reward, FEE / 2, "F03: reward paid");
        assertEq(IErc20Venue(CRVUSD).balanceOf(rep) - repBefore, STAKE + FEE / 2, "F03: reporter custody exact");
        (uint256 held2, uint256 credits2, uint256 dao2) = k.b.accounting();
        assertEq(held2 + credits2 + dao2, 0, "F03: all liabilities discharged");
        assertEq(IErc20Venue(CRVUSD).balanceOf(address(k.b)), 0, "F03: bounty custody emptied");
        // Recognized/Rewarded is durable: late callback/claim/seizure
        // replays are inert.
        fvm.prank(THIN_AGENT);
        k.b.recognizeKill(id);
        fvm.prank(THIN_AGENT);
        k.b.creditBallot(id, reporter_());
        assertEq(uint8(k.b.getReport(id).phase), uint8(Phase.Rewarded), "F03: rewarded stays rewarded");
        (uint256 s3, uint256 r3) = k.b.claim(id);
        assertEq(s3 + r3, 0, "F03: claim pays once");
        fvm.prank(keeper());
        assertEq(k.core_.confiscate(g), 0, "F03: no second seizure");
    }

    // ------------------------------------------------------------------ F04

    function test_Fork_ThinLosingAndExpiredRefunds() public {
        _f04RealLosingBallotRefund();
        _f04PassedUnexecutedLateKill();
    }

    function _f04RealLosingBallotRefund() private {
        _freshFork();
        Kit memory k = _deployThinKit();
        address g = _listPrimary(k);
        address rep = reporter_();
        _fundReporter(k, rep, 1);
        (bytes32 id, uint256 voteIdA) = _submitForkBallot(k, g, rep, 441, keccak256(abi.encode("f04a", g)));
        // A genuine low-quorum losing ballot: nobody votes, the window
        // closes with zero yea, resolve observes the closed failed record.
        fvm.warp(k.b.getReport(id).voteEnd);
        assertFalse(IVotingExec(THIN_VOTING_APP).canExecute(voteIdA), "F04a: fails on quorum");
        fvm.prank(rep);
        assertTrue(k.b.resolve(id), "F04a: losing ballot resolves");
        assertEq(uint8(k.b.getReport(id).phase), uint8(Phase.Rejected), "F04a: Rejected");
        uint256 before = IErc20Venue(CRVUSD).balanceOf(rep);
        (uint256 stake,) = k.b.claim(id);
        assertEq(stake, STAKE, "F04a: losing ballot returns the full bond");
        assertEq(IErc20Venue(CRVUSD).balanceOf(rep) - before, STAKE, "F04a: exact real-token refund");
        assertFalse(GovernanceProbe(g).is_killed(), "F04a: nothing was killed by a losing report");
    }

    function _f04PassedUnexecutedLateKill() private {
        _freshFork();
        Kit memory k = _deployThinKit();
        address g = _listPrimary(k);
        address rep = reporter_();
        _fundReporter(k, rep, 1);
        (bytes32 id, uint256 voteId) = _submitForkBallot(k, g, rep, 442, keccak256(abi.encode("f04b", g)));
        address[] memory voters = forkVoters();
        require(voters.length > 0, "F04b fixture blocked: no discovered voting set");
        for (uint256 i = 0; i < voters.length; ++i) {
            fvm.prank(voters[i]);
            IVotingExec(THIN_VOTING_APP).vote(voteId, true, false);
        }
        // Passed but NEVER executed, past executeBy: local expiry refunds.
        fvm.warp(k.b.getReport(id).executeBy + 1);
        (uint256 stake, uint256 reward) = k.b.claim(id);
        assertEq(stake + reward, STAKE, "F04b: refund at expiry, no reward without execution");
        assertEq(uint8(k.b.getReport(id).phase), uint8(Phase.Expired), "F04b: Expired");

        // Late upstream execution still kills (the accepted ballot is
        // executable indefinitely) but cannot earn or resurrect anything.
        assertTrue(IVotingExec(THIN_VOTING_APP).canExecute(voteId), "F04b: still executable");
        fvm.prank(rep);
        IVotingExec(THIN_VOTING_APP).executeVote(voteId);
        assertTrue(GovernanceProbe(g).is_killed(), "F04b: late execution delivers the kill");
        ReportView memory rv = k.b.getReport(id);
        assertEq(uint8(rv.phase), uint8(Phase.Expired), "F04b: no resurrection to Recognized/Rewarded");
        assertEq(rv.rewardCredit, 0, "F04b: no reward invented");
        (uint256 s2, uint256 r2) = k.b.claim(id);
        assertEq(s2 + r2, 0, "F04b: refund already paid, nothing repeats");
        (uint256 held,,) = k.b.accounting();
        assertEq(held, 0, "F04b: ledger settled");
    }
}
