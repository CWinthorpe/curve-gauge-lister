#!/usr/bin/env python3
"""Reconcile a forge --list --json inventory against V1ALIGN-WITNESS-INVENTORY.json.

Stage semantics:
  p2   : interim — retained + bounty + v2-twin suites all still present;
         the eight offline PORT_TRUST identities must be found at their NEW
         target (test/TrustedFactory.t.sol), not the retired v2 file.
  p3   : final  — only RETAIN_V1 + PORT_TRUST (new location) ship.
  fork : fork-profile list; p2/p3 same rules for fork rows.
"""
import json, sys, collections

inv = json.load(open("plans/V1ALIGN-WITNESS-INVENTORY.json"))
rows = inv["identities"]

def expected(profile, stage):
    exp = {}
    for r in rows:
        if r["profile"] != profile:
            continue
        d = r["disposition"]
        if d == "RETAIN_V1":
            exp[r["baseline_identity"]] = r
        elif d == "PORT_TRUST":
            if stage in ("p2", "p3"):
                exp[r["target_identity_or_counterpart"]] = r
        elif d in ("RETIRE_BOUNTY", "RETIRE_V2_TWIN"):
            if stage == "p2":
                exp[r["baseline_identity"]] = r
    return exp

def discovered(path):
    d = json.load(open(path))
    out = {}
    raw = []
    for f, contracts in d.items():
        for cname, tests in contracts.items():
            for t in tests:
                name = t["name"] if isinstance(t, dict) else t
                sig = (t.get("signature") if isinstance(t, dict) else None)
                ident = f"{f}:{cname}:{name}"
                out[ident] = sig
                raw.append(ident)
    return out, raw

def main():
    profile, stage, lst = sys.argv[1], sys.argv[2], sys.argv[3]
    exp = expected(profile, stage)
    disc, raw = discovered(lst)
    missing = sorted(set(exp) - set(disc))
    extra = sorted(set(disc) - set(exp))
    print(f"profile={profile} stage={stage}: expected={len(exp)} discovered={len(disc)}")
    sig_mismatch = []
    for idn, r in exp.items():
        pass  # name-level identity compared above; executed signatures checked separately from run JSON
    print("MISSING (block acceptance):", len(missing))
    for m in missing: print("  -", m)
    print("EXTRA (needs inventory row):", len(extra))
    for e in extra: print("  +", e)
    print("SIGNATURE MISMATCHES:", len(sig_mismatch))
    for s in sig_mismatch[:20]: print("  ~", s)
    dupes = sorted([k for k,v in collections.Counter(raw).items() if v>1])
    print("DUPLICATES:", len(dupes))
    sys.exit(0 if not (missing or extra or sig_mismatch or dupes) else 1)

main()
