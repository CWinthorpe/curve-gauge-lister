# REVIEW LEG BRIEF — curve-gauge-lister / v1align-conf2 (VC-01 receipt verdict + VC-02 amendment ruling)

Bounded closure leg, clinical register. Two items, then certify or name the
remainder. Candidate main @ 2c7c1f0 (orchestrator verified 77/77 offline,
13/13 fork, product+test diff EMPTY vs b37e533 — receipts only).

1. VC-01 (F-NB-SPLIT redo): the fix leg claims a product-only mutant that
   corrupts only the FD-credit side, keeping earlier guards alive, so
   test_KillAtEachReleaseCount now FAILS AT the exact FD-delta assertion
   (WITNESSES.md:74). REPRODUCE it yourself in a disposable copy: pristine
   green → mutant red at the named frame (cite the trace line) → restored
   green. Credit or reject per the frame, not the claim.

2. VC-02 (F-NB-HORIZON near-end cell): the fix leg declares the WEEK-1
   cursor cell unreachable under the authorized epochStart(t)->t mutant
   (offset-1 aborts first; per-offset selection cannot skip it without test
   edits, which the authority freezes) and files an amendment request:
   plans/.../AMENDMENT-REQUEST-VC02.md with impossibility receipts. RULE:
   read the receipts; either ACCEPT the amendment — amending
   V1ALIGN-WITNESSES.md:76's cell to guard-level sensitivity as the honest
   maximum (state exactly what the earlier red DOES prove: H+1 partial-week
   horizon liveness) — or DIRECT a specific reachable alternative. You may
   probe the impossibility yourself (selected-offset runs). The existing
   receipts stay untouched either way.

On both closed: certify NO-BOUNTY V1 ACCEPTED, deployment-pending. Commit
review/V1ALIGN-CONF2.md `v1align-conf2: <verdict> <sha>` + push. If you
amend the witness authority, include the amendment text in the same commit.

Print `DONE v1align-conf2` as your final line.
