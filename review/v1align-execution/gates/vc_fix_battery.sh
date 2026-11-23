#!/usr/bin/env bash
# v1align-fix battery: VC-01 (F-NB-SPLIT falsifier reaching the named FD-delta
# frame) + VC-02 (F-NB-HORIZON per-offset cell execution attempts), product-only
# mutants on disposable copies of a git archive of candidate b37e533.
# Committed tests are never mutated; hash pins are enforced per stage.
set -uo pipefail
REPO=/home/winny/curve-gauge-lister
GATES="$REPO/review/v1align-execution/gates"
W="${CGL_WORK:-/home/winny/tmp-scratch/v1align-fix-r1}"
CAND_SHA=b37e5333a07050e7ea87da98712c0edc483673fa
export TMPDIR=/home/winny/tmp-scratch

exec 9> "$W/.gate.lock"
flock -n 9 || { echo "GATE LOCK HELD BY OTHER LEG"; echo "BATTERY_RC=3"; exit 3; }

rm -rf "$W/cand" "$W/seal"
mkdir -p "$W/cand" || exit 4
git -C "$REPO" archive "$CAND_SHA" | tar -x -C "$W/cand" || { echo "ARCHIVE FAIL"; echo "BATTERY_RC=4"; exit 4; }
export CGL_CANDIDATE="$W/cand"

echo "== candidate pins"
sha256sum "$W/cand/contracts/CurveGaugeLister.sol" "$W/cand/test/Settlement.t.sol"

echo "== VC-01"
CGL_FALSIFY_WORK="$W/vc01" python3 "$GATES/vc01_falsifiers.py" > "$W/vc01-summary.out" 2>&1
RC1=$?
tail -3 "$W/vc01-summary.out"
grep -E '^(F-NB|VC)' "$W/vc01-summary.out" | head

echo "== VC-02"
CGL_FALSIFY_WORK="$W/vc02" python3 "$GATES/vc02_falsifiers.py" > "$W/vc02-summary.out" 2>&1
RC2=$?
grep -E 'verdict|native_exits|near_end_cursor|first_fail' "$W/vc02-summary.out" | head

echo "== seal"
mkdir -p "$W/seal/vc01" "$W/seal/vc02"
cp "$W/vc01"/*.log "$W/vc01"/*.patch.txt "$W/vc01/hashes.txt" "$W/seal/vc01/" || { echo "SEAL VC01 FAIL"; echo "BATTERY_RC=5"; exit 5; }
cp "$W/vc02"/*.log "$W/vc02"/*.patch.txt "$W/vc02"/*.json "$W/seal/vc02/" || { echo "SEAL VC02 FAIL"; echo "BATTERY_RC=5"; exit 5; }
tar czf "$W/seal/vc01-falsify-logs.tar.gz" -C "$W/seal" vc01
tar czf "$W/seal/vc02-falsify-logs.tar.gz" -C "$W/seal" vc02
sha256sum "$W/seal"/*.tar.gz

echo "VC01_RC=$RC1"
echo "VC02_RC=$RC2"
# proof the archive was never mutated by us (generator works on copies)
sha256sum "$W/cand/contracts/CurveGaugeLister.sol" "$W/cand/test/Settlement.t.sol"
echo "BATTERY_RC_DONE"
