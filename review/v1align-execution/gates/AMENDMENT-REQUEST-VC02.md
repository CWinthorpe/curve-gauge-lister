# AMENDMENT REQUEST — VC-02 near-end cursor cell (F-NB-HORIZON)

Status: REQUEST FOR REVIEW-AUTHORITY DISPOSITION. Not self-approved.
Routing: executor lane (qwen) -> Astra (V1ALIGN-CONF review authority).
Candidate: b37e5333a07050e7ea87da98712c0edc483673fa (product+tests frozen;
this leg changed no product/test byte — receipts only).
Authority anchors: plans/V1ALIGN-WITNESSES.md:76; review/V1ALIGN-CONF.md
VC-02 "Required disposition".

## What the executor leg delivered

The authorized mutant (`epochStart(t)` -> `t` in the Step-2 freshness bound,
contracts/CurveGaugeLister.sol:767) was re-run against the FINAL committed
witness `test/Settlement.t.sol:SettlementTest:
test_AuditM01_AccountingHorizonIncludesPartialWeekEdges()` with native exits
0 / 1 / 0 (pristine / mutant-red / restored), exact single-identity
selection (`--match-path` + `--match-contract '^SettlementTest$'` +
`--match-test '^...\\(\\)$'`, `-vvvv`), tests byte-identical across stages
(per-stage SHA-256 pins in `vc02/test_AuditM01_...attribution.json` and the
sealed bundle `vc02-falsify-logs.tar.gz`).

Per-cell execution attribution from the -vvvv traces:

| Cell | cursor (setLastTokenTime frame) | pristine | mutant red | restored |
| --- | --- | --- | --- | --- |
| oi=0 offset 0      | 1800489600 | 3 probes executed, green | 3 probes executed, green | 3 probes, green |
| oi=1 offset 1      | 1818633601 | 3 probes executed, green | 3 probes executed; h+1 probe RED (`next call did not revert as expected`) — test ABORTS here | 3 probes, green |
| oi=2 WEEK-1 (named near-end) | 1837382399 | 3 probes executed, green | **0 frames — never executed** | 3 probes, green |

The red log contains zero occurrences of the near-end cursor 1837382399 and
zero occurrences of its probe warps (1848873599 / 1848873600 / 1848873601);
the pristine and restored logs contain all three of each.

## Why the brief's primary disposition is mechanically impossible here

The brief permits splitting "into per-offset selected executions ... if the
test structure permits via --match-contract/--match-test selection only —
no test edits". It does not permit:

1. Selection granularity is the COMPILED FUNCTION. `forge test --offline
   --list --json` shows exactly ONE identity covering all three cells:
   `test/Settlement.t.sol:SettlementTest:test_AuditM01_AccountingHorizonIn
   cludesPartialWeekEdges()` (probe log `...probe-list.json.log`).
2. The three offsets are an in-function array loop (`uint256[3] memory
   offsets = [0, 1, WEEK-1]`, function at test/Settlement.t.sol:2023, loop
   body through :2040 — the range V1ALIGN-CONF VC-02 itself cites). No
   per-offset identity, parameter, or environment handle exists.
3. Per-offset selector attempts are provably empty: `--match-test` patterns
   naming a single offset path select nothing (probe logs
   `...probe-sel-cell0_offset0.log`, `...probe-sel-cell1_offset1.log`,
   `...probe-sel-cell2_weekminus1.log` — no `Ran 1 test for`, no PASS/FAIL
   lines; empty selection is not a kill and not an execution).
4. Forge-std assertions abort a test function at the FIRST failed assertion
   (require-based reverts in test/TestBase.sol). The oi=1 h+1 probe fails
   first; oi=2 code is unreachable for this mutant class within the one
   permitted selection identity.

## The honest maximum, and what acceptance would mean

Arithmetic note: for oi=2 the mutant bound would be
`(h+1) - (T0+71*WEEK-1) = 19*WEEK+2 <= 20*WEEK`, so the near-end h+1 probe
would also fail `expectRevert` — at the SAME assertion as the oi=1 cell — if
and only if execution reached it. What the executed red PROVES is genuine
H+1 freshness-bound sensitivity at the first partial-week cursor (offset 1),
not the specifically named near-end cursor. That is exactly the partial
evidence V1ALIGN-CONF VC-02 declined to credit.

Requested dispositions (pick one; executor makes no choice):

A. Amend the VC-02 authority to accept the offset-1 H+1 cell (this battery,
   with per-cell attribution receipts) as the maximum honest sensitivity for
   the epochStart(t)->t mutant class, closing VC-02 as
   "near-end cell unreachable; earlier partial-week cell executed and
   killed at the named assertion class".

B. Or authorize, in a FUTURE test-authority leg (not this one — it would
   break the final-tests-byte-identical freeze), splitting the loop into
   three dedicated per-offset identities so each gets its own 0/1/0 receipt.

## VC-01 (for completeness — no amendment requested)

VC-01 is closed WITHOUT an amendment: the delivered product-only mutant
F-NB-SPLIT-R2 reaches the designated test assertion `FD got exactly the
unreleased` (test/Settlement.t.sol:2341) with the gross lister-debit
postcheck, the Step-1/Step-2 destination and cursor guards, and the Step-5
mandatory-checkpoint postchecks all alive (receipts `F-NB-SPLIT-R2.*`),
satisfying the VC-01 Required disposition. The companion row
F-NB-SPLIT-LITERAL documents the construction necessity: keeping the
FD-credit postcheck literal while splitting the credit makes the product
revert at contracts/CurveGaugeLister.sol:782 before the witness call
returns, so the aligned FD-credit postcheck is a required part of the
authorized "FD-credit side of the half-remainder split path" scope, not a
removal. No product defect is indicated; the pristine guards continue to
catch this split.
