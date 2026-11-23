# r3docs — confirmation-brief carrier (work order P0 builder remainder)

This is the carrier into which `plans/R3GATE-WORK-ORDER.md` P0 requires the
r3gate §3.4 structural future-engagement paragraph to be carried VERBATIM.
It binds the ONE bounded independent confirmation pass (work order G5).

## Scope of the confirmation pass (G5, restated — not enlarged)

- Inspect only: P0-P2 delivery, the admitted row mapping
  (`review/r3docs/ROW-HUNK-MAP.md`), the G0-G4 receipts
  (`review/r3docs/GATES.md`, `review/r3docs/BYTECODE-PROOF.md`,
  `review/r3docs/artifacts/`) and the current obligation statuses
  (`review/simplify2/FD-BOUND-OBLIGATION.md`,
  `review/simplify2/CTL-CALLER-ROLE-GATE.md`,
  review/simplify2/AUTH-EVIDENCE-INDEX.md incl. its r3docs final-binding
  addendum).
- Verify exact candidate/source/hash custody and compare the prose to the
  actual code/observations.
- May reproduce existing gates or produce the final G4 receipt on the exact
  shipped candidate; the builder and confirmer need not duplicate the same
  final fork run merely to create two receipts.
- No new simplification hunt, no arbitrary sensitivity expansion, no
  confirmation-by-count.
- If the allowed edits and all gates pass, state exactly:
  LEAN CONVERGED — ACTIVATION OBLIGATIONS OPEN, while carrying
  PAO-FD/CTL/AUTH as ACTIVATION-OPEN without counting them again as
  simplifications. A failed confirmation is a named bounded
  correction/HOLD, not an automatic new broad audit.
- The confirmation binds the shipped product/docs candidate
  `a9de6ffc99343801575b72a2be78ea83bd73508c` (receipts land in the final
  r3docs commit under `review/r3docs/`; product tree unchanged after the
  candidate).

## Mandatory future-engagement wording (r3gate §3.4, verbatim)

> Review the candidate against the admitted authority and its PRE-ACTIVATION OBLIGATION register before counting findings. PAO-FD, PAO-CTL and PAO-AUTH have two statuses: SATISFIED-TRACKING and ACTIVATION-OPEN. An acknowledged, candidate-bound obligation with its missing evidence, approval role and activation stop condition recorded is NOT a confirmed simplification merely because production selection, grants, current-pin observations, a certificate or final approval remain open. Carry it once in a separate activation-obligations section; give no fresh simplification count or design-quality deduction for that unchanged status. This does not certify deployment or waive the obligation. A new confirmed finding must identify a concrete missing or contradictory current invariant, false evidence claim, unsound coverage/composition argument, inaccessible required evidence, stale candidate binding, or proposed activation bypass, and explain the exact delta from the registered obligation with source/cell evidence. A genuinely new defect remains reportable even within an acknowledged obligation. If a mandatory approval/evidence cell is absent at an activation review, activation is HOLD regardless of design convergence. Cosmetic restyling, repeated requests to choose an already-open deployment alternative, and proposals with no material review/safety benefit are not confirmed simplifications. Confirmed status is never implementation authority: every proposed change still requires an itemized ADOPT/DEFER/REJECT ruling and a bounded work order preserving the monetary law, guards and exact approved witness identities.

The register travels with each candidate's owner-approved review package;
it need not all be public. Failure to supply the required package is a
bounded evidence-access finding, not grounds to invent content. References
to pre-r3 DONE labels must carry the tracking-versus-activation
distinction. (Framing around this quote restates RULING.md §3.4/§5 for the
confirmation carrier; only the quoted block above is the verbatim mandate.)
