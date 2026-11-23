# CX-AUTH — Candidate-specific invariant → clause → implementation → evidence index

Current product: `d88d633c64fde7b3f37e29d846f744747186a688`.
Current authority: `review/r3gate/RULING.md` C03, carrying the approved
V1ALIGN law and admitted simplify/simplify2 decisions. The r2 origin is
CX-AUTH; historical S/CX/auditfix labels below explain provenance, not a
requirement to reconstruct another authority stack. The invariant column is
the resolved current rule for this candidate; the named current plan/manifest
and this r3gate resolution control on conflict with old wording.

SATISFIED-TRACKING / ACTIVATION-OPEN (PAO-AUTH). C03 repairs the incorrect
admission citation and missing fork-clause resolution here. Final-candidate
build/receipt binding and owner approval remain open. This carrier is
selectively published under the r3gate operator order; the complete package
and its approval remain owner-controlled and producible on demand. A path or
DONE label is not release approval, and release approval is not activation.
PAO-FD and PAO-CTL remain separately open under their current supplements.

## Legacy §-marker resolution (shipping sources)

| Marker (as used in tracked sources) | Resolves to (owner-held authority) |
| --- | --- |
| `plan §3.1` (core types/constants/storage/events/errors) | plans/V1ALIGN-PLAN.md "ABI, storage and deletion manifest" (§3) + this index O-01/O-02 |
| `plan §4` (admission steps) | plans/V1ALIGN-PLAN.md §2.1 "Constructor and admission", especially the `listGauge` order paragraph; current O-03 below |
| `plan §5` (settlement) | plans/V1ALIGN-PLAN.md §2.2 "Settlement and all-FD confiscation — mandatory unchanged law" |
| `plan §6` (confiscation) | plans/V1ALIGN-PLAN.md §2.2 items 1–5 (atomic ordering) + CX-FD bound obligation (this package, FD-BOUND-OBLIGATION.md) |
| `plan §7` (platforms) | plans/V1ALIGN-PLAN.md §2.3 adapter/shared protections + docs/OPERATIONS.md venue matrix |
| `plans/V1ALIGN-PLAN.md §2.1` | trusted-validator admission amendment (this index O-04) |
| `auditfix001 §1` | one-time owner-gated adapter binding law (O-07) |
| `auditfix001 §2` | paid-admission adapter-binding readiness (O-08) |
| `auditfix001 §3` | FD mandatory same-transaction accounting (O-05) |
| `auditfix001 §4` | MockFeeDistributor fault seams (fixture-only controls, O-14) |
| `auditfix001 §5/§7` | custody/observation strengthenings incl. FD field locality (O-12/O-13) |
| `A2.3` / `A2.4` | Amendment A2 kill-oracle law (O-06) / gauge mock flag shape (fixture) |
| `review1 finding 9`, `exec7`, `R8-1/2/3/4`, `V-H01`, `H01`, `S01–S27` | earlier named work orders and prior-sweep rows recorded in review/v1align-execution/FINAL.md and review/v1align-simplify/RELEASE-EVIDENCE.md §1; their preservation clauses remain in force unless superseded below |
| `FORK-PLAN §…` and bare fork-fixture section markers | review/r3gate/FORK-CLAUSE-RESOLUTION.md: actual archived planning/amendment objects, current V1ALIGN approvals and explicit r3gate resolution; no nonexistent checkout path or obsolete test count/cooldown rule |
| `INTEL §3.3/§4` | docs/INTEL-YB-HELPERS.md research record — HISTORICAL; current law is annotated at each site (r2 CX-HISTORY); never authority to reintroduce the standing-approval exception or the stale receipt formula |

## Obligation index

| ID | Invariant (as controlled) | Clause + supersession | Implementation | Independent evidence |
| --- | --- | --- | --- | --- |
| O-01 | Exact 30-function/10-event/33-error core ABI; 15-field Listing; recursive layout slots 0–7; adapters' published surfaces | plans/V1ALIGN-MANIFEST.json (normative; sha256 in RELEASE-EVIDENCE §2) | contracts/* | receipts/final-manifest-comparison.txt (fresh compile, both profiles, exact equality) + in-tree `test_Adapter_CompiledAbiSurfaceMatchesAllowlist` (signature keys + no-fallback probe ONLY — README §Running checks boundary) |
| O-02 | Fixed economics FEE=QUARTER*EPOCHS=10,000e18, 4×2,500e18, WEEK=604800, BPS=10000, INITIAL_WEIGHT=0 | plan §2.2; r2 CX-CONSTANTS derives FEE at declaration WITHOUT value/getter/layout change | contracts/CurveGaugeLister.sol constants | `test_NoOwnerWithdrawalOrArbitraryExecutionSurface` literal-constant assertions (kept independent per row) |
| O-03 | Paid lane: anyone-callable, not-paused; `_admit` read-only phase → trust → binding on same snapshot → record/escrow → exact fee → `add_gauge(…,0)` → immediate canonical typed-membership postcheck (type zero valid) → GaugeListed; DAO lane owner-only, paused-OK, no trust/readiness/fee and owner-supplied weight | plans/V1ALIGN-PLAN.md §2.1 paid-lane order; current shared identical-work helpers do not merge lane guards (CX-ADMIT provenance) | core `listGauge`/`listGaugeNoEscrow` + `_admit`/`_writeAdmittedRecord`/`_seatMembership` | TF identity 4 poison/whole-record cells, identity 6 precedence, `test_PaidListingUsesZeroWeightAndMembershipOnly`, fork paid/seating witnesses; selected-production caller/role/route proof remains PAO-CTL, not this fixture |
| O-04 | Validator: immutable seventh arg, one `validateGauge(gauge)` staticcall, exact-32 canonical-1; zero→`UntrustedGauge`; failure/length/word>1→`TrustedGaugeCheckFailed`; no bubbling, no fallback decode, admission-only | plan §2.1; r2 CX-HISTORY places the call-site law beside the interface declaration | core `_requireTrustedGauge`; interfaces/ITrustedGaugeValidator @dev | TF identities 1/2/3/5/6/8; fork TF identities (live pinned predicate); receipts/final-fork-r2.log |
| O-05 | Confiscation: one bound obligation (floored inclusive horizon, separate eligibility, exact two-sided custody, mandatory checkpoint, both postchecks, whole-call rollback) | plan §2.2 items 1–5 + auditfix001 §3; r2 CX-FD single-obligation binding + CX-AMOUNT direct remainder derivation + CX-ADAPTER direction-first predicate (credit/addition and baseline checks NOT equated) | core `_confiscate`, `_gaugeKilled` callers, `FD_ACCOUNTING_HORIZON_WEEKS`, `_exactOutboundDelta` | FD-BOUND-OBLIGATION.md; `test_AuditM01_*` identities (independent interval oracle; boundary/same-ts/rounding cells), `test_KillViaGaugeFlagOnlyConfiscates`, fork `test_Fork_ConfiscationRequiresFreshAccountableFeeDistributor`, `test_Fork_MidDripKillStopsLaterTranchesAndSeizesRemainder` |
| O-06 | Kill oracle is gauge `is_killed()` ONLY; per-quarter observation unit (initial read covers tranche one; later quarters reread; both legs commit as a unit); weight never a kill signal; read failure reverts | plan §2.2 (A2); r2 CX-QUARTER documents + extends witness | core `checkpoint`/`confiscate`/`releasable`/`_gaugeKilled`; interfaces/ICurveGauge @dev (stable reference) | `test_KilledFlagTrueAtMaturityStopsMidCatchUp` (BOTH legs, r2), `test_GaugeFlagReadFailure*`, `test_TerminalStatesSkipKillOracleReads`, `test_WeightZeroWithoutKilledFlagDoesNotConfiscate`, fork kill identities |
| O-07 | Adapter binding: owner-only write-once `setLister`, nonzero code target, no rebind/recovery even across ownership transfer; ownership proposal is nonzero/current-owner-only, only pending owner accepts and clears pending state, with existing events and errors | plans/V1ALIGN-PLAN.md §2.3 and this resolved rule; stateless predicates retained (auditfix001/S22/CX-ADAPTER provenance) | adapters `setLister`/`lister`, libraries/AdapterOwnable, libraries/AdapterCustody | `test_Adapter_VotiumNonListerAndBindingRejects`, `test_Adapter_OwnershipTransferTwoStep` (same-instance pending/acceptance, outsider and bound no-rebind controls), fork binding readbacks in `_deployTrioAt` |
| O-08 | Paid admission refuses unbound/misbound positive-share adapters before any fee/record/liability/controller-add effect; zero-share never read; prospective staging allowed without weakening per-admission checks | plans/V1ALIGN-PLAN.md §§2.1,2.3; auditfix001 label is provenance | core `_requireAdaptersBound`/`_requireAdapterBound` | `test_AuditH01_PaidAdmissionRejectsUnboundOrMisboundAdapters`, `test_AuditH01_ReadinessGetterFailuresAndZeroShareExemption` |
| O-09 | Receipts: one common contract — nonzero adapter-domain L1-ingress correlation; Votium event-only repeatable full tuple; VoteMarket keyed+chronological records, pair-key rejection, derived-behind-getters receipt (row + one-based position; member/stride kept; no raw-slot evidence retained — explicit decision); getters only where implemented | S09 + r2 CX-RECEIPT (wording) + r2 CX-DERIVED-RECEIPT (layout-preserving derivation; no gas claim) | adapters' receipt sites + `getDeposit`/`depositAt`; IIncentivePlatform @notice | `test_Adapter_VotiumDeterministicNonzeroReceipts`, `test_Adapter_VoteMarketDuplicateGuardAndNonceReceipts`, `test_Adapter_EndToEndFourQuartersSettleViaCheckpoint` (chronological==keyed), fork `_assertAdapterRecord`/`_assertCampaignDepositLog` |
| O-10 | Custody observations: core exact funding debit plus nonzero adapter attestation; adapters exact pull credit and return to pre-pull balance (no new retention, not an independent recipient-credit check); FD exact debit AND credit; bounded zero-first/exact approvals, one checked zero on a zero request, final clear, no standing approval/withdrawal/rescue, one-way ETH float | plans/V1ALIGN-PLAN.md §§2.2–2.3; current predicate/approval representation retained; r3gate C05/C07 correct claims only | core `_fundPlatform`/`_confiscate`; AdapterCustody; SafeToken; adapters | independent venue transfers/custody/float plus final allowances; fork `_assertApprovalTrace` is a CRVUSD/owner/spender-scoped MULTISET with exact multiplicity/exhaustion including Votium `gross-fee`, NOT lifecycle order per deposit; C07 builder comments pending |
| O-11 | Venue policy asymmetry kept: Votium unsigned strict-increase + live `maxExclusions()`; VoteMarket arbitrary distinct caller order; ordered copies after validation only, both caps and empty-list exemption; live manager settings remain live; VoteMarket worst-case length50 arithmetic guards precede mutation, positive-amount `ethDeficit` quotes one message's configured funding shortfall and zero amount returns zero | plans/V1ALIGN-PLAN.md §2.3 and this resolved rule (R12/R17/CX-EXCLUDED/CX-QUOTE provenance) | adapters `setExcluded`; VoteMarket `setGasSettings`/`ethDeficit`/`deposit` | exclusion/configuration witnesses and standalone R2 gas-setting boundary/rejection/rollback identities; quotes are not executability or delivery guarantees |
| O-12 | Escrow ledger: deposited=remaining+released+confiscated; Active-only public `remaining`; due ≠ remaining; capped paid-age `epochsElapsed`; aggregate `totalEscrow` sum-of-paid-remainments; terminal no-ops; observed confiscation terminal after unkill | S14/S27 + r2 CX-AMOUNT (custody amount independent of display filter) | core `getListing`/`_remaining`/`_releasedAmount`/`_maturedUnpaid`/`_cappedElapsed` | `test_FourEpochQuarterRelease`, `test_KillAtEachReleaseCount`, `test_ObservedConfiscationStaysTerminalAfterFlagCleared`, fork `_assertLedger`/`_assertConfiscatedLedger` (whole-listing hash in Snap) |
| O-13 | Complete public listing observations in ordering/rollback witnesses (whole `getListing` keccak + separate `totalEscrow`; distinct custody/controller/allowance/venue fields kept) | r2 CX-TRUST | test/mocks/TrustedFactoryMocks.sol `PreAdmissionObservingValidator`; test/TrustedFactoryFixture.sol `Snap`; fork Snap (already hash-form) | TF identity 4 cells (a)-(e), all snapshot-equality cells; fork full-state rollback comparisons |
| O-14 | Fixtures are disclosed models, never authority: YB-helper history annotated at stale sites; module/validator faults = disclosed injection only; code-bearing missing-selector mock kept though `unrelated()` uncalled; dead setters pruned ONLY (voteForGauge/allowToken/setFault/setMinter — zero callers, verified) | R16/R17 law + r2 CX-MOCK-PRUNE/CX-HISTORY | contracts/mocks/*, test/mocks/*, docs/INTEL-YB-HELPERS.md annotations | grep-verified zero callers (commit 83db13a); suite green with prunes; behavioral cells of retained controls unchanged |
| O-15 | Claims must not exceed observations: fixture pricing is not a venue guard; L1 submission is not L2 delivery; gross expenditure is not net reward/readiness; confiscation is conditional on observed current flag and successful accounting; token decoder failure is not always the local custom error; `EscrowConfiscated` follows mandatory checks, maintenance Boolean only means upstream returned | current resolved rule; r3gate C05/C13/C15 admits remaining wording corrections, not new behavior; CX-LABELS/CX-MAINT provenance retained | actual adapter/token/core branches and existing public prose | source/cell attribution in r3gate RULING; builder wording corrections OPEN; exact identity equality is not itself proof of unchanged assertions, which the work order separately freezes |
| O-16 | Fork selection vs clock: fail-closed header preflight (hash/number/timestamp/chain) is the selected-fork-identity check; in-EVM assertions + optional warp are scenario clock restoration; neither substitutes | r2 CX-FORK-CLOCK | scripts/test-fork.sh; ForkFixture `_freshFork` | receipts/final-fork-r2.log preflight lines; unreachable-RPC preflight fail (prior package G4 control) |
| O-17 | Shared fork setup, both targets: one destination-parameterized `_deployTrioAt`; provenance/validator-pin checks pre-write; controller-pin assertion on both; DAO-scoped bindings + readback; paused postcondition; explicit activation | r2 CX-FORK-SETUP | ForkFixture | all 13 fork identities; `_assertPrimaryProvenance`/`_assertValidatorPinAtFork` receipts |
| O-18 | Census: 77 offline + 13 fork identities, exact set equality; AdapterConfigR2Test stays standalone at its historical path (shared funding-driver extraction remains barred, prior S17 DECLINED clause) | plans/V1ALIGN-PLAN.md §4 + WITNESS inventory | test tree | receipts/final-identity-set.txt (sha256 61cbba7a…, set-equality check) |
| O-19 | Deployable size ceiling: every product runtime ≤ 24,576 decoded bytes | plan §5 G5 | build artifacts | sizes + sha256 table in RELEASE-EVIDENCE.md §Sizes |
| O-20 | Owner-controlled evidence/approval: historical V2/proposal remains archived; complete candidate package is producible on demand; selective r3gate publication neither publishes all receipts nor constitutes approval by path existence | current operator R3GATE-BRIEF publication exception and RULING §1; full manifest/witness authority remains hash-bound in BINDING.json | README evidence boundary (limited builder update owed); this index and current PAO carriers | r3gate input/product hashes and validation; owner final-candidate approval and deployment certificates remain OPEN |

Row supersessions recorded: CX-CONSTANTS supersedes the literal-equal FEE
declaration; CX-AMOUNT supersedes routing the confiscation amount through
the display's status filter; CX-ADMIT supersedes the duplicated
record/membership blocks with shared identical-work helpers (gates NOT
merged); CX-ADAPTER supersedes the two inline debit comparisons with the
direction-first predicate and the four duplicated adapter comparisons with
AdapterCustody predicates; CX-EXCLUDED supersedes manual copy loops with
ordered data-location copies; CX-DERIVED-RECEIPT supersedes storing the
receipt as evidence while keeping member/stride/getter behaviour;
CX-QUOTE supersedes the duplicated priced-message expression with the
named one-message helper; CX-TRUST supersedes the status+aggregate
projection in the observing validator and Snap; CX-FORK-SETUP supersedes
the two near-duplicate trio deploys; CX-FORK-TRACE supersedes value-
filtered approval counts with bounded pair traces. Everything not listed
here is unchanged.

## Current resolved boundary and approval ledger (r3gate)

The legacy admission `plan §4` reference resolves to V1ALIGN-PLAN §2.1,
not §1.3 or the settlement section. `_admit` retains nonzero/code checks,
permanent local uniqueness and successful typed-read occupancy rejection
BEFORE registry/trust/custody; bounded registry indices, pool/gauge/LP
authentication, false admission kill flag, handler-derived valid type and
distinct/nonzero used coins remain mandatory. A caught absence-read failure
only permits later checks, not proof of production health. Both lanes retain
their own gates and the add-then-readback health postcondition. The constructor
remains chain1-first, seven arguments, explicit immutable validator, current
code/token/FD/config checks and paused start. Existing locks, named rejection
precedence, zero-share exemptions and prospective-only configs are unchanged.

The current receipt contract is `IIncentivePlatform.deposit`, resolved in
O-09. Distinct-positive-endpoint policy belongs to the core; keyed/repeatable
receipt and exclusion policies belong to the respective adapters. Do not
move those policies into a generic receipt/custody promise. Source labels and
historical provenance never override these boundaries.

`review/r3gate/FORK-CLAUSE-RESOLUTION.md` supplies the actual archived fork
approval/amendment objects and the current approved fork clauses, including
which old count, binding and cooldown text is superseded. No broad historical
comment deletion or public evidence migration is authorized. The earlier
table's r2 receipts remain evidence of their recorded candidate, not fresh
executions by this authority leg.

| Binding/approval cell | Current status |
| --- | --- |
| Product reviewed | d88d633c64fde7b3f37e29d846f744747186a688; all tracked bytes match the r3 supplied product snapshot (BINDING.json). |
| Authority/manifests/census | Actual pre-ruling digests and exact 77/13 full-signature sets are locked in BINDING.json; immutable manifest/witness documents were not edited. |
| Current map/citation repair | C03 delivered by r3gate; SATISFIED-TRACKING, not a production certificate. |
| Admitted builder claims | C03 publication wording and final binding, C05/C07/C13/C15 corrections OPEN under plans/R3GATE-WORK-ORDER.md. |
| Final shipped candidate and fresh gate receipts | OPEN until builder/confirmation supplies exact hashes and native results; append a candidate-specific addendum here rather than another index. |
| Final owner release-evidence approval | OPEN; deployment operator assembles, owner/governance release authority approves; no named completed approval is inferred. |
| Selected production certificates/enablement | PAO-FD and PAO-CTL ACTIVATION-OPEN, plus every independent deployment gate in DEPLOYMENT-PINS. |

These registration duties are satisfied for the current design review. Future
rounds must use the verbatim r3gate evidence standard: an unchanged acknowledged
activation gate is not a confirmed simplification; a concrete new contradiction,
missing current-law mapping, stale binding or bypass remains reportable. Final
candidate approval and activation cannot be claimed while their cells are open.
