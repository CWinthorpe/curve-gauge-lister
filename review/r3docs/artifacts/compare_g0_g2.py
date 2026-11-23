#!/usr/bin/env python3
"""r3docs gate helper:
(a) unauthorized-file freeze: every file in BINDING.json
    product_baseline_sha256 that is NOT on the admitted allowlist must be
    byte-identical (sha256) to the bound baseline;
(b) admitted Solidity files: executable token streams identical to
    d88d633 (string-aware comment strip via token_cmp);
(c) artifact comparison: for the three product deployables the executable
    (validated-metadata-stripped) creation and runtime hashes must equal the
    recorded baseline under a profile; full-hash drift is permitted only
    when the parsed trailer validates; test-contract executable drift is
    reported for disclosure (embedded creation-code metadata, G2 note).

Usage: compare_g0_g2.py BASELINE_DEFAULT.json BASELINE_FORK.json NEW_DEFAULT.json NEW_FORK.json
Reads allowlist from R3DOCS_ALLOW env (colon-separated) or built-in.
"""
import hashlib
import json
import subprocess
import sys

sys.path.insert(0, "/home/winny/.hermes/profiles/qwen-executor/cache/scratch/r3docs")
from token_cmp import strip_keep_tokens  # noqa: E402

REPO = "/home/winny/curve-gauge-lister"
DEPLOYABLES = [
    "CurveGaugeLister.sol/CurveGaugeLister.json",
    "VoteMarketAdapter.sol/VoteMarketAdapter.json",
    "VotiumAdapter.sol/VotiumAdapter.json",
]
ALLOW_SOL = [
    "contracts/adapters/VoteMarketAdapter.sol",
    "contracts/adapters/VotiumAdapter.sol",
    "contracts/interfaces/ICampaignRemoteManager.sol",
    "contracts/libraries/SafeToken.sol",
    "test/fork/ForkFixture.sol",
    "test/fork/ForkVoteMarket.t.sol",
]
ALLOW_OTHER = [
    "README.md", "docs/OPERATIONS.md", "docs/ABI.md", "docs/CURVE-PROPOSAL.md",
]


def sha_file(path):
    return hashlib.sha256(open(path, "rb").read()).hexdigest()


def load_out(p):
    d = json.load(open(p))
    return {k: v for k, v in d.items() if not k.startswith("build-info/")}


def main():
    fail = []
    binding = json.load(open(f"{REPO}/review/r3gate/BINDING.json"))
    baseline_hashes = binding["product_baseline_sha256"]
    allowed = set(ALLOW_SOL) | set(ALLOW_OTHER)
    for f, want in sorted(baseline_hashes.items()):
        if f in allowed:
            continue
        try:
            got = sha_file(f"{REPO}/{f}")
        except OSError as e:
            fail.append(f"(a) MISSING {f}: {e}")
            continue
        if got != want:
            fail.append(f"(a) UNAUTHORIZED DRIFT {f}")
    print(f"(a) unauthorized files checked: {len(baseline_hashes) - len(allowed)} "
          f"(allowlist: {len(allowed)})")

    for f in ALLOW_SOL:
        old = subprocess.run(["git", "show", f"d88d633:{f}"], cwd=REPO,
                             capture_output=True, text=True, check=True).stdout
        new = open(f"{REPO}/{f}").read()
        if strip_keep_tokens(old) != strip_keep_tokens(new):
            fail.append(f"(b) EXECUTABLE TOKEN DELTA {f}")
    print(f"(b) admitted .sol executable-token identity checked: {len(ALLOW_SOL)} files")

    for prof, bpath, np_ in (
        ("default", sys.argv[1], sys.argv[3]),
        ("fork", sys.argv[2], sys.argv[4]),
    ):
        b, n = load_out(bpath), load_out(np_)
        if set(b) != set(n):
            fail.append(f"(c) {prof}: artifact record set differs")
            continue
        for k in DEPLOYABLES:
            for side in ("creation", "runtime"):
                br, nr = b[k][side], n[k][side]
                if "metadata_parse_error" in br or "metadata_parse_error" in nr:
                    fail.append(f"(c) {prof}: trailer parse failure {k} {side}")
                if br["executable_sha256"] != nr["executable_sha256"]:
                    fail.append(f"(c) {prof}: DEPLOYABLE EXECUTIVE DELTA {k} {side}")
                if br["full_sha256"] != nr["full_sha256"]:
                    print(f"(c) {prof}: full-hash metadata-trailer drift (disclosed, "
                          f"executable identical) {k} {side}")
        test_drift = sorted(
            k for k in b
            if k not in DEPLOYABLES
            and ("creation" in b[k] and b[k]["creation"]["executable_sha256"] != n[k]["creation"]["executable_sha256"]
                 or "runtime" in b[k] and b[k]["runtime"]["executable_sha256"] != n[k]["runtime"]["executable_sha256"]))
        if test_drift:
            print(f"(c) {prof}: test-artifact executable moves (embedded product "
                  f"creation-code metadata; sources frozen by (a)/(b)): {test_drift}")
        print(f"(c) {prof}: {len(b)} artifact records compared")

    if fail:
        print("FAIL")
        for x in fail:
            print(" ", x)
        return 1
    print("ALL GATES (a)(b)(c) PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
