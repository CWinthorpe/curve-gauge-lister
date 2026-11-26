#!/usr/bin/env python3
"""Read-only routergate evidence validation; --capture emits a draft binding.

No build, test, network, signing or product write is performed. Semantic
rulings remain the authority's judgment; hashes do not adjudicate them.
"""
import argparse
import hashlib
import json
import re
import subprocess
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CANDIDATE = "72f775e91c0a090364f00ceafe9b55d8bb862922"
REVIEWED = "60956b62879916081325ef0a66c502d3be85f913"
S3_COMMIT = "cbb485aa2bbda41228d764aeb90c86fc516da18f"
HERE = "review/routergate/"
AUTH = "review/simplify2/AUTH-EVIDENCE-INDEX.md"
FD = "review/simplify2/FD-BOUND-OBLIGATION.md"
CTL = "review/simplify2/CTL-CALLER-ROLE-GATE.md"
BEFORE = {
    AUTH: (65538, "5d44b26b47147f9545c37e95a4f61f51756ddbdcd828c6a49c5b9e3b6a0781b3"),
    FD: (14211, "22a50ed470e4bb4f9df9c82a462cb9b9d626d040844e79dcdb25dad241f33f80"),
    CTL: (24695, "25dc31ab77ff0b07878dc0e68ccc81e908d754611d6dfc33c03a26643ce7fa6e"),
}
ALLOWLIST = [HERE + name for name in ("RULING.md", "BINDING.json", "verify.py", "VALIDATION.json")]
SEVERITIES = ("Critical", "High", "Medium", "Low", "Informational")
EXPECTED_IDS = {f"CGL-{i:02}" for i in range(1, 10)} | {f"CGL-I{i:02}" for i in range(1, 9)}
REPEATED = {"CGL-01", "CGL-02", "CGL-03", "CGL-04", "CGL-08", "CGL-09"}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def raw(path):
    return (ROOT / path).read_bytes()


def load(path):
    return json.loads(raw(path))


def digest(path):
    data = raw(path)
    return {"sha256": sha(data), "bytes": len(data)}


def git(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT)


def rows(text):
    for line in text.splitlines():
        if line.startswith("|"):
            yield [part.strip().strip("`*") for part in line.strip().strip("|").split("|")]


def report_findings(path):
    result = {}
    for cells in rows(raw(path).decode()):
        if not re.fullmatch(r"(?:CGL-(?:I|V)?\d{2}|[VI]-?\d{2})", cells[0]):
            continue
        require(cells[0] not in result, f"duplicate report ID: {path}: {cells[0]}")
        if re.fullmatch(r"(?:CGL-)?I-?\d{2}", cells[0]):
            severity = "Informational"
        else:
            match = re.match(r"(Critical|High|Medium|Low|Informational)\b", cells[2])
            require(match is not None, f"unparsed severity: {path}: {cells}")
            severity = match.group(1)
        result[cells[0]] = {"severity": severity, "table_cells": cells}
    require(result, f"empty report: {path}")
    counts = Counter(item["severity"] for item in result.values())
    return result, {severity: counts[severity] for severity in SEVERITIES}


def native_passes(path):
    text = raw(path).decode()
    require(not re.search(r"^\[(?:FAIL|SKIP)", text, re.M), f"nonpass marker: {path}")
    current = None
    found = []
    for line in text.splitlines():
        header = re.match(r"Ran \d+ tests? for (\S+\.sol:\S+)", line)
        if header:
            current = header.group(1)
        passed = re.match(r"\[PASS\] (\S+\([^)]*\))", line)
        if passed:
            require(current is not None, f"PASS without suite: {path}")
            found.append(current + ":" + passed.group(1))
    require(found and len(found) == len(set(found)), f"empty/duplicate PASS: {path}")
    totals = re.findall(r"(\d+) tests? passed, (\d+) failed, (\d+) skipped", text)
    require(totals and tuple(map(int, totals[-1])) == (len(found), 0, 0), f"native totals: {path}")
    return sorted(found)


def tracked_map(commit):
    require(re.fullmatch(r"[0-9a-f]{40}", commit) is not None, "malformed Git identifier")
    names = git("ls-tree", "-r", "--name-only", commit).decode().splitlines()
    return {name: sha(git("show", f"{commit}:{name}")) for name in names}


def collect():
    tracked = tracked_map(CANDIDATE)
    require(len(tracked) == 65, "candidate tracked count")
    product = {p: h for p, h in tracked.items() if not p.startswith(("plans/", "review/"))}
    require(len(product) == 60, "candidate product count")
    for path, expected in tracked.items():
        require(sha(raw(path)) == expected, f"candidate byte drift: {path}")
    require(git("rev-parse", CANDIDATE + "^").decode().strip() == REVIEWED, "conformance parent")
    delta = git("diff", "--name-status", REVIEWED, CANDIDATE).decode().strip()
    require(delta == "A\treview/ROUTERCONF5.md", "non-report conformance bridge")
    git("merge-base", "--is-ancestor", S3_COMMIT, CANDIDATE)

    s3 = load("review/secgate3/BINDING.json")
    prior_authority = {}
    for name in ("RULING.md", "BINDING.json", "VALIDATION.json"):
        path = "review/secgate3/" + name
        blob = git("show", S3_COMMIT + ":" + path)
        require(raw(path) == blob, f"prior authority differs from Git: {path}")
        prior_authority[path] = {**digest(path), "git_object": S3_COMMIT + ":" + path}
    require(s3["security_convergence_certified"] is True, "pre-router convergence missing")
    require(len(s3["bounded_confirmation"]) == 12, "prior documentation confirmation census")
    contracts_delta = git("diff", "--name-status", s3["candidate"], CANDIDATE, "--", "contracts/").decode().strip()
    require(contracts_delta == "A\tcontracts/GaugeControllerAdmin.sol", "old contract drift")

    audit_rounds = {}
    for key, old in s3["audit_rounds"].items():
        archive = Path("/home/winny/audits-archive") / (key + "-2026-11-24")
        report = str(archive / "audits" / Path(old["report"]).name)
        snapshot = Path(old["audit_snapshot"])
        require(digest(report) == old["report_binding"], f"relocated report mismatch: {key}")
        findings, counts = report_findings(report)
        require(counts == old["severity_counts"], f"historical severity mismatch: {key}")
        require(set(findings) == {x["id"] for x in old["findings"]}, f"historical ID mismatch: {key}")
        matched = old["snapshot_matched_sha256"]
        require(len(matched) == 53, f"historical snapshot census: {key}")
        for path, expected in matched.items():
            require(sha(raw(str(snapshot / path))) == expected, f"snapshot drift: {key}/{path}")
            require(sha(git("show", old["candidate"] + ":" + path)) == expected, f"Git snapshot drift: {key}/{path}")
        audit_rounds[key] = {
            "candidate": old["candidate"], "report": report, "previous_report_path": old["report"],
            "report_binding": digest(report), "archive_manifest": digest(str(archive / "manifest.json")),
            "archive_manifest_path": str(archive / "manifest.json"), "audit_snapshot": str(snapshot),
            "snapshot_matched_sha256": matched, "findings": findings, "severity_counts": counts,
            "evidence_class": "archived static fleet report; hash matches sealed secgate3 binding",
        }
    current_root = Path("/home/winny/audits-work/cgl-router-fleet-r1")
    current_report = str(current_root / "audits/contracts-audit-report-verified-2026-11-26.md")
    findings, counts = report_findings(current_report)
    require(set(findings) == EXPECTED_IDS, "router fleet ID coverage")
    require(counts == dict(zip(SEVERITIES, (0, 0, 4, 5, 8))), "router fleet severity totals")
    missing = []
    for path, expected in tracked.items():
        target = current_root / "source" / path
        if target.is_file():
            require(sha(raw(str(target))) == expected, f"router fleet snapshot drift: {path}")
        else:
            missing.append(path)
    require(set(missing) == set(tracked) - set(product), "unexpected missing fleet input")
    audit_rounds["cgl-router-fleet-r1"] = {
        "candidate": CANDIDATE, "report": current_report, "report_binding": digest(current_report),
        "audit_snapshot": str(current_root / "source"), "snapshot_matched_sha256": product,
        "audit_snapshot_missing_tracked_paths": sorted(missing), "findings": findings,
        "severity_counts": counts, "evidence_class": "static fleet report; no test/runtime/readiness proof",
    }
    for key in ("cgl-sec-r3", "cgl-router-fleet-r1"):
        require(audit_rounds[key]["severity_counts"]["Critical"] == 0, "final-round Critical")
        require(audit_rounds[key]["severity_counts"]["High"] == 0, "final-round High")

    conf = load("review/routerconf5/BINDING.json")
    require(conf["candidate"] == REVIEWED, "conformance candidate")
    require(conf["tree"] == git("rev-parse", REVIEWED + "^{tree}").decode().strip(), "conformance tree")
    require(conf["file_count"] == len(conf["files"]) == 27, "conformance receipt total")
    require(len(conf["authority_inputs"]) == 6, "conformance authority total")
    for path, expected in conf["files"].items():
        require(sha(raw("review/routerconf5/" + path)) == expected, f"conformance receipt: {path}")
    for path, expected in conf["authority_inputs"].items():
        require(sha(raw(path)) == expected, f"conformance input: {path}")
    baseline = load("review/routerplan/BASELINE.json")["identities"]
    additions = {"default": [], "fork": []}
    for cells in rows(raw("review/routerfix/receipts/CENSUS-LEDGER.md").decode()):
        if re.fullmatch(r"[OIF]\d{2}", cells[0]):
            additions[cells[1]].append(cells[2])
    census = {}
    for profile, count in (("default", 103), ("fork", 25)):
        merged = baseline[profile] + additions[profile]
        require(len(merged) == len(set(merged)) == count, f"baseline/ledger: {profile}")
        census[profile] = sorted(merged)
        saved = load(f"review/routerconf5/{profile}-census.json")["identities"]
        require(sorted(saved) == census[profile], f"saved census: {profile}")
        listing = load(f"review/routerconf5/{profile}-list.stdout")
        names = sorted(f"{p}:{c}:{n}" for p, cs in listing.items() for c, ns in cs.items() for n in ns)
        require(names == sorted(x[:-2] for x in merged), f"native discovery: {profile}")
        require(all(x.endswith("()") for x in merged), "unexpected parameterized signature")
    saved_runs = {}
    for stem, profile in (("G2-offline-full", "default"), ("G3-offline-unreachable", "default"),
                          ("G5-fork-cold", "fork"), ("G6-fork-warm", "fork")):
        prefix = "review/routerfix6/receipts/gates/" + stem
        run = load(prefix + ".run.json")
        require(run["rc"] == 0 and run["candidate"] == REVIEWED and run["tree"] == conf["tree"], f"run binding: {stem}")
        require(native_passes(prefix + ".stdout") == census[profile], f"native PASS set: {stem}")
        saved_runs[stem] = {
            "profile": profile, "candidate": REVIEWED, "native_exit": run["rc"],
            "pass_count": len(census[profile]), "failed": 0, "skipped": 0,
            "files": {prefix + suffix: digest(prefix + suffix) for suffix in (".run.json", ".stdout", ".stderr")},
            "evidence_class": "historical executor full suite; Git association from retained sidecar, not stdout",
        }
    selected_runs = {}
    for stem in ("I03-trace", "F05-trace"):
        prefix = "review/routerconf5/" + stem
        run = load(prefix + ".run.json")
        passes = native_passes(prefix + ".stdout")
        require(run["candidate"] == REVIEWED and run["exit_code"] == 0, f"selected run: {stem}")
        require(passes == run["pass_identities"] and len(passes) == 1, f"selected PASS: {stem}")
        selected_runs[stem] = {"pass_identities": passes, "native_exit": 0, "evidence_class": "historical independent conformance execution"}

    dispositions = {}
    ruling = raw(HERE + "RULING.md").decode()
    for cells in rows(ruling):
        if cells[0] in EXPECTED_IDS:
            require(cells[0] not in dispositions and len(cells) == 4, "duplicate/malformed disposition")
            require(cells[1] == findings[cells[0]]["severity"], "disposition severity changed")
            decision, grounds = cells[3].split(" — ", 1)
            require(decision == "ACCEPT-WITH-REASON", "unexpected work adoption")
            dispositions[cells[0]] = {"ruling": decision, "severity": cells[1], "registration_status": cells[2],
                                    "grounds": grounds, "work_package": None, "executable_change_adopted": False}
    require(set(dispositions) == EXPECTED_IDS, "incomplete disposition coverage")
    require({k for k, v in dispositions.items() if v["registration_status"] == "REGISTERED RE-DERIVATION"} == REPEATED,
            "accepted-risk triage coverage")
    activation = {cells[0]: {"requirement": cells[1], "status": cells[2]} for cells in rows(ruling)
                  if cells[0] in {"PAO-FD", "PAO-CTL", "PAO-AUTH", "Current dependencies and venue readiness",
                                  "Approvals, funding and staffing", "Post-authorization funded trial"}}
    require(len(activation) == 6, "activation-open coverage")
    for phrase in ("ROUTER+FLEET CONVERGED at 72f775e.", "The campaign's audit obligations are complete.",
                   "ACTIVATION HOLD", "router's FIRST blind round", "one further blind router/security round AFTER shipment"):
        require(phrase in ruling, f"missing decision boundary: {phrase}")
    carriers = {}
    for path, (size, before) in BEFORE.items():
        data = raw(path)
        require(sha(data[:size]) == before, f"carrier prefix changed: {path}")
        if path != AUTH:
            require(len(data) == size, f"unapproved carrier append: {path}")
        else:
            require(data[size:].startswith(b"\n## routergate"), "missing same-index bridge")
            require(CANDIDATE.encode() in data[size:] and b"ROUTER+FLEET CONVERGED" in data[size:], "stale carrier bridge")
        carriers[path] = {"bytes_before": size, "sha256_before": before, "bytes_after": len(data),
                          "sha256_after": sha(data), "edit": "append-only" if path == AUTH else "unchanged",
                          "tracking_status": "SATISFIED-TRACKING", "activation_status": "ACTIVATION-OPEN",
                          "custody": "owner-held/ignored/producible on demand; not published"}

    inputs = ["plans/ROUTERGATE-BRIEF.md", "plans/ROUTERPLAN-SPEC.md", "plans/ROUTERPLAN-ABI.json",
              "plans/ROUTERPLAN-DEPLOYMENT.md", "plans/ROUTERPLAN-WORK-ORDER.md", "plans/ROUTERPLAN-WITNESSES.md",
              "plans/V1ALIGN-PLAN.md", "plans/SECGATE-WORK-ORDER.md", "plans/SECGATE2-WORK-ORDER.md",
              "review/secgate/RULING.md", "review/secgate/BINDING.json", "review/secgate2/RULING.md",
              "review/secgate2/BINDING.json", "review/secgate3/RULING.md", "review/secgate3/BINDING.json",
              "review/secgate3/VALIDATION.json", "review/r3gate/RULING.md", "review/routerplan/RULING.md",
              "review/routerplan/BASELINE.json", "review/ROUTERCONF5.md", "review/routerconf5/BINDING.json",
              "review/routerfix/receipts/CENSUS-LEDGER.md", "review/routerfix6/receipts/gates/GATES.json"]
    inputs += [str(current_root / "audits/glm-5.3/evidence" / name)
               for name in ("CurveFeeDistribution.vy", "GaugeController.vy", "VotiumFlattened.sol", "CrmFlattened.sol")]
    package = {path: sha(raw(path)) for path in (HERE + "RULING.md", HERE + "verify.py")}
    return {
        "schema": 1, "authority_id": "routergate", "candidate": CANDIDATE,
        "candidate_tree": git("rev-parse", CANDIDATE + "^{tree}").decode().strip(),
        "scope": "Authority-only per-item admission and historical evidence validation; no fresh product build/test/fleet/chain proof",
        "candidate_tracked_sha256": tracked, "product_baseline_sha256": product,
        "audit_rounds": audit_rounds, "final_two_blind_rounds": ["cgl-sec-r3", "cgl-router-fleet-r1"],
        "router_blind_round_count": 1, "prior_authority_git_bindings": prior_authority,
        "prior_documentation_confirmation": "P1-P4 and P5 D1-D4/O1-O4 plus secgate G4/secgate2 G3 COMPLETE in secgate3",
        "contracts_delta_since_sec_r3": contracts_delta,
        "conformance_bridge": {"reviewed_candidate": REVIEWED, "reviewed_tree": conf["tree"],
                               "candidate_delta": delta, "receipt_files": conf["files"],
                               "authority_inputs": conf["authority_inputs"], "selected_runs": selected_runs},
        "census": census, "saved_full_runs": saved_runs,
        "input_bindings": {path: digest(path) for path in inputs}, "carriers": carriers,
        "dispositions": dispositions, "activation_open": activation,
        "work_packages": {}, "executable_changes_authorized": [], "product_documentation_changes_authorized": [],
        "census_additions_authorized": [], "new_operational_implementation_authorized": [],
        "disclosure_location": "RULING.md section 2 and append-only existing PAO-AUTH bridge; existing activation/change-control duties retained",
        "rejected_executable_alternatives": {
            "CGL-05": "Independent owner/free-lane role split, owner==router.dao hard pin, automatic regrant plumbing",
            "CGL-06": "New successor handshake/allowlist/operability protocol or revival of retired routers",
            "CGL-07": "Constructor public-checkpoint getter/guard as fail-faster hardening",
            "CGL-I01": "Hardcoded production DAO or generic code-presence requirement in reusable constructor",
        },
        "router_fleet_convergence_certified": True, "campaign_audit_obligations_complete": True,
        "builder_status": "No outstanding audit builder or documentation work order",
        "activation": "HOLD; PAO-FD/CTL/AUTH and selected-deployment/operations/approval/trial cells remain ACTIVATION-OPEN",
        "future_executable_change_rule": "Any later adopted executable change needs a bounded order, implementation/conformance and one further blind router/security round after shipment",
        "bytecode_diff_expectation": "ZERO full creation/runtime difference including metadata under identical inputs; no fresh compilation claimed",
        "publication_allowlist": ALLOWLIST, "package_sha256": package,
        "reproduction_requires": "Named owner-held archived reports/snapshots, conformance receipts, PAO carriers and historical Git objects; public clone is not self-contained",
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--capture", action="store_true", help="emit initial binding; never writes or replaces it")
    args = parser.parse_args()
    observed = collect()
    if args.capture:
        print(json.dumps(observed, indent=2, ensure_ascii=False))
        return
    accepted = load(HERE + "BINDING.json")
    require(observed == accepted, "sealed BINDING differs from current evidence/ruling; investigate, do not auto-reseal")
    changes = set(git("diff", "--name-only", CANDIDATE).decode().splitlines())
    current_tracked = set(git("ls-files").decode().splitlines())
    additions = current_tracked - set(accepted["candidate_tracked_sha256"])
    require((changes | additions) <= set(ALLOWLIST), "publication/product path drift")
    git("diff", "--check")
    git("diff", "--cached", "--check")
    result = {
        "status": "PASS", "authority_id": "routergate", "candidate": CANDIDATE,
        "checked_at_utc": datetime.now(timezone.utc).isoformat(),
        "binding_sha256": sha(raw(HERE + "BINDING.json")),
        "candidate_tracked_files": len(accepted["candidate_tracked_sha256"]),
        "fleet_snapshot_product_files": len(accepted["product_baseline_sha256"]),
        "dispositions": len(accepted["dispositions"]), "registered_re_derivations": len(REPEATED),
        "final_two_blind_rounds": accepted["final_two_blind_rounds"], "final_two_critical_high": 0,
        "historical_round_one_conditional_high": 1, "router_blind_round_count": 1,
        "historical_default_pass_set": len(accepted["census"]["default"]),
        "historical_fork_pass_set": len(accepted["census"]["fork"]),
        "historical_full_runs_reconciled": len(accepted["saved_full_runs"]),
        "conformance_receipt_files_verified": len(accepted["conformance_bridge"]["receipt_files"]),
        "conformance_authority_inputs_verified": len(accepted["conformance_bridge"]["authority_inputs"]),
        "product_bytes_unchanged": True, "carrier_prefix_preserved": True,
        "fd_ctl_carriers_unchanged": True, "publication_scope_valid": True,
        "new_product_executions": 0, "new_chain_queries_or_transactions": 0,
        "campaign_audit_obligations_complete": True, "activation": "HOLD / ACTIVATION-OPEN",
    }
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
