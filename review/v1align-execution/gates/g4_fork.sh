#!/usr/bin/env bash
# G4: full 13-identity fork suite through scripts/test-fork.sh at the SAME pin,
# in a cold isolated HOME (only installed solc copied, no .foundry/cache/rpc),
# then warm, then the same wrapper with an unreachable RPC (must fail preflight
# before tests even with cache warm), preserving the failed-endpoint attempt.
set -uo pipefail
CAND="${CGL_CANDIDATE:?}"
ISO="${CGL_ISOHOME:?}"
WORK="$CAND/gates-out"
mkdir -p "$WORK"
ARCHIVE_RPC="https://eth-mainnet.public.blastapi.io"

cd "$CAND"

echo "== attempt 0: historical publicnode endpoint (expected archive failure; preserved)"
HOME="$ISO" MAINNET_RPC_URL=https://ethereum-rpc.publicnode.com ./scripts/test-fork.sh --match-path 'fork/TrustedFactory.t.sol' > "$WORK/g4-publicnode-attempt.txt" 2>&1
echo "exit=$?" | tee -a "$WORK/g4-publicnode-attempt.txt"

echo "== re-seed pristine isolated HOME for the official cold run (solc only)"
rm -rf "$ISO"
mkdir -p "$ISO/.local/share/svm"
cp -a "${SOLC_SRC:-/home/winny/.local/share/svm/0.8.30}" "$ISO/.local/share/svm/"
ls "$ISO/.foundry/cache" >/dev/null 2>&1 && { echo "ISOHOME HAS FOUNDRY CACHE"; exit 2; }
ls "$ISO/.cache" >/dev/null 2>&1 && { echo "ISOHOME HAS XDG CACHE"; exit 2; }
ls "$ISO/.foundry" >/dev/null 2>&1 && { echo "ISOHOME HAS FOUNDRY HOME"; exit 2; }
HOME="$ISO" MAINNET_RPC_URL="$ARCHIVE_RPC" ./scripts/test-fork.sh > "$WORK/g4-cold.txt" 2>&1
RC_COLD=$?
echo "cold exit=$RC_COLD" | tee -a "$WORK/g4-cold.txt"
[ $RC_COLD -eq 0 ] || { tail -40 "$WORK/g4-cold.txt"; exit 1; }

echo "== warm run (same HOME, caches now present)"
ls "$ISO/.foundry/cache" >/dev/null 2>&1 && echo "rpc cache present (warm confirmed)"
HOME="$ISO" MAINNET_RPC_URL="$ARCHIVE_RPC" ./scripts/test-fork.sh > "$WORK/g4-warm.txt" 2>&1
RC_WARM=$?
echo "warm exit=$RC_WARM" | tee -a "$WORK/g4-warm.txt"
[ $RC_WARM -eq 0 ] || { tail -40 "$WORK/g4-warm.txt"; exit 1; }

echo "== unreachable RPC repeat (must fail preflight before tests)"
HOME="$ISO" MAINNET_RPC_URL=http://127.0.0.1:1 ./scripts/test-fork.sh > "$WORK/g4-unreachable.txt" 2>&1
RC_UN=$?
echo "unreachable exit=$RC_UN" | tee -a "$WORK/g4-unreachable.txt"
if [ $RC_UN -eq 0 ]; then echo "G4 FAIL: unreachable run exited 0"; exit 1; fi
grep -q "BLOCKED: RPC" "$WORK/g4-unreachable.txt" || { echo "G4 FAIL: no BLOCKED preflight label"; exit 1; }
grep -q "refusing to run fork tests" "$WORK/g4-unreachable.txt" || { echo "G4 FAIL: not preflight-fail-closed"; exit 1; }
grep -Eq "Ran [0-9]+ tests? for" "$WORK/g4-unreachable.txt" && { echo "G4 FAIL: tests ran under unreachable RPC"; exit 1; }
grep -q "\[PASS\]" "$WORK/g4-unreachable.txt" && { echo "G4 FAIL: PASS lines under unreachable RPC"; exit 1; }

for f in cold warm; do
  grep -q "chainId=0x1 number=0x192d8fb hash=0x55810b079923a14fb97ad548f5024f65530dbc4fb2357a38f41e13b3d27cb6d3 timestamp=0x6af61657" "$WORK/g4-$f.txt" || { echo "G4 FAIL: pin verification line missing in $f"; exit 1; }
  grep -q "VERIFIED — proceeding" "$WORK/g4-$f.txt" || { echo "G4 FAIL: no VERIFIED line in $f"; exit 1; }
  grep -q "13 tests passed, 0 failed, 0 skipped" "$WORK/g4-$f.txt" || { echo "G4 FAIL: 13-identity census in $f"; exit 1; }
done
echo "G4 OK"
