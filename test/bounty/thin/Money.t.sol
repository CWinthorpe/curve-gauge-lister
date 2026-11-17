// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BountyFixture} from "../BountyFixture.sol";
import {Vm} from "../../TestBase.sol";
import {GaugeBounty} from "../../../contracts/GaugeBounty.sol";
import {CurveGaugeListerV2} from "../../../contracts/CurveGaugeListerV2.sol";
import {IGaugeBounty} from "../../../contracts/interfaces/IGaugeBounty.sol";
import {ReportView, BountyConfig, Phase, StakeState} from "../../../contracts/bounty/BountyTypes.sol";
import {GovernanceGauge} from "../mocks/MockBountyGovernance.sol";
import {MockFeeDistributor} from "../../../contracts/mocks/MockFeeDistributor.sol";
import {ReentrantToken} from "../mocks/BountyFaultActors.sol";
import {MockIncentivePlatform} from "../../../contracts/mocks/MockIncentivePlatform.sol";
import {MockListingController} from "../../../contracts/mocks/MockListingController.sol";
import {SafeToken} from "../../../contracts/libraries/SafeToken.sol";
import {FeeDistributorAccounting} from "../../../contracts/libraries/FeeDistributorAccounting.sol";

/// @notice Thin money suite (plans/BOUNTY-THIN-PLAN.md §7.2 M01–M10): the
/// single owner-only stake-forfeit transition, exhaustive non-frivolous
/// refunds (every §3.3 row incl. both timeout paths), fixed-recipient
/// combined claims and the FD liability flush. Every assertion inspects real
/// custody deltas, real liability totals and the real flat report view.
contract ThinMoneyTest is BountyFixture {
    struct Live {
        CurveGaugeListerV2 core_;
        GaugeBounty b;
        address gauge;
        bytes32 id;
        uint256 voteId;
    }

    uint256 internal _seq = 1;

    function setUp() public {
        setupBountyWorld();
    }

    // ---------------------------------------------------------------- glue

    function _fundStake(GaugeBounty b, address who) internal {
        crvUSD.mint(who, STAKE);
        approveCrvUsd(who, address(b), STAKE);
    }

    function _thinSubmit(GaugeBounty b, address who, address gauge) internal returns (bytes32 id, bool created) {
        bytes32 eh = keccak256(abi.encode("money-evidence", who, gauge, _seq));
        _seq += 1;
        (id,) = submitBeneficiaryBallot(b, address(coreOf(b)), gauge, who, _seq, eh);
        created = uint8(b.getReport(id).phase) == uint8(Phase.Proposed);
    }

    /// @dev Resolve the pair partner for a given bounty instance.
    mapping(GaugeBounty => CurveGaugeListerV2) internal _pairOf;

    function coreOf(GaugeBounty b) internal view returns (CurveGaugeListerV2) {
        return _pairOf[b];
    }

    function _proposed(GaugeBounty b, address gauge) internal returns (bytes32 id) {
        bool created;
        (id, created) = _thinSubmit(b, reporter, gauge);
        require(created, "money: admitted");
    }

    function _recognize(GaugeBounty b, bytes32 id, uint256 voteId) internal {
        address whale = address(uint160(0xA11CE500 + _seq++));
        giveVePower(whale, 5_000_000e18);
        vm.prank(whale);
        voting.vote(voteId, true);
        vm.warp(b.getReport(id).voteEnd);
        vm.prank(stranger);
        voting.executeVote(voteId); // real CallsScript/Agent/proxy/gauge path
    }

    /// @dev Fresh honest pair with one fully recognized canonical kill.
    function _recognizedWorld() internal returns (Live memory L) {
        (L.core_, L.b) = deployBoundPair();
        _pairOf[L.b] = L.core_;
        (, L.gauge,) = listBountyEligible(L.core_);
        L.id = _proposed(L.b, L.gauge);
        L.voteId = L.b.getReport(L.id).proposalId;
        _recognize(L.b, L.id, L.voteId);
        require(GovernanceGauge(L.gauge).is_killed(), "money: killed via route");
    }

    function _spaceFdCursor() internal {
        if (block.timestamp <= fd.last_token_time() + 86_400) {
            fd.setLastTokenTime(block.timestamp - 86_401);
        }
    }

    function _listOn(CurveGaugeListerV2 c) internal returns (address) {
        (, address g,) = listBountyEligible(c);
        return g;
    }

    /// @dev Snapshot of everything markFrivolous must NOT change: the full
    /// flat view except the bond disposition, and the full V2 listing.
    function _caseFingerprint(GaugeBounty b, CurveGaugeListerV2 core_, address gauge, bytes32 id)
        internal
        view
        returns (bytes32)
    {
        ReportView memory rv = b.getReport(id);
        // The bond disposition is the ONLY thing markFrivolous may change.
        rv.stakeState = 0;
        bytes32 hRv = keccak256(abi.encode(rv));
        bytes32 hLs = keccak256(abi.encode(core_.getListing(gauge)));
        (bytes32 slot,,) = b.rewardTerms(gauge);
        return keccak256(abi.encode(hRv, hLs, slot));
    }

    // ----------------------------------------------------------------- M01

    function test_Thin_FailedBallotRefund() public {
        // Closed, unexecuted, canExecute-false ballot: resolve -> Rejected
        // and an immediate full bond refund. Never an automatic forfeit.
        (CurveGaugeListerV2 core_, GaugeBounty b) = deployBoundPair();
        _pairOf[b] = core_;
        address g = _listOn(core_);
        bytes32 id = _proposed(b, g);
        uint256 voteId = b.getReport(id).proposalId;
        vm.warp(b.getReport(id).voteEnd); // close the ballot with NO votes
        assertFalse(voting.canExecute(voteId), "zero-vote tally cannot execute");
        vm.prank(stranger);
        assertTrue(b.resolve(id), "resolve closes the validated failure");
        assertEq(uint8(Phase.Rejected), uint256(b.getReport(id).phase), "Rejected");
        assertEq(uint8(b.getReport(id).stakeState), uint8(StakeState.Refundable), "refundable at once");
        (uint256 stake0, uint256 rew0) = b.claim(id);
        assertEq(stake0, STAKE, "losing ruling refunds the full bond");
        assertEq(rew0, 0, "losers get no reward");
        (uint256 held,, uint256 dao) = b.accounting();
        assertEq(held, 0, "held stakes empty after refund");
        assertEq(dao, 0, "losing never slashes");
        // A second resolve is a terminal no-op.
        assertFalse(b.resolve(id), "Rejected is a local no-op");
    }

    // M02 (test_Thin_UncreatedRefundWithDeadDependencies) is RETIRED with
    // the queue (plans/BOUNTY-REWORK-PLAN.md §7): there are no uncreated
    // accepted reports, and every dead-dependency refund path is covered by
    // test_Thin_UnexecutedRefundWithDeadDependencies plus the rework suite.

    // ----------------------------------------------------------------- M03

    function test_Thin_UnexecutedRefundWithDeadDependencies() public {
        // Passed-but-unexecuted, then the execution window lapses with every
        // upstream dependency unavailable: executeBy + 1 refunds locally.
        Live memory L = _recognizedWorld();
        address g2 = _listOn(L.core_);
        bytes32 idP = _proposed(L.b, g2);
        ReportView memory rvP = L.b.getReport(idP);
        require(rvP.reporter != address(0), "bound");
        (, bool executedP,,,,,,,,) = voting.getVote(rvP.proposalId);
        require(!executedP, "ballot left unexecuted");

        // Everything rots while the ballot sits unexecuted.
        voting.setGetVoteFault(1);
        voting.setNewVoteFault(1);
        checker.setAllow(false);
        GovernanceGauge(g2).setFlagFault(1);
        fd.setKilled(true);

        vm.warp(rvP.executeBy + 1);
        (uint256 stakeP, uint256 rewP) = L.b.claim(idP);
        assertEq(stakeP, STAKE, "executeBy+1 refund with no live dependency");
        assertEq(rewP, 0, "nothing was ever funded");
        assertEq(uint8(Phase.Expired), uint256(L.b.getReport(idP).phase), "Expired via claim cleanup");

        voting.setGetVoteFault(0);
        voting.setNewVoteFault(0);
        checker.setAllow(true);
        GovernanceGauge(g2).setFlagFault(0);
        fd.setKilled(false);
        // Late upstream execution can still kill but cannot revive a reward:
        // the terminal case claims empty forever.
        (uint256 stakeLate, uint256 rewLate) = L.b.claim(idP);
        assertEq(stakeLate, 0, "terminal claim stays empty");
        assertEq(rewLate, 0, "terminal claim stays empty (reward)");
    }

    // ----------------------------------------------------------------- M04

    function test_Thin_SuccessRefundBeforeDelayedReward() public {
        // Bond claimable AT recognition even while the FD refuses funding;
        // later safe settlement funds B and the reward claims with no new
        // delay and no finality flag.
        Live memory L = _recognizedWorld();
        assertEq(uint8(Phase.Recognized), uint256(L.b.getReport(L.id).phase), "Recognized");
        assertEq(uint8(L.b.getReport(L.id).stakeState), uint8(StakeState.Refundable), "bond refundable");

        // FD unavailable: confiscation is refused BEFORE any effect, so the
        // entitlement remains local and unallocated.
        uint256 savedCursor = fd.last_token_time();
        fd.setLastTokenTime(block.timestamp - 41 * WEEK); // beyond 20 weeks
        vm.prank(stranger);
        vm.expectRevert(FeeDistributorAccounting.DistributorUnusable.selector);
        L.core_.confiscate(L.gauge);
        assertEq(L.b.getReport(L.id).rewardCredit, 0, "nothing allocated yet");
        assertEq(
            uint8(Phase.Recognized), uint256(L.b.getReport(L.id).phase), "still Recognized (no expiry while FD waits)"
        );

        // The stake does NOT wait for funding or flush:
        (uint256 stake0,) = L.b.claim(L.id);
        assertEq(stake0, STAKE, "bond paid at recognition despite FD outage");

        // FD recovers; the retry of the SAFE seizure funds B exactly once.
        fd.setLastTokenTime(savedCursor);
        _spaceFdCursor();
        uint256 rem = L.core_.getListing(L.gauge).remaining;
        vm.prank(stranger);
        L.core_.confiscate(L.gauge);
        assertEq(L.b.getReport(L.id).rewardCredit, rem / 2, "funded after delay");
        assertEq(uint8(Phase.Rewarded), uint256(L.b.getReport(L.id).phase), "Rewarded");
        (, uint256 reward0) = L.b.claim(L.id);
        assertEq(reward0, rem / 2, "reward claimable immediately, no new delay");
        (uint256 sEnd, uint256 rEnd) = L.b.claim(L.id);
        assertEq(sEnd, 0, "combined claim empty after both legs");
        assertEq(rEnd, 0, "combined claim empty after both legs (reward)");
    }

    // ----------------------------------------------------------------- M05

    function test_Thin_FrivolousAuthorityIsConfigOwner() public {
        Live memory L = _recognizedWorld();
        GaugeBounty b = L.b;

        // Unknown report reverts regardless of caller authority.
        vm.prank(daoOwner);
        vm.expectRevert(IGaugeBounty.UnknownReport.selector);
        b.markFrivolous(keccak256("ghost"));

        // Outsiders and every OTHER role are refused with NotDao.
        address[5] memory refuse = [stranger, reporter, address(agent), treasury, emergencySafe];
        for (uint256 i = 0; i < refuse.length; ++i) {
            vm.prank(refuse[i]);
            vm.expectRevert(IGaugeBounty.NotDao.selector);
            b.markFrivolous(L.id);
        }
        assertEq(uint256(b.getReport(L.id).phase), uint8(Phase.Recognized), "still recognized");

        // The CURRENT V2 config owner succeeds.
        vm.prank(daoOwner);
        assertTrue(b.markFrivolous(L.id), "owner forfeits");
        (,, uint256 dao1) = b.accounting();
        assertEq(dao1, STAKE, "one reserved forfeit");

        // Actual two-step transfer moves ONLY this authority. While the
        // transfer is merely pending, the current owner retains it and the
        // pending address has none.
        address newOwner = actor("freshDaoMultisig");
        (, address g2,) = listBountyEligible(L.core_);
        (bytes32 id2,) = _thinSubmit(b, secondReporter, g2);
        vm.prank(daoOwner);
        L.core_.transferOwnership(newOwner);
        vm.prank(newOwner);
        vm.expectRevert(IGaugeBounty.NotDao.selector);
        b.markFrivolous(id2);
        vm.prank(daoOwner);
        assertTrue(b.markFrivolous(id2), "current owner keeps authority while pending");

        vm.prank(newOwner);
        L.core_.acceptOwnership();
        (, address g3,) = listBountyEligible(L.core_);
        (bytes32 id3,) = _thinSubmit(b, reporter, g3);
        vm.prank(daoOwner);
        vm.expectRevert(IGaugeBounty.NotDao.selector);
        b.markFrivolous(id3);
        vm.prank(newOwner);
        assertTrue(b.markFrivolous(id3), "new owner forfeits");
        (,, uint256 dao3) = b.accounting();
        assertEq(dao3, 3 * STAKE, "three exact reservations");

        // Same authority as V2's configuration setters: it moved together.
        vm.prank(daoOwner);
        vm.expectRevert(CurveGaugeListerV2.NotOwner.selector);
        L.core_.setPaused(true);
        vm.prank(newOwner);
        L.core_.setPaused(true);
        vm.prank(newOwner);
        L.core_.setPaused(false);
    }

    // ----------------------------------------------------------------- M06

    function test_Thin_ForfeitOnlyStake() public {
        _forfeitQueuedCell();
        _forfeitProposedCell();
        _forfeitRecognizedCells();
    }

    function _forfeitQueuedCell() private {
        (CurveGaugeListerV2 c1, GaugeBounty b1) = deployBoundPair();
        _pairOf[b1] = c1;
        (, address gS,) = listBountyEligible(c1);
        bytes32 idS = _proposed(b1, gS);
        idS;
        (, address gQ,) = listBountyEligible(c1);
        (bytes32 idQ, bool createdQ) = _thinSubmit(b1, secondReporter, gQ);
        assertTrue(createdQ, "concurrent proposal");
        _forfeitAndCompare(b1, c1, gQ, idQ, "proposed-concurrent");
    }

    function _forfeitProposedCell() private {
        (CurveGaugeListerV2 c2, GaugeBounty b2) = deployBoundPair();
        _pairOf[b2] = c2;
        (, address gP,) = listBountyEligible(c2);
        bytes32 idP = _proposed(b2, gP);
        _forfeitAndCompare(b2, c2, gP, idP, "proposed");
    }

    function _forfeitRecognizedCells() private {
        // (c) Recognized case, bond refundable-but-unpaid.
        Live memory R3 = _recognizedWorld();
        _forfeitAndCompare(R3.b, R3.core_, R3.gauge, R3.id, "recognized");

        // (d) Reward-funded case: the forfeited bond never vetoes the half.
        Live memory R4 = _recognizedWorld();
        uint256 rem = R4.core_.getListing(R4.gauge).remaining;
        _spaceFdCursor();
        vm.prank(stranger);
        R4.core_.confiscate(R4.gauge);
        assertEq(R4.b.getReport(R4.id).rewardCredit, rem / 2, "reward funded first");
        _forfeitAndCompare(R4.b, R4.core_, R4.gauge, R4.id, "reward-funded");
        (, uint256 rewR4) = R4.b.claim(R4.id);
        assertEq(rewR4, rem / 2, "forfeited case still earns its half");
        (uint256 stakeR4,) = R4.b.claim(R4.id);
        assertEq(stakeR4, 0, "forfeited bond paid nothing");
    }

    struct Snap {
        bytes32 fp;
        uint256 held;
        uint256 credits;
        uint256 dao;
    }

    function _snap(GaugeBounty b, CurveGaugeListerV2 core_, address gauge, bytes32 id)
        private
        view
        returns (Snap memory x)
    {
        x.fp = _caseFingerprint(b, core_, gauge, id);
        (x.held, x.credits, x.dao) = b.accounting();
    }

    function _forfeitAndCompare(GaugeBounty b, CurveGaugeListerV2 core_, address gauge, bytes32 id, string memory label)
        private
    {
        Snap memory pre = _snap(b, core_, gauge, id);
        vm.prank(daoOwner);
        vm.recordLogs();
        assertTrue(b.markFrivolous(id), label);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertTrue(hasEventFrom(logs, address(b), sig("StakeForfeited(bytes32)")), "StakeForfeited emitted");
        Snap memory post = _snap(b, core_, gauge, id);
        assertEq(post.fp, pre.fp, "only the stake moved");
        assertEq(post.held, pre.held - STAKE, "held stakes minus one stake");
        assertEq(post.dao, pre.dao + STAKE, "FD liability plus one stake");
        assertEq(post.credits, pre.credits, "credits untouched");
        assertEq(uint8(b.getReport(id).stakeState), uint8(StakeState.Forfeited), "Forfeited");
    }

    // ----------------------------------------------------------------- M07

    function test_Thin_ForfeitAndRefundOrdering() public {
        // Claim-before-mark order: the bond is paid, mark is then powerless.
        Live memory L = _recognizedWorld();
        (uint256 stake0,) = L.b.claim(L.id);
        assertEq(stake0, STAKE, "refund paid first");
        vm.prank(daoOwner);
        assertFalse(L.b.markFrivolous(L.id), "paid stake cannot forfeit");
        (,, uint256 daoA) = L.b.accounting();
        assertEq(daoA, 0, "no liability from a paid bond");
        // No late clawback: the payment stands forever.
        vm.prank(daoOwner);
        assertFalse(L.b.markFrivolous(L.id), "repeat is inert");
        assertEq(crvUSD.balanceOf(address(L.b)), 0, "no clawback path");

        // Mark-before-claim order: refundable-but-unpaid forfeits exactly.
        Live memory R = _recognizedWorld();
        vm.prank(daoOwner);
        assertTrue(R.b.markFrivolous(R.id), "refundable unpaid bond forfeits");
        (uint256 stakeR,) = R.b.claim(R.id);
        assertEq(stakeR, 0, "forfeited bond pays nothing");
        (,, uint256 daoR) = R.b.accounting();
        assertEq(daoR, STAKE, "exactly one stake reserved");
        vm.prank(daoOwner);
        assertFalse(R.b.markFrivolous(R.id), "forfeited bond cannot double-forfeit");
        (,, uint256 daoR2) = R.b.accounting();
        assertEq(daoR2, STAKE, "liability stays one stake");
        // The forfeited case's recognized entitlement survives the forfeit.
        uint256 rem = R.core_.getListing(R.gauge).remaining;
        _spaceFdCursor();
        vm.prank(stranger);
        R.core_.confiscate(R.gauge);
        (, uint256 rewR) = R.b.claim(R.id);
        assertEq(rewR, rem / 2, "recognition unaffected by forfeit");
        // Both transaction orders commute on the money: B/F preserved, only
        // the bond destination differed.
        assertEq(crvUSD.balanceOf(reporter), STAKE + rem / 2, "one bond (first case) plus one reward");
    }

    // ----------------------------------------------------------------- M08

    function test_Thin_FixedRecipientClaimAndRollback() public {
        Live memory L = _recognizedWorld();
        // Caller cannot redirect: stranger claims, stored reporter is paid.
        uint256 rep0 = crvUSD.balanceOf(reporter);
        uint256 att0 = crvUSD.balanceOf(stranger);
        (uint256 stakeC,) = L.b.claim(L.id);
        assertEq(stakeC, STAKE, "anyone may claim");
        assertEq(crvUSD.balanceOf(reporter) - rep0, STAKE, "fixed reporter received");
        assertEq(crvUSD.balanceOf(stranger), att0, "caller never redirected the payment");
        // Repeated claim: zero without token movement.
        uint256 bountyBal = crvUSD.balanceOf(address(L.b));
        (uint256 stakeAgain, uint256 rewAgain) = L.b.claim(L.id);
        assertEq(stakeAgain, 0, "repeat is empty");
        assertEq(rewAgain, 0, "repeat reward empty");
        assertEq(crvUSD.balanceOf(address(L.b)), bountyBal, "empty claim touches nothing");
        // Unknown reports revert rather than pay nothing quietly.
        vm.expectRevert(IGaugeBounty.UnknownReport.selector);
        L.b.claim(keccak256("ghost"));

        // Token tax, false return and empty return each run on a fresh
        // recognized world (credits must not be shared across fault cells).
        _claimFaultCell(25, false, false);
        _claimFaultCell(0, true, false);
        _claimFaultCell(0, false, true);

        // Malformed (non-empty, non-true) return and re-entrant payout.
        _tokenFaultWorldCell();

        // bountyreworkfix C3(b) (F10): the reward-only component ALONE,
        // faulted and retried AFTER the bond has already settled — once via
        // refund, once via explicit forfeiture. Healthy reward-only payment
        // elsewhere is not this oracle (review/BOUNTY-REWORK-CONF.md C3(b));
        // each cell asserts complete rollback and the exact retry payout.
        _rewardOnlyFaultedClaimAfterBondRefunded();
        _rewardOnlyFaultedClaimAfterBondForfeited();
    }

    /// @dev Same honest recognized world as _recognizedWorld but voted by a
    /// dominant whale: the M08 identity accumulates ve supply across its
    /// many fresh cells, so the added reward-only lifetime cells fund a
    /// whale that clears the STRICT support/quorum ratios against the grown
    /// total supply (the fixed 5M whale would otherwise fail the tally).
    function _recognizedWorldDominant() private returns (Live memory L) {
        (L.core_, L.b) = deployBoundPair();
        _pairOf[L.b] = L.core_;
        (, L.gauge,) = listBountyEligible(L.core_);
        L.id = _proposed(L.b, L.gauge);
        L.voteId = L.b.getReport(L.id).proposalId;
        address whale = address(uint160(0xA11CEB00 + _seq++));
        giveVePower(whale, (escrow.totalSupply() + 1e18) * 3);
        vm.prank(whale);
        voting.vote(L.voteId, true);
        vm.warp(L.b.getReport(L.id).voteEnd);
        vm.prank(stranger);
        voting.executeVote(L.voteId);
        require(GovernanceGauge(L.gauge).is_killed(), "money: dominant-whale killed via route");
    }

    /// @dev Shared funding for the reward-only cells: confiscate the killed
    /// canonical listing so the case is Rewarded with exactly B funded.
    function _fundRewardOnly(Live memory W) internal returns (uint256 bHalf) {
        _spaceFdCursor();
        vm.prank(stranger);
        uint256 gross = W.core_.confiscate(W.gauge);
        bHalf = gross / 2;
        (, uint256 credits,) = W.b.accounting();
        require(credits == bHalf && bHalf > 0, "money: reward funded");
    }

    /// @dev Bond REFUNDED first, then the funded reward claim faults on a
    /// false-transfer token and retries: (0, B) exactly, once, with the
    /// credit/liability/phase fully surviving the rollback.
    function _rewardOnlyFaultedClaimAfterBondRefunded() private {
        Live memory W = _recognizedWorldDominant();
        (uint256 stake0,) = W.b.claim(W.id);
        assertEq(stake0, STAKE, "reward-only cell: bond settled first");
        uint256 bHalf = _fundRewardOnly(W);
        (uint256 h0, uint256 c0, uint256 d0) = W.b.accounting();
        assertEq(h0, 0, "reward-only cell: no bond held after refund");
        assertEq(c0, bHalf, "reward-only cell: liability is the funded reward");
        uint256 rep0 = crvUSD.balanceOf(reporter);
        crvUSD.setTransferBehavior(0, true, false); // transfers return false
        vm.expectRevert(abi.encodeWithSelector(SafeToken.SafeTokenBadReturn.selector, address(crvUSD)));
        W.b.claim(W.id);
        crvUSD.setTransferBehavior(0, false, false);
        (uint256 h1, uint256 c1, uint256 d1) = W.b.accounting();
        bytesEq(abi.encode(h1, c1, d1), abi.encode(h0, c0, d0), "reward-only fault rolls the ledger back intact");
        assertEq(uint8(W.b.getReport(W.id).phase), uint8(Phase.Rewarded), "reward-only fault keeps the phase");
        assertEq(W.b.getReport(W.id).rewardCredit, bHalf, "reward-only fault keeps the credit");
        assertEq(crvUSD.balanceOf(reporter), rep0, "reward-only fault pays nothing");
        (uint256 s1, uint256 r1) = W.b.claim(W.id);
        assertEq(s1, 0, "reward-only retry pays no second bond");
        assertEq(r1, bHalf, "reward-only retry pays the exact funded reward");
        assertEq(crvUSD.balanceOf(reporter) - rep0, bHalf, "reward-only retry: exact money moved once");
        (uint256 s2, uint256 r2) = W.b.claim(W.id);
        assertEq(s2 + r2, 0, "reward-only: nothing left after the single retry");
        (, uint256 c2,) = W.b.accounting();
        assertEq(c2, 0, "reward-only: credit liability cleared");
    }

    /// @dev Bond FORFEITED first (markFrivolous is the sole exception), then
    /// the funded reward claim faults and retries: still exactly (0, B) —
    /// forfeiture never vetoes the legitimate reward and the rollback keeps
    /// the forfeit-side liability and the credit intact.
    function _rewardOnlyFaultedClaimAfterBondForfeited() private {
        Live memory W = _recognizedWorldDominant();
        vm.prank(daoOwner);
        assertTrue(W.b.markFrivolous(W.id), "forfeit-only reward cell: bond forfeited");
        uint256 bHalf = _fundRewardOnly(W);
        (uint256 h0, uint256 c0, uint256 d0) = W.b.accounting();
        assertEq(c0, bHalf, "forfeit-only reward cell: reward funded despite forfeit");
        assertEq(d0, STAKE, "forfeit-only reward cell: FD liability reserved");
        uint256 rep0 = crvUSD.balanceOf(reporter);
        crvUSD.setTransferBehavior(0, true, false);
        vm.expectRevert(abi.encodeWithSelector(SafeToken.SafeTokenBadReturn.selector, address(crvUSD)));
        W.b.claim(W.id);
        crvUSD.setTransferBehavior(0, false, false);
        (uint256 h1, uint256 c1, uint256 d1) = W.b.accounting();
        bytesEq(abi.encode(h1, c1, d1), abi.encode(h0, c0, d0), "forfeit reward fault rolls back intact");
        assertEq(W.b.getReport(W.id).rewardCredit, bHalf, "forfeit reward fault keeps the credit");
        assertEq(uint8(W.b.getReport(W.id).phase), uint8(Phase.Rewarded), "forfeit reward fault keeps the phase");
        assertEq(crvUSD.balanceOf(reporter), rep0, "forfeit reward fault pays nothing");
        (uint256 sf, uint256 rf) = W.b.claim(W.id);
        assertEq(sf, 0, "forfeit reward retry pays no bond: the forfeit stands");
        assertEq(rf, bHalf, "forfeit reward retry pays the exact funded reward");
        assertEq(crvUSD.balanceOf(reporter) - rep0, bHalf, "forfeit reward retry: exact money moved once");
        (,, uint256 d2) = W.b.accounting();
        assertEq(d2, STAKE, "forfeit liability intact through the retry");
    }

    function _claimFaultCell(uint16 feeBps, bool retFalse, bool noReturn) private {
        Live memory M = _recognizedWorld();
        require(uint8(M.b.getReport(M.id).stakeState) == uint8(StakeState.Refundable), "money: refundable pre-fault");
        crvUSD.setTransferBehavior(feeBps, retFalse, noReturn);
        uint256 rep0 = crvUSD.balanceOf(reporter);
        if (retFalse || feeBps > 0) {
            if (retFalse) {
                vm.expectRevert(abi.encodeWithSelector(SafeToken.SafeTokenBadReturn.selector, address(crvUSD)));
            } else {
                vm.expectRevert(IGaugeBounty.TokenDeltaMismatch.selector);
            }
            M.b.claim(M.id);
            assertEq(crvUSD.balanceOf(reporter), rep0, "fault pays nothing");
            assertEq(uint8(M.b.getReport(M.id).stakeState), uint8(StakeState.Refundable), "state restored by rollback");
            (uint256 held,,) = M.b.accounting();
            assertEq(held, STAKE, "bucket restored by rollback");
            crvUSD.setTransferBehavior(0, false, false);
            (uint256 stakeM,) = M.b.claim(M.id);
            assertEq(stakeM, STAKE, "recovery claim pays exactly");
            assertEq(crvUSD.balanceOf(reporter) - rep0, STAKE, "single payment after fault");
        } else {
            (uint256 stakeE,) = M.b.claim(M.id);
            assertEq(stakeE, STAKE, "empty-return token still pays exactly");
            crvUSD.setTransferBehavior(0, false, false);
        }
    }

    struct FaultWorld {
        GaugeBounty b;
        ReentrantToken token;
        bytes32 t1;
        bytes32 t2;
    }

    /// @dev Bounty whose stake asset is a switchable fault token: two
    /// locally-expired (Refundable) cases exercise the malformed return and
    /// the re-entrant payout.
    function _tokenFaultWorldCell() private {
        FaultWorld memory w = _buildFaultWorld();
        _malformedReturnCell(w);
        _reentrantPayoutCell(w);
    }

    function _malformedReturnCell(FaultWorld memory w) private {
        ReportView memory rv1 = w.b.getReport(w.t1);
        vm.warp(rv1.executeBy + 1);
        assertTrue(w.b.resolve(w.t1), "t1 locally expired");

        // Malformed return: strict SafeToken rejects it; state survives.
        w.token.setMalformedReturn(true);
        vm.expectRevert(abi.encodeWithSelector(SafeToken.SafeTokenBadReturn.selector, address(w.token)));
        w.b.claim(w.t1);
        assertEq(uint8(w.b.getReport(w.t1).stakeState), uint8(StakeState.Refundable), "malformed: state retained");
        (uint256 heldW,,) = w.b.accounting();
        assertEq(heldW, 3 * STAKE, "malformed: seed + t1 + t2 bonds all held");
        w.token.setMalformedReturn(false);
        (uint256 stakeT1,) = w.b.claim(w.t1);
        assertEq(stakeT1, STAKE, "malformed: recovery pays exactly");
    }

    function _reentrantPayoutCell(FaultWorld memory w) private {
        ReportView memory rv2 = w.b.getReport(w.t2);
        vm.warp(rv2.executeBy + 1);
        assertTrue(w.b.resolve(w.t2), "t2 locally expired");
        w.token.armAttack(address(w.b), abi.encodeCall(GaugeBounty.claim, (w.t2)), true, false);
        uint256 rep0 = w.token.balanceOf(reporter);
        (uint256 stakeT2,) = w.b.claim(w.t2);
        assertEq(stakeT2, STAKE, "outer claim completes exactly once");
        assertEq(w.token.balanceOf(reporter) - rep0, STAKE, "single payment");
        assertFalse(w.token.lastReentryReturned(), "re-entrant claim refused by the guard");
        (uint256 stakeT2b, uint256 rewT2b) = w.b.claim(w.t2);
        assertEq(stakeT2b, 0, "claim is dependency-free and empty on repeat");
        assertEq(rewT2b, 0, "empty repeat reward");
    }

    ReentrantToken internal _faultTk;

    function _buildFaultWorld() private returns (FaultWorld memory w) {
        ReentrantToken token = new ReentrantToken(18);
        _faultTk = token;
        (GaugeBounty b2, CurveGaugeListerV2 core2) = _deployFaultPair(token);
        address gS = _faultList(token, core2);
        bytes32 idSeed = _proposedTokenCase(b2, gS);
        idSeed;
        address g1 = _faultList(token, core2);
        (bytes32 t1,) = _tokenCase(b2, g1, reporter);
        address g2 = _faultList(token, core2);
        (bytes32 t2,) = _tokenCase(b2, g2, reporter);
        w.b = b2;
        w.token = token;
        w.t1 = t1;
        w.t2 = t2;
    }

    function _deployFaultPair(ReentrantToken token) private returns (GaugeBounty b2, CurveGaugeListerV2 core2) {
        MockFeeDistributor fd2 = new MockFeeDistributor(address(token), fdAdmin, block.timestamp);
        MockIncentivePlatform platV = new MockIncentivePlatform(address(token));
        MockIncentivePlatform platM = new MockIncentivePlatform(address(token));
        MockListingController ctl2 = new MockListingController(controllerDao, int128(2));
        BountyConfig memory cfg = defaultBountyConfig();
        cfg.crvUSD = address(token);
        cfg.feeDistributor = address(fd2);
        b2 = new GaugeBounty(cfg);
        core2 = new CurveGaugeListerV2(
            address(agent), // initial owner == configured Agent (thin §2.1)
            address(token),
            address(ctl2),
            address(fd2),
            CurveGaugeListerV2.AdmissionConfig(address(registry), 8),
            CurveGaugeListerV2.PlatformConfig(address(platV), address(platM), 5000),
            address(b2),
            address(tfValidator)
        );
        platV.setLister(address(core2));
        platM.setLister(address(core2));
        vm.prank(controllerDao);
        ctl2.setLister(address(core2));
        vm.prank(address(agent));
        b2.bindLister(address(core2));
        vm.prank(address(agent));
        core2.transferOwnership(daoOwner);
        vm.prank(daoOwner);
        core2.acceptOwnership();
        vm.prank(daoOwner);
        core2.setPaused(false);
        _pairOf[b2] = core2;
    }

    /// @dev One registry-authenticated, PAID listing for the fault world
    /// (no registration exists any more; the live route is re-checked).
    function _faultList(ReentrantToken token, CurveGaugeListerV2 core2) private returns (address gauge) {
        (address pool, address g,) = deployGovernanceGauge();
        uint256 slot = lastSlot;
        token.mint(payer, FEE);
        vm.startPrank(payer);
        token.approve(address(core2), FEE);
        core2.listGauge(pool, g, 0, slot);
        vm.stopPrank();
        require(core2.getListing(g).status == 1, "fault listing active");
        return g;
    }

    function _proposedTokenCase(GaugeBounty b, address gauge) private returns (bytes32 id) {
        bool created;
        (id, created) = _tokenCase(b, gauge, reporter);
        require(created, "money: token head creates");
    }

    function _tokenCase(GaugeBounty b, address gauge, address who) private returns (bytes32 id, bool created) {
        bytes32 eh = keccak256(abi.encode("fault-evidence", who, gauge, _seq));
        _seq += 1;
        vm.startPrank(who);
        _faultTk.mint(who, STAKE);
        _faultTk.approve(address(b), STAKE);
        vm.stopPrank();
        uint256 pid;
        (id, pid) = createBeneficiaryBallot(b, address(coreOf(b)), gauge, who, who, _seq, eh);
        vm.prank(who);
        id = b.submit(gauge, pid, eh, _seq);
        created = uint8(b.getReport(id).phase) == uint8(Phase.Proposed);
    }

    // ----------------------------------------------------------------- M09

    function test_Thin_FlushReservedStakeOnly() public {
        // Two forfeitures reserve exactly 2,000 of FD liability.
        (CurveGaugeListerV2 core_, GaugeBounty b) = deployBoundPair();
        _pairOf[b] = core_;
        (, address g1,) = listBountyEligible(core_);
        (bytes32 id1,) = _thinSubmit(b, reporter, g1);
        (, address g2,) = listBountyEligible(core_);
        (bytes32 id2,) = _thinSubmit(b, secondReporter, g2);
        vm.prank(daoOwner);
        assertTrue(b.markFrivolous(id1), "forfeit one");
        vm.prank(daoOwner);
        assertTrue(b.markFrivolous(id2), "forfeit two");
        (,, uint256 dao) = b.accounting();
        assertEq(dao, 2 * STAKE, "reserved liability");

        // Unsolicited income is surplus, never flushable through daoLiability.
        crvUSD.mint(address(b), 555e18);

        // Bounds: zero and over-liability revert with BadAmount from ANY
        // caller (the flush keeper is permissionless, not a role).
        vm.prank(stranger);
        vm.expectRevert(IGaugeBounty.BadAmount.selector);
        b.flushDao(0);
        vm.expectRevert(IGaugeBounty.BadAmount.selector);
        b.flushDao(2 * STAKE + 1);
        vm.prank(actor("otherKeeper"));
        vm.expectRevert(IGaugeBounty.BadAmount.selector);
        b.flushDao(2 * STAKE + 555e18);

        // Permissionless exact flush to the PINNED FD with mandatory
        // same-transaction accounting.
        uint256 b0 = crvUSD.balanceOf(address(b));
        uint256 f0 = crvUSD.balanceOf(address(fd));
        uint256 calls0 = fd.checkpointCalls();
        _spaceFdCursor();
        assertEq(b.flushDao(STAKE), STAKE, "flush reports the amount");
        assertEq(crvUSD.balanceOf(address(fd)) - f0, STAKE, "pinned FD received exactly");
        assertEq(b0 - crvUSD.balanceOf(address(b)), STAKE, "bounty debited exactly");
        (,, uint256 daoMid) = b.accounting();
        assertEq(daoMid, STAKE, "liability decremented once");
        assertEq(fd.checkpointCalls(), calls0 + 1, "accounting ran");
        assertEq(fd.last_token_time(), block.timestamp, "cursor moved");
        assertEq(fd.token_last_balance(), crvUSD.balanceOf(address(fd)), "accounted balance");
        assertEq(crvUSD.allowance(address(b), address(fd)), 0, "no approval to the FD (no pooled burn)");

        // A second, independent keeper completes the aggregate.
        _spaceFdCursor();
        vm.prank(actor("secondKeeper"));
        assertEq(b.flushDao(STAKE), STAKE, "second flush");
        (,, uint256 daoEnd) = b.accounting();
        assertEq(daoEnd, 0, "liability exhausted");
        vm.expectRevert(IGaugeBounty.BadAmount.selector);
        b.flushDao(1);
        // The 555 donation remains unspendable surplus at the bounty.
        assertEq(crvUSD.balanceOf(address(b)), 555e18, "surplus untouched by flushes");
    }

    // ----------------------------------------------------------------- M10

    function test_Thin_FlushFailureDoesNotDelayOthers() public {
        // One reporter: recognized, bond refundable AND reward funded.
        Live memory L = _recognizedWorld();
        uint256 rem = L.core_.getListing(L.gauge).remaining;
        _spaceFdCursor();
        vm.prank(stranger);
        L.core_.confiscate(L.gauge);
        assertEq(L.b.getReport(L.id).rewardCredit, rem / 2, "reward funded");
        // Another reporter: forfeited bond becomes the FD liability.
        (, address gF,) = listBountyEligible(L.core_);
        (bytes32 idF,) = _thinSubmit(L.b, secondReporter, gF);
        vm.prank(daoOwner);
        assertTrue(L.b.markFrivolous(idF), "forfeit second reporter");
        (,, uint256 daoR) = L.b.accounting();
        assertEq(daoR, STAKE, "reserved");

        // Every FD-unavailable shape fails the flush closed, liability intact.
        _flushFailCell(L, "stale");
        _flushFailCell(L, "cooldown");
        _flushFailCell(L, "killed");

        // None of that delayed the other reporter's money or the project CRV:
        // bond and reward claims move without any FD dependency.
        assertEq(crv.balanceOf(address(L.b)), 0, "project CRV untouched before");
        (int128 lamt, uint256 lend) = escrow.locked(address(L.b));
        (uint256 stakeL, uint256 rewardL) = L.b.claim(L.id);
        assertEq(stakeL, STAKE, "bond claim survives every FD failure");
        assertEq(rewardL, rem / 2, "reward claim survives every FD failure, same call");
        (int128 lamt2, uint256 lend2) = escrow.locked(address(L.b));
        assertEq(uint256(int256(lamt2)), uint256(int256(lamt)), "lock principal intact");
        assertEq(lend2, lend, "lock end intact");
        assertEq(crv.balanceOf(address(L.b)), 0, "project CRV untouched after");

        // The reserved liability is not lost: a healthy FD flushes it later.
        _spaceFdCursor();
        vm.prank(stranger);
        assertEq(L.b.flushDao(STAKE), STAKE, "delayed safe flush");
        (,, uint256 daoZ) = L.b.accounting();
        assertEq(daoZ, 0, "flushed exactly once");
    }

    function _flushFailCell(Live memory L, string memory mode) private {
        uint256 saved = fd.last_token_time();
        if (keccak256(bytes(mode)) == keccak256("stale")) {
            fd.setLastTokenTime(block.timestamp - 41 * WEEK); // beyond 20 weeks
            vm.expectRevert(FeeDistributorAccounting.DistributorUnusable.selector);
            L.b.flushDao(STAKE);
            fd.setLastTokenTime(saved);
        } else if (keccak256(bytes(mode)) == keccak256("cooldown")) {
            fd.setLastTokenTime(block.timestamp - 3600); // inside the 1-day gate
            vm.expectRevert(MockFeeDistributor.CannotCheckpoint.selector);
            L.b.flushDao(STAKE);
        } else {
            fd.setKilled(true);
            vm.expectRevert(FeeDistributorAccounting.DistributorUnusable.selector);
            L.b.flushDao(STAKE);
            fd.setKilled(false);
        }
        (,, uint256 daoAfter) = L.b.accounting();
        assertEq(daoAfter, STAKE, "liability retained by the failed flush");
    }
}
