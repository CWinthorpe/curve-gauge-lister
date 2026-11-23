#!/usr/bin/env python3
"""G2/G5 executor gate: fresh-ABI/manifest + layout + adapter + size comparators.

Run from a clean isolated checkout (no pre-existing out/cache) AFTER both
profile builds. Mirrors the authority comparator logic (keyed full-entry ABI
comparison; recursive storage layout after stripping only compiler AST/type
IDs). Fails on the first disagreement.
"""
import collections, hashlib, json, os, re, subprocess, sys
from pathlib import Path

ROOT = Path(os.environ.get("CGL_CANDIDATE", Path.cwd())).resolve()
MAN = json.loads((ROOT / "plans/V1ALIGN-MANIFEST.json").read_text())
OUT = {"default": ROOT / "out", "fork": ROOT / "out-fork"}
KEY = "CurveGaugeLister.sol/CurveGaugeLister.json"
ADAPTERS = ["VotiumAdapter.sol/VotiumAdapter.json", "VoteMarketAdapter.sol/VoteMarketAdapter.json"]
REPORT = {}

def sha(b): return hashlib.sha256(b).hexdigest()

def canon_type(item):
    if item["type"].startswith("tuple"):
        return "(" + ",".join(canon_type(v) for v in item["components"]) + ")" + item["type"][5:]
    return item["type"]

def signature(entry):
    return entry.get("name", entry["type"]) + "(" + ",".join(canon_type(v) for v in entry.get("inputs", [])) + ")"

def keyed(abi):
    result = {(entry["type"], signature(entry)): entry for entry in abi}
    assert len(result) == len(abi), "Duplicate full-ABI entry"
    return result

def strip_ids_layout(layout):
    """Recursively strip compiler astIds and numeric type-id suffixes only."""
    def strip_typeid(t):
        # Strip compiler type-id numbers only (…)_N_storage suffixes and
        # trailing enum ids like t_enum(Status)22. No t_array length tokens
        # occur in this layout, so array lengths (a real encoding fact) are
        # never touched.
        t = re.sub(r"\)\d+(_storage)", ")\1", t)
        t = re.sub(r"\)\d+$", ")", t)
        return t
    out = {"storage": [], "types": {}}
    for row in layout["storage"]:
        r = dict(row)
        r.pop("astId", None); r.pop("contract", None)
        r["type"] = strip_typeid(r["type"])
        out["storage"].append(r)
    for t, defn in layout["types"].items():
        d = dict(defn)
        members = []
        for m in d.get("members", []):
            mm = dict(m); mm.pop("astId", None); mm.pop("contract", None)
            mm["type"] = strip_typeid(mm["type"])
            members.append(mm)
        if "members" in d: d["members"] = members
        for k in ("key", "value"):
            if k in d: d[k] = strip_typeid(d[k])
        out["types"][strip_typeid(t)] = d
    # sort storage by slot/offset for order-insensitive comparison
    out["storage"].sort(key=lambda r: (int(r["slot"]), r["offset"], r["label"]))
    out["types"] = {strip_typeid(k): v for k, v in sorted(out["types"].items())}
    return out

def main():
    failures = []
    for profile in ("default", "fork"):
        art = json.loads((OUT[profile] / KEY).read_text())
        # -- G2: full ABI comparison, entry-order-normalized --
        a, m = keyed(art["abi"]), keyed(MAN["abi"])
        if a != m:
            only_a, only_m = sorted(set(a) - set(m)), sorted(set(m) - set(a))
            changed = [k for k in sorted(set(a) & set(m)) if a[k] != m[k]]
            failures.append(f"G2/{profile}: ABI mismatch only_artifact={only_a[:5]} only_manifest={only_m[:5]} changed={changed[:5]}")
        counts = dict(collections.Counter(x["type"] for x in art["abi"]))
        if counts != MAN["counts"]:
            failures.append(f"G2/{profile}: counts {counts} != {MAN['counts']}")
        if art["methodIdentifiers"] != MAN["methodIdentifiers"]:
            failures.append(f"G2/{profile}: methodIdentifiers mismatch")
        for sig in ("bounty()", "listingId(address)"):
            if sig in art["methodIdentifiers"]:
                failures.append(f"G2/{profile}: bounty capability present: {sig}")
        # -- G2: recursive storage layout vs baseline V1 layout --
        if strip_ids_layout(art["storageLayout"]) != strip_ids_layout(MAN["baseline_v1_storageLayout"]):
            failures.append(f"G2/{profile}: storage layout mismatch")
        # -- G2: adapters equal to same-profile baseline --
        for key in ADAPTERS:
            j = json.loads((OUT[profile] / key).read_text())
            if keyed(j["abi"]) != keyed(MAN["unchanged_adapter_abi"][key]):
                failures.append(f"G2/{profile}: adapter ABI drift {key}")
            if j["methodIdentifiers"] != MAN["unchanged_adapter_methodIdentifiers"][key]:
                failures.append(f"G2/{profile}: adapter methodIdentifiers drift {key}")
            runtime = bytes.fromhex(j["deployedBytecode"]["object"].removeprefix("0x"))
            exp = MAN["unchanged_adapter_runtime_by_profile"][profile][key]
            if len(runtime) != exp["runtime_bytes"] or sha(runtime) != exp["runtime_sha256_decoded"]:
                failures.append(f"G2/{profile}: adapter runtime drift {key}")
            # -- G5: independent decode + ceiling, metadata counted --
            if "__" in j["deployedBytecode"]["object"]:
                failures.append(f"G5/{profile}: unresolved placeholder in {key}")
        # -- G5: core sizes --
        for key in [KEY] + ADAPTERS:
            j = json.loads((OUT[profile] / key).read_text())
            obj = j["deployedBytecode"]["object"].removeprefix("0x")
            if re.search(r"__", obj):
                failures.append(f"G5/{profile}: unresolved placeholders in {key}")
            runtime = bytes.fromhex(obj)
            creation = bytes.fromhex(j["bytecode"]["object"].removeprefix("0x"))
            REPORT.setdefault(profile, {})[key] = {
                "runtime_bytes": len(runtime),
                "runtime_headroom": 24576 - len(runtime),
                "creation_bytes": len(creation),
                "runtime_sha256": sha(runtime),
            }
            if len(runtime) > 24576:
                failures.append(f"G5/{profile}: RUNTIME CEILING BREACH {key}: {len(runtime)}")
        # -- G5: forge build --sizes exit 0 recorded separately --
    # -- G2: forbidden product tokens in shipping sources --
    for path in MAN["shipping_product_sources"]:
        text = (ROOT / path).read_text()
        for tok in MAN["forbidden_product_tokens"]:
            if tok in text:
                failures.append(f"G2: forbidden token {tok!r} in shipping source {path}")
    # -- G2: import closure of shipping sources --
    removed = set(MAN["remove_product_sources"])
    def imports_of(path):
        text = (ROOT / path).read_text()
        return re.findall(r'import\s+(?:\{[^}]*\}|\*|[\w"]+)?\s*(?:from\s+)?"([^"]+)"', text, re.S)
    closure = {}
    for path in MAN["shipping_product_sources"]:
        deps = []
        for imp in imports_of(path):
            p = (ROOT / Path(path).parent / imp).resolve().relative_to(ROOT)
            deps.append(str(p))
        closure[path] = deps
        for d in deps:
            if d in removed:
                failures.append(f"G2: shipping import of retired dependency {d} via {path}")
    REPORT["import_closure"] = closure
    REPORT["sizes"] = REPORT.get("default"), REPORT.get("fork")
    print(json.dumps(REPORT, indent=1))
    if failures:
        print("\n".join(failures), file=sys.stderr)
        sys.exit(1)
    print("G2+G5 COMPARATORS: ALL EQUAL", file=sys.stderr)

main()
