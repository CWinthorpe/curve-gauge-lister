#!/usr/bin/env python3
"""G3: native list + two offline runs (MAINNET_RPC_URL unset, then explicitly
http://127.0.0.1:1), with PASS==discovered==approved-inventory enforcement.
Run inside the isolated candidate checkout (fresh default out/ built there,
not a redirected build over a stale out/)."""
import json, os, re, subprocess, sys
from pathlib import Path

ROOT = Path(os.environ.get("CGL_CANDIDATE", Path.cwd())).resolve()
INV = json.loads((ROOT / "plans/V1ALIGN-WITNESS-INVENTORY.json").read_text())
EVID = ROOT / "gates-out"
EVID.mkdir(exist_ok=True)

def approved(profile):
    out = set()
    for r in INV["identities"]:
        if r["profile"] != profile:
            continue
        if r["disposition"] == "RETAIN_V1":
            out.add(r["baseline_identity"])
        elif r["disposition"] == "PORT_TRUST":
            out.add(r["target_identity_or_counterpart"])
    return out

def listed(profile):
    env = dict(os.environ)
    if profile == "fork":
        env["FOUNDRY_PROFILE"] = "fork"
    r = subprocess.run(["forge", "test", "--offline", "--list", "--json"], cwd=ROOT, env=env,
                       capture_output=True, text=True)
    assert r.returncode == 0, r.stderr
    d = json.loads(r.stdout)
    ids = set(f"{f}:{c}:{t}" for f, cs in d.items() for c, ts in cs.items() for t in ts)
    (EVID / f"list-{profile}.json").write_text(r.stdout)
    return ids

def parse_passes(text):
    passed, current = [], None
    for line in text.splitlines():
        h = re.fullmatch(r"Ran \d+ tests? for (\S+)", line)
        if h:
            current = h[1]
        p = re.match(r"\[PASS\] (\S+\([^)]*\))", line)
        if p:
            assert current is not None
            passed.append(current + ":" + p[1])
        assert not re.match(r"\[(FAIL|SKIP)", line), "failing/skipped line: " + line
    footer = re.search(r"Ran (\d+) test suites? .*?: (\d+) tests passed, (\d+) failed, (\d+) skipped", text)
    assert footer, "missing native final footer"
    assert (int(footer[2]), int(footer[3]), int(footer[4])) == (len(passed), 0, 0), "footer/count mismatch"
    return set(passed), int(footer[1])

def run_offline(tag, rpc_mode):
    env = dict(os.environ)
    if rpc_mode == "unset":
        env.pop("MAINNET_RPC_URL", None)
    else:
        env["MAINNET_RPC_URL"] = "http://127.0.0.1:1"
    r = subprocess.run(["forge", "test", "--offline", "-vvv"], cwd=ROOT, env=env,
                       capture_output=True, text=True)
    (EVID / f"test-{tag}.txt").write_text("$ forge test --offline -vvv\n\n" + r.stdout + "\n--stderr--\n" + r.stderr)
    if r.returncode != 0:
        print(r.stdout[-4000:])
        sys.exit(f"G3 {tag}: forge test exited {r.returncode}")
    sigs, suites = parse_passes(r.stdout)
    (EVID / f"test-{tag}.ids.json").write_text(json.dumps(sorted(sigs), indent=1))
    return sigs, suites

def bare(ids):
    return {i.rsplit(":", 1)[0] + ":" + i.rsplit(":", 1)[1].split("(")[0] for i in ids}

def main():
    failures = []
    exp = approved("default")
    listing = listed("default")
    if listing != exp:
        failures.append(f"G3 list: missing={sorted(exp-listing)[:8]} extra={sorted(listing-exp)[:8]}")
    if any(i.startswith("fork/") for i in listing):
        failures.append("G3: default profile lists fork runners")
    for tag, mode in (("unset", "unset"), ("unreachable", "unreachable")):
        sigs, suites = run_offline(tag, mode)
        if bare(sigs) != listing:
            failures.append(f"G3 {tag}: PASS ids != discovered ids (missing {sorted(listing-bare(sigs))[:5]} extra {sorted(bare(sigs)-listing)[:5]})")
        if any(i.startswith("fork/") for i in sigs):
            failures.append(f"G3 {tag}: executed fork identities under default profile")
    summary = {"default_listed": len(listing), "expected_approved": len(exp)}
    for tag in ("unset", "unreachable"):
        ids = json.loads((EVID / f"test-{tag}.ids.json").read_text())
        summary[f"pass_{tag}"] = len(ids)
    print(json.dumps(summary, indent=1))
    if failures:
        print("\n".join(failures), file=sys.stderr)
        sys.exit(1)
    print("G3 OK", file=sys.stderr)

main()
