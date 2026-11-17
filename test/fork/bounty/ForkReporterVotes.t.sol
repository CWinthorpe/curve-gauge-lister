// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BountyForkFixture, Kit} from "./BountyForkFixture.sol";
import {ForkFixture, FVm, IErc20Venue} from "../ForkFixture.sol";
import {GaugeBounty} from "../../../contracts/GaugeBounty.sol";
import {CurveGaugeListerV2} from "../../../contracts/CurveGaugeListerV2.sol";
import {ReportView, Phase, StakeState} from "../../../contracts/bounty/BountyTypes.sol";
import {IGaugeBounty} from "../../../contracts/interfaces/IGaugeBounty.sol";
import {BountyScripts} from "../../../contracts/libraries/BountyScripts.sol";

/// @dev Real mainnet Voting app read surface for bound-record verification.
interface IVotingAppFactsR {
    function votesLength() external view returns (uint256);
    function lastCreateVoteTimes(address) external view returns (uint256);
    function getVote(uint256 _id)
        external
        view
        returns (
            bool open,
            bool executed,
            uint256 startDate,
            uint256 snapshotBlock,
            uint256 supportRequired,
            uint256 minAcceptQuorum,
            uint256 yea,
            uint256 nay,
            uint256 votingPower,
            bytes memory script
        );
}

interface IVotingExecR {
    function vote(uint256 voteId, bool option, bool autoExecute) external;
    function executeVote(uint256 voteId) external;
}

interface IVeSnapR {
    function balanceOfAt(address, uint256) external view returns (uint256);
}

interface IVotingNewFork {
    function newVote(bytes calldata script, string calldata metadata, bool castVote, bool executesIfDecided)
        external
        returns (uint256);
}

/// @dev Migrated fork identities (plans/BOUNTY-REWORK-PLAN.md §7): F01
/// (test_Fork_ThinLockAndCanonicalVote) becomes REAL beneficiary-bound
/// creation/admission — an actual creator (a disclosed real veCRV holder,
/// NOT the beneficiary) creates the canonical S(rA, A, g) ballot through
/// the deployed Voting API and only A may bind it; F02
/// (test_Fork_ThinCooldownQueue) becomes independent beneficiary-bound
/// ballots: coexisting same-gauge reports, upstream per-creator cooldowns
/// never gating another pair's admission, winner takes the single award,
/// the loser refunds. The retired lock/queue/creation cells are gone with
/// the machinery they exercised.
abstract contract ReporterVotesForkSpec is BountyForkFixture {
    function setUp() public virtual {
        _freshFork();
    }

    function _votingR() internal view returns (IVotingAppFactsR) {
        return IVotingAppFactsR(THIN_VOTING_APP);
    }

    // --------------------------------------- F01: beneficiary vote binding

    function test_Fork_Rework_BeneficiaryVoteBinding() public {
        _freshFork();
        Kit memory k = _deployThinKit();
        address g = _listPrimary(k);
        address rep = reporter_(); // BENEFICIARY + submitter
        address sponsor = forkBallotCreator(); // ACTUAL creator, distinct
        assertTrue(sponsor != rep, "fork: sponsorship shape is real");
        _fundReporter(k, rep, 1);

        uint256 vl0 = _votingR().votesLength();
        bytes32 eh = keccak256(abi.encode("f01r", g, rep));
        uint256 nonce = 1001;
        // The creator's upstream proposal rights are exercised; the bounty
        // never reads or admits them (no creator getter exists anywhere).
        (bytes32 id, uint256 proposalId) = _createForkBallot(k, g, rep, nonce, eh);
        assertEq(proposalId, vl0, "fork: monotonic actual id equals the pre-call length");
        assertEq(_votingR().votesLength(), vl0 + 1, "fork: exactly one real ballot");

        uint256 startDate = _assertCanonicalForkBallot(k, g, rep, id, proposalId);

        _assertMismatchedForkBallot(k, g, rep, sponsor);

        // The beneficiary submits the honest ballot with the exact stake.
        fvm.prank(rep);
        bytes32 idA = k.b.submit(g, proposalId, eh, nonce);
        assertEq(idA, id, "fork: submitted id equals the precomputed id");
        ReportView memory rv = k.b.getReport(idA);
        assertEq(uint8(rv.phase), uint8(Phase.Proposed), "fork: admitted immediately");
        assertEq(uint8(rv.stakeState), uint8(StakeState.Bonded), "fork: exact bond");
        assertEq(rv.proposalId, proposalId, "fork: immutable ballot binding");
        assertEq(rv.voteEnd, startDate + 604800, "fork: ORIGINAL clock bound");
        assertEq(rv.executeBy, startDate + 2 * 604800, "fork: grace after the ballot");
        assertEq(IErc20Venue(CRVUSD).balanceOf(address(k.b)), STAKE, "fork: real bond in the bounty");

        // Real funded snapshot voters pass the ballot; permissionless
        // execution runs the genuine CallsScript/Agent/proxy route and the
        // beneficiary-bound callbacks recognize with the false->true flag.
        _castYesR(proposalId);
        fvm.warp(rv.voteEnd);
        assertTrue(!_votingOpenR(proposalId), "fork: closed at voteEnd");
        fvm.prank(strangerFork());
        IVotingExecR(THIN_VOTING_APP).executeVote(proposalId);
        assertEq(uint8(k.b.getReport(idA).phase), uint8(Phase.Recognized), "fork: canonical recognition");
        (bytes32 latched,, bool eligible) = k.b.rewardTerms(g);
        assertEq(latched, idA, "fork: winner latch names the beneficiary report");
        assertTrue(eligible, "fork: entitlement live");

        _settleForkSingle(k, g, rep, idA);
    }

    function _settleForkSingle(Kit memory k, address gauge, address beneficiary, bytes32 id) internal {
        uint256 fdBefore = IErc20Venue(CRVUSD).balanceOf(FEEDIST);
        fvm.prank(strangerFork());
        uint256 gross = k.core_.confiscate(gauge);
        assertEq(gross, FEE, "fork: full remainder seized");
        assertEq(IErc20Venue(CRVUSD).balanceOf(FEEDIST) - fdBefore, gross - gross / 2, "fork: real FD got F");
        uint256 repBefore = IErc20Venue(CRVUSD).balanceOf(beneficiary);
        (uint256 stake, uint256 reward) = k.b.claim(id);
        assertEq(stake, STAKE, "fork: bond refunded");
        assertEq(reward, gross / 2, "fork: funded half paid once");
        assertEq(IErc20Venue(CRVUSD).balanceOf(beneficiary) - repBefore, STAKE + gross / 2, "fork: fixed recipient");
    }

    function _newVoteFork(bytes memory script) internal returns (uint256) {
        return IVotingNewFork(THIN_VOTING_APP).newVote(script, "", false, false);
    }

    function _assertMismatchedForkBallot(Kit memory k, address gauge, address beneficiary, address sponsor) internal {
        bytes32 eh = keccak256(abi.encode("f01r-mismatch"));
        bytes32 reportId = _forkReportId(k, gauge, beneficiary, 1002, eh);
        bytes memory badScript =
            BountyScripts.buildKillScript(THIN_AGENT, address(k.b), THIN_KILL_PROXY, gauge, reportId, sponsor);
        uint256 last = _votingR().lastCreateVoteTimes(sponsor);
        if (block.timestamp < last + COOLDOWN) fvm.warp(last + COOLDOWN);
        fvm.prank(sponsor);
        uint256 proposalId = _newVoteFork(badScript);
        uint256 balance = IErc20Venue(CRVUSD).balanceOf(address(k.b));
        fvm.prank(beneficiary);
        vm.expectRevert(IGaugeBounty.BadVote.selector);
        k.b.submit(gauge, proposalId, eh, 1002);
        assertEq(IErc20Venue(CRVUSD).balanceOf(address(k.b)), balance, "fork: mismatch retains nothing");
    }

    function _assertCanonicalForkBallot(
        Kit memory k,
        address gauge,
        address beneficiary,
        bytes32 id,
        uint256 proposalId
    ) internal view returns (uint256 startDate) {
        (bool open, bool executed, uint256 start, uint256 snapshotBlock,,,,,, bytes memory script) =
            _votingR().getVote(proposalId);
        executed;
        snapshotBlock;
        assertTrue(open, "fork: ballot open at admission");
        bytes memory canonical =
            BountyScripts.buildKillScript(THIN_AGENT, address(k.b), THIN_KILL_PROXY, gauge, id, beneficiary);
        assertEq(keccak256(script), keccak256(canonical), "fork: recorded script is the canonical bytes");
        return start;
    }

    function _votingOpenR(uint256 proposalId) internal view returns (bool open) {
        (open,,,,,,,,,) = _votingR().getVote(proposalId);
    }

    function _castYesR(uint256 proposalId) internal {
        address[] memory voters = forkVoters();
        require(voters.length > 0, "fork fixture blocked: no discovered voting set");
        (,,, uint256 snapBlock,,,,,,) = _votingR().getVote(proposalId);
        uint256 accumulated;
        for (uint256 i = 0; i < voters.length; ++i) {
            uint256 pw = IVeSnapR(THIN_VE_CRV).balanceOfAt(voters[i], snapBlock);
            assertTrue(pw > 0, "fork: voter has real veCRV at the snapshot");
            fvm.prank(voters[i]);
            IVotingExecR(THIN_VOTING_APP).vote(proposalId, true, false);
            accumulated += pw;
        }
        assertTrue(accumulated >= QUORUM_POWER_MIN, "fork: YES clears the acceptance quorum");
    }

    // --------------------------------- F02: independent beneficiary ballots

    function test_Fork_Rework_IndependentReporterProposals() public {
        _freshFork();
        Kit memory k = _deployThinKit();
        address g = _listPrimary(k);
        address repA = reporter_();
        address repB = secondReporter_();
        address sponsor = forkBallotCreator();
        _fundReporter(k, repA, 1);
        _fundReporter(k, repB, 1);

        // Both beneficiary-bound reports use the disclosed sponsor where
        // needed; upstream proposal rights remain per-creator and do not
        // become a bounty capacity or admission gate.
        (bytes32 idA,) = _submitForkBallot(k, g, repA, 2001, keccak256(abi.encode("f02r-a")));
        (bytes32 idB, uint256 pidB) = _submitForkBallotBy(k, g, repB, sponsor, 2002, keccak256(abi.encode("f02r-b")));
        assertTrue(idA != idB, "fork: distinct reports coexist");
        assertEq(IErc20Venue(CRVUSD).balanceOf(address(k.b)), 2 * STAKE, "fork: two exact bonds");
        (uint256 heldA,,) = k.b.accounting();
        assertEq(heldA, 2 * STAKE, "fork: both liabilities held");
        // A creator's upstream state (lastCreateVoteTimes moved by B's own
        // creation) never gated A's admission: A was admitted in the same
        // frame with a different creator and never waits on a shared slot.
        assertEq(uint8(k.b.getReport(idA).phase), uint8(Phase.Proposed), "fork: A proposed");
        assertEq(uint8(k.b.getReport(idB).phase), uint8(Phase.Proposed), "fork: B proposed");
        // Re-citing one bound ballot is not a new claim.
        fvm.prank(repA);
        vm.expectRevert(IGaugeBounty.DuplicateProposal.selector);
        k.b.submit(g, pidB, keccak256(abi.encode("f02r-b-again")), 2003);

        // B executes first and wins; A's later execution closes as the
        // loser without touching the latch; both bonds refund.
        // Both ballots are voted while open. B is executed first at its later
        // boundary; A's already-approved ballot is then executed late.
        _castYesR(k.b.getReport(idA).proposalId);
        _castYesR(pidB);
        fvm.warp(k.b.getReport(idB).voteEnd);
        fvm.prank(strangerFork());
        IVotingExecR(THIN_VOTING_APP).executeVote(pidB);
        assertEq(uint8(k.b.getReport(idB).phase), uint8(Phase.Recognized), "fork: B wins");
        (bytes32 latched,,) = k.b.rewardTerms(g);
        assertEq(latched, idB, "fork: latch names B");
        (uint256 stakeB,) = k.b.claim(idB);
        assertEq(stakeB, STAKE, "fork: winner stake refundable at recognition");

        // A's approved ballot executes late: kill already true — A closes
        // NoAward, its bond refunds, and the winner's identity stands.
        fvm.prank(strangerFork());
        IVotingExecR(THIN_VOTING_APP).executeVote(k.b.getReport(idA).proposalId);
        assertEq(uint8(k.b.getReport(idA).phase), uint8(Phase.NoAward), "fork: loser closed by its own attempt");
        (uint256 stakeA,) = k.b.claim(idA);
        assertEq(stakeA, STAKE, "fork: loser bond refunds once");
        (uint256 heldEnd,,) = k.b.accounting();
        assertEq(heldEnd, 0, "fork: bonds discharged");

        _settleForkWinner(k, g, repA, repB, idA, idB);
    }

    function _settleForkWinner(Kit memory k, address g, address repA, address repB, bytes32 idA, bytes32 idB) internal {
        // Real settlement pays the single winner exactly one funded half.
        uint256 repBBefore = IErc20Venue(CRVUSD).balanceOf(repB);
        fvm.prank(strangerFork());
        uint256 gross = k.core_.confiscate(g);
        require(gross == FEE, "fork: fee escrow seized");
        (, uint256 rewB) = k.b.claim(idB);
        assertEq(rewB, gross / 2, "fork: one real allocation, to B");
        assertEq(IErc20Venue(CRVUSD).balanceOf(repB) - repBBefore, gross / 2, "fork: exact recipient");
        // A late third submission for the latched listing is refused even
        // though the gauge is killed and the escrow gone (IneligibleGauge).
        fvm.prank(repA);
        vm.expectRevert();
        k.b.submit(g, 0, keccak256("late"), 2004);
    }

    /// @dev Variant where the creator differs from the submitting
    /// beneficiary (explicit sponsorship through the real app).
    function _submitForkBallotBy(
        Kit memory k,
        address gauge,
        address beneficiary,
        address creator,
        uint256 nonce,
        bytes32 eh
    ) internal returns (bytes32 reportId, uint256 proposalId) {
        reportId = _forkReportId(k, gauge, beneficiary, nonce, eh);
        bytes memory script =
            BountyScripts.buildKillScript(THIN_AGENT, address(k.b), THIN_KILL_PROXY, gauge, reportId, beneficiary);
        uint256 last = _votingR().lastCreateVoteTimes(creator);
        if (last != 0 && block.timestamp < last + COOLDOWN) fvm.warp(last + COOLDOWN);
        fvm.prank(creator);
        proposalId = IVotingNewFork(THIN_VOTING_APP).newVote(script, "", false, false);
        fvm.prank(beneficiary);
        bytes32 id = k.b.submit(gauge, proposalId, eh, nonce);
        require(id == reportId, "fork: sponsor-bound id matches");
    }

    function strangerFork() internal pure returns (address) {
        return address(uint160(uint256(keccak256(bytes("bountyrework-fork-stranger")))));
    }

    function secondReporter_() internal pure returns (address) {
        return address(uint160(uint256(keccak256(bytes("bountyrework-fork-second")))));
    }
}
