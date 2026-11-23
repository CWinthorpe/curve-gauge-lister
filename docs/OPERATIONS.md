# CurveGaugeLister operations — no-bounty runbook

Prospective deployment only. No production authorization, successful rollout or current pin verification is implied by this document. The shipping system is CurveGaugeLister with the two venue adapters. The DAO handles gauge review and kills through existing authorized governance/emergency paths; the lister provides no reporting, staking, reward, ballot or kill-command service.

## Roles and deployment

Assign a deployment operator, lister config-owner responder, adapter manager, settlement keeper, governance liaison and FeeDistributor-admin liaison before accepting fees. These are staffing requirements, not newly implemented monitoring tools.

1. Bind the exact release commit, compiler/settings, full ABI/layout checks, source/runtime hashes, test inventory and both-profile size receipts. Complete the release-plan gates held by the project owner with the candidate-bound release evidence package (producible on demand).
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
