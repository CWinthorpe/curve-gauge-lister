// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BountyFixture} from "../BountyFixture.sol";
import {Vm} from "../../TestBase.sol";
import {GaugeBounty} from "../../../contracts/GaugeBounty.sol";
import {CurveGaugeListerV2} from "../../../contracts/CurveGaugeListerV2.sol";
import {IGaugeBounty} from "../../../contracts/interfaces/IGaugeBounty.sol";
import {IERC20Minimal} from "../../../contracts/interfaces/IERC20Minimal.sol";
import {ReportView, Phase, StakeState} from "../../../contracts/bounty/BountyTypes.sol";
import {BountyScripts} from "../../../contracts/libraries/BountyScripts.sol";
import {GovernanceGauge} from "../mocks/MockBountyGovernance.sol";

/// @notice Rework direct-admission and race suite (plans/BOUNTY-REWORK-PLAN.md
/// §7/§8): six migrated Queue identities (direct stake/domain, concurrent
/// admission + terminal refusal, vote-zero independent admission, atomic
/// submit-and-bind, original vote clocks, continued drips/kill/exhaustion)
/// plus the six new beneficiary-bound witnesses RW-C/RW-H/RW-P/RW-R/RW-W/
/// RW-S. Ballots are REAL: the canonical three-action script is created
/// on-chain by the actual creator (who may be a sponsor distinct from the
/// submitting beneficiary); there is no protocol queue and no creator
/// authentication anywhere.
contract ReworkReportTest is BountyFixture {
    /// @dev Independent recomputation of the reporter-bound identity (§3.1).
    bytes32 internal constant DOMAIN = keccak256(bytes("CurveGaugeBounty.report.reporter.v1"));

    uint256 internal _nonce;
    address internal _mega;
    CurveGaugeListerV2 internal core_;
    GaugeBounty internal b;

    function setUp() public {
        setupBountyWorld();
        (core_, b) = deployBoundPair();
    }

    // ---------------------------------------------------------------- glue

    function _list() internal returns (address) {
        (, address g,) = listBountyEligible(core_);
        return g;
    }

    /// @dev Real admission path: create the beneficiary-bound ballot (self-
    /// created unless a sponsor is supplied), fund the exact stake, submit.
    function _submitBound(address g, address who) internal returns (bytes32 id, uint256 proposalId) {
        _nonce += 1;
        bytes32 eh = keccak256(abi.encode("rework", g, who, _nonce));
        return submitBeneficiaryBallot(b, address(core_), g, who, _nonce, eh);
    }

    function _fundMega() internal {
        if (_mega == address(0)) {
            _mega = address(uint160(0x6FA1CE01));
            giveVePower(_mega, 5_000_000e18);
        }
    }

    function _newVoteAfterCooldown(address creator, bytes memory script) internal returns (uint256 proposalId) {
        ensureVePower(creator);
        uint256 last = voting.lastCreateVoteTimes(creator);
        if (last != 0 && block.timestamp < last + COOLDOWN) vm.warp(last + COOLDOWN);
        vm.prank(creator);
        return voting.newVote(script, "", false, false);
    }

    /// @dev Permissionless canonical execution: one dominant YES voter makes
    /// the strict support/quorum floors pass, the ballot closes, and a
    /// stranger executes.
    function _passAndExecute(uint256 proposalId) internal {
        _fundMega();
        vm.prank(_mega);
        voting.vote(proposalId, true);
        vm.warp(block.timestamp + VOTE_TIME + 1);
        vm.prank(stranger);
        voting.executeVote(proposalId);
    }

    function _votePairAndExecuteFirst(uint256 first, uint256 second) internal {
        _fundMega();
        vm.prank(_mega);
        voting.vote(first, true);
        vm.prank(_mega);
        voting.vote(second, true);
        vm.warp(block.timestamp + VOTE_TIME + 1);
        vm.prank(stranger);
        voting.executeVote(first);
    }

    function _phase(bytes32 id) internal view returns (uint8) {
        return uint8(b.getReport(id).phase);
    }

    function _held() internal view returns (uint256 h) {
        (h,,) = b.accounting();
    }

    function _credits() internal view returns (uint256 c) {
        (, c,) = b.accounting();
    }

    function _spaceFdCursor() internal {
        if (block.timestamp <= fd.last_token_time() + 86_400) {
            fd.setLastTokenTime(block.timestamp - 86_401);
        }
    }

    /// @dev Authorized seizure via one of the two permissionless entrypoints
    /// after the current flag is true (no prefunded bounty reward to fake
    /// funding: the pull is the real V2 escrow remainder).
    function _seizeVia(address gauge, bool viaCheckpoint) internal {
        _spaceFdCursor();
        vm.prank(stranger);
        if (viaCheckpoint) {
            core_.checkpoint(gauge);
        } else {
            core_.confiscate(gauge);
        }
    }

    // ============================================ migrated Queue identities

    /// @dev Migrated from test_Thin_DirectStakeAndReportIdentity.
    function test_Rework_DirectStakeAndPrecomputableIdentity() public {
        address g = _list();
        bytes32 eh = keccak256(abi.encode("q1", g));
        uint256 nonce = 7;

        // Larger-than-requested approval: the pull is STILL exactly 1,000 and
        // the surplus allowance survives (no caller-denomination retention).
        crvUSD.mint(reporter, 5 * STAKE);
        approveCrvUsd(reporter, address(b), 5 * STAKE);
        uint256 repBefore = crvUSD.balanceOf(reporter);

        // A reporter knows the entire domain BEFORE the ballot exists:
        bytes32 preId = computeReportId(b, address(core_), g, reporter, nonce, eh);
        (, uint256 pid) = createBeneficiaryBallot(b, address(core_), g, reporter, reporter, nonce, eh);
        // proposalId is NOT in the reportId preimage: no future-ID
        // prediction and no circular hash.
        bytes32 lid = core_.listingId(g);
        bytes32 expect =
            keccak256(abi.encode(DOMAIN, uint256(1), address(b), address(core_), g, lid, reporter, nonce, eh));
        assertEq(preId, expect, "domain-bound identity");

        vm.prank(reporter);
        bytes32 id = b.submit(g, pid, eh, nonce);
        assertEq(id, expect, "submitted id equals the precomputed id");
        assertEq(repBefore - crvUSD.balanceOf(reporter), STAKE, "exact 1000 pull");
        assertEq(crvUSD.balanceOf(address(b)), STAKE, "bounty custody exact");
        assertEq(crvUSD.allowance(reporter, address(b)), 4 * STAKE, "surplus allowance not burned");

        // One accepted report, immediately Proposed+Bonded; the immutable
        // recipient IS the submitter; the ballot binding is stored.
        ReportView memory rv = b.getReport(id);
        assertEq(rv.reporter, reporter, "immutable recipient is the submitter");
        assertEq(rv.evidenceHash, eh, "evidence recorded");
        assertEq(rv.proposalId, pid, "actual proposal id stored immutably");
        assertEq(uint8(Phase.Proposed), rv.phase, "Proposed on admission");
        assertEq(uint8(StakeState.Bonded), rv.stakeState, "Bonded on admission");

        // Zero evidence: reverted before any pull; nothing retained.
        address g2 = _list();
        uint256 bal0 = crvUSD.balanceOf(address(b));
        vm.prank(secondReporter);
        vm.expectRevert(IGaugeBounty.BadEvidence.selector);
        b.submit(g2, pid, bytes32(0), 1234);
        assertEq(crvUSD.balanceOf(address(b)), bal0, "bad evidence retains nothing");

        // No beneficiary/creator/app endpoint exists anywhere: the paid
        // recipient is only ever the stored submitter.
        (bool sponsorOk,) = address(b).call(abi.encodeWithSignature("setBeneficiary(bytes32,address)", id, stranger));
        assertFalse(sponsorOk, "no beneficiary endpoint");
        (bool setRec,) = address(b).call(abi.encodeWithSignature("setRecipient(bytes32,address)", id, stranger));
        assertFalse(setRec, "no recipient setter");
    }

    /// @dev Migrated from test_Thin_SingleActiveReport: the active-slot
    /// admission lock is replaced by permanent concurrent reports and a
    /// first-qualifying-recognition latch with terminal refusal after.
    function test_Rework_ConcurrentAdmissionAndTerminalRefusal() public {
        address g = _list();

        // Two distinct beneficiary-bound ballots for the SAME gauge coexist:
        // submission order is not entitlement and there is no cap/queue.
        (bytes32 idA, uint256 pidA) = _submitBound(g, reporter);
        (bytes32 idB, uint256 pidB) = _submitBound(g, secondReporter);
        assertTrue(idA != idB && pidA != pidB, "distinct reports coexist");
        assertEq(crvUSD.balanceOf(address(b)), 2 * STAKE, "two exact bonds");
        assertEq(_held(), 2 * STAKE, "heldStakes counts both");

        // Repeated references to ONE ballot are not new claims.
        fundStake(b, reporter);
        vm.prank(reporter);
        vm.expectRevert(IGaugeBounty.DuplicateProposal.selector);
        b.submit(g, pidA, keccak256("again"), 99);
        // Replaying an existing report identity is refused forever.
        bytes32 ehA = b.getReport(idA).evidenceHash;
        uint256 nonceA = _nonce; // _submitBound consumed the latest nonce
        vm.prank(reporter);
        vm.expectRevert(IGaugeBounty.DuplicateProposal.selector);
        b.submit(g, pidA, ehA, nonceA);

        // First qualifying flag-true recognition stands. B was never
        // executed: it simply stays Proposed (a pending submission is not
        // an entitlement candidate).
        _votePairAndExecuteFirst(pidA, pidB);
        assertEq(uint8(Phase.Recognized), _phase(idA), "A recognized");
        assertEq(uint8(Phase.Proposed), _phase(idB), "unexecuted B is not an entitlement");

        // A NEW ballot for the same listing is refused forever, even after
        // an authorized unkill: the latch is load-bearing, not merely
        // hidden behind the pre-killed guard.
        unkillGaugeViaRoute(g);
        vm.prank(stranger);
        vm.expectRevert(IGaugeBounty.IneligibleGauge.selector);
        b.submit(g, 0, keccak256("late"), 123);

        // B may still complete its own protective kill; its callbacks cannot
        // revive it or touch the winner.
        vm.prank(stranger);
        voting.executeVote(pidB);
        assertEq(uint8(Phase.NoAward), _phase(idB), "loser closed by its own attempt");
        assertTrue(GovernanceGauge(g).is_killed(), "loser's protective kill still landed");
        vm.prank(address(agent));
        b.creditBallot(idB, secondReporter);
        assertEq(uint8(Phase.NoAward), _phase(idB), "repeat callbacks are inert");
        (bytes32 latched,,) = b.rewardTerms(g);
        assertEq(latched, idA, "winner latch intact through the loser execution");
    }

    /// @dev Migrated from test_Thin_CooldownBoundaryAndVoteZero: proposal id
    /// zero is legal, existence is the stored reporter, and one creator's
    /// upstream cooldown never consumes another reporter's admission.
    function test_Rework_VoteZeroAndIndependentAdmission() public {
        address g = _list();

        // First-ever ballot in this world is proposal id zero, submitted by
        // its beneficiary with nonce zero.
        bytes32 eh = keccak256(abi.encode("zero", g));
        (bytes32 id0, uint256 pid0) = submitBeneficiaryBallot(b, address(core_), g, reporter, 0, eh);
        assertEq(pid0, 0, "vote id zero is a legal binding");
        assertEq(b.getReport(id0).proposalId, 0, "stored proposal id zero");
        assertEq(b.getReport(id0).reporter, reporter, "nonzero reporter establishes existence");

        // Nonexistent id (>= votesLength) fails closed before custody.
        uint256 absentProposal = voting.votesLength() + 5;
        vm.prank(reporter);
        vm.expectRevert(IGaugeBounty.BadVote.selector);
        b.submit(g, absentProposal, keccak256("nope"), 55);

        // Upstream per-CREATOR proposal rights/cooldowns remain (fixture
        // enforces them), but they are the creator's problem only: while
        // _mega must wait out its cooldown between creations, an unrelated
        // creator/beneficiary pair is admitted immediately and independently.
        _fundMega();
        address g2 = _list();
        (bytes32 id2,) = submitBeneficiaryBallotBy(b, address(core_), g2, secondReporter, _mega, 31, keccak256("c2"));
        assertEq(_phase(id2), uint8(Phase.Proposed), "independent admission");
        address third = actor("thirdReporter");
        (bytes32 id3,) = _submitBound(g, third);
        assertEq(_phase(id3), uint8(Phase.Proposed), "no shared capacity exists");
        // _mega is now cooling down; another beneficiary with another creator
        // is admitted during that window anyway.
        address g4 = _list();
        (bytes32 id4,) = submitBeneficiaryBallotBy(b, address(core_), g4, third, stranger, 41, keccak256("c4"));
        assertEq(_phase(id4), uint8(Phase.Proposed), "creator cooldown bounds nothing here");
    }

    /// @dev Migrated from test_Thin_AtomicCreateAndBind: all effects and the
    /// exact pull are ONE reverting transaction; a failed custody step
    /// consumes nothing, including the permanent id reservations.
    function test_Rework_AtomicSubmitAndBind() public {
        address g = _list();
        bytes32 eh = keccak256(abi.encode("atomic", g));
        uint256 nonce = 9;
        (bytes32 reportId, uint256 pid) = createBeneficiaryBallot(b, address(core_), g, reporter, reporter, nonce, eh);

        // Without the stake: full revert, nothing retained anywhere.
        uint256 held0 = _held();
        vm.prank(reporter);
        vm.expectRevert(); // SafeToken failure on an unapproved/empty pull
        b.submit(g, pid, eh, nonce);
        assertEq(crvUSD.balanceOf(address(b)), 0, "no custody on failure");
        assertEq(b.getReport(reportId).reporter, address(0), "no report on failure");
        assertEq(_held(), held0, "no liability on failure");

        // The same proposal/domain re-admits cleanly: nothing partial
        // survived the failed attempt.
        fundStake(b, reporter);
        vm.prank(reporter);
        bytes32 id = b.submit(g, pid, eh, nonce);
        assertEq(id, reportId, "retry under the exact identity");
        assertEq(_held(), STAKE, "liability posted once");

        // A foreign-gauge reference to the same stored script fails closed
        // before custody.
        address g2 = _list();
        vm.prank(secondReporter);
        vm.expectRevert(IGaugeBounty.DuplicateProposal.selector);
        b.submit(g2, pid, eh, 10);
        assertEq(crvUSD.balanceOf(address(b)), STAKE, "no extra bond");

        // Wrong chain fails before anything else.
        vm.chainId(5);
        vm.prank(reporter);
        vm.expectRevert(IGaugeBounty.WrongChain.selector);
        b.submit(g, pid, eh, 11);
        vm.chainId(1);
    }

    /// @dev Migrated from test_Thin_ActualCreationTimes: the ORIGINAL ballot
    /// clock is bound at admission and never reset to submit time.
    function test_Rework_OriginalVoteClockNeverResets() public {
        address g = _list();
        bytes32 eh = keccak256(abi.encode("clock", g));
        uint256 nonce = 21;
        (bytes32 reportId, uint256 pid) = createBeneficiaryBallot(b, address(core_), g, reporter, reporter, nonce, eh);
        (, bool createdOpen, uint256 startDate,,,,,,,) = voting.getVote(pid);
        createdOpen;

        // Delay the SUBMISSION by 3 days: the vote clock stays original.
        vm.warp(block.timestamp + 3 days);
        fundStake(b, reporter);
        vm.prank(reporter);
        bytes32 id = b.submit(g, pid, eh, nonce);
        assertEq(id, reportId, "identity unaffected by submission time");

        ReportView memory rv = b.getReport(id);
        assertEq(rv.voteEnd, startDate + VOTE_TIME, "voteEnd == actual start + ballot");
        assertEq(rv.executeBy, startDate + 2 * VOTE_TIME, "executeBy == start + 14d");
        assertTrue(rv.voteEnd < block.timestamp + VOTE_TIME, "clock NOT rebased to submit");
        assertEq(uint8(Phase.Proposed), rv.phase, "still Proposed");

        // Timely execution inside the original window still qualifies; the
        // unexecuted ballot that merely FAILED closes as Rejected with a
        // refundable bond (validated rejection), never a slash.
        _passAndExecute(pid);
        assertEq(uint8(Phase.Recognized), _phase(id), "recognized on original clocks");

        // Late upstream execution beyond executeBy: the ballot can still
        // land its protective kill, but the expired offer earns nothing.
        address g2 = _list();
        (bytes32 id2, uint256 pid2) = _submitBound(g2, reporter);
        _fundMega();
        vm.prank(_mega);
        voting.vote(pid2, true);
        vm.warp(b.getReport(id2).executeBy + 1);
        assertTrue(b.resolve(id2), "expiry is a close, not a defer");
        assertEq(uint8(Phase.Expired), _phase(id2), "local expiry at executeBy+1");
        vm.prank(stranger);
        voting.executeVote(pid2); // late stale-ballot execution still kills
        assertTrue(GovernanceGauge(g2).is_killed(), "protective kill survives expiry");
        assertEq(uint8(Phase.Expired), _phase(id2), "expired offer earns nothing");
    }

    /// @dev Migrated from test_Thin_DripKillAndExhaustionWhilePending: an
    /// unrelated/emergency kill and a drained (confiscated) listing while a
    /// report is Proposed are positively observed, closed NoAward, and
    /// refunded locally.
    function test_Rework_DripKillAndExhaustionWhileProposed() public {
        // Emergency/unrelated kill before recognition: positively observed
        // prekill closes the offer with refund, never a slash.
        address g = _list();
        (bytes32 id, uint256 pid) = _submitBound(g, reporter);
        pid;
        killGaugeViaRoute(g);
        assertTrue(b.resolve(id), "resolve observes the prekill");
        assertEq(uint8(Phase.NoAward), _phase(id), "NoAward");
        vm.prank(stranger);
        (uint256 s,) = b.claim(id);
        assertEq(s, STAKE, "bond refunded by a permissionless claim");

        // Exhaustion while Proposed: the escrow is confiscated to terminal
        // (no matching allocation) while a fresh report is open.
        address g2 = _list();
        (bytes32 id2, uint256 pid2) = _submitBound(g2, reporter);
        pid2;
        killGaugeViaRoute(g2);
        _seizeVia(g2, false);
        assertTrue(b.resolve(id2), "resolve observes terminal/exhausted listing");
        assertEq(uint8(Phase.NoAward), _phase(id2), "NoAward on exhaustion");
        vm.prank(stranger);
        (uint256 s2,) = b.claim(id2);
        assertEq(s2, STAKE, "exhaustion refund route pays once");
    }

    // ==================================================== new rework witnesses

    /// @dev RW-C (plans/BOUNTY-REWORK-PLAN.md §8): the explicit beneficiary
    /// word inside the canonical script is the SOLE admission guard between
    /// two otherwise-identical ballots. A ballot storing S(rA,B,g) — both
    /// callback ids rA, the gauge, wrappers, clocks and every other byte
    /// correct, ONLY the creditBallot beneficiary word differing from A —
    /// must be refused for A with BadVote and zero token/report/map effects.
    /// The separate S(rA,A,g) control succeeds even though the actual
    /// creator is a sponsor C != A (that is sponsorship, not proof).
    function _sponsoredControl(address sponsor, address gauge) internal returns (bytes32 id, uint256 pid) {
        return submitBeneficiaryBallotBy(b, address(core_), gauge, reporter, sponsor, 4002, keccak256("rw-c-control"));
    }

    function _walletBeneficiaryControl(address gauge, address sponsor, BeneficiaryWallet wallet, address walletOwner)
        internal
    {
        bytes32 eh = keccak256(abi.encode("rw-c-wallet", gauge));
        uint256 nonce = 4003;
        bytes32 id = computeReportId(b, address(core_), gauge, address(wallet), nonce, eh);
        bytes memory script =
            BountyScripts.buildKillScript(address(agent), address(b), address(killProxy), gauge, id, address(wallet));
        uint256 pid = _newVoteAfterCooldown(sponsor, script);
        crvUSD.mint(address(wallet), STAKE);
        wallet.approveStake(address(crvUSD), address(b), STAKE);
        vm.prank(walletOwner);
        vm.expectRevert(IGaugeBounty.BadVote.selector);
        b.submit(gauge, pid, eh, nonce);
        wallet.submit(gauge, pid, eh, nonce);
        assertEq(b.getReport(id).reporter, address(wallet), "wallet is the fixed recipient");
    }

    function _mismatchAndSponsor(address sponsor, address gauge, BeneficiaryWallet wallet)
        internal
        returns (bytes32 idA, uint256 pidA, uint256 reporterBalance)
    {
        bytes32 eh = keccak256(abi.encode("rw-c-mismatch", gauge));
        uint256 nonce = 4001;
        bytes32 id = computeReportId(b, address(core_), gauge, reporter, nonce, eh);
        bytes memory badScript =
            BountyScripts.buildKillScript(address(agent), address(b), address(killProxy), gauge, id, address(wallet));
        uint256 pid = _newVoteAfterCooldown(sponsor, badScript);
        fundStake(b, reporter);
        reporterBalance = crvUSD.balanceOf(reporter);
        uint256 bountyBalance = crvUSD.balanceOf(address(b));
        uint256 held = _held();
        // bountyreworkfix C1: the required rejection is NAMED and BOUND to
        // the real mismatched submission (helper keeps the stack shallow).
        _refuseMismatchedSubmit(gauge, pid, eh, nonce);
        assertEq(crvUSD.balanceOf(reporter), reporterBalance, "no stake taken on mismatch");
        assertEq(crvUSD.balanceOf(address(b)), bountyBalance, "no custody on mismatch");
        assertEq(_held(), held, "no liability on mismatch");
        assertEq(b.getReport(id).reporter, address(0), "no report registered on mismatch");
        vm.prank(address(wallet));
        vm.expectRevert(IGaugeBounty.BadVote.selector);
        b.submit(gauge, pid, eh, nonce);
        (idA, pidA) = _sponsoredControl(sponsor, gauge);
        assertEq(_phase(idA), uint8(Phase.Proposed), "sponsor-created, beneficiary-admitted");
    }

    /// @dev The NAMED beneficiary-mismatch rejection probe (separated to
    /// keep the enclosing witness' stack shallow).
    function _refuseMismatchedSubmit(address gauge, uint256 pid, bytes32 eh, uint256 nonce) private {
        vm.prank(reporter);
        (bool mismatchAccepted, bytes memory mismatchRet) =
            address(b).call(abi.encodeCall(b.submit, (gauge, pid, eh, nonce)));
        assertFalse(
            mismatchAccepted, "BENEFICIARY_MISMATCH_ACCEPTED: submit of the beneficiary-mismatched ballot is refused"
        );
        bytesEq(
            mismatchRet,
            abi.encodeWithSelector(IGaugeBounty.BadVote.selector),
            "BENEFICIARY_MISMATCH_ACCEPTED: the refusal selector is BadVote"
        );
    }

    function test_Rework_BeneficiaryMismatchIsSoleGuard() public {
        address sponsor = actor("sponsorC");
        address walletOwner = actor("walletOwner");
        BeneficiaryWallet wallet = new BeneficiaryWallet(b);
        address g = _list();

        (bytes32 idA, uint256 pidA, uint256 aBal0) = _mismatchAndSponsor(sponsor, g, wallet);

        // (c) Contract-wallet beneficiary: the OWNER EOA is not
        // interchangeable — the wallet itself must submit its own ballot.
        address g2 = _list();
        _walletBeneficiaryControl(g2, sponsor, wallet, walletOwner);

        // (d) Unrelated ballot refused for A; permissionless execution and
        // fixed-recipient claim: a stranger executes A's passed ballot and
        // only A (the stored reporter) is paid.
        address g3 = _list();
        (, uint256 pidForeign) =
            createBeneficiaryBallot(b, address(core_), g3, stranger, stranger, 4004, keccak256("foreign"));
        fundStake(b, reporter);
        vm.prank(reporter);
        vm.expectRevert(IGaugeBounty.BadVote.selector);
        b.submit(g3, pidForeign, keccak256("whatever"), 4005);

        _passAndExecute(pidA);
        assertEq(uint8(Phase.Recognized), _phase(idA), "winner via permissionless execution");
        vm.prank(stranger);
        (uint256 s,) = b.claim(idA);
        assertEq(s, STAKE, "fixed recipient: only A is paid");
        assertEq(crvUSD.balanceOf(reporter), aBal0 + 2 * STAKE, "A net-zero after refund");
    }

    /// @dev RW-H: same beneficiary, two eligible gauges — the script must
    /// name the RIGHT gauge in the middle kill; wrong-target under the
    /// intended reportId is a whole-hash failure before any stake. Retains
    /// target/value/order/extra/trailing/domain classes.
    function test_Rework_WrongGaugeIsSoleHashGuard() public {
        address g1 = _list();
        address g2 = _list();

        // r1 is A's exact precomputed id for g1; build S(r1, A, g2): both
        // callbacks keep the intended reportId, the explicit beneficiary is
        // correct, only the KILLED gauge differs.
        bytes32 eh = keccak256(abi.encode("rw-h", g1));
        uint256 nonce = 5001;
        bytes32 r1 = computeReportId(b, address(core_), g1, reporter, nonce, eh);
        bytes memory wrongGauge =
            BountyScripts.buildKillScript(address(agent), address(b), address(killProxy), g2, r1, reporter);
        fundStake(b, reporter);
        uint256 pidWrong = _newVoteAfterCooldown(reporter, wrongGauge);
        uint256 bal0 = crvUSD.balanceOf(address(b));
        vm.prank(reporter);
        vm.expectRevert(IGaugeBounty.BadVote.selector);
        b.submit(g1, pidWrong, eh, nonce);
        assertEq(crvUSD.balanceOf(address(b)), bal0, "wrong-gauge refuses before stake");

        // Correct gauge under its own domain succeeds.
        (bytes32 id2,) = _submitBound(g2, reporter);
        assertEq(_phase(id2), uint8(Phase.Proposed), "correct-gauge admitted");

        // Tampering classes on the honest canonical script (record created,
        // then submitted under the intended id): reordered actions, a
        // trailing extra byte, one flipped payload byte and a foreign
        // bounty target are ALL BadVote before custody.
        bytes memory honest = canonicalKillScript(b, g1, r1, reporter);
        bytes[] memory tampered = new bytes[](4);
        tampered[0] = _orderSwap(honest);
        tampered[1] = _trailing(honest);
        tampered[2] = _flipByte(honest, 40); // inside the first Agent payload
        tampered[3] = BountyScripts.buildKillScript(
            address(agent), address(uint160(0xB00B)), address(killProxy), g1, r1, reporter
        );
        for (uint8 i = 0; i < tampered.length; ++i) {
            uint256 lastLen = voting.votesLength();
            uint256 pt = _newVoteAfterCooldown(reporter, tampered[i]);
            vm.prank(reporter);
            vm.expectRevert(IGaugeBounty.BadVote.selector);
            b.submit(g1, pt, eh, nonce); // same intended domain, tampered script
            assertEq(voting.votesLength(), lastLen + 1, "record exists but never admitted");
        }
        assertEq(crvUSD.balanceOf(address(b)), bal0 + STAKE, "only the honest admission ever bonded");
    }

    function _orderSwap(bytes memory s) internal pure returns (bytes memory) {
        // Keep the credit entry; swap the kill and recognize entries.
        uint256 l1 = 24 + 228;
        uint256 l23 = 24 + 196;
        bytes memory out = bytes.concat(_gslice(s, 0, 4 + l1), _gslice(s, 4 + l1 + l23, l23), _gslice(s, 4 + l1, l23));
        return out;
    }

    /// @dev Ordinary memory copy of one complete block of a script.
    function _gslice(bytes memory s, uint256 start, uint256 n) private pure returns (bytes memory out) {
        require(start + n <= s.length, "rework: slice out of bounds");
        out = new bytes(n);
        for (uint256 i = 0; i < n; ++i) {
            out[i] = s[start + i];
        }
    }

    function _trailing(bytes memory s) internal pure returns (bytes memory) {
        return bytes.concat(s, hex"00");
    }

    function _flipByte(bytes memory s, uint256 at) internal pure returns (bytes memory) {
        bytes memory t = new bytes(s.length);
        for (uint256 i = 0; i < s.length; ++i) {
            t[i] = i == at ? bytes1(uint8(s[i]) ^ 0x01) : s[i];
        }
        return t;
    }

    /// @dev bountyreworkconf2 C1 / F13 remainder: the distinct-report-ID
    /// control AT THE ADMISSION SITE. A funded, approved A presents an
    /// otherwise-valid, UNBOUND ballot whose canonical script belongs to a
    /// DIFFERENT report domain: same reporter A, same gauge, same evidence,
    /// only the nonce differs (rA = id(g,A,nonceA,eh) != rB =
    /// id(g,A,nonceB,eh)), the ballot being genuinely created for rB through
    /// the real creator route. The submit of that rB ballot under the rA
    /// domain is refused BadVote at the step-5 admission comparison — before
    /// any pull, and before callback/stored-report guards. Under the
    /// beneficiary-word-only RW-C2 mutation this stays green: the mutant
    /// relaxes only the expected script's beneficiary word; the reportId
    /// words still differ and the live whole-script equality refuses. The
    /// honest-domain positive follows (the SAME ballot admitted under
    /// (nonceB, eh)): the refusal is bound to the report-ID comparison, not
    /// to an unrelated ballot invalidity, a callback guard or the
    /// duplicate-reservation step (both reservations are empty when the
    /// refused submit runs). Call shape mirrors the accepted wrong-gauge
    /// control above, with a low-level named probe like the
    /// beneficiary-mismatch witness binding the refusal to that submit call.
    function test_Rework_DistinctReportIdRejectedAtAdmission() public {
        address g = _list();
        bytes32 eh = keccak256(abi.encode("rw-f13-domain", g));

        // Real ballot for the rB domain, created on-chain by the actual
        // creator route (no fixture re-point): stored script S(rB, A, g).
        uint256 nonceB = 6102;
        (bytes32 rB, uint256 pidB) = createBeneficiaryBallot(b, address(core_), g, reporter, reporter, nonceB, eh);

        // The distinct domain it is presented under: same evidence, only the
        // nonce differs, so the derived reportId words differ.
        uint256 nonceA = 6101;
        bytes32 rA = computeReportId(b, address(core_), g, reporter, nonceA, eh);
        assertTrue(rA != rB && rA != bytes32(0), "distinct reportId words for the same reporter/gauge");

        // Funded and approved: if admission relaxed, the pull WOULD happen —
        // so the zero-effect refusal is a genuine refusal.
        fundStake(b, reporter);
        uint256 rep0 = crvUSD.balanceOf(reporter);
        uint256 bounty0 = crvUSD.balanceOf(address(b));
        uint256 held0 = _held();

        // ADMISSION-SITE refusal: BadVote from the submit call itself.
        _refuseDistinctDomainSubmit(g, pidB, eh, nonceA);
        assertEq(crvUSD.balanceOf(reporter), rep0, "no stake taken on distinct-domain submit");
        assertEq(crvUSD.balanceOf(address(b)), bounty0, "no custody on distinct-domain submit");
        assertEq(_held(), held0, "no liability on distinct-domain submit");
        assertEq(b.getReport(rA).reporter, address(0), "no report under the mismatched domain");
        assertEq(b.getReport(rB).reporter, address(0), "the ballot's own domain stays unregistered too");

        // Honest-domain positive: the SAME ballot is admitted under its own
        // (nonceB, eh) — the only input that differed was the derived
        // reportId, so the refusal above can only be the live report-ID
        // comparison (the reservations are empty here, and _admitBallot
        // demonstrably passes this ballot).
        vm.prank(reporter);
        bytes32 id = b.submit(g, pidB, eh, nonceB);
        assertEq(id, rB, "own-domain submit admitted");
        assertEq(_phase(id), uint8(Phase.Proposed), "own-domain report is Proposed");
        assertEq(crvUSD.balanceOf(address(b)), bounty0 + STAKE, "exactly one bond after the honest admission");
        assertEq(crvUSD.balanceOf(reporter), rep0 - STAKE, "exactly one pull");
    }

    /// @dev The NAMED distinct-report-ID rejection probe bound to the real
    /// low-level submit call (same shape as the beneficiary-mismatch probe):
    /// the refusal must BE BadVote out of that call, nothing else.
    function _refuseDistinctDomainSubmit(address gauge, uint256 pid, bytes32 eh, uint256 nonce) private {
        vm.prank(reporter);
        (bool domainAccepted, bytes memory domainRet) =
            address(b).call(abi.encodeCall(b.submit, (gauge, pid, eh, nonce)));
        assertFalse(domainAccepted, "DISTINCT_REPORT_ID_ACCEPTED: submit of the other-domain ballot is refused");
        bytesEq(
            domainRet,
            abi.encodeWithSelector(IGaugeBounty.BadVote.selector),
            "DISTINCT_REPORT_ID_ACCEPTED: the refusal selector at admission is BadVote"
        );
    }

    /// @dev RW-P: monotonic ACTUAL ids including zero; once-bound proposals
    /// never rebind — including after terminal refund — and used report ids
    /// never reopen.
    function test_Rework_ProposalReuseRejected() public {
        address g = _list();
        bytes32 eh1 = keccak256(abi.encode("p1", g));
        (bytes32 id1, uint256 pid1) = submitBeneficiaryBallot(b, address(core_), g, reporter, 6001, eh1);

        // Nonexistent id rejected before custody (no binding exists there).
        vm.prank(reporter);
        vm.expectRevert(IGaugeBounty.BadVote.selector);
        b.submit(g, pid1 + 1000, keccak256("ghost"), 6002);

        // Fresh nonce AND fresh evidence cannot rebind the proposal — the
        // permanent map fires before the script comparison. Repoint the
        // fixture record to the otherwise-valid fresh canonical script so a
        // product-only removal of the proposal reservation reaches the
        // expected DuplicateProposal assertion rather than a hash guard.
        bytes32 freshEvidence = keccak256("fresh-evidence");
        bytes32 freshId = computeReportId(b, address(core_), g, reporter, 6003, freshEvidence);
        voting.setScriptFor(
            pid1, BountyScripts.buildKillScript(address(agent), address(b), address(killProxy), g, freshId, reporter)
        );
        fundStake(b, reporter);
        vm.prank(reporter);
        vm.expectRevert(IGaugeBounty.DuplicateProposal.selector);
        b.submit(g, pid1, freshEvidence, 6003);
        // Another reporter cannot take the bound proposal either.
        fundStake(b, secondReporter);
        vm.prank(secondReporter);
        vm.expectRevert(IGaugeBounty.DuplicateProposal.selector);
        b.submit(g, pid1, keccak256("other"), 6004);

        // Replay of the exact same report identity is refused forever.
        vm.prank(reporter);
        vm.expectRevert(IGaugeBounty.DuplicateReport.selector);
        b.submit(g, pid1, eh1, 6001);

        // Terminal refund does not reopen bindings: a report that ends
        // Expired (local clock, listing still live) keeps its proposal
        // permanently bound. bountyreworkfix C4(b): these two post-expiry
        // submits refuse at _admitBallot's DEADLINE guard (BadVote before
        // the reservation checks) — they are clock evidence only. The
        // permanent report/proposal binding after terminal refund/forfeit is
        // witnessed, unmasked, in test_Rework_TerminalBindingReplayLifecycle.
        address g2 = _list();
        (bytes32 id2, uint256 pid2) = submitBeneficiaryBallot(b, address(core_), g2, reporter, 6005, keccak256("p2"));
        ReportView memory rv2 = b.getReport(id2);
        vm.warp(rv2.executeBy + 1);
        assertTrue(b.resolve(id2), "local expiry");
        assertEq(uint8(Phase.Expired), uint8(b.getReport(id2).phase), "Expired");
        vm.prank(stranger);
        (uint256 s2,) = b.claim(id2);
        assertEq(s2, STAKE, "refunded");
        vm.prank(reporter);
        vm.expectRevert(IGaugeBounty.BadVote.selector);
        b.submit(g2, pid2, keccak256("p2-again"), 6006); // DEADLINE_GUARD: not binding evidence
        // And the refunded report's own identity stays closed to reuse.
        vm.prank(reporter);
        vm.expectRevert(IGaugeBounty.BadVote.selector);
        b.submit(g2, pid2, keccak256("p2-again"), 6005); // DEADLINE_GUARD: not binding evidence
    }

    struct TbCase {
        address g;
        bytes32 id;
        uint256 pid;
        bytes32 eh;
        uint256 held;
        uint256 credits;
        uint256 dao;
        uint256 repBal;
        uint256 bountyBal;
        bytes32 reportShape;
    }

    /// @dev RW-P terminal/refund/forfeit lifetime (review/BOUNTY-REWORK-CONF.md
    /// C4(b)): the permanent report/proposal bindings must fire with their OWN
    /// selectors after a terminal closure — not masked by the deadline guard.
    /// The post-refund replays here run inside the never-executed ballot's
    /// honest [voteEnd, executeBy] window (the clock is the only thing
    /// rewound; every observed ballot word stays genuine), so _admitBallot
    /// fully passes and the step-4 reservations alone refuse. The original
    /// report domain is replayed unchanged (TERMINAL_REPORT_BINDING) and the
    /// proposal rebinds under a fresh domain whose otherwise-valid canonical
    /// script is installed through the labelled fixture re-point
    /// (TERMINAL_PROPOSAL_BINDING — the same explicit fault-model isolation
    /// the live cell above uses, now at the terminal lifetime). Full
    /// custody/report invariance and a successful permitted fresh-ballot
    /// retry are asserted, and the forfeited lifetime keeps both bindings.
    /// Falsifiers: RW-P2 removes the used-proposal reservation (the fresh
    /// replay goes red); RW-P3 removes the used-report check (the original
    /// replay goes red).
    function test_Rework_TerminalBindingReplayLifecycle() public {
        TbCase memory c = _tbRefundedCase();
        _tbOriginalDomainReplay(c);
        _tbProposalRebindReplay(c);
        _tbInvarianceAndPermittedRetry(c);
        _tbForfeitLifetime();
    }

    /// @dev Refund lifetime: admit, locally expire, refund once, then rewind
    /// the clock into the never-executed ballot's own honest window so the
    /// deadline guard cannot mask the permanent-binding checks (the ballot
    /// was never voted or executed; only the clock is rewound). Snapshots
    /// custody/report state for the invariance oracle.
    function _tbRefundedCase() private returns (TbCase memory c) {
        c.g = _list();
        c.eh = keccak256("terminal-binding");
        (c.id, c.pid) = submitBeneficiaryBallot(b, address(core_), c.g, reporter, 8100, c.eh);
        uint256 executeBy = b.getReport(c.id).executeBy;
        vm.warp(executeBy + 1);
        assertTrue(b.resolve(c.id), "local expiry");
        assertEq(uint8(Phase.Expired), uint8(b.getReport(c.id).phase), "Expired");
        vm.prank(stranger);
        (uint256 stakeT,) = b.claim(c.id);
        assertEq(stakeT, STAKE, "refunded once");
        (c.held, c.credits, c.dao) = b.accounting();
        c.reportShape = keccak256(abi.encode(b.getReport(c.id)));
        vm.warp(executeBy - 1);
        fundStake(b, reporter);
        c.repBal = crvUSD.balanceOf(reporter);
        c.bountyBal = crvUSD.balanceOf(address(b));
    }

    /// @dev Original report domain replay (gauge, proposal, evidence and
    /// nonce all unchanged): the used-report-ID check must refuse with its
    /// OWN selector. Falsifier RW-P3 removes that check and fails here.
    function _tbOriginalDomainReplay(TbCase memory c) private {
        vm.prank(reporter);
        (bool sameOk, bytes memory sameRet) = address(b).call(abi.encodeCall(b.submit, (c.g, c.pid, c.eh, 8100)));
        assertFalse(sameOk, "TERMINAL_REPORT_BINDING: a refunded report's domain never reopens");
        bytesEq(
            sameRet,
            abi.encodeWithSelector(IGaugeBounty.DuplicateReport.selector),
            "TERMINAL_REPORT_BINDING: the used-report check itself refuses, not the deadline guard"
        );
    }

    /// @dev Fresh domain on the bound proposal with the fixture record
    /// re-pointed to the otherwise-valid canonical script (labelled
    /// fault-model, plan §8 RW-P): the used-proposal reservation alone
    /// stands between the replay and admission. Falsifier RW-P2 removes the
    /// reservation and fails here.
    function _tbProposalRebindReplay(TbCase memory c) private {
        bytes32 freshEh = keccak256("terminal-fresh");
        bytes32 freshId = computeReportId(b, address(core_), c.g, reporter, 8101, freshEh);
        voting.setScriptFor(
            c.pid, BountyScripts.buildKillScript(address(agent), address(b), address(killProxy), c.g, freshId, reporter)
        );
        vm.prank(reporter);
        (bool reuseOk, bytes memory reuseRet) = address(b).call(abi.encodeCall(b.submit, (c.g, c.pid, freshEh, 8101)));
        assertFalse(reuseOk, "TERMINAL_PROPOSAL_BINDING: a refunded proposal never rebinds");
        bytesEq(
            reuseRet,
            abi.encodeWithSelector(IGaugeBounty.DuplicateProposal.selector),
            "TERMINAL_PROPOSAL_BINDING: the used-proposal reservation itself refuses, not the deadline guard"
        );
    }

    /// @dev Full unchanged custody/report state after both refused replays,
    /// and a successful permitted retry: the terminal refund is not a
    /// listing quarantine.
    function _tbInvarianceAndPermittedRetry(TbCase memory c) private {
        (uint256 held1, uint256 credits1, uint256 dao1) = b.accounting();
        assertEq(held1, c.held, "replay takes no stake");
        assertEq(credits1, c.credits, "replay invents no credit");
        assertEq(dao1, c.dao, "replay moves no liability");
        assertEq(keccak256(abi.encode(b.getReport(c.id))), c.reportShape, "terminal record unchanged");
        assertEq(crvUSD.balanceOf(reporter), c.repBal, "refunded reporter moves no further token");
        assertEq(crvUSD.balanceOf(address(b)), c.bountyBal, "no bond survives the terminal replay attempts");
        (bytes32 idFresh, uint256 pidFresh) = _submitBound(c.g, secondReporter);
        pidFresh;
        assertEq(_phase(idFresh), uint8(Phase.Proposed), "fresh ballot admitted after terminal refund");
    }

    /// @dev Forfeit lifetime: an explicitly forfeited unpaid report keeps
    /// both permanent bindings; the owner mark is not an admission reset.
    function _tbForfeitLifetime() private {
        address g = _list();
        bytes32 ehF = keccak256("terminal-forfeit");
        (bytes32 idForf, uint256 pidForf) = submitBeneficiaryBallot(b, address(core_), g, reporter, 8102, ehF);
        uint256 executeByF = b.getReport(idForf).executeBy;
        vm.prank(daoOwner);
        assertTrue(b.markFrivolous(idForf), "owner forfeits the unpaid bond");
        vm.warp(executeByF - 1); // inside the never-executed ballot's window
        vm.prank(reporter);
        vm.expectRevert(IGaugeBounty.DuplicateReport.selector);
        b.submit(g, pidForf, ehF, 8102); // post-forfeit original-domain replay
        bytes32 postForfeitEh = keccak256("post-forfeit");
        bytes32 postForfeitId = computeReportId(b, address(core_), g, reporter, 8103, postForfeitEh);
        voting.setScriptFor(
            pidForf,
            BountyScripts.buildKillScript(address(agent), address(b), address(killProxy), g, postForfeitId, reporter)
        );
        fundStake(b, reporter);
        vm.prank(reporter);
        vm.expectRevert(IGaugeBounty.DuplicateProposal.selector);
        b.submit(g, pidForf, postForfeitEh, 8103); // post-forfeit proposal rebind
    }

    /// @dev RW-R: two reporters, two ACTUAL proposals, one listing. First
    /// valid recognition wins in either order, independent of submit order;
    /// both bonds refundable; exactly one real allocation through BOTH
    /// seizure entrypoints, with no prefunded bounty reward to fake it.
    function test_Rework_FirstRecognitionWinsBothOrders() public {
        // Order A-first (first submitter also wins).
        address g = _list();
        (bytes32 idA, uint256 pidA) = _submitBound(g, reporter);
        (bytes32 idB, uint256 pidB) = _submitBound(g, secondReporter);
        _votePairAndExecuteFirst(pidA, pidB);
        assertEq(uint8(Phase.Recognized), _phase(idA), "A wins first");
        unkillGaugeViaRoute(g); // authorized unkill with R still positive
        vm.prank(stranger);
        voting.executeVote(pidB); // B's kill still lands (protective); B loses
        assertEq(uint8(Phase.NoAward), _phase(idB), "loser cannot overwrite the latch");
        assertEq(uint8(Phase.Recognized), _phase(idA), "winner untouched");
        assertTrue(GovernanceGauge(g).is_killed(), "B's middle kill still protected");

        // Exactly one real allocation via confiscate(); the bounty held no
        // reward credit before it.
        assertEq(_credits(), 0, "no prefunded reward to fake funding");
        _seizeVia(g, false);
        assertEq(uint8(Phase.Rewarded), _phase(idA), "winner rewarded");
        assertEq(_credits(), FEE / 2, "one funded half-credit only");
        vm.prank(stranger);
        (uint256 sB,) = b.claim(idB);
        assertEq(sB, STAKE, "loser bond refunded");

        // Order B-first (first SUBMITTED may still LOSE), via checkpoint().
        address g2 = _list();
        (bytes32 idX, uint256 pidX) = _submitBound(g2, reporter);
        (bytes32 idY, uint256 pidY) = _submitBound(g2, secondReporter);
        _votePairAndExecuteFirst(pidY, pidX); // the later submission wins first
        assertEq(uint8(Phase.Recognized), _phase(idY), "submission order ranks nothing");
        assertEq(uint8(Phase.Proposed), _phase(idX), "X still pending its own ballot");
        unkillGaugeViaRoute(g2);
        vm.prank(stranger);
        voting.executeVote(pidX);
        assertEq(uint8(Phase.NoAward), _phase(idX), "X closed by its own failed attempt");
        assertEq(uint8(Phase.Recognized), _phase(idY), "winner intact");
        assertEq(_credits(), FEE / 2, "still exactly one funded credit world-wide");
        _seizeVia(g2, true);
        assertEq(uint8(Phase.Rewarded), _phase(idY), "second listing pays via checkpoint");
        assertEq(_credits(), FEE, "one real B per qualifying listing, never two");
        (uint256 sy,) = b.claim(idY);
        assertEq(sy, STAKE, "winner stake refund available regardless");
        // X's execution produced no allocation: its claim is stake-only.
        (uint256 sx, uint256 rx) = b.claim(idX);
        assertEq(sx, STAKE, "X bond refund");
        assertEq(rx, 0, "X earns no invented reward");
    }

    /// @dev RW-W: the winner survives an FD outage, its stake refund,
    /// unkill/re-kill and time past executeBy; later reporters cannot replace
    /// it; terminal exhaustion closes the unpaid entitlement but never
    /// reopens the latch.
    function test_Rework_WinnerSurvivesUnkillAndDelay() public {
        address g = _list();
        (bytes32 idW, uint256 pidW) = _submitBound(g, reporter);
        _passAndExecute(pidW);
        assertEq(uint8(Phase.Recognized), _phase(idW), "winner");

        // FD unavailable (killed distributor): the funded seizure fails
        // closed and the entitlement REMAINS Recognized without time expiry
        // while the bond can already be claimed.
        _spaceFdCursor();
        fd.setKilled(true);
        vm.prank(stranger);
        vm.expectRevert(); // fail-closed FD preflight
        core_.confiscate(g);
        fd.setKilled(false);

        vm.prank(stranger);
        (uint256 s,) = b.claim(idW);
        assertEq(s, STAKE, "bond claimable during outage");
        (bytes32 rid, address rr, bool el) = b.rewardTerms(g);
        assertEq(rid, idW, "latch survives claim");
        assertEq(rr, reporter, "fixed recipient survives claim");
        assertTrue(el, "still eligible until actually funded");

        // Unkill/re-kill and time past executeBy: winner intact; a later
        // reporter is refused on the latched listing.
        unkillGaugeViaRoute(g);
        killGaugeViaRoute(g);
        vm.warp(b.getReport(idW).executeBy + 1 days);
        (rid, rr, el) = b.rewardTerms(g);
        assertEq(rid, idW, "latch forever");
        assertEq(rr, reporter, "identity forever");
        assertTrue(el, "Recognized survives time alone without expiry");
        fundStake(b, secondReporter);
        vm.prank(secondReporter);
        vm.expectRevert(IGaugeBounty.IneligibleGauge.selector);
        b.submit(g, 0, keccak256("too late"), 7001);

        // Recovery pays the same winner exactly once; afterwards the latch
        // still names it but eligibility is consumed.
        _seizeVia(g, false);
        assertEq(uint8(Phase.Rewarded), _phase(idW), "funded after recovery");
        (rid,, el) = b.rewardTerms(g);
        assertFalse(el, "consumed allocation no longer eligible");
        assertEq(rid, idW, "id/reporter still returned after funding");
        assertEq(b.getReport(idW).reporter, reporter, "permanent identity");
        // Terminal closure (second listing never won) never reopens a latch:
        // an exhausted unpaid case keeps the consumed permanent record.
        vm.prank(stranger);
        (uint256 sw, uint256 rw2) = b.claim(idW);
        assertEq(sw, 0, "stake already paid");
        assertEq(rw2, FEE / 2, "funded reward paid to the fixed recipient");
    }

    /// @dev RW-S: every admission fault is atomic — balances, liabilities,
    /// reports and proposal reservations are unchanged, and a successful
    /// retry after each fault proves no consumed id.
    function test_Rework_AdmissionFaultsAreAtomic() public {
        address g = _list();

        // Absent id.
        fundStake(b, reporter);
        vm.prank(reporter);
        vm.expectRevert(IGaugeBounty.BadVote.selector);
        b.submit(g, 9999, keccak256("ghost"), 1);

        // Already-executed ballot never bound to any report. bountyreworkfix
        // C4(a): the killed-listing refusal is kept as its own honest cell,
        // then the listing is restored to eligibility through the authorized
        // route so the refusal can no longer hide behind _requireEligible:
        // with the gauge un-killed the ONLY thing that can refuse this
        // executed-record submit is _admitBallot's rec.executed guard —
        // BadVote before custody (falsifier RW-S2 removes that guard and
        // fails at the named frame below).
        address gE = _list();
        bytes32 ehE = keccak256(abi.encode("exec", gE));
        (bytes32 rE, uint256 pidE) = createBeneficiaryBallot(b, address(core_), gE, reporter, reporter, 7100, ehE);
        _passAndExecute(pidE); // executes; report was never submitted
        assertEq(b.getReport(rE).reporter, address(0), "executing alone registers nothing");
        assertTrue(GovernanceGauge(gE).is_killed(), "the executed ballot landed its protective kill");
        vm.prank(reporter);
        vm.expectRevert(IGaugeBounty.IneligibleGauge.selector);
        b.submit(gE, pidE, ehE, 7100); // listing-killed refusal (eligibility guard, not the executed guard)
        assertEq(_held(), 0, "no liability from the killed-listing submit");
        unkillGaugeViaRoute(gE); // ballot stays executed forever; the listing is eligible again
        assertFalse(GovernanceGauge(gE).is_killed(), "listing eligibility restored");
        fundStake(b, reporter);
        uint256 heldBeforeE = _held();
        uint256 bountyBeforeE = crvUSD.balanceOf(address(b));
        vm.prank(reporter);
        (bool execAdmitted, bytes memory execRet) = address(b).call(abi.encodeCall(b.submit, (gE, pidE, ehE, 7100)));
        assertFalse(execAdmitted, "ADMIT_EXECUTED_BALLOT: an executed ballot is refused before custody");
        bytesEq(
            execRet,
            abi.encodeWithSelector(IGaugeBounty.BadVote.selector),
            "ADMIT_EXECUTED_BALLOT: the refusal is _admitBallot's rec.executed BadVote, not an eligibility artifact"
        );
        assertEq(_held(), heldBeforeE, "no liability from executed-ballot submit");
        assertEq(crvUSD.balanceOf(address(b)), bountyBeforeE, "no custody from executed-ballot submit");
        assertEq(b.getReport(rE).reporter, address(0), "executed ballot still registers nothing");
        // The executed record is what refused it: the same eligible listing
        // still admits a fresh unexecuted ballot immediately.
        (bytes32 idE2,) = _submitBound(gE, secondReporter);
        assertEq(
            _phase(idE2), uint8(Phase.Proposed), "unexecuted ballot admitted: the executed guard carried the refusal"
        );

        // Future startDate observation seam fails closed.
        address gF = _list();
        bytes32 ehF = keccak256(abi.encode("future", gF));
        (, uint256 pidF) = createBeneficiaryBallot(b, address(core_), gF, reporter, reporter, 7101, ehF);
        voting.setStartDateObservation(true, block.timestamp + 10 days);
        vm.prank(reporter);
        vm.expectRevert(IGaugeBounty.BadVote.selector);
        b.submit(gF, pidF, ehF, 7101);
        voting.setStartDateObservation(false, 0);

        // Malformed record (truncated getVote return) fails closed.
        voting.setGetVoteFault(2);
        vm.prank(reporter);
        vm.expectRevert(IGaugeBounty.BadVote.selector);
        b.submit(gF, pidF, ehF, 7101);
        voting.setGetVoteFault(0);

        // Pin drift (voteTime) is configuration incompatibility, before the
        // pull, retaining nothing: the SAME proposal admits after recovery.
        // (bountyreworkfix: compared as a delta, since earlier cells of this
        // identity now hold legitimately admitted bonds.)
        vm.prank(votingDao);
        voting.setVoteTime(1);
        uint256 balBeforeDrift = crvUSD.balanceOf(address(b));
        vm.prank(reporter);
        vm.expectRevert(IGaugeBounty.BadConfiguration.selector);
        b.submit(gF, pidF, ehF, 7101);
        assertEq(crvUSD.balanceOf(address(b)), balBeforeDrift, "pin drift retains nothing");
        vm.prank(votingDao);
        voting.setVoteTime(VOTE_TIME);
        vm.prank(reporter);
        bytes32 idF = b.submit(gF, pidF, ehF, 7101);
        assertEq(idF, computeReportId(b, address(core_), gF, reporter, 7101, ehF), "retry consumed no id");

        // Zero evidence precedes everything after the pull.
        address gZ = _list();
        vm.prank(reporter);
        vm.expectRevert(IGaugeBounty.BadEvidence.selector);
        b.submit(gZ, pidF, bytes32(0), 7102);

        // A never-listed gauge is not a registry-authenticated paid listing.
        (address poolP, address gaugeP,) = deployGovernanceGauge();
        poolP;
        vm.prank(reporter);
        vm.expectRevert(IGaugeBounty.IneligibleGauge.selector);
        b.submit(gaugeP, pidF, keccak256("free"), 7103);

        // Transfer fault then successful retry proves no consumed proposal:
        // no allowance fails the pull; the same proposal/domain re-admits.
        address gR = _list();
        bytes32 ehR = keccak256(abi.encode("retry", gR));
        (bytes32 idR, uint256 pidR) =
            createBeneficiaryBallot(b, address(core_), gR, secondReporter, secondReporter, 7104, ehR);
        vm.prank(secondReporter);
        vm.expectRevert(); // no allowance: SafeToken fails the pull
        b.submit(gR, pidR, ehR, 7104);
        assertEq(b.getReport(idR).reporter, address(0), "nothing persisted");
        fundStake(b, secondReporter);
        vm.prank(secondReporter);
        bytes32 idAgain = b.submit(gR, pidR, ehR, 7104);
        assertEq(idAgain, idR, "no consumed id across the transfer fault");

        // Unauthorized callbacks revert; the wrong-beneficiary authorized
        // callback only closes its own unfinished offer, then the exact
        // 1,000 refund pays the FIXED recipient once.
        vm.prank(stranger);
        vm.expectRevert(IGaugeBounty.NotAgent.selector);
        b.creditBallot(idAgain, secondReporter);
        vm.prank(stranger);
        vm.expectRevert(IGaugeBounty.NotAgent.selector);
        b.recognizeKill(idAgain);
        vm.prank(address(agent));
        b.creditBallot(idAgain, reporter); // wrong supplied beneficiary
        assertEq(uint8(Phase.NoAward), uint8(b.getReport(idAgain).phase), "own offer closed, no slash");
        vm.prank(stranger);
        (uint256 s,) = b.claim(idAgain);
        assertEq(s, STAKE, "exact 1,000 refund, fixed recipient, once");
        vm.prank(stranger);
        (uint256 s2, uint256 r2) = b.claim(idAgain);
        assertEq(s2 + r2, 0, "repeat claim makes no token call");
    }
}

/// @dev Minimal contract-wallet beneficiary: only the wallet itself (not its
/// owner EOA) can bind a ballot naming it; the owner merely triggers.
contract BeneficiaryWallet {
    GaugeBounty private immutable _bounty;

    constructor(GaugeBounty bounty_) {
        _bounty = bounty_;
    }

    function approveStake(address token, address spender, uint256 amount) external {
        IERC20Minimal(token).approve(spender, amount);
    }

    function submit(address gauge, uint256 proposalId, bytes32 evidenceHash, uint256 nonce) external {
        _bounty.submit(gauge, proposalId, evidenceHash, nonce);
    }
}
