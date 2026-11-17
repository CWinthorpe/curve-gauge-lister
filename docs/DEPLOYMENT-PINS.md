# Deployment pins — Ethereum mainnet (base pins 2026-11-12; V2 trusted-factory amendment)

Operative constructor/config addresses for frozen `CurveGaugeLister`, amended `CurveGaugeListerV2` and their venue adapters on Ethereum mainnet. The V2 trusted-factory addition has its own pinned-block evidence and recipe below. Verified on
**2026-11-12** via `https://ethereum-rpc.publicnode.com` plus
`https://eth.blockscout.com` and `https://docs.curve.finance`. This document
supersedes the earlier "operator pins vs sourced candidates" table (the three void strings failed EIP-55 checksum, had no code on chain, and are NOT deployment constants). There are no unresolved pins.

## Verification infrastructure (exact endpoints used)

- RPC: `https://ethereum-rpc.publicnode.com` — `eth_chainId` = `0x1`
- Explorer cross-check: `https://eth.blockscout.com/api/v2/smart-contracts/<address>`
- Verified sources: `https://sourcify.dev/server/v2/contract/1/<address>?fields=sources,metadata`
  (and `...?fields=sources,abi,metadata,compilation`)
- Docs: `https://docs.curve.finance/developer/fees/fee-distributor`,
  `https://docs.curve.finance/user/dao/emergency-dao`
- `cast` examples below use `--rpc-url https://ethereum-rpc.publicnode.com`;
  raw `eth_call` with the 4-byte selector gives the same result. Re-verify at
  a selected current block, recording its number/hash and chain ID. An immutable lister pointer does not freeze external governance, policy, code or operational state; re-verify those separately.

## Pins

| Role | Address | Verification evidence (method, 2026-11-12) |
| --- | --- | --- |
| GaugeController | `0x2F50D538606Fa9EDD2B11E2446BEb18C9D5846bB` | `eth_getCode` code present; `n_gauge_types()` = 13; `admin()` = `0x40907540d8a6C65c637785e8f8B742ae6b0b9968` |
| crvUSD | `0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E` | `symbol()` = `crvUSD`; `decimals()` = 18; `totalSupply()` = 2,134,809,204.98 crvUSD |
| crvUSD FeeDistributor | `0xD16d5eC345Dd86Fb63C6a9C43c517210F1027914` | `token()` == crvUSD pin; `is_killed()` == false |
| Lister owner | `0x40907540d8a6C65c637785e8f8B742ae6b0b9968` | CurveDAO Aragon org — the GaugeController `admin()` above; passed explicitly as `owner_`; re-verified via blockscout/docs.curve.finance |
| Votium v2 deposit | `0x63942E31E98f1833A234077f47880A66136a2D1e` | Sourcify verified-source match |
| VoteMarket CampaignRemoteManager | `0x53ad4cd1f1e52dd02aa9fc4a8250a1b74f351ca2` | Sourcify verified-source match; chainId-1 source guard confirmed |

Code-size references from the earlier block-26398129 sourcing: GaugeController 12013 bytes, FeeDistributor 6701 bytes, crvUSD 3572
bytes.

## Re-verification recipe

```bash
RPC=https://ethereum-rpc.publicnode.com

# GaugeController — expect 13, 0x40907540d8a6C65c637785e8f8B742ae6b0b9968
cast call 0x2F50D538606Fa9EDD2B11E2446BEb18C9D5846bB "n_gauge_types()(int128)" --rpc-url $RPC
cast call 0x2F50D538606Fa9EDD2B11E2446BEb18C9D5846bB "admin()(address)" --rpc-url $RPC

# crvUSD — expect "crvUSD", 18, 2134809204.98e18 (value drifts with mint/burn)
cast call 0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E "symbol()(string)" --rpc-url $RPC
cast call 0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E "decimals()(uint8)" --rpc-url $RPC
cast call 0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E "totalSupply()(uint256)" --rpc-url $RPC

# FeeDistributor — expect the crvUSD pin and false
cast call 0xD16d5eC345Dd86Fb63C6a9C43c517210F1027914 "token()(address)" --rpc-url $RPC
cast call 0xD16d5eC345Dd86Fb63C6a9C43c517210F1027914 "is_killed()(bool)" --rpc-url $RPC

# Code presence
curl -s $RPC -X POST -H 'content-type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"eth_getCode","params":["0x2F50D538606Fa9EDD2B11E2446BEb18C9D5846bB","latest"]}'

# Venue verified sources (recorded Sourcify match IDs: Votium 2406308
# compiler 0.8.13, CampaignRemoteManager 6106607)
curl -s "https://sourcify.dev/server/v2/contract/1/0x63942E31E98f1833A234077f47880A66136a2D1e?fields=sources,metadata"
curl -s "https://sourcify.dev/server/v2/contract/1/0x53ad4cd1f1e52dd02aa9fc4a8250a1b74f351ca2?fields=sources,metadata"

# EmergencyDAO context (not wired into the lister)
# https://docs.curve.finance/user/dao/emergency-dao
```

`totalSupply` is a live value; only its 2026-11-12 reading
(2,134,809,204.98 crvUSD) is pinned as evidence, not as an expected constant.
The `token()`/`is_killed()` pair is additionally enforced at the lister's own
constructor (`DistributorUnusable` reverts otherwise).

## Constructor wiring

- `CurveGaugeLister(owner_, crvUSD_, controller_, feeDistributor_, admission_,
  platforms_)`: `owner_` = CurveDAO org (row above), `crvUSD_`, `controller_`,
  `feeDistributor_` = pinned rows. The constructor itself re-checks code
  presence and the distributor's `token()`/`is_killed()`.
- `CurveGaugeListerV2(owner_, crvUSD_, controller_, feeDistributor_, admission_, platforms_, bounty_, trustedGaugeValidator_)`: preserve the first seven parameters and pass `trustedGaugeValidator_ = 0x888888c34a46d0b2A34e9204e5273208E670e784` explicitly. The eighth argument has no default; V2 first requires chain 1, then code at immutable dependencies, including the validator (`NoCode` for a zero/EOA validator). The public immutable getter is `trustedGaugeValidator()`. There is no setter. Preserve paused start and reciprocal bounty/adapter binding.
- `VotiumAdapter(crvUSD_, owner_, votium_)`: `votium_` = Votium v2 deposit
  pin.
- `VoteMarketAdapter(crvUSD_, owner_, campaignRemoteManager_, votemarket_)`:
  `campaignRemoteManager_` = C1 pin; `votemarket_` = the Arbitrum-side
  destination `0x8c2c5a295450ddff4cb360ca73fccc12243d14d9`, a
  constructor-pinned pass-through per the binding live reads in
  `docs/INTEL-YB-HELPERS.md` (verify on Arbitrum, chainId 42161, not via the
  mainnet endpoint above).

## V2 trusted-factory validator — verified lineage and re-verification

This addition does not amend V1's constructor or paid behavior. New V2 deployment operators MUST explicitly supply the validator pin below; code presence alone is not authenticity verification.

| Role | Address / pinned observation |
| --- | --- |
| V2 trustedGaugeValidator_ | `0x888888c34a46d0b2A34e9204e5273208E670e784` |
| Exact external predicate | `validateGauge(address gauge) external view returns (bool)`, selector `0xe92cd3d3`; pass the GAUGE |
| Validator runtime | 3,402 bytes, Keccak-256 `0x2d684822a3f2bf6f99f902474289219041443a9d9cc94cbc28505050185016cd` |
| Owner at both verification blocks | `0x40907540d8a6C65c637785e8f8B742ae6b0b9968` |
| Enabled source-manifest initial manager | `0xc0DE00005F21Fa7846BA0EA2E3F2FC4F048a72C9` |
| SS-ng regular gauge-factory policy | `0x6A8cbed756804B16E05E741eDaBd5cB544AE21bf` -> module `0x999902533033Cc63c8128C501e307477932B742E`, method 1 |
| Legacy crypto-factory policy | `0xF18056Bbd320E96A48e3Fbf8bC061322531aac99` -> same module, method 2 |
| Current gauge-module runtime | 1,336 bytes, Keccak-256 `0xfc5562e86bbf44b97a41e6e1e1f578a396c0fd4a5aaac85805ef62630fca36ff` |

The full validator and gauge-module runtime bytes, including metadata, were independently reproduced from `wavey0x/curve-gauge-validator` commit `c1246600ef8aeea452ab0c849bf9135647ee8c4f` with solc `0.8.28+commit.7893614a`, optimizer 200, Cancun, remapping `forge-std/=lib/forge-std/src/`. This is dependency-source verification, not a change to this repository's solc 0.8.30 product profiles. Source: https://github.com/wavey0x/curve-gauge-validator/blob/c1246600ef8aeea452ab0c849bf9135647ee8c4f/src/GaugeValidator.sol and adjacent GaugeValidationModuleV1.sol. The source is a full contract, not a proxy. A Curve organization AutoWrapper precedent was not corroborated; `curvefi/automation` returned 404. Do not present the validator as Curve-organization-authored; provenance rests on the reproduced runtime bytes, the pinned source commit and the DAO's ownership of the deployment.

Commands actually run for the unchanged fork pin (read-only; expected outputs follow):

```bash
cast chain-id --rpc-url https://eth-mainnet.public.blastapi.io
cast block 26401019 --json --rpc-url https://eth-mainnet.public.blastapi.io
cast code 0x888888c34a46d0b2A34e9204e5273208E670e784 --block 26401019 --rpc-url https://eth-mainnet.public.blastapi.io
cast call 0x888888c34a46d0b2A34e9204e5273208E670e784 'owner()(address)' --block 26401019 --rpc-url https://eth-mainnet.public.blastapi.io
cast call 0x888888c34a46d0b2A34e9204e5273208E670e784 'policyForFactory(address)(address,uint8)' 0x6A8cbed756804B16E05E741eDaBd5cB544AE21bf --block 26401019 --rpc-url https://eth-mainnet.public.blastapi.io
cast call 0x888888c34a46d0b2A34e9204e5273208E670e784 'validateGauge(address)(bool)' 0x9f96B45A2ea3Fea791513aa3A7921d474105B23e --block 26401019 --rpc-url https://eth-mainnet.public.blastapi.io
cast call 0x888888c34a46d0b2A34e9204e5273208E670e784 'validateGauge(address)(bool)' 0xfB389aCa09ddC676fC9D5aC3cfD2Cd133bf44E19 --block 26401019 --rpc-url https://eth-mainnet.public.blastapi.io
```

Observed: chain 1; block hash `0x55810b079923a14fb97ad548f5024f65530dbc4fb2357a38f41e13b3d27cb6d3`, timestamp 1794512471; nonempty validator code whose exact bytes/hash are above; DAO owner; module/method 1; true for each gauge. The legacy candidate's distinct LP token `0x1AEa495539B514A5538878D3D3695c7AEDdC61F1` has minter pool `0x03470B57B05089EE40c651dAC9E0387F1f3cb46f`: direct factory lookup on LP returns zero and the pool lookup returns that gauge. The same validator/module runtime and SS-ng reads were rechecked at block 26430187, hash `0x759f2d92d850d038341630d429de7cd9c54817897452d4ca77897978e073817c`, via PublicNode. PublicNode's old-state HTTP 403 responses are retained; Blast supplied the archive reads. An archive error is not empty code or a successful check.

For deployment, choose and record a new fixed current block and repeat code, chain/header, owner/manager, policy/module and actual candidate-gauge reads against that same block; recompile the pinned sources or compare the verified runtime bytes, then record the current state immediately before opening paid admission. Resolve policy changes explicitly rather than expecting old mutable getters to remain constant. The listed manager is one checked key, not an exhaustive manager enumeration; audit ManagerSet/FactoryPolicySet history and current relevant keys before deployment. Preserve the existing fork-test block instead of changing it to refresh operational evidence.

Never use `validateProposalGauges(uint256)` (`0x2da285c4`) for admission. `proposalModule()` (`0xf8dc587d`) returns `0x999903ff5ac376e8cec3f9055ed3a1a7e71f3ab7`, a proposal-validation module, not the paid gauge checker. Do not substitute a factory/LP/pool address for the gauge or accept a nonzero factory-policy mapping without the reciprocal proof. Validator false becomes `UntrustedGauge(gauge)`; top-level read failure, nonexact return length or noncanonical bool becomes `TrustedGaugeCheckFailed(gauge)`. Any failure reverts the entire listing before custody/controller addition. The validator's internal dependency faults can return false and are still rejected. DAO `listGaugeNoEscrow` performs no trust read; existing escrow settlement is not revalidated against later policy changes.

## Roles (authority context)

The lister owner is the CurveDAO Aragon org
`0x40907540d8a6C65c637785e8f8B742ae6b0b9968` — the GaugeController's
`admin()`. It is a regular governance executor, **not a multisig**; it owns
config knobs only (`setPaused`, `setAdmissionConfig`, `setPlatformConfig`,
two-step `transferOwnership`) and has zero fee custody. The EmergencyDAO
(5-of-9 at `0x467947EE34aF926cF1DCac093870f613C96B1E0c`, per
`docs.curve.finance/user/dao/emergency-dao`) is context only — nothing in the
lister is wired to it, and kill detection needs no authority from it: the
gauge-side `is_killed()` flag is the sole kill oracle.

## Still open (not pins)

GaugeAdder seating review, venue integration probes (crvUSD `TokenAllow` at
the live Votium venue, VoteMarket `MINIMUM_PERIODS`, bridge liveness), the
atomic owner-authenticated adapter deployment-and-binding batch and
FeeDistributor operations monitoring (summarized below),
ops ETH float, and a funded trial listing.

## Deployment amendments (binding blockers)

Binding atomism checklist (supersedes the retired first-call-wins guidance):

- Use an authorized atomic deployment-and-binding batch: deploy the
  adapters, deploy the core, bind each adapter to that now-deployed core as
  its actual owner (`setLister` reverts `NotOwner` for anyone else and
  `ListerAlreadySet` after a successful bind), verify both `lister()`
  values and the reward-token/code/split identities, and keep paid
  admissions paused pending the remaining deployment checks. The batch must
  possess the actual owner authority for each call; a factory is not
  implicitly authorized. If temporarily owned by a deployment executor,
  finish the existing two-step handoff to the intended owners and verify it
  before enabling admission.
- Do not expose a partially wired deployment or rely on public transaction
  ordering: owner authentication removes outsider capture before binding
  and paid readiness (`PlatformNotReady`) refuses unbound/wrong-bound
  endpoints even if pause is omitted — but neither replaces the atomic
  deployment receipt and pause gate. A mistaken binding means replacing
  that adapter before accepting fees; no in-place rebinding or migration of
  historical paid snapshots exists.

FeeDistributor operations checklist (supersedes the retired best-effort /
admin-pre-transfer-admin-post guidance):

- Rebind verification to the chosen distributor's deployed code/source and
  record pinned `token`, `is_killed`, `admin`, `can_checkpoint_token`,
  `last_token_time`, `token_last_balance` and actual token balance; verify
  the 20-week-bucket loop and the 86400-second strict cooldown.
- Require public checkpointing enabled for this ordinary lister (it is not
  FD.admin) and monitor the live eligibility window — `now >
  last_token_time + 86400` AND the 20-week safe-accounting freshness horizon —
  polling at least daily; retry killed gauges at the next eligible time. A
  successful token checkpoint (including a confiscation's mandatory
  accounting or any third-party call) resets the SHARED cursor and can
  impose a new cooldown; permissionless callers can repeatedly postpone
  settlement — accepted liveness cost, never a reason to weaken custody.
- For a stale FD keep new confiscation funds in escrow. A separate
  zero-delta refresh is demonstrably lossless only while
  `balanceOf(fd) == token_last_balance()`; verify that condition and cursor
  advancement. A stale FD with a positive unaccounted delta cannot be
  repaired by checkpointing — escalate upstream and keep this lister's
  funds reserved. Lister owner or outer-caller FD-admin identity does not
  confer the inner admin bypass.
- Emergency kills must not depend on seizure succeeding: a kill+confiscate
  atomic batch rolls back the kill too when freshness/accounting fails.
  Execute the real emergency kill separately, leave the flag true, and
  retry the seizure safely. No weight-zero fallback, local kill latch,
  payer refund or owner sweep exists.

## GaugeBounty — beneficiary-bound-ballot dependencies (prospective)

No production deployment or authorization is implied. The bounty constructor has nine fields. Values below are the retained mainnet dependencies from the frozen fork pin; all mutable roles, code identities, script executor binding, ballot semantics and Agent target/value/selector authorization must be re-verified immediately before deployment and before attribution. The bounty does not use project CRV, a voting escrow, a project treasury or a wallet checker.

| Field (constructor tuple order) | Value |
| --- | --- |
| crvUSD | 0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E |
| feeDistributor | 0xD16d5eC345Dd86Fb63C6a9C43c517210F1027914 (token()==crvUSD, not killed, public checkpoint path live) |
| ownershipVoting | 0xE478de485ad2fe566d49342Cbd03E49ed7DB3356 (minBalance 2,500e18; minTime 43,200; voteTime 604,800; support 51.00e16; quorum 30.00e16; enableVoteCreation true) |
| ownershipAgent | 0x40907540d8a6C65c637785e8f8B742ae6b0b9968 (== killProxy.dao() at the pin) |
| killProxy | 0xeDA0108D5bB8cdE2ba4A59E22F3Ed5d211C77187 |
| supportedFactory | 0x6A8cbed756804B16E05E741eDaBd5cB544AE21bf (admin() == killProxy) |
| votingImplementation | 0xa4D1a2693589840BABb7f3A44D14Fdf41b3bF1Fe |
| agentImplementation | 0x3A93C17FC82CC33420d1809dDA9Fb715cc89dd37 |
| callsScriptExecutor | 0x5cEb19e1890f677c3676d5ecDF7c501eBA01A054 (registry getEVMScriptExecutor(0x00000001)) |

Fixed economics: each accepted report posts exactly 1,000 crvUSD. The original Ownership ballot start determines `voteEnd = startDate + 604800`; `executeBy = voteEnd + 604800`. Recognition is inclusive at `executeBy`; unresolved expiry is strictly later. There is no queue timeout, lock horizon, project CRV allocation or shared creator cadence. Reporter proposal rights remain upstream; an eligible sponsor may create a ballot for the named beneficiary.

Deployment order: deploy the bounty, deploy the V2 core paused with initial config owner equal to the configured Ownership Agent, and bind reciprocally through that Agent. Use the legitimate two-step V2 ownership transfer where required. Do not unpause paid admissions until source, role, beneficiary-script, venue and FeeDistributor checks pass. No project CRV funding step exists; reporters or eligible sponsors create beneficiary-bound Ownership ballots, and only the submitting beneficiary approves/posts its crvUSD stake.

Before `submit` and attribution, revalidate the live Ownership `getVote` record, unexecuted state, original clock, exact canonical CallsScript bytes, beneficiary/gauge/report binding, implementation pointers, Agent executor authorization, V2 listing and FeeDistributor custody conditions. The bounty never creates or authorizes a ballot. Any change to the beneficiary-binding mechanism requires a revised, explicitly approved pin table — never a silent edit to this document.
