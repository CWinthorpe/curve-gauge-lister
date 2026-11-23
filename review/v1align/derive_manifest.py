#!/usr/bin/env python3
"""Derive the normative target ABI and exact test disposition from native baseline artifacts."""
import collections
import copy
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
b = json.loads((HERE / "baseline.json").read_text())
s = json.loads((HERE / "source-comparison.json").read_text())
p = b["profiles"]["default"]
v1 = p["CurveGaugeLister.sol/CurveGaugeLister.json"]
v2 = p["CurveGaugeListerV2.sol/CurveGaugeListerV2.json"]
abi = copy.deepcopy(v1["abi"])
ctor = next(x for x in abi if x["type"] == "constructor")
ctor["inputs"].append(copy.deepcopy(next(x for x in v2["abi"] if x["type"] == "constructor")["inputs"][-1]))
new_names = {"trustedGaugeValidator", "WrongChain", "UntrustedGauge", "TrustedGaugeCheckFailed"}
abi.extend(copy.deepcopy([x for x in v2["abi"] if x.get("name") in new_names]))
methods = dict(v1["methodIdentifiers"])
methods["trustedGaugeValidator()"] = v2["methodIdentifiers"]["trustedGaugeValidator()"]
manifest = {
    "authority": "plans/V1ALIGN-PLAN.md", "baseline": b["candidate"],
    "status": "NORMATIVE TARGET, derived from baseline ABIs; NOT a compiled or accepted implementation",
    "contract": "contracts/CurveGaugeLister.sol:CurveGaugeLister", "abi_order": "Compare full entry objects after sorting by canonical signature and type; preserve tuple component order, names, internalType, mutability, event indexing and constructor order.",
    "abi": abi, "methodIdentifiers": dict(sorted(methods.items())),
    "counts": dict(collections.Counter(x["type"] for x in abi)),
    "constructor_policy": {"chainid": 1, "first_error": "WrongChain()", "paused_start": True, "trusted_validator_argument_index_1_based": 7, "validator_default": None, "validator_setter": None},
    "unchanged_adapter_abi": {key: p[key]["abi"] for key in ("VotiumAdapter.sol/VotiumAdapter.json", "VoteMarketAdapter.sol/VoteMarketAdapter.json")},
    "unchanged_adapter_methodIdentifiers": {key: p[key]["methodIdentifiers"] for key in ("VotiumAdapter.sol/VotiumAdapter.json", "VoteMarketAdapter.sol/VoteMarketAdapter.json")},
    "storage_policy": "V1 recursive slots, offsets, widths and field order unchanged. Ignore compiler AST IDs and contract-qualified type IDs only after recursive normalization. New validator is immutable, not storage.",
    "baseline_v1_storageLayout": v1["storageLayout"],
    "shipping_product_sources": sorted(s["composed_closures"]["v1"] + ["contracts/interfaces/ITrustedGaugeValidator.sol"]),
    "remove_product_sources": sorted(set(s["composed_closures"]["v2_with_bounty"]) - set(s["composed_closures"]["v1"]) - {"contracts/interfaces/ITrustedGaugeValidator.sol"}),
    "forbidden_product_tokens": ["GaugeBounty", "CurveGaugeListerV2", "IGaugeBounty", "ICurveGaugeListerV2", "FeeDistributorAccounting", "BountyScripts", "BountyRead", "BountyConfig", "ReportView", "reporterReward", "rewardReportId", "listingId"],
    "unchanged_shared_source_sha256": {k: b["source_sha256"][k] for k in s["composed_closures"]["v1"] if k != "contracts/CurveGaugeLister.sol"},
    "unchanged_adapter_runtime_by_profile": {profile: {k: {field: data[k][field] for field in ("runtime_bytes", "runtime_sha256_decoded")} for k in ("VotiumAdapter.sol/VotiumAdapter.json", "VoteMarketAdapter.sol/VoteMarketAdapter.json")} for profile, data in b["profiles"].items()},
}
(ROOT / "plans/V1ALIGN-MANIFEST.json").write_text(json.dumps(manifest, indent=2) + "\n")
rows = []
for profile in ("default", "fork"):
    inv = json.loads((HERE / ("list-" + profile + ".txt")).read_text())
    for path, contracts in inv.items():
        for contract, tests in contracts.items():
            for test in tests:
                old = f"{path}:{contract}:{test}"
                new = old
                reason = "Retain exact identity; only authorized fixture/config migration and additive witness cells."
                disposition = "RETAIN_V1"
                if path == "test/v2/TrustedFactory.t.sol":
                    new = old.replace("test/v2/TrustedFactory.t.sol", "test/TrustedFactory.t.sol")
                    disposition = "PORT_TRUST"
                    reason = "Retain test/contract names and all non-bounty cells; use V1 Listing and all-FD event, remove bounty-only state/hook/claim cells."
                elif path == "fork/TrustedFactory.t.sol":
                    disposition = "PORT_TRUST"
                    reason = "Keep runner identity; scenario uses ForkFixture/Trio and V1, no BountyForkFixture/Kit."
                elif "/bounty/" in path:
                    disposition = "RETIRE_BOUNTY"
                    new = None
                    reason = "Removed product mechanism; preserved at baseline commit, not executable in shipping tree."
                elif path.startswith("test/v2/"):
                    disposition = "RETIRE_V2_TWIN"
                    new = old.replace("test/v2/V2Adapters.t.sol:V2AdaptersTest:", "test/Adapters.t.sol:AdaptersTest:").replace("test/v2/V2Admission.t.sol:V2AdmissionTest:", "test/CurveGaugeLister.t.sol:CurveGaugeListerTest:").replace("test/v2/V2Settlement.t.sol:V2SettlementTest:", "test/Settlement.t.sol:SettlementTest:").replace("test_V2_", "test_")
                    reason = "Version-specific twin removed; counterpart identifies retained non-bounty obligation, not a claim of byte-identical tests. Constructor-chain/paused/trust additions are carried in the trust matrix."
                # Forge --list JSON contains bare names, while execution and
                # anchored --match-test use compiled input signatures. Bind
                # both without guessing that every test is zero-argument.
                test_artifact = json.loads((Path(b["scratch"]) / profile / "out" / Path(path).name / (contract + ".json")).read_text())
                signatures = [sig for sig in test_artifact["methodIdentifiers"] if sig.startswith(test + "(")]
                assert len(signatures) == 1, (old, signatures)
                baseline_signature = signatures[0]
                target_signature = None if new is None else new.rsplit(":", 1)[1] + baseline_signature[len(test):]
                rows.append({"profile": profile, "baseline_identity": old, "baseline_signature": baseline_signature, "disposition": disposition, "target_identity_or_counterpart": new, "target_signature_or_counterpart": target_signature, "target_match_test_regex": None if target_signature is None else "^" + re.escape(target_signature) + "$", "reason": reason})
retained = {x["baseline_identity"] for x in rows if x["disposition"] == "RETAIN_V1"}
assert all(x["target_identity_or_counterpart"] in retained for x in rows if x["disposition"] == "RETIRE_V2_TWIN")
counts = {profile: dict(collections.Counter(x["disposition"] for x in rows if x["profile"] == profile)) for profile in ("default", "fork")}
expected = {profile: sum(v for k, v in c.items() if k in ("RETAIN_V1", "PORT_TRUST")) for profile, c in counts.items()}
census = {"baseline": b["candidate"], "source": "native forge test --offline --list --json, both profiles", "baseline_counts": {profile: sum(c.values()) for profile, c in counts.items()}, "disposition_counts": counts, "expected_if_only_this_authorized_identity_plan_is_implemented": expected, "policy": "These totals are consequences, not targets. Final exact inventory and PASS identities must be regenerated; additions require reason and row, missing or duplicate identities block acceptance. Fuzz runs are not separate identities.", "identities": rows}
(ROOT / "plans/V1ALIGN-WITNESS-INVENTORY.json").write_text(json.dumps(census, indent=2) + "\n")
# Verify old hardcoded out/ ABI-test inputs match fresh compiler objects.
comparisons = {}
for name in ("VotiumAdapter", "VoteMarketAdapter"):
    key = name + ".sol/" + name + ".json"
    old_art = json.loads((ROOT / "out" / key).read_text())
    comparisons[key] = {"abi_equal": old_art["abi"] == p[key]["abi"], "methodIdentifiers_equal": old_art["methodIdentifiers"] == p[key]["methodIdentifiers"], "runtime_equal": __import__("hashlib").sha256(bytes.fromhex(old_art["deployedBytecode"]["object"].removeprefix("0x"))).hexdigest() == p[key]["runtime_sha256_decoded"]}
assert all(all(v.values()) for v in comparisons.values())
(HERE / "hardcoded-artifact-check.json").write_text(json.dumps(comparisons, indent=2) + "\n")
# Entry identity counts and summary for the report, with exact source/storage data.
print(json.dumps({"manifest_counts": manifest["counts"], "census": counts, "expected": expected, "v1_storage": v1["storageLayout"], "v2_storage": v2["storageLayout"], "target_functions": methods, "errors": [x for x in abi if x["type"] == "error"], "remove": manifest["remove_product_sources"], "hardcoded_artifact_check": comparisons}, indent=2))
