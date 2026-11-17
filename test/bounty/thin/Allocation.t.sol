// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BountyFixture} from "../BountyFixture.sol";
import {Vm} from "../../TestBase.sol";
import {GaugeBounty} from "../../../contracts/GaugeBounty.sol";
import {CurveGaugeListerV2} from "../../../contracts/CurveGaugeListerV2.sol";
import {IGaugeBounty} from "../../../contracts/interfaces/IGaugeBounty.sol";
import {ICurveGaugeListerV2} from "../../../contracts/interfaces/ICurveGaugeListerV2.sol";
import {IERC20Minimal} from "../../../contracts/interfaces/IERC20Minimal.sol";
import {ReportView, StakeState, Phase} from "../../../contracts/bounty/BountyTypes.sol";
import {GovernanceGauge} from "../mocks/MockBountyGovernance.sol";
import {MockFeeDistributor} from "../../../contracts/mocks/MockFeeDistributor.sol";
import {FeeDistributorAccounting} from "../../../contracts/libraries/FeeDistributorAccounting.sol";

/// @notice Thin allocation suite (plans/BOUNTY-THIN-PLAN.md §7.2 rows
/// A01–A08): actual unreleased remainder R, B = floor(R/2) to the reporter
/// via the bound bounty, F = R - B to the pinned FD, both seizure entry
/// points through the single routine, all-or-nothing rollback, exact once
/// credits, the accepted FD accounting policy, terminal/weight independence,
/// and a stateful custody-conservation fuzz with an independent ledger.
contract ThinAllocationTest is BountyFixture {
    struct Pair {
        CurveGaugeListerV2 core_;
        GaugeBounty b;
    }

    uint256 internal _seq = 1;
    uint256 internal _whale = 1;

    function setUp() public {
        setupBountyWorld();
    }

    // ---------------------------------------------------------------- glue

    function _pair() internal returns (Pair memory P) {
        (P.core_, P.b) = deployBoundPair();
    }

    function _fundStake(GaugeBounty b, address who) internal {
        crvUSD.mint(who, STAKE);
        approveCrvUsd(who, address(b), STAKE);
    }

    /// @dev Release n real quarters BEFORE proposing (a killed gauge would
    /// confiscate inside checkpoint itself).
    function _drip(Pair memory P, address gauge, uint256 n) internal {
        uint256 start = P.core_.getListing(gauge).listingEpoch;
        for (uint256 q = 1; q <= n; ++q) {
            vm.warp(start + q * WEEK);
            (uint256 rel, uint256 conf) = P.core_.checkpoint(gauge);
            require(conf == 0 && rel == QUARTER, "pre-kill drip");
        }
    }

    function _proposed(Pair memory P, address gauge) internal returns (bytes32 id, uint256 voteId) {
        bytes32 eh = keccak256(abi.encode("alloc-evidence", gauge, _seq));
        _seq += 1;
        (id, voteId) = submitBeneficiaryBallot(P.b, address(P.core_), gauge, reporter, _seq, eh);
        require(uint8(P.b.getReport(id).phase) == uint8(Phase.Proposed), "alloc: admitted");
    }

    /// @dev Honest ballot pass + execute through the real script: false ->
    /// true attribution with the middle proxy kill.
    function _recognize(Pair memory P, bytes32 id, uint256 voteId) internal {
        address whale = address(uint160(0xA11CEA00 + _whale++));
        // Power must clear the STRICT support and quorum ratios against the
        // accumulated total supply of the shared escrow model.
        giveVePower(whale, (escrow.totalSupply() + 1e18) * 3);
        vm.prank(whale);
        voting.vote(voteId, true);
        vm.warp(P.b.getReport(id).voteEnd);
        vm.prank(stranger);
        voting.executeVote(voteId);
    }

    function _spaceFdCursor() internal {
        if (block.timestamp <= fd.last_token_time() + 86_400) {
            fd.setLastTokenTime(block.timestamp - 86_401);
        }
    }

    struct Snap {
        uint256 v2Bal;
        uint256 bountyBal;
        uint256 fdBal;
        uint256 totalEscrow;
        uint256 fdCalls;
        ICurveGaugeListerV2.ListingV2 listing;
    }

    function _snap(Pair memory P, address gauge) internal view returns (Snap memory x) {
        x.v2Bal = crvUSD.balanceOf(address(P.core_));
        x.bountyBal = crvUSD.balanceOf(address(P.b));
        x.fdBal = crvUSD.balanceOf(address(fd));
        x.totalEscrow = P.core_.totalEscrow();
        x.fdCalls = fd.checkpointCalls();
        x.listing = P.core_.getListing(gauge);
    }

    function _expectNoDrift(Pair memory P, address gauge, Snap memory pre, string memory label) internal view {
        Snap memory post = _snap(P, gauge);
        assertEq(post.v2Bal, pre.v2Bal, label);
        assertEq(post.bountyBal, pre.bountyBal, label);
        assertEq(post.fdBal, pre.fdBal, label);
        assertEq(post.totalEscrow, pre.totalEscrow, label);
        assertEq(post.fdCalls, pre.fdCalls, label);
        assertEq(uint8(post.listing.status), uint8(pre.listing.status), label);
        assertEq(post.listing.remaining, pre.listing.remaining, label);
        assertEq(post.listing.reporterReward, pre.listing.reporterReward, label);
        assertEq(post.listing.fdConfiscated, pre.listing.fdConfiscated, label);
        assertEq(post.listing.rewardReportId, pre.listing.rewardReportId, label);
        assertEq(crvUSD.allowance(address(P.core_), address(P.b)), 0, label);
    }

    // ----------------------------------------------------------------- A01

    function test_Thin_ActualRemainderHalfSplit() public {
        // n = 0..3 actually funded quarters; B = floor((FEE - n*QUARTER)/2).
        for (uint256 n = 0; n <= 3; ++n) {
            Pair memory P = _pair();
            (, address gauge,) = listBountyEligible(P.core_);
            _drip(P, gauge, n);
            (bytes32 id, uint256 voteId) = _proposed(P, gauge);
            _recognize(P, id, voteId);
            uint256 r = FEE - QUARTER * n;
            assertEq(P.core_.getListing(gauge).remaining, r, "actual unreleased remainder");

            _spaceFdCursor();
            uint256 bountyBefore = crvUSD.balanceOf(address(P.b));
            uint256 fdBefore = crvUSD.balanceOf(address(fd));
            vm.recordLogs();
            vm.prank(stranger);
            uint256 gross = P.core_.confiscate(gauge);
            Vm.Log[] memory logs = vm.getRecordedLogs();
            assertEq(gross, r, "gross is the remainder, never the quote");
            ICurveGaugeListerV2.ListingV2 memory ls = P.core_.getListing(gauge);
            assertEq(ls.status, 3, "Confiscated");
            assertEq(ls.reporterReward, r / 2, "B = floor(R/2)");
            assertEq(ls.fdConfiscated, r - r / 2, "F = R - B");
            assertEq(ls.reporterReward + ls.fdConfiscated, ls.confiscated, "B+F = gross");
            assertEq(ls.confiscated, r, "recorded gross");
            assertEq(crvUSD.balanceOf(address(P.b)) - bountyBefore, r / 2, "bounty funded exactly B");
            assertEq(crvUSD.balanceOf(address(fd)) - fdBefore, r - r / 2, "FD got exactly F");
            assertEq(P.core_.totalEscrow(), 0, "escrow drained");
            // The versioned event carries the buckets.
            assertTrue(
                hasEventFrom(
                    logs,
                    address(P.core_),
                    sig("EscrowConfiscated(address,address,bytes32,uint256,uint256,uint256,uint256)")
                ),
                "versioned confiscation event"
            );
            (, uint256 credits,) = P.b.accounting();
            assertEq(credits, r / 2, "rewardCredits counts only the funded reward");
            (uint256 st, uint256 rw) = P.b.claim(id);
            assertEq(st, STAKE, "bond refunds immediately");
            assertEq(rw, r / 2, "reporter half claims once");
            (uint256 st2, uint256 rw2) = P.b.claim(id);
            assertEq(st2 + rw2, 0, "never twice");
        }

        // Zero-remainder ending: recognized but unkill'd, the normal release
        // exhausts the listing before any seizure; resolve closes NoAward.
        Pair memory P = _pair();
        (, address gauge,) = listBountyEligible(P.core_);
        (bytes32 id, uint256 voteId) = _proposed(P, gauge);
        _recognize(P, id, voteId);
        // Authorized unkill so releases may run to exhaustion.
        vm.prank(address(killProxy));
        GovernanceGauge(gauge).set_killed(false);
        assertEq(uint8(Phase.Recognized), uint256(P.b.getReport(id).phase), "still Recognized after unkill");
        uint256 start = P.core_.getListing(gauge).listingEpoch;
        for (uint256 q = 1; q <= 4; ++q) {
            vm.warp(start + q * WEEK);
            P.core_.checkpoint(gauge);
        }
        assertEq(P.core_.getListing(gauge).status, 2, "Exhausted terminal");
        assertTrue(P.b.resolve(id), "observed terminal closes NoAward");
        assertEq(uint8(Phase.NoAward), uint256(P.b.getReport(id).phase), "NoAward");
        assertEq(P.b.getReport(id).rewardCredit, 0, "no allocation invented");
        assertEq(P.core_.getListing(gauge).reporterReward, 0, "listing has no reporter bucket");
        assertEq(P.core_.getListing(gauge).fdConfiscated, 0, "no FD bucket either");
        (uint256 st,) = P.b.claim(id);
        assertEq(st, STAKE, "stake was already refundable at recognition");

        // bountyreworkfix C3(d) (RW-W terminal-unpaid-entitlement latch):
        // the claim-site latch check is a DIFFERENT site. At THIS terminal
        // unpaid closure — recognized -> unkill -> normal exhaustion ->
        // NoAward -> exact bond refund — the old winner ID/reporter must
        // remain permanently latched and unreplaceable.
        (bytes32 lidNow, address repNow, bool eligNow) = P.b.rewardTerms(gauge);
        assertEq(lidNow, id, "terminal closure keeps the old winner latched");
        assertEq(repNow, reporter, "terminal closure keeps the old reporter latched");
        assertFalse(eligNow, "consumed entitlement is not re-eligible");
        // Unreplaceable: a new report is refused on the latched listing
        // forever, and re-running the authorized callbacks on the closed
        // case cannot resurrect, duplicate or overwrite anything.
        vm.prank(secondReporter);
        vm.expectRevert(IGaugeBounty.IneligibleGauge.selector);
        P.b.submit(gauge, 0, keccak256("post-closure"), 9101);
        vm.prank(address(agent));
        P.b.creditBallot(id, reporter);
        vm.prank(address(agent));
        P.b.recognizeKill(id);
        assertEq(uint8(Phase.NoAward), uint256(P.b.getReport(id).phase), "terminal closure cannot resurrect");
        (uint256 st2, uint256 rw2) = P.b.claim(id);
        assertEq(st2 + rw2, 0, "bond paid once, no invented reward");
        (bytes32 lidAfter, address repAfter, bool eligAfter) = P.b.rewardTerms(gauge);
        assertEq(lidAfter, id, "old winner ID immutable at the terminal closure site");
        assertEq(repAfter, reporter, "old reporter immutable at the terminal closure site");
        assertFalse(eligAfter, "no re-eligibility after the terminal unpaid closure");
        assertEq(uint8(P.b.getReport(id).phase), uint8(Phase.NoAward), "phase stays terminal");
    }

    // ----------------------------------------------------------------- A02

    function test_Thin_BothSeizureEntryPoints() public {
        // Two identically shaped cases: one seized through checkpoint()'s
        // catch-up path, one through confiscate(); buckets and custody are
        // identical and a stranger's earlier call cannot redirect or avoid B.
        Pair memory PA = _pair();
        Pair memory PB = PA; // same world, two gauges
        (, address gA,) = listBountyEligible(PA.core_);
        (, address gB,) = listBountyEligible(PB.core_);
        _drip(PA, gA, 1);
        _drip(PB, gB, 1);
        (bytes32 idA, uint256 vA) = _proposed(PA, gA);
        vm.warp(block.timestamp + COOLDOWN);
        (bytes32 idB, uint256 vB) = _proposed(PB, gB);
        _recognize(PA, idA, vA);
        _recognize(PB, idB, vB);

        // A: seize via checkpoint (a second quarter becomes due at the same
        // time the true flag is observed).
        vm.warp(PA.core_.getListing(gA).listingEpoch + 2 * WEEK);
        _spaceFdCursor();
        (, uint256 confA) = PA.core_.checkpoint(gA);
        // B: seize via confiscate at the same schedule point.
        vm.warp(PB.core_.getListing(gB).listingEpoch + 2 * WEEK);
        _spaceFdCursor();
        uint256 confB = PB.core_.confiscate(gB);

        ICurveGaugeListerV2.ListingV2 memory la = PA.core_.getListing(gA);
        ICurveGaugeListerV2.ListingV2 memory lb = PB.core_.getListing(gB);
        assertEq(confA, confB, "same gross through both entries");
        assertEq(la.reporterReward, lb.reporterReward, "same B");
        assertEq(la.fdConfiscated, lb.fdConfiscated, "same F");
        assertEq(la.status, 3, "A confiscated");
        assertEq(lb.status, 3, "B confiscated");
        // The stranger who called first never redirected anything: stored
        // reporters were paid.
        (uint256 stakeA, uint256 rewardA) = PA.b.claim(idA);
        assertEq(stakeA, STAKE, "A bond to stored reporter");
        (, uint256 rewardB) = PB.b.claim(idB);
        assertEq(rewardB, lb.reporterReward, "B reward to stored reporter");
        assertEq(rewardA, la.reporterReward, "A reward to stored reporter");
        assertEq(crvUSD.balanceOf(stranger), 0, "front-runner captured nothing");
    }

    // ----------------------------------------------------------------- A03

    function test_Thin_MidCatchUpSplit() public {
        // Complete an earlier quarter, then genuine canonical recognition
        // splits only the remaining escrow: later scheduled quarters never
        // leave escrow after the terminal state.
        Pair memory P = _pair();
        (, address gauge,) = listBountyEligible(P.core_);
        _drip(P, gauge, 1);
        uint256 votiumDepositsBefore = votium.depositCount();
        (bytes32 id, uint256 voteId) = _proposed(P, gauge);
        _recognize(P, id, voteId);
        _spaceFdCursor();
        vm.prank(actor("randomCaller"));
        uint256 gross = P.core_.confiscate(gauge);
        uint256 r = FEE - QUARTER; // only the ONE funded quarter reduced R
        assertEq(gross, r, "split is the remaining escrow only");
        assertEq(P.core_.getListing(gauge).reporterReward, r / 2, "B");
        assertEq(P.core_.getListing(gauge).fdConfiscated, r - r / 2, "F");
        // The venue received exactly the one funded quarter, nothing more.
        assertEq(
            votium.depositCount(),
            votiumDepositsBefore,
            "seizure adds no venue deposits; the earlier quarter stays funded"
        );
        (uint256 depAmount,,) = votium.getDeposit(gauge, P.core_.getListing(gauge).listingEpoch + WEEK);
        assertEq(depAmount, QUARTER / 2, "votium share of the funded quarter at 5000 bps");
        assertEq(P.core_.totalEscrow(), 0, "escrow fully accounted");
        assertEq(crvUSD.balanceOf(address(P.core_)), 0, "no escrow left behind");
        (, uint256 credits,) = P.b.accounting();
        assertEq(credits, r / 2, "credit equals B");
    }

    // ----------------------------------------------------------------- A04

    function test_Thin_LaterFailureRollsBackEverything() public {
        // After one earlier funded quarter, every later-leg fault must revert
        // the WHOLE seizure: balances, listing, receipts, credits, allowances.
        Pair memory P = _pair();
        (, address gauge,) = listBountyEligible(P.core_);
        _drip(P, gauge, 1);
        (bytes32 id, uint256 voteId) = _proposed(P, gauge);
        _recognize(P, id, voteId);
        uint256 r = FEE - QUARTER;

        // (a) FD checkpoint reverts after the F transfer leg.
        Snap memory pre = _snap(P, gauge);
        fd.setCheckpointRevert(true);
        vm.prank(stranger);
        vm.expectRevert(MockFeeDistributor.CheckpointFailed.selector);
        P.core_.confiscate(gauge);
        fd.setCheckpointRevert(false);
        _expectNoDrift(P, gauge, pre, "checkpoint-revert no drift");

        // (b) crvUSD transfer tax on the funded B pull.
        pre = _snap(P, gauge);
        crvUSD.setTransferBehavior(25, false, false);
        vm.prank(stranger);
        vm.expectRevert();
        P.core_.confiscate(gauge);
        crvUSD.setTransferBehavior(0, false, false);
        _expectNoDrift(P, gauge, pre, "taxed-pull no drift");

        // (c) FD cursor read reverts (preflight) / returns malformed.
        pre = _snap(P, gauge);
        fd.setCursorReadMode(1);
        vm.prank(stranger);
        vm.expectRevert(MockFeeDistributor.CursorReadFailed.selector);
        P.core_.confiscate(gauge);
        fd.setCursorReadMode(2);
        vm.prank(stranger);
        vm.expectRevert();
        P.core_.confiscate(gauge);
        fd.setCursorReadMode(0);
        _expectNoDrift(P, gauge, pre, "cursor faults no drift");

        // (d) no-op accounting: checkpoint returns without moving buckets.
        pre = _snap(P, gauge);
        fd.setCheckpointMode(1);
        vm.prank(stranger);
        vm.expectRevert(FeeDistributorAccounting.DistributorUnusable.selector);
        P.core_.confiscate(gauge);
        fd.setCheckpointMode(2);
        vm.prank(stranger);
        vm.expectRevert(FeeDistributorAccounting.DistributorUnusable.selector);
        P.core_.confiscate(gauge);
        fd.setCheckpointMode(0);
        _expectNoDrift(P, gauge, pre, "no-op accounting no drift");

        // Healthy retry settles exactly once afterwards.
        _spaceFdCursor();
        vm.prank(stranger);
        assertEq(P.core_.confiscate(gauge), r, "retry gross exact");
        (, uint256 credits,) = P.b.accounting();
        assertEq(credits, r / 2, "funded once");
        (, uint256 reward) = P.b.claim(id);
        assertEq(reward, r / 2, "paid once");
        (, uint256 rewardAgain) = P.b.claim(id);
        assertEq(rewardAgain, 0, "never twice");
    }

    // ----------------------------------------------------------------- A05

    function test_Thin_ExactListerCreditOnce() public {
        Pair memory P = _pair();
        (, address gauge,) = listBountyEligible(P.core_);
        (bytes32 id, uint256 voteId) = _proposed(P, gauge);
        _recognize(P, id, voteId);
        uint256 r = FEE;

        // Wrong authority: EOA and stranger cannot credit.
        vm.prank(stranger);
        vm.expectRevert(IGaugeBounty.NotLister.selector);
        P.b.creditReward(id, r / 2);

        // Before the terminal write: phase Recognized but listing still
        // Active -> the independent verification refuses.
        vm.prank(address(P.core_));
        vm.expectRevert(IGaugeBounty.BadConfiguration.selector);
        P.b.creditReward(id, r / 2);

        // From the bound lister with a tampered amount BEFORE the terminal
        // write: the independent verification refuses (no allocation yet).
        vm.prank(address(P.core_));
        vm.expectRevert(IGaugeBounty.BadConfiguration.selector);
        P.b.creditReward(id, r / 2 - 1);
        vm.prank(address(P.core_));
        vm.expectRevert(IGaugeBounty.BadAmount.selector);
        P.b.creditReward(id, 0);
        vm.prank(address(P.core_));
        vm.expectRevert(IGaugeBounty.UnknownReport.selector);
        P.b.creditReward(keccak256("not-a-report"), r / 2);

        // Real seizure happens.
        _spaceFdCursor();
        vm.prank(stranger);
        P.core_.confiscate(gauge);

        // Replay after the legitimate credit: BadPhase (one lifetime credit).
        (uint256 stake0, uint256 reward0) = P.b.claim(id);
        assertEq(stake0, STAKE, "bond paid");
        assertEq(reward0, r / 2, "legit credit paid once, same call");
        vm.prank(address(P.core_));
        vm.expectRevert(IGaugeBounty.BadPhase.selector);
        P.b.creditReward(id, r / 2);

        // Donations cannot inflate anything: top up V2 and re-seize a fresh
        // terminal case; pulls stay exactly B/F per its own remainder.
        crvUSD.mint(address(P.core_), 777e18);
        vm.warp(block.timestamp + COOLDOWN); // clear the shared creator interval
        bytes32 id3;
        bool made3;
        address g3;
        (id3, made3) = _submitNoCreate(P, reporter, _listFresh(P));
        made3;
        g3 = P.b.getReport(id3).gauge;
        require(uint8(P.b.getReport(id3).phase) == uint8(Phase.Proposed), "case3 admitted");
        _recognize(P, id3, P.b.getReport(id3).proposalId);
        _spaceFdCursor();
        vm.prank(stranger);
        uint256 gross3 = P.core_.confiscate(g3);
        assertEq(gross3, FEE, "own remainder only");
        assertEq(crvUSD.balanceOf(address(P.core_)), 777e18, "donation retained, escrow paid out");
        (, uint256 rew3) = P.b.claim(id3);
        assertEq(rew3, gross3 / 2, "exact half once");
    }

    function _submitNoCreate(Pair memory P, address who, address gauge) internal returns (bytes32 id, bool created) {
        bytes32 eh = keccak256(abi.encode("alloc5-evidence", gauge, _seq));
        _seq += 1;
        (id,) = submitBeneficiaryBallot(P.b, address(P.core_), gauge, who, _seq, eh);
        created = uint8(P.b.getReport(id).phase) == uint8(Phase.Proposed);
    }

    function _listFresh(Pair memory P) internal returns (address) {
        (, address g,) = listBountyEligible(P.core_);
        return g;
    }

    // ----------------------------------------------------------------- A06

    function test_Thin_FeeDistributorSafety() public {
        Pair memory P = _pair();
        (, address gauge,) = listBountyEligible(P.core_);
        (bytes32 id, uint256 voteId) = _proposed(P, gauge);
        _recognize(P, id, voteId);
        uint256 r = FEE;

        // Forty-week raw-loss control: stale FD refuses with nothing moved.
        Snap memory pre = _snap(P, gauge);
        uint256 saved = fd.last_token_time();
        fd.setLastTokenTime(block.timestamp - 40 * WEEK);
        vm.prank(stranger);
        vm.expectRevert(FeeDistributorAccounting.DistributorUnusable.selector);
        P.core_.confiscate(gauge);
        _expectNoDrift(P, gauge, pre, "40-week stale: escrow retained");
        (, uint256 credits,) = P.b.accounting();
        assertEq(credits, 0, "no half-route to FD");

        // Partial-week horizon boundary at the 20-week cursor floor, on a
        // FRESH world each side so a success cannot mask the refusal.
        {
            Pair memory QB = _pair();
            (, address gb,) = listBountyEligible(QB.core_);
            (bytes32 ib, uint256 vb) = _proposed(QB, gb);
            _recognize(QB, ib, vb);
            uint256 weekNow = (block.timestamp / WEEK) * WEEK;
            vm.warp(weekNow); // now exactly on a Thursday boundary
            fd.setLastTokenTime(weekNow - 20 * WEEK); // gap == 20 weeks: allowed
            vm.prank(stranger);
            assertEq(QB.core_.confiscate(gb), FEE, "inclusive 20-week horizon settles");
            assertEq(QB.core_.getListing(gb).status, 3, "confiscated at the boundary");
        }
        {
            Pair memory QC = _pair();
            (, address gc,) = listBountyEligible(QC.core_);
            (bytes32 ic, uint256 vc) = _proposed(QC, gc);
            _recognize(QC, ic, vc);
            uint256 weekNow = (block.timestamp / WEEK) * WEEK;
            vm.warp(weekNow);
            fd.setLastTokenTime(weekNow - 20 * WEEK - 1); // floor one week older
            vm.prank(stranger);
            vm.expectRevert(FeeDistributorAccounting.DistributorUnusable.selector);
            QC.core_.confiscate(gc);
            assertEq(QC.core_.getListing(gc).status, 1, "beyond horizon: retained");
        }

        // Refresh with zero unaccounted delta, then the strict public
        // cooldown, then the safe split retry completes exactly once.
        vm.warp(block.timestamp + WEEK); // let the first-seized case sit
        fd.setLastTokenTime(block.timestamp - 86_401);
        vm.prank(stranger);
        assertEq(P.core_.confiscate(gauge), r, "safe retry");
        pre = _snap(P, gauge);
        // Terminal replay: no dependency reads, no buckets, no events.
        vm.prank(stranger);
        (uint256 rel2, uint256 conf2) = P.core_.checkpoint(gauge);
        assertEq(rel2 + conf2, 0, "terminal checkpoint is inert");
        vm.prank(stranger);
        assertEq(P.core_.confiscate(gauge), 0, "terminal confiscate is inert");
        _expectNoDrift(P, gauge, pre, "terminal replay no drift");
        (, uint256 reward) = P.b.claim(id);
        assertEq(reward, r / 2, "funded half claimed");

        // Raw-allocator negative control (retained from the banked suite):
        // transferring the FULL gross to the FD and checkpointing WITHOUT
        // the accepted preflight lets the naive week-bucket allocator absorb
        // custody the policy must refuse. Documents the hazard; the product
        // path above never allows it.
        {
            uint256 stale = block.timestamp - 40 * WEEK;
            fd.setLastTokenTime(stale);
            uint256 beforeRaw = crvUSD.balanceOf(address(fd));
            crvUSD.mint(address(this), QUARTER);
            crvUSD.transfer(address(fd), QUARTER);
            vm.prank(fdAdmin);
            fd.checkpoint_token();
            assertTrue(crvUSD.balanceOf(address(fd)) > beforeRaw, "raw allocator moved custody unsafely");
            // restore an honest cursor for any later cell in this test
            fd.setLastTokenTime(block.timestamp);
        }
    }

    // ----------------------------------------------------------------- A07

    function test_Thin_TerminalAndWeightIndependence() public {
        Pair memory P = _pair();
        (, address gauge,) = listBountyEligible(P.core_);
        (bytes32 id, uint256 voteId) = _proposed(P, gauge);
        _recognize(P, id, voteId);

        // Unknown gauge differs even with everything live.
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(CurveGaugeListerV2.UnknownGauge.selector, actor("neverListed")));
        P.core_.confiscate(actor("neverListed"));

        _spaceFdCursor();
        vm.prank(stranger);
        uint256 gross = P.core_.confiscate(gauge);
        assertEq(gross, FEE, "seized");

        // Terminal states return before any dependency read: break the gauge
        // flag oracle; the terminal reads still answer cleanly.
        GovernanceGauge(gauge).setFlagFault(1);
        vm.prank(stranger);
        (uint256 rel, uint256 conf) = P.core_.checkpoint(gauge);
        assertEq(rel + conf, 0, "terminal checkpoint never touches the oracle");
        vm.prank(stranger);
        assertEq(P.core_.confiscate(gauge), 0, "terminal confiscate never touches the oracle");

        // Scheduled-weight/getter independence: controller weight reads
        // reverting change no settlement money.
        Pair memory Q = _pair();
        (, address gauge2,) = listBountyEligible(Q.core_);
        (bytes32 id2, uint256 vote2) = _proposed(Q, gauge2);
        _recognize(Q, id2, vote2);
        controller.setReadsRevert(true);
        Q.b.resolve(id2); // must not change anything (still Recognized)
        assertEq(uint8(Phase.Recognized), uint256(Q.b.getReport(id2).phase), "weight faults do not cancel entitlement");
        _spaceFdCursor();
        vm.prank(stranger);
        uint256 gross2 = Q.core_.confiscate(gauge2);
        controller.setReadsRevert(false);
        assertEq(gross2, gross, "identical gross without any weight dependency");
        (, uint256 rw1) = P.b.claim(id);
        (, uint256 rw2) = Q.b.claim(id2);
        assertEq(rw1, rw2, "identical B under weight/getter faults");
    }

    // ----------------------------------------------------------------- A08

    struct Run {
        CurveGaugeListerV2 core_;
        GaugeBounty b;
        address g1;
        address g2;
        bytes32 r1;
        bytes32 r2;
        bool ok1;
        bool ok2;
        bool seized;
        uint256 donated;
        uint256 flushed;
        uint256 paidB;
    }

    function testFuzz_Thin_CustodyConservation(uint256 seed) public {
        // Bounded interleavings across TWO listings/reports on the real pair,
        // driven by seed bits; every step is a real call. The independent
        // ledger recomputes all three liabilities from the final report
        // states and the money identity must hold to the wei.
        Run memory x;
        (x.core_, x.b) = deployBoundPair();
        (, x.g1,) = listBountyEligible(x.core_);
        (, x.g2,) = listBountyEligible(x.core_);
        crvUSD.mint(actor("ledgerA"), 100 * STAKE);
        crvUSD.mint(actor("ledgerB"), 100 * STAKE);
        (x.r1, x.ok1) = _stepSubmit(x, actor("ledgerA"), x.g1, seed);
        (x.r2, x.ok2) = _stepSubmit(x, actor("ledgerB"), x.g2, seed >> 1);
        require(x.ok1 || x.ok2, "fuzz needs a live report");
        bool recognized = false;
        if (seed & 0x100 != 0 && x.ok1 && uint8(x.b.getReport(x.r1).phase) == uint8(Phase.Proposed)) {
            _recognizeB(x, x.r1);
            recognized = uint8(x.b.getReport(x.r1).phase) == uint8(Phase.Recognized);
        }
        if (seed & 0x200 != 0 && x.ok2) {
            vm.prank(daoOwner);
            x.b.markFrivolous(x.r2);
        }
        if (seed & 0x400 != 0 && recognized) {
            _spaceFdCursor();
            vm.prank(stranger);
            x.seized = x.core_.confiscate(x.g1) > 0;
            if (x.seized) {
                x.paidB = x.b.getReport(x.r1).rewardCredit;
            }
        }
        if (seed & 0x800 != 0) {
            x.donated = (seed % 997) * 1e15;
            crvUSD.mint(address(x.b), x.donated);
        }
        if (x.ok1) {
            x.b.claim(x.r1);
        }
        if (x.ok2) {
            x.b.claim(x.r2);
        }
        (,, uint256 daoNow) = x.b.accounting();
        if (daoNow > 0) {
            _spaceFdCursor();
            vm.prank(stranger);
            x.b.flushDao(daoNow);
            x.flushed = daoNow;
        }
        _fuzzLedger(x, seed);
    }

    function _recognizeB(Run memory x, bytes32 id) internal {
        address whale = address(uint160(0xA11CEB00 + _whale++));
        uint256 vid = x.b.getReport(id).proposalId;
        giveVePower(whale, (escrow.totalSupply() + 1e18) * 3);
        vm.prank(whale);
        voting.vote(vid, true);
        vm.warp(x.b.getReport(id).voteEnd);
        vm.prank(stranger);
        voting.executeVote(vid);
    }

    function _fuzzLedger(Run memory x, uint256 seed) private view {
        ReportView memory v1 = x.ok1 ? x.b.getReport(x.r1) : _zeroView();
        ReportView memory v2 = x.ok2 ? x.b.getReport(x.r2) : _zeroView();
        uint256 heldWant;
        uint256 daoWant;
        heldWant += (v1.stakeState == uint8(StakeState.Bonded) || v1.stakeState == uint8(StakeState.Refundable))
            ? STAKE
            : 0;
        heldWant += (v2.stakeState == uint8(StakeState.Bonded) || v2.stakeState == uint8(StakeState.Refundable))
            ? STAKE
            : 0;
        daoWant += (v1.stakeState == uint8(StakeState.Forfeited)) ? STAKE : 0;
        daoWant += (v2.stakeState == uint8(StakeState.Forfeited)) ? STAKE : 0;

        (uint256 held, uint256 credits, uint256 dao) = x.b.accounting();
        assertEq(held, heldWant, "held stakes match the independent bond ledger");
        assertEq(dao, daoWant - x.flushed, "FD liability matches the forfeit/flush ledger");
        assertEq(credits, v1.rewardCredit + v2.rewardCredit, "credits equal funded unpaid rewards");
        assertTrue(credits <= FEE, "credits bounded by the real remainders");
        if (x.seized) {
            assertTrue(v1.phase == uint8(Phase.Rewarded), "the seized run reached Rewarded");
            ICurveGaugeListerV2.ListingV2 memory ls = x.core_.getListing(x.g1);
            assertEq(ls.reporterReward, x.paidB, "listing B matches the paid record");
            assertTrue(x.paidB > 0, "a seizure with entitlement funded a real half");
            assertEq(ls.reporterReward + ls.fdConfiscated, FEE - QUARTER * uint256(ls.epochsReleased), "B+F gross");
        }
        uint256 bountyCash = crvUSD.balanceOf(address(x.b));
        assertEq(bountyCash, held + credits + dao + x.donated, "bounty reconciles against liabilities + surplus");
        assertEq(crvUSD.balanceOf(address(x.core_)), x.core_.totalEscrow(), "V2 covers its remaining escrow");
        seed;
    }

    function _stepSubmit(Run memory x, address who, address gauge, uint256 seed)
        internal
        returns (bytes32 id, bool ok_)
    {
        seed;
        vm.startPrank(who);
        crvUSD.approve(address(x.b), type(uint256).max);
        vm.stopPrank();
        bytes32 eh = keccak256(abi.encode("fuzz-evidence", who, _seq));
        _seq += 1;
        (bytes32 rid, uint256 pid) = createBeneficiaryBallot(x.b, address(x.core_), gauge, who, who, _seq, eh);
        vm.prank(who);
        (bool s, bytes memory ret) = address(x.b).call(abi.encodeCall(GaugeBounty.submit, (gauge, pid, eh, _seq)));
        if (s) {
            id = abi.decode(ret, (bytes32));
            ok_ = x.b.getReport(id).reporter != address(0);
        } else {
            id = rid; // the domain the attempt targeted; existence test stays authoritative
        }
    }

    function _zeroView() internal pure returns (ReportView memory) {
        return ReportView({
            reporter: address(0),
            gauge: address(0),
            listingId: bytes32(0),
            evidenceHash: bytes32(0),
            proposalId: 0,
            voteEnd: 0,
            executeBy: 0,
            phase: 0,
            stakeState: 0,
            rewardCredit: 0
        });
    }
}
