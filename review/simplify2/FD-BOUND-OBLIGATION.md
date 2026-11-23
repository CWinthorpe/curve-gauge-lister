# CX-FD — One confiscation-accounting proof bound to the selected pinned allocator

Original r2 carrier: candidate-bound, owner-held and producible on demand. Authority:
`/home/winny/audits-work/cgl-v1align-cx-r2/audits/complexity-review-verified-2026-11-23.md`
row CX-FD (rank 1). Verdict file sha256
`996822e104456557311bd55e24389620253bb156084041f0b6a98fbc0aac5cab`.

## The selected pinned allocator

Destination: crvUSD FeeDistributor `0xD16d5eC345Dd86Fb63C6a9C43c517210F1027914`
(docs/DEPLOYMENT-PINS.md "Intended constructor dependencies", row 4;
immutable as `CurveGaugeLister.feeDistributor`). The allocator model is
`CurveFeeDistribution.vy` `_checkpoint_token`, whose bounded
`for i in range(20)` week-iteration loop apportions the accumulated
fee-token delta from the cursor's week floor. The verification record for
THIS candidate is the pinned regression fork (chain 1, block 26401019,
hash `0x55810b079923a14fb97ad548f5024f65530dbc4fb2357a38f41e13b3d27cb6d3`,
timestamp 1794512471 — docs/DEPLOYMENT-PINS.md §Fixed regression-fork
anchor), where the fork suite asserts the FD runtime keccak
`H_FD = 0x04ba5a2515caeeb9a3839afb59c8a0cc1f76df17b7f436171782fe880be1ad8d`
(read-only in `_assertPrimaryProvenance`, `test/fork/ForkFixture.sol`) and
executes live reads of `token`, `is_killed`, `admin`,
`can_checkpoint_token`, `last_token_time`, `token_last_balance`,
`tokens_per_week` and actual crvUSD custody through `IFdVenue`.

Release binding: docs/DEPLOYMENT-PINS.md §Re-verification procedure
requires, at a newly recorded fixed block, the full runtime bytes + hash
and verified source for every dependency, and (§FD paragraph, line 112)
records "admin, can_checkpoint_token, last_token_time, token_last_balance,
actual crvUSD balance and bounded-loop/cooldown source" and requires
"public checkpoint availability for the ordinary lister, nonzero/nonfuture
cursor, `now<=floor(t/604800)*604800+20*604800` and strict public
eligibility `now>t+86400`". Those recorded reads ARE the allocator
source/runtime binding this obligation attaches to; they are operational
re-verification duties at release, not this repository's compile-time
claims.

## THE ONE OBLIGATION (stated together, bound to that source/runtime)

For any confiscation of an Active listing's exact remainder, ALL of the
following must hold in the SAME transaction, keyed to the selected
allocator identified above:

1. FLOORED INCLUSIVE COVERAGE BOUND. Read cursor `t = last_token_time()`
   BEFORE any terminal effect or transfer: `t != 0`, `t <= now`, and
   `now <= epochStart(t) + FD_ACCOUNTING_HORIZON_WEEKS * WEEK` — the
   first partial week consumes one of the allocator's 20 bounded-loop
   iterations, so `H == now` passes and `H + 1` reverts
   (`DistributorUnusable`). Implementation: `contracts/CurveGaugeLister.sol`
   constant `FD_ACCOUNTING_HORIZON_WEEKS` (@dev names the allocator
   source/runtime binding) and `_confiscate` Step 2.
2. SEPARATE ORDINARY-CALLER ELIGIBILITY. As a non-admin caller the lister
   additionally needs the allocator's PUBLIC checkpoint eligibility —
   `can_checkpoint_token()` AND strictly `now > t + 86400` (the mock
   models both). Availability is not coverage; coverage is not
   availability; neither implies the other. (R01 law: the two are kept
   distinct, and the constant stays private confiscation logic.)
3. EXACT TWO-SIDED CUSTODY. Transfer exactly `R = FEE -
   QUARTER*epochsReleased` (CX-AMOUNT derivation); the lister debit must
   equal exactly `-R` (direction-first predicate `_exactOutboundDelta`,
   never an arithmetic Panic) and the FD credit must equal exactly `+R`
   in addition form; the two comparisons are distinct boundaries with
   distinct errors.
4. MANDATORY IN-TRANSACTION ACCOUNTING. `checkpoint_token()` called
   directly, no catch, no pre-transfer checkpoint, after the transfer.
5. BOTH POSTCHECKS. `last_token_time() == now` AND
   `token_last_balance() == balanceOf(fd)`; any failure reverts
   EVERYTHING, including earlier quarters of the same checkpoint
   (whole-call rollback; policy: retained escrow beats an unrecoverable
   allocation omission).
6. ROUNDING. Normal upstream per-bucket truncation dust is preserved as
   acceptable (independent oracle: `allocated <= total` and
   `total - allocated < coveredWeeks`); an omitted allocation TAIL is
   the unsafe case the horizon forbids.
7. SHARED-WINDOW SERIALIZATION LIMIT (explicit). A third-party public
   checkpoint can win the shared daily window and postpone settlement
   indefinitely; the product guarantees conditionally available
   accounting, not a completion time. Documented at
   docs/OPERATIONS.md §Mandatory FD safe-accounting and contention and in
   `test/fork/ForkKill.t.sol` cooldown cells including the
   admin-outer/inner-lister control.

## What remains INDEPENDENT (this row's law)

* The expected-bucket oracle stays independent interval arithmetic over
  the week grid (`_assertUpstreamAllocation`, test/Settlement.t.sol,
  identity `test_AuditM01_AccountingHorizonIncludesPartialWeekEdges`):
  boundary cells H-1/H/H+1, the near-end-of-week offset-2 case where
  `now - t < 20*WEEK` but the floored horizon rejects, and the
  same-timestamp allocator branch. Its expectations are never derived
  from the core's own literal or from the mock's code path (R01: the
  mock keeps its own fixture-side 20-loop copy of the upstream model;
  the fork repeats a literal, not a getter — unchanged).
* The accepted horizon is NOT narrowed: 20 weeks from the cursor's week
  floor, equality passing. The pinned fork observes real bucket credits
  on the shorter recovery interval
  (`test_Fork_ConfiscationRequiresFreshAccountableFeeDistributor`
  subcase 2: `(a0-b0)+(a1-b1) == FEE` over the affected buckets); the
  exact-horizon boundary stays model-based offline — neither substitutes
  for the other (R02 law).
* `EscrowConfiscated` remains the completion signal (CX-MAINT); the
  mandatory checkpoint's postchecks precede it; no evidence claim is
  made from the wrapper's Boolean.

## Still OPEN (confirmed question, not an implementation authorization)

Q2 (r2) asks whether ADDITIONAL independently attributable near-end
sensitivity is required under an approved evidence change for the
allocator. That is an owner/acceptance decision; nothing in this package
invents it, and no additional evidence dependency was added by simplify2.

## r3gate status supplement — PAO-FD

Current product: `d88d633c64fde7b3f37e29d846f744747186a688`.
Authority: `review/r3gate/RULING.md` §§2–3, C01 (DEFER production
certificate; no builder code authorization).

SATISFIED-TRACKING / ACTIVATION-OPEN. The existing r2 package satisfies the
present obligation to identify the invariant, evidence limits and activation
gate. Its DONE label is not a completed selected-deployment accounting
certificate. The release-binding paragraph above describes REQUIRED future
records, not records already produced by this carrier. This supplement is
selectively published under the r3gate operator order; the full evidence
package remains owner-held. The original r2 release receipt is unchanged.

Owner/approver roles: deployment operator supplies source/runtime/state
bindings and the accounting proof; settlement keeper and FD-admin liaison
supply operational evidence; the owner/governance release authority approves
the exact package before paid admission is enabled. No individual appointment
or completed approval is asserted.

| Certificate row | Existing scope credited | Missing before activation |
| --- | --- | --- |
| Identity | Historical fork asserts the intended FD runtime at the fixed regression pin. | Current selected chain/block/hash/time, full runtime and verified source revision/content binding (including any implementation), actual loop/arithmetic/caller rule and relevant cursor writers; no source title or old hash alone. |
| Coverage | Independent model interval oracle at H-1/H/H+1 and same-timestamp/rounding cells; shorter live recovery bucket increments are separate evidence. | General runtime-bound composition proving coverage for the accepted floored inclusive horizon, including pre-existing unaccounted custody and existing bucket balances; either a source-bound argument or independent before/after increments over the TOTAL allocator delta, never a sum of separately rounded sources. |
| Custody | Product requires exact full-remainder lister debit AND FD credit before accounting. | Bind those unchanged checks and funded observations to the final candidate/selected token and allocator; do not treat adapter baseline checks as the same boundary. |
| Postconditions | Mandatory same-transaction checkpoint, cursor==now and accounted balance==custody, with whole-call rollback. | Bind the actual source/runtime meaning of both fields; the model writes them before allocation, so their equality is not itself a coverage certificate. |
| Availability | Ordinary non-admin caller, public flag and strict cooldown are distinct from coverage; indefinite shared-window postponement is disclosed. | Current state and role observations, actual cursor-writing entry points, operational demand/contention assumptions and accepted escalation policy; no finite completion-time promise. |
| Stale refresh | The fork's stale-recovery scenario establishes zero delta in its controlled execution. | Execution-time support for zero unaccounted delta, not just a pre-submission balance read; if custody may change before execution and the premise cannot be established, do not claim/schedule a lossless stale refresh. Positive stale delta remains an upstream problem. |
| Sensitivity/approval | VC-02 accepts the reached offset-1 H+1 guard sensitivity; pristine near-end cells remain binding, and the later near-end mutant cell is not claimed reached. | Release authority explicitly decides whether the selected-runtime coverage argument needs additional independently attributable sensitivity. No extra regression or inventory amendment is authorized by r3gate. |

Here TOTAL delta means the custody delta actually consumed by the selected
allocator at checkpoint, including the confiscation remainder and any
pre-existing unaccounted funds. Compare bucket INCREMENTS, not assumed-zero
historical buckets. Retain upstream truncation/dust semantics. An argument
over a clean-state single source is not automatically a commingled certificate.

Activation stop condition: any missing/rejected row or unapproved candidate
binding leaves paid admission disabled. No horizon narrowing/export, guard
deletion, transfer-only terminalization, pre-transfer checkpoint, alternate
recipient, batching, refund or recovery surface is authorized. Future design
rounds carry this obligation without re-counting it as a simplification unless
they establish a concrete new defect under the r3gate evidence standard.
