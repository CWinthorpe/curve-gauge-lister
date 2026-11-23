# EXEC LEG BRIEF — curve-gauge-lister / v1align-exec (implement the no-bounty V1 parity per V1ALIGN authority)

Executor lane, qwen. Sole authority: plans/V1ALIGN-PLAN.md +
V1ALIGN-WITNESSES.md + V1ALIGN-WITNESS-INVENTORY.json + V1ALIGN-MANIFEST.json
+ V1ALIGN-DOC-DELTAS.md at HEAD (561c93d lineage) — read ALL five in full
before touching anything; they are binding at cell/file level.

Baseline: e18bee5 + authority. Execute §6's four packages EXACTLY, one
commit each, prefix `v1align:`, never merged/squashed:

P1 Core parity + fixture wiring (constructor seventh-arg validator,
WrongChain first, paused-at-construction, ITrustedGaugeValidator + trusted
mock move, ALL constructor call sites updated incl. fork fixture helpers and
interim-live V2/bounty test references so the tree compiles at each commit;
never weaken original assertions to accommodate setup).
P2 Port the eight trust offline identities (test/TrustedFactory.t.sol,
names unchanged) + rewrite the two fork trust identities onto no-bounty
fixtures; add matrix-named cells; delete the old v2 trust file in the move;
run native inventories + named trust falsifiers.
P3 Retire the bounty shipping tree per the named deletion list ONLY
(after dependency closure; keep test/bountyfix02/ and every survivor),
delete docs/BOUNTY-ABI.md + docs/BOUNTY-OPERATIONS.md, create docs/ABI.md +
docs/OPERATIONS.md, apply V1ALIGN-DOC-DELTAS verbatim to README/proposal/
pins/venue-intel; re-derive census; run the ENTIRE G1–G7 gate set.
P4 Evidence only: review/v1align-execution/FINAL.md — exact commits, file
dispositions, native inventories (bare names AND compiled signatures per
plan §4), gate exits, sizes/ABI/layout vs V1ALIGN-MANIFEST.json under both
profiles, mutant diffs + red frames + restored reruns, deployment-open
items. Fix defects by amending the responsible package, never smuggle code
into P4.

Gates: run them as written (G1–G7), including the isolated-HOME cold fork
run on the SAME pin (block 26401019, never a block override; preserve the
failed-endpoint attempt if one happens), unreachable-RPC repeat, both-
profile builds/sizes under 24,576 with metadata counted, fresh-out rule for
the hardcoded-path adapter tests, and byte-identical candidate tests during
falsifiers. No compiler-policy change, no new dependency, no broadcast, no
deploy, no waivers.

Census honesty: 77 offline / 13 fork is the plan's derived expectation —
report ACTUAL counts with inventory reconciliation; extra justified
regressions need inventory rows; missing/skipped/duplicated identities
BLOCK, do not delete a valid witness to hit a number.

If anything conflicts with the authority docs or a gate is unrunnable:
plans/V1ALIGN-EXEC-BLOCKED.md, stop that package, continue independents.
Checkpoint-commit immediately when green (`wip:` under clock pressure),
never end a sitting uncommitted. Push origin main throughout.

Finish by printing exactly `DONE v1align-exec` as your final line.
