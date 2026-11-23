#!/usr/bin/env python3
"""Exhaustive function-token comparison; no product writes."""
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
LEX = re.compile(r'//[^\n]*|/\*.*?\*/|"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|[A-Za-z_$][\w$]*|0x[\da-fA-F]+|\d[\w]*|>>=|<<=|\*\*|&&|\|\||==|!=|<=|>=|\+\+|--|\+=|-=|\*=|/=|%=|&=|\|=|\^=|<<|>>|=>|:=|->|[^\s]', re.S)


def tokens(s):
    return [(m.group(), m.start(), m.end()) for m in LEX.finditer(s) if not m.group().startswith(("//", "/*"))]


def routines(s):
    ts = tokens(s)
    found = {}
    for i, (t, start, _) in enumerate(ts):
        if t not in ("function", "constructor", "modifier"):
            continue
        name = ts[i + 1][0] if t != "constructor" else "constructor"
        j = i
        while ts[j][0] not in ("{", ";"):
            j += 1
        if ts[j][0] == ";":
            continue
        depth = 1
        k = j + 1
        while depth:
            depth += (ts[k][0] == "{") - (ts[k][0] == "}")
            k += 1
        raw = s[start:ts[k - 1][2]]
        assert name not in found, "Overloaded/nested routine requires signature-keyed comparison: " + name
        found[name] = {"line": s[:start].count("\n") + 1, "end_line": s[:ts[k - 1][2]].count("\n") + 1, "raw": raw, "tokens": [x[0] for x in ts[i:k]]}
    return found


def sha(s):
    return hashlib.sha256(s.encode()).hexdigest()


p1 = "contracts/CurveGaugeLister.sol"
p2 = "contracts/CurveGaugeListerV2.sol"
s1, s2 = (ROOT / p1).read_text(), (ROOT / p2).read_text()
r1, r2 = routines(s1), routines(s2)
out = {"candidate": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(), "files": {p1: sha(s1), p2: sha(s2)}, "method": "raw UTF-8 bytes and Solidity lexical tokens; only whitespace/comments omitted from token equality; strings preserved", "routines": []}
for name in sorted(r1.keys() | r2.keys()):
    a, b = r1.get(name), r2.get(name)
    row = {"name": name, "raw_equal": bool(a and b and a["raw"] == b["raw"]), "tokens_equal": bool(a and b and a["tokens"] == b["tokens"])}
    for label, v in (("v1", a), ("v2", b)):
        row[label] = None if v is None else {"line": v["line"], "end_line": v["end_line"], "raw_sha256": sha(v["raw"]), "token_sha256": sha(json.dumps(v["tokens"], separators=(",", ":")))}
    out["routines"].append(row)
# Exact accepted accounting fragments after explicitly listed identifier/constant substitution.
lib = (ROOT / "contracts/libraries/FeeDistributorAccounting.sol").read_text()
lr = routines(lib)
v1_pre = s1[s1.index("        if (fd.code.length", s1.index("function _confiscate")):s1.index("        // Step 3: effects", s1.index("function _confiscate"))]
v1_post = s1[s1.index("        uint256 listerBefore", s1.index("function _confiscate")):s1.index("        // Step 6: custody", s1.index("function _confiscate"))]
lib_pre = lr["preflight"]["raw"].split("{", 1)[1].rsplit("}", 1)[0]
lib_post = lr["depositAndAccount"]["raw"].split("{", 1)[1].rsplit("}", 1)[0]
substitutions = {"crvUSD": "token", "listerBefore": "senderBefore", "epochStart(t)": "BountyScripts.weekFloor(t)", "20 * WEEK": "ACCOUNTING_HORIZON_WEEKS * WEEK"}

def norm(s):
    for old, new in substitutions.items():
        s = s.replace(old, new)
    s = re.sub(r"\{\s*revert DistributorUnusable\(\);\s*\}", "revert DistributorUnusable();", s)
    return [x[0] for x in tokens(s)]
out["accounting_fragments"] = {"substitutions_v1_to_library": substitutions, "brace_normalization": "unwrap a block containing only revert DistributorUnusable(); on both sides", "preflight_equal_after_declared_normalization": norm(v1_pre) == norm(lib_pre), "deposit_and_account_equal_after_declared_normalization": norm(v1_post) == norm(lib_post), "v1_preflight_raw_sha256": sha(v1_pre), "library_preflight_raw_sha256": sha(lib_pre), "v1_postflight_raw_sha256": sha(v1_post), "library_postflight_raw_sha256": sha(lib_post)}
# Import closure by actual relative imports, including interfaces and internal libraries.
tracked = subprocess.check_output(["git", "ls-files", "contracts", "test", "fork"], cwd=ROOT, text=True).splitlines()
graph = {}
for p in tracked:
    if not p.endswith(".sol"):
        continue
    text = (ROOT / p).read_text()
    graph[p] = [str(((ROOT / p).parent / dep).resolve().relative_to(ROOT)) for dep in re.findall(r'import\s+(?:[^;]*?from\s+)?["\']([^"\']+)["\']\s*;', text)]

def closure(seeds):
    seen = set()
    stack = list(seeds)
    while stack:
        p = stack.pop()
        if p in seen:
            continue
        seen.add(p)
        stack.extend(graph.get(p, []))
    return sorted(seen)
shared_seeds = ["contracts/adapters/VotiumAdapter.sol", "contracts/adapters/VoteMarketAdapter.sol"]
out["composed_closures"] = {"v1": closure([p1] + shared_seeds), "v2_with_bounty": closure([p2, "contracts/GaugeBounty.sol"] + shared_seeds)}
out["import_graph"] = graph
(HERE / "source-comparison.json").write_text(json.dumps(out, indent=2) + "\n")
print(json.dumps({"routines": [{k: row[k] for k in ("name", "raw_equal", "tokens_equal")} for row in out["routines"]], "accounting": out["accounting_fragments"], "closures": out["composed_closures"]}, indent=2))
