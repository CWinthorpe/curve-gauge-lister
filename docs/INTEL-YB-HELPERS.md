# Intel: YB → Votium/VoteMarket on-chain funding (operator pointer, msg 2026-11-12)

Historical venue-integration research, not the current deployment or product specification. The observations below were recorded on 2026-11-12 using Sourcify and https://ethereum-rpc.publicnode.com; they are not fresh v1align verification. Current authority is OPERATIONS.md, ABI.md and DEPLOYMENT-PINS.md, together with the candidate's compiled source. In particular, the current Votium receipt is keccak256(abi.encode(gauge, scheduledEpoch, amount, round)); both adapters use exact bounded approvals and clear them, with no standing-approval exception. The old implications below are retained as research history, not permission to change those rules.

## Contracts
- DepositPlatformDivider `0x0997f89c451124eadf00f87de77924d77a38419a` (MIT)
  - claims YB from Curve vesting, splits by helper weights (65% Votium /
    35% VoteMarket), pulls-free `notifyReward(amount)` on each helper.
- DepositHelperVotium `0x5005DE019301aB6b744B6EFbB942E9A8999EEeC7` (MIT)
  - `notifyReward` from Divider → `depositUnevenSplitGauges(token, round,
    gauges, amounts, maxPerVote, excluded)` on Votium v2
    `DEPOSIT_ADDRESS = 0x63942E31E98f1833A234077f47880A66136a2D1e`,
    round = `activeRound()` at call time; approval to deposit address set
    once in constructor (unlimited). [HISTORICAL OBSERVATION OF THE YB
    HELPER — the product does NOT adopt this shape: both adapters use exact
    bounded approvals cleared after every venue call, with NO standing-approval
    exception; current law at `contracts/adapters/VotiumAdapter.sol`
    (`deposit`, `setExcluded`) and docs/OPERATIONS.md. Retained as research
    history, not permission to change those rules.]
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

[HISTORICAL RECORD — these were the exec3-scope implications recorded
2026-11-12. Each formula/exception below is annotated at its site where the
shipped product law differs; the shipping adapters and docs/OPERATIONS.md,
docs/ABI.md and docs/DEPLOYMENT-PINS.md govern. Source provenance, venue
calldata shapes, receipt preimages and the no-standing-approval rule are the
current law; this section is not authority to change them.]

1. Both platforms ARE plain mainnet calls from the escrow's perspective;
   the earlier "bridge problem" note is obsolete.
2. VotiumAdapter: approve crvUSD to 0x63942E31...2D1e (bounded, per deposit
   flow), call depositUnevenSplitGauges (single-gauge arrays) for
   activeRound(); receipt = keccak of (round, gauge, amount).
   [HISTORICAL FORMULA — the shipped preimage is
   `keccak256(abi.encode(gauge, scheduledEpoch, amount, round))` in that
   field order, per `contracts/adapters/VotiumAdapter.sol deposit` and this
   file's header note; the receipt is an adapter-domain ingress correlation,
   event-only on this venue, not a delivery token.]
3. VoteMarketAdapter: approve crvUSD to CampaignRemoteManager
   0x53ad4cd1...1ca2, call createCampaign{value} with params bound to
   (block.chainid, gauge, manager = adapter), numberOfPeriods = 2,
   maxRewardPerVote from config; needs payable ETH float + owner/topup
   path and an ETH-shortfall revert (do NOT silently skip a quarter —
   core requires exact funding; adapter must revert and the checkpoint
   rolls back, same as today's mocks).
   [HISTORICAL: the shipped adapter deliberately has NO owner/topup-withdraw
   path — `receive()` accepts float from anyone and nothing takes ETH back
   out (INTEL §4 deviation); the shortfall revert is `InsufficientEth`.]
4. DELIBERATE DEVIATIONS from the YB helpers in our adapters:
   - no owner `execute()` / `withdrawEther` surface;
   - no unlimited standing approvals — approve exact amount, clear after
     (matches core §7 pattern), except where platform ABI requires
     standing approvals, then cap and document;
     [HISTORICAL: the "matches core §7 pattern" reference was to the retired
     plan section — the stable current reference is the shipped adapters'
     bounded-approve-then-clear law in `contracts/adapters/` and
     docs/OPERATIONS.md. The "except where platform ABI requires standing
     approvals" EXCEPTION WAS NOT ADOPTED: both adapters approve exact,
     clear after, and keep no standing allowance; no venue-side standing-
     approval is used by this product.]
   - per-gauge deposit binding (our model), not shared weights array;
   - AGPL license of the VoteMarket helper: we reimplement the call, not
     copy source.
5. Adapter unit tests use faithful CampaignRemoteManager + Votium mocks
   (new, mirroring the exact ABI above); integration against real
   platforms stays a pre-mainnet checklist item (crvUSD acceptance at both
   platforms, MINIMUM_PERIODS value, round-mapping for late tranches).
