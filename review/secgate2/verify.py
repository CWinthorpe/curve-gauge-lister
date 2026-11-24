#!/usr/bin/env python3
"""Validate secgate2 authority artifacts; no build, product tests or chain calls."""
import collections
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
CHECKS = []


def require(condition, name):
    if not condition:
        raise ValueError(name)
    CHECKS.append(name)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def unique_keys(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON key: {key}")
        result[key] = value
    return result


def load(path):
    return json.loads((ROOT / path).read_text(), object_pairs_hook=unique_keys)


def git(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT)


def ancestor(base, tip):
    result = subprocess.run(["git", "merge-base", "--is-ancestor", base, tip], cwd=ROOT)
    require(result.returncode in (0, 1), f"valid ancestry query: {base}")
    return result.returncode == 0


def report_rows(path):
    result = []
    for line in (ROOT / path).read_text().splitlines():
        if re.match(r"^\| (?:CGL-)?[VI]-?\d{2} \|", line):
            row = [cell.strip() for cell in line.split("|")[1:-1]]
            result.append({"id": row[0], "severity": row[2], "flagged_by": row[4]})
    return result


def severity_counts(rows):
    result = dict.fromkeys(["Critical", "High", "Medium", "Low", "Informational"], 0)
    for row in rows:
        result[row["severity"].split()[0]] += 1
    return result


def saved_discovery(path, census):
    file = contract = None
    resolved = []
    for line in (ROOT / path).read_text().splitlines():
        if re.fullmatch(r"(?:test|fork)/\S+\.sol", line):
            file, contract = line, None
        elif re.fullmatch(r"  \w+", line):
            contract = line.strip()
        elif re.fullmatch(r"    test\w+", line):
            require(file is not None and contract is not None, f"discovery context: {line}")
            bare = f"{file}:{contract}:{line.strip()}"
            matches = [identity for identity in census if identity.rsplit("(", 1)[0] == bare]
            require(len(matches) == 1, f"unique normative signature: {bare}")
            resolved.append(matches[0])
    require(sorted(resolved) == census and len(resolved) == len(set(resolved)),
            f"exact saved discovery: {path}")


def saved_passes(path, census):
    suite = None
    executed = []
    text = (ROOT / path).read_text()
    for line in text.splitlines():
        header = re.fullmatch(r"Ran \d+ tests? for ((?:test|fork)/[^:]+:\S+)", line)
        if header:
            suite = header.group(1)
        result = re.match(r"\[PASS\] (\S+\([^)]*\))", line)
        if result:
            require(suite is not None, f"PASS context: {path}")
            executed.append(f"{suite}:{result.group(1)}")
        require(not re.match(r"\[(?:FAIL|SKIP)", line), f"no saved failure/skip: {path}")
    require(sorted(executed) == census and len(executed) == len(set(executed)),
            f"exact saved PASS set: {path}")
    require(re.search(rf"{len(census)} tests passed, 0 failed, 0 skipped", text) is not None,
            f"native summary agrees: {path}")


def main():
    binding_path = ROOT / "review/secgate2/BINDING.json"
    b = load(binding_path)
    candidate = b["candidate"]
    require(re.fullmatch(r"[0-9a-f]{40}", candidate) is not None, "full candidate identifier")
    require(git("rev-parse", candidate).decode().strip() == candidate, "candidate object available")
    require(git("branch", "--show-current").decode().strip() == "main", "main branch")
    require(ancestor(candidate, "HEAD"), "HEAD descends from reviewed candidate")
    tracked = git("ls-tree", "-r", "--name-only", candidate).decode().splitlines()
    require(set(tracked) == set(b["candidate_tracked_sha256"]), "complete candidate tracked binding")
    product = {p: d for p, d in b["candidate_tracked_sha256"].items()
               if not p.startswith(("plans/", "review/"))}
    require(product == b["product_baseline_sha256"] and len(product) == 53,
            "exact 53-file product binding")
    for path, digest in b["candidate_tracked_sha256"].items():
        source = git("show", f"{candidate}:{path}")
        require(sha(source) == digest, f"candidate digest: {path}")
        require((ROOT / path).read_bytes() == source, f"unchanged working candidate: {path}")

    published = set(b["publication_allowlist"])
    current = set(git("ls-files").decode().splitlines())
    require(current - set(tracked) <= published, "tracked additions confined to publication allowlist")
    for args in [("diff", "--name-only", candidate, "HEAD"), ("diff", "--name-only"),
                 ("diff", "--cached", "--name-only")]:
        require(set(git(*args).decode().splitlines()) <= published, "scope: " + " ".join(args))
    for args in [("diff", "--check"), ("diff", "--cached", "--check"),
                 ("diff", "--check", candidate, "HEAD")]:
        result = subprocess.run(["git", *args], cwd=ROOT, capture_output=True)
        require(result.returncode == 0, "git " + " ".join(args))

    for path, record in b["input_bindings_before_ruling"].items():
        content = (ROOT / path).read_bytes()
        if path in b["carriers"]:
            content = content[:record["bytes"]]
        require(len(content) == record["bytes"] and sha(content) == record["sha256"],
                f"input or preserved prefix: {path}")
    for path, record in b["carriers"].items():
        content = (ROOT / path).read_bytes()
        require(sha(content) == record["sha256_after"], f"carrier final digest: {path}")
        require(sha(content[:record["bytes_before"]]) == record["sha256_before"],
                f"carrier original prefix: {path}")
        require(path not in current, f"carrier remains untracked: {path}")
        require(subprocess.run(["git", "check-ignore", "-q", path], cwd=ROOT).returncode == 0,
                f"carrier remains ignored: {path}")
        if record["obligation"] == "PAO-AUTH":
            suffix = content[record["bytes_before"]:].decode()
            require(suffix.startswith("\n## secgate2") and candidate in suffix
                    and "CGL-V05" in suffix and "ACTIVATION-OPEN" in suffix
                    and "P5" in suffix and "CONVERGENCE NOT CERTIFIED" in suffix,
                    "new Votium registration and open work in same AUTH carrier")
        else:
            require(len(content) == record["bytes_before"], f"FD/CTL not amended: {path}")
    for spec, record in b["historical_authority_bindings"].items():
        data = git("show", spec)
        require(len(data) == record["bytes"] and sha(data) == record["sha256"],
                f"historical authority bytes: {spec}")
        require(git("rev-parse", spec).decode().strip() == record["git_blob"],
                f"historical blob identity: {spec}")
        require(ancestor(spec.split(":")[0], candidate) == record["ancestor_of_candidate"],
                f"historical ancestry not invented: {spec}")

    round_counts = {}
    for name, record in b["audit_rounds"].items():
        revision, snapshot = record["candidate"], Path(record["audit_snapshot"])
        paths = git("ls-tree", "-r", "--name-only", revision).decode().splitlines()
        missing, matched = [], {}
        for path in paths:
            if not (snapshot / path).is_file():
                missing.append(path)
                continue
            data = git("show", f"{revision}:{path}")
            require((snapshot / path).read_bytes() == data, f"{name} snapshot equality: {path}")
            matched[path] = sha(data)
        require(missing == record["audit_snapshot_missing_tracked_paths"], f"{name} exact absent paths")
        require(all(p.startswith(("plans/", "review/")) for p in missing), f"{name} no missing product")
        require(matched == record["snapshot_matched_sha256"], f"{name} snapshot manifest")
        rows = report_rows(record["report"])
        require(rows == record["findings"], f"{name} exact report IDs/severities/attribution")
        require(len({row["id"] for row in rows}) == len(rows), f"{name} no repeated report item")
        round_counts[name] = severity_counts(rows)
        require(round_counts[name] == record["severity_counts"], f"{name} severity totals")
    require(round_counts["cgl-sec-r1"]["High"] == 1
            and round_counts["cgl-sec-r2"]["High"] == 0
            and all(counts["Critical"] == 0 for counts in round_counts.values()),
            "historical conditional High preserved; r2 zero Critical/High")
    attribution = {row["id"]: len(row["flagged_by"].split(", "))
                   for row in b["audit_rounds"]["cgl-sec-r2"]["findings"][:5]}
    require(attribution == b["finding_attribution_counts"], "exact vulnerability attribution counts")
    require(list(attribution.values()) == [8, 8, 6, 6, 1], "unanimity not overstated")

    prior = load("review/secgate/BINDING.json")
    bridge = b["builder_bridge"]
    require(git("diff", "--name-only", bridge["base"], candidate).decode().splitlines()
            == bridge["changed_paths"], "exact preceding docs-only builder delta")
    require(all(p == "README.md" or p.startswith("docs/") for p in bridge["changed_paths"]),
            "builder changes only public prose paths")
    for path, digest in prior["product_baseline_sha256"].items():
        if path not in bridge["changed_paths"]:
            require(product[path] == digest, f"product frozen through both rounds: {path}")
    receipts = load("review/secdocs/RECEIPTS.json")
    require(receipts["final"] == candidate and receipts["base"] == bridge["base"],
            "saved builder receipts bind actual candidate")
    for path, digest in receipts["receipt_files"].items():
        require(sha((ROOT / path).read_bytes()) == digest, f"saved receipt integrity: {path}")
    manifest = load("review/secdocs/final-tree-manifest.json")
    require(manifest["final_head"] == candidate and manifest["sha256"] == b["candidate_tracked_sha256"],
            "builder final-tree manifest equals full candidate")
    inventory = load("plans/V1ALIGN-WITNESS-INVENTORY.json")["identities"]
    for profile, count in [("default", 77), ("fork", 13)]:
        want = b["census"][profile]
        normative = sorted(row["target_identity_or_counterpart"].rsplit(":", 1)[0] + ":"
                           + row["target_signature_or_counterpart"] for row in inventory
                           if row["profile"] == profile and row["disposition"] in {"RETAIN_V1", "PORT_TRUST"})
        require(want == sorted(set(want)) and len(want) == count, f"exact {profile} census")
        require(want == normative == prior["census"][profile], f"{profile} authority census equality")
        saved_discovery(f"review/secdocs/files/discover-{profile}.txt", want)
    for stem, profile in [("test-offline", "default"), ("test-offline-unreachable", "default"),
                          ("test-fork", "fork")]:
        saved_passes(f"review/secdocs/files/{stem}.txt", b["census"][profile])

    for path, digest in b["package_sha256"].items():
        require(sha((ROOT / path).read_bytes()) == digest, f"package digest: {path}")
    ruling = (ROOT / "review/secgate2/RULING.md").read_text()
    work = (ROOT / "plans/SECGATE2-WORK-ORDER.md").read_text()
    rows = re.findall(r"^\| (CGL-[VI]\d{2}) \| ([A-Z-]+) \| (.+) \|$", ruling, re.M)
    ids = [f"CGL-V{i:02d}" for i in range(1, 6)] + [f"CGL-I{i:02d}" for i in range(1, 12)]
    require([row[0] for row in rows] == ids, "exact five findings and eleven informational rulings")
    require(set(b["dispositions"]) == set(ids), "exact JSON disposition coverage")
    for key, status, grounds in rows:
        record = b["dispositions"][key]
        require(status == record["ruling"] and grounds == record["grounds"], f"JSON/ruling agreement: {key}")
        require(bool(record["lineage"]), f"explicit lineage or new-decision boundary: {key}")
        require(record["work_package"] == ("P5" if key == "CGL-V05" else None),
                f"only Votium creates builder work: {key}")
    require(b["work_packages"] == {"P5": {"items": ["CGL-V05"],
            "files": ["docs/OPERATIONS.md", "docs/CURVE-PROPOSAL.md"],
            "acceptance_cells": ["D1", "D2", "D3", "D4", "O1", "O2", "O3", "O4"]}},
            "bounded P5 exact scope")
    require(re.findall(r"^\| ([DO][1-4]) \|", work, re.M)
            == b["work_packages"]["P5"]["acceptance_cells"], "all P5 acceptance cells present once")
    require("## P5 — CGL-V05" in work and "original secgate §6" in work.lower(),
            "work-order row and prior registration bound")
    original = next(line for line in (ROOT / "review/secgate/RULING.md").read_text().splitlines()
                    if line.startswith("> Review the candidate"))
    supplement = next(line for line in ruling.splitlines() if line.startswith("> Apply review/secgate2"))
    require(sha(original.encode()) == b["original_registration_paragraph_sha256"]
            == prior["future_registration_paragraph_sha256"], "original registration paragraph preserved")
    require(sha(supplement.encode()) == b["future_registration_supplement_sha256"],
            "new registration supplement bound")
    disclosure = next(line for line in ruling.splitlines() if line.startswith("> A successfully funded Votium"))
    require(disclosure in work and sha(disclosure.encode()) == b["disclosure_paragraph_sha256"],
            "exact Votium disclosure supplied in both authority and order")
    require(b["executable_changes_authorized"] == [] and b["census_additions_authorized"] == [],
            "no executable/census authorization")
    require(b["security_convergence_certified"] is False and b["builder_status"] == "P5 OPEN"
            and "CONVERGENCE NOT CERTIFIED AT 4a442e6" in ruling,
            "convergence withheld for finite disclosure/ops delta")
    require(b["activation"] == "HOLD; PAO-FD/CTL/AUTH ACTIVATION-OPEN; approvals and operational readiness OPEN",
            "activation not closed by artifact validation")
    return {
        "status": "PASS",
        "scope": "Executed authority-artifact checks only; saved tests historical, no fresh product build/tests/chain proof",
        "candidate": candidate,
        "binding_sha256": sha(binding_path.read_bytes()),
        "all_items": ids,
        "dispositions": dict(collections.Counter(status for _, status, _ in rows)),
        "audit_severity_counts": round_counts,
        "finding_attribution_counts": attribution,
        "candidate_tracked_files": len(tracked),
        "unchanged_product_files": len(product),
        "saved_receipt_digests_verified": len(receipts["receipt_files"]),
        "census": {profile: len(want) for profile, want in b["census"].items()},
        "saved_native_results": "secgate-exec discovery and 77/77/13 PASS sets reconciled; not rerun",
        "carrier_prefixes_preserved": sorted(b["carriers"]),
        "amended_carriers": [p for p, r in b["carriers"].items() if r["obligation"] == "PAO-AUTH"],
        "carriers_published": False,
        "fresh_product_tests_run": False,
        "security_convergence_certified": False,
        "builder_status": b["builder_status"],
        "prior_secgate_G4_confirmation": "OPEN; not performed by this authority intake",
        "activation": b["activation"],
        "checks_passed": len(CHECKS),
    }


if __name__ == "__main__":
    try:
        print(json.dumps(main(), indent=2, sort_keys=True))
    except (ValueError, OSError, KeyError, IndexError, StopIteration, subprocess.CalledProcessError) as error:
        print(json.dumps({"status": "FAIL", "error": str(error), "checks_passed": len(CHECKS)}, indent=2))
        sys.exit(1)
