#!/usr/bin/env python3
"""r3docs: extract the native PASS identity set from scripts/test-fork.sh
output and compare to the BINDING fork census exactly (paths, contracts,
signatures; 13 identities, no duplicates, no skips/fails)."""
import json
import re
import sys

log = open(sys.argv[1], encoding="utf-8", errors="replace").read()
log = re.sub(r"\x1b\[[0-9;]*m", "", log)
ids = []
cur = None
for line in log.splitlines():
    m = re.match(r"Ran \d+ tests? for (\S+):(\S+)", line.strip())
    if m:
        cur = (m.group(1), m.group(2))
    m = re.match(r"\[PASS\] (\S+)", line.strip())
    if m and cur:
        ids.append(f"{cur[0]}:{cur[1]}:{m.group(1)}")
fails = re.findall(r"\[FAIL[^\]]*\] (\S+)", log)
skips = re.findall(r"\[SKIP\] (\S+)", log)
binding = json.load(open("/home/winny/curve-gauge-lister/review/r3gate/BINDING.json"))
census = set(binding["census"]["fork"])
print("executed PASS identities:", len(ids), "unique:", len(set(ids)))
print("fails:", fails, "skips:", skips)
print("executed == census:", set(ids) == census)
if set(ids) != census:
    print("xor:", set(ids) ^ census)
print("FORK CENSUS", "PASS" if set(ids) == census and not fails and not skips else "FAIL")
sys.exit(0 if set(ids) == census and not fails and not skips else 1)
