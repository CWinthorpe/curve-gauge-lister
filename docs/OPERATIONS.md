# CurveGaugeLister operations — no-bounty runbook

Prospective deployment only. No production authorization, successful rollout or current pin verification is implied by this document. The shipping system is CurveGaugeLister with the two venue adapters. The DAO handles gauge review and kills through existing authorized governance/emergency paths; the lister provides no reporting, staking, reward, ballot or kill-command service.

## Roles and deployment

Assign a deployment operator, lister config-owner responder, adapter manager, settlement keeper, governance liaison and FeeDistributor-admin liaison before accepting fees. These are staffing requirements, not newly implemented monitoring tools.

1. Bind the exact release commit, compiler/settings, full ABI/layout checks, source/runtime hashes, test inventory and both-profile size receipts. Complete the release-plan gates held by the project owner with the candidate-bound release evidence package (producible on demand).
2. Reverify chain 1 and the dependencies in `DEPLOYMENT-PINS.md` at one recorded current block, then check mutable state again immediately before enabling admission. Code presence is not authenticity or readiness. Check the validator's owner/managers, relevant factory/module policies and actual candidate predicates. It is an external mutable policy dependency, not a pool-safety audit.
3. The intended lister owner is CurveDAO Aragon org `0x40907540d8a6C65c637785e8f8B742ae6b0b9968`. Establish approved upstream authorization for the exact lister-to-controller `add_gauge` path through a separately selected and separately approved authority-preserving GaugeAdder/wrapper/executor composition. The unchanged lister MUST NOT become raw controller admin, even temporarily: under the named raw controller, retaining its existing admin prevents either admission lane's direct addition, and seating the lister as raw admin strands callable controller administration and both incumbent-admin-only ownership-transfer steps — the lister's own owner functions cannot perform those calls, DAO ownership of the lister does not solve the caller mismatch, and lister-owner transfer cannot repair it. The DAO-free lane has the same inner-caller constraint. The fork-only controller admin transfer is a disposable regression simulation, not a deployment recipe, a GaugeAdder seating proof or a production integration template.
4. Use an actually authorized atomic deployment/binding batch: deploy fresh correctly pinned adapters; deploy CurveGaugeLister with its seven arguments and paused start; have each adapter's real owner call its one-time `setLister(core)`; read back bindings, token/ingress pins and the core's future platform config. A deployment factory is not automatically an owner. If temporary ownership is used, finish and verify the existing two-step handoff before admission opens. There is no rebinding or recovery for a mistaken adapter binding.
5. Verify every positive-share endpoint, real funded venue ingress, current token acceptance/round settings, VoteMarket destination-chain requirements and delivery, and the FeeDistributor policy below. Complete the controller-composition prerequisite: the selected authority-preserving GaugeAdder/wrapper/executor graph must be simulated and approved before production enablement, and actual authorized grants, bindings and ownership readbacks verified before unpause — never a direct raw-admin seat. Fund VoteMarket's committed ETH float. Only the owner may unpause after these checks; verify the resulting state. Unpause opens the permissionless lane; it is not a restricted trial, and the first real paid broadcast remains post-authorization evidence. Readiness still rejects unbound/misbound adapters if someone unpauses prematurely. If no compatible composition is selected and approved, remain paused under activation HOLD and do not claim production DAO-free integration either.

Construction/setPlatformConfig deliberately allow staging unbound future adapters. Every paid listing checks readiness on its exact snapshotted positive-share configuration before escrow effects. Zero-share destinations are never called. The DAO-free lane does not require validator or adapter readiness and continues while paused; registry/structural/controller checks still apply.

## Venue guarantee lifetimes

One matrix for what each venue guarantee actually covers. Binding a core
listing to adapter endpoints is not a venue-funding, venue-compatibility or
destination-delivery assertion; failure modes stay disclosed in the sections
below.

| Guarantee | Set by | Frozen when | Mutable afterwards |
| --- | --- | --- | --- |
| Prospective admission/platform defaults (registry, maxCoins, future votium/voteMarket endpoints, split) | owner `setAdmissionConfig`/`setPlatformConfig` | only for the NEXT listing | always; prospective only, never redirects existing records |
| Frozen listing endpoints and split | snapshotted at paid admission | at that admission | never for that record |
| Adapter lister binding (write-once `setLister`) | each adapter's real owner | at first successful bind | never; no rebind/recovery path |
| Live venue terms at those endpoints (Votium `maxPerVote`/exclusions, VoteMarket gas settings/reward cap/exclusions) | adapter manager setters | never | always; pending records remain exposed to current settings, so poll and simulate before settlement |
| External ingress/delivery eligibility (real venue round state, CRM platform whitelist, L2 campaign creation) | the venue/bridge/destination chain | never | changes independently of this protocol; an L1 receipt proves recorded ingress only |

Frozen above means non-redirectable, not available. If any required immutable
ingress becomes permanently failed or incompatible, or the pinned FeeDistributor
becomes permanently unusable, the ENTIRE affected remaining balance stays
reserved indefinitely — including the healthy leg of a mixed listing, because
checkpoint settlement is atomic across both shares. Retention preserves
backing, not availability. No row of this matrix implies a completion bound,
refund, migration, alternate destination, partial payout or timeout exit.

## Admission and ordinary settlement

The payer approves at least the exact 10,000-crvUSD fee; a larger allowance is legal, but only that fee is pulled. Registry authentication precedes the strict trusted-validator read; all rejection paths roll back the complete listing transaction. Admission creates membership at raw weight zero, not an emissions allocation. Checker revocation/fault stops new paid listing, including owner-paid listing, but does not revalidate an existing escrow.

`listGauge` settles admission against the owner-selected prospective defaults in effect AT EXECUTION. The payer supplies no expected endpoints, split, hash, version or deadline: configured defaults may change after the payer inspects, approves or submits but before execution, and an approval, simulation or off-chain notification is not an atomic commitment to previously reviewed terms. Only the endpoints and split recorded by successful admission are frozen against later core-owner replacement; live adapter settings and upstream venue policies remain mutable for those records. Code presence and the adapters' `rewardToken`/`lister` compatibility reads establish interface consistency, not independent venue identity — reviewed deployment/configuration pins and governance remain a trust dependency. This product does not offer a payer who requires enforceable pre-submission terms that guarantee.

Checkpoint each matured tranche using the stored listing epoch, venues and split. Four quarters of 2,500 crvUSD mature at weekly Thursday boundaries; delayed settlement catches up in order. Votium uses its execution-time active round, which can serve more than one weekly tranche. VoteMarket submits a gauge-bound L1 campaign message toward Arbitrum; verify destination creation separately. No quarter may be skipped as paid, and configuration changes cannot repair or redirect already frozen listing endpoints. Settlement admission lanes (CX-ADMIT matrix): the PAID lane is anyone-callable, not-paused-required, runs the shared read-only `_admit` phase (registry/structural checks; no effects), then the pinned-trust read, then adapter-binding on the same configuration snapshot, then record/liability writes, the exact fee pull and `add_gauge` at zero weight with the immediate typed-membership postcheck; the DAO-FREE lane is owner-only, works while paused, shares the identical read-only `_admit` phase and the same add-then-postcheck membership work with the owner-supplied weight, and has no fee, escrow, trust read or adapter readiness. Both lanes keep their own entry gates: the shared code never hoists a paid check ahead of `_admit` and static validation is never treated as registry truth.

Fee, tranche and release amounts are gross escrow expenditure — `PlatformDeposit`/`QuarterReleased` amounts name what left escrow, not what arrived net at a venue. At the independently observed pinned Votium venue, net reward plus the current platform fee equals gross; no fixed future fee, universal net reward or guaranteed vote count is promised, and VoteMarket funding stays funded L1 ingress, not L2 delivery. Maturity views (see `ABI.md`) are gross projections conditioned on current status and the kill flag, not funded execution quotes; venue/FD executability limitations below stay in force.

Poll venue compatibility and ETH float at least hourly while releases are pending and simulate immediately before settlement. The Votium manager can shorten/clear an exclusion list if upstream maxExclusions changes, preserving sorted/nonzero constraints; check token and round availability too. For VoteMarket, check one-message `ethDeficit` and the backlog's aggregate needs, configured pricing, remote whitelist, periods and actual bridge state. Refill and retry the same maturity rather than suppressing a failed leg.

Either venue's failure rolls back both shares, approvals, receipts and all provisional quarter progress. A permanently failed or incompatible required immutable ingress can leave the ENTIRE affected remaining balance reserved indefinitely — including the healthy leg, because settlement is atomic across both shares. The mirror case is terminal at the FeeDistributor: while the immutable pinned FeeDistributor remains unusable, even a legitimately killed listing cannot terminalize and its whole outstanding remainder stays reserved. Retention preserves backing, not availability; polling and new prospective defaults do not repair old liabilities. Pause NEW paid listings on persistent incompatibility; replacements/defaults are prospective only. Publish unresolved old obligations and keep monitoring them. There is no healthy-leg-only payout, payer refund, alternate FD, arbitrary recovery, old-escrow migration, timeout exit, owner withdrawal or administrative kill-for-repair policy. Legitimately killed gauges can use venue-free confiscation, subject to FD accounting — a protective kill remains an independent governance action, must stay independent of settlement, and must never be performed solely to repair a venue.

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

Poll at least hourly while confiscations are pending and at least daily otherwise, and immediately before sending. Prefer an eligible pending confiscation over no-transfer housekeeping that consumes the same window. Canonical zero-delta maintenance is a direct `checkpoint_token()` call on the FeeDistributor by the ordinary public caller (its own caller/cooldown rules apply); the core's `checkpointFees()` wrapper is retained convenience whose `true` only records that the upstream call returned. A successful third-party public checkpoint can win the shared window and repeatedly postpone settlement; private routing does not guarantee priority or completion time. Recompute from the new cursor and retry. Removing our checkpointFees wrapper would not remove upstream contention.

For a stale FD, keep new confiscation money in escrow. A separate refresh is demonstrably lossless only after confirming `balanceOf(fd)==token_last_balance()` (zero unaccounted delta). Verify that the refresh advanced the cursor without consuming new money, wait STRICTLY beyond its cooldown, and attempt confiscation directly without another pre-checkpoint. A positive stale unaccounted delta requires upstream attention: this protocol cannot promise that checkpointing it is lossless or repair an omitted tail afterward. Disabled public checkpointing requires legitimate upstream restoration, not a local recipient change.

`checkpointFees()` transfers no escrow and catches only its own upstream checkpoint failure. A true return means the call returned, not that arbitrary stale pre-existing fees were completely allocated; it is not escrow-accounting evidence — successful confiscation accounting is evidenced by the core's `EscrowConfiscated` event, which commits only after exact custody and mandatory same-transaction FD accounting succeed. No alternate FD, refund, sweep or old-liability migration exists. If the pinned FeeDistributor itself becomes permanently unusable — killed, wrong token, or otherwise failing the checks above with no legitimate upstream restoration — that is the terminal case accepted for this product: every affected listing's entire outstanding remainder, including a killed listing's confiscatable balance, stays reserved in escrow indefinitely, backed but unavailable. Monitoring makes the condition visible; it does not promise restoration, and no local route replaces the pinned destination or converts retention into an exit.

## Adapter arithmetic and one-way float

New adapter construction checks nonzero arguments first, then code at crvUSD and the local Votium/CRM ingress. The manager may be an EOA. The remote VoteMarket address is nonzero but deliberately not checked for L1 code; verify it on chain 42161. These guards do not prove endpoint identity or availability.

Custody/attestation observation boundary: the core's funding check observes
the exact lister-side source debit plus a nonzero adapter attestation
(receipt) — it is not a recipient-credit check; each adapter separately
observes the exact pull credit into its own balance and the return of that
balance to its pre-deposit baseline — an adapter-side observation, not a
measured credit at the venue. Destination facts come from the pinned ingress
record plus independent venue evidence (fork observations, balance deltas),
never from either balance check alone. The confiscation path is the one place
the lister itself checks both sides of a single transfer: exact lister debit
and exact FeeDistributor credit. Common receipt meaning stays defined at
`IIncentivePlatform.deposit`; this paragraph records the observation boundary
only and adds no new receipt specification.

For VoteMarket base B>0, per-exclusion X and price P>0, with U=type(uint256).max, `setGasSettings` requires `X <= (U-B)/50` and then `P <= U/(B+50*X)`. Equality and X=0 are permitted; all future list lengths 0..50 are protected. Rejection is BadGasSettings before storage/event changes, not arithmetic Panic. Defaults are base2,000,000, per-exclusion50,000 and price1gwei. This is arithmetic safety, not a live quote or affordability cap.

`ethDeficit(amount>0)` quotes ONE message's configured funding shortfall, independent of token amount; `ethDeficit(0)==0` is a deliberate no-message query. Quote and deposit execution share ONE named priced-message calculation (`_oneMessageEthRequirement`: the current one-message bridge-gas limit times the configured gas price), so they cannot price differently under identical settings. A positive return is not funding readiness and not a quote conditioned on the core's binding — it prices one message under current settings while a catch-up may require several messages. Returned unused bridge ETH stays in reusable committed float, so call value need not equal net expenditure. There is no operator withdrawal/rescue of the float.

## VoteMarket residuals and delivery limits

Successful funded ingress is final expenditure from listing escrow. The adapter appoints itself campaign manager; its L1 owner is not that destination manager. Ownership transfer does not change existing campaign managers or make the numerical adapter address on Arbitrum a controlled recovery receiver. There is no campaign-close, manager-update, receiver-selection, arbitrary-execution, token-recovery or bridge-return API here.

Unused/unclaimed destination rewards have no ordinary project-controlled recovery route. Permanent forfeiture is an accepted product limitation; residuals can equal the whole campaign funding, not merely dust. They never restore listing.remaining or a local DAO credit. In the historically verified venue reference, a 24-week post-campaign claim period is followed by a four-week manager close window. At/after that boundary, permissionless closure subject to required prior-state updates sends residuals to the VoteMarket platform fee collector. This is not an automatic timed transfer, a project refund or a deposit to Curve's pinned crvUSD FeeDistributor; reverify the deployed destination policy before operation.

An L1 receipt proves funded ingress/message submission, not asynchronous delivery or a live destination campaign. Monitor the destination independently. Tokens donated or somehow returned to an L1 adapter are preserved by its deposit balance check while each next deposit pulls its full new amount; they are not automatically reused or withdrawable. Donations to the core create no listing credit and no rescue right.

## Review and change boundary

Historical audits and accepted-risk labels belong to their original candidates. Their relevant mechanisms remain disclosed here without importing a removed reporting protocol. The no-bounty source amendment needs fresh candidate-bound implementation gates. If an immutable endpoint becomes incompatible, restoration or a separately reviewed FUTURE deployment does not migrate existing escrow. Current authorization, upstream governance and bridge readiness are continuing operational duties, not guarantees made by a past fork run.
