// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BountyForkFixture, Kit} from "./BountyForkFixture.sol";
import {
    ForkFixture,
    FVm,
    IErc20Venue,
    IVotiumVenue,
    IProxyVenue,
    IFdVenue,
    ILaPosteVenue,
    ICcipAdapterVenue,
    IRouterVenue,
    VenueIncentive
} from "../ForkFixture.sol";
import {GaugeBounty} from "../../../contracts/GaugeBounty.sol";
import {CurveGaugeListerV2} from "../../../contracts/CurveGaugeListerV2.sol";
import {ReportView, Phase, StakeState} from "../../../contracts/bounty/BountyTypes.sol";
import {IGaugeBounty} from "../../../contracts/interfaces/IGaugeBounty.sol";
import {VoteMarketAdapter} from "../../../contracts/adapters/VoteMarketAdapter.sol";
import {FeeDistributorAccounting} from "../../../contracts/libraries/FeeDistributorAccounting.sol";

/// @dev F05–F08 (plans/BOUNTY-THIN-PLAN.md §7.3): real custody/venue splits,
/// emergency supersession, FD stale-cooldown rollback and the sole stake-only
/// DAO forfeit with delayed safe flush — against genuinely deployed thin/V2
/// instances and real mainnet tokens. Ballots are cast at the pin through the
/// real vote API with the ballot's own snapshot power (balanceOfAt oracle,
/// positive gate per voter, quorum asserted), executed permissionlessly via
/// the real executeVote/CallsScript/Agent/proxy path; no tally/flag/ACL/code
/// writes (same disclosed discipline as the frozen F03 voter set).
/// Disclosed local role pranks (labelled, never broadcasts): EMERGENCY_DAO
/// bare emergency action; the real FD admin (the DAO) is NEVER pranked — FD
/// maintenance happens through the permissionless post-deadline checkpoint
/// path only.
interface IVeSnapFacts {
    function balanceOfAt(address, uint256) external view returns (uint256);
}

interface IVotingGetFacts {
    function getVote(uint256)
        external
        view
        returns (bool, bool, uint256, uint256, uint256, uint256, uint256, uint256, uint256, bytes memory);
}

interface IVotingExec2 {
    function vote(uint256 voteId, bool option, bool autoExecute) external;
    function executeVote(uint256 voteId) external;
    function canExecute(uint256 voteId) external view returns (bool);
}

abstract contract ForkThinCustodySpec is BountyForkFixture {
    function setUp() public virtual {
        _freshFork();
    }

    // ---------------------------------------------------------------- shared

    /// @dev Frozen-fork pattern: vm.deal to a fresh donor + normal payable
    /// call into the VoteMarket adapter receive(); never a real ingress.
    function _floatVm(Kit memory k, uint256 weiAmount) private {
        fvm.deal(donor(), weiAmount * 2);
        fvm.prank(donor());
        (bool ok,) = payable(k.vma).call{value: weiAmount}("");
        assertTrue(ok, "custody: float top-up delivered");
    }

    /// @dev Real snapshot voters cast YES through the actual app API while
    /// the ballot is open (frozen F03 discipline; no tally/flag writes).
    function _castYes(uint256 voteId) internal {
        address[] memory voters = forkVoters();
        require(voters.length > 0, "custody fixture blocked: no discovered voting set");
        (,,, uint256 snapBlock,,,,,,) = IVotingGetFacts(THIN_VOTING_APP).getVote(voteId);
        uint256 accumulated;
        for (uint256 i = 0; i < voters.length; ++i) {
            // F03 discipline: charge the ballot's own snapshot-power oracle
            // read (real prior-block power) and vote while the lock behind it
            // is certainly unexpired — all thin ballots are cast at the pin.
            uint256 pw = IVeSnapFacts(THIN_VE_CRV).balanceOfAt(voters[i], snapBlock);
            assertTrue(pw > 0, "custody: voter has real veCRV at the snapshot");
            accumulated += pw;
            fvm.prank(voters[i]);
            IVotingExec2(THIN_VOTING_APP).vote(voteId, true, false);
        }
        assertTrue(accumulated >= QUORUM_POWER_MIN, "custody: YES clears the 30% acceptance quorum");
    }

    /// @dev Close the ballot window and run the REAL canonical script
    /// through Voting -> CallsScript -> Agent -> bounty/proxy/gauge.
    function _executeAtVoteEnd(Kit memory k, bytes32 id, uint256 voteId) internal {
        fvm.warp(k.b.getReport(id).voteEnd);
        assertTrue(IVotingExec2(THIN_VOTING_APP).canExecute(voteId), "custody: tally passed");
        fvm.prank(reporter_());
        IVotingExec2(THIN_VOTING_APP).executeVote(voteId);
    }

    /// @dev Sum of the real FD's weekly buckets over the stable 27-week
    /// window ending two weeks past now: `_checkpoint_token` redistributes
    /// `balance - token_last_balance` from the OLD cursor's week forward
    /// (20-week loop cap), so settlement/refresh bucket deltas must be read
    /// across the full reachable span, not just the current week.
    function _fdBucketWindow() internal view returns (uint256 fromWeek, uint256 toWeek) {
        uint256 nowW = (block.timestamp / WEEK) * WEEK;
        // 47 weeks back: covers a permissionless refresh redistributing from
        // a cursor already ~41 weeks stale (the 20-week loop's oldest leg).
        return (nowW - 45 * WEEK, nowW + 2 * WEEK);
    }

    /// @dev FD's unaccounted residual at now: balance - token_last_balance.
    /// Every real checkpoint redistributes THIS plus the new transfer into
    /// weekly buckets, so bucket deltas are compared against
    /// `residual + ourTransfer` — the exact custody/accounting law.
    function _fdResidual() internal view returns (uint256) {
        uint256 bal = IErc20Venue(CRVUSD).balanceOf(FEEDIST);
        uint256 last = IFdVenue(FEEDIST).token_last_balance();
        return bal > last ? bal - last : 0;
    }

    function _fdBucketSum(uint256 fromWeek, uint256 toWeek) internal view returns (uint256 sum) {
        for (uint256 w = fromWeek; w <= toWeek; w += WEEK) {
            sum += IFdVenue(FEEDIST).tokens_per_week(w);
        }
    }

    /// @dev Bucket reconciliation oracle: the real `_checkpoint_token`
    /// apportions `to_distribute` across weeks with floor divisions, so the
    /// summed bucket gain is expected MINUS at most one wei per traversed
    /// week (max 20). Custody deltas are asserted exactly elsewhere; here
    /// the bounded law: expected-20 <= gain <= expected.
    function _assertBucketGain(uint256 fromWeek, uint256 toWeek, uint256 before, uint256 expected, string memory label)
        private
        view
    {
        uint256 gain = _fdBucketSum(fromWeek, toWeek) - before;
        if (gain > expected || expected - gain > 20) {
            assertTrue(
                false,
                string(
                    abi.encodePacked(
                        label,
                        " GAIN=",
                        _u(gain),
                        " EXP=",
                        _u(expected),
                        " BEFORE=",
                        _u(before),
                        " AFTER=",
                        _u(_fdBucketSum(fromWeek, toWeek))
                    )
                )
            );
        }
    }

    function _countTokenTransfers(FVm.Log[] memory logs, address token, address from, address to, uint256 amount)
        private
        pure
        returns (uint256 n)
    {
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].emitter != token || logs[i].topics.length != 3 || logs[i].topics[0] != T_TRANSFER) {
                continue;
            }
            if (
                address(uint160(uint256(logs[i].topics[1]))) != from
                    || address(uint160(uint256(logs[i].topics[2]))) != to
            ) {
                continue;
            }
            if (abi.decode(logs[i].data, (uint256)) == amount) {
                ++n;
            }
        }
    }

    function _countMessageSent(FVm.Log[] memory logs) private pure returns (uint256 n) {
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].emitter == LA_POSTE && logs[i].topics.length >= 1 && logs[i].topics[0] == T_MESSAGE_SENT) {
                ++n;
            }
        }
    }

    // ------------------------------------------------------------------ F05

    function test_Fork_ThinSplitAndVenues() public {
        // (i) fresh ZERO-DRIP canonical settlement: no quarter ever released,
        // the real ballot executes, and R/B/F route exactly through the real
        // tokens with fixed reporter pulls while venues hold nothing new.
        _f05ZeroDripCanonical();
        // (ii) ALREADY-FUNDED quarter: one real quarter first sits in exact
        // Votium/CRM/LaPoste/TokenFactory custody; the same report ID then
        // runs the canonical settlement and its later bond/reward claim is
        // checked against the reduced remainder. Shared custody oracle, not
        // lost venue coverage (thin §7.3 F05).
        _f05FundedQuarterCanonical();
    }

    function _f05ZeroDripCanonical() private {
        _freshFork();
        Kit memory k = _deployThinKit();
        address g = _listPrimary(k);
        address rep = reporter_();
        _fundReporter(k, rep, 1);
        (bytes32 id, uint256 voteId) = _submitForkBallot(k, g, rep, 551, keccak256(abi.encode("f05zc", g)));
        _castYes(voteId);
        _executeAtVoteEnd(k, id, voteId);
        assertEq(uint8(k.b.getReport(id).phase), 3, "f05zc: canonical recognition");
        _f05zcSettle(k, id, g);
        _f05zcClaim(k, id);
    }

    /// @dev Pre-settlement observation set for the zero-drip cell (folded
    /// into one struct to keep the codegen stack shallow).
    struct ZcPre {
        uint256 vb0;
        uint256 tf0;
        uint256 fee0;
        uint256 vaEth;
        uint256 weekLo;
        uint256 weekHi;
        uint256 bucket0;
        uint256 residual0;
        uint256 fdBefore;
        uint256 coreBefore;
    }

    function _zcSnap(Kit memory k) private view returns (ZcPre memory z) {
        z.vb0 = IVotiumVenue(VOTIUM).virtualBalance(CRVUSD);
        z.tf0 = IErc20Venue(CRVUSD).balanceOf(TOKEN_FACTORY);
        z.fee0 = IErc20Venue(CRVUSD).balanceOf(VOTIUM_FEE_ADDRESS);
        z.vaEth = k.vma.balance;
        (z.weekLo, z.weekHi) = _fdBucketWindow();
        z.bucket0 = _fdBucketSum(z.weekLo, z.weekHi);
        z.residual0 = _fdResidual();
        z.fdBefore = IErc20Venue(CRVUSD).balanceOf(FEEDIST);
    }

    /// @dev Settlement with zero funded quarters: R is the full 10,000;
    /// exact B/F custody legs, mandatory FD checkpoint, weekly-bucket
    /// reconciliation, and ZERO venue disturbance (no Votium credit, no L2
    /// lock, no fee leg, no adapter ETH spend, no campaign message).
    function _f05zcSettle(Kit memory k, bytes32 id, address g) private {
        assertEq(_acctHash(k), keccak256(abi.encode(STAKE, 0, 0)), "f05zc: bond held, nothing funded yet");
        ZcPre memory z = _zcSnap(k);
        assertEq(IErc20Venue(CRVUSD).balanceOf(address(k.core_)), FEE, "f05zc: full escrow pre-settlement");
        fvm.recordLogs();
        fvm.prank(reporter_());
        uint256 gross = k.core_.confiscate(g);
        FVm.Log[] memory logs = fvm.getRecordedLogs();
        assertEq(gross, FEE, "f05zc: R is the full remainder");
        assertEq(k.core_.getListing(g).released, 0, "f05zc: zero-drip stays zero");
        assertEq(k.core_.getListing(g).confiscated, FEE, "f05zc: gross confiscated");
        assertEq(k.core_.getListing(g).reporterReward, FEE / 2, "f05zc: B exact");
        assertEq(_acctHash(k), keccak256(abi.encode(STAKE, FEE / 2, 0)), "f05zc: B funded, bond intact, no slash");
        assertEq(IErc20Venue(CRVUSD).balanceOf(address(k.b)), STAKE + FEE / 2, "f05zc: exact B pull");
        assertEq(z.fdBefore + FEE / 2, IErc20Venue(CRVUSD).balanceOf(FEEDIST), "f05zc: exact F to real FD");
        assertEq(IFdVenue(FEEDIST).last_token_time(), block.timestamp, "f05zc: mandatory checkpoint");
        assertEq(
            IFdVenue(FEEDIST).token_last_balance(),
            IErc20Venue(CRVUSD).balanceOf(FEEDIST),
            "f05zc: FD accounted == custody"
        );
        _assertBucketGain(z.weekLo, z.weekHi, z.bucket0, z.residual0 + FEE / 2, "f05zc: FD weekly buckets +F");
        // Zero-drip means the VENUES saw nothing.
        assertEq(IVotiumVenue(VOTIUM).virtualBalance(CRVUSD), z.vb0, "f05zc: Votium untouched");
        assertEq(IErc20Venue(CRVUSD).balanceOf(TOKEN_FACTORY), z.tf0, "f05zc: no L2 lock minted");
        assertEq(IErc20Venue(CRVUSD).balanceOf(VOTIUM_FEE_ADDRESS), z.fee0, "f05zc: fee recipient untouched");
        assertEq(_countMessageSent(logs), 0, "f05zc: no campaign message");
        assertEq(k.vma.balance, z.vaEth, "f05zc: float untouched");
        id;
    }

    /// @dev Fixed reporter pull of bond AND reward together, exact through
    /// the real token, with the ledger fully discharged.
    function _f05zcClaim(Kit memory k, bytes32 id) private {
        address rep = reporter_();
        uint256 rep0 = IErc20Venue(CRVUSD).balanceOf(rep);
        (uint256 stake, uint256 reward) = k.b.claim(id);
        assertEq(stake, STAKE, "f05zc: bond paid");
        assertEq(reward, FEE / 2, "f05zc: positive funded half paid");
        assertEq(IErc20Venue(CRVUSD).balanceOf(rep) - rep0, STAKE + FEE / 2, "f05zc: exact fixed-recipient pull");
        assertEq(_acctHash(k), keccak256(abi.encode(0, 0, 0)), "f05zc: liabilities discharged");
    }

    function _f05FundedQuarterCanonical() private {
        _freshFork();
        Kit memory k = _deployThinKit();
        address g = _listPrimary(k);
        address rep = reporter_();
        _fundReporter(k, rep, 1);
        _floatVm(k, 1 ether);
        (bytes32 id, uint256 voteIdQ) = _submitForkBallot(k, g, rep, 552, keccak256(abi.encode("f05qc", g)));
        // Ballots are cast while the voters' power is certainly live (at the
        // pin); the funded quarter then releases and the closed ballot runs.
        _castYes(voteIdQ);
        uint256 listingEpoch = k.core_.getListing(g).listingEpoch;
        // ONE real quarter released to the venues first (epoch boundary +1).
        _f05qcReleaseReceipts(k, g, listingEpoch);

        _f05qcCanonicalSettleAndClaim(k, id, g);
    }

    /// @dev Execution-time venue receipts for the one released quarter, on the
    /// frozen reconciliation pattern (`test/fork/ForkVoteMarket.t.sol:125-164`):
    /// Votium net credit PLUS the actual Votium token-balance delta/final
    /// custody, the VM half fully forwarded to CRM/TokenFactory with the
    /// bridged message decoded and bound field-by-field, the adapter record's
    /// EXPECTED receipt, and an equality-based ETH reconciliation against an
    /// independently live-quoted router fee (bountyconf3 finding 7).
    struct VmPre {
        uint256 tf;
        uint256 crm;
        uint256 vaEth;
        uint256 core;
        uint256 nonce;
        uint256 votiumCrv;
        uint256 crmEth;
        uint256 laPosteEth;
        uint256 ccipEth;
        uint256 payerEth;
        uint256 keeperEth;
        uint256 daoEth;
        uint256 routerQuote;
    }

    function _f05qcReleaseReceipts(Kit memory k, address g, uint256 listingEpoch) private {
        fvm.warp(listingEpoch + WEEK + 1);
        uint256 half = QUARTER / 2;
        uint256 net = half - (half * IVotiumVenue(VOTIUM).platformFee()) / IVotiumVenue(VOTIUM).DENOMINATOR();
        uint256 vb0 = IVotiumVenue(VOTIUM).virtualBalance(CRVUSD);
        uint256 feeRec0 = IErc20Venue(CRVUSD).balanceOf(VOTIUM_FEE_ADDRESS);
        uint256 round = IVotiumVenue(VOTIUM).activeRound();
        uint256 incLen0 = IVotiumVenue(VOTIUM).incentivesLength(round, g);
        VmPre memory pre;
        pre.tf = IErc20Venue(CRVUSD).balanceOf(TOKEN_FACTORY);
        pre.crm = IErc20Venue(CRVUSD).balanceOf(CRM);
        pre.vaEth = k.vma.balance;
        pre.core = IErc20Venue(CRVUSD).balanceOf(address(k.core_));
        pre.nonce = ILaPosteVenue(LA_POSTE).sentNonces(VM_DEST_CHAIN_ID);
        pre.votiumCrv = IErc20Venue(CRVUSD).balanceOf(VOTIUM);
        pre.crmEth = CRM.balance;
        pre.laPosteEth = LA_POSTE.balance;
        pre.ccipEth = CCIP_ADAPTER.balance;
        pre.payerEth = payer().balance;
        pre.keeperEth = keeper().balance;
        pre.daoEth = DAO.balance;
        pre.routerQuote = _f05qcBindRouter(k, half);
        fvm.recordLogs();
        fvm.prank(reporter_());
        (uint256 released,) = k.core_.checkpoint(g);
        FVm.Log[] memory rl = fvm.getRecordedLogs();
        assertEq(released, QUARTER, "f05qc: one quarter released");
        assertEq(IVotiumVenue(VOTIUM).virtualBalance(CRVUSD) - vb0, net, "f05qc: Votium net credit exact");
        assertEq(IErc20Venue(CRVUSD).balanceOf(VOTIUM) - pre.votiumCrv, net, "f05qc: Votium ACTUAL token custody delta");
        assertEq(IErc20Venue(CRVUSD).balanceOf(VOTIUM_FEE_ADDRESS) - feeRec0, half - net, "f05qc: fee leg exact");
        assertEq(
            (IErc20Venue(CRVUSD).balanceOf(VOTIUM) - pre.votiumCrv)
                + (IErc20Venue(CRVUSD).balanceOf(VOTIUM_FEE_ADDRESS) - feeRec0),
            half,
            "f05qc: net + fee = gross (frozen Votium custody law)"
        );
        assertEq(
            IVotiumVenue(VOTIUM).virtualBalance(CRVUSD) - vb0,
            IErc20Venue(CRVUSD).balanceOf(VOTIUM) - pre.votiumCrv,
            "f05qc: virtual credit is backed by real custody"
        );
        assertEq(IErc20Venue(CRVUSD).balanceOf(k.va), 0, "f05qc: Votium adapter retains nothing");
        assertEq(IVotiumVenue(VOTIUM).incentivesLength(round, g), incLen0 + 1, "f05qc: exactly one incentive");
        _assertIncentive(k.va, round, incLen0, half);
        _f05qcVmReceipts(k, listingEpoch, half, rl, pre);
    }

    /// @dev bountyconf3 finding 7 (frozen pattern:
    /// `test/fork/ForkVoteMarket.t.sol:125-164`): rebuild the exact downstream
    /// message from the verified deployed semantics, LIVE-QUOTE the real
    /// router with it, and bind the adapter's own `getFee` call plus its
    /// `ccipSend` at EXACTLY the quoted value. The quote is an independent
    /// oracle for the ETH accounting below, never a rearrangement of the
    /// observed spend.
    function _f05qcBindRouter(Kit memory k, uint256 half) private returns (uint256 quote) {
        VoteMarketAdapter vma = VoteMarketAdapter(payable(k.vma));
        // The forwarded budget is priced by the adapter itself, from live
        // getters: (campaignCreationGas + blacklistedAddressGas * excluded)
        // * gasPrice, and the float already covers it.
        assertEq(vma.excluded().length, 0, "f05qc: no blacklisted addresses priced into the message");
        assertEq(
            (vma.campaignCreationGas() + vma.blacklistedAddressGas() * vma.excluded().length) * vma.gasPrice(),
            CALL_VALUE,
            "f05qc: adapter's own bridge budget equals the forwarded value"
        );
        assertEq(vma.ethDeficit(half), 0, "f05qc: float already covers one bridge payment");
        assertEq(ICcipAdapterVenue(CCIP_ADAPTER).router(), CCIP_ROUTER, "f05qc: derived router identity");
        uint64 destSelector = uint64(ICcipAdapterVenue(CCIP_ADAPTER).getBridgeChainId(VM_DEST_CHAIN_ID));
        assertTrue(destSelector != 0, "f05qc: bridge chain selector present");
        assertTrue(IRouterVenue(CCIP_ROUTER).isChainSupported(destSelector), "f05qc: real router supports destination");
        IRouterVenue.CcipEvm2AnyMessage memory ccipMsg = _buildCcipMessage(_expectedLaposteMessage(vma, half));
        assertEq(
            keccak256(ccipMsg.extraArgs),
            keccak256(abi.encodePacked(CCIP_EXTRA_ARGS_TAG, abi.encode(uint256(2_050_000)))),
            "f05qc: extra-args bytes: tag 0x97a657c9 + gas 2050000"
        );
        quote = IRouterVenue(CCIP_ROUTER).getFee(destSelector, ccipMsg);
        assertTrue(quote > 0 && quote < CALL_VALUE, "f05qc: live router quote positive and within the forwarded value");
        // The adapter's own getFee with the identical message, and its
        // ccipSend at EXACTLY the quoted value.
        fvm.expectCall(CCIP_ROUTER, abi.encodeCall(IRouterVenue.getFee, (destSelector, ccipMsg)));
        fvm.expectCall(CCIP_ROUTER, quote, abi.encodeCall(IRouterVenue.ccipSend, (destSelector, ccipMsg)));
    }

    function _f05qcVmReceipts(Kit memory k, uint256 listingEpoch, uint256 half, FVm.Log[] memory rl, VmPre memory pre)
        private
    {
        assertEq(_countTokenTransfers(rl, CRVUSD, k.vma, CRM, half), 1, "f05qc: adapter->CRM transfer");
        assertEq(_countTokenTransfers(rl, CRVUSD, CRM, TOKEN_FACTORY, half), 1, "f05qc: CRM burn-lock transfer");
        assertEq(IErc20Venue(CRVUSD).balanceOf(TOKEN_FACTORY) - pre.tf, half, "f05qc: final custody at TokenFactory");
        assertEq(IErc20Venue(CRVUSD).balanceOf(CRM), pre.crm, "f05qc: CRM retains nothing");
        assertEq(ILaPosteVenue(LA_POSTE).sentNonces(VM_DEST_CHAIN_ID) - pre.nonce, 1, "f05qc: one bridged message");
        assertEq(_countMessageSent(rl), 1, "f05qc: one LaPoste MessageSent log");
        _f05qcMessageProof(rl, k.vma, listingEpoch + WEEK, half, pre.nonce);
        _f05qcEthReconciliation(k, pre);
        assertEq(IErc20Venue(CRVUSD).balanceOf(k.vma), 0, "f05qc: VM adapter keeps nothing");
        assertEq(pre.core - IErc20Venue(CRVUSD).balanceOf(address(k.core_)), QUARTER, "f05qc: exact quarter debit");
    }

    /// @dev bountyconf3 finding 7: the bridged message and the adapter record
    /// are BOUND, not counted. The `MessageSent` log's nonce topic, indexed
    /// sender and destination are checked, the whole `LpMessage` is decoded
    /// through the frozen campaign-message oracle (destination chain, to,
    /// sender, token leg, real TokenFactory metadata, CRM CREATE_CAMPAIGN
    /// payload with gauge/manager/reward-token/periods/gross), and the keyed
    /// plus chronological adapter records are compared to the receipt the
    /// adapter itself must have computed.
    function _f05qcMessageProof(
        FVm.Log[] memory rl,
        address adapter,
        uint256 scheduledEpoch,
        uint256 half,
        uint256 liveNonceBefore
    ) private view {
        (bytes32 nonceTopic, bytes32 senderTopic, address to, LpMessage memory message) = _requireMessageSent(rl);
        assertEq(uint256(nonceTopic), liveNonceBefore + 1, "f05qc: message nonce topic is the next live nonce");
        assertEq(address(uint160(uint256(senderTopic))), CRM, "f05qc: indexed sender = CRM");
        assertEq(to, CRM, "f05qc: log to = CRM");
        _assertCampaignMessage(message, liveNonceBefore + 1, adapter, half);
        assertEq(_countLogs(rl, CRM, T_CAMPAIGN_PAYLOAD_SENT), 1, "f05qc: real CampaignCreationPayloadSent");

        VoteMarketAdapter vma = VoteMarketAdapter(payable(adapter));
        assertEq(vma.depositCount(), 1, "f05qc: one deposit record");
        bytes32 expectedReceipt = keccak256(abi.encode(GAUGE_PRIMARY, scheduledEpoch, half, 1));
        VoteMarketAdapter.DepositRecord memory drec = vma.depositAt(0);
        assertEq(drec.gauge, GAUGE_PRIMARY, "f05qc: recorded gauge");
        assertEq(drec.scheduledEpoch, scheduledEpoch, "f05qc: scheduled epoch recorded");
        assertEq(drec.amount, half, "f05qc: recorded gross");
        assertEq(drec.executionEpoch, (block.timestamp / WEEK) * WEEK, "f05qc: execution epoch is the live week floor");
        assertEq(drec.receipt, expectedReceipt, "f05qc: receipt == keccak(gauge, scheduledEpoch, gross, local nonce)");
        (uint256 amt, uint256 execEp, bytes32 keyed) = vma.getDeposit(GAUGE_PRIMARY, scheduledEpoch);
        assertEq(amt, half, "f05qc: keyed record gross");
        assertEq(execEp, drec.executionEpoch, "f05qc: keyed and chronological epochs agree");
        assertEq(keyed, drec.receipt, "f05qc: keyed receipt equals the chronological receipt");
        _assertCampaignDepositLog(rl, vma, scheduledEpoch, half, 1);
    }

    /// @dev bountyconf3 finding 7: the ETH law is EXACT, not a bound. The
    /// adapter forwards CALL_VALUE, the real router charges the independently
    /// quoted fee and refunds the rest, so the float must drop by precisely
    /// that quote and nothing else may retain ETH. `0 < spent <= CALL_VALUE`
    /// (the previous oracle) established neither the fee nor where the refund
    /// landed; the equality below does, because it can only hold if the
    /// unused `CALL_VALUE - fee` came back to the adapter.
    function _f05qcEthReconciliation(Kit memory k, VmPre memory pre) private {
        emit log_named_uint("f05qc: independently quoted router fee (wei)", pre.routerQuote);
        emit log_named_uint("f05qc: forwarded CALL_VALUE (wei)", CALL_VALUE);
        uint256 floatAfter = k.vma.balance;
        assertEq(floatAfter, pre.vaEth - pre.routerQuote, "f05qc: float = floatBefore - quoted router fee");
        assertEq(pre.vaEth - floatAfter, pre.routerQuote, "f05qc: ETH spend equals the independent quote exactly");
        assertTrue(pre.routerQuote > 0, "f05qc: the real router charged a positive fee");
        assertTrue(pre.routerQuote < CALL_VALUE, "f05qc: fee is inside the forwarded CALL_VALUE");
        assertEq(CRM.balance, pre.crmEth, "f05qc: CRM retains no ETH");
        assertEq(LA_POSTE.balance, pre.laPosteEth, "f05qc: LaPoste retains no ETH");
        assertEq(CCIP_ADAPTER.balance, pre.ccipEth, "f05qc: CCIP adapter retains no ETH");
        assertEq(payer().balance, pre.payerEth, "f05qc: no ETH to the listing payer");
        assertEq(keeper().balance, pre.keeperEth, "f05qc: no ETH to the checkpoint keeper");
        assertEq(DAO.balance, pre.daoEth, "f05qc: no ETH to the owner/agent");
    }

    /// @dev The SAME report ID then runs the canonical ballot and its later
    /// bond/reward claim is checked against the reduced remainder (fixed
    /// reporter pulls, exact FD buckets, fully discharged ledger).
    function _f05qcCanonicalSettleAndClaim(Kit memory k, bytes32 id, address g) private {
        // Canonical settlement through the REAL ballot (cast at the pin) on
        // the SAME report ID.
        _executeAtVoteEnd(k, id, k.b.getReport(id).proposalId);
        assertEq(uint8(k.b.getReport(id).phase), 3, "f05qc: canonical recognition");
        _f05qcSettle(k, id, g);
        _f05qcClaim(k, id);
    }

    /// @dev R = 10,000 - 2,500*n with n = 1 ACTUALLY funded quarter; exact
    /// B/F split into the real custodies with mandatory FD checkpoint and
    /// weekly-bucket reconciliation (shared custody oracle).
    function _f05qcSettle(Kit memory k, bytes32 id, address g) private {
        assertEq(_acctHash(k), keccak256(abi.encode(STAKE, 0, 0)), "f05qc: bond held, nothing funded pre-settle");
        uint256 expectedR = FEE - QUARTER;
        (uint256 weekLo, uint256 weekHi) = _fdBucketWindow();
        uint256 bucket0 = _fdBucketSum(weekLo, weekHi);
        uint256 residual0 = _fdResidual();
        uint256 fdBefore = IErc20Venue(CRVUSD).balanceOf(FEEDIST);
        fvm.prank(reporter_());
        uint256 gross = k.core_.confiscate(g);
        assertEq(gross, expectedR, "f05qc: only the remaining escrow settles");
        assertEq(k.core_.getListing(g).released, QUARTER, "f05qc: funded quarter preserved");
        assertEq(k.core_.getListing(g).reporterReward, expectedR / 2, "f05qc: B exact on remainder");
        assertEq(
            _acctHash(k), keccak256(abi.encode(STAKE, expectedR / 2, 0)), "f05qc: B credited, bond intact, no slash"
        );
        assertEq(IErc20Venue(CRVUSD).balanceOf(address(k.b)), STAKE + expectedR / 2, "f05qc: exact B pull into custody");
        assertEq(IErc20Venue(CRVUSD).balanceOf(FEEDIST) - fdBefore, expectedR - expectedR / 2, "f05qc: F leg exact");
        assertEq(IFdVenue(FEEDIST).last_token_time(), block.timestamp, "f05qc: mandatory checkpoint");
        assertEq(
            IFdVenue(FEEDIST).token_last_balance(),
            IErc20Venue(CRVUSD).balanceOf(FEEDIST),
            "f05qc: FD accounted == custody"
        );
        _assertBucketGain(weekLo, weekHi, bucket0, residual0 + expectedR - expectedR / 2, "f05qc: buckets +F");
        id;
    }

    /// @dev The earlier funded-quarter report ID now pays its own bond AND
    /// the positive reward through the fixed recipient.
    function _f05qcClaim(Kit memory k, bytes32 id) private {
        uint256 rep0 = IErc20Venue(CRVUSD).balanceOf(reporter_());
        (uint256 stake, uint256 reward) = k.b.claim(id);
        assertEq(stake, STAKE, "f05qc: bond paid on the same report");
        assertEq(reward, (FEE - QUARTER) / 2, "f05qc: positive half paid on the same report");
        assertEq(IErc20Venue(CRVUSD).balanceOf(reporter_()) - rep0, STAKE + (FEE - QUARTER) / 2, "f05qc: exact pull");
        assertEq(_acctHash(k), keccak256(abi.encode(0, 0, 0)), "f05qc: liabilities discharged");
    }

    // ------------------------------------------------------------------ F06

    function test_Fork_ThinEmergencyNoAward() public {
        _freshFork();
        Kit memory k = _deployThinKit();
        address g = _listPrimary(k);
        address rep = reporter_();
        _fundReporter(k, rep, 1);
        (bytes32 id, uint256 voteId) = _submitForkBallot(k, g, rep, 606, keccak256(abi.encode("f06", g)));

        // A bare, separately authorized emergency kill lands during the
        // pending report (disclosed emergency-role prank on the proxy).
        fvm.prank(EMERGENCY_DAO);
        IProxyVenue(THIN_KILL_PROXY).set_killed(g);

        // FD cooldown CONDITION and settlement REFUSAL inside the emergency
        // window: the public-checkpoint permission flag is live on the real
        // FD, but the pinned cursor is under TOKEN_CHECKPOINT_DEADLINE old,
        // so the FD's own `now > last_token_time + 86400` condition is false
        // and the product's settlement is refused, leaving every
        // custody/liability value where it was.
        assertTrue(IFdVenue(FEEDIST).can_checkpoint_token(), "f06: public checkpointing permitted by the FD");
        assertTrue(
            block.timestamp <= IFdVenue(FEEDIST).last_token_time() + 86400,
            "f06: inside the FD 1-day checkpoint cooldown in the emergency window"
        );
        uint256 fdCursor0 = IFdVenue(FEEDIST).last_token_time();
        uint256 fdBal0 = IErc20Venue(CRVUSD).balanceOf(FEEDIST);
        fvm.prank(rep);
        vm.expectRevert(); // the strict public cooldown refusal bubbles from the FD
        k.core_.confiscate(g);
        (uint256 h0, uint256 c0, uint256 d0) = k.b.accounting();
        assertEq(h0, STAKE, "f06: refused settlement moved no bond");
        assertEq(c0, 0, "f06: refused settlement funded no credit");
        assertEq(d0, 0, "f06: refused settlement invented no liability");
        assertEq(IFdVenue(FEEDIST).last_token_time(), fdCursor0, "f06: refused settlement moved no cursor");
        assertEq(IErc20Venue(CRVUSD).balanceOf(FEEDIST), fdBal0, "f06: refused settlement paid no FD");
        assertEq(uint256(k.core_.getListing(g).status), 1, "f06: listing still Active after refusal");

        // Late canonical execution cannot appropriate the emergency kill:
        // prepare sees the flag already true (pre-kill expectation fails)
        // and closes WITHOUT award, while the middle entry still succeeds.
        _castYes(voteId);
        _executeAtVoteEnd(k, id, voteId);
        ReportView memory rv = k.b.getReport(id);
        assertEq(uint8(rv.phase), 7, "f06: emergency supersession -> NoAward");
        assertEq(rv.rewardCredit, 0, "f06: nothing appropriated");
        voteId;

        _f06SettleAndRefund(k, id, g);
    }

    /// @dev Full FD settlement on the safe (post-deadline) retry path with
    /// the real bucket reconciliation, and the independent bond refund.
    function _f06SettleAndRefund(Kit memory k, bytes32 id, address g) private {
        address rep = reporter_();
        (uint256 weekLo, uint256 weekHi) = _fdBucketWindow();
        uint256 bucket0 = _fdBucketSum(weekLo, weekHi);
        uint256 residual0 = _fdResidual();
        uint256 fdBefore = IErc20Venue(CRVUSD).balanceOf(FEEDIST);
        fvm.prank(rep);
        uint256 gross = k.core_.confiscate(g);
        (, uint256 credits, uint256 dao) = k.b.accounting();
        assertEq(credits, 0, "f06: reporter half not credited (no entitlement)");
        dao;
        assertEq(gross, FEE, "f06: full remainder settles");
        assertEq(IErc20Venue(CRVUSD).balanceOf(FEEDIST) - fdBefore, gross, "f06: full R safely accounted to FD");
        assertEq(IFdVenue(FEEDIST).last_token_time(), block.timestamp, "f06: mandatory checkpoint ran");
        assertEq(
            IFdVenue(FEEDIST).token_last_balance(),
            IErc20Venue(CRVUSD).balanceOf(FEEDIST),
            "f06: FD accounted == custody"
        );
        _assertBucketGain(weekLo, weekHi, bucket0, residual0 + gross, "f06: FD weekly buckets +R");
        (uint256 stake,) = k.b.claim(id);
        assertEq(stake, STAKE, "f06: full bond refund");
    }

    // ------------------------------------------------------------------ F07

    function test_Fork_ThinFDStaleCooldownRollback() public {
        _freshFork();
        Kit memory k = _deployThinKit();
        address g = _listPrimary(k);
        address rep = reporter_();
        _fundReporter(k, rep, 1);
        (bytes32 id, uint256 voteId7) = _submitForkBallot(k, g, rep, 607, keccak256(abi.encode("f07", g)));
        voteId7;

        _f07Recognize(k, id);
        _f07StaleRefusalBeforeEitherHalf(k, id, g);
        _f07BondIndependentDuringOutage(k, id, g);
        uint256 cursor = _f07ZeroDeltaRefresh(k);
        _f07StrictCooldownRetryAndClaim(k, id, g, cursor);
    }

    /// @dev Real canonical recognition FIRST: this row must prove the
    /// failure happens BEFORE EITHER half, with a live entitlement.
    function _f07Recognize(Kit memory k, bytes32 id) private {
        uint256 voteId = k.b.getReport(id).proposalId;
        _castYes(voteId);
        _executeAtVoteEnd(k, id, voteId);
        assertEq(uint8(k.b.getReport(id).phase), 3, "f07: recognized entitlement exists");
    }

    /// @dev 41-week stale horizon (pure time advance, no FD writes): the
    /// settlement refuses and NEITHER half moved — no reporter credit, no
    /// FD payment, no cursor change, no bucket change, no terminal state.
    /// @dev Shared custody-ledger fingerprint of the three liability totals.
    function _acctHash(Kit memory k) private view returns (bytes32) {
        (uint256 h, uint256 c, uint256 d) = k.b.accounting();
        return keccak256(abi.encode(h, c, d));
    }

    /// @dev 41-week stale horizon (pure time advance, no FD writes): the
    /// settlement refuses and NEITHER half moved — no reporter credit, no
    /// FD payment, no cursor change, no bucket change, no terminal state.
    function _f07StaleRefusalBeforeEitherHalf(Kit memory k, bytes32 id, address g) private {
        fvm.warp(block.timestamp + 41 * WEEK);
        assertEq(_acctHash(k), keccak256(abi.encode(STAKE, 0, 0)), "f07: ledger pre-refusal (bond held, no halves)");
        (uint256 weekLo, uint256 weekHi) = _fdBucketWindow();
        uint256 bucket0 = _fdBucketSum(weekLo, weekHi);
        uint256 fdBal0 = IErc20Venue(CRVUSD).balanceOf(FEEDIST);
        uint256 fdCursor0 = IFdVenue(FEEDIST).last_token_time();
        uint256 coreBal0 = IErc20Venue(CRVUSD).balanceOf(address(k.core_));
        fvm.prank(reporter_());
        vm.expectRevert(FeeDistributorAccounting.DistributorUnusable.selector);
        k.core_.confiscate(g);
        assertEq(_acctHash(k), keccak256(abi.encode(STAKE, 0, 0)), "f07: neither half moved on refusal");
        assertEq(coreBal0, IErc20Venue(CRVUSD).balanceOf(address(k.core_)), "f07: core escrow retained");
        assertEq(fdBal0, IErc20Venue(CRVUSD).balanceOf(FEEDIST), "f07: FD paid nothing while stale");
        assertEq(IFdVenue(FEEDIST).last_token_time(), fdCursor0, "f07: cursor unmoved by refusal");
        assertEq(_fdBucketSum(weekLo, weekHi), bucket0, "f07: buckets unmoved while refused");
        assertEq(uint256(k.core_.getListing(g).status), 1, "f07: no terminal transition while stale");
        (bytes32 slotId,, bool eligible) = k.b.rewardTerms(g);
        assertEq(slotId, id, "f07: entitlement slot intact");
        assertTrue(eligible, "f07: entitlement survives the outage");
    }

    /// @dev Bond recovery is INDEPENDENT while settlement remains
    /// unavailable: recognition already made the full 1,000 refundable and
    /// claim needs no FD, no Voting, no gauge.
    function _f07BondIndependentDuringOutage(Kit memory k, bytes32 id, address g) private {
        address rep = reporter_();
        uint256 rep0 = IErc20Venue(CRVUSD).balanceOf(rep);
        (uint256 stakeB, uint256 rewardB) = k.b.claim(id);
        assertEq(stakeB, STAKE, "f07: bond recovered during the outage");
        assertEq(rewardB, 0, "f07: unfunded reward never forced");
        assertEq(IErc20Venue(CRVUSD).balanceOf(rep) - rep0, STAKE, "f07: exact independent refund");
        g;
    }

    /// @dev Zero-delta refresh through the permissionless post-deadline path
    /// (no FD write permissions exercised): the cursor moves to now, the
    /// token custody and every weekly bucket do NOT.
    function _f07ZeroDeltaRefresh(Kit memory k) private returns (uint256 cursor) {
        uint256 t2 = block.timestamp;
        fvm.warp((t2 / WEEK) * WEEK + WEEK + 3600); // early in a fresh week
        uint256 balBefore = IErc20Venue(CRVUSD).balanceOf(FEEDIST);
        uint256 residual0 = _fdResidual();
        (uint256 weekLo, uint256 weekHi) = _fdBucketWindow();
        uint256 bucketBefore = _fdBucketSum(weekLo, weekHi);
        fvm.prank(reporter_());
        IFdVenue(FEEDIST).checkpoint_token();
        cursor = IFdVenue(FEEDIST).last_token_time();
        assertEq(cursor, block.timestamp, "f07: refresh landed on now");
        // ZERO-DELTA: the refresh moves NO token — custody unchanged, the
        // accounted balance snaps to custody, and the buckets absorb exactly
        // the pre-existing unaccounted residual (nothing is invented).
        assertEq(IErc20Venue(CRVUSD).balanceOf(FEEDIST), balBefore, "f07: refresh is ZERO-DELTA in custody");
        assertEq(IFdVenue(FEEDIST).token_last_balance(), balBefore, "f07: refresh accounted the balance exactly");
        assertEq(_fdBucketSum(weekLo, weekHi) - bucketBefore, residual0, "f07: buckets absorb only the residual");
        k;
    }

    /// @dev STRICT public cooldown: at the exact one-day boundary the FD
    /// refuses (can_checkpoint_token false, settlement reverts, still
    /// neither half paid); one second later the retry settles, the actual
    /// tokens_per_week deltas reconcile to F, and the funded half is
    /// claimable ON TOP of the already-independently-recovered bond.
    function _f07StrictCooldownRetryAndClaim(Kit memory k, bytes32 id, address g, uint256 cursor) private {
        fvm.warp(cursor + 86400);
        // Exact-boundary witness: the FD's public condition is
        // `now > last_token_time + 86400`, so at EQUALITY it still refuses.
        assertEq(block.timestamp, IFdVenue(FEEDIST).last_token_time() + 86400, "f07: at the strict boundary");
        fvm.prank(reporter_());
        vm.expectRevert(); // checkpoint refusal inside the mandatory accounting
        k.core_.confiscate(g);
        (, uint256 credits2,) = k.b.accounting();
        assertEq(credits2, 0, "f07: still neither half paid at the boundary");
        fvm.warp(cursor + 86401);
        assertTrue(block.timestamp > IFdVenue(FEEDIST).last_token_time() + 86400, "f07: cooldown cleared past +86400");
        (uint256 weekLo2, uint256 weekHi2) = _fdBucketWindow();
        uint256 bucket1 = _fdBucketSum(weekLo2, weekHi2);
        uint256 residual1 = _fdResidual();
        uint256 fdBefore2 = IErc20Venue(CRVUSD).balanceOf(FEEDIST);
        fvm.prank(reporter_());
        uint256 gross = k.core_.confiscate(g);
        assertEq(gross, FEE, "f07: retry settles the full remainder");
        assertEq(IErc20Venue(CRVUSD).balanceOf(FEEDIST) - fdBefore2, FEE / 2, "f07: FD received exactly F");
        assertEq(IErc20Venue(CRVUSD).balanceOf(address(k.b)), FEE / 2, "f07: B pulled into bounty custody");
        assertEq(IFdVenue(FEEDIST).last_token_time(), block.timestamp, "f07: mandatory checkpoint advanced");
        assertEq(
            IFdVenue(FEEDIST).token_last_balance(),
            IErc20Venue(CRVUSD).balanceOf(FEEDIST),
            "f07: postcondition cursor==now accounted balance"
        );
        _assertBucketGain(weekLo2, weekHi2, bucket1, residual1 + FEE / 2, "f07: tokens_per_week deltas reconcile to F");
        (uint256 stakeF, uint256 rewardF) = k.b.claim(id);
        assertEq(stakeF, 0, "f07: bond was already recovered independently");
        assertEq(rewardF, FEE / 2, "f07: funded half paid after settlement");
        (uint256 heldF, uint256 creditsF, uint256 daoF) = k.b.accounting();
        assertEq(heldF + creditsF + daoF, 0, "f07: ledger fully discharged");
    }

    // ------------------------------------------------------------------ F08

    function test_Fork_ThinDaoStakeOnlyForfeit() public {
        _freshFork();
        Kit memory k = _deployThinKit();
        address g = _listPrimary(k);
        address rep = reporter_();
        _fundReporter(k, rep, 2);
        (bytes32 id, uint256 voteId8) = _submitForkBallot(k, g, rep, 608, keccak256(abi.encode("f08", g)));
        voteId8;
        _f08Id = id;
        _f08MarkAuthorityAndReservation(k, id);
        _f08RewardSurvivalAndFlush(k, id, g);
        _f08GenuinelyRefundedControl(k);
    }

    /// @dev Unauthorized attempts refuse at the intended authority; the
    /// current config owner's sole mark reserves exactly 1,000 and moves
    /// nothing else (full report-view fingerprint, liabilities); the repeat
    /// mark is inert.
    function _f08MarkAuthorityAndReservation(Kit memory k, bytes32 id) private {
        fvm.prank(reporter_());
        vm.expectRevert(IGaugeBounty.NotDao.selector);
        k.b.markFrivolous(id);
        (uint256 heldPre, uint256 credPre, uint256 daoPre) = k.b.accounting();
        assertEq(heldPre, STAKE, "f08: bond held pre-mark");
        assertEq(credPre, 0, "f08: no credit pre-mark");
        assertEq(daoPre, 0, "f08: no liability pre-mark");
        ReportView memory pre = k.b.getReport(id);
        pre.stakeState = uint8(StakeState.None);
        fvm.prank(THIN_AGENT);
        assertTrue(k.b.markFrivolous(id), "f08: sole mark applied");
        ReportView memory post = k.b.getReport(id);
        post.stakeState = uint8(StakeState.None);
        assertEq(keccak256(abi.encode(post)), keccak256(abi.encode(pre)), "f08: only the bond disposition moved");
        (uint256 held1, uint256 credits1, uint256 dao1) = k.b.accounting();
        assertEq(held1, 0, "f08: bond left held custody");
        assertEq(credits1, 0, "f08: no credit side effects");
        assertEq(dao1, STAKE, "f08: exactly 1,000 reserved to the pinned FD");
        assertTrue(k.b.getReport(id).reporter != address(0), "f08: vote untouched");
        fvm.prank(THIN_AGENT);
        assertFalse(k.b.markFrivolous(id), "f08: mark is once");
        (uint256 held1b, uint256 cred1b, uint256 dao1b) = k.b.accounting();
        assertEq(held1b, held1, "f08: repeat mark held");
        assertEq(cred1b, credits1, "f08: repeat mark credited");
        assertEq(dao1b, dao1, "f08: repeat mark reserved");
    }

    /// @dev The marked case still runs its REAL ballot to recognition and
    /// positive allocation (reward unchanged before/after allocation by the
    /// mark), then the reserved stake reaches the real FD through the
    /// delayed permissionless safe flush with bucket reconciliation.
    function _f08RewardSurvivalAndFlush(Kit memory k, bytes32 id, address g) private {
        uint256 voteId = k.b.getReport(id).proposalId;
        _castYes(voteId);
        _executeAtVoteEnd(k, id, voteId);
        assertEq(uint8(k.b.getReport(id).phase), 3, "f08: forfeited case still recognized");
        (bytes32 slotId,, bool eligible) = k.b.rewardTerms(g);
        assertEq(slotId, id, "f08: entitlement intact after mark");
        assertTrue(eligible, "f08: mark never cancelled the entitlement");
        fvm.prank(reporter_());
        uint256 gross = k.core_.confiscate(g);
        assertEq(gross, FEE, "f08: allocation proceeds for the marked case");
        ReportView memory rv3 = k.b.getReport(id);
        assertEq(rv3.rewardCredit, FEE / 2, "f08: positive reward survived the mark");
        assertTrue(rv3.rewardCredit > 0, "f08: reward is genuinely positive");
        (uint256 h4, uint256 c4, uint256 d4) = k.b.accounting();
        assertEq(h4, 0, "f08: forfeited bond never double-counted");
        assertEq(c4, FEE / 2, "f08: reward credit funded");
        assertEq(d4, STAKE, "f08: liability still reserved");
        _f08DelayedFlush(k);
    }

    /// @dev Real delayed safe flush: the reserved stake reaches the actual
    /// FD through the accepted accounting path (permissionless keeper), with
    /// exact custody and weekly-bucket reconciliation.
    function _f08DelayedFlush(Kit memory k) private {
        fvm.warp(block.timestamp + 86401); // strict FD cooldown after settle
        (uint256 weekLo, uint256 weekHi) = _fdBucketWindow();
        uint256 bucket0 = _fdBucketSum(weekLo, weekHi);
        uint256 residual0 = _fdResidual();
        uint256 fdBefore = IErc20Venue(CRVUSD).balanceOf(FEEDIST);
        fvm.prank(reporter_());
        assertEq(k.b.flushDao(STAKE), STAKE, "f08: delayed safe flush");
        assertEq(IErc20Venue(CRVUSD).balanceOf(FEEDIST) - fdBefore, STAKE, "f08: real FD custody delta");
        _assertBucketGain(weekLo, weekHi, bucket0, residual0 + STAKE, "f08: FD buckets +stake");
        assertEq(IFdVenue(FEEDIST).last_token_time(), block.timestamp, "f08: flush accounted mandatorily");
        assertEq(_acctHash(k), keccak256(abi.encode(0, FEE / 2, 0)), "f08: only the funded reward credit remains");
        (uint256 stakePaid, uint256 rewardPaid) = k.b.claim(_f08Id);
        assertEq(stakePaid, 0, "f08: forfeited bond is not claimable");
        assertEq(rewardPaid, FEE / 2, "f08: the marked case still gets its half");
    }

    bytes32 private _f08Id;

    /// @dev Genuinely REFUNDED post-refund control: a second listing's case
    /// pays its full bond AND reward, reaching StakeState.Refunded; marking
    /// THAT case is inert — the paid stake never comes back, no liability is
    /// invented and the Rewarded state/claims stay intact.
    function _f08GenuinelyRefundedControl(Kit memory k) private {
        address rep = reporter_();
        address g2 = _listSecond(k);
        (bytes32 id2, uint256 voteId2) = _submitForkBallot(k, g2, rep, 609, keccak256(abi.encode("f08b", g2)));
        _castYes(voteId2);
        _executeAtVoteEnd(k, id2, voteId2);
        assertEq(uint8(k.b.getReport(id2).phase), 3, "f08b: second case recognized");
        fvm.warp(block.timestamp + 86401); // strict FD cooldown after the last settle
        fvm.prank(rep);
        uint256 gross2 = k.core_.confiscate(g2);
        assertTrue(gross2 > 0, "f08b: second case settles positive");
        (uint256 stake2, uint256 reward2) = k.b.claim(id2);
        assertEq(stake2, STAKE, "f08b: bond REFUNDED for real");
        assertEq(reward2, gross2 / 2, "f08b: reward paid");
        assertEq(uint8(k.b.getReport(id2).stakeState), uint8(StakeState.Refunded), "f08b: Refunded state");
        (uint256 heldR, uint256 credR, uint256 daoR) = k.b.accounting();
        fvm.prank(THIN_AGENT);
        assertFalse(k.b.markFrivolous(id2), "f08b: mark on a genuinely refunded case is inert");
        (uint256 heldR2, uint256 credR2, uint256 daoR2) = k.b.accounting();
        assertEq(heldR2, heldR, "f08b: refunded mark moved no bond custody");
        assertEq(credR2, credR, "f08b: refunded mark moved no credit");
        assertEq(daoR2, daoR, "f08b: refunded mark invented no liability");
        assertEq(uint8(k.b.getReport(id2).phase), uint8(Phase.Rewarded), "f08b: rewarded state intact");
        (uint256 s3, uint256 r3) = k.b.claim(id2);
        assertEq(s3 + r3, 0, "f08b: nothing repeats after the inert mark");
    }
}
