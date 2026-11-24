# secgate — bounded builder work order

Authority: `review/secgate/RULING.md` against `d224b12ec2f62e3ef877d682ad0b6968d9cc3e95` and its authority-only secgate child.
Status: RELEASED FOR DOCUMENTATION ONLY; NO EXECUTABLE CHANGE; NOT ACTIVATION APPROVAL.

The fleet/verifier is not an implementation queue. Only ADOPT rows V-01/V-03/V-04/V-05/V-07/I-05/I-07 are released below. ACCEPT-WITH-REASON rows require preservation, not extra changes; I-02 and the executable alternatives rejected within ADOPT rows are not admitted. There are no deferred code tickets, new witnesses, wrapper implementation or deployment transactions in this order.

## P1 — V-01 controller composition prohibition

Allowed public sites:

- `docs/DEPLOYMENT-PINS.md`: Intended constructor dependencies controller row and its explanatory paragraph; Production controller composition; the matching controller condition under Deployment gates still open.
- `docs/OPERATIONS.md`: Roles and deployment, especially step 3 and the controller prerequisite in step 5.
- `docs/CURVE-PROPOSAL.md`: Specification and rollout conditions controller bullet only.
- `README.md`: Status and evidence / Layout publication sentences only, to account truthfully for the newly published secgate authority exception while the historical r3gate/PAO carriers and full receipt package remain owner-held.

Required edits:

1. Separate the canonical raw registry/regression reference `0x2F50D538606Fa9EDD2B11E2446BEb18C9D5846bB` from the UNSELECTED production `controller_` endpoint. The raw reference is not an approved direct constructor value. Do not insert a guessed GaugeAdder/wrapper address or silently change any literal pin.
2. State that the unchanged lister MUST NOT become raw controller admin, even temporarily: existing raw admin retention prevents its direct additions; raw admin transfer to this lister strands callable controller administration and both incumbent-admin-only ownership-transfer steps. Lister-owner transfer cannot repair that. The DAO-free lane has the same inner-caller constraint.
3. State that the raw-admin fork fixture is a regression simulation ONLY and is invalid as a production integration template. Its historical S03 “production composition” label and successful additions do not prove retained governance. Preserve the useful regression pin, assertions and passing receipt scope without claiming handback/retained-route proof.
4. Permit only a separately selected and approved authority-preserving GaugeAdder/wrapper/executor composition for this core and named raw controller. A name/whitelist/narrow shim is not proof. Its core-facing endpoint must implement the exact three `IListingController` operations, synchronously forward the correct gauge/type/weight, provide canonical count/type/absence semantics including type zero, and preserve same-transaction add/readback and rollback. The last raw-controller caller must have real authority.
5. Carry PAO-CTL's tightened W1–W8: selected-current-pin source/runtime/role graph; paid AND DAO-free positives; unmasked attributed authorization negative; existing DAO and seated-wrapper routes; reachable type/weight administration and both ownership-transfer steps through actual authorized callable routes. A raw-admin three-method shim without those retained routes is prohibited. No destructive live governance action is demanded merely as a test.
6. Keep selected-composition simulation approval before production enablement, actual authorized grants/bindings/ownership readbacks before unpause, and first paid broadcast after authorized unpause. Unpause opens the permissionless lane. Independent FD/venue/operations gates still apply. If no compatible graph is approved, remain paused and do not claim a production DAO-free integration either.

Acceptance: no public passage names the raw address as the solved production immutable target; no fork/impersonation/admin-seat inference supplies production authority; the unknown actual endpoint is explicit. README identifies only the new secgate ruling/binding/work order/validation exception as published, never the historical package or owner approval. Correcting the docs does NOT close V-01's activation blocker. No Solidity or fixture-comment edit is authorized; the public explanation expressly bounds the retained historical fixture label.

## P2 — V-03/V-04 payer-facing limits

Allowed public sites: existing economic/limits paragraphs in `docs/CURVE-PROPOSAL.md`; Venue guarantee lifetimes, Admission and ordinary settlement, and Mandatory FD safe-accounting sections of `docs/OPERATIONS.md`. Keep one explanation per context, not a parallel monetary model.

V-03 required meaning:

- Permanent failure/incompatibility of any required immutable ingress may leave the ENTIRE affected remaining balance reserved indefinitely, including the healthy leg under atomic settlement.
- A legitimate gauge kill is venue-free, not a guaranteed terminal exit: permanent unusability of the immutable FeeDistributor can also leave the entire outstanding remainder reserved indefinitely. No refund, migration, alternate FD, healthy-leg-only payout, timeout exit, owner withdrawal or kill-for-repair policy exists.
- Retention preserves backing but not availability; polling and new prospective defaults do not repair old liabilities. Keep unresolved liabilities visible and pause new paid admission on persistent incompatibility; emergency protective kills must remain independent of settlement.

V-04 required meaning, including at the payer's initial escrow/snapshot explanation:

- `listGauge` uses owner-selected defaults AT EXECUTION. The payer supplies no expected endpoints/split/hash/version/deadline; defaults may change after inspection or submission but before execution. An approval/simulation/off-chain notification is not an atomic commitment to reviewed terms.
- Only the endpoints/split recorded by successful admission are frozen against later core-owner replacement. Live adapter settings and upstream venue policies remain mutable for those records.
- Code presence, `rewardToken` and `lister` compatibility checks do not independently authenticate venue identity. Reviewed deployment/configuration pins and governance remain a trust dependency, and a payer who requires enforceable pre-submission terms is not offered that guarantee by this product.

Acceptance: neither “snapshotted” nor “cannot redirect existing escrow” is presented as payer consent to a previously inspected configuration; no perpetual availability or escape guarantee is invented. The new disclosure retains all current fixed monetary amounts, Thursday maturities, current-flag oracle and custody semantics. No expected-config overload/version/timelock/allowlist or settlement-resolution code is authorized.

## P3 — V-05/V-07 operational acceptance and controls

Allowed public sites: `docs/OPERATIONS.md` Roles and deployment, Admission and ordinary settlement, Adapter arithmetic and one-way float, VoteMarket residuals and delivery limits, Review and change boundary; `docs/CURVE-PROPOSAL.md` existing VoteMarket limit bullet only for the V-05 consequence. Do not rewrite the already adequate V-06 residual policy.

V-05 required disclosure and operating rule:

- Successful funded L1 ingress retires the local share even if the message never creates/funds any live destination campaign. The entire submitted VoteMarket share may be unavailable for intended distribution with no restored local liability. This is distinct from both synchronous ingress failure (whole-call rollback) and post-creation residual forfeiture.
- The settlement keeper records each funded source transaction/log, adapter-domain receipt, gauge, scheduled epoch and amount, then correlates the actual messenger identity (where established by source evidence) and destination-chain campaign/outcome. Distinguish pending/unknown, observed failure and evidenced delivery. No fabricated destination ID or inference from L1 success, adapter address equality or elapsed time.
- Reconcile the outstanding submission list at the existing at-least-hourly pending-work cadence and on settlement, escalate missing/failed delivery to the governance/venue liaison and disclose unresolved spent amounts. This is a staffing/runbook duty, not authorization to build new monitoring software or promise an SLA.
- Do not reverse `released`, restore `remaining`, issue a compensating local credit or resubmit the already-spent tranche. No recovery/retry/acknowledgement API is added. A venue-supported intervention, if any, needs separately authenticated authority and evidence; its existence/success is not assumed.
- Positive-share activation requires current selected-destination/bridge checks and real funded probe evidence, plus explicit governance approval of the disclosed full-share non-delivery and residual-loss limits. The current gate accepts the product boundary, not any chosen venue's readiness. A zero share may be an independently approved prospective deployment choice, not an instruction to change the split here or redirect old records.

V-07 required operating rule:

- Name and verify the actual separate adapter owner/manager and its authorized response/handoff path. The core owner has no inherent repair power over a separately owned adapter. Loss/unavailability of that role is a continued availability risk; do not promise that an owner transfer recovers inaccessible authority.
- Before positive-share activation, the deployment operator and adapter manager must present a gas/value envelope and committed-float/backlog funding policy for release-authority approval, based on the actual messenger/destination requirements. Record the selected numerical values in the selected-deployment package, not invented defaults in this documentation task. Missing/unaffordable/unapproved policy means no activation.
- Before each gas/exclusion update or settlement, account for current settings, actual bridge requirements, pending old listing obligations, mixed-leg/all-due rollback and the backlog's aggregate message budget. `ethDeficit(amount>0)` quotes one configured message, not the backlog or delivery readiness. Simulate the proposed settings against those obligations, verify available/committed float, and read back the authorized update. Existing arithmetic bounds remain exactly unchanged.
- Excessive valid settings can stop old routes; only an authorized correction or sufficient committed funding may restore them. Escalate and pause NEW paid admissions if correction/funding is unavailable; pausing does not repair pending records. Do not silently underfund messages or label unfunded quarters released. No arbitrary on-chain affordability cap, manager override or float withdrawal is admitted.

Review-boundary paragraph: retain historical-candidate limits; identify these as current no-bounty accepted product boundaries subject to selected-deployment evidence/approval, not an unqualified import of all prior bounty risk labels. V-M02 is the residual lineage, not the authority for V-05 or V-07. Public prose must be self-contained and may refer to the owner-held candidate package without requiring an unpublished path to be browsable.

Acceptance: source ingress, destination delivery and residual recovery remain three distinct facts; pending-route gas control is assigned to the role that actually has power; no operational practice is represented as an enforced on-chain guarantee.

## P4 — I-05/I-07 cheap ABI-reader clarifications

File: `docs/ABI.md` only, beside Monetary views and Errors/Constructor respectively.

- I-05: `releasable` returns zero for a non-Active record without consulting the gauge, or for an Active gauge whose readable kill flag is true; an Active gauge flag read/decode failure propagates as a failed view, not zero. A scheduler must not silently interpret that failure as no amount due, a kill or executable readiness. No scheduler implementation is requested.
- I-07: `BadAdmissionConfig()` can mean a successfully decoded constructor `decimals()` value other than 18, as well as invalid registry/maxCoins configuration. Distinguish by call context; a dependency call/decode failure need not produce that local error. Do not rename/add errors or imply that all constructor failures share this diagnostic.

No other informational row needs an edit. I-01 telemetry is already disclosed; I-02 zero-first approvals stay; I-03 raw compatibility storage is not an API; I-04 zero-share identity is unused. I-06 stays fixture-only: production deployable allowlist is exactly `CurveGaugeLister`, `VotiumAdapter`, `VoteMarketAdapter`, with independent source/runtime pins, not every artifact compiled under `contracts/`. No mock relocation, import, event, selector or test change.

## Exact allowlist and publication/custody

Product-side edits are PROSE ONLY in these five files:

- `docs/DEPLOYMENT-PINS.md` — P1 only.
- `docs/OPERATIONS.md` — P1/P2/P3 only.
- `docs/CURVE-PROPOSAL.md` — the corresponding P1/P2/P3 passages only.
- `docs/ABI.md` — P4 only.
- `README.md` — P1 selective-publication qualification only.

Freeze every other product path byte-for-byte to d224b12, including all Solidity comments, tests, test names, imports, manifests, `foundry.toml`, `scripts/test-fork.sh` and literal pins. No broad reformat, typo sweep, duplicated summary or housekeeping by association. No raw controller pin is replaced with a guessed deployment endpoint; its documentary role changes, not its value.

Implement as one row-mapped documentation commit (`secdocs: clarify controller gate and accepted settlement limits`), plus an evidence-only child if needed. The builder must not rewrite this ruling, its work order, BINDING or historical approvals to fit work. New owner-held receipts go under `review/secdocs/`. Append a final candidate/receipt/approval-status bridge to the SAME owner-held `review/simplify2/AUTH-EVIDENCE-INDEX.md`, preserving its previous bytes and the secgate supplement. Do not republish that carrier, bulk receipts or other private files by association; complete evidence remains owner-held. The new secgate ruling/binding/verifier/validation and this work order are the sole new authority-leg publication exception.

The authority leg has already amended PAO-CTL/FD/AUTH. Do not recreate those carriers, broaden W1–W8, add a second limitation register, or mark any activation cell complete. Copy the §6 future-engagement paragraph from the secgate ruling verbatim into the bounded confirmation brief.

## Census, bytecode and mandatory verification

Census stays exactly the full sets in `review/secgate/BINDING.json`: default 77, fork 13. No additions/removals/renames/skips or fixture/witness changes. PAO-CTL's selected-composition evidence cells are NOT new native test identities or authority to rewrite the raw-target regression.

G0 — Bind the base and actual changed paths. Require all non-allowlisted candidate files byte-identical to d224b12; compare the entire contracts/test/fork/scripts/configuration input set, not just the three deployables. Record native `git diff --check`; manually map each prose hunk to one admitted row and source truth. Stop on unrelated changes or any modified executable/comment/test input.

G1 — In isolated exact baseline and final candidate archives with fresh outputs, use the same installed compiler/toolchain and unchanged profile settings: Solidity 0.8.30, optimizer200, no viaIR, default Paris and fork Cancun/chain1. Run `forge fmt --check`, and `forge build --offline --sizes --extra-output storageLayout` under both profiles. Retain actual stdout/stderr/native exits and warnings. No compiler-policy change or dependency installation is authorized to make this pass.

G2 — Compare the full decoded creation AND runtime artifact objects for all three product deployables to the same-profile baseline, INCLUDING metadata; all must be byte-identical, not merely metadata-stripped equal. Compare full ABI/methodIdentifiers/recursive layout to the bound manifest and baseline; check unchanged size/initcode limits. Bind compiler and source digests. A metadata delta is unexpected in this prose-only order and is a STOP, not the last gate's comment exception. Different future deployment immutables belong to the separate selected-composition gate, not this comparison.

G3 — Native discovery under both profiles must match the exact approved full signatures, resolving Forge's bare names through compiled methodIdentifiers rather than assuming signatures. Run the full default offline suite with RPC unset and again with `MAINNET_RPC_URL=http://127.0.0.1:1`; PASS sets must equal discovery/inventory, with no failures/skips. The ABI test must read the fresh default `out/`, not a stale path. Bind original r3confirm2 fork receipts to the unchanged source/runner/configuration and 13-identity set; label them historical raw-target regression evidence.

This documentation order does NOT require a new live/cold fork run or mutation battery: every Solidity/test/runner/configuration byte is frozen and its existing full evidence is retained. That is an explicit scope decision for prose-only work, not retroactive waiver of an earlier required gate. No historical raw-admin green can satisfy selected-production-composition W1–W8. Any source/input mismatch invalidates the documentation-only exemption and requires a new authority ruling, not an unapproved code repair.

G4 — One bounded independent confirmation: check all P1–P4 required meanings, source/ABI/error accuracy, changed-path/source/artifact/census evidence, final index binding and future-engagement paragraph. No fresh broad security/complexity audit. Report finite missed work-order cells if any; do not create a new refactor queue. On pass: DOCUMENTATION ORDER CONFIRMED; LEAN CONVERGENCE RETAINED; ACTIVATION HOLD. Owner approval absent remains OPEN; paid admission stays disabled until actual controller, FD, venue, binding, float and operational approval gates are met.

No build, confirmation, commit, test or completion marker authorizes raw-admin transfer, deployment, governance broadcast, production unpause or changes to old escrow.
