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


## r3docs final-shipped-candidate binding addendum (appended by the builder, C03/P0)

Final shipped product/docs candidate: `a9de6ffc99343801575b72a2be78ea83bd73508c`
(P2+P0; sole product-side parent commit `340db1d40882f4a3a8432e9bc0e5505023faf99d`,
P1; both descend from authority `62c8326ff2bdac2aa4917bf2caac9aaa71bf31f9`).
The product tree is byte-identical to the bound baseline
`d88d633c64fde7b3f37e29d846f744747186a688` except the ten allowlisted
comment/prose files below; receipts land in the final `r3docs:` commit under
`review/r3docs/` per the operator leg brief. Previous candidate records above
are preserved unchanged as history; this is the candidate-specific addendum
required by the r3gate ledger, not another index.

### Facts produced by the builder (records, not approvals)

Admitted rows implemented: C03 (publication wording + this binding), C05,
C07, C13, C15 — comments/prose only. The G5 independent confirmation pass
and owner approval remain outside this leg's outputs.

Source digests (sha256) of the ten changed files at the candidate:

| path | sha256 |
| --- | --- |
| `README.md` | `eabb56ea1dacba33f21aa91cb4d1cf656adbd1d94c3ffe0a8e3f2fb9cab2961e` |
| `contracts/adapters/VoteMarketAdapter.sol` | `7e7c46bc649c3ab6972fccc4bbe9b2f9f3b3dc3f04bef43e8d2fde7c65b58fdd` |
| `contracts/adapters/VotiumAdapter.sol` | `a8fdb6b283b6aef00637836e587980606c00ab9a3736411c9fa6d88bff60bf15` |
| `contracts/interfaces/ICampaignRemoteManager.sol` | `4d45eb62d4776b6cbe75ade6d6a7b5756a827972f60e7ef50bff52957e866c4d` |
| `contracts/libraries/SafeToken.sol` | `99f608a32758d0e733524b490dd94b43f136c06f9c03e9decdcabe79ff905447` |
| `docs/ABI.md` | `74c0cd83d2d65f1067cf65433a92ccb39bf8bf51c63c48c765d97f38b73ebd0f` |
| `docs/CURVE-PROPOSAL.md` | `039e77175d037a920f0456998f37c2126a15e2c67c8d50435c469f90950d0719` |
| `docs/OPERATIONS.md` | `1eea222e59c70a4135ce3e238ff16ab2fc5ef2804c850ff6a861b9aeb344c178` |
| `test/fork/ForkFixture.sol` | `3e347daa2b600885701e36f6473e1c46c7703fad95fe553fe9c8b581a3b50838` |
| `test/fork/ForkVoteMarket.t.sol` | `445614f6ee034a5965e97af212a24012a00adb6a0e42f9e2ae1799c557fa7c5b` |

Bytecode equality: for the three product deployables (`CurveGaugeLister`,
`VoteMarketAdapter`, `VotiumAdapter`) the EXECUTABLE (validated-metadata-
stripped) creation and runtime bytecode hashes are IDENTICAL to the
d88d633 baseline under both profiles, from fresh isolated-worktree builds
(method and raw trailer bytes retained). Full-object hashes drift only
inside the validated Solidity metadata trailer because metadata embeds
source keccaks; per the work order this is disclosed and no byte-identical
compiler metadata is claimed from a comment-only diff. Test artifacts
embed product creation-code metadata, so their equivalence rests on the
frozen sources: 43 non-allowlisted files byte-equal to the BINDING.json
baseline and zero executable-token delta on all six admitted Solidity
files. Details: `review/r3docs/BYTECODE-PROOF.md`.

Gate receipts (digest-bound):

| receipt | sha256 |
| --- | --- |
| `review/r3docs/BYTECODE-PROOF.md` | `6fe8081f10d80af9a8355d2c7132b50cb58c7817290fd902e31ceeff0c764a32` |
| `review/r3docs/CONFIRMATION-BRIEF.md` | `5e00629702392534166a1d8cb1f964068aa8a6c3fdda5e7f3bf2a5f87a58a752` |
| `review/r3docs/GATES.md` | `440531c01b1937d4e8a3ab42c750dfae6b1c2c317d1dab5ba6d974396e57fc5f` |
| `review/r3docs/MANIFEST.json` | `6d3ea5ce3dee9191c7fd162d9812d85d6adca2d4e61d706015cb33689fe0f155` |
| `review/r3docs/ROW-HUNK-MAP.md` | `15cee1a5d9028080f5725b52a277a1de3c215f9d616b18b3be4e411431473473` |
| `review/r3docs/artifacts/census_check.py` | `a0c5d8fc38aa9fb7c3c159713ef3315341e7cd6e35e380eac2225303601e11d0` |
| `review/r3docs/artifacts/compare-final.txt` | `cda22b5ab8f1a2bbdfaa36bac8c247761210987eaf80a579ffcc2525e19a9e16` |
| `review/r3docs/artifacts/compare_g0_g2.py` | `13eab8f2411900870fbd96c61ae6f8f4811bc6016b593401cb9ab23cc2936463` |
| `review/r3docs/artifacts/fork-run.log` | `ab3ac8f2bbbc05b59c4241b7e4c96e609669dca02a1374ac82274b80dd15a766` |
| `review/r3docs/artifacts/fork_identity_check.py` | `320379c562a861ec83b6f21f205596c6d8d1d2dabdc31d6bfa50cf19b5c7341d` |
| `review/r3docs/artifacts/hash_artifacts.py` | `219dac354f00b36fee2b2da4a36a7733881402a9d48848b4bbfa30d0833cb5fb` |
| `review/r3docs/artifacts/hashes-base-default.json` | `c75882492cf4327f84b99474303ff02de0f57ba24a3cc9558af30bf113559d55` |
| `review/r3docs/artifacts/hashes-base-fork.json` | `b30067c86c0b567e5d444afe5ae0e20b08813dc7b7da3f27fe30003aeeb55766` |
| `review/r3docs/artifacts/hashes-cand-default.json` | `4f221e656a978292aa29597b8b4a523d44b1ea8469c0fd75ed4e2ca7770a2a20` |
| `review/r3docs/artifacts/hashes-cand-fork.json` | `1bbb8402f67c75453549684d86640ea5a9139f48f2467626c2976ae2f54eafdd` |
| `review/r3docs/artifacts/list-cand-default.txt` | `4643fab6ffe76f0159a44060a21f7f4411e445f92e121ffd045d6413a4827a1f` |
| `review/r3docs/artifacts/list-cand-fork.txt` | `2f9cf3cc0618bb79e95e849ecb83db9c7268aad3ff1b8414968875b50c0cd601` |
| `review/r3docs/artifacts/test-cand-default.json` | `5f7784f0a54c8f222cc04935859b99314b63c1069549fa743a6a9a1e779cf832` |
| `review/r3docs/artifacts/test-cand-unreachable.json` | `21cff64b3d5d6bf595f30cfb9e6efa739499b33f5ee86d8f2b1704a80db8a358` |
| `review/r3docs/artifacts/token_cmp.py` | `b36ff97226c0b269eb99aaaee79f96788d560f0f19b2179d97e5465bb4691629` |

Verdicts recorded natively (exits retained in `review/r3docs/artifacts/`):
`forge fmt --check` exit 0; both-profile fresh builds exit 0; offline
suite 77/77 Success in BOTH the RPC-unset run and the
`MAINNET_RPC_URL=http://127.0.0.1:1` repeat, executed == discovered ==
BINDING census (77 default identities, no duplicates, no skips); pinned
fork `scripts/test-fork.sh` exit 0 with fail-closed preflight at block
26401019 hash `0x55810b079923a14fb97ad548f5024f65530dbc4fb2357a38f41e13b3d27cb6d3`
and executed PASS set == BINDING census (13 fork identities, no skips);
`git diff --check` exit 0. Fork cache mode: fresh same-session build in
the isolated candidate worktree; NO new cold/warm qualification is
claimed (historical cold/warm evidence stays historical).

### Pending approval cells (OPEN — never filled from green gates)

| cell | status |
| --- | --- |
| Owner approval of this shipped candidate, its build/evidence and the digests above | ABSENT ⇒ OPEN (owner/governance release authority owes it; a successful suite is not approval) |
| PAO-AUTH final release/activation binding | SATISFIED-TRACKING (this addendum supplies candidate binding); final owner approval OPEN |
| PAO-FD | SATISFIED-TRACKING; ACTIVATION-OPEN under review/simplify2/FD-BOUND-OBLIGATION.md |
| PAO-CTL | SATISFIED-TRACKING; ACTIVATION-OPEN under review/simplify2/CTL-CALLER-ROLE-GATE.md |
| Independent confirmation pass (work order G5) | OWED; carrier `review/r3docs/CONFIRMATION-BRIEF.md` (r3gate §3.4 paragraph verbatim) |
| All other deployment gates (DEPLOYMENT-PINS §, registry/validator/gauge/kill-role, funded venues, ownership/bindings, float, operations) | independently OPEN |

No completion marker, gate receipt or published path in this package
authorizes deployment, broadcast or unpause.
