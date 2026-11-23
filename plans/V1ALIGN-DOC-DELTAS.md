# v1align — exact documentation deltas

Authority: V1ALIGN-PLAN.md. Apply in package 3 only, with the implementation; these are target documents, not statements that the current unamended candidate already implements the target.

For each BEGIN_FILE/END_FILE block below, replace/create that exact repository-relative file with the enclosed UTF-8 text, including its final newline; the marker lines are not file content. Delete docs/BOUNTY-ABI.md and docs/BOUNTY-OPERATIONS.md. Do not retain their sections as optional features or an operational appendix. Apply the one exact literal replacement for the historical intel file at the end. No other old document contents survive the five whole-file replacements. Historical source/proposal remains in Git at e18bee54c08832dd7fd6d0a11932290155bf9178; do not rewrite history.

BEGIN_FILE README.md
# Curve Gauge Lister

Fee-gated registration of Curve gauges, with four-epoch vote-incentive escrow and all-unspent-escrow confiscation to the pinned crvUSD FeeDistributor when the gauge's own `is_killed()` flag is true. The DAO handles gauge review and kills through its existing authorized processes. There are no reporter rewards or reporting stakes.

## Product

- Anyone, including the owner, may use `listGauge` to pay exactly 10,000 crvUSD. Registry authentication and structural checks run first. The immutable, explicitly supplied GaugeValidator at `0x888888c34a46d0b2A34e9204e5273208E670e784` must then return canonical true from `validateGauge(gauge)`, before adapter readiness, listing/escrow effects, fee transfer or controller addition. False, failed and malformed reads reject the listing.
- A successful paid listing is added atomically at raw weight zero. Registration grants no emissions; veCRV voting still determines emissions.
- Four tranches of 2,500 crvUSD mature at the four following Thursday-aligned weekly boundaries. Anyone may checkpoint them. Each listing keeps its original venue addresses and split. Late settlement funds execution-time Votium rounds or VoteMarket ingress, not historical votes; a successful L1 VoteMarket receipt is not proof of destination delivery.
- If an Active listing's gauge flag is true, `confiscate` or `checkpoint` sends its entire unreleased balance to `0xD16d5eC345Dd86Fb63C6a9C43c517210F1027914`. Mandatory exact-transfer and same-transaction FeeDistributor accounting must succeed or everything reverts with escrow retained. Controller weight is never a kill signal.
- The owner-only `listGaugeNoEscrow` path retains registry/structural/controller checks but does not query the trusted validator or require paid-adapter readiness. It creates no fee or escrow and works while paused.
- The core starts paused on chain 1. Deployment must complete owner-authenticated one-time adapter bindings, DAO ownership and actual upstream controller authorization before enabling paid listings. Pause blocks only new paid admission. No owner withdrawal, payer refund, arbitrary execution, recipient replacement or escrow migration exists.

The validator pointer is immutable, but its owner or appointed managers can change upstream factory/module policies. Admission is not an audit of a pool's safety. Later checker failure or revocation does not block existing escrow settlement. Gauge kill authority belongs to the actual gauge implementation and its administrators; paying a listing fee neither grants nor transfers it.

## Status and evidence

Not deployed. The no-bounty release requires the gates in `plans/V1ALIGN-PLAN.md`; an authority ruling is not implementation acceptance or mainnet authorization. Exact test identities and derived expectations are in `plans/V1ALIGN-WITNESS-INVENTORY.json`. Consult candidate-bound execution receipts for actual passing counts, not historical totals.

The earlier V2/reporting implementation and proposal are preserved at Git commit `e18bee54c08832dd7fd6d0a11932290155bf9178`. Historical reviews describe their original candidates and are not a fresh audit of this release. The source comparison and baseline evidence are in `review/v1align/`. Current operational limits include FeeDistributor checkpoint contention, immutable venue availability and irrecoverable VoteMarket campaign residuals; see `docs/OPERATIONS.md`.

## Layout

- `contracts/CurveGaugeLister.sol` — paid trusted admission, DAO-free admission, four-epoch escrow and all-FeeDistributor confiscation.
- `contracts/adapters/` — Votium and VoteMarket funded ingress.
- `contracts/interfaces/`, `contracts/libraries/SafeToken.sol` — narrow dependency interfaces and safe token operations.
- `contracts/mocks/`, `test/` — test fixtures and offline tests, including retained adapter-hardening regressions.
- `fork/` — concrete pinned mainnet-fork runners; abstract scenarios remain under `test/fork/`.
- `docs/CURVE-PROPOSAL.md`, `docs/ABI.md`, `docs/OPERATIONS.md`, `docs/DEPLOYMENT-PINS.md` — current product and deployment reference.
- `plans/`, `review/` — authority, exact manifests and candidate-bound evidence.

## Running checks

```sh
forge fmt --check
forge build --offline --sizes
forge test --offline
FOUNDRY_PROFILE=fork forge build --offline --sizes
MAINNET_RPC_URL=https://eth-mainnet.public.blastapi.io scripts/test-fork.sh
```

The acceptance plan additionally requires exact ABI/inventory/layout comparisons, an RPC-unreachable offline control, cold/warm fork runs, fail-closed fork preflight, named falsifiers and independent runtime-byte ceiling checks. Use a fresh build output for artifact-reading tests. The fork endpoint can change; the pinned block cannot silently change.

Build policy: Solidity 0.8.30, optimizer 200 runs, no external Solidity dependencies; default EVM Paris, fork EVM Cancun on chain 1. Baseline evidence used Forge 1.7.1. Reverify compiler/tool versions for the release.
END_FILE README.md

BEGIN_FILE docs/CURVE-PROPOSAL.md
# Proposal: Fee-Gated Automatic Gauge Registration

## Simple Summary

Add a paid route for registry-authenticated Curve gauges to register with the GaugeController after trusted-factory validation, without a separate per-gauge approval vote. The fee is 10,000 crvUSD and funds four weekly tranches of vote incentives for that gauge. Registration starts at raw weight zero and does not award emissions; veCRV voters retain that choice.

The DAO handles monitoring, review and kills through its existing authorized processes. When a listed gauge's own `is_killed()` flag is true, all still-unreleased escrow is confiscated to the pinned crvUSD FeeDistributor for distribution under its normal rules. There is no payment to a reporter, payer or deployer. This is an additional admission route, not a retirement of existing governance or seated-wrapper routes.

## How it works

1. **Paid listing.** `CurveGaugeLister.listGauge` authenticates the pool/gauge/LP relationship and structural eligibility through the configured registry. It then calls `validateGauge(gauge)` on the constructor-pinned validator `0x888888c34a46d0b2A34e9204e5273208E670e784`. Only a successful, exact 32-byte canonical true result passes. A named factory alone is insufficient: the external validator applies its configured reciprocal factory/module proof, including supported distinct-LP legacy routes. Failure rejects before fee transfer or controller addition. The owner has no paid-lane exception.
2. **Escrow and incentives.** Exactly 10,000 crvUSD is held in the lister, with 2,500 crvUSD maturing at each of the four following Thursday weekly boundaries. Anyone may checkpoint. Each listing snapshots its Votium/VoteMarket endpoints and split; later owner configuration cannot redirect it. Every funded quarter requires exact custody movement and receipts. A late tranche uses current venue timing, not retroactive votes. VoteMarket funding is asynchronous L1-to-L2 ingress.
3. **Kill and confiscation.** Gauge kills remain external DAO/gauge-administrator actions; this lister cannot kill a gauge. Its only settlement oracle is the current gauge `is_killed()` flag, never controller weight or a report. Anyone may settle a killed Active listing. Its whole unspent remainder goes directly to crvUSD FeeDistributor `0xD16d5eC345Dd86Fb63C6a9C43c517210F1027914`, conditional on mandatory safe accounting in the same transaction. If that cannot complete, the transaction reverts and the escrow remains reserved. No early-kill refund or alternative recipient exists.
4. **DAO lane and administration.** The owner-only `listGaugeNoEscrow` lane charges no fee, creates no escrow, and does not query the trusted validator. It retains registry/structural/controller checks, so otherwise valid non-factory gauges remain eligible through DAO action. Pausing affects only new paid listings. Ownership is two-step; the intended owner is the CurveDAO Aragon org. No withdrawal, rescue, sweep, arbitrary execution or escrow-migration authority is added.

A live listing completes after four successfully funded quarters. Previously funded venue amounts are expenditure, not recoverable escrow.

## Motivation

Separate registration eligibility from emissions preference. The paid route replaces the per-gauge approval step only for candidates satisfying the defined admission checks; it does not replace veCRV voting or promise liquidity, votes, yield or a launch-to-emissions timetable.

Each successful paid listing pre-funds its initial vote-incentive budget. A later authorized kill forfeits the remaining budget to the FeeDistributor rather than returning it to the payer. Protective governance remains a DAO responsibility, without a separate reporting or reward protocol.

## Specification and rollout conditions

- The shipping contracts are the amended `CurveGaugeLister`, `VotiumAdapter` and `VoteMarketAdapter`, deployed from an exact reviewed release commit, not a moving branch name.
- Core constructor order is `(owner_, crvUSD_, controller_, feeDistributor_, admission_, platforms_, trustedGaugeValidator_)`. The validator is the seventh argument, explicitly supplied, immutable and without a setter/default. Chain 1 is mandatory; the core starts paused.
- Intended lister owner: CurveDAO Aragon org `0x40907540d8a6C65c637785e8f8B742ae6b0b9968`. Fee token: crvUSD `0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E`. Confiscation destination and validator are the pins above. Constructor code checks do not authenticate a supplied address; deployment must verify all pins and mutable upstream policy.
- Fixed economics: fee 10,000 crvUSD, four tranches of 2,500 crvUSD, paid initial controller weight zero, and 100% of unreleased escrow to the FeeDistributor on observed flag-true confiscation.
- Complete owner-authenticated, write-once adapter binding and actual upstream permission for the lister's `add_gauge` call before opening admission. The fork suite's impersonated controller-admin transfer is not a production GaugeAdder integration or an authorization receipt.
- Reverify current validator policy, registry associations, venue token acceptance/timing, destination VoteMarket requirements, bridge delivery and ETH float. Prove FeeDistributor public-checkpoint availability and safe accounting. Existing routes remain available on their existing terms.

## Limits and disclosures

- The immutable validator address has mutable upstream owner/manager-controlled policies. It authenticates the configured proof, not pool safety, economic quality or an independent deployment trace. Revocation/fault stops new paid admission, not settlement of already-admitted escrow.
- Kill authority is gauge-specific. Admission does not grant it to the payer or lister and does not verify every gauge's governance route. The DAO must verify and use the real authorized route. A kill cleared before the lister observes it leaves no historical kill proof here.
- FeeDistributor settlement requires a fresh bounded-allocation cursor and successful atomic accounting. Its public checkpoint cooldown is strict and shared; third parties can repeatedly delay settlement. Funds remain in escrow on failure, with no guaranteed completion time or recipient substitution. A standalone checkpoint is not a repair for already omitted stale allocations.
- Either venue's failure rolls back the whole checkpoint. An immutable broken venue can strand ordinary releases indefinitely; new defaults do not repair old snapshots. A legitimate gauge kill can use the separate venue-free confiscation path, still subject to FeeDistributor accounting.
- VoteMarket L1 ingress does not establish destination campaign delivery. Unused destination rewards have no ordinary project-controlled recovery API and may equal the whole campaign funding. They do not return to listing escrow or necessarily reach Curve's FeeDistributor. See the operations reference.

## Review boundary and references

Not deployed. The v1align authority review defines the no-bounty source amendment and the release gates; implementation acceptance must bind the actual release commit and fresh test/ABI/size receipts. Earlier reviews and test totals apply to their original candidates only. The previous product/proposal is preserved at `e18bee54c08832dd7fd6d0a11932290155bf9178` for the public audit trail.

- Repository: https://github.com/CWinthorpe/curve-gauge-lister
- Authority and gates: `../plans/V1ALIGN-PLAN.md`
- Exact ABI manifest: `../plans/V1ALIGN-MANIFEST.json`
- Interface reference: `ABI.md`
- Operations and limits: `OPERATIONS.md`
- Deployment pins and re-verification: `DEPLOYMENT-PINS.md`
END_FILE docs/CURVE-PROPOSAL.md

BEGIN_FILE docs/ABI.md
# CurveGaugeLister — no-bounty interface

This reference describes the v1align target. The complete normative ABI is `../plans/V1ALIGN-MANIFEST.json`; acceptance requires fresh compiler ABI and method identifiers to match it under both profiles. A disagreement blocks release; neither prose nor a matching function count silently overrides the contract or manifest.

## Constructor and tuples

Nonpayable constructor, in exact order:

`(address owner_,address crvUSD_,address controller_,address feeDistributor_,AdmissionConfig admission_,PlatformConfig platforms_,address trustedGaugeValidator_)`

- `AdmissionConfig`: `(address registry,uint8 maxCoins)`.
- `PlatformConfig`: `(address votium,address voteMarket,uint16 votiumBps)`.
- `Listing`: `(address pool,address lpToken,address payer,address admissionRegistry,int128 gaugeType,uint256 listingEpoch,uint8 status,uint8 epochsReleased,uint256 deposited,uint256 remaining,uint256 released,uint256 confiscated,address votium,address voteMarket,uint16 votiumBps)`.

`status`: Unlisted=0, Active=1, Exhausted=2, Confiscated=3, DaoExempt=4. Unknown `getListing` returns the all-zero tuple. A DAO-exempt record has zero monetary fields and platform snapshots. `confiscated` is the entire amount sent to the fixed FeeDistributor, not a gross split allocation. The gauge is the mapping key; no separate listing-ID API exists.

Chain 1 is checked first. The owner must be nonzero; the token/controller/FD/validator must have code; crvUSD decimals are 18; FD token and not-killed checks plus admission/platform validation apply. The core starts paused. Validator and positive-share adapters need not accept a candidate or be bound during construction; paid readiness is enforced at admission. The seventh argument is the validator, with no reserved extra argument.

## Complete callable core surface (30)

Nonpayable mutators:

- `listGauge(address pool,address gauge,uint256 gaugeIndex,uint256 handlerId)` -> `()`
- `listGaugeNoEscrow(address pool,address gauge,uint256 gaugeIndex,uint256 handlerId,uint256 initialWeight)` -> `()`
- `checkpoint(address gauge)` -> `(uint256 releasedNow,uint256 confiscatedNow)`
- `confiscate(address gauge)` -> `(uint256 amount)`
- `checkpointFees()` -> `(bool checkpointed)`
- `setPaused(bool paused_)` -> `()`
- `setAdmissionConfig((address registry,uint8 maxCoins) config)` -> `()`
- `setPlatformConfig((address votium,address voteMarket,uint16 votiumBps) config)` -> `()`
- `transferOwnership(address newOwner)` -> `()`
- `acceptOwnership()` -> `()`

Views:

- `BPS()`, `EPOCHS()`, `FEE()`, `INITIAL_WEIGHT()`, `QUARTER()`, `WEEK()` -> `uint256` each.
- `controller()`, `crvUSD()`, `feeDistributor()`, `owner()`, `pendingOwner()`, `trustedGaugeValidator()` -> `address` each.
- `paused()` -> `bool`.
- `totalEscrow()` -> `uint256`.
- `getAdmissionConfig()` -> `AdmissionConfig`.
- `getPlatformConfig()` -> `PlatformConfig`.
- `getListing(address gauge)` -> `Listing`.
- `epochsElapsed(address gauge)` -> `uint256`.
- `releasable(address gauge)` -> `uint256`.

Pure:

- `epochStart(uint256 timestamp)` -> `uint256`.

There is no payable core entrypoint, receive or fallback. Owner setters and two-step transfer cannot move funds, replace immutable destinations, alter existing listing snapshots or execute arbitrary calls.

## Events (10)

- `GaugeListed(address indexed gauge,address indexed pool,address indexed payer,int128 gaugeType,uint256 listingEpoch,uint256 fee,bool daoExempt)`
- `PlatformDeposit(address indexed gauge,address indexed platform,uint256 indexed scheduledEpoch,uint256 executionEpoch,uint256 amount,bytes32 receipt)`
- `QuarterReleased(address indexed gauge,uint256 indexed scheduledEpoch,uint256 amount,uint256 remaining)`
- `EscrowConfiscated(address indexed gauge,address indexed feeDistributor,uint256 amount,uint256 receiptWeek)`
- `FeeCheckpointResult(bool success)`
- `PauseSet(bool paused)`
- `AdmissionConfigSet(address registry,uint8 maxCoins)`
- `PlatformConfigSet(address votium,address voteMarket,uint16 votiumBps)`
- `OwnershipTransferStarted(address indexed owner,address indexed pendingOwner)`
- `OwnershipTransferred(address indexed previousOwner,address indexed newOwner)`

Successful confiscation emits `EscrowConfiscated` then `FeeCheckpointResult(true)` after exact custody and mandatory accounting succeed. Its receipt week is the transfer's week floor, not a promise that all fees enter one upstream week bucket. A standalone `checkpointFees` result reports only whether that upstream call returned.

## Errors (33, including shared token errors)

No-argument errors:

`BadAdmissionConfig()`, `BadCoin()`, `BadCoinCount()`, `BadGaugeType()`, `BadLpToken()`, `BadPlatformConfig()`, `ConfiscationDeltaMismatch()`, `DistributorUnusable()`, `FeeDeltaMismatch()`, `GaugeKilledAtAdmission()`, `GaugeMismatch()`, `IndexOutOfRange()`, `ListingsPaused()`, `MembershipFailed()`, `NotOwner()`, `NotPendingOwner()`, `PoolNotRegistered()`, `Reentrancy()`, `WrongChain()`, `ZeroOwner()`, `ZeroTarget()`.

Address-bearing product errors:

`AlreadyListed(address gauge)`, `ControllerRegistryOccupied(address gauge)`, `NoCode(address target)`, `PlatformDeltaMismatch(address platform)`, `PlatformNotReady(address platform)`, `PlatformReceiptMissing(address platform)`, `TrustedGaugeCheckFailed(address gauge)`, `UnknownGauge(address gauge)`, `UntrustedGauge(address gauge)`.

Shared errors:

`SafeTokenBadReturn(address token)`, `SafeTokenCallFailed(address token)`, `SafeTokenNoCode(address token)`.

The new getter selector is `trustedGaugeValidator() = 0x3ca09961`. The only validator predicate used is `validateGauge(address) = 0xe92cd3d3`, with the candidate gauge as its argument. A successful exact-32-byte zero returns `UntrustedGauge(address) = 0x6c706dca`; call failure, nonexact length or a word greater than one returns `TrustedGaugeCheckFailed(address) = 0x7835e9b7`. Only word one passes. The external validator's internal faults may collapse to false and therefore yield UntrustedGauge. Out-of-gas and other dependency ABI failures need not have a uniform custom error.

## Adapter interfaces and invariant boundary

The full unchanged VotiumAdapter and VoteMarketAdapter ABIs/method identifiers are included in the manifest. Their constructors remain `(address crvUSD_,address owner_,address votium_)` and `(address crvUSD_,address owner_,address campaignRemoteManager_,address votemarket_)`, respectively.

Both implement `rewardToken()`, `lister()` and `deposit(address gauge,uint256 scheduledEpoch,uint256 amount) returns (bytes32 receipt)`. `setLister(address)` is owner-authenticated and write-once. They accept deposits only from that bound core, use exact bounded token approvals and clear allowances. VoteMarket also accepts native ETH through `receive()` as committed message float; neither adapter exposes withdrawal, rescue or arbitrary execution. Its `getDeposit`, `depositCount` and `depositAt` expose recorded ingress, not proof of asynchronous delivery. See `OPERATIONS.md` for mutable venue settings, gas arithmetic and residual-loss limits.
END_FILE docs/ABI.md

BEGIN_FILE docs/OPERATIONS.md
# CurveGaugeLister operations — no-bounty runbook

Prospective deployment only. No production authorization, successful rollout or current pin verification is implied by this document. The shipping system is CurveGaugeLister with the two venue adapters. The DAO handles gauge review and kills through existing authorized governance/emergency paths; the lister provides no reporting, staking, reward, ballot or kill-command service.

## Roles and deployment

Assign a deployment operator, lister config-owner responder, adapter manager, settlement keeper, governance liaison and FeeDistributor-admin liaison before accepting fees. These are staffing requirements, not newly implemented monitoring tools.

1. Bind the exact release commit, compiler/settings, full ABI/layout checks, source/runtime hashes, test inventory and both-profile size receipts. Complete `../plans/V1ALIGN-PLAN.md` gates.
2. Reverify chain 1 and the dependencies in `DEPLOYMENT-PINS.md` at one recorded current block, then check mutable state again immediately before enabling admission. Code presence is not authenticity or readiness. Check the validator's owner/managers, relevant factory/module policies and actual candidate predicates. It is an external mutable policy dependency, not a pool-safety audit.
3. The intended lister owner is CurveDAO Aragon org `0x40907540d8a6C65c637785e8f8B742ae6b0b9968`. Establish approved upstream authorization for the exact lister-to-controller `add_gauge` path. The fork-only controller admin transfer is not a deployment recipe or GaugeAdder seating proof.
4. Use an actually authorized atomic deployment/binding batch: deploy fresh correctly pinned adapters; deploy CurveGaugeLister with its seven arguments and paused start; have each adapter's real owner call its one-time `setLister(core)`; read back bindings, token/ingress pins and the core's future platform config. A deployment factory is not automatically an owner. If temporary ownership is used, finish and verify the existing two-step handoff before admission opens. There is no rebinding or recovery for a mistaken adapter binding.
5. Verify every positive-share endpoint, real funded venue ingress, current token acceptance/round settings, VoteMarket destination-chain requirements and delivery, and the FeeDistributor policy below. Fund VoteMarket's committed ETH float. Only the owner may unpause after these checks; verify the resulting state. Readiness still rejects unbound/misbound adapters if someone unpauses prematurely.

Construction/setPlatformConfig deliberately allow staging unbound future adapters. Every paid listing checks readiness on its exact snapshotted positive-share configuration before escrow effects. Zero-share destinations are never called. The DAO-free lane does not require validator or adapter readiness and continues while paused; registry/structural/controller checks still apply.

## Admission and ordinary settlement

The payer approves at least the exact 10,000-crvUSD fee; a larger allowance is legal, but only that fee is pulled. Registry authentication precedes the strict trusted-validator read; all rejection paths roll back the complete listing transaction. Admission creates membership at raw weight zero, not an emissions allocation. Checker revocation/fault stops new paid listing, including owner-paid listing, but does not revalidate an existing escrow.

Checkpoint each matured tranche using the stored listing epoch, venues and split. Four quarters of 2,500 crvUSD mature at weekly Thursday boundaries; delayed settlement catches up in order. Votium uses its execution-time active round, which can serve more than one weekly tranche. VoteMarket submits a gauge-bound L1 campaign message toward Arbitrum; verify destination creation separately. No quarter may be skipped as paid, and configuration changes cannot repair or redirect already frozen listing endpoints.

Poll venue compatibility and ETH float at least hourly while releases are pending and simulate immediately before settlement. The Votium manager can shorten/clear an exclusion list if upstream maxExclusions changes, preserving sorted/nonzero constraints; check token and round availability too. For VoteMarket, check one-message `ethDeficit` and the backlog's aggregate needs, configured pricing, remote whitelist, periods and actual bridge state. Refill and retry the same maturity rather than suppressing a failed leg.

Either venue's failure rolls back both shares, approvals, receipts and all provisional quarter progress. A permanently unusable immutable ingress can block old releases indefinitely. Pause NEW paid listings on persistent incompatibility; replacements/defaults are prospective only. Publish unresolved old obligations and keep monitoring them. There is no healthy-leg-only payout, payer refund, arbitrary recovery, old-escrow migration or administrative kill-for-repair policy. Legitimately killed gauges can use venue-free confiscation, subject to FD accounting.

## Kills and all-FeeDistributor confiscation

Verify the actual gauge implementation, factory/admin and governance/emergency authorization before using a kill route. Paid admission transfers no authority to the payer or lister. An authorized gauge admin other than the payer can kill and cause forfeiture. The lister does not authenticate who set the flag: it reads only current `is_killed()`.

Execute a protective kill through its legitimate route independently of settlement. Never make an urgent kill contingent on confiscation succeeding: a combined atomic transaction rolls back the kill if settlement fails. Leave the flag true and let anyone call `confiscate(gauge)` or `checkpoint(gauge)` when safe accounting is available.

For an Active killed listing, the entire unreleased remainder goes to pinned FeeDistributor `0xD16d5eC345Dd86Fb63C6a9C43c517210F1027914`. No caller, reporter, payer or owner receives a share. Prior venue expenditure is not recaptured. Initial zero controller weight, later weight changes and a caller's assertion are never kill evidence. Gauge-read failures revert. A flag cleared before observation cannot be inferred retrospectively; a successful confiscation remains terminal after a later unkill. Exhausted and DAO-exempt records have no confiscatable remainder.

## Mandatory FD safe-accounting and contention

Settlement keeper and FD-admin liaison must rebind operational checks to the selected FD's actual source/runtime. Record token, killed status, admin, public-checkpoint flag, `last_token_time`, `token_last_balance`, actual token balance and affected week buckets.

Before a seizure:

- FD code must remain present, `token()==crvUSD`, and `is_killed()==false`.
- Cursor t must be nonzero, not in the future and satisfy `now <= floor(t/604800)*604800 + 20*604800`. Equality at the horizon is valid; one second beyond is not. The first partial week consumes one bounded-loop iteration, so `t+20 weeks` is NOT the correct horizon.
- For this ordinary non-admin lister, public checkpointing must be enabled and the public cooldown is STRICT: `now > t + 86400`. Freshness and cooldown are separate requirements; neither implies the other. An outer FD-admin caller does not make the inner lister an admin.

Confiscation performs the exact direct transfer, checks both sender debit and destination credit, calls checkpoint_token without catching failure, then requires cursor==now and accounted balance==actual custody. It emits custody/accounting-success events only after success. No FD approval or burn(address) call is used. A failure rolls back the entire checkpoint, including any earlier quarter; best-effort monetary accounting is forbidden. Normal upstream integer-rounding dust is distinct from an unsafe omitted allocation tail.

Poll at least hourly while confiscations are pending and at least daily otherwise, and immediately before sending. Prefer an eligible pending confiscation over no-transfer housekeeping that consumes the same window. A successful third-party public checkpoint can win the shared window and repeatedly postpone settlement; private routing does not guarantee priority or completion time. Recompute from the new cursor and retry. Removing our checkpointFees wrapper would not remove upstream contention.

For a stale FD, keep new confiscation money in escrow. A separate refresh is demonstrably lossless only after confirming `balanceOf(fd)==token_last_balance()` (zero unaccounted delta). Verify that the refresh advanced the cursor without consuming new money, wait STRICTLY beyond its cooldown, and attempt confiscation directly without another pre-checkpoint. A positive stale unaccounted delta requires upstream attention: this protocol cannot promise that checkpointing it is lossless or repair an omitted tail afterward. Disabled public checkpointing requires legitimate upstream restoration, not a local recipient change.

`checkpointFees()` transfers no escrow and catches only its own upstream checkpoint failure. A true return means the call returned, not that arbitrary stale pre-existing fees were completely allocated. No alternate FD, refund, sweep or old-liability migration exists.

## Adapter arithmetic and one-way float

New adapter construction checks nonzero arguments first, then code at crvUSD and the local Votium/CRM ingress. The manager may be an EOA. The remote VoteMarket address is nonzero but deliberately not checked for L1 code; verify it on chain 42161. These guards do not prove endpoint identity or availability.

For VoteMarket base B>0, per-exclusion X and price P>0, with U=type(uint256).max, `setGasSettings` requires `X <= (U-B)/50` and then `P <= U/(B+50*X)`. Equality and X=0 are permitted; all future list lengths 0..50 are protected. Rejection is BadGasSettings before storage/event changes, not arithmetic Panic. Defaults are base2,000,000, per-exclusion50,000 and price1gwei. This is arithmetic safety, not a live quote or affordability cap.

`ethDeficit(amount>0)` quotes ONE message's configured funding shortfall, independent of token amount; `ethDeficit(0)==0`. A catch-up may require several messages. Returned unused bridge ETH stays in reusable committed float, so call value need not equal net expenditure. There is no operator withdrawal/rescue of the float.

## VoteMarket residuals and delivery limits

Successful funded ingress is final expenditure from listing escrow. The adapter appoints itself campaign manager; its L1 owner is not that destination manager. Ownership transfer does not change existing campaign managers or make the numerical adapter address on Arbitrum a controlled recovery receiver. There is no campaign-close, manager-update, receiver-selection, arbitrary-execution, token-recovery or bridge-return API here.

Unused/unclaimed destination rewards have no ordinary project-controlled recovery route. Permanent forfeiture is an accepted product limitation; residuals can equal the whole campaign funding, not merely dust. They never restore listing.remaining or a local DAO credit. In the historically verified venue reference, a 24-week post-campaign claim period is followed by a four-week manager close window. At/after that boundary, permissionless closure subject to required prior-state updates sends residuals to the VoteMarket platform fee collector. This is not an automatic timed transfer, a project refund or a deposit to Curve's pinned crvUSD FeeDistributor; reverify the deployed destination policy before operation.

An L1 receipt proves funded ingress/message submission, not asynchronous delivery or a live destination campaign. Monitor the destination independently. Tokens donated or somehow returned to an L1 adapter are preserved by its deposit balance check while each next deposit pulls its full new amount; they are not automatically reused or withdrawable. Donations to the core create no listing credit and no rescue right.

## Review and change boundary

Historical audits and accepted-risk labels belong to their original candidates. Their relevant mechanisms remain disclosed here without importing a removed reporting protocol. The no-bounty source amendment needs fresh candidate-bound implementation gates. If an immutable endpoint becomes incompatible, restoration or a separately reviewed FUTURE deployment does not migrate existing escrow. Current authorization, upstream governance and bridge readiness are continuing operational duties, not guarantees made by a past fork run.
END_FILE docs/OPERATIONS.md

BEGIN_FILE docs/DEPLOYMENT-PINS.md
# Deployment pins — no-bounty CurveGaugeLister

Prospective Ethereum-mainnet configuration. These are intended pins and historical verification anchors, not a claim of current deployment readiness. Reverify all addresses, code/source identities, roles and mutable policies at a newly recorded fixed block and again before opening paid admission. Keep the test fork pin separate and unchanged.

## Intended constructor dependencies

| Role | Address / value |
| --- | --- |
| Lister owner / CurveDAO Aragon org | `0x40907540d8a6C65c637785e8f8B742ae6b0b9968` |
| crvUSD | `0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E` |
| GaugeController reference | `0x2F50D538606Fa9EDD2B11E2446BEb18C9D5846bB` |
| crvUSD FeeDistributor | `0xD16d5eC345Dd86Fb63C6a9C43c517210F1027914` |
| MetaRegistry | `0xF98B45FA17DE75FB1aD0e7aFD971b0ca00e379fC` |
| Admission structural maxCoins | `8` |
| trustedGaugeValidator_ | `0x888888c34a46d0b2A34e9204e5273208E670e784` |
| Votium v2 local deposit ingress | `0x63942E31E98f1833A234077f47880A66136a2D1e` |
| VoteMarket local CampaignRemoteManager | `0x53ad4cd1f1e52dd02aa9fc4a8250a1b74f351ca2` |
| VoteMarket remote destination, chain42161 | `0x8c2c5a295450ddff4cb360ca73fccc12243d14d9` |

The controller row identifies the real controller used in the fork, not proof of production calling authority. The core's immutable controller target must expose the required add/type/count interface and have an explicitly approved authorization path. Do not silently replace a pin or use the fork-only impersonated admin transfer as a deployment instruction. GaugeAdder seating/integration remains a separate rollout gate.

The lister owner controls pause, prospective configurations and two-step ownership, not discretionary token withdrawal. It is an Aragon governance executor, not described here as a deployer multisig. Actual gauge kill roles are separate, implementation-specific upstream authorities; they are not new constructor dependencies or lister privileges.

## Constructor and binding order

- `CurveGaugeLister(owner_,crvUSD_,controller_,feeDistributor_,admission_,platforms_,trustedGaugeValidator_)`: six original parameters plus the validator as SEVENTH. Admission is `(registry,maxCoins)`; platforms are `(freshVotiumAdapter,freshVoteMarketAdapter,approvedVotiumBps)`. The split is an explicit DAO-approved deployment choice, not implied by the test fixture's example. Supply the validator pin exactly; no default or setter exists. Chain1 is checked first; owner/code/token/FD/config validation follows; the core starts paused.
- `VotiumAdapter(crvUSD_,owner_,votium_)`: the token and local ingress need code. The manager is explicitly assigned, never an unexamined deployer default.
- `VoteMarketAdapter(crvUSD_,owner_,campaignRemoteManager_,votemarket_)`: local token/CRM need code; verify the nonzero remote on Arbitrum, not by an L1 code lookup.
- Use an authorized atomic deploy-and-bind batch. Each adapter's actual owner calls `setLister` once after the core exists. Read back both bindings and all pins/config; complete any two-step ownership handoff. Keep admission paused until controller, venue, FD and operational gates are complete. A misbound adapter must be replaced before accepting fees, not rebound later.

## Fixed regression-fork anchor

Chain1; block `26401019`; hash `0x55810b079923a14fb97ad548f5024f65530dbc4fb2357a38f41e13b3d27cb6d3`; timestamp `1794512471`.

`scripts/test-fork.sh` verifies the exact header over RPC before invoking Forge. Its endpoint override is MAINNET_RPC_URL, not a block override. The historical PublicNode endpoint can lack old-state access; an archive error is a failure, not empty code or a negative predicate. Blast's public mainnet endpoint was used for archived state in the preceding evidence. Recheck availability; do not silently repin or replace live contracts with fixture code.

Fork code/hash/role assertions and holder/DAO impersonations are in `../test/fork/ForkFixture.sol` and `../test/fork/ForkTrustedFactory.t.sol`. These are simulations, not broadcast receipts, production seating or destination-delivery certificates.

## Trusted validator lineage and mutable policy

The prior source-verification record, preserved at `e18bee54c08832dd7fd6d0a11932290155bf9178`, binds these historical facts:

| Item | Historical observation |
| --- | --- |
| Validator predicate | `validateGauge(address)`, selector `0xe92cd3d3`; argument is the GAUGE |
| Validator runtime | 3,402 bytes; Keccak256 `0x2d684822a3f2bf6f99f902474289219041443a9d9cc94cbc28505050185016cd` |
| Validator owner | `0x40907540d8a6C65c637785e8f8B742ae6b0b9968` |
| One checked enabled manager | `0xc0DE00005F21Fa7846BA0EA2E3F2FC4F048a72C9` |
| Gauge-validation module | `0x999902533033Cc63c8128C501e307477932B742E` |
| Module runtime | 1,336 bytes; Keccak256 `0xfc5562e86bbf44b97a41e6e1e1f578a396c0fd4a5aaac85805ef62630fca36ff` |
| SS-ng regular gauge factory | `0x6A8cbed756804B16E05E741eDaBd5cB544AE21bf`, module above, method1 |
| Legacy crypto factory | `0xF18056Bbd320E96A48e3Fbf8bC061322531aac99`, same module, method2 |
| SS-ng fork candidate gauge | `0x9f96B45A2ea3Fea791513aa3A7921d474105B23e` |
| Legacy candidate gauge | `0xfB389aCa09ddC676fC9D5aC3cfD2Cd133bf44E19` |
| Distinct legacy LP / minter pool | `0x1AEa495539B514A5538878D3D3695c7AEDdC61F1` / `0x03470B57B05089EE40c651dAC9E0387F1f3cb46f` |

The prior record reports full runtime reproduction from `wavey0x/curve-gauge-validator` commit `c1246600ef8aeea452ab0c849bf9135647ee8c4f`, Solidity `0.8.28+commit.7893614a`, optimizer200, Cancun, remapping `forge-std/=lib/forge-std/src/`. Source: https://github.com/wavey0x/curve-gauge-validator/blob/c1246600ef8aeea452ab0c849bf9135647ee8c4f/src/GaugeValidator.sol and adjacent GaugeValidationModuleV1.sol. This is a dependency-source anchor, not this repository's compiler policy. Do not infer Curve-organization authorship or an AutoWrapper precedent from the address; the earlier `curvefi/automation` attribution was not corroborated.

The pointer is immutable in the lister, but upstream owner/managers may change policies. The one manager above is not an exhaustive role inventory. Review ManagerSet/FactoryPolicySet history and current relevant manager keys. Verify each intended factory's module/method and actual reciprocal gauge predicate; a factory name or nonzero mapping alone does not pass. For the distinct-LP legacy route, a successful zero direct lookup permits the minter route; a failed direct read does not.

Never substitute `validateProposalGauges(uint256)` (`0x2da285c4`), a proposal module, a pool, LP, factory or transaction deployer for the per-gauge predicate. The core's code check alone proves none of this. DAO-free listing does not query the checker; policy changes do not add a settlement gate to existing escrow.

## Re-verification procedure

Select one endpoint and explicit block. Record chain ID, block number/hash/timestamp before reading code and state; use that same block for every observation. The following read-only example preserves the regression anchor; deployment must use its separately selected current block.

```sh
RPC=https://eth-mainnet.public.blastapi.io
BLOCK=26401019
cast chain-id --rpc-url "$RPC"
cast block "$BLOCK" --json --rpc-url "$RPC"
cast code 0x888888c34a46d0b2A34e9204e5273208E670e784 --block "$BLOCK" --rpc-url "$RPC"
cast call 0x888888c34a46d0b2A34e9204e5273208E670e784 'owner()(address)' --block "$BLOCK" --rpc-url "$RPC"
cast call 0x888888c34a46d0b2A34e9204e5273208E670e784 'policyForFactory(address)(address,uint8)' 0x6A8cbed756804B16E05E741eDaBd5cB544AE21bf --block "$BLOCK" --rpc-url "$RPC"
cast call 0x888888c34a46d0b2A34e9204e5273208E670e784 'validateGauge(address)(bool)' 0x9f96B45A2ea3Fea791513aa3A7921d474105B23e --block "$BLOCK" --rpc-url "$RPC"
cast call 0x888888c34a46d0b2A34e9204e5273208E670e784 'validateGauge(address)(bool)' 0xfB389aCa09ddC676fC9D5aC3cfD2Cd133bf44E19 --block "$BLOCK" --rpc-url "$RPC"
cast call 0xD16d5eC345Dd86Fb63C6a9C43c517210F1027914 'token()(address)' --block "$BLOCK" --rpc-url "$RPC"
cast call 0xD16d5eC345Dd86Fb63C6a9C43c517210F1027914 'is_killed()(bool)' --block "$BLOCK" --rpc-url "$RPC"
```

Additionally record/hash full runtime bytes and verified sources for each dependency and any proxy implementation; confirm crvUSD decimals18, controller/registry ABI and authority, validator owner/managers/policy/module, actual gauge/LP/pool/coins and real kill authorization. Full runtime hashes, not size or proxy shape alone, establish code identity. Validate literal addresses before lookup, never silently correct a malformed pin.

For the FD, record admin, can_checkpoint_token, last_token_time, token_last_balance, actual crvUSD balance and bounded-loop/cooldown source. Require public checkpoint availability for the ordinary lister, nonzero/nonfuture cursor, `now<=floor(t/604800)*604800+20*604800` and strict public eligibility `now>t+86400`. Shared-cursor contention can indefinitely delay settlement. Stale zero-delta refresh and direct retry are governed by `OPERATIONS.md`; positive stale unaccounted money is not safely repaired by a claimed best-effort refresh.

## Deployment gates still open

Current pin/source/role and validator-policy verification; approved actual controller integration/seating; Votium crvUSD acceptance and execution-round behavior; remote VoteMarket whitelist/MINIMUM_PERIODS and destination delivery; funded real venue probes; authorized deployment/binding/ownership receipts; committed ETH float; assigned operational roles; safe FD window and a funded trial listing. No authority or fork receipt silently closes these gates. Emergency kills should proceed through their real authority independently of settlement; a failing combined kill-and-confiscate batch would also roll back the kill.
END_FILE docs/DEPLOYMENT-PINS.md

## Exact literal replacement in docs/INTEL-YB-HELPERS.md

Replace only this original opening paragraph:

BEGIN_OLD_INTEL
Source of truth for real bribe-platform ingestion. Verified 2026-11-12:
Sourcify exact_match (chainId 1) for all three; live storage reads via
https://ethereum-rpc.publicnode.com.
END_OLD_INTEL

With:

BEGIN_NEW_INTEL
Historical venue-integration research, not the current deployment or product specification. The observations below were recorded on 2026-11-12 using Sourcify and https://ethereum-rpc.publicnode.com; they are not fresh v1align verification. Current authority is OPERATIONS.md, ABI.md and DEPLOYMENT-PINS.md, together with the candidate's compiled source. In particular, the current Votium receipt is keccak256(abi.encode(gauge, scheduledEpoch, amount, round)); both adapters use exact bounded approvals and clear them, with no standing-approval exception. The old implications below are retained as research history, not permission to change those rules.
END_NEW_INTEL
