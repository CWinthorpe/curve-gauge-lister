#!/usr/bin/env bash
# v1align-fix FINAL gates on the unchanged candidate tree (receipts-only delta
# vs b37e533). Mirrors the V1ALIGN-CONF gate invocations. Writes a compact
# receipt + a raw-log bundle. Never touches product/test sources.
set -uo pipefail
REPO=/home/winny/curve-gauge-lister
GATES="$REPO/review/v1align-execution/gates"
W="${CGL_WORK:-/home/winny/tmp-scratch/v1align-fix-r1}/final-gates"
CAND_SHA=b37e5333a07050e7ea87da98712c0edc483673fa
export TMPDIR=/home/winny/tmp-scratch
ARCHIVE_RPC="https://eth-mainnet.public.blastapi.io"
mkdir -p "$W/raw"
REC="$W/v1align-fix-final-gates.txt"
exec 9> "$W/.gate.lock"
flock -n 9 || { echo "GATE LOCK HELD BY OTHER LEG" > "$REC"; echo "GATES_RC=3"; exit 3; }

{
echo "# v1align-fix final gates — generated $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "repo=$REPO HEAD=$(git -C "$REPO" rev-parse HEAD)"
echo "candidate=$CAND_SHA"
} > "$REC"

run() { # label, cmd...  -> rc line into receipt, full output to raw/<label>.log
  local label="$1"; shift
  { echo; echo "== $label"; echo "\$ $*"; } >> "$REC"
  ( eval "$@" ) > "$W/raw/$label.log" 2>&1
  local rc=$?
  echo "RC=$rc" >> "$REC"
  echo "sha256(raw)=$(sha256sum "$W/raw/$label.log" | cut -d' ' -f1)" >> "$REC"
  return $rc
}

cd "$REPO"
FAIL=0

run fmt 'forge fmt --check'
rc=$?; [ $rc -eq 0 ] || { echo "FMT FAILED" >> "$REC"; FAIL=1; }
grep -E "^Diff in|error" "$W/raw/fmt.log" | head -5 >> "$REC" || true

run build-default 'forge build --offline --sizes --extra-output storageLayout --ast'
rc=$?; [ $rc -eq 0 ] || { echo "BUILD DEFAULT FAILED" >> "$REC"; FAIL=1; }
grep -E "Compiler run|Error" "$W/raw/build-default.log" | head -3 >> "$REC"

run build-fork 'env FOUNDRY_PROFILE=fork forge build --offline --sizes --extra-output storageLayout --ast'
rc=$?; [ $rc -eq 0 ] || { echo "BUILD FORK FAILED" >> "$REC"; FAIL=1; }
grep -E "Compiler run|Error" "$W/raw/build-fork.log" | head -3 >> "$REC"

run list-default 'env -u MAINNET_RPC_URL forge test --offline --list --json'
NDEF=$(python3 -c "
import json,re
t=open('$W/raw/list-default.log').read()
doc=json.loads(t[t.index('{'):])
print(sum(len(v) for c in doc.values() for v in c.values()))")
run list-fork 'env FOUNDRY_PROFILE=fork env -u MAINNET_RPC_URL forge test --offline --list --json'
NFORK=$(python3 -c "
import json
t=open('$W/raw/list-fork.log').read()
doc=json.loads(t[t.index('{'):])
print(sum(len(v) for c in doc.values() for v in c.values()))")
{ echo; echo "== inventory census default=$NDEF fork=$NFORK (expect 77 / 13)"; } >> "$REC"
[ "$NDEF" = "77" ] && [ "$NFORK" = "13" ] || { echo "INVENTORY MISMATCH" >> "$REC"; FAIL=1; }

run suite-offline 'env -u MAINNET_RPC_URL forge test --offline -vvv'
grep -E "Test result|Suite result: ok" "$W/raw/suite-offline.log" | tail -10 >> "$REC"
grep -q "77 tests passed, 0 failed, 0 skipped" "$W/raw/suite-offline.log" \
  || { echo "OFFLINE 77-EXACT MISMATCH" >> "$REC"; FAIL=1; }
grep -Eq "\[FAIL" "$W/raw/suite-offline.log" && { echo "OFFLINE FAIL LINES PRESENT" >> "$REC"; FAIL=1; }

run fork13 'env MAINNET_RPC_URL='"$ARCHIVE_RPC"' ./scripts/test-fork.sh'
grep -E "fork preflight|Test result" "$W/raw/fork13.log" | tail -8 >> "$REC"
grep -q "13 tests passed, 0 failed, 0 skipped" "$W/raw/fork13.log" \
  || { echo "FORK 13-EXACT MISMATCH" >> "$REC"; FAIL=1; }

{
echo; echo "== product/test purity vs candidate"
echo "\$ git diff --name-only $CAND_SHA HEAD -- contracts test fork scripts foundry.toml remappings.txt"
D1=$(git -C "$REPO" diff --name-only "$CAND_SHA" HEAD -- contracts test fork scripts foundry.toml remappings.txt)
echo "committed-delta: [${D1:-EMPTY}]"
[ -z "$D1" ] || FAIL=1
PINS=$(git -C "$REPO" show "$CAND_SHA:contracts/CurveGaugeLister.sol" | sha256sum; git -C "$REPO" show "$CAND_SHA:test/Settlement.t.sol" | sha256sum)
echo "candidate pins:"; echo "$PINS"
echo "worktree pins:"
sha256sum contracts/CurveGaugeLister.sol test/Settlement.t.sol
} >> "$REC"
[ "$(sha256sum contracts/CurveGaugeLister.sol | cut -d' ' -f1)" = "$(echo "$PINS" | head -1 | cut -d' ' -f1)" ] || { echo "PRODUCT HASH DRIFT" >> "$REC"; FAIL=1; }
[ "$(sha256sum test/Settlement.t.sol | cut -d' ' -f1)" = "$(echo "$PINS" | tail -1 | cut -d' ' -f1)" ] || { echo "TEST HASH DRIFT" >> "$REC"; FAIL=1; }

{
echo; echo "== new receipts this leg (sha256)"
sha256sum "$GATES"/vc01_falsifiers.py "$GATES"/vc02_falsifiers.py "$GATES"/vc_fix_battery.sh \
  "$GATES"/vc01-falsify-logs.tar.gz "$GATES"/vc02-falsify-logs.tar.gz \
  "$GATES"/vc01-summary.out "$GATES"/vc02-summary.out \
  "$GATES"/AMENDMENT-REQUEST-VC02.md
[ -n "${EXTRA_NOTE:-}" ] && echo "$EXTRA_NOTE" >> "$REC"
} >> "$REC"

tar czf "$W/v1align-fix-final-rawlogs.tar.gz" -C "$W" raw
echo; echo "raw bundle sha256: $(sha256sum "$W/v1align-fix-final-rawlogs.tar.gz" | cut -d' ' -f1)" >> "$REC"
echo "GATES_RC=$FAIL" >> "$REC"
echo "GATES_RC=$FAIL"
cp -f "$REC" "$GATES/v1align-fix-final-gates.txt"
cp -f "$W/v1align-fix-final-rawlogs.tar.gz" "$GATES/v1align-fix-final-rawlogs.tar.gz"
echo "GATES_DONE"
exit $FAIL
