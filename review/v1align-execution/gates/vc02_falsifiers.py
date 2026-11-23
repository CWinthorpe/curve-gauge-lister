#!/usr/bin/env python3
"""VC-02 closure attempt — F-NB-HORIZON per-offset cell execution.

Authority: review/V1ALIGN-CONF.md VC-02 "Required disposition" and
plans/V1ALIGN-WITNESSES.md:76 (`test_AuditM01_AccountingHorizonIncludes
PartialWeekEdges` / H+1 near-end cursor). The mutant is the authorized
single product edit `epochStart(t)` -> `t` in the Step-2 freshness bound
(contracts/CurveGaugeLister.sol:767).

The named near-end cell is the loop iteration oi=2 (cursor =
T0 + 70*WEEK + WEEK - 1 = 1837382399, T0 = 1794441600, WEEK = 604800).
Under the mutant the earlier oi=1 iteration (cursor 1818633601) fails its
H+1 `expectRevert(DistributorUnusable())` probe ("next call did not revert
as expected") and forge-std assertions abort the test function, so oi=2
never executes.

The brief's primary disposition is to split the mutant run into per-offset
selected executions "if the test structure permits via --match-contract/
--match-test selection only — no test edits". This generator proves the
selection granularity mechanically:

  probe-list            --list --json: exactly ONE compiled identity covers
                        the three cells; no per-offset identities exist.
  probe-sel-cell0/1/2   --match-test attempts for single-offset selection:
                        all empty selections (no test executed) -> per-offset
                        CLI selection is impossible without test edits.
  mutant run            pristine/red/restored of the one whole-identity
                        selection (native exits 0/1/0) with -vvvv traces
                        used for per-cell EXECUTION ATTRIBUTION:
                        pristine executes all 9 probes (setLastTokenTime
                        frames 1800489600 x3, 1818633601 x3, 1837382399 x3);
                        red executes cells 0 and 1 only (six setLastTokenTime
                        frames) and NEVER the near-end cursor; restored
                        executes all 9 again.

The unreachable WEEK-1 cell therefore follows the brief's second branch:
impossibility evidence published here + AMENDMENT-REQUEST-VC02.md routed
to the review authority (no self-approval).
"""
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys

CAND = os.environ["CGL_CANDIDATE"]
WORK = os.environ.get("CGL_FALSIFY_WORK", "/home/winny/tmp-scratch/v1align-fix-vc02")
CL = "contracts/CurveGaugeLister.sol"
SUITE_FILE = "test/Settlement.t.sol"
CONTRACT = "SettlementTest"
TEST = "test_AuditM01_AccountingHorizonIncludesPartialWeekEdges"
EDIT = [
    (
        "        if (block.timestamp - epochStart(t) > 20 * WEEK) revert DistributorUnusable();",
        "        if (block.timestamp - t > 20 * WEEK) revert DistributorUnusable(); // MUTANT F-NB-HORIZON (freshness bound keyed to raw cursor)",
    ),
]

# Cell frames (T0 = 1794441600, WEEK = 604800): cursor set by
# MockFeeDistributor::setLastTokenTime; probe times by VM::warp.
CELLS = {
    "cell0_offset0": {"cursor": "1800489600", "warps": ["1812585599", "1812585600", "1812585601"]},
    "cell1_offset1": {"cursor": "1818633601", "warps": ["1830729599", "1830729600", "1830729601"]},
    "cell2_weekminus1": {"cursor": "1837382399", "warps": ["1848873599", "1848873600", "1848873601"]},
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


def forge_cmd(testsel):
    return (f"forge test --offline --match-path {SUITE_FILE} "
            f"--match-contract '^{CONTRACT}$' --match-test '{testsel}' -vvvv 2>&1")


def frames(text):
    """(cursor, warp) execution frame counts from a -vvvv log.

    Forge traces print numeric arguments as `name(DECIMAL [approx])`, so match
    the frame opener prefix up to the exact decimal (no closing paren).
    """
    out = {}
    for name, c in CELLS.items():
        out[name] = {
            "cursor_frames": text.count(f"setLastTokenTime({c['cursor']}"),
            "warp_frames": {w: text.count(f"warp({w}") for w in c["warps"]},
        }
    return out


def main():
    os.makedirs(WORK, exist_ok=True)
    d = os.path.join(WORK, "copy_horizon")
    if os.path.exists(d):
        shutil.rmtree(d)
    shutil.copytree(CAND, d, ignore=shutil.ignore_patterns(
        "out", "out-fork", "cache", "cache-fork", ".git", "gates-out"))
    src = open(os.path.join(d, CL)).read()

    # -- selection inventory probe: how many compiled identities cover the loop
    rcL, outL = run("forge test --offline --list --json", d,
                    os.path.join(WORK, f"{TEST}.probe-list.json.log"))
    # `--list --json` shape: {"<file>": {"<Contract>": ["<name>", ...]}}.
    # Count compiled identities covering the loop function.
    hits = set()
    try:
        start = outL.index("{")
        doc = json.JSONDecoder().raw_decode(outL[start:])[0]
        for fkey, cmap in doc.items():
            if not isinstance(cmap, dict):
                continue
            for ckey, names in cmap.items():
                for n in names if isinstance(names, list) else []:
                    if isinstance(n, str) and (n == TEST or n.startswith(TEST + "(")):
                        hits.add(f"{fkey}:{ckey}:{n}()")
    except (ValueError, AttributeError, TypeError):
        for tok in re.findall(re.escape(TEST) + r"[^\",}\]]*", outL):
            hits.add(tok + "()")
    n_identities = len(hits)
    inventory_hits = sorted(hits)

    # -- pristine / red / restored with the only possible (whole-function) selection
    rc1, out1 = run(forge_cmd(f"^{TEST}\\(\\)$"), d, os.path.join(WORK, f"{TEST}.pristine.log"))
    pg = rc1 == 0 and f"[PASS] {TEST}()" in out1 and "Ran 1 test for" in out1 \
        and "0 failed" in out1 and "0 skipped" in out1
    fr_pris = frames(out1)

    mutated = src
    for old, new in EDIT:
        mutated = sub(mutated, old, new)
    open(os.path.join(WORK, f"{TEST}.patch.txt"), "w").write(
        f"file: {CL}\nselected: {SUITE_FILE}:{CONTRACT}:{TEST}()\n\n"
        + "\n\n".join(f"OLD:\n{o}\nNEW:\n{n}" for o, n in EDIT) + "\n")
    open(os.path.join(d, CL), "w").write(mutated)

    rc2, out2 = run(forge_cmd(f"^{TEST}\\(\\)$"), d, os.path.join(WORK, f"{TEST}.red.log"))
    fail_lines = [l for l in out2.splitlines() if l.startswith("[FAIL")]
    red = (rc2 != 0 and "[FAIL" in out2 and "Suite result: FAILED" in out2
           and "did not revert" in out2 and "Ran 1 test for" in out2)
    fr_red = frames(out2)

    # -- per-offset selection attempts under the mutant (the brief's split route)
    probe_sel = {}
    for name in ("cell0_offset0", "cell1_offset1", "cell2_weekminus1"):
        # every selector naming only a single offset path: such identities do
        # not exist in the compiled inventory, so the run selects nothing.
        sel = f"^{TEST}\\[{name}\\]\\(\\)$"
        rcp, outp = run(forge_cmd(sel), d,
                        os.path.join(WORK, f"{TEST}.probe-sel-{name}.log"))
        probe_sel[name] = {
            "rc": rcp,
            "executed_any_test": ("Ran 1 test for" in outp or "[PASS]" in outp or "[FAIL" in outp),
        }

    # restored
    open(os.path.join(d, CL), "w").write(src)
    rc3, out3 = run(forge_cmd(f"^{TEST}\\(\\)$"), d, os.path.join(WORK, f"{TEST}.restored.log"))
    rg = rc3 == 0 and f"[PASS] {TEST}()" in out3 and "Ran 1 test for" in out3 \
        and "0 failed" in out3 and "0 skipped" in out3
    fr_rest = frames(out3)

    hash_ok = all(
        hashlib.sha256(open(os.path.join(d, p), "rb").read()).hexdigest() == PINS[p]
        for p in PIN_FILES)

    # -- adjudication: the named near-end cell is UNREACHABLE under the mutant
    # within the permitted selection mechanism.
    near_end_executed_in_red = fr_red["cell2_weekminus1"]["cursor_frames"] > 0
    cells01_executed_in_red = (fr_red["cell0_offset0"]["cursor_frames"] == 3
                               and fr_red["cell1_offset1"]["cursor_frames"] == 3)
    near_end_executed_in_pristine = (fr_pris["cell2_weekminus1"]["cursor_frames"] == 3
                                     and fr_rest["cell2_weekminus1"]["cursor_frames"] == 3)
    all_sel_empty = all(not v["executed_any_test"] for v in probe_sel.values())

    verdict = ("UNREACHABLE_FOR_MUTANT_CLASS"
               if (pg and red and rg and hash_ok and not near_end_executed_in_red
                   and cells01_executed_in_red and near_end_executed_in_pristine
                   and all_sel_empty and n_identities == 1)
               else "REVIEW")
    record = {
        "selected_identity": f"{SUITE_FILE}:{CONTRACT}:{TEST}()",
        "compiled_identities_covering_loop": n_identities,
        "identity_strings": inventory_hits,
        "native_exits_pristine_red_restored": [rc1, rc2, rc3],
        "pristine_green": pg, "mutant_red": red, "restored_green": rg,
        "tests_and_product_byte_identical_to_candidate_after_restore": hash_ok,
        "first_fail_line_red": fail_lines[:1],
        "cell_execution_frames": {"pristine": fr_pris, "red": fr_red, "restored": fr_rest},
        "per_offset_selection_attempts": probe_sel,
        "near_end_cursor_1837382399_frames_in_red":
            fr_red["cell2_weekminus1"]["cursor_frames"],
        "verdict": verdict,
    }
    with open(os.path.join(WORK, f"{TEST}.attribution.json"), "w") as fh:
        json.dump(record, fh, indent=1)
    print(json.dumps(record, indent=1))
    sys.exit(0 if verdict == "UNREACHABLE_FOR_MUTANT_CLASS" else 1)


if __name__ == "__main__":
    main()
