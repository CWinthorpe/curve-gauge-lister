#!/usr/bin/env python3
"""Validate secgate3 authority, snapshots and retained evidence; no fresh Forge/RPC."""
import collections
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

from Crypto.Hash import keccak

ROOT = Path(__file__).resolve().parents[2]
CANDIDATE = "3ba03f35d66ca5172c4c417335804f0a6f4ed07d"
ROUNDS = {
    "cgl-sec-r1": "d224b12ec2f62e3ef877d682ad0b6968d9cc3e95",
    "cgl-sec-r2": "4a442e63421a89b04e902f4e709613b8234f16c5",
    "cgl-sec-r3": CANDIDATE,
}
CHECKS = []


def require(ok, message):
    if not ok:
        raise ValueError(message)
    CHECKS.append(message)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def record(path):
    data = (ROOT / path).read_bytes()
    return {"sha256": sha(data), "bytes": len(data)}


def unique(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON key: {key}")
        result[key] = value
    return result


def load(path):
    return json.loads((ROOT / path).read_text(), object_pairs_hook=unique)


def git(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT)


def ancestor(base, tip):
    rc = subprocess.run(["git", "merge-base", "--is-ancestor", base, tip], cwd=ROOT).returncode
    require(rc in (0, 1), f"ancestry query: {base}")
    return rc == 0


def tracked(revision):
    return git("ls-tree", "-r", "--name-only", revision).decode().splitlines()


def manifest(revision):
    return {p: sha(git("show", f"{revision}:{p}")) for p in tracked(revision)}


def report_rows(path):
    rows = []
    for line in (ROOT / path).read_text().splitlines():
        if re.match(r"^\| (?:CGL-)?[VI]-?\d{2} \|", line):
            cells = [s.strip() for s in line.split("|")[1:-1]]
            if len(cells) == 6:
                key, title, severity, location, flagged, _ = cells
            elif len(cells) == 4:
                key, title, location, flagged = cells
                severity = "Informational"
            else:
                raise ValueError(f"unrecognized finding row: {line}")
            rows.append({"id": key, "title": title, "severity": severity,
                         "location": location, "flagged_by": flagged})
    require(len({r["id"] for r in rows}) == len(rows), f"unique finding IDs: {path}")
    return rows


def severity_counts(rows):
    counts = dict.fromkeys(["Critical", "High", "Medium", "Low", "Informational"], 0)
    for row in rows:
        counts[row["severity"].split()[0]] += 1
    return counts


def round_evidence(name, revision):
    directory = Path("/home/winny/audits-work") / name
    snapshot = directory / "source"
    missing, matched = [], {}
    for path in tracked(revision):
        if not (snapshot / path).is_file():
            missing.append(path)
        else:
            data = git("show", f"{revision}:{path}")
            require((snapshot / path).read_bytes() == data, f"{name} source equality: {path}")
            matched[path] = sha(data)
    require(all(p.startswith(("plans/", "review/")) for p in missing), f"{name} complete product snapshot")
    contract_paths = {p for p in tracked(revision) if p.startswith("contracts/")}
    snapshot_contracts = {str(p.relative_to(snapshot)) for p in (snapshot / "contracts").rglob("*") if p.is_file()}
    require(snapshot_contracts == contract_paths, f"{name} exact audited contract-file inventory")
    report = directory / "audits/contracts-audit-report-verified-2026-11-24.md"
    primary = sorted((directory / "audits").glob("*/contracts-audit-report-*-2026-11-24.md"))
    require(len(primary) == 8 and len({p.parent.name for p in primary}) == 8,
            f"{name} eight distinct primary model directories")
    require(all(p.name == f"contracts-audit-report-{p.parent.name}-2026-11-24.md" for p in primary),
            f"{name} primary report naming")
    checkpoints = sorted((directory / "audits").glob("*/audits/contracts-audit-report-*.md"))
    rows = report_rows(report)
    return {"candidate": revision, "audit_snapshot": str(snapshot), "report": str(report),
            "report_binding": record(report), "findings": rows, "severity_counts": severity_counts(rows),
            "snapshot_matched_sha256": matched, "audit_snapshot_missing_tracked_paths": missing,
            "primary_reports": {str(p): record(p) for p in primary},
            "same_model_checkpoints_not_extra_reviewers": {str(p): record(p) for p in checkpoints}}


def canonical_abi(abi):
    return sorted(json.dumps(entry, sort_keys=True) for entry in abi)


def canonical_layout(layout):
    def member(m):
        return {k: (kind(v) if k == "type" else v) for k, v in m.items() if k != "astId"}

    def kind(key):
        result = {}
        for k, v in layout["types"][key].items():
            if k in ("base", "key", "value"):
                result[k] = kind(v)
            elif k == "members":
                result[k] = [member(m) for m in v]
            else:
                result[k] = v
        return result

    return [member(m) for m in layout["storage"]]


def artifact_evidence():
    base = Path("/home/winny/tmp-scratch/sg2-base")
    final = Path("/home/winny/tmp-scratch/sg2-final")
    normative = load("plans/V1ALIGN-MANIFEST.json")
    for directory, revision in [(base, ROUNDS["cgl-sec-r2"]), (final, CANDIDATE)]:
        for path in tracked(revision):
            require((directory / path).read_bytes() == git("show", f"{revision}:{path}"),
                    f"retained archive source: {directory.name}/{path}")
    inventories, products = {}, {}
    for profile, out, evm in [("default", "out", "paris"), ("fork", "out-fork", "cancun")]:
        left = {str(p.relative_to(base)): sha(p.read_bytes()) for p in sorted((base / out).rglob("*.json"))
                if "build-info" not in p.parts}
        right = {str(p.relative_to(final)): sha(p.read_bytes()) for p in sorted((final / out).rglob("*.json"))
                 if "build-info" not in p.parts}
        require(bool(left) and left == right, f"retained complete non-build-info artifacts equal: {profile}")
        inventories[profile] = left
        for name in ["CurveGaugeLister", "VotiumAdapter", "VoteMarketAdapter"]:
            relative = f"{out}/{name}.sol/{name}.json"
            a = load(final / relative)
            metadata = a["metadata"]
            require(metadata["compiler"]["version"] == "0.8.30+commit.73712a01", f"compiler: {relative}")
            settings = metadata["settings"]
            require(settings["evmVersion"] == evm and settings["optimizer"] == {"enabled": True, "runs": 200}
                    and not settings.get("viaIR", False), f"profile settings: {relative}")
            for source, data in metadata["sources"].items():
                digest = "0x" + keccak.new(digest_bits=256, data=git("show", f"{CANDIDATE}:{source}")).hexdigest()
                require(digest == data["keccak256"], f"artifact metadata source binding: {relative}/{source}")
            key = f"{name}.sol/{name}.json"
            abi = normative["abi"] if name == "CurveGaugeLister" else normative["unchanged_adapter_abi"][key]
            methods = (normative["methodIdentifiers"] if name == "CurveGaugeLister"
                       else normative["unchanged_adapter_methodIdentifiers"][key])
            require(canonical_abi(a["abi"]) == canonical_abi(abi), f"full normative ABI: {relative}")
            require(a["methodIdentifiers"] == methods, f"full normative methods: {relative}")
            if name == "CurveGaugeLister":
                require(canonical_layout(a["storageLayout"]) == canonical_layout(normative["baseline_v1_storageLayout"]),
                        f"recursive normative core layout: {relative}")
            creation = bytes.fromhex(a["bytecode"]["object"].removeprefix("0x"))
            runtime = bytes.fromhex(a["deployedBytecode"]["object"].removeprefix("0x"))
            require(len(runtime) <= 24576 and len(creation) <= 49152, f"product size ceilings: {relative}")
            products[relative] = {"artifact_sha256": left[relative],
                                  "creation_sha256": sha(creation), "runtime_sha256": sha(runtime),
                                  "creation_bytes": len(creation), "runtime_bytes": len(runtime),
                                  "full_metadata_included": True}
    return {"base_root": str(base), "base_candidate": ROUNDS["cgl-sec-r2"],
            "final_root": str(final), "final_candidate": CANDIDATE,
            "non_build_info_artifact_sha256": inventories, "products": products,
            "scope": "Retained builder artifact re-comparison and source/metadata binding, not fresh compilation; build-info run records excluded"}


def native_discovery(path, profile, census):
    file = contract = None
    result = []
    out = "out" if profile == "default" else "out-fork"
    for line in (ROOT / path).read_text().splitlines():
        if re.fullmatch(r"(?:test|fork)/\S+\.sol", line):
            file, contract = line, None
        elif re.fullmatch(r"  \w+", line):
            contract = line.strip()
        elif re.fullmatch(r"    test\w+", line):
            if file is None or contract is None:
                raise ValueError(f"native discovery missing context: {path}")
            require(True, f"native discovery context: {path}")
            artifact = Path("/home/winny/tmp-scratch/sg2-final") / out / Path(file).name / f"{contract}.json"
            methods = load(artifact)["methodIdentifiers"]
            matches = [sig for sig in methods if sig.split("(")[0] == line.strip()]
            require(len(matches) == 1, f"compiled test signature: {file}:{contract}:{line.strip()}")
            result.append(f"{file}:{contract}:{matches[0]}")
    require(sorted(result) == census and len(result) == len(set(result)), f"exact saved discovery: {path}")
    return len(result)


def native_passes(path, census):
    suite = None
    result = []
    text = (ROOT / path).read_text()
    for line in text.splitlines():
        header = re.fullmatch(r"Ran \d+ tests? for ((?:test|fork)/[^:]+:\S+)", line)
        if header:
            suite = header.group(1)
        match = re.match(r"\[PASS\] (\S+\([^)]*\))", line)
        if match:
            require(suite is not None, f"native PASS context: {path}")
            result.append(f"{suite}:{match.group(1)}")
        require(not re.match(r"\[(?:FAIL|SKIP)", line), f"no saved failure/skip: {path}")
    require(sorted(result) == census and len(result) == len(set(result)), f"exact saved PASS set: {path}")
    require(re.search(rf"{len(census)} tests passed, 0 failed, 0 skipped", text) is not None,
            f"native summary agrees: {path}")
    return len(result)


def gather():
    candidate_manifest = manifest(CANDIDATE)
    rounds = {name: round_evidence(name, revision) for name, revision in ROUNDS.items()}
    require([list(r["severity_counts"].values()) for r in rounds.values()]
            == [[0, 1, 4, 3, 7], [0, 0, 3, 2, 11], [0, 0, 1, 5, 14]], "truthful three-round severity history")
    census = load("review/secgate2/BINDING.json")["census"]
    inventory = load("plans/V1ALIGN-WITNESS-INVENTORY.json")["identities"]
    for profile, count in [("default", 77), ("fork", 13)]:
        identities = sorted(row["target_identity_or_counterpart"].rsplit(":", 1)[0] + ":"
                            + row["target_signature_or_counterpart"] for row in inventory
                            if row["profile"] == profile and row["disposition"] in {"RETAIN_V1", "PORT_TRUST"})
        require(identities == census[profile] == load("review/secgate/BINDING.json")["census"][profile]
                and len(identities) == len(set(identities)) == count, f"normative exact census: {profile}")
    receipts = {}
    for directory, revision in [("secdocs", ROUNDS["cgl-sec-r2"]), ("secdocs2", CANDIDATE)]:
        path = f"review/{directory}/RECEIPTS.json"
        receipt = load(path)
        require(receipt["final"] == revision, f"builder candidate: {directory}")
        for file, digest in receipt["receipt_files"].items():
            require(record(file)["sha256"] == digest, f"saved receipt integrity: {file}")
        tree = load(f"review/{directory}/final-tree-manifest.json")
        require(tree["final_head"] == revision and tree["sha256"] == manifest(revision), f"builder final-tree binding: {directory}")
        results = {}
        for profile in census:
            results[f"discovery_{profile}"] = native_discovery(f"review/{directory}/files/discover-{profile}.txt", profile, census[profile])
        for stem, profile in [("test-offline", "default"), ("test-offline-unreachable", "default"), ("test-fork", "fork")]:
            results[stem] = native_passes(f"review/{directory}/files/{stem}.txt", census[profile])
        receipts[path] = {"binding": record(path), "base": receipt["base"], "final": revision,
                          "receipt_files_verified": len(receipt["receipt_files"]), "saved_native_results": results}
    historical = {}
    for spec, expected in load("review/secgate2/BINDING.json")["historical_authority_bindings"].items():
        data = git("show", spec)
        item = {"sha256": sha(data), "bytes": len(data), "git_blob": git("rev-parse", spec).decode().strip(),
                "ancestor_of_candidate": ancestor(spec.split(":")[0], CANDIDATE)}
        require(item == expected, f"recovered historical authority: {spec}")
        historical[spec] = item
    builders = {}
    for base, final in [("ce1cc22b9b97ca2b2e3f135ab991dc0e905e9e8f", ROUNDS["cgl-sec-r2"]),
                        ("f6c6cf85cc4b984cd346ea97887b55a393e733ca", CANDIDATE)]:
        paths = git("diff", "--name-only", base, final).decode().splitlines()
        require(all(p == "README.md" or p.startswith("docs/") for p in paths), f"docs-only builder: {base}")
        builders[base] = {"final": final, "changed_paths": paths}
    require(not git("diff", "--name-only", ROUNDS["cgl-sec-r1"], CANDIDATE,
                    "--", "contracts", "test", "fork", "scripts", "foundry.toml", ".gitignore"),
            "every executable/comment/test/runner/config byte frozen across all rounds")
    for revision in ROUNDS.values():
        require(ancestor(revision, CANDIDATE), f"audit candidate ancestry: {revision}")
    return {"candidate_tracked_sha256": candidate_manifest,
            "product_baseline_sha256": {p: d for p, d in candidate_manifest.items() if not p.startswith(("plans/", "review/"))},
            "audit_rounds": rounds, "census": census, "historical_authority_bindings": historical,
            "builder_bridges": builders, "saved_builder_receipts": receipts, "retained_artifacts": artifact_evidence()}


def main():
    binding_path = "review/secgate3/BINDING.json"
    b = load(binding_path)
    require(b["schema"] == 1 and b["authority_id"] == "secgate3" and b["candidate"] == CANDIDATE,
            "exact authority and full candidate identifier")
    require(git("branch", "--show-current").decode().strip() == "main" and ancestor(CANDIDATE, "HEAD"),
            "main descends from reviewed candidate")
    actual = gather()
    for key, value in actual.items():
        require(b[key] == value, f"recomputed evidence binding: {key}")
    for path, digest in b["candidate_tracked_sha256"].items():
        require(record(path)["sha256"] == digest, f"working candidate frozen: {path}")
    for path, item in b["input_bindings_before_ruling"].items():
        data = (ROOT / path).read_bytes()
        if path in b["carriers"]:
            data = data[:item["bytes"]]
        require({"sha256": sha(data), "bytes": len(data)} == item, f"input/preserved prefix: {path}")
    current = set(git("ls-files").decode().splitlines())
    preceding = load("review/secgate2/BINDING.json")
    preceding_builder = load("review/secdocs2/RECEIPTS.json")
    for path, item in b["carriers"].items():
        data = (ROOT / path).read_bytes()
        require(sha(data) == item["sha256_after"] and len(data) == item["bytes_after"], f"current carrier: {path}")
        require(sha(data[:item["bytes_before"]]) == item["sha256_before"], f"carrier historical prefix: {path}")
        old = preceding["carriers"][path]
        require(sha(data[:old["bytes_after"]]) == old["sha256_after"], f"original secgate2 carrier preserved: {path}")
        require(path not in current and subprocess.run(["git", "check-ignore", "-q", path], cwd=ROOT).returncode == 0,
                f"carrier remains owner-held/ignored: {path}")
        if item["obligation"] == "PAO-AUTH":
            require(item["sha256_before"] == preceding_builder["carrier_digests"]["AUTH_post_bridge"],
                    "pre-ruling AUTH equals actual P5 final bridge")
            suffix = data[item["bytes_before"]:].decode()
            require(suffix.startswith("\n## secgate3") and CANDIDATE in suffix
                    and "SECURITY AUDIT CONVERGED" in suffix and "ACTIVATION-OPEN" in suffix
                    and "V06" in suffix and "P1" in suffix and "P5" in suffix, "same-index final convergence bridge")
        else:
            require(item["bytes_before"] == item["bytes_after"], f"FD/CTL unchanged: {path}")
    published = set(b["publication_allowlist"])
    require(current - set(b["candidate_tracked_sha256"]) <= published, "tracked additions confined to new authority package")
    for args in [("diff", "--name-only", CANDIDATE, "HEAD"), ("diff", "--name-only"), ("diff", "--cached", "--name-only")]:
        require(set(git(*args).decode().splitlines()) <= published, "scope: " + " ".join(args))
    for args in [("diff", "--check"), ("diff", "--cached", "--check"), ("diff", "--check", CANDIDATE, "HEAD")]:
        require(subprocess.run(["git", *args], cwd=ROOT).returncode == 0, "git " + " ".join(args))
    for path, digest in b["package_sha256"].items():
        require(record(path)["sha256"] == digest, f"authority package digest: {path}")
    ruling = (ROOT / "review/secgate3/RULING.md").read_text()
    rows = re.findall(r"^\| ([VI]\d{2}) \| ([A-Z-]+) \| (.+) \|$", ruling, re.M)
    ids = [f"V{i:02d}" for i in range(1, 7)] + [f"I{i:02d}" for i in range(1, 15)]
    require([row[0] for row in rows] == ids == [row["id"] for row in b["audit_rounds"]["cgl-sec-r3"]["findings"]],
            "exact six findings and fourteen informational dispositions")
    require(set(b["dispositions"]) == set(ids), "no missing or extra JSON disposition")
    severities = {r["id"]: r["severity"] for r in b["audit_rounds"]["cgl-sec-r3"]["findings"]}
    for key, disposition, grounds in rows:
        item = b["dispositions"][key]
        require(item["ruling"] == disposition and item["grounds"] == grounds
                and item["severity"] == severities[key] and item["lineage"] and item["work_package"] is None,
                f"report/ruling/JSON agreement and no new work: {key}")
    require(all(b["dispositions"][f"V{i:02d}"]["registration_status"] == "REGISTERED-RE-DERIVATION" for i in range(1, 6))
            and b["dispositions"]["V06"]["ruling"] == "REJECT", "registered recurrence and explicit V06 rejection")
    require(re.findall(r"^\| (P[1-4]|[DO][1-4]) \| CONFIRMED \|", ruling, re.M)
            == list(b["bounded_confirmation"])
            == ["P1", "P2", "P3", "P4", "D1", "D2", "D3", "D4", "O1", "O2", "O3", "O4"],
            "complete P1-P4 and eight P5 confirmation cells")
    for path, digest in b["carried_registration_paragraphs"].items():
        text = next(line for line in (ROOT / path).read_text().splitlines() if line.startswith("> Review the candidate") or line.startswith("> Apply review/secgate2"))
        require(sha(text.encode()) == digest and text in ruling, f"verbatim prior engagement rule: {path}")
    disclosure = next(line.removeprefix("> ") for line in (ROOT / "review/secgate2/RULING.md").read_text().splitlines()
                      if line.startswith("> A successfully funded Votium"))
    require(disclosure in (ROOT / "docs/OPERATIONS.md").read_text(), "P5 required disclosure delivered verbatim")
    require(b["work_packages"] == {} and b["executable_changes_authorized"] == []
            and b["product_documentation_changes_authorized"] == [] and b["operational_duty_changes_authorized"] == []
            and b["census_additions_authorized"] == [],
            "no new executable/product-doc/ops/census work")
    require(b["security_convergence_certified"] is True and "SECURITY AUDIT CONVERGED" in ruling
            and b["activation"].startswith("HOLD") and "trial" in ruling.lower(), "convergence distinct from activation")
    return {"status": "PASS", "candidate": CANDIDATE, "binding_sha256": record(binding_path)["sha256"],
            "scope": "Executed authority-artifact checks, manual bounded prose confirmation and retained evidence re-comparison; no fresh Forge/RPC/deployment",
            "all_items": ids, "dispositions": dict(collections.Counter(r[1] for r in rows)),
            "audit_severity_counts": {k: v["severity_counts"] for k, v in b["audit_rounds"].items()},
            "candidate_tracked_files": len(b["candidate_tracked_sha256"]),
            "unchanged_product_files": len(b["product_baseline_sha256"]),
            "retained_artifacts_equal": sum(len(x) for x in b["retained_artifacts"]["non_build_info_artifact_sha256"].values()),
            "product_artifacts_recompared": len(b["retained_artifacts"]["products"]),
            "saved_native_results": {k: v["saved_native_results"] for k, v in b["saved_builder_receipts"].items()},
            "census": {k: len(v) for k, v in b["census"].items()}, "bounded_confirmation_cells": list(b["bounded_confirmation"]),
            "security_convergence_certified": True, "lean_convergence": "RETAINED", "activation": b["activation"],
            "fresh_product_tests_run": False, "current_chain_readiness_verified": False, "checks_passed": len(CHECKS)}


if __name__ == "__main__":
    try:
        print(json.dumps(main(), indent=2, sort_keys=True))
    except (ValueError, OSError, KeyError, IndexError, StopIteration, subprocess.CalledProcessError) as error:
        print(json.dumps({"status": "FAIL", "error": str(error), "checks_passed": len(CHECKS)}, indent=2))
        sys.exit(1)
