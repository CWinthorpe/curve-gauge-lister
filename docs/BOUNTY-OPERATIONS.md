# GaugeBounty operations — beneficiary-bound ballots, prospective runbook

Nothing in this document implies production deployment or authorization. Beneficiary-in-hash binding is the mechanism; creator verification is neither claimed nor established. The existing Voting implementation remains pinned; no creator getter, attestor, receipt proof or upgrade is introduced. Paid operation still requires all implementation, conformance, audit and deployment gates.

## Custody and proposal preparation

The bounty holds only crvUSD stake/reward/DAO liabilities, not project CRV or veCRV. There is no projectTreasury, standing-lock funding/top-up/relock, checker probe or capital-dedication task. Do not send CRV to the bounty: unsolicited assets have no rescue and never create credits. Reporter proposal rights and any personal veCRV lock stay outside the bounty.

Contract-issued V2-to-bounty/venue approvals are exact and cleared. Reporter/payer allowances may exceed the exact amount pulled. Stake is exactly 1,000 crvUSD, separate from listing escrow and funded reward; donations never satisfy a credit obligation.

Reporter procedure:

1. Confirm chain/app, paid Active positive-remainder listing, false kill flag, supported factory/admin/Agent route and no recorded winning entitlement. Read upstream proposal requirements for the actual creator, which may be the reporter or a sponsor. Historically the app required 2,500 veCRV and a 43,200-second creator interval; these are upstream rules, not a bounty queue/capacity promise. Current requirements and source must be rechecked.
2. Choose a nonzero evidenceHash and a reportNonce. Compute the reportId using the exact domain/abi.encode order in BOUNTY-REWORK-PLAN §3.1 and the actual chain, bounty, V2, gauge/listing and submitting address. Nonce zero is legal; reuse of an accepted ID is not. Do not predict the next Aragon proposal ID.
3. Build the exact three-action CallsScript using that reportId and reporter: Agent.execute(bounty,0,creditBallot(id,reporter)); Agent.execute(killProxy,0,set_killed(gauge)); Agent.execute(bounty,0,recognizeKill(id)). Keep the fixed CallsScript type, framing, targets, order, zero ETH and exact calldata. The full hash, not a visible selector or description, binds the beneficiary.
4. The reporter or eligible sponsor creates the Ownership ballot; record the actual returned ID. StartVote creator is off-chain provenance only, not bounty admission authority. A contract-wallet beneficiary must itself submit, even if an EOA or another contract created the ballot. The bounty never calls newVote or casts a vote; there is no bounty automatic-YES policy.
5. Match the full script, explicit reporter, both reportId arguments, original start/snapshot/ratios and unexecuted state to the expected values. Approve stake and submit(gauge,proposalId,evidenceHash,reportNonce) from the named beneficiary no later than executeBy. Rejected submission creates no new report or bond and leaves accepted reports unchanged. The separately created upstream vote remains independent; failed admission does not roll back a prior transaction's vote.
6. Confirm ReportSubmitted and the stored reporter/proposal/clock. Evidence metadata may describe report, gauge and evidence link, but it is not on-chain creator proof and there is no enforced fixed description string. A signature from a claimant does not prove they created the vote.
7. Before official creation, approval and execution, the report monitor and governance liaison reconcile the full canonical script hash with the report's stored proposal ID and all identified duplicate proposal IDs, including approved-unexecuted historical ballots. Re-creating an identical payload does not replace the accepted binding. Do not tell the beneficiary to submit it again as a repair: report/proposal bindings are permanent. Flag duplicate approvals and record which ID is bound; execution remains permissionless and monitoring is not a guarantee that the bound ID executes first. Never delay an urgent protective kill to preserve a bounty or promise a compensating payment. An approved duplicate that already closed the report cannot be repaired by reordering later transactions.

## Permissionless monitoring and settlement

There is no servicePending, queueState, head, createBy or lock-maintenance loop. Subscribe to ReportSubmitted/state/claim/forfeit/reward events, indexed by gauge/report/proposal. The report monitor reconciles open offers and governance state at least hourly and reacts to ballot closure; submit does not promise a new full voting period. The local reward deadline is original ballot end plus seven days, never reset by submission or retries.

1. Anyone may execute a genuinely passed, closed ballot via Ownership Voting. A passing tally alone does not create an entitlement. Execute promptly where appropriate; execution order is public and cannot be reserved to a keeper.
2. Anyone may resolve a validated failed/ineligible case. Unknown/unreadable observations defer rather than slash; local expiry and a locally known other winner do not require external reads.
3. Anyone may claim for a reporter: funds always go to the stored reporter. A losing report can claim as soon as another winner is recognized. Otherwise local unresolved expiry is strictly after executeBy. Recognized bonds are claimable before FD settlement. Funded reward claims and bond refunds require a functioning crvUSD token but no non-token dependency.
4. Settle a killed listing through existing V2 checkpoint/confiscate when safe FD accounting is available; only the recognized winner receives floor(actual remaining/2). Keep the FD policy below. Flush only explicitly reserved forfeited stakes, never held stakes, reward credits or surplus. Never combine an urgent protective kill with a settlement operation whose failure could roll it back.

## Removed shared queue; remaining execution-order dependence

CGL-V-M01's shared-creator capacity mechanism and CGL-V-L04's checker/dedicated-project-CRV exposure are REMOVED WITH THEIR MECHANISMS. Do not operate or advertise the historical fifteen/fourteen creation ceiling, seven-day creation offer, 16+1 queue witness, capacity scan or project lock margin. The history of those mechanisms is not a current requirement.

Any number of distinct beneficiary-bound claims can coexist, including on one gauge; transaction resources and the actual creator's upstream rights/cooldown still apply. Different creators are permitted through sponsorship; mismatched beneficiaries are not. Each accepted report requires an exact beneficiary-bound ballot, a 1,000-crvUSD forfeitable stake and transaction resources. Bonds refund unless forfeited before payment; no automatic irreversible charge exists. Public evidence may be reused in separate bound ballots. Do not promise information ownership, execution priority or guaranteed admission availability.

The first valid flag-true recognition permanently wins the listing entitlement, not first submission/proposal ID. For distinct accepted reports, either report may win if its own bound ballot supplies the first qualifying execution; this is not a promise that duplicate ballots for one report are interchangeable. Losing non-forfeited reports refund once immediately through local winner cleanup. Subsequent unkill, time, stake claim or FD delay never replaces the winner or creates another reward. A recognized entitlement is still unfunded until exact V2 split settlement. Listing releases continue while live, and the offer can end without reward if the remainder is exhausted.

The CURRENT V2 owner responder reviews evidence of frivolous submissions while bonds are unpaid. Rejected governance, another report's recognition or an outage is not an automatic finding. Marking transfers only the unpaid stake into pinned-FD liability, not proposal/reward rights, and cannot reverse prior transaction ordering. A prior refund cannot be recovered. The report monitor escalates urgent gauge evidence through existing Curve governance/emergency processes, never delays a protective kill for an award, and never promises a compensating payment.

## Kill attribution, timing and faults

The three canonical actions execute atomically through the Ownership Agent. creditBallot/recognizeKill are Agent-only one-shot observations; creditBallot checks the stored reporter but only arms, while recognizeKill may record entitlement after the kill. Failed compatibility, beneficiary mismatch, malformed bounded reads, stale/unarmed callbacks or a pre-killed gauge yield no award without blocking the middle kill under adequate gas. No callback transfers tokens or calls FD. Whole-script equality and true current is_killed remain mandatory; controller weight is not a substitute.

Two valid beneficiary-bound proposals remain execution-order dependent. The recognized winner remains fixed during unkill/re-kill or delayed funding; a different report's callback cannot overwrite it. An already-killed gauge, including an emergency kill before creditBallot, yields no fresh attribution and a non-forfeited refund. Late execution after executeBy can still kill but cannot revive an expired report.

V-02 (Low, accepted) is a separate same-report case: two distinct approved proposal IDs can store identical canonical bytes for one beneficiary/gauge/report. Only one ID is bound at submit. If the bound ID executes first and qualifies, later duplicate callbacks cannot erase its winner or pay again. If the duplicate executes first while the bound ID is still unexecuted, its first callback closes the pending report NoAward, its middle kill can still succeed, and its final callback cannot recognize. Later execution of the bound ID cannot reopen the consumed report, even after an authorized unkill. The non-forfeited bond refunds once to the fixed reporter; the lost reporter half is not compensated. Without another eligible winner, B=0 and F=R for actual unreleased escrow at safe settlement. Identical-script approval is not a reservation of bounty entitlement. Duplicate review mitigates honest mistakes but neither revokes approved scripts nor guarantees ordering.

An old approved, unexecuted ballot can be executed by an outsider after its originating bounty expires. That authorized middle kill can preempt another unrecognized report; both reports' non-forfeited stakes still refund, and without a qualified entitlement the actual remainder goes entirely to the pinned FD when accounting permits. Removing FIFO does not revoke old DAO-approved scripts or guarantee attribution. Index old proposal IDs as well as live reports, inspect approved-unexecuted ballots before official solicitation, warn of this exposure and execute appropriate passed ballots promptly. Monitoring/private routing does not guarantee ordering. Bountyfix03 is withdrawn; no separate age-veto repair is claimed.

Actual ballot creation time, not submission time, determines the reward clock. Guard untrusted future/full-range timing values before arithmetic. A malformed stored observation can fail attribution without obstructing the ordinary kill; repaired dependencies do not revive a consumed NoAward offer. An unavailable observation cannot prevent the eventual local non-frivolous refund.

## Frivolousness

markFrivolous(reportId) authenticates the current V2 config owner. Its ONLY consequence is moving one unpaid 1,000 stake from heldStakes to pinned-FD liability. Phase, original deadlines, proposal, arm, winner, reward credit and V2 listing stay unchanged. A forfeited report can still win and receive its half. No separate frivolousness proposal, court, finality/grace period or automatic slash exists; unknown reports revert and refunded/already-forfeited bonds are inert.

### Local pins and venue availability (CGL-V-L01 FIX; CGL-V-L02 ACCEPTED)

Both findings are Low. New VotiumAdapter construction requires code at
crvUSD and the local votium ingress; new VoteMarketAdapter construction
requires code at crvUSD and the local CampaignRemoteManager. All existing
nonzero checks remain. The owner may be an EOA, and the remote votemarket
address is NOT checked for L1 code. Failure uses the constructor's existing
zero-argument rule first, then Error("no code") for empty local code. These
are minimum gates, not endpoint authentication or liveness guarantees.

Deployment policy — responsible roles: deployment operator, adapter manager
and lister config owner. Before enabling paid listings, record a pinned
block/chain, code/source identity and expected ABI for each local target;
check token identity/decimals/acceptance, real venue calls, exact
owner-authenticated one-time lister bindings, and every positive-share
adapter snapshot. Validate the remote VoteMarket on its DESTINATION chain,
including whitelist, MINIMUM_PERIODS and delivery, not by looking for its
code on L1. Keep paid admissions closed until the funded integration probes
pass. Use fresh correctly pinned adapters before accepting a fee; these
checks cannot repair already deployed bad snapshots.

Venue-availability policy — responsible roles: adapter manager and
settlement keeper. Poll compatibility and ETH float at least hourly while
releases are pending and simulate immediately before settlement. Votium's
current maxExclusions may fall below a previously accepted list length;
clear or shorten the list with setExcluded, preserving sorted/nonzero
requirements, then retry the same scheduled maturity. Check token/round
availability too. For VoteMarket, check ethDeficit for one deposit, the
backlog's aggregate funding needs, gas settings and actual remote/bridge
readiness; fund the one-way float and retry rather than skipping a quarter.

Either leg's revert rolls back BOTH shares, receipts, transfers and all
tentative quarter progression. Retained escrow is not guaranteed
availability. If an immutable ingress becomes permanently unusable,
ordinary releases on its existing listings may remain unavailable
indefinitely. There is no independent healthy-leg payout, migration,
payer refund, owner withdrawal or administrative kill-for-repair policy.
A legitimately killed gauge can use the separate venue-free confiscation
path, still conditional on FD/bounty accounting.

On persistent failure the config owner stops NEW paid listings with the
existing pause. Replacement adapters/new defaults are prospective only;
old listings keep their snapshotted destinations and obligations. Publish
their unresolved condition, retain settlement monitoring and do not describe
redeployment as recovery of old escrow. The round-one V-M02 acceptance of
spent campaign residuals remains separate and unchanged below.

### Gas-setting safety and float policy (CGL-V-L06, Low, FIX)

setGasSettings rejects unsafe values before storing/emitting. For positive
base B and price P, per-exclusion X and U=type(uint256).max, it requires
`X <= (U-B)/50`, then `P <= U/(B+50*X)`. Violations give BadGasSettings,
not Panic(0x11). Equality and X=0 remain allowed; all permitted exclusion
lengths 0..50 are protected even if the list grows later. Initial defaults
remain 2,000,000 base gas, 50,000 gas per exclusion and 1 gwei.

The adapter manager must still sanity-check pricing and float against the
actual bridge before changes. Arithmetic safety is NOT an affordability
limit, live fee quote or delivery guarantee. A valid but excessive budget
can still make deposits fail with InsufficientEth until corrected/funded.
ethDeficit(amount>0) quotes ONE message's configured funding shortfall,
independent of token amount, not the aggregate checkpoint/catch-up cost;
ethDeficit(0) is zero. Message call value is not necessarily net bridge
expenditure: returned ETH remains reusable committed float with no rescue.

### VoteMarket expenditure and residuals (V-M02 accepted)

A successful funded VoteMarket release is final expenditure from this
protocol's listing escrow. The adapter appoints itself campaign manager; its
L1 owner is NOT that manager for destination authentication. Transferring
adapter ownership does not change existing campaign managers or make the
numerical adapter address on Arbitrum a controlled recovery receiver. This
version deliberately provides no campaign-close, update-manager,
token-recovery, arbitrary-execution, receiver-selection or bridge-return API.

Unused/unclaimed destination rewards have NO ordinary project-controlled
recovery path. The protocol accepts permanent forfeiture of these stragglers;
they need not be small dust and may equal the entire campaign funding if
nobody qualifies or claims. They never restore a listing's remaining balance
or create a reporter/DAO credit. The bounty's half split applies only to
still-unreleased listing escrow, not to previously funded venue amounts.

In the verified venue reference, a 24-week claim period follows campaign end,
followed by a four-week manager close window. At/after that close-window
boundary, permissionless closure, subject to the venue's required prior-state
updates, sends the residual to the VoteMarket PLATFORM FEE COLLECTOR. It is
not an automatic timed transfer, not a refund to this project, and not a
deposit to the pinned Curve crvUSD FeeDistributor. Do not rely on possible
upstream governance intervention as a protocol recovery mechanism.

If crvUSD somehow returns to the L1 adapter or is donated there, the existing
deposit balance check preserves it while the next deposit pulls its FULL new
amount separately. That balance is not automatically reused or withdrawable.
No automatic L1 return is promised. ETH is different: unused message ETH
returned to the adapter stays in its reusable gas float; the float still has
no operator withdrawal/rescue path. Fund it as committed operating capital.

An L1 campaign receipt proves funded ingress and message submission, NOT
asynchronous destination delivery or a live destination campaign. Operators
must separately monitor destination creation and actual venue/remote/bridge
readiness before relying on campaigns. The audit's actual CRM/core
authorization/accounting tests use explicitly modelled transport,
wrapped-token delivery and oracle input; they are not a completed real
cross-chain lifecycle test. This acceptance does not waive deployment
readiness checks.

### FD checkpoint contention (CGL-V-L03, Low, ACCEPTED)

This expands/supersedes round-one V-I10's incomplete operational rationale:
passive cooldown is not the only risk. Any eligible public checkpoint,
including a direct upstream call, can win the shared window first and
repeatedly delay confiscation, reporter funding and forfeited-stake
flushing. Removing/gating our checkpointFees wrapper would not remove the
upstream race. There is no guaranteed safe-settlement time.

FD-window policy — responsible role: settlement keeper, with an upstream
FD-admin liaison. Poll at least hourly while settlement/flush is pending,
at least daily otherwise, and read again immediately before sending:

* Verify FD token identity, not-killed status and can_checkpoint_token.
  Public checkpoint eligibility is STRICTLY `now>last_token_time+86400`.
  Independently verify a nonzero, nonfuture cursor and
  `now<=floor(last_token_time/604800)*604800+20*604800`. A fresh cursor does
  not imply the public cooldown is over; a passed cooldown does not imply
  the bounded allocation horizon is safe.
* Prioritize an eligible pending confiscation over no-transfer housekeeping
  or a separate flush that would consume its window. Simulate, then submit
  seizure directly; a private transaction route may reduce ordering risk
  but guarantees nothing. If another checkpoint wins, retain the obligation
  and retry the next eligible opportunity using the NEW cursor.
* For a stale FD, keep funds in the lister/bounty. Refresh separately only
  after verifying `balanceOf(fd)==token_last_balance()` (zero unaccounted
  delta). Then wait STRICTLY beyond the new daily cooldown and attempt the
  seizure directly, without another pre-checkpoint. A positive unaccounted
  stale delta requires upstream attention; this protocol cannot call that
  refresh lossless. Disabled public checkpointing likewise needs legitimate
  upstream restoration, not a local recipient change.
* Never make an emergency kill contingent on settlement success: execute
  the protective kill separately, then settle when safe. An outer caller
  being FD admin does not give the inner lister/bounty admin identity.

Exact transfers, mandatory accounting and whole-transaction B/F rollback
remain unchanged. Recognition creates an unfunded entitlement, not reward
credit. Failed seizure retains escrow and undoes provisional bounty credit;
local non-forfeited bond refunds and ALREADY FUNDED reward claims remain
available with a functioning token. Recognition does not expire just for
waiting, but an authorized unkill followed by ordinary exhaustion may end
the unfunded offer. No owner withdrawal, alternate FD, best-effort monetary
accounting or old-liability migration is provided.

### Reporter proposal rights; no bounty lock/checker dependency

The standing-lock CGL-V-L04 exposure is retired with the code. The project dedicates no CRV principal to this bounty, and checker policy cannot block a removed bounty extension/relock. The actual creator, whether reporter or sponsor, remains responsible for upstream eligibility and any personal lock policy. A beneficiary without proposal rights may submit a correctly sponsored ballot. Without an authentic canonical ballot there is no accepted submission. Accepted reports, local refunds and funded claims do not require continuing proposal rights. Do not address upstream eligibility by funding the bounty or using a removed maintenance endpoint.

### Governance pin drift (CGL-V-L05, Low, retained)

Runtime compatibility remains fail-closed. Monitor the approved Voting/Agent implementation pointers, app/executor/factory/proxy code identities, executor binding, voteTime/support/quorum, factory.admin, killProxy.dao and exact Agent target/value/selector authorization. Beneficiary identity is in the canonical script, not a creator getter. Read live minBalance/minTime/creation-enabled state only to advise creators or sponsors; these are not a shared bounty capacity policy.

The governance liaison and report monitor reconcile at least hourly while offers are open, on change notices, and immediately before submit/execution. Incompatible submit reverts without retaining a stake; subsequent incompatible canonical execution can still kill but irreversibly close the offer NoAward. Restoration never revives a consumed offer. Already recognized funding does not re-run proposal pins, but remains subject to matching live listing/current flag, exact custody and FD accounting.

Warn reporters, stop official solicitation and, where appropriate, pause NEW paid listings on incompatibility. Neither action is a bounty submit pause. Coordinate nonurgent changes when governance permits, but never delay an urgent protective kill. Seek restoration through authorized upstream governance only; do not silently adopt new pins, change the beneficiary rule, relax compatibility or add a migration authority.

A lasting incompatible upstream change requires a separately reviewed configuration/deployment for FUTURE listings. It does not migrate old snapshots, stake/reward liabilities or entitlements. Keep paying/refunding existing obligations under their rules; there is no project standing principal to recover in this design.

## Disclosed limits

Submitter==canonical beneficiary prevents a mismatched ballot from being admitted; it does not authenticate the creator or establish ownership of public evidence. An eligible creator may sponsor the named beneficiary. First valid recognition is execution-order dependent. Payer==reporter remains allowed; coordinated payer/reporter/keeper activity is not distinguished. Private relays and monitoring cannot guarantee priority or reward.

Frivolousness is ordinary transaction ordering, not an adjudication window:
an eligible refund (a bond already Refundable, e.g. after recognition,
rejection, no-award or a local timeout) can win the race and be claimed
BEFORE `markFrivolous` lands. There is no protected adjudication period and
no clawback after payment — once the bond is paid to the stored reporter,
marking that case is permanently inert (§3.2; covered by regression tests). Refundable bonds deter spam only while the DAO
actually forfeits unpaid ones: operators who want a slash must land
`markFrivolous` first; the design deliberately trades the deleted court's
late-slash opportunity for immediate refunds and will not quietly restore
it with a grace or finality timer.

### Rework verification boundary and reward limits

The standing-lock/queue architecture and its capacity mechanisms are removed with their code; the round-two queue and checker findings are not re-labelled as fixed — those mechanisms no longer exist. The retained limits keep their names and stated bounds: adapter hardening (CGL-V-L01/L06), venue availability (CGL-V-L02), FD contention (CGL-V-L03), governance pin drift (CGL-V-L05) and campaign residual loss (V-M02). Historical audit counts and severities describe their original candidates only.

Creator equality is neither required nor established; the beneficiary lives in the canonical script, not in a getter, indexer or metadata. The trusted-factory amendment preserves the bounty interfaces and V2's original 31 callables, adding only the `trustedGaugeValidator` getter, the eighth constructor argument and two errors (32 V2 functions total).

Rewards require valid beneficiary-bound canonical recognition and actual still-unreleased escrow. Ordinary permissionless releases can exhaust that remainder while the flag is false. Independent authorized kills and old approved scripts can prevent fresh attribution. Recognition fixes one report, not a minimum payout: subsequent unkill and exhaustion can leave no reward. There is no escrow freeze, retrospective kill history, duplicate allocation, compensating-payment promise or attribution to a different beneficiary's ballot. Bond forfeiture does not cancel a qualifying reward.

Inherited all-FD economics are V1-only. V2 pays floor(R/2) to its single eligible winner and R-floor(R/2) to the pinned FD, else all-FD, with full accounting/rollback. Frozen V1 has no mainnet-only constructor guard unlike V2/bounty; deployment operators still verify chain/pins. Invalid ERC20 bool results fail closed without a guaranteed uniform error. Donations create no credit and have no rescue; adapter ETH is reusable committed float without an owner withdrawal. No project CRV lock remains.

Before paid operation re-verify the explicit V2 validator pin, its owner/manager authority and the intended factories' current module policies using docs/DEPLOYMENT-PINS.md. Validator failure or revocation blocks new paid admission, not existing settlement; do not route around it through frozen V1. The DAO-free lane remains intentionally factory-exempt. Bounty eligibility is still the narrower supported kill-route policy, not every factory the admission validator trusts. Before paid operation assign the report monitor, current config-owner responder, adapter manager, settlement keeper and governance/FD-admin liaisons. These are staffing requirements, not newly built monitors or an on-chain submit pause. Respect prospective deployment and real seating/bridge readiness requirements; no existing snapshot or liability is migrated by this rework.
