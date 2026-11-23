#!/usr/bin/env python3
"""r3docs census verifier: discovered (--list) and executed (--json) identity
sets under both runs must equal the BINDING.json census EXACTLY (paths,
contracts, signatures), zero failures/skips, no duplicates."""
import json
import re
import sys

R = "/home/winny/.hermes/profiles/qwen-executor/cache/scratch/r3docs"
binding = json.load(open("/home/winny/curve-gauge-lister/review/r3gate/BINDING.json"))


def parse_list(path):
    ids = []
    f = c = None
    for line in open(path):
        if line.startswith("No files changed") or not line.strip():
            continue
        if not line.startswith(" "):
            f = line.strip()
        elif not line.startswith("    "):
            c = line.strip()
        else:
            ids.append(f"{f}:{c}:{line.strip()}()")
    return ids


def parse_json(path, expect_success=True):
    d = json.load(open(path))
    ids, bad = [], []
    for key, val in d.items():
        f, c = key.split(":")
        for tname, t in val.get("test_results", {}).items():
            ids.append(f"{f}:{c}:{tname}")
            if t.get("status") != "Success":
                bad.append((f"{f}:{c}:{tname}", t.get("status")))
    if len(ids) != len(set(ids)):
        bad.append(("DUPLICATE identities", len(ids) - len(set(ids))))
    return set(ids), bad


ok = True
census_def = set(binding["census"]["default"])
census_fork = set(binding["census"]["fork"])

disc_def = parse_list(f"{R}/list-cand-default.txt")
if sorted(disc_def) != sorted(census_def) or len(disc_def) != len(set(disc_def)):
    ok = False
    print("DISCOVERED-DEFAULT mismatch:", set(disc_def) ^ census_def)
print(f"discovered default: {len(disc_def)} == 77 census: {len(disc_def) == 77 and sorted(disc_def) == sorted(census_def)}")

for label, jp in (("run1 RPC-unset", "test-cand-default.json"),
                  ("run2 RPC-unreachable", "test-cand-unreachable.json")):
    ex, bad = parse_json(f"{R}/{jp}")
    if ex != census_def or bad:
        ok = False
        print(f"{label}: executed mismatch {ex ^ census_def} bad {bad}")
    print(f"{label}: executed==census {ex == census_def}, failures/skips {len(bad)}")

disc_fork = parse_list(f"{R}/list-cand-fork.txt")
same = sorted(disc_fork) == sorted(census_fork)
if not same:
    ok = False
    print("DISCOVERED-FORK mismatch:", set(disc_fork) ^ census_fork)
print(f"discovered fork: {len(disc_fork)} == 13 census: {same}")

print("CENSUS GATES", "PASS" if ok else "FAIL")
sys.exit(0 if ok else 1)
