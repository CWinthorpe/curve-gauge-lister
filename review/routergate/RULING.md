# routergate — router-surface fleet admission ruling

Status: ROUTER+FLEET CONVERGED; CAMPAIGN AUDIT OBLIGATIONS COMPLETE; ZERO EXECUTABLE CHANGES; ACTIVATION HOLD.
Date: 2026-11-26 (+04).
Candidate: `72f775e91c0a090364f00ceafe9b55d8bb862922` (`72f775e`).
Authority: `plans/ROUTERGATE-BRIEF.md`. Fleet findings have no implementation authority without this per-item gate.
Input: `/home/winny/audits-work/cgl-router-fleet-r1/audits/contracts-audit-report-verified-2026-11-26.md`.

## 1. Accepted-risk triage — no re-litigation

CONFIRM each mechanism against its actual lineage. These independent re-derivations confirm that the acceptance described an honest product boundary; they are not new remediation tickets. Current report severities are retained. `S1`, `S2`, `S3` below mean `review/secgate/RULING.md`, `review/secgate2/RULING.md`, `review/secgate3/RULING.md`; `L`, `R`, `VA`, `VM` mean `contracts/CurveGaugeLister.sol`, `contracts/GaugeControllerAdmin.sol`, `contracts/adapters/VotiumAdapter.sol`, `contracts/adapters/VoteMarketAdapter.sol`.

| ID | Severity | Registration | Ruling and one-line grounds |
| --- | --- | --- | --- |
| CGL-01 | Medium | REGISTERED RE-DERIVATION | ACCEPT-WITH-REASON — PAO-FD / S1 V-02,V-08 → S2 CGL-V01 → S3 V01 preserves shared-cursor/inter-listing delay without a completion bound, separately from stale coverage; L:897–978 and Operations:75–89 retain mandatory accounting, not a bypass or batching order. |
| CGL-02 | Medium | REGISTERED RE-DERIVATION | ACCEPT-WITH-REASON — S1 V-03/P2 → S2 CGL-V02 → S3 V03/P2 confirmation accepts whole-remainder retention from required frozen ingress or immutable FD failure; L:424–431,530–544,853–875,897–967 and Operations:43–49,63,89 preserve backing, not availability or an exit. |
| CGL-03 | Medium | REGISTERED RE-DERIVATION | ACCEPT-WITH-REASON — S1 V-05/P3 → S2 CGL-V03 → S3 V04/P3 confirmation expressly covers successful funded ingress without destination creation; VM:198–232,259–277 and L:530–544 retire local liability without acknowledgement/recredit, distinct from post-creation residual loss. |
| CGL-04 | Medium | REGISTERED RE-DERIVATION | ACCEPT-WITH-REASON — S1 V-06 carries VoteMarket residuals; separately S2 CGL-V05/P5 carries Votium unprocessed incentives, with P5 confirmed by S3:104–111; VA:149–162,193–242 and VM:198–220,364–429 expose neither venue lifecycle route, and local ownership transfers confer no such upstream identity. |
| CGL-08 | Low | REGISTERED RE-DERIVATION | ACCEPT-WITH-REASON — S1 V-04/P2 → S2 CGL-V04 → S3 V02/P2 confirmation accepts execution-time defaults without payer-bound terms; L:406–438,592–605 and Operations:55 disclose the admission race; the different historical R17 release-settings rejection is not its lineage. |
| CGL-09 | Low | REGISTERED RE-DERIVATION | ACCEPT-WITH-REASON — S1 V-07/P3 and V-04's live-terms boundary → S3 V05/I01 retain separate-manager affordability and mutable venue terms on old routes; VA:141–162,199–239, VM:191–220,399–426 and Operations:35–41,108–112 supply no frozen terms, cap, override or recovery promise. |

The exact prior decisions are S1:98–108, S2:21–77 and S3:26–57,94–123. CGL-04's current Medium is preserved even though S2's narrower CGL-V05 was Low; likewise the later fleet's severity choices do not rewrite earlier reports. No historical V-M02 acceptance is stretched to cover missing destination creation, Votium depositor rights or gas affordability.

## 2. Fresh finding gates

| ID | Severity | Registration | Ruling and one-line grounds |
| --- | --- | --- | --- |
| CGL-05 | Low | REGISTERED-DESIGN + DISCLOSURE | ACCEPT-WITH-REASON — the owner-authorized, two-step rotation intentionally transfers the owner-only free lane while R's grant remains keyed to L; disclose and govern that coupling below; REJECT independent privilege plumbing absent a new role-separation requirement. |
| CGL-06 | Low | REGISTERED-GOVERNANCE / ACTIVATION-OPEN | ACCEPT-WITH-REASON — successor operability is an existing exact-successor approval/rehearsal gate, not a property established by an address postcheck; retain permanent retirement and the no-reseat prohibition; REJECT a new on-chain successor protocol. |
| CGL-07 | Low | REGISTERED-READINESS / ACTIVATION-OPEN | ACCEPT-WITH-REASON — public FD eligibility is already required before activation and settlement; mandatory runtime accounting fails closed but does not guarantee liveness; REJECT the construction-time fail-faster getter check under real need. |

### CGL-05 — ownership is the free-lane authority

Premise CONFIRMED. L:450–471 permits its current owner to register with no escrow, no validator/readiness requirement and a supplied controller-valid initial weight, including while paused. L:609–623 implements the specified current-owner proposal / pending-owner acceptance. Both admission lanes reach R from L through L:833–836; R:106–109,138–160 checks the address-keyed grant and incumbency, not the outer owner. A completed rotation therefore carries the free-lane capability without a second router grant. It does not convey D-only router grant, execute or handback powers.

The intended owner is the DAO organization/executor D, not an independent configuration-only operator (`docs/DEPLOYMENT-PINS.md:9,23,60–67`; `docs/OPERATIONS.md:11–15`). The grant deliberately includes controller-valid supplied weights; paid zero is L's lane rule, not an R-wide clamp (`review/routerplan/RULING.md:21–23`). Rotation is the approved two-step ownership mechanism, not an outsider bypass. Splitting configuration ownership from free admission, hard-pinning L's owner to R.dao(), or automatically revoking/regranting on rotation would change that design and its cross-contract authority assumptions. No such distinct operational-owner requirement or unauthorized path is established. Those executable alternatives fail real need; fleet cost reinforces, but does not substitute for, that judgment.

Operative disclosure, registered now: transferring L ownership also transfers its privileged fee-free, validator-independent, supplied-weight registration lane while L remains granted at an active incumbent R. Two-step acceptance proves control of the nominated owner, not continued DAO identity. Treat L.owner, R.dao and R.isAdder(L) as one governance change-control decision. Before a transfer away from the approved D, D must revoke L's grant unless the resulting delegation is explicitly approved; core pause is insufficient because the free lane remains open. Re-read owner/pending owner, grant, router lifecycle/incumbency and approved caller routes at the change. Revocation cannot undo registrations already committed; it stops both future L lanes without changing existing escrow settlement. Changing L's owner does not rotate R's immutable D; an executor replacement needs the separately approved controller handback/replacement route.

This ruling supplies the disclosure and files it in the existing PAO-AUTH carrier. It creates no separate public-product-documentation order, role split, monitor software or deferred executable ticket.

### CGL-06 — trusted successor selection, not a new handshake

Premise CONFIRMED, including potentially permanent loss of controller administration. R:247–277 excludes zero/current R/C, requires a fresh matching nomination, verifies the resulting administrator address and permanently retires on successful apply. Those checks do not establish the successor's callable authority. Both typed and mediated execute paths share them (R:191–215,223–232); all mutators reject a retired R (R:111–117). A later incumbent can seat an old retired router directly at C, outside this router's state machine; weakening retirement would not be an acceptable repair.

The control already exists: `plans/ROUTERPLAN-DEPLOYMENT.md:11–19,64–79` requires pre-apply isolated rehearsal, exact selected bytecode/governance bindings and successor approval independently establishing callable governance, with L and retired routers excluded. `docs/OPERATIONS.md:17–26` requires the handback rehearsal and tooling refusal of reseating, explicitly discloses stranding and no guaranteed recovery; `docs/DEPLOYMENT-PINS.md:73–84` carries retained administration/handback and selected-graph approval. These are obligations, not claims that production rehearsals or approvals have occurred.

Bind the exact successor and its real authorization route before approving/executing its commit/apply: prove subsequent additions, type/weight administration and onward ownership transfer remain callable by the approved authority. The existing handback-to-D rehearsal is not evidence for a different successor; apply the existing selected-successor gate to that actual nomination. A failed or missing proof is HOLD; after success, read back actual administration and enforce permanent no-reseat. Source/runtime presence, a self-reported interface, an acceptance call or address equality alone cannot establish these governance properties. A new handshake/allowlist would introduce a successor protocol, restrict the approved generic handback and still not police future direct C transfers. REJECT that executable change. Register the existing pre-activation AND continuing change-control gate; preserve the no-revival invariant and the disclosed irreversible misconfiguration risk.

### CGL-07 — constructor success is not FD eligibility

Premise CONFIRMED. L:279–295 checks distributor code/token/killed status, not public-checkpoint permission; L:585–588 does not add such a check at unpause. The saved `CurveFeeDistribution.vy:129–140` permits the ordinary caller only with `can_checkpoint_token` and strict cooldown, independently of the outer caller's privilege. The flag is mutable. L:947–967 requires exact two-sided custody, mandatory accounting and both postconditions; rejection rolls back the full confiscation, including prior provisional work.

Do not overclaim that bad eligibility prevents paid fees: an incorrectly enabled L can admit paid escrow with public checkpointing disabled. That creates backed-but-unavailable killed-listing liabilities until legitimate upstream restoration, potentially indefinitely under the accepted FD-retention boundary. The approved rollout must prevent that configuration: `docs/DEPLOYMENT-PINS.md:142,146` expressly requires the flag and ordinary-lister eligibility; `docs/OPERATIONS.md:75–89` requires pre-seizure checks, ongoing polling, contention handling and legitimate restoration. The core starts paused, so these checks can be completed before paid exposure, but the checklist is not an on-chain admission guard.

A constructor getter would detect one bad deployment-time value, not the chosen identity, later flag changes, coverage, cooldown or current operability. It would add interface/bytecode and regression scope without supplying a lifetime guarantee. Preserve the existing fail-closed runtime accounting and require current ordinary-lister public eligibility before opening admission and at the existing operational cadence. REJECT executable fail-faster hardening; the existing activation checklist plus this explicit registration is the honest ceiling. No accounting weakening, alternative recipient or blanket liveness claim is admitted.

## 3. Informational rows — complete disposition

`AUTH` means `review/simplify2/AUTH-EVIDENCE-INDEX.md`. REGISTERED can identify an existing semantic/checklist rule without claiming a previously identical finding title.

| ID | Severity | Registration | Ruling and one-line grounds |
| --- | --- | --- | --- |
| CGL-I01 | Informational | REGISTERED / ACTIVATION-OPEN | ACCEPT-WITH-REASON — exact immutable D identity and callable governance belong to the existing selected-instance gate, not a reusable constructor code check; R:44–47,99–109,123–129, ABI:113 and Deployment-Pins:38–48 require literal/artifact/readback/route binding; no hardcode or new getter is admitted. |
| CGL-I02 | Informational | REGISTERED | ACCEPT-WITH-REASON — AUTH O-07/O-08 and VA:108–124, VM:152–168, L:352–364,417–436 already make binding write-once and reject positive-share misbinding before fee/liability effects; replace the instance before enablement, never add rebind. |
| CGL-I03 | Informational | REGISTERED | ACCEPT-WITH-REASON — AUTH O-04 and Deployment-Pins:118–120 distinguish immutable pointer from mutable validator policy; L:378–385 rejects new paid admission, not old settlement; retain existing predicate/role monitoring. |
| CGL-I04 | Informational | REGISTERED | ACCEPT-WITH-REASON — S2:85 and routerplan:22 separately cover lister/adapter donations, committed nonwithdrawable VM float and forced router balances; R:191–215 adds no rescue path and L:432–436 creates no donation credit; no sweep or recovery work. |
| CGL-I05 | Informational | REGISTERED / NO-ACTION | ACCEPT-WITH-REASON — README:55–66 already mandates a clean build with `--extra-output storageLayout`; RouterHarness:249–253 consumes that artifact input, so absent layout is an evidence/setup failure, not a canonical-build defect or new code ticket. |
| CGL-I06 | Informational | REGISTERED | ACCEPT-WITH-REASON — r3gate C13 → S2:90 → S3:86 and SafeToken:52–61 / ABI:89–96 already preserve fail-closed noncanonical-Boolean decoder diagnostics; no error normalization. |
| CGL-I07 | Informational | REGISTERED | ACCEPT-WITH-REASON — S1 I-07/P4 confirmed by S3:103 and ABI:79 expressly cover decoded non-18 decimals using BadAdmissionConfig at L:285; diagnose by context, no selector change. |
| CGL-I08 | Informational | REGISTERED / NO-ACTION | ACCEPT-WITH-REASON — Operations:57 and S2:67 retain execution-time Votium rounds; VA:133–161 and VM:179–220,259–277 show maturity is a local schedule/key, not historical execution or a requested destination start; register the payload clarification without inventing an exact earlier ruling on that omission. |

CGL-I01 approval condition: independently bind chain 1, C `0x2F50D538606Fa9EDD2B11E2446BEb18C9D5846bB` and D `0x40907540d8a6C65c637785e8f8B742ae6b0b9968` to the actual constructor, complete runtime with embedded immutables, getter readbacks and current Voting/Agent/Kernel/ACL route before the seating vote becomes executable (`plans/ROUTERPLAN-DEPLOYMENT.md:11–19`; Operations:19). A well-formed address or code check does not establish the approved executor. Reject a mismatched instance before seating; a reusable ABI accepting EOAs does not authorize an EOA substitution in this deployment. The flag has no setter and the deployer has no correction privilege. This is already PAO-CTL/PAO-AUTH activation work, not an additional builder order.

The report's gas/style notes establish no material need: retain bounded deduplication, checked zero-first approvals and intentional adapter ownership diagnostics. No cosmetic refactor is admitted.

## 4. Candidate, history and evidence boundary

The fleet snapshot matches all 60 candidate product/test/document/configuration paths. The other five tracked paths are ROUTERCONF reports, not supplied in `source/`. Every candidate tracked byte is bound in BINDING. Against the pre-router security candidate `3ba03f35d66ca5172c4c417335804f0a6f4ed07d`, the only `contracts/` delta is addition of `contracts/GaugeControllerAdmin.sol`; the lister and both venue adapters are byte-identical, not newly repaired by this ruling.

S3:94–123 already completed P1–P4 and P5 D1–D4/O1–O4, including the carried secgate G4 / secgate2 G3 bounded confirmation. Its local ruling/binding/validation are authenticated against ancestor commit `cbb485aa2bbda41228d764aeb90c86fc516da18f`; no historical OPEN clause revives those completed audit orders. ROUTERCONF5:3–20,171–176 closes the final router conformance residuals at `60956b62879916081325ef0a66c502d3be85f913`. Candidate 72f775e is its direct report-only descendant, changing only `review/ROUTERCONF5.md`.

The reports' severity tables are parsed separately; accepted status does not erase severity:

| Engagement | Candidate | Critical | High | Medium | Low | Informational |
| --- | --- | --- | --- | --- | --- | --- |
| cgl-sec-r1 | d224b12ec2f62e3ef877d682ad0b6968d9cc3e95 | 0 | 1 conditional | 4 | 3 | 7 |
| cgl-sec-r2 | 4a442e63421a89b04e902f4e709613b8234f16c5 | 0 | 0 | 3 | 2 | 11 |
| cgl-sec-r3 | 3ba03f35d66ca5172c4c417335804f0a6f4ed07d | 0 | 0 | 1 | 5 | 14 |
| cgl-router-fleet-r1 | 72f775e91c0a090364f00ceafe9b55d8bb862922 | 0 | 0 | 4 | 5 | 8 |

The FINAL TWO chronological blind fleet rounds are cgl-sec-r3 and cgl-router-fleet-r1, each with zero Critical/High. Together they cover the lister/venues and then the full composition including the router. This is the router's FIRST blind round, not two router rounds or two reviews of the same full executable tree. Pre-router security convergence separately used sec-r2/sec-r3. Preserve sec-r1's conditional High and its prohibition of L as raw admin; do not rewrite history to claim all rounds were High-free. The reports describe eight-model static engagements; no statistical-independence or universal-unanimity claim is made.

The older reports moved from `audits-work/cgl-sec-r{1,2,3}/audits/` to `/home/winny/audits-archive/cgl-sec-r{1,2,3}-2026-11-24/audits/`; their source snapshots remain under the original `audits-work/cgl-sec-r{1,2,3}/source/` paths. BINDING records current resolvable paths and verifies report/snapshot hashes against S3's historical binding and actual Git candidates. Old bindings are not rewritten. The current fleet report remains at the input path above.

ROUTERCONF5's 27 receipt hashes and six authority inputs are checked. Its independent execution was I03 and F05 only, with fresh discovery of the exact 103 default / 25 fork identities; it did not independently rerun the full suites. Separately, routerfix6's retained G2/G3 full-default and G5/G6 cold/warm-fork stdout are reparsed against baseline-plus-ledger identities: 103/103 and 25/25, zero failures/skips/duplicates. Their saved sidecars bind candidate 60956b6 and its tree; raw Forge text alone does not identify Git. These are authenticated HISTORICAL results, not executions by routergate. Prior accepted gates remain credited; no extra census or new audit matrix is created.

This leg executes authority-artifact verification, not Solidity builds/tests, a new fleet, a current-chain query, deployment certification or a broadcast. Dependency snapshots establish source semantics, not today's deployed permissions or readiness. Hash equality authenticates inputs, not the semantic correctness of a ruling. No existing production instance, successful downstream outcome or approval is inferred.

## 5. Convergence and residual posture

ROUTER+FLEET CONVERGED at 72f775e.

The campaign's audit obligations are complete. Router conformance is closed; the supplied fleet's nine findings and eight informational rows all have an individual authority disposition. The six repeated risks are registered; the fresh governance/design/readiness observations are accepted with the disclosures and existing gates above; proposed executable hardening is gate-rejected. There is no outstanding audit builder order, public-product-documentation correction, new operational implementation, test/census change or further blind round owed for this candidate. This is campaign audit closure, not an exhaustive absence-of-defects guarantee, owner release approval or activation closure.

Residual posture:

- Unspent escrow is backed under the reviewed accounting model but may remain unavailable indefinitely through shared FD windows, coverage/permission/health failure, frozen required ingress failure or unreadable current gauge flags. There is no completion bound, partial exit, refund, migration, alternate FD or kill-for-repair policy.
- Paid admission uses execution-time governance defaults without payer commitment; stored endpoints/split do not freeze live manager/upstream terms. Governance intentionally controls the weighted fee-free lane, and L ownership rotation carries it unless the router grant is removed.
- Spent venue shares are final gross local expenditure without guaranteed destination creation, delivery, processing, voter claims or project-controlled residual recovery. VoteMarket and Votium limitations remain distinct; reconciliation continues after local exhaustion but cannot restore escrow. Do not double-count retained and spent maxima as losses of the same funds.
- Correct DAO identity, live callable governance, successor selection, no reseating of retired routers, reachable adapter management, funding and ongoing dependency verification remain trusted controls. An unusable successor or wrong authority pin can strand control without a protocol-local remedy. Forced funds and committed float have no rescue entitlement.

| ACTIVATION-OPEN cell | Required evidence and approval role | Status |
| --- | --- | --- |
| PAO-FD | Deployment operator binds current selected source/runtime and general TOTAL-unaccounted-delta floored coverage, exact custody/postchecks; keeper/FD liaison supplies ordinary-L public eligibility, current cursor/cooldown/health, contention/capacity and execution-time zero-delta refresh evidence; release authority approves. | SATISFIED-TRACKING / ACTIVATION-OPEN; no certificate closed here. |
| PAO-CTL | Source implementation/conformance/blind-review prerequisite is now COMPLETE at this candidate; deployment operator/governance still owe actual R/L instances, literal D/immutable/runtime/ACL bindings, selected-production-bytecode W1–W6/W8 simulations, exact installation/grants, queued-proposal continuity, independently verified successor/handback routes and W7 authorization/readbacks. L as raw admin and retired-R reseating remain prohibited. | SATISFIED-TRACKING / ACTIVATION-OPEN; no selected deployment or installation approval. |
| PAO-AUTH | Existing index binds this candidate, completed audit orders, accepted risks and immutable historical evidence; owner/release authority must approve the actual final artifact package, deployment, ownership/bindings/grants and risk acceptance, including ownership/free-lane coupling. | SATISFIED-TRACKING / ACTIVATION-OPEN; filing is not approval. |
| Current dependencies and venue readiness | Deployment operator, adapter managers and keepers verify current token/registry/validator/factory/gauge/kill authority, positive-share funded venue probes, Votium processing/distributor policy, VoteMarket whitelist/periods/bridge/destination delivery and current FD eligibility. | OPEN; no current operational certificate supplied. |
| Approvals, funding and staffing | Owner/governance explicitly accepts retention/delivery/recovery/control limits; assigns actual deployment/config/adapter/keeper/governance/FD-liaison roles and approves reachable management, gas/value envelope and committed-float/backlog budget. | OPEN; runbooks and audit acceptance are not appointments or operational approvals. |
| Post-authorization funded trial | Approve selected simulations and all pre-enable gates; complete actual authorized installation/grants/bindings/ownership readbacks; explicitly authorize and verify unpause; then retain the first real paid listing and downstream evidence as rollout evidence. | OPEN; unpause opens permissionless admission, not a restricted trial. |

Missing a mandatory activation cell remains HOLD. No deployment, signing, governance transaction, controller transfer, grant, unpause, recovery or movement of escrow is authorized here. Future executive-owner changes and handbacks retain the same pre-action verification discipline after activation.

Under the operator's convergence law, ANY later admitted executable change requires a bounded work order, implementation/conformance gates and one further blind router/security round AFTER shipment before renewed convergence. None is adopted now. A changed premise, material new defect, contradictory guarantee, false evidence, inaccessible/stale binding, bypass or failed mandatory activation cell remains reportable. Mere re-derivation of these registered limits does not reopen the campaign.

## 6. Filing, preservation and verification

Append this candidate/disposition/convergence bridge only to the SAME `review/simplify2/AUTH-EVIDENCE-INDEX.md`; preserve its complete 65,538-byte prior prefix. PAO-FD and PAO-CTL remain byte-identical. Earlier implementation/review-OPEN descriptions are advanced only for the candidate-specific completed audit prerequisite, never silently converted into selected-instance certificates. No parallel carrier is created.

The requested commit/push is a narrow publication exception for `review/routergate/RULING.md`, `review/routergate/BINDING.json`, `review/routergate/verify.py` and `review/routergate/VALIDATION.json`. Full fleets, historical manifests/receipts and the amended PAO index remain owner-held/ignored/producible on demand. No bulk force-add, alteration of sealed earlier records or product-file change is authorized. This public ruling contains the operative new disclosure and stop conditions itself; it does not depend on a publicly browsable private carrier.

`python3 review/routergate/verify.py` verifies candidate/snapshot equality, historical report severity tables and relocation, archived S3 authority, conformance receipt integrity, exact saved discovery/PASS identity sets, all seventeen dispositions, input/package digests, frozen product bytes, carrier-prefix preservation and publication scope. `--capture` emits an initial binding for deliberate sealing only; normal verification never regenerates accepted digests. VALIDATION contains the actual default verifier result. Reproduction requires the named owner-held historical inputs and archived Git objects; a public clone alone is not self-contained. Full creation/runtime bytes including metadata are expected unchanged under identical compilation inputs; no fresh compiled-byte comparison is claimed by this authority-only leg.
