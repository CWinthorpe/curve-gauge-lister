#!/usr/bin/env python3
"""VC-01 closure — F-NB-SPLIT falsifier that reaches the named test frame.

Authority: review/V1ALIGN-CONF.md VC-01 "Required disposition" and
plans/V1ALIGN-WITNESSES.md:74 (`test_KillAtEachReleaseCount` / exact FD
delta). The stored F-NB-SPLIT mutant (half-transfer only, both product
delta postchecks untouched) is preempted by the lister-debit check and
reports ConfiscationDeltaMismatch(); test/Settlement.t.sol:2339 never
returns so the designated `FD got exactly the unreleased` assertion at
:2341 is never evaluated.

Rows here (product-only mutations, final committed tests byte-identical):

- F-NB-SPLIT-R2: the half-remainder split path keeps the GROSS lister
  debit alive and honest (both halves leave the lister; the lister-debit
  postcheck at contracts/CurveGaugeLister.sol:779-781 is UNTOUCHED and
  passes) and keeps every earlier guard (Step 1 destination guards, Step 2
  cursor/freshness guards, Step 3 terminalization + gross liability debit,
  Step 5 mandatory checkpoint + cursor/custody postchecks, events) alive.
  ONLY the FD-credit side of the split path is corrupted: FD is credited
  half the remainder, the other half leaves to an inert sink address, and
  the FD-credit postcheck stays LIVE (still reverts ConfiscationDeltaMismatch
  on any deviation from the split credit) but is aligned to the corrupted
  credit so `confiscate` returns and the selected test proceeds PAST
  ConfiscationDeltaMismatch and fails AT :2341 `FD got exactly the
  unreleased`. This is the construction VC-01 names as "corrupts ONLY the
  FD-credit side of the half-remainder split path".

- F-NB-SPLIT-LITERAL (impossibility lemma): same split transfers, but the
  FD-credit postcheck kept LITERAL (`fdBefore + amount`). Confiscate then
  reverts at contracts/CurveGaugeLister.sol:782 with
  ConfiscationDeltaMismatch() — the test aborts at the :2339 call frame and
  :2341 is never evaluated. With the MockFeeDistributor source fact that
  checkpoint_token moves no tokens (contracts/mocks/MockFeeDistributor.sol
  `_doCheckpointToken` only reads balanceOf and updates bookkeeping), this
  empirically establishes that no product-only mutant which keeps BOTH
  delta postchecks literal can reach the named test frame: any FD credit
  shortfall is stopped by :782 before the test's own measurement, and any
  FD-side change after :782 would have to come from a token movement that
  the product's Step-5 call path does not perform. Hence aligning the
  FD-credit postcheck to the corrupted credit is a NECESSARY part of the
  authorized FD-credit-side corruption scope, not an optional touch.

Selected identity for both rows:
  test/Settlement.t.sol:SettlementTest:test_KillAtEachReleaseCount()
Selection form (V1ALIGN-CONF §5): --match-path <file> --match-contract
'^SettlementTest$' --match-test '^<name>\\(\\)$', verbosity -vvvv on every
stage so the trace carries the cheat/call frames used for attribution.
"""
import hashlib
import json
import os
import shutil
import subprocess
import sys

CAND = os.environ["CGL_CANDIDATE"]
WORK = os.environ.get("CGL_FALSIFY_WORK", "/home/winny/tmp-scratch/v1align-fix-vc01")
CL = "contracts/CurveGaugeLister.sol"
SUITE_FILE = "test/Settlement.t.sol"
CONTRACT = "SettlementTest"
TEST = "test_KillAtEachReleaseCount"
SINK = "0x000000000000000000000000000000000000dEaD"

SPLIT_EDITS = [
    (
        "        SafeToken.safeTransfer(crvUSD, fd, amount);\n",
        "        SafeToken.safeTransfer(crvUSD, fd, amount / 2); // MUTANT half-remainder split: FD credited only half\n"
        f"        SafeToken.safeTransfer(crvUSD, {SINK}, amount - amount / 2); // MUTANT other half leaves the lister (gross debit stays whole)\n",
    ),
]
CHECK2_EDIT = [
    (
        "        if (IERC20Minimal(crvUSD).balanceOf(fd) != fdBefore + amount) revert ConfiscationDeltaMismatch();",
        "        if (IERC20Minimal(crvUSD).balanceOf(fd) != fdBefore + amount / 2) revert ConfiscationDeltaMismatch(); // MUTANT FD-credit postcheck kept live, aligned to the split credit",
    ),
]

# id -> (file, edits, required first-failing label, labels that must be ABSENT)
MUTANTS = {
    "F-NB-SPLIT-R2": (CL, SPLIT_EDITS + CHECK2_EDIT,
                      "FD got exactly the unreleased", ["ConfiscationDeltaMismatch"]),
    "F-NB-SPLIT-LITERAL": (CL, SPLIT_EDITS,
                           "ConfiscationDeltaMismatch", ["FD got exactly the unreleased"]),
}

PIN_FILES = sorted(
    os.path.join(dp, f)
    for dp, _, fs in os.walk(CAND)
    for f in fs
    if (dp[len(CAND) + 1:].split(os.sep, 1)[0] in ("contracts", "test", "fork"))
)
PINS = {p: hashlib.sha256(open(os.path.join(CAND, p), "rb").read()).hexdigest() for p in PIN_FILES}


def sub(text, old, new):
    assert text.count(old) == 1, "anchor not unique: %r" % old[:80]
    return text.replace(old, new)


def run(cmd, cwd, log):
    r = subprocess.run(cmd, shell=True, cwd=cwd, capture_output=True, text=True)
    with open(log, "w") as fh:
        fh.write("$ " + cmd + "\n\n" + r.stdout + "\n--stderr--\n" + r.stderr
                 + "\nexit=%d\n" % r.returncode)
    return r.returncode, r.stdout + r.stderr


def forge_cmd(extra_verb=""):
    return (f"forge test --offline --match-path {SUITE_FILE} "
            f"--match-contract '^{CONTRACT}$' --match-test '^{TEST}\\(\\)$' {extra_verb} 2>&1")


def hashes(d, tag, out):
    rows = []
    for p in PIN_FILES:
        h = hashlib.sha256(open(os.path.join(d, p), "rb").read()).hexdigest()
        rows.append(f"{tag} {h} {p}")
    out.extend(rows)


def main():
    only = sys.argv[1:] or list(MUTANTS)
    os.makedirs(WORK, exist_ok=True)
    results, hashlog = [], []
    for mid in only:
        rel, edits, label, absent = MUTANTS[mid]
        d = os.path.join(WORK, "copy_" + mid.replace("-", "_"))
        if os.path.exists(d):
            shutil.rmtree(d)
        shutil.copytree(CAND, d, ignore=shutil.ignore_patterns(
            "out", "out-fork", "cache", "cache-fork", ".git", "gates-out"))
        pristine_src = open(os.path.join(d, rel)).read()
        pg, rg = True, True
        rc, out = run(forge_cmd("-vvvv"), d, os.path.join(WORK, f"{mid}.{TEST}.pristine.log"))
        pg = rc == 0 and f"[PASS] {TEST}()" in out and "Ran 1 test for" in out \
            and "0 failed" in out and "0 skipped" in out
        hashes(d, f"{mid}.pristine", hashlog)
        mutated = pristine_src
        try:
            for old, new in edits:
                mutated = sub(mutated, old, new)
        except AssertionError as e:
            results.append((mid, "MUTATION-PATCH-FAIL", str(e)))
            print(mid, "MUTATION-PATCH-FAIL", e, flush=True)
            continue
        assert mutated != pristine_src
        with open(os.path.join(WORK, f"{mid}.patch.txt"), "w") as fh:
            fh.write(f"file: {rel}\nselected: {SUITE_FILE}:{CONTRACT}:{TEST}()\n"
                     f"required-label: {label}\nmust-not-appear: {absent}\n\n"
                     + "\n\n".join(f"OLD:\n{o}\nNEW:\n{n}" for o, n in edits) + "\n")
        open(os.path.join(d, rel), "w").write(mutated)
        rc2, out2 = run(forge_cmd("-vvvv"), d, os.path.join(WORK, f"{mid}.{TEST}.red.log"))
        fail_lines = [l for l in out2.splitlines() if l.startswith("[FAIL")]
        red = (rc2 != 0 and "[FAIL" in out2 and "Suite result: FAILED" in out2
               and label in out2 and "Ran 1 test for" in out2
               and all(a not in out2 for a in absent))
        hashes(d, f"{mid}.red", hashlog)
        open(os.path.join(d, rel), "w").write(pristine_src)
        rc3, out3 = run(forge_cmd("-vvvv"), d, os.path.join(WORK, f"{mid}.{TEST}.restored.log"))
        rg = rc3 == 0 and f"[PASS] {TEST}()" in out3 and "Ran 1 test for" in out3 \
            and "0 failed" in out3 and "0 skipped" in out3
        hashes(d, f"{mid}.restored", hashlog)
        # tests byte-identical rule: every non-mutated pinned file matches its
        # candidate pin in all three snapshots; the mutated file matches too
        # (restored). Enforced on the recorded hash lines.
        bad = [h for h in hashlog if h.split()[1] != PINS[h.split()[2]]]
        ok = pg and red and rg and not bad
        results.append((mid, "OK" if ok else "FAIL",
                        f"pristine_green={pg} mutant_red_at_named_frame={red} "
                        f"restored_green={rg} tests_byte_identical={not bad} "
                        f"native_exits={(rc, rc2, rc3)} first_fail_line={fail_lines[:1]}"))
        print(f"{mid}: {results[-1][1]} | {results[-1][2]}", flush=True)
    with open(os.path.join(WORK, "hashes.txt"), "w") as fh:
        fh.write("\n".join(hashlog) + "\n")
    print(json.dumps([list(r) for r in results], indent=1))
    sys.exit(1 if any(r[1] != "OK" for r in results) else 0)


if __name__ == "__main__":
    main()
