#!/usr/bin/env python3
"""Read-only product baseline collection. All durable writes are in this directory."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
SCRATCH = Path(tempfile.mkdtemp(prefix="v1align-", dir=os.environ["TMPDIR"]))
SUMMARY = {"candidate": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(), "scratch": str(SCRATCH), "commands": [], "profiles": {}}


def run(name, argv, env):
    started = time.time()
    with (HERE / (name + ".txt")).open("w") as stream:
        result = subprocess.run(argv, cwd=ROOT, env=env, stdout=stream, stderr=subprocess.STDOUT)
    SUMMARY["commands"].append({"name": name, "argv": argv, "cwd": str(ROOT), "profile": env.get("FOUNDRY_PROFILE"), "exit": result.returncode, "seconds": round(time.time() - started, 3)})
    print(name, result.returncode, flush=True)
    return result.returncode


def digest(data):
    return hashlib.sha256(data).hexdigest()


tracked = subprocess.check_output(["git", "ls-files"], cwd=ROOT, text=True).splitlines()
SUMMARY["source_sha256"] = {p: digest((ROOT / p).read_bytes()) for p in tracked if p.startswith(("contracts/", "test/", "fork/", "scripts/", "docs/")) or p in ("README.md", "foundry.toml")}
for profile in ("default", "fork"):
    env = os.environ.copy()
    env.pop("MAINNET_RPC_URL", None)
    env.update(FOUNDRY_PROFILE=profile, FOUNDRY_OUT=str(SCRATCH / profile / "out"), FOUNDRY_CACHE_PATH=str(SCRATCH / profile / "cache"))
    run("build-" + profile, ["forge", "build", "--offline", "--sizes", "--extra-output", "storageLayout", "--ast"], env)
    run("list-" + profile, ["forge", "test", "--offline", "--list", "--json"], env)
    artifacts = {}
    for p in sorted((SCRATCH / profile / "out").glob("*/*.json")):
        a = json.loads(p.read_text())
        source = a.get("metadata", {}).get("settings", {}).get("compilationTarget", {}) if isinstance(a.get("metadata"), dict) else {}
        if not source:
            m = a.get("rawMetadata")
            source = json.loads(m).get("settings", {}).get("compilationTarget", {}) if m else {}
        if not any(k.startswith("contracts/") and not k.startswith("contracts/mocks/") for k in source):
            continue
        runtime = a.get("deployedBytecode", {}).get("object", "0x").removeprefix("0x")
        init = a.get("bytecode", {}).get("object", "0x").removeprefix("0x")
        artifacts[str(p.relative_to(SCRATCH / profile / "out"))] = {
            "compilationTarget": source, "runtime_bytes": len(runtime) // 2, "creation_bytes": len(init) // 2,
            "runtime_headroom": 24576 - len(runtime) // 2, "runtime_sha256_decoded": digest(bytes.fromhex(runtime)),
            "abi": a.get("abi"), "methodIdentifiers": a.get("methodIdentifiers"), "storageLayout": a.get("storageLayout"),
            "immutableReferences": a.get("deployedBytecode", {}).get("immutableReferences", {}),
        }
    SUMMARY["profiles"][profile] = artifacts
    if profile == "default":
        run("test-default-unset", ["forge", "test", "--offline", "-vv"], env)
        env["MAINNET_RPC_URL"] = "http://127.0.0.1:1"
        run("test-default-unreachable", ["forge", "test", "--offline", "-vv"], env)
(HERE / "baseline.json").write_text(json.dumps(SUMMARY, indent=2) + "\n")
print("SUMMARY", str(HERE / "baseline.json"), flush=True)
