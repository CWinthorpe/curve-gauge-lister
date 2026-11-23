#!/usr/bin/env python3
"""Validate the authority package against retained native evidence; never edit product.

Run at the reviewed baseline with the existing fresh scratch artifacts. Re-running
collectors after implementation would be a NEW baseline, not reproduction of this
candidate. JSON outputs below are derived receipts, not synthesized test output.
"""
import collections
import copy
import hashlib
import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
BASE = json.loads((HERE / "baseline.json").read_text())
CMP = json.loads((HERE / "source-comparison.json").read_text())
MAN = json.loads((ROOT / "plans/V1ALIGN-MANIFEST.json").read_text())
INV = json.loads((ROOT / "plans/V1ALIGN-WITNESS-INVENTORY.json").read_text())


def sha(data):
    return hashlib.sha256(data).hexdigest()


def emit(name, obj):
    (HERE / name).write_text(json.dumps(obj, indent=2) + "\n")


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


def native_inventory(profile):
    inv = json.loads((HERE / ("list-" + profile + ".txt")).read_text())
    identities = [f"{path}:{contract}:{test}" for path, cs in inv.items() for contract, tests in cs.items() for test in tests]
    assert len(identities) == len(set(identities))
    return set(identities)


def pass_inventory(filename):
    text = (HERE / filename).read_text()
    current = None
    result = []
    for line in text.splitlines():
        header = re.fullmatch(r"Ran \d+ tests? for (\S+)", line)
        if header:
            current = header[1]
        passed = re.match(r"\[PASS\] (\S+\([^)]*\))", line)
        if passed:
            assert current is not None
            result.append(current + ":" + passed[1])
        assert not re.match(r"\[(FAIL|SKIP)", line), line
    assert len(result) == len(set(result)), filename + " duplicate executed ID"
    footer = re.search(r"Ran (\d+) test suites? .*?: (\d+) tests passed, (\d+) failed, (\d+) skipped", text)
    assert footer, filename + " missing native final footer"
    assert (int(footer[2]), int(footer[3]), int(footer[4])) == (len(result), 0, 0)
    return set(result), int(footer[1])


assert BASE["candidate"] == CMP["candidate"] == MAN["baseline"] == INV["baseline"]
# All current tracked product/tests/docs/tooling must be byte-identical to the
# pre-authority collection; an unchanged contract subset alone is insufficient.
for path, expected in BASE["source_sha256"].items():
    assert sha((ROOT / path).read_bytes()) == expected, "Product drift: " + path
assert all(command["exit"] == 0 for command in BASE["commands"])

historical_commit = "74e536f32437f9813630f5c89a3427e11c40af29"
historical_files = ["contracts/CurveGaugeLister.sol", "contracts/adapters/VotiumAdapter.sol", "contracts/adapters/VoteMarketAdapter.sol", "contracts/libraries/SafeToken.sol", "contracts/interfaces/IFeeDistributor.sol", "contracts/interfaces/IIncentivePlatform.sol"]
historical = {"historical_local_object": historical_commit, "candidate": BASE["candidate"], "qualification": "Local Git object, not assumed publicly reachable on main; current reviewed candidate hashes are independently retained.", "files": {}}
historical_lookup = subprocess.run(["git", "cat-file", "-e", historical_commit + "^{commit}"], cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
if historical_lookup.returncode == 0:
    historical["status"] = "SIX_RAW_SOURCE_COMPARISONS_REPRODUCED"
    for path in historical_files:
        old = subprocess.check_output(["git", "show", historical_commit + ":" + path], cwd=ROOT)
        current = (ROOT / path).read_bytes()
        assert current == old, path
        historical["files"][path] = {"historical_sha256": sha(old), "candidate_sha256": sha(current), "raw_equal": current == old}
else:
    # Supplementary local-object corroboration is not a hidden dependency of
    # publicly reproducible current-candidate ABI/source/accounting checks.
    historical["status"] = "NOT_REPRODUCED_MISSING_OPTIONAL_LOCAL_OBJECT"
    historical["lookup_exit"] = historical_lookup.returncode
emit("historical-source-check.json", historical)

v1 = BASE["profiles"]["default"]["CurveGaugeLister.sol/CurveGaugeLister.json"]
v2 = BASE["profiles"]["default"]["CurveGaugeListerV2.sol/CurveGaugeListerV2.json"]
a, b = keyed(v1["abi"]), keyed(v2["abi"])
delta = {
    "candidate": BASE["candidate"], "key_policy": "ABI entry type and canonical input signature; changed entries retain complete original objects, including internalType metadata",
    "only_v1": [a[k] for k in sorted(a.keys() - b.keys())],
    "only_v2": [b[k] for k in sorted(b.keys() - a.keys())],
    "common_changed": [{"key": k, "v1": a[k], "v2": b[k]} for k in sorted(a.keys() & b.keys()) if a[k] != b[k]],
    "common_exact_equal": [k for k in sorted(a.keys() & b.keys()) if a[k] == b[k]],
}
emit("abi-delta.json", delta)
expected_abi = copy.deepcopy(v1["abi"])
next(x for x in expected_abi if x["type"] == "constructor")["inputs"].append(copy.deepcopy(next(x for x in v2["abi"] if x["type"] == "constructor")["inputs"][-1]))
additions = {"trustedGaugeValidator", "WrongChain", "UntrustedGauge", "TrustedGaugeCheckFailed"}
expected_abi.extend(copy.deepcopy([x for x in v2["abi"] if x.get("name") in additions]))
assert keyed(expected_abi) == keyed(MAN["abi"])
assert dict(collections.Counter(x["type"] for x in MAN["abi"])) == MAN["counts"] == {"function": 30, "constructor": 1, "event": 10, "error": 33}
expected_methods = dict(v1["methodIdentifiers"], **{"trustedGaugeValidator()": v2["methodIdentifiers"]["trustedGaugeValidator()"]})
assert expected_methods == MAN["methodIdentifiers"]
assert MAN["baseline_v1_storageLayout"] == v1["storageLayout"]
assert set(MAN["remove_product_sources"]) == set(CMP["composed_closures"]["v2_with_bounty"]) - set(CMP["composed_closures"]["v1"]) - {"contracts/interfaces/ITrustedGaugeValidator.sol"}
for path, expected in MAN["unchanged_shared_source_sha256"].items():
    assert sha((ROOT / path).read_bytes()) == expected

routines = CMP["routines"]
routine_counts = {"all": len(routines), "common": sum(bool(r["v1"] and r["v2"]) for r in routines), "raw_equal": sum(r["raw_equal"] for r in routines), "tokens_equal": sum(r["tokens_equal"] for r in routines)}
assert routine_counts == {"all": 35, "common": 32, "raw_equal": 23, "tokens_equal": 28}
assert CMP["accounting_fragments"]["preflight_equal_after_declared_normalization"]
assert CMP["accounting_fragments"]["deposit_and_account_equal_after_declared_normalization"]

size_rows = {}
for profile, artifacts in BASE["profiles"].items():
    size_rows[profile] = {}
    for key, summary in artifacts.items():
        fresh = json.loads((Path(BASE["scratch"]) / profile / "out" / key).read_text())
        runtime = bytes.fromhex(fresh["deployedBytecode"]["object"].removeprefix("0x"))
        creation = bytes.fromhex(fresh["bytecode"]["object"].removeprefix("0x"))
        assert len(runtime) == summary["runtime_bytes"]
        assert len(creation) == summary["creation_bytes"]
        assert sha(runtime) == summary["runtime_sha256_decoded"]
        assert summary["runtime_headroom"] == 24576 - len(runtime)
        assert len(runtime) <= 24576, key
        assert fresh["abi"] == summary["abi"]
        assert fresh["methodIdentifiers"] == summary["methodIdentifiers"]
        assert BASE["profiles"]["default"][key]["abi"] == BASE["profiles"]["fork"][key]["abi"]
        size_rows[profile][key] = {k: summary[k] for k in ("runtime_bytes", "creation_bytes", "runtime_headroom")}
for key, expected in MAN["unchanged_adapter_abi"].items():
    assert keyed(expected) == keyed(BASE["profiles"]["default"][key]["abi"])
    assert MAN["unchanged_adapter_methodIdentifiers"][key] == BASE["profiles"]["default"][key]["methodIdentifiers"]
assert all(all(v.values()) for v in json.loads((HERE / "hardcoded-artifact-check.json").read_text()).values())

log_rows = {}
for profile, filenames in {"default": ["test-default-unset.txt", "test-default-unreachable.txt"], "fork": ["fork-cold.txt", "fork-warm.txt"]}.items():
    native = native_inventory(profile)
    baseline_rows = [r for r in INV["identities"] if r["profile"] == profile]
    assert {r["baseline_identity"] for r in baseline_rows} == native
    assert len(baseline_rows) == len(native) == INV["baseline_counts"][profile]
    counts = dict(collections.Counter(r["disposition"] for r in baseline_rows))
    assert counts == INV["disposition_counts"][profile]
    targets = [r["target_identity_or_counterpart"] for r in baseline_rows if r["disposition"] in ("RETAIN_V1", "PORT_TRUST")]
    assert len(targets) == len(set(targets)) == INV["expected_if_only_this_authorized_identity_plan_is_implemented"][profile]
    executed_signatures = {r["baseline_identity"].rsplit(":", 1)[0] + ":" + r["baseline_signature"] for r in baseline_rows}
    assert len(executed_signatures) == len(native)
    for filename in filenames:
        passed, suites = pass_inventory(filename)
        assert passed == executed_signatures, (filename, executed_signatures - passed, passed - executed_signatures)
        log_rows[filename] = {"passed": len(passed), "failed": 0, "skipped": 0, "suites": suites, "exact_native_identity_set": True}
retained = {r["baseline_identity"] for r in INV["identities"] if r["disposition"] == "RETAIN_V1"}
assert all(r["target_identity_or_counterpart"] in retained for r in INV["identities"] if r["disposition"] == "RETIRE_V2_TWIN")
fork_status = json.loads((HERE / "fork-status.json").read_text())
assert fork_status["candidate"] == BASE["candidate"] and fork_status["initial_rpc_cache_absent"]
assert {r["name"]: r["exit"] for r in fork_status["runs"]} == {"fork-cold": 0, "fork-warm": 0, "fork-unreachable": 1}
for filename in ("fork-cold.txt", "fork-warm.txt"):
    text = (HERE / filename).read_text()
    assert "chainId=0x1 number=0x192d8fb hash=0x55810b079923a14fb97ad548f5024f65530dbc4fb2357a38f41e13b3d27cb6d3 timestamp=0x6af61657" in text
    assert "VERIFIED — proceeding" in text
unreachable = (HERE / "fork-unreachable.txt").read_text()
assert "BLOCKED: RPC" in unreachable and "refusing to run fork tests" in unreachable
assert "[PASS]" not in unreachable and not re.search(r"Ran \d+ tests? for", unreachable)

# Exact executor payloads are independently extractable; do not apply here.
deltas = (ROOT / "plans/V1ALIGN-DOC-DELTAS.md").read_text()
blocks = re.findall(r"^BEGIN_FILE ([^\n]+)\n(.*?)^END_FILE \1$", deltas, re.M | re.S)
assert len(blocks) == 5
replacements = dict(blocks)
assert set(replacements) == {"README.md", "docs/CURVE-PROPOSAL.md", "docs/ABI.md", "docs/OPERATIONS.md", "docs/DEPLOYMENT-PINS.md"}
for path, text in replacements.items():
    assert text.endswith("\n") and text.startswith("# ")
    assert text.count("```") % 2 == 0, path
    for removed in ("GaugeBounty", "reporterReward", "rewardReportId", "creditReward", "1,000", "floor(R/2)", "BOUNTY-ABI.md", "BOUNTY-OPERATIONS.md"):
        assert removed not in text, (path, removed)
old_match = re.search(r"^BEGIN_OLD_INTEL\n(.*?)^END_OLD_INTEL$", deltas, re.M | re.S)
new_match = re.search(r"^BEGIN_NEW_INTEL\n(.*?)^END_NEW_INTEL$", deltas, re.M | re.S)
assert old_match is not None and new_match is not None
old_intel = old_match[1]
new_intel = new_match[1]
intel = (ROOT / "docs/INTEL-YB-HELPERS.md").read_text()
assert intel.count(old_intel) == 1
replacements["docs/INTEL-YB-HELPERS.md"] = intel.replace(old_intel, new_intel)
replacement_hashes = {path: {"sha256": sha(text.encode()), "bytes": len(text.encode()), "lines": len(text.splitlines())} for path, text in replacements.items()}
emit("documentation-replacements.json", {"authority": "plans/V1ALIGN-DOC-DELTAS.md", "status": "TARGET TEXT HASHES ONLY; not applied to current product docs", "replacement_sha256": replacement_hashes, "delete": ["docs/BOUNTY-ABI.md", "docs/BOUNTY-OPERATIONS.md"]})

# Compute every signature rather than trusting literals or compiler-name counts.
selector_rows = {}
for sig in ("trustedGaugeValidator()", "validateGauge(address)", "UntrustedGauge(address)", "TrustedGaugeCheckFailed(address)"):
    value = subprocess.check_output(["cast", "sig", sig], cwd=ROOT, text=True).strip()
    assert value in replacements["docs/ABI.md"], (sig, value)
    selector_rows[sig] = value
assert selector_rows["trustedGaugeValidator()"] == "0x" + MAN["methodIdentifiers"]["trustedGaugeValidator()"]

# A nonwriting formatter check; capture failures instead of interpreting silence.
fmt = subprocess.run(["forge", "fmt", "--check"], cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
(HERE / "fmt-check.txt").write_text(fmt.stdout)
assert fmt.returncode == 0, "baseline forge fmt --check failed; see fmt-check.txt"
report = {
    "candidate": BASE["candidate"], "status": "AUTHORITY PACKAGE VALIDATED; NOT FUTURE IMPLEMENTATION ACCEPTANCE",
    "baseline_source_hashes_unchanged": len(BASE["source_sha256"]),
    "routine_counts": routine_counts, "full_target_abi_derivation_equal": True,
    "expected_target_census": INV["expected_if_only_this_authorized_identity_plan_is_implemented"],
    "actual_log_census": log_rows, "fork_unreachable_failed_before_tests": True,
    "profile_sizes_redecoded": size_rows, "selectors": selector_rows,
    "documentation_replacement_hashes": replacement_hashes,
    "formatter": {"argv": ["forge", "fmt", "--check"], "exit": fmt.returncode},
    "deployment_approved": False, "product_implemented": False,
}
emit("authority-check.json", report)
print(json.dumps({k: report[k] for k in ("status", "baseline_source_hashes_unchanged", "routine_counts", "expected_target_census", "actual_log_census", "selectors", "formatter")}, indent=2))
