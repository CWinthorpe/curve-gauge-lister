#!/usr/bin/env python3
"""Exercise the unchanged baseline fork gate with isolated cold/warm HOME."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
baseline = json.loads((HERE / "baseline.json").read_text())
scratch = Path(baseline["scratch"])
home = Path(tempfile.mkdtemp(prefix="v1align-fork-home-", dir=os.environ["TMPDIR"]))
solc = Path.home() / ".local" / "share" / "svm" / "0.8.30"
assert solc.is_dir(), "Installed solc directory absent; do not install or fake fork acceptance"
shutil.copytree(solc, home / ".local" / "share" / "svm" / "0.8.30")
assert not (home / ".foundry" / "cache" / "rpc").exists()
env = os.environ.copy()
env.update(HOME=str(home), XDG_DATA_HOME=str(home / ".local" / "share"), XDG_CACHE_HOME=str(home / ".cache"), MAINNET_RPC_URL="https://eth-mainnet.public.blastapi.io", FOUNDRY_OUT=str(scratch / "fork" / "out"), FOUNDRY_CACHE_PATH=str(scratch / "fork" / "cache"))
summary = {"candidate": baseline["candidate"], "home": str(home), "initial_rpc_cache_absent": True, "runs": []}
for name, endpoint in (("fork-cold", "https://eth-mainnet.public.blastapi.io"), ("fork-warm", "https://eth-mainnet.public.blastapi.io"), ("fork-unreachable", "http://127.0.0.1:1")):
    env["MAINNET_RPC_URL"] = endpoint
    started = time.time()
    argv = ["bash", "scripts/test-fork.sh"]
    with (HERE / (name + ".txt")).open("w") as stream:
        try:
            result = subprocess.run(argv, cwd=ROOT, env=env, stdout=stream, stderr=subprocess.STDOUT, timeout=600)
            rc = result.returncode
        except subprocess.TimeoutExpired:
            rc = 124
    summary["runs"].append({"name": name, "argv": argv, "cwd": str(ROOT), "endpoint": endpoint, "exit": rc, "seconds": round(time.time() - started, 3)})
    (HERE / "fork-status.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(name, rc, flush=True)
    if rc == 124:
        break
