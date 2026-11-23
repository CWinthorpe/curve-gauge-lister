#!/usr/bin/env python3
"""Validate the r3gate authority artifact; does not run or certify product tests."""

import hashlib
import json
import re
import subprocess
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PACKAGE = ROOT / "review/r3gate"


def digest(data):
    return hashlib.sha256(data).hexdigest()


def git(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT)


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def read(relative):
    return (ROOT / relative).read_text()


def main():
    lock = json.loads(read("review/r3gate/BINDING.json"))
    candidate = lock["candidate"]
    require(re.fullmatch(r"[0-9a-f]{40}", candidate) is not None, "candidate SHA format")
    require(git("rev-parse", candidate).decode().strip() == candidate, "candidate exists")
    require(
        subprocess.run(
            ["git", "merge-base", "--is-ancestor", candidate, "HEAD"],
            cwd=ROOT,
            check=False,
        ).returncode == 0,
        "authority HEAD must descend from the product candidate",
    )

    product = lock["product_baseline_sha256"]
    baseline_paths = git("ls-tree", "-r", "--name-only", candidate).decode().splitlines()
    require(set(baseline_paths) == set(product), "complete candidate tracked-path lock")
    snapshot = Path(lock["audit_snapshot"])
    for path, expected in product.items():
        require(digest(git("show", f"{candidate}:{path}")) == expected, f"Git binding: {path}")
        require(digest((ROOT / path).read_bytes()) == expected, f"product modified: {path}")
        require(digest((snapshot / path).read_bytes()) == expected, f"audit snapshot: {path}")

    carriers = {
        "review/simplify2/FD-BOUND-OBLIGATION.md": "PAO-FD",
        "review/simplify2/CTL-CALLER-ROLE-GATE.md": "PAO-CTL",
        "review/simplify2/AUTH-EVIDENCE-INDEX.md": "PAO-AUTH",
    }
    for path, expected in lock["input_sha256_before_ruling"].items():
        p = Path(path) if path.startswith("/") else ROOT / path
        if path in carriers:
            require(digest((snapshot / path).read_bytes()) == expected, f"carrier original: {path}")
            require(digest(p.read_bytes()) != expected, f"carrier amendment absent: {path}")
        else:
            require(digest(p.read_bytes()) == expected, f"sealed authority/input modified: {path}")
    for path, expected in lock["saved_inventory_sha256"].items():
        require(digest((ROOT / path).read_bytes()) == expected, f"saved receipt changed: {path}")

    inventory = json.loads(read("plans/V1ALIGN-WITNESS-INVENTORY.json"))
    census = {}
    for profile, count in (("default", 77), ("fork", 13)):
        rows = [
            row for row in inventory["identities"]
            if row["profile"] == profile and row["disposition"] in ("RETAIN_V1", "PORT_TRUST")
        ]
        signatures = sorted(
            row["target_identity_or_counterpart"].rsplit(":", 1)[0]
            + ":" + row["target_signature_or_counterpart"]
            for row in rows
        )
        require(signatures == lock["census"][profile], f"full signature lock: {profile}")
        require(len(signatures) == len(set(signatures)) == count, f"census uniqueness: {profile}")
        saved = json.loads(read(f"review/simplify2/receipts/final-identities-{profile}.json"))
        bare = [
            f"{file}:{contract}:{name}"
            for file, contracts in saved.items()
            for contract, names in contracts.items()
            for name in names
        ]
        require(
            sorted(bare) == sorted(row["target_identity_or_counterpart"] for row in rows),
            f"saved native receipt equality: {profile}",
        )
        census[profile] = {"identities": count, "set_equality": True, "duplicates": 0}

    ruling = read("review/r3gate/RULING.md")
    work = read("plans/R3GATE-WORK-ORDER.md")
    entries = re.findall(r"^\| (C\d{2}) \| (ADOPT|DEFER|REJECT) \| ([^\n]+) \|$", ruling, re.M)
    expected_dispositions = {
        "C01": "DEFER", "C02": "DEFER", "C03": "ADOPT", "C04": "DEFER",
        "C05": "ADOPT", "C06": "REJECT", "C07": "ADOPT", "C08": "REJECT",
        "C09": "REJECT", "C10": "REJECT", "C11": "REJECT", "C12": "REJECT",
        "C13": "ADOPT", "C14": "REJECT", "C15": "ADOPT", "C16": "REJECT",
    }
    require(len(entries) == len(expected_dispositions), "exactly one row per C01-C16")
    require({key: value for key, value, _ in entries} == expected_dispositions, "disposition ledger")
    require(all(reason.strip() for _, _, reason in entries), "one-line reasons")
    for key, disposition, _ in entries:
        require(key in work, f"work order disposition mapping: {key}")
        if disposition == "ADOPT":
            require(key in work.split("## Change allowlist")[0], f"bounded adopted scope: {key}")
    for gate in range(6):
        require(f"G{gate} —" in work, f"work-order gate G{gate}")
    require("77" in work and "13" in work and "file:contract:signature" in work, "census lock text")
    require("ZERO executable" in work, "comment-only executable freeze")
    require("No product" in ruling, "authority-only scope disclosure")
    require("Another full blind round is NOT warranted" in ruling, "convergence decision")
    require("Convergence has not yet been declared" in ruling, "no premature closure")
    require("NOT a confirmed simplification" in ruling, "binding future-engagement wording")
    require("A genuinely new defect remains reportable" in ruling, "no defect immunity")
    require("activation is HOLD" in ruling, "activation stop condition")

    for path, identifier in carriers.items():
        text = read(path)
        require(candidate in text and identifier in text, f"candidate/obligation: {path}")
        require("SATISFIED-TRACKING / ACTIVATION-OPEN" in text, f"two statuses: {path}")
    index = read("review/simplify2/AUTH-EVIDENCE-INDEX.md")
    marker_line = next(line for line in index.splitlines() if line.startswith("| `plan §4`"))
    require("§2.1" in marker_line and "§1.3" not in marker_line, "admission marker repaired")
    require("FORK-CLAUSE-RESOLUTION.md" in index, "fork resolution pointer")
    require("IIncentivePlatform.deposit" in index, "common receipt owner")
    require("MULTISET" in index and "NOT lifecycle order" in index, "approval evidence scope")
    require("identity equality is not itself proof of unchanged assertions" in index, "assertion/census distinction")
    require("SIMULATION" in read("review/simplify2/CTL-CALLER-ROLE-GATE.md"), "controller evidence phase")
    require("TOTAL" in read("review/simplify2/FD-BOUND-OBLIGATION.md"), "commingled FD delta")

    archive_objects = {
        "45a73a2979b53f5514d00014ea34f4c05851b6de":
            "508a0459bed332b922640ede361ea190ff3803418578e693db5e2adf11eff2a6",
        "74f0484fba2f0e47591d410486d46a6723a02754":
            "4f28f1d214de405e4c82805e229130e3f07130ba63b45bc31a22cce27c3e0fc4",
    }
    resolution = read("review/r3gate/FORK-CLAUSE-RESOLUTION.md")
    for commit, expected in archive_objects.items():
        require(digest(git("show", f"{commit}:plans/FORK-PLAN.md")) == expected, "archived fork approval")
        require(commit in resolution and expected in resolution, "archival citation/digest")
        require(
            subprocess.run(["git", "merge-base", "--is-ancestor", commit, candidate], cwd=ROOT, check=False).returncode == 1,
            "archived fork object is not represented as an ancestor",
        )

    allowed = {
        "plans/R3GATE-BRIEF.md", "plans/R3GATE-WORK-ORDER.md",
        "review/r3gate/RULING.md", "review/r3gate/BINDING.json",
        "review/r3gate/FORK-CLAUSE-RESOLUTION.md", "review/r3gate/verify.py",
        "review/r3gate/VALIDATION.json", *carriers,
    }
    changed = set(git("diff", "--name-only", candidate).decode().splitlines())
    require(changed <= allowed, f"unauthorized changed paths: {sorted(changed - allowed)}")
    require(not git("diff", "--name-only", candidate, "--", *product).strip(), "product Git diff empty")
    whitespace = subprocess.run(["git", "diff", "--check", candidate], cwd=ROOT, capture_output=True, text=True)
    require(whitespace.returncode == 0, whitespace.stdout + whitespace.stderr)

    documents = sorted(allowed - {"review/r3gate/VALIDATION.json"})
    for path in documents:
        require((ROOT / path).is_file(), f"document exists: {path}")
        text = (ROOT / path).read_text()
        require(text.endswith("\n"), f"final newline: {path}")
        require(all(line == line.rstrip() for line in text.splitlines()), f"trailing whitespace: {path}")

    print(json.dumps({
        "status": "PASS",
        "candidate": candidate,
        "authority_head_at_validation": git("rev-parse", "HEAD").decode().strip(),
        "verification_scope": "Static authority artifacts, frozen bytes and saved inventory reconciliation only",
        "fresh_product_build_or_test_execution": False,
        "all_candidate_tracked_files_unchanged_and_equal_to_audit_snapshot": len(product),
        "sealed_inputs_unchanged_except_three_authorized_carriers": True,
        "census": census,
        "dispositions": {key: value for key, value, _ in entries},
        "disposition_counts": dict(sorted(Counter(value for _, value, _ in entries).items())),
        "historical_fork_approval_objects_verified": archive_objects,
        "changed_paths_at_validation": sorted(changed),
        "scope_check": "PASS",
        "git_diff_check_exit": whitespace.returncode,
        "document_sha256": {path: digest((ROOT / path).read_bytes()) for path in documents},
        "semantic_review_boundary": "Mechanical checks supplement, not substitute for, the authority's source-bound ruling",
    }, indent=2))


if __name__ == "__main__":
    main()
