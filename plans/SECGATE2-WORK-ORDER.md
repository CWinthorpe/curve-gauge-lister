# secgate2 — bounded Votium disclosure/operations work order

Authority: `review/secgate2/RULING.md` and `review/secgate2/BINDING.json`.
Baseline product: `4a442e63421a89b04e902f4e709613b8234f16c5`, plus its authority-only secgate2 child.
Status: RELEASED FOR PROSE/EXISTING-ROLE DUTIES ONLY; NO EXECUTABLE CHANGE; SECURITY CONVERGENCE PENDING; ACTIVATION HOLD.

Only CGL-V05 is ADOPTED for new work. CGL-V01–V04 and CGL-I01–I11 generate no new builder tickets. This is not authority to implement the audit report's recovery suggestions. Acceptance of the no-project-recovery consequence is effective now; public disclosure and reconciliation instructions remain owed.

## P5 — CGL-V05 Votium unprocessed-incentive disclosure and reconciliation

### Allowed product sites

1. `docs/OPERATIONS.md`: add one adjacent section, “Votium unprocessed incentives”, before the existing VoteMarket residuals section; a narrow cross-reference in Admission and ordinary settlement and a Votium-specific addition to Review and change boundary are permitted only to connect that section to the existing cadence/registration. Do not rewrite the VoteMarket acceptance or duplicate the monetary model.
2. `docs/CURVE-PROPOSAL.md`: add one Votium-specific bullet under Limits and disclosures, referring to the operations reference. Keep the existing VoteMarket bullet and all fixed economics, rollout/pin/controller statements unchanged.

No README/ABI/deployment-pin/source-comment edits are needed or authorized. Public prose must be self-contained; no unpublished authority path is required to understand the limitation. All other product bytes remain frozen to the baseline.

### P5-D — required disclosure meaning

Use the following wording in the operations section; normal document wrapping is allowed, not weakening of qualifiers:

> A successfully funded Votium share is final gross expenditure from listing escrow, not proof that its incentive was processed or that voters received rewards. The venue records the adapter as depositor, but this adapter cannot withdraw or recycle an unprocessed incentive. Such amounts can remain unavailable for their intended distribution indefinitely, with no project-controlled recovery and no restoration of listing escrow or payer/Curve FeeDistributor credit. Under the referenced venue policy, the Votium owner can recycle an eligible unprocessed incentive; that is an independent upstream power, not a right of the lister or adapter owner and not a promise of recovery or eventual distribution. A gauge kill does not by itself prove permanent loss. Venue processing and downstream voter claims must be evidenced separately, and the selected venue/distributor policy must be reverified before activation.

The payer-facing bullet must retain final gross expenditure, potential indefinite unavailability, no project-controlled withdrawal/recycling or local recredit, the separate conditional venue-owner recycling possibility, and the distinction between ingress/processing/actual rewards. A concise reference to the runbook may carry the operational detail, not hide those economic limits.

Do not import VoteMarket's campaign-close timetable, fee-collector outcome, destination manager or bridge mechanics into Votium. Unprocessed is not synonymous with processed-but-unclaimed. The saved Votium ingress transfers aggregate rewards to a distributor; it does not prove a downstream Merkle implementation, claim expiry, or a kill's effect on an existing voter claim. Do not assert any such policy without selected-deployment evidence. No promise of at most two maturities per Votium round is permitted: catch-up uses execution-time rounds.

Source anchors: `contracts/adapters/VotiumAdapter.sol:127–190,193–242`; `contracts/libraries/AdapterOwnable.sol:25–43`; `contracts/CurveGaugeLister.sol:530–544,649–670,853–875,936–949`; saved Votium source bound in secgate2 BINDING at :333–381,541–615,639–648,703–801. These support the disclosure, not current runtime or outcome certification.

### P5-O — bounded existing-role operations duty

Use the existing settlement keeper and governance/venue liaison; do not build monitoring software or invent a new contract manager role.

- On each successful source settlement, retain chain/venue/adapter identity, source transaction and log positions, gauge, scheduled maturity, execution round, gross funded amount and adapter-domain receipt. Correlate the actual upstream `NewIncentive` event/state to `(venue, round, gauge, incentive index)`, depositor, token and recorded fee-net amount. Read/derive fees only from actual selected-source/evidence; do not hardcode a future fee. The adapter receipt is repeatable and event-only, not a unique upstream incentive index.
- Reconcile outstanding funded Votium incentives at the existing at-least-hourly pending-work cadence and on settlement. “Pending work” here includes unresolved downstream incentives after the local listing becomes Exhausted or Confiscated; local terminal state does not close venue follow-up. Normal future-round processing is pending, not automatically failure.
- Record observed amount/`distributed`/`recycled`, observation block and processing/finalization evidence. Distinguish pending/unprocessed or unknown, evidenced processing/allocation, and evidenced recycling; mixed/partial states keep their actual amounts. Track a recycled amount through the evidenced successor incentive index/round, whether created by ordinary round processing or by authorized upstream-owner recycling. A finalized round alone is not proof that every incentive was processed. Unknown/missing evidence remains unknown.
- Keep processing/allocation separate from distributor transfer and voter claims. A nonzero `distributed` field, a source receipt or a finalized round is not proof of individual rewards or a Merkle claim. Claim/distribution assertions require separately authenticated selected-distributor evidence; absent it, state the limit rather than inventing delivery, root publication or a claim ID.
- Escalate unresolved/abnormal processing and missing evidence to the existing governance/venue liaison; disclose unresolved spent amounts without guaranteeing restoration. Monitoring and upstream coordination are staffing duties, not an SLA or a project right to force a venue action. Investigate persistent incompatibility and pause NEW paid admissions through existing authorized roles under the runbook; that does not recover old expenditure or redirect existing snapshots.
- Do not reverse `released`, restore `remaining`/`totalEscrow`, resubmit the spent maturity, promise a payer/FD credit or equate a returned/donated adapter balance with recovered listing escrow. No project withdrawal/recycle/reclaim/manager-update/receiver-selection/execute/acknowledgement API, new residual ledger, recovery bot or automatic intervention is authorized. An upstream-owner action must be separately authorized under the real venue's policy and evidenced; this order authorizes no broadcast by that owner or this project.
- Before enabling a positive Votium share, the deployment operator and keeper must supply current source/runtime/policy and funded-ingress evidence required by the existing venue gate, an evidenced understanding of the selected processing/distributor boundary, and a staffed reconciliation/escalation assignment. The owner/governance release authority must explicitly accept the disclosed no-project-disposition and indefinite-nondistribution risk. Missing mandatory evidence, staffing, disclosure or approval is HOLD. No actual venue readiness, staff appointment or approval is claimed by writing this runbook. Selecting a zero share is only a separately approved prospective configuration choice, not a repair for old records or an instruction in this order.

### P5-A — acceptance cells

| Cell | Required observable result |
| --- | --- |
| D1 | Operations text identifies the adapter as depositor, final gross local expenditure, lack of callable project withdrawal/recycling and no recredit. |
| D2 | Potential indefinite unavailability is explicit; eligible Votium-owner recycling remains conditional/separate; kill is not automatic permanent-loss proof. |
| D3 | Ingress, venue processing/allocation, distributor transfer and downstream claims are distinguished; no VoteMarket timetable or unverified Merkle/expiry assertion. |
| D4 | The payer bullet discloses the economic limitation rather than relegating it entirely to the runbook. |
| O1 | Actual source logs/receipt are correlated to actual venue/round/gauge/incentive index, with gross/net/fee and depositor evidence; no invented ID or receipt uniqueness. |
| O2 | Existing hourly/settlement cadence includes unresolved downstream work after local terminal state; actual amounts and recycled-successor lineage are retained. |
| O3 | Escalation/disclosure, no silent resubmission/recredit and independent upstream authority are explicit; no new monitoring software or authority. |
| O4 | Selected positive-share policy/evidence/staffing/risk approval remains pre-activation HOLD until satisfied; document delivery does not supply it. |

## Sealed behavior, census and publication scope

Fee/tranche/Thursday cadence, current-flag-only kill, later-quarter observations, both-leg/all-due atomicity, all-FD remainder, mandatory accounting, admission precedence, immutable listing endpoints/split, zero-share no-call, owner-only write-once adapter binding, approval sequence, ingress receipt meaning, ABI and storage are unchanged. Preserve every Solidity byte including comments, every test body/identity, runner, manifest, literal pin and compiler setting. No recovery mechanism may add manager/reclaim powers. No optional cleanup from the informational rows is admitted.

Census remains the exact 77 default and 13 fork full file:contract:signature sets in secgate2 BINDING, identical to secgate and the normative witness inventory. No additions/removals/renames/skips. Expected bytecode change is ZERO for full creation/runtime artifacts INCLUDING metadata under identical profiles/toolchain/inputs; a source/comment/config mismatch is a STOP, not permission to use metadata-stripped equality.

Implement one row-mapped prose commit; an evidence-only child is permitted if required by the execution brief. New builder receipts belong under owner-held `review/secdocs2/`. Append the actual final candidate and receipt/approval-status bridge to the SAME owner-held `review/simplify2/AUTH-EVIDENCE-INDEX.md`, preserving its complete pre-builder prefix, including secgate2's supplement. No separate Votium carrier or authority stack. Do not modify PAO-FD/CTL, older rulings/work orders/bindings or historical raw receipts. Do not republish ignored carriers, audit inputs or bulk evidence by association.

The authority-leg publication exception is only the five files listed in secgate2 BINDING. Builder product publication is limited to the two named public documents. Evidence remains owner-held/producible on demand unless a subsequent operator order names an exact publication exception. P1–P4 implementation stays credited; the pre-existing secgate G4 confirmation remains owed, not reissued as builder rework.

## Mandatory verification and stopping rule

G0 — Bind the exact baseline and final product candidate; hash every baseline tracked file and show that only the two admitted public documents differ on the product side. Map every hunk to D1–D4/O1–O4 and source truth; run native `git diff --check`. Verify the preserved index prefix and exact final bridge, with absent owner/activation approvals explicit.

G1 — In an isolated exact final-candidate archive with fresh outputs, use the same installed toolchain and unchanged foundry profiles. Run `forge fmt --check`, both-profile offline builds with sizes/storageLayout, and the full default offline suite with RPC unset. Discover both profiles and reconcile exact signatures with the normative/bound 77/13 sets. Preserve actual stdout/stderr/exits and warnings; fail or skipped identities are not success. The ABI witness must use fresh default `out/`, not a stale artifact path. No dependency install/compiler-policy change/source edit is authorized to force a pass.

G2 — Demonstrate full creation/runtime bytecode INCLUDING metadata, ABI/methodIdentifiers/recursive layout and product sizes are unchanged from 4a442e6 under each same profile, using complete retained baseline artifacts if available and authenticated; otherwise build the exact baseline in a separate fresh archive. Compare all three product deployables, not counts alone. Bind source/compiler/settings. Reconcile the saved 13 fork identities to frozen source/runner/configuration, explicitly historical raw-target regression evidence. No new live/cold fork, mutation battery, deployment or chain transaction is required for this prose-only order. Missing artifacts or native failures are bounded evidence gaps, never fabricated results.

G3 — ONE bounded independent confirmation of P5's eight acceptance cells, source accuracy, all changed paths/freeze/artifact/census evidence and the same-index final binding. Include the carried secgate G4 P1–P4 confirmation owed at the baseline; it need not rerun a blind audit or create more documentation beyond any concrete missed cell. Its brief must include the ORIGINAL secgate §6 registration paragraph and the secgate2 §7 supplement verbatim. Prior receipts retain their original scope; neither a count nor this order's issuance closes the confirmation.

On pass, the authority can issue SECURITY AUDIT CONVERGED for the exact final documentation descendant, with unchanged contracts bound to 4a442e6, LEAN CONVERGENCE RETAINED, and ACTIVATION HOLD. Use truthful severity history: round one contained one conditional High, disposed through composition prohibition/P1 with selected integration still open; round two contained zero Critical/High. Do not state that both rounds historically found zero High, or that all four re-derivations had eight-model attribution. No full third blind round is warranted solely for the registered limits or this prose change. A failed mandatory cell is a finite named correction/HOLD; a genuinely changed invariant/composition or new material defect still requires authority adjudication.

No completion marker, suite result, commit or convergence certificate authorizes deployment, raw-admin transfer, governance broadcast, production unpause, a recovery operation or changes to old escrow.
