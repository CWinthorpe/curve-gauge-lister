#!/usr/bin/env python3
"""Read-only secgate authority checks; no product build/test/chain execution."""
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


def no_duplicate_keys(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON key: {key}")
        result[key] = value
    return result


def load(path):
    return json.loads((ROOT / path).read_text(), object_pairs_hook=no_duplicate_keys)


def git(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT)


def main():
    binding_path = ROOT / "review/secgate/BINDING.json"
    binding = load(binding_path)
    candidate = binding["candidate"]
    require(re.fullmatch(r"[0-9a-f]{40}", candidate) is not None, "full candidate identifier")
    require(git("rev-parse", candidate).decode().strip() == candidate, "candidate object available")
    require(git("branch", "--show-current").decode().strip() == "main", "main branch")
    require(subprocess.run(["git", "merge-base", "--is-ancestor", candidate, "HEAD"],
                           cwd=ROOT, check=False).returncode == 0, "HEAD descends from candidate")

    tracked = git("ls-tree", "-r", "--name-only", candidate).decode().splitlines()
    expected = binding["candidate_tracked_sha256"]
    require(set(tracked) == set(expected), "complete candidate tracked-file binding")
    product_paths = [p for p in tracked if not p.startswith(("plans/", "review/"))]
    require(len(product_paths) == 53, "53 candidate product/test/doc/configuration paths")
    require(binding["product_baseline_sha256"] == {p: expected[p] for p in product_paths},
            "product binding excludes only separately published report")
    snapshot = Path(binding["audit_snapshot"])
    absent = []
    for path in tracked:
        source = git("show", f"{candidate}:{path}")
        require(sha(source) == expected[path], f"candidate digest: {path}")
        require((ROOT / path).read_bytes() == source, f"working freeze: {path}")
        if (snapshot / path).is_file():
            require((snapshot / path).read_bytes() == source, f"audit snapshot: {path}")
        else:
            absent.append(path)
    require(absent == binding["audit_snapshot_absent_tracked_paths"] == ["review/R3CONFIRM.md"],
            "snapshot omits only the report")
    confirmed = binding["confirmed_product_parent"]
    require(git("diff", "--name-only", confirmed, candidate).decode().splitlines()
            == ["review/R3CONFIRM.md"], "confirmed-parent product bridge")

    published = set(binding["publication_allowlist"])
    current_paths = set(git("ls-files").decode().splitlines())
    require(current_paths - set(tracked) <= published, "no unexpected tracked additions")
    require(set(git("diff", "--name-only", candidate, "HEAD").decode().splitlines()) <= published,
            "committed delta limited to publication exception")
    for args in [("diff", "--check"), ("diff", "--cached", "--check"),
                 ("diff", "--check", candidate, "HEAD")]:
        require(subprocess.run(["git", *args], cwd=ROOT, check=False,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE).returncode == 0,
                "git " + " ".join(args))

    carriers = binding["carriers"]
    for path, before in binding["input_bindings_before_ruling"].items():
        content = (ROOT / path).read_bytes()
        if path in carriers:
            content = content[:before["bytes"]]
        require(len(content) == before["bytes"] and sha(content) == before["sha256"],
                f"input or preserved carrier prefix: {path}")
    for path, record in carriers.items():
        content = (ROOT / path).read_bytes()
        require(sha(content) == record["sha256_after"], f"final carrier digest: {path}")
        require(content[record["bytes_before"]:].startswith(b"\n## secgate"),
                f"append-only secgate supplement: {path}")
        text = content[record["bytes_before"]:].decode()
        require(candidate in text and "ACTIVATION-OPEN" in text and "REGISTERED" in text
                if record["obligation"] != "PAO-AUTH"
                else candidate in text and "ACTIVATION-OPEN" in text and "registration rule" in text,
                f"candidate/status/registration: {path}")
        require(path not in current_paths, f"owner-held carrier remains untracked: {path}")
        require(subprocess.run(["git", "check-ignore", "-q", path], cwd=ROOT,
                               check=False).returncode == 0, f"carrier ignored: {path}")

    for spec, record in binding["historical_authority_bindings"].items():
        source = git("show", spec)
        require(sha(source) == record["sha256"] and len(source) == record["bytes"],
                f"historical authority bytes: {spec}")
        require(git("rev-parse", spec).decode().strip() == record["git_blob"],
                f"historical authority blob: {spec}")
        ancestor = subprocess.run(["git", "merge-base", "--is-ancestor", spec.split(":")[0], candidate],
                                  cwd=ROOT, check=False).returncode == 0
        require(ancestor == record["ancestor_of_candidate"], f"historical ancestry scope: {spec}")

    for path, digest in binding["package_sha256"].items():
        require(sha((ROOT / path).read_bytes()) == digest, f"package digest: {path}")
    ruling = (ROOT / "review/secgate/RULING.md").read_text()
    work = (ROOT / "plans/SECGATE-WORK-ORDER.md").read_text()
    rows = re.findall(r"^\| ([VI]-\d{2}) \| ([A-Z-]+) \| (.+) \|$", ruling, re.M)
    ids = [row[0] for row in rows]
    all_ids = [f"V-{i:02d}" for i in range(1, 9)] + [f"I-{i:02d}" for i in range(1, 8)]
    require(ids == all_ids and len(ids) == len(set(ids)), "all 15 items ruled exactly once")
    require({key: status for key, status, _ in rows}
            == {key: row["ruling"] for key, row in binding["dispositions"].items()},
            "JSON and ruling dispositions agree")
    require(all(grounds.strip() for _, _, grounds in rows), "one-line grounds for every item")
    require(all(status in {"ADOPT", "DEFER", "REJECT", "ACCEPT-WITH-REASON"}
                for _, status, _ in rows), "allowed dispositions only")
    for key, row in binding["dispositions"].items():
        if row["ruling"] == "ADOPT":
            require(row["work_package"] in binding["work_packages"], f"adopted work package: {key}")
            require(key in binding["work_packages"][row["work_package"]]["items"],
                    f"package maps adopted row: {key}")
        else:
            require(row["work_package"] is None, f"no non-adopted builder work: {key}")
        if row["ruling"] == "ACCEPT-WITH-REASON":
            require(bool(row["lineage"]), f"acceptance lineage: {key}")
    package_items = []
    for package, record in binding["work_packages"].items():
        heading = re.search(rf"^## {package} — (.+)$", work, re.M)
        require(heading is not None and all(item in heading.group(1) for item in record["items"]),
                f"work-order heading binds items: {package}")
        package_items.extend(record["items"])
    require(sorted(package_items) == sorted(k for k, v in binding["dispositions"].items()
                                            if v["ruling"] == "ADOPT"), "exact ADOPT-only work mapping")
    require(binding["executable_changes_authorized"] == [] and binding["census_additions_authorized"] == [],
            "no executable changes or census additions")
    paragraph = next(line for line in ruling.splitlines() if line.startswith("> Review the candidate"))
    require(sha(paragraph.encode()) == binding["future_registration_paragraph_sha256"],
            "exact future blind-round registration standard")
    require("INVALID AS A PRODUCTION INTEGRATION TEMPLATE" in ruling
            and "No concrete intermediary address" in ruling
            and "ZERO, including compiler metadata" in ruling,
            "controller/non-selection/full-bytecode boundaries explicit")

    prior = load("review/r3gate/BINDING.json")["census"]
    inventory = load("plans/V1ALIGN-WITNESS-INVENTORY.json")["identities"]
    saved = ROOT / "review/r3confirm2"
    receipt_manifest = load(saved / "RECEIPTS.json")
    require(receipt_manifest["candidate"] == confirmed, "saved receipts bind confirmed parent")
    for path, digest in receipt_manifest["receipt_sha256"].items():
        require(sha((saved / path).read_bytes()) == digest, f"saved receipt integrity: {path}")
    # Historical carrier hashes apply to preserved original prefixes, not amended files.
    for path, digest in receipt_manifest["authority_sha256"].items():
        content = (ROOT / path).read_bytes()
        if path in carriers:
            content = content[:carriers[path]["bytes_before"]]
        require(sha(content) == digest, f"saved authority integrity at original scope: {path}")

    census = binding["census"]
    for profile, count in [("default", 77), ("fork", 13)]:
        want = census[profile]
        require(want == sorted(set(want)) and len(want) == count, f"exact {profile} census/count")
        normative = sorted(row["target_identity_or_counterpart"].rsplit(":", 1)[0] + ":"
                           + row["target_signature_or_counterpart"] for row in inventory
                           if row["profile"] == profile and row["disposition"] in {"RETAIN_V1", "PORT_TRUST"})
        require(want == normative == sorted(prior[profile]), f"{profile} normative/r3gate identities")
        native = load(saved / f"candidate-{profile}-list.stdout")
        bare = [f"{file}:{contract}:{test}" for file, contracts in native.items()
                for contract, tests in contracts.items() for test in tests]
        resolved = []
        for item in bare:
            matches = [sig for sig in want if sig.rsplit("(", 1)[0] == item]
            require(len(matches) == 1, f"unique saved signature resolution: {item}")
            resolved.append(matches[0])
        require(sorted(resolved) == want and len(resolved) == len(set(resolved)),
                f"saved native {profile} discovery equals census")
        require(load(saved / f"candidate-{profile}-list.run.json")["exit_code"] == 0,
                f"saved native {profile} discovery exit")
    for stem in ["candidate-offline-test", "candidate-unreachable-test"]:
        native = load(saved / f"{stem}.stdout")
        executed = []
        for suite, data in native.items():
            for signature, result in data["test_results"].items():
                require(result["status"] == "Success", f"saved PASS: {stem}:{suite}:{signature}")
                executed.append(f"{suite}:{signature}")
        require(sorted(executed) == census["default"] and len(executed) == len(set(executed)),
                f"saved {stem} executed exact census, no failures/skips")
        require(load(saved / f"{stem}.run.json")["exit_code"] == 0, f"saved {stem} native exit")
    fork_pass = []
    suite = None
    for line in (saved / "candidate-cold-fork-wrapper.stdout").read_text().splitlines():
        header = re.fullmatch(r"Ran \d+ tests? for (fork/[^:]+:[^\s]+)", line)
        if header:
            suite = header.group(1)
        result = re.match(r"\[PASS\] (\S+\([^)]*\))", line)
        if result:
            require(suite is not None, "saved fork PASS has suite")
            fork_pass.append(f"{suite}:{result.group(1)}")
        require(not re.match(r"\[(?:FAIL|SKIP)", line), "saved fork no failed/skipped identity")
    require(sorted(fork_pass) == census["fork"] and len(fork_pass) == len(set(fork_pass)),
            "saved fork executed exact census")
    require(load(saved / "candidate-cold-fork-wrapper.run.json")["exit_code"] == 0,
            "saved fork native exit")
    return {
        "status": "PASS",
        "scope": "Executed authority-artifact checks only; no fresh product build/test/fork/live-chain proof",
        "candidate": candidate,
        "confirmed_product_parent": confirmed,
        "binding_sha256": sha(binding_path.read_bytes()),
        "rulings": dict(collections.Counter(status for _, status, _ in rows)),
        "all_items": ids,
        "unchanged_product_files": len(product_paths),
        "audit_product_snapshot_byte_equal": True,
        "historical_report_snapshot_absent": absent,
        "census": {p: len(c) for p, c in census.items()},
        "native_results_reconciled": "historical r3confirm2 only; default + unreachable + raw-target fork",
        "saved_receipt_digests_verified": len(receipt_manifest["receipt_sha256"]),
        "carrier_prefixes_preserved": sorted(carriers),
        "owner_held_carriers_published": False,
        "executable_changes_authorized": [],
        "fresh_product_tests_run": False,
        "activation": "HOLD; PAO-FD/CTL/AUTH ACTIVATION-OPEN; direct raw-admin composition PROHIBITED",
        "checks_passed": len(CHECKS),
    }


if __name__ == "__main__":
    try:
        print(json.dumps(main(), indent=2, sort_keys=True))
    except (ValueError, OSError, KeyError, subprocess.CalledProcessError) as error:
        print(json.dumps({"status": "FAIL", "error": str(error), "checks_passed": len(CHECKS)}, indent=2))
        sys.exit(1)
