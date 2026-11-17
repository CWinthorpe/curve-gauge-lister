# Intel: YB → Votium/VoteMarket on-chain funding (operator pointer, msg 2026-11-12)

Source of truth for real bribe-platform ingestion. Verified 2026-11-12:
Sourcify exact_match (chainId 1) for all three; live storage reads via
https://ethereum-rpc.publicnode.com.

## Contracts
- DepositPlatformDivider `0x0997f89c451124eadf00f87de77924d77a38419a` (MIT)
  - claims YB from Curve vesting, splits by helper weights (65% Votium /
    35% VoteMarket), pulls-free `notifyReward(amount)` on each helper.
- DepositHelperVotium `0x5005DE019301aB6b744B6EFbB942E9A8999EEeC7` (MIT)
  - `notifyReward` from Divider → `depositUnevenSplitGauges(token, round,
    gauges, amounts, maxPerVote, excluded)` on Votium v2
    `DEPOSIT_ADDRESS = 0x63942E31E98f1833A234077f47880A66136a2D1e`,
    round = `activeRound()` at call time; approval to deposit address set
    once in constructor (unlimited).
- DepositHelperVoteMarket `0xfD97b14E1d91B82936e35aE7b20dA4FD16C855B1` (AGPL-3.0)
  - LIVE READS: owner == manager == 0x40907540d8a6c65c637785e8f8b742ae6b0b9968;
    votemarket = 0x8c2c5a295450ddff4cb360ca73fccc12243d14d9 (Arbitrum side);
    campaignRemoteManager = 0x53ad4cd1f1e52dd02aa9fc4a8250a1b74f351ca2 (L1);
    rewardToken = YB 0x01791f726b4103694969820be083196cc7c045ff;
    maxRewardPerVote = type(uint256).max;
    gasSettings = (campaignCreationGas 2_000_000, blacklistedAddressGas
    50_000, gasPrice 1 gwei).
  - KEY MECHANISM: on-chain L1 funding of an L2 campaign — approve
    rewardToken to CampaignRemoteManager, then
    `CampaignRemoteManager.createCampaign{value: additionalGasLimit *
    gasPrice}(CampaignCreationParams{chainId: block.chainid, gauge, manager,
    rewardToken, numberOfPeriods: 2, maxRewardPerVote, totalRewardAmount,
    addresses: excludeAddresses, hook, isWhitelist: false},
    DESTINATION_CHAIN_ID = 42161, additionalGasLimit, votemarket)`.
    Requires ETH float: gauges × additionalGasLimit × gasPrice.
    Cross-chain delivery via VoteMarket's LaPoste messenger (error names in
    the interface: OnlyLaPoste/InvalidSender). Campaign creation is
    ASYNCHRONOUS — L1 success does not itself prove L2 campaign live; the
    campaign id surfaces on L2.

## Implications for CurveGaugeLister adapters (exec3 scope)
1. Both platforms ARE plain mainnet calls from the escrow's perspective;
   the earlier "bridge problem" note is obsolete.
2. VotiumAdapter: approve crvUSD to 0x63942E31...2D1e (bounded, per deposit
   flow), call depositUnevenSplitGauges (single-gauge arrays) for
   activeRound(); receipt = keccak of (round, gauge, amount).
3. VoteMarketAdapter: approve crvUSD to CampaignRemoteManager
   0x53ad4cd1...1ca2, call createCampaign{value} with params bound to
   (block.chainid, gauge, manager = adapter), numberOfPeriods = 2,
   maxRewardPerVote from config; needs payable ETH float + owner/topup
   path and an ETH-shortfall revert (do NOT silently skip a quarter —
   core requires exact funding; adapter must revert and the checkpoint
   rolls back, same as today's mocks).
4. DELIBERATE DEVIATIONS from the YB helpers in our adapters:
   - no owner `execute()` / `withdrawEther` surface;
   - no unlimited standing approvals — approve exact amount, clear after
     (matches core §7 pattern), except where platform ABI requires
     standing approvals, then cap and document;
   - per-gauge deposit binding (our model), not shared weights array;
   - AGPL license of the VoteMarket helper: we reimplement the call, not
     copy source.
5. Adapter unit tests use faithful CampaignRemoteManager + Votium mocks
   (new, mirroring the exact ABI above); integration against real
   platforms stays a pre-mainnet checklist item (crvUSD acceptance at both
   platforms, MINIMUM_PERIODS value, round-mapping for late tranches).
