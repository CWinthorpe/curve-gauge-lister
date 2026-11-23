// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {
    ForkFixture,
    FVm,
    IVotiumVenue,
    ICrmmVenue,
    ITokenFactoryVenue,
    ICcipAdapterVenue,
    IRouterVenue,
    IErc20Venue
} from "./ForkFixture.sol";
import {CurveGaugeLister} from "../../contracts/CurveGaugeLister.sol";
import {VoteMarketAdapter} from "../../contracts/adapters/VoteMarketAdapter.sol";

/// @notice Abstract VoteMarket split/rollback specification,
/// plans/FORK-PLAN.md §7 runner `VoteMarket` (lean-audit2 reduced set: mixed
/// split, ETH shortfall rollback, real CRM guards). Concrete only in
/// fork/VoteMarket.t.sol.
abstract contract ForkVoteMarketSpec is ForkFixture {
    /// @dev Nonzero alternate destination proven absent from the real CRM
    /// platform whitelist (read live in test 14; never whitelisted here).
    address internal constant ALT_DESTINATION = address(uint160(0xD1CE));

    function setUp() public virtual {
        _freshFork();
    }

    // ------------------------------------------------------------------
    // Shared §6.2 proof: one genuine campaign message at `ts` for `gross`
    // (split across helpers to keep every stack frame shallow)
    // ------------------------------------------------------------------

    struct ProverPre {
        Snap s;
        uint256 payerEth;
        uint256 keeperEth;
        uint256 daoEth;
        uint256 laPosteEth;
        uint256 ccipAdapterEth;
        uint256 crmEth;
    }

    function _proveCrmFacts(VoteMarketAdapter vma) internal view {
        assertTrue(ICrmmVenue(CRM).whitelistedPlatforms(VM_DESTINATION), "real platform whitelisted");
        assertEq(ICrmmVenue(CRM).LA_POSTE(), LA_POSTE, "CRM posts via real LaPoste");
        assertEq(ICrmmVenue(CRM).TOKEN_FACTORY(), TOKEN_FACTORY, "CRM locks via real TokenFactory");
        assertEq(ITokenFactoryVenue(TOKEN_FACTORY).CHAIN_ID(), FORK_CHAIN_ID, "source chain 1");
        assertEq(ICcipAdapterVenue(CCIP_ADAPTER).BASE_GAS_LIMIT(), CCIP_BASE_GAS_LIMIT, "bridge base budget");
        assertEq(vma.campaignCreationGas(), CAMPAIGN_CREATION_GAS, "creation gas live");
        assertEq(vma.gasPrice(), ADAPTER_GAS_PRICE, "gas price live");
        // R8-3: the derived router identity is pinned to the corrected
        // address (emitted getter result == actual getFee/ccipSend callee).
        assertEq(ICcipAdapterVenue(CCIP_ADAPTER).router(), CCIP_ROUTER, "derived CCIP router identity");
        uint64 chainSelector = uint64(ICcipAdapterVenue(CCIP_ADAPTER).getBridgeChainId(VM_DEST_CHAIN_ID));
        assertTrue(chainSelector != 0, "bridge chain selector present");
        assertTrue(IRouterVenue(CCIP_ROUTER).isChainSupported(chainSelector), "real router supports destination");
        // Downstream extra-args budget = additional gas + the bridge's actual
        // base budget (§6.2; real adapter getter, not assumed). The exact
        // extraArgs BYTES are asserted in the router reconciliation below.
        assertEq(
            CAMPAIGN_CREATION_GAS + ICcipAdapterVenue(CCIP_ADAPTER).BASE_GAS_LIMIT(), 2_050_000, "extra-args budget"
        );
    }

    function _expectCrmCampaign(VoteMarketAdapter vma, uint256 gross) internal {
        fvm.expectCall(
            CRM,
            CALL_VALUE,
            abi.encodeWithSelector(
                ICrmmVenue.createCampaign.selector,
                _expectedCampaignParams(vma, gross),
                VM_DEST_CHAIN_ID,
                CAMPAIGN_CREATION_GAS,
                VM_DESTINATION
            )
        );
    }

    function _captureProverPre(Trio memory t) internal view returns (ProverPre memory p) {
        p.s = _snap(t);
        p.payerEth = payer().balance;
        p.keeperEth = keeper().balance;
        p.daoEth = DAO.balance;
        p.laPosteEth = LA_POSTE.balance;
        p.ccipAdapterEth = CCIP_ADAPTER.balance;
        p.crmEth = CRM.balance;
    }

    function _assertCustodyChain(Trio memory t, Snap memory before, FVm.Log[] memory logs, uint256 gross)
        internal
        view
    {
        assertEq(
            IErc20Venue(CRVUSD).balanceOf(address(t.lister)),
            before.listerCrv - QUARTER,
            "lister debited full quarter (this venue share + co-routed share)"
        );
        assertEq(_snap(t).tfCrv - before.tfCrv, gross, "final custody: TokenFactory locked exactly gross");
        assertEq(IErc20Venue(CRVUSD).balanceOf(address(t.vma)), before.vmaCrv, "adapter retains nothing");
        assertEq(IErc20Venue(CRVUSD).balanceOf(CRM), before.crmCrv, "CRM retains nothing (+gross NOT the oracle)");
        assertEq(_tokenTransferCount(logs, address(t.lister), address(t.vma), gross), 1, "Transfer lister->adapter");
        assertEq(_tokenTransferCount(logs, address(t.vma), CRM, gross), 1, "Transfer adapter->CRM");
        assertEq(_tokenTransferCount(logs, CRM, TOKEN_FACTORY, gross), 1, "Transfer CRM->TokenFactory (burn lock)");
        // CX-FORK-TRACE: the product-owned approval legs are bounded as
        // COMPLETE owner/spender-scoped traces (every observed value must
        // match the expected multiplicity; a count of one value does not
        // bound the others). Legitimate token-generated decrements from the
        // consuming transferFrom stay in the expected trace: per deposit the
        // lister->adapter pair is [0, gross, 0, 0] (zero reset, exact set,
        // consumption, single checked clear) and the adapter->CRM pair is
        // [0, gross, 0, 0] likewise.
        uint256[] memory listerTrace = new uint256[](4);
        listerTrace[0] = 0;
        listerTrace[1] = gross;
        listerTrace[2] = 0;
        listerTrace[3] = 0;
        uint256[] memory crmTrace = new uint256[](4);
        crmTrace[0] = 0;
        crmTrace[1] = gross;
        crmTrace[2] = 0;
        crmTrace[3] = 0;
        _assertApprovalTrace(logs, address(t.lister), address(t.vma), listerTrace, "vma leg: lister approval trace");
        _assertApprovalTrace(logs, address(t.vma), CRM, crmTrace, "vma leg: bounded approval trace");
        // The third-party CRM->TokenFactory leg is a venue-internal pattern:
        // the exact-gross approval is counted, the final cleared allowance
        // and full custody movement are asserted below/above — no delivery
        // claim is read from any of these observations.
        assertEq(_tokenApprovalCount(logs, CRM, TOKEN_FACTORY, gross), 1, "Approval CRM->TokenFactory");
        _assertZeroApprovals(t);
    }

    function _assertMessageProof(Trio memory t, Snap memory before, FVm.Log[] memory logs, uint256 gross) internal {
        assertEq(_snap(t).lpNonce - before.lpNonce, 1, "sentNonces +1 per committed campaign");
        (bytes32 nonceTopic, bytes32 senderTopic, address to, LpMessage memory message) = _requireMessageSent(logs);
        assertEq(uint256(nonceTopic), before.lpNonce + 1, "message nonce topic");
        assertEq(address(uint160(uint256(senderTopic))), CRM, "indexed sender = CRM");
        assertEq(to, CRM, "log to = CRM");
        _assertCampaignMessage(message, before.lpNonce + 1, address(t.vma), gross);
        emit log_named_uint("laPoste nonce", uint256(nonceTopic));
        // CRM payload event (tuple is indexed: a hash topic, fields proved
        // from the full call/message data above).
        assertEq(_countLogs(logs, CRM, T_CAMPAIGN_PAYLOAD_SENT), 1, "real CampaignCreationPayloadSent");
    }

    /// @dev R8-3: independent router fee/refund reconciliation. The three
    /// observations are independent of each other: (1) the live router quote
    /// (genuine getFee call with the exact reconstructed message), (2) the
    /// actual ccipSend value (expectCall bound the adapter's own send to the
    /// identical calldata at exactly this value), (3) the real refund credited
    /// to the adapter's receive (float observation). The float identity is
    /// then checked against (1)+(2), never against its own rearrangement.
    function _assertFloatReconciliation(ProverPre memory pre, VoteMarketAdapter vma, uint256 observedFee)
        internal
        view
    {
        uint256 floatAfter = address(vma).balance;
        assertEq(floatAfter, pre.s.vmaEth - observedFee, "floatAfter = floatBefore - observed router fee");
        assertTrue(observedFee > 0, "router charged a positive fee");
        assertTrue(observedFee < CALL_VALUE, "fee within the forwarded value");
        // No ETH sticks to any intermediary, payer, keeper or owner.
        assertEq(CRM.balance, pre.crmEth, "CRM retains no ETH");
        assertEq(LA_POSTE.balance, pre.laPosteEth, "LaPoste retains no ETH");
        assertEq(CCIP_ADAPTER.balance, pre.ccipAdapterEth, "CCIP adapter retains no ETH");
        assertEq(payer().balance, pre.payerEth, "no ETH to payer");
        assertEq(keeper().balance, pre.keeperEth, "no ETH to keeper");
        assertEq(DAO.balance, pre.daoEth, "no ETH to owner");
    }

    /// @dev R8-3 preamble (split out for stack headroom): rebuild the exact
    /// downstream message, assert the extra-args BYTES, live-quote the REAL
    /// router, and expect the adapter's own getFee call plus its ccipSend at
    /// exactly the quoted value. Returns the observed quote.
    function _quoteAndBindRouter(VoteMarketAdapter vma, uint256 vmGross) internal returns (uint256 routerQuote) {
        uint64 destSelector = uint64(ICcipAdapterVenue(CCIP_ADAPTER).getBridgeChainId(VM_DEST_CHAIN_ID));
        IRouterVenue.CcipEvm2AnyMessage memory ccipMsg = _buildCcipMessage(_expectedLaposteMessage(vma, vmGross));
        assertEq(
            keccak256(ccipMsg.extraArgs),
            keccak256(abi.encodePacked(CCIP_EXTRA_ARGS_TAG, abi.encode(uint256(2_050_000)))),
            "extra-args bytes: tag 0x97a657c9 + gas 2050000"
        );
        routerQuote = IRouterVenue(CCIP_ROUTER).getFee(destSelector, ccipMsg);
        assertTrue(routerQuote > 0 && routerQuote < CALL_VALUE, "live router quote positive and within value");
        fvm.expectCall(CCIP_ROUTER, abi.encodeCall(IRouterVenue.getFee, (destSelector, ccipMsg)));
        fvm.expectCall(CCIP_ROUTER, routerQuote, abi.encodeCall(IRouterVenue.ccipSend, (destSelector, ccipMsg)));
    }

    /// @dev Per-quarter facts bundled to keep the prover's stack frame
    /// shallow: weekly timestamp, VoteMarket gross/local nonce, the Votium
    /// leg's round/gross (zero for the pure path) and the live router quote.
    struct QuarterCtx {
        uint256 ts;
        uint256 vmGross;
        uint256 nonce;
        uint256 votiumRound;
        uint256 votiumGross;
        uint256 routerQuote;
    }

    /// @dev Post-checkpoint record/event binding for one quarter (R8-2):
    /// custody chain, message, keyed+chronological adapter record, the
    /// adapter's CampaignDeposit event, the lister's per-leg PlatformDeposit
    /// events and receipts, the Votium leg when mixed (R8-1), and the
    /// independent float reconciliation (R8-3).
    function _assertQuarterOutcome(Trio memory t, ProverPre memory pre, FVm.Log[] memory logs, QuarterCtx memory c)
        internal
    {
        _assertCustodyChain(t, pre.s, logs, c.vmGross);
        _assertMessageProof(t, pre.s, logs, c.vmGross);
        _assertAdapterRecord(t, c.ts, c.vmGross, c.nonce);
        _assertCampaignDepositLog(logs, t.vma, c.ts, c.vmGross, c.nonce);
        _assertListerPlatformDeposit(
            logs,
            address(t.lister),
            address(t.vma),
            c.ts,
            c.vmGross,
            keccak256(abi.encode(GAUGE_PRIMARY, c.ts, c.vmGross, c.nonce))
        );
        if (c.votiumGross > 0) {
            _assertVotiumLegEvents(t, logs, c.votiumGross, 1);
            _assertListerPlatformDeposit(
                logs,
                address(t.lister),
                address(t.va),
                c.ts,
                c.votiumGross,
                keccak256(abi.encode(GAUGE_PRIMARY, c.ts, c.votiumGross, c.votiumRound))
            );
        }
        _assertFloatReconciliation(pre, t.vma, c.routerQuote);
        // Anchored post-step Listing check (R8-2): in the single-listing
        // fixture law the cumulative funded-quarter count IS the adapter's
        // local nonce, so every prover call (including test 14's successful
        // controls) carries the complete expected ledger, not only the
        // runner-level spot checks.
        _assertLedger(t, GAUGE_PRIMARY, uint8(c.nonce), c.nonce == EPOCHS);
    }

    /// @dev Run one matured keeper checkpoint whose VoteMarket share must
    /// produce the exact CRM call, custody chain, message, receipt and — R8-3 —
    /// the live router quote/send/refund reconciliation. In mixed mode pass
    /// the Votium leg's round/gross so the SAME checkpoint proves both legs
    /// (R8-1); pass gross 0 for the pure path.
    function _proveCampaignQuarter(
        Trio memory t,
        uint256 vmGross,
        uint256 ts,
        uint256 expectedLocalNonce,
        uint256 votiumRound,
        uint256 votiumGross
    ) internal returns (FVm.Log[] memory logs) {
        _expectCrmCampaign(t.vma, vmGross);
        if (votiumGross > 0) {
            _expectVotiumDeposit(votiumRound, votiumGross);
        }

        // R8-3: live router quote + exact getFee/ccipSend call binding.
        QuarterCtx memory c;
        c.ts = ts;
        c.vmGross = vmGross;
        c.nonce = expectedLocalNonce;
        c.votiumRound = votiumRound;
        c.votiumGross = votiumGross;
        c.routerQuote = _quoteAndBindRouter(t.vma, vmGross);

        ProverPre memory pre = _captureProverPre(t);

        fvm.recordLogs();
        (uint256 rel, uint256 conf) = _keeperCheckpoint(t, GAUGE_PRIMARY);
        assertEq(rel, QUARTER, "quarter released");
        assertEq(conf, 0, "not confiscated");
        logs = fvm.getRecordedLogs();

        _assertQuarterOutcome(t, pre, logs, c);
        return logs;
    }

    // ------------------------------------------------------------------
    // 12
    // ------------------------------------------------------------------

    /// @dev §7.12 Mixed 6500/3500 split across four weeks funding BOTH real
    /// venues: per-quarter 1625 gross Votium (1592.5 net / 32.5 fee) and 875
    /// gross to CRM/TokenFactory; cumulative totals exact.
    function test_Fork_MixedSplitFourWeeksFundsBothRealVenues() public {
        Trio memory t = _seedStandard(6500);
        _topUpVm(t, FIXTURE_ETH_FLOAT);
        _proveCrmFacts(t.vma); // once per freshly initialized VM fixture

        uint256 votiumGross = (QUARTER * 6500) / 10_000; // 1625e18
        uint256 vmGross = QUARTER - votiumGross; // 875e18
        assertEq(votiumGross, 1625e18, "split math");
        assertEq(vmGross, 875e18, "split remainder");

        Snap memory seed = _snap(t);
        for (uint256 k = 0; k < 4; ++k) {
            uint256 ts = _maturity(k);
            uint256 round = _maturityRound(k);
            fvm.warp(ts);
            assertEq(IVotiumVenue(VOTIUM).activeRound(), round, "actual time-derived round");

            uint256 lenBefore = IVotiumVenue(VOTIUM).incentivesLength(round, GAUGE_PRIMARY);
            Snap memory votBefore = _snap(t);
            FVm.Log[] memory qLogs = _proveCampaignQuarter(t, vmGross, ts, k + 1, round, votiumGross);

            // Votium side of the same quarter (gross/net/fee exact).
            assertEq(IVotiumVenue(VOTIUM).incentivesLength(round, GAUGE_PRIMARY), lenBefore + 1, "one votium incentive");
            _assertIncentive(address(t.va), round, lenBefore, votiumGross);
            _assertVotiumDeltas(votBefore, _snap(t), votiumGross);
            assertEq(_countLogs(qLogs, address(t.va), T_VOTIUM_DEPOSIT), 1, "VotiumDeposit once");
            assertEq(_countLogs(qLogs, address(t.lister), T_QUARTER_RELEASED), 1, "QuarterReleased once");
            assertEq(_countLogs(qLogs, address(t.lister), T_PLATFORM_DEPOSIT), 2, "two PlatformDeposits (split)");

            // Post-quarter ledger/approvals are checked inside the shared
            // prover (_assertQuarterOutcome); only the adapters-empty check
            // is distinct out here.
            _assertAdaptersEmpty(t);
        }

        // Cumulative exactness across both venues.
        Snap memory post = _snap(t);
        assertEq(post.tfCrv - seed.tfCrv, 3500e18, "cumulative 3500e18 locked in TokenFactory");
        assertEq(post.votiumCrv - seed.votiumCrv, 6370e18, "cumulative votium net 6370e18");
        assertEq(post.feeCrv - seed.feeCrv, 130e18, "cumulative votium fee 130e18");
        assertEq(post.lpNonce - seed.lpNonce, 4, "four real messages");
        assertEq(post.vmaDeposits - seed.vmaDeposits, 4, "four adapter deposits");
        assertEq(post.fdCrv - seed.fdCrv, 0, "no FD increment");
        assertEq(post.listerCrv, seed.listerCrv - 10_000e18, "all gross left the core");
        assertEq(t.lister.totalEscrow(), 0, "escrow cleared to Exhausted");
        assertEq(uint256(t.lister.getListing(GAUGE_PRIMARY).status), 2, "Exhausted");
    }

    // ------------------------------------------------------------------
    // 13
    // ------------------------------------------------------------------

    /// @dev §7.13 Mixed ETH shortfall: one wei short, the REAL adapter
    /// InsufficientEth reverts the whole checkpoint including the provisional
    /// Votium funding; after topping the missing wei exactly one mixed
    /// quarter funds, never double.
    function test_Fork_VoteMarketEthShortfallRollsBackMixedCheckpoint() public {
        Trio memory t = _seedStandard(6500);
        _proveCrmFacts(t.vma); // once per freshly initialized VM fixture
        // Top up so the adapter holds EXACTLY one-call-required value minus
        // one wei, on top of any pre-existing mainnet dust at this address.
        uint256 vmaEthBase = address(t.vma).balance;
        assertTrue(CALL_VALUE - 1 > vmaEthBase, "base below required minus one");
        _topUpVm(t, CALL_VALUE - 1 - vmaEthBase);
        assertEq(address(t.vma).balance, CALL_VALUE - 1, "one short");

        // ethDeficit prices ONE deposit, not the entire catch-up budget.
        uint256 vmGross = QUARTER - (QUARTER * 6500) / 10_000; // 875e18
        assertEq(t.vma.ethDeficit(vmGross), 1, "shortfall exactly one wei");
        assertEq(t.vma.ethDeficit(0), 0, "zero-amount query reports no deficit");

        fvm.warp(_maturity(0));
        Snap memory before = _snap(t);

        _probeCheckpointRevert(
            t,
            GAUGE_PRIMARY,
            abi.encodeWithSelector(VoteMarketAdapter.InsufficientEth.selector),
            "shortfall reverts the whole checkpoint"
        );

        // The earlier provisional Votium funding in the SAME checkpoint must
        // roll back completely: incentives, virtual balance, venue balances,
        // message nonce, receipts, ledger and allowances unchanged.
        _assertSnapEq(before, _snap(t), "shortfall full rollback");
        assertEq(IVotiumVenue(VOTIUM).incentivesLength(136, GAUGE_PRIMARY), before.len136, "no partial incentive");
        assertEq(IErc20Venue(CRVUSD).allowance(address(t.lister), address(t.vma)), 0, "no dangling approval");
        assertEq(address(t.vma).balance, CALL_VALUE - 1, "float preserved on revert (one-call-required minus one)");
        assertEq(t.vma.depositCount(), 0, "no receipts");
        assertEq(t.lister.totalEscrow(), FEE, "ledger untouched");

        // Add the missing wei through receive and retry: exactly one
        // successful mixed quarter, never double funding.
        _topUpVm(t, 1);
        assertEq(t.vma.ethDeficit(vmGross), 0, "deficit cleared");
        _proveCampaignQuarter(t, vmGross, _maturity(0), 1, 136, 1625e18);
        assertEq(IVotiumVenue(VOTIUM).incentivesLength(136, GAUGE_PRIMARY), before.len136 + 1, "one incentive total");
        assertEq(t.vma.depositCount(), 1, "one campaign deposit total");
    }

    // ------------------------------------------------------------------
    // 14
    // ------------------------------------------------------------------

    /// @dev §7.14 Real CRM guards: wrong source chain and non-whitelisted
    /// platform each revert the full mixed checkpoint with zero side effects.
    function test_Fork_RealCRMRejectsWrongChainAndUnlistedPlatform() public {
        // Subcase A: fork execution chain 31337 for the first call only.
        Trio memory t = _seedStandard(6500);
        _topUpVm(t, FIXTURE_ETH_FLOAT);
        _proveCrmFacts(t.vma); // once per freshly initialized VM fixture
        fvm.warp(_maturity(0));
        Snap memory beforeA = _snap(t);

        fvm.chainId(31337);
        assertEq(block.chainid, 31337, "execution chain changed for this call");
        _probeCheckpointRevert(
            t,
            GAUGE_PRIMARY,
            abi.encodeWithSelector(ICrmmVenue.InvalidChainId.selector),
            "real CRM rejects wrong source chain"
        );
        _assertSnapEq(beforeA, _snap(t), "wrong-chain full rollback (mixed first venue included)");
        assertEq(IVotiumVenue(VOTIUM).incentivesLength(136, GAUGE_PRIMARY), beforeA.len136, "no votium residue");

        fvm.chainId(1);
        assertEq(block.chainid, 1, "chain restored");
        _proveCampaignQuarter(t, 875e18, _maturity(0), 1, 136, 1625e18);
        assertEq(IVotiumVenue(VOTIUM).incentivesLength(136, GAUGE_PRIMARY), beforeA.len136 + 1, "votium funded once");

        // Subcase B: adapter bound to a destination proven absent from the
        // real whitelist (no whitelist edits).
        _freshFork();
        assertFalse(ICrmmVenue(CRM).whitelistedPlatforms(ALT_DESTINATION), "alt destination absent");
        assertTrue(ALT_DESTINATION != address(0), "alt destination nonzero");
        Trio memory t2 = _deployTrioAltVm(6500, ALT_DESTINATION);
        assertEq(t2.vma.votemarket(), ALT_DESTINATION, "adapter immutable alt destination");
        _seat(t2.lister);
        _fundPayer(payer(), 1);
        _approveFee(t2);
        // S05: explicit final activation before the positive listing.
        _activatePaidAdmission(t2);
        fvm.prank(payer());
        t2.lister.listGauge(POOL_PRIMARY, GAUGE_PRIMARY, GAUGE_INDEX, HANDLER_ID);
        _topUpVm(t2, FIXTURE_ETH_FLOAT);
        fvm.warp(_maturity(0));
        Snap memory beforeB = _snap(t2);

        _probeCheckpointRevert(
            t2,
            GAUGE_PRIMARY,
            abi.encodeWithSelector(ICrmmVenue.PlatformNotWhitelisted.selector),
            "real CRM rejects unlisted platform"
        );
        _assertSnapEq(beforeB, _snap(t2), "unlisted-platform full rollback");
        assertEq(IVotiumVenue(VOTIUM).incentivesLength(136, GAUGE_PRIMARY), beforeB.len136, "no first-venue residue");
        assertEq(address(t2.vma).balance, beforeB.vmaEth, "float preserved");

        // Positive control: fresh correctly pinned deployment succeeds.
        _freshFork();
        Trio memory t3 = _seedStandard(6500);
        _topUpVm(t3, FIXTURE_ETH_FLOAT);
        _proveCrmFacts(t3.vma); // once per freshly initialized VM fixture
        fvm.warp(_maturity(0));
        _proveCampaignQuarter(t3, 875e18, _maturity(0), 1, 136, 1625e18);
    }
}
