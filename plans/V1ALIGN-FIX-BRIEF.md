# EXEC LEG BRIEF — curve-gauge-lister / v1align-fix (close VC-01 + VC-02 falsifier cells)

Executor lane, qwen. Authority: review/V1ALIGN-CONF.md (HOLD @ b37e533) —
read VC-01 and VC-02 in full; their "Required disposition" paragraphs are
the order. Candidate b37e533. Product files FROZEN; final tests byte-
identical; the ONLY changes are falsifier mutant construction + new receipts
under review/v1align-execution/gates/. No relabeling or rewriting existing
receipts; they remain history.

VC-01 (F-NB-SPLIT): deliver a product-only mutant that keeps the
gross lister-debit and prior guards alive but corrupts ONLY the FD-credit
side of the half-remainder split path, so the selected identity
test_KillAtEachReleaseCount proceeds PAST ConfiscationDeltaMismatch and
fails AT the specified exact-FD-delta assertion (plans/V1ALIGN-WITNESSES.md:74).
If no such mutant reaches that frame without touching the guards the
authority says must stay live, publish the failing-frame proof of that
impossibility and take the alternative disposition: an authority-amendment
request file stating why the earlier guard-level sensitivity is the honest
maximum — I will route it to Astra; do not self-approve.

VC-02 (F-NB-HORIZON): make the named near-end cursor cell (offset WEEK-1)
actually EXECUTE under the epochStart(t)->t mutation — per the report the
offset-1 abort preempts it. Achieve execution by splitting the mutant run
into per-offset selected executions (same final test, three native runs
each selecting a single offset path if the test structure permits via
--match-contract/--match-test selection only — no test edits) so all three
cells (0, 1, WEEK-1) have their own 0/1/0 receipts; or, if a cell is
unreachable for that mutant class, the same impossibility-proof + amendment
request route.

Gates on final tree (unchanged candidate): fmt/build both profiles; offline
77 exact; fork 13 via scripts/test-fork.sh once; product+test diff EMPTY vs
b37e533 (receipts only). Commit prefix `v1align-fix:`, push. Report: each
row — mutant diff, selected identity, native exits, final failing frame,
plus whether amendment requests are needed.

Finish by printing exactly `DONE v1align-fix` as your final line.
