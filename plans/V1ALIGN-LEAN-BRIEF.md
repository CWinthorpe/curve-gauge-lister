# REVIEW LEG BRIEF — curve-gauge-lister / v1align-lean (lean sweep of the no-bounty V1 tree)

Lean sweep, clinical register — same standard as the project's prior lean
rounds. Candidate: main @ ce0fe3a (certified no-bounty V1, 77/13 gates
green). You are a surgeon: find code/docs kept ONLY because the deleted
bounty or V2 lineage needed it. No redesigns, no new abstractions, no
speculative refactors.

## Sweep targets
1. Orphaned surface: functions/getters/events/errors/constants/interfaces/
   library branches whose only callers died with V2/GaugeBounty — prove
   per item with repo-wide search across contracts/, test/, fork/, scripts/
   before proposing.
2. Dead imports/storage-adjacent code: libraries still carrying bounty-era
   branches (e.g. FeeDistributorAccounting's BountyScripts import was
   flagged during v1align — verify closure is clean; any similar residue).
3. Test-side rot: helpers/fixtures/mocks retained only by retired
   identities (bounty-named fixtures surviving by name alone, unused mock
   seams).
4. Doc drift: README/docs/OPERATIONS/ABI/PINS sentences still describing
   deleted subsystems or asserting anything the code no longer does.
5. Size/gas: any product contract that grew in the amendment without a
   ruled reason.

## Hard rules
- Every proposed cut: proven in a disposable worktree (compile + full
  suites green WITH the cut applied), before/after size delta recorded,
  then reverted; unproven cuts do not enter the table.
- FROZEN: certified monetary law (fee/tranche/epoch/confiscation code
  paths, FD accounting, validator gate), falsifier receipts under
  review/, witness authority files, foundry.toml, adapters' certified
  bytes. A cut requiring a change to any of those is DECLINED, not argued.
- Census may not move: 77/13 exact set equality before and after; if a cut
  would alter an identity, the cut is wrong.
- Empty table is a valid outcome: certify LEAN in one page; do not
  manufacture cuts.
- Cuts (if any): one commit per item `v1align-lean:`, full gates each
  (fmt/build/offline 77/unreachable-RPC repeat/fork 13/frozen-diff check).
Report review/V1ALIGN-LEAN.md + push. Print `DONE v1align-lean` as your
final line.
