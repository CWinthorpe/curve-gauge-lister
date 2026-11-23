# r3gate — authority admission ruling

Status: BOUNDED DOCUMENTATION WORK RELEASED; NO EXECUTABLE CHANGE; NOT ACTIVATION APPROVAL.
Date: 2026-11-24 (+04).
Product candidate: `d88d633c64fde7b3f37e29d846f744747186a688`.

## 1. Authority, evidence and scope

The operator's `plans/R3GATE-BRIEF.md` is binding for this leg. The r3 verified report is an input to this ruling, not a builder authorization. All C01–C16 invariant notes, the rejected/amendment ledger and the adjacent design grades were read. A high model grade, consensus or static equivalence does not establish a need to change code.

Inputs:

- `/home/winny/audits-work/cgl-v1align-cx-r3/audits/complexity-review-verified-2026-11-23.md`
- `/home/winny/audits-work/cgl-v1align-cx-r3/audits/design-grades-2026-11-23.md`

`BINDING.json` binds their actual SHA-256 values, the pre-ruling authorities and obligation carriers, all tracked candidate files, and the full retained file:contract:signature census. All 53 tracked files at the candidate were compared byte-for-byte with the verifier's supplied `source/` snapshot and match. This authenticates the product snapshot against local Git; it does not turn the verifier's static review into an executed test or an activation certificate.

The existing saved simplify2 native inventories were parsed and reconciled to the approved RETAIN_V1/PORT_TRUST inventory: 77 default identities and 13 fork identities, exact sets without duplicates. This is receipt reconciliation, not a fresh Forge run. Historical passing suites and dependency observations retain their original scope.

This authority leg writes only `plans/` and `review/`. The operator's express commit/push instruction is a narrow publication exception to simplify2's untracked-local rule for the named r3gate documents and amended carriers. It does not authorize bulk publication of private receipts, manifests or the audit fleet. No product, test, runner, configuration, dependency, deployment or governance transaction is changed here.

## 2. Item-by-item admission ledger

ADOPT below is limited to the stated branch and the work order. DEFER is not a builder queue. REJECT means the proposal has not met this engagement's real-need gate; it need not be a false technical observation.

| ID | Ruling | One-line reason and admitted boundary |
| --- | --- | --- |
| C01 | DEFER | The FD obligation is already adequately registered; a selected-runtime accounting certificate is genuine activation work, not another simplification or permission to change any accounting guard. |
| C02 | DEFER | The controller obligation is already adequately registered; exact production grants, retained routes and attributed call witnesses await a selected graph, not a speculative controller or fixture rewrite. |
| C03 | ADOPT | Correct the wrong admission citation and unresolved legacy fork authority, resolve the existing invariant map now, and keep its final candidate/approval binding open until release. |
| C04 | DEFER | Independently selectable sensitivity can be useful, but no outstanding accepted gate requires a census change; retain 77/13 and VC-02's honest reached-cell scope pending a separately approved evidence need. |
| C05 | ADOPT | Correct concrete overclaims about recipient credit and campaign creation using comments/prose only; baseline equality is not a recipient-credit or L2-delivery check. |
| C06 | REJECT | The three short preimages agree today; another receipt representation/helper change has no demonstrated material need and the stored-value alternative would reverse the approved skipped-write decision. |
| C07 | ADOPT | Call the existing evidence a token/owner/spender-scoped multiset in comments and the current index; preserve its acceptance set, helper identifiers and diagnostics, with no ordered-cursor rewrite. |
| C08 | REJECT | The second local gas-limit calculation has no intervening interaction and already shares the pricing expression; a tuple refactor fixes no pricing divergence or measured problem. |
| C09 | REJECT | Inlining would reverse the just-admitted stateless predicate factoring without removing a defect or proof obligation; the extra navigation alone does not justify churn. |
| C10 | REJECT | Moving the kill-read control flow gives no functional benefit and reopens the most sensitive observation/rollback boundary; retain the already explicit quarter cadence. |
| C11 | REJECT | Replacing the fixed-input test parser is an optional navigation cut, not a deficient ABI witness; preserve the proven independent comparison rather than churn it for brevity. |
| C12 | REJECT | Inlining the isolated maintenance helper removes one hop but no ambiguity or defect; preserve the visibly separate mandatory and best-effort accounting paths. |
| C13 | ADOPT | Correct the diagnostic contract: false/wrong-length returns reach the local error, noncanonical Boolean words can fail in the decoder, and failed calls are wrapped rather than bubbled. |
| C14 | REJECT | The zero-address branch is redundant but explicit and harmless; deleting one validation line has no material benefit under the no-cosmetic-churn rule. |
| C15 | ADOPT | Qualify payer-facing forfeiture at the claim and explain gross expenditure versus net reward and non-readiness views without changing monetary meanings. |
| C16 | REJECT | The extended interface is already labelled fixture-only and has no production typed-movement caller; relocation is directory hygiene, not a functional or evidence repair. |

The admitted implementation set contains no executable refactor. C03's current authority/index repair is delivered by this leg; the builder owes only its limited publication wording and final-candidate refresh plus C05/C07/C13/C15. The rejected alternatives within an adopted row are not admitted by association.

Source adjudication:

- C04: `test/Settlement.t.sol:2062-2095` is one sequential identity; an early red masks later cells. `plans/V1ALIGN-WITNESSES.md:83-91` already authorizes offset-1 guard-level sensitivity, not near-end mutant coverage. `review/V1ALIGN-CONF2.md:58-72` records that distinction. A green full test does not make every internal cell independently selectable.
- C05: core funding checks source debit plus nonzero attestation at `contracts/CurveGaugeLister.sol:863-875`; both adapters check pull credit then return to their own balance baseline (`VoteMarketAdapter.sol:179-225`, `VotiumAdapter.sol:139-165`). The FD path actually checks both debit and recipient credit at core `:947-955`. VoteMarket's heading and custody comments (`:13-35,220-225`) and `ICampaignRemoteManager.sol:30-42` overstate what their call-site observations prove.
- C06/C08: `VoteMarketAdapter.sol:253-270,325-350` retains the same tuple and one-based ordinal in all three sites; `:188-190,300-315` has no interaction between gas-limit reads. The public zero-message case, positive-amount equality, stride and zero raw member stay intact.
- C07: `test/fork/ForkFixture.sol:1038-1060` matches unused expected values with a bitmap, accepting permutations; `:1116-1166` and `test/fork/ForkVoteMarket.t.sol:106-125` describe a lifecycle more strongly than that matcher proves. Preserve the legitimate Votium `gross-fee` partial-consumption member, all multiplicities, emitter/pair/data-length scope, transfers and final allowances.
- C09/C10/C12: `AdapterCustody.sol:18-45` has explicit stateless predicates and venue-local errors; core `:485-518` already expresses initial/no-due and later-quarter observations; core `:575-576,991-998` separates maintenance from mandatory `:957-978`. No missing guard or failing behavior was established by these rows.
- C11/C14/C16: `test/Adapters.t.sol:900,929,946-1003` has two literal callers and an intact bidirectional allowlist/no-fallback witness; `VotiumAdapter.sol:207-219` rejects zero before venue reads either way; `IERC20Minimal.sol:4-38` already states the production/fixture boundary. Their possible reductions are credited as possible, not necessary.
- C13: `SafeToken.sol:44-51` rejects call failure locally and invokes `abi.decode(ret,(bool))` before its local bad-return error on a 32-byte word. Only comments/documentation are authorized; no uint-word normalization or revert-byte change.
- C15: `docs/CURVE-PROPOSAL.md:7,22` omits qualifications present in `:13,36-38`; `test/fork/ForkFixture.sol:1067-1088` independently distinguishes Votium gross, fee and net. The core ledger and public projections remain exactly those at core `:638-703`.

## 3. Structural evidence-standard amendment — effective now

### 3.1 Two independent statuses

A PRE-ACTIVATION OBLIGATION has (1) a tracking/disclosure status and (2) an activation-proof status. SATISFIED-TRACKING means the candidate-bound carrier identifies the invariant, evidence boundary, remaining deliverables, responsible approval role and activation stop condition. It does not mean the invariant's selected-deployment proof is complete. ACTIVATION-OPEN forbids describing the package as production-ready.

This is an evidence-classification amendment, not a weaker safety standard. The existing S02/CX-FD and S03/CX-CTL deliverables were valid obligation registrations. Their recorded DONE labels do not close deployment. S01/CX-AUTH supplied the evidence framework but C03 has a real, finite citation/resolution defect, which is repaired here rather than excused as a deployment choice.

| Obligation | Carrier | Ruling as of this authority package | Remaining activation condition |
| --- | --- | --- | --- |
| PAO-FD | `review/simplify2/FD-BOUND-OBLIGATION.md` | Existing registration SATISFIED; the r3gate supplement makes the remaining certificate boundaries explicit; ACTIVATION-OPEN. | Approved source/runtime-bound total-delta coverage proof, current caller/cursor/health state, operational contention and stale-refresh treatment, and final candidate evidence approval. |
| PAO-CTL | `review/simplify2/CTL-CALLER-ROLE-GATE.md` | Existing registration SATISFIED; the r3gate supplement resolves witness phases and attribution; ACTIVATION-OPEN. | One viable selected graph, exact grants and route preservation, selected-target positive/negative/absence evidence and authorized deployment/binding/enablement receipts. |
| PAO-AUTH | `review/simplify2/AUTH-EVIDENCE-INDEX.md` | Tracking framework existed; its current citation/resolution defect is CLOSED by C03 in this package; SATISFIED-TRACKING, final release/activation binding OPEN. | Refresh the same index and digests to the final shipped candidate, approved build/evidence and selected deployment; owner approval, not another historical index. |

Thus the current carriers satisfy the present obligation to register and disclose these gates, with C03's local repair applied. They do NOT yet satisfy the actual FD/controller activation certificates. “Modulo deployment” includes the concrete source/composition proof and approvals below, not merely entering addresses or waiting for a date. A selected composition may fail to meet the law; that would be a real blocker, not a paperwork completion.

### 3.2 Precise missing FD evidence

The FD supplement controls the checklist. Required before activation:

1. Identify the selected allocator at a current fixed chain/block/hash/time, preserving the intended destination; record full runtime and verified source revision/content/compiler or equivalent reproducible source binding, including proxies if applicable. Bind the actual week loop, arithmetic, caller/cooldown rule and every relevant cursor-writing entry point. Historical runtime assertion at the regression pin is not this release record.
2. Produce the general coverage composition for the accepted inclusive floored horizon, separately from exact custody and the two postconditions. Account for pre-existing unaccounted custody and existing bucket balances: use the allocator's TOTAL unaccounted delta and independent bucket increments or a runtime-bound general argument, never separately rounded per-source amounts or bookkeeping equalities as coverage proof. Keep independent model boundary/rounding evidence and shorter live-fork observations distinctly labelled.
3. Record actual ordinary-lister eligibility, not the outer caller's privilege; accept the documented possibility of indefinite shared-window postponement. Operations must identify contention/capacity assumptions and escalation, and may not promise a completion time. A pre-submission zero-delta read alone does not establish a lossless stale refresh at execution; establish that premise at execution by separately reviewed operational evidence or do not claim/schedule such a refresh as safe.
4. Make an explicit acceptance decision about any additional independently attributable near-end sensitivity. The existing VC-02 amendment remains sufficient for the current design gate; no new named witness is authorized here. A concrete selected-runtime proof gap may reopen that question under a separate evidence amendment.

The fee, private bound, direct full-remainder transfer, nonzero/nonfuture cursor checks, inclusive equality, mandatory same-transaction call, both postchecks, normal upstream rounding and whole-call rollback are sealed. No recovery/shim/batch/refund/bypass is authorized.

### 3.3 Precise missing controller evidence and phase rule

The CTL supplement controls W1–W8. Select one actual graph with caller, target, required grant/selector, grant authority, retained DAO and seated-wrapper routes, immediate canonical typed readback (including type zero), candidate bindings and evidence phase. Neither the offline DAO-or-lister fixture nor raw-admin fork transfer establishes that graph. An intermediary or altered immutable target requires its own authority review, not automatic admission through C02.

Pre-activation positive/negative paid-admission witnesses may be funded simulations against the selected production composition. The simulated instance must be explicitly unpaused for the negative so the pause/trust/binding gates cannot mask the real `add_gauge` authorization failure. Bind actual caller, target and calldata reachability to that failure as well as revert bytes and complete rollback; the current regression negative at `ForkAdmission.t.sol:42-57` does not itself assert call reachability, unlike the positive at `:79`. This residual is carried into W2/W8, not silently certified or patched speculatively.

Approve W1–W6's selected-composition simulations/reads and W8's unmasked negative before any production unpause. Record real grants and deployment/binding/ownership readbacks before that enablement. The first real paid broadcast occurs only after an explicitly authorized unpause, and is labelled a post-authorization funded trial, not evidence that was already present before unpause. Unpause opens the permissionless lane; there is no invented restricted trial mode. The authority for that first activation must accept this sequencing and separately require real venue/destination probes and the other deployment gates. Simulation is not a broadcast receipt; no first paid success is demanded while the contract is paused.

### 3.4 Mandatory wording for future engagements

Include the following text verbatim in future design/complexity engagements:

> Review the candidate against the admitted authority and its PRE-ACTIVATION OBLIGATION register before counting findings. PAO-FD, PAO-CTL and PAO-AUTH have two statuses: SATISFIED-TRACKING and ACTIVATION-OPEN. An acknowledged, candidate-bound obligation with its missing evidence, approval role and activation stop condition recorded is NOT a confirmed simplification merely because production selection, grants, current-pin observations, a certificate or final approval remain open. Carry it once in a separate activation-obligations section; give no fresh simplification count or design-quality deduction for that unchanged status. This does not certify deployment or waive the obligation. A new confirmed finding must identify a concrete missing or contradictory current invariant, false evidence claim, unsound coverage/composition argument, inaccessible required evidence, stale candidate binding, or proposed activation bypass, and explain the exact delta from the registered obligation with source/cell evidence. A genuinely new defect remains reportable even within an acknowledged obligation. If a mandatory approval/evidence cell is absent at an activation review, activation is HOLD regardless of design convergence. Cosmetic restyling, repeated requests to choose an already-open deployment alternative, and proposals with no material review/safety benefit are not confirmed simplifications. Confirmed status is never implementation authority: every proposed change still requires an itemized ADOPT/DEFER/REJECT ruling and a bounded work order preserving the monetary law, guards and exact approved witness identities.

The register travels with each candidate's owner-approved review package. It need not all be public. Failure to supply the required package is a bounded evidence-access finding, not grounds to invent its content or repeatedly reconstruct a new authority hierarchy. References to pre-r3 DONE labels must carry the tracking-versus-activation distinction.

## 4. Sealed law and builder admission boundary

`plans/R3GATE-WORK-ORDER.md` is the only released builder order. Preserve FEE=10,000e18, QUARTER=2,500e18, four Thursday-grid tranches, frozen endpoints/split, zero-share no-call behavior, current `is_killed()` as sole kill oracle, initial/no-due and later-quarter read cadence, both-leg/all-due atomicity, exact all-FD remainder and accounting, full rollback, admission precedence, locks, token guards/approval sequence, receipt semantics and ABI/layout. Preserve all 77/13 file:contract:signature identities and every assertion; counts alone are insufficient.

All Q01–Q16 remain questions/operational decisions, not extra implementation tickets. Relevant FD/controller/authority questions are carried above. Other deployment gates in `docs/DEPLOYMENT-PINS.md:126-132` remain independently open, including current registry/validator/gauge/kill-role verification, funded venue and destination acceptance, ownership/bindings, float and operations. This ruling neither retires those gates nor answers them with a fork result.

## 5. Overall quality and stopping rule

The post-simplify2 product tree is MATERIALLY CLEAN for this bounded complexity/admission review. C04–C16 establish no admitted executable monetary or guarded-behavior defect. The fresh admitted work corrects evidence/disclosure claims; it is not a redesign. “Materially clean” is neither an exhaustive security certification nor deployment readiness.

Lean convergence may be declared after the admitted package ships and ONE bounded independent confirmation pass verifies the work order's claim corrections, comment-only/executable freeze, manifest/layout and exact census gates. Another full blind round is NOT warranted on this evidence. That confirmation must carry PAO-FD/CTL/AUTH as ACTIVATION-OPEN without counting them again as simplifications.

A failed confirmation remains a named bounded correction/HOLD, not an automatic new broad audit. Reopen a wider round only for a newly demonstrated material invariant defect, changed executable design/dependency composition outside this order, failed safety gate, or a new owner scope decision. Selected-controller/intermediary review and allocator activation certification are separate dependency/activation work, not an endless lean-loop prerequisite. Convergence has not yet been declared: the builder's documentation corrections and that confirmation are still owed.

## 6. Verification of this authority leg

`python3 review/r3gate/verify.py` emits the JSON retained in `review/r3gate/VALIDATION.json`: exact C-row coverage/dispositions, work-order mapping, required structural wording, candidate/input bindings, unchanged product hashes, census lock and document/path consistency. It requires the owner-held authorities, original audit snapshot and local archived Git objects named in BINDING/the fork resolution; a bare public clone is not claimed to contain all inputs. Native status/diff checks and publication verification accompany the final handoff. No fresh product build, offline suite, fork suite, current-pin observation or on-chain action is claimed by this authority-only leg.
