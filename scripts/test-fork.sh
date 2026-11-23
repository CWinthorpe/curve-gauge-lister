#!/usr/bin/env bash
# Strict, fail-closed mainnet-fork acceptance runner (plans/FORK-PLAN.md §2).
#
# Resolves the RPC endpoint exactly like the fixture (MAINNET_RPC_URL override
# for the ENDPOINT ONLY — never a block override), reads the pinned block
# header and chain id over JSON-RPC, compares hash/number/timestamp against
# the FORK-PLAN constants, and exits nonzero on ANY mismatch or RPC error
# before invoking the fork-profile Forge test. Bounded retries target the
# same pinned request only; there is no moving-head retry and no endpoint
# fallback. Credential-bearing URLs are never printed.
set -euo pipefail
cd "$(dirname "$0")/.."

RPC="${MAINNET_RPC_URL:-https://ethereum-rpc.publicnode.com}"
FORK_BLOCK=26401019
FORK_BLOCK_HEX=0x192d8fb
FORK_HASH=0x55810b079923a14fb97ad548f5024f65530dbc4fb2357a38f41e13b3d27cb6d3
FORK_TS_HEX=0x6af61657
FORK_TS=1794512471
EXPECTED_CHAIN_HEX=0x1

# Credential redaction (plans/FORK-PLAN.md §2: never print credential-bearing
# URLs). sanitize_url keeps ONLY scheme://host[:port] — userinfo, path, query
# and fragment are dropped. redact strips userinfo from any embedded URL in
# free-text diagnostics so failure output cannot reintroduce it.
sanitize_url() { # $1: url -> scheme://host[:port]
    printf '%s' "$1" | sed -E -e 's#^([a-zA-Z][a-zA-Z0-9+.-]+)://([^/?#@]*@)?([^/?#]*).*$#\1://\3#'
}
redact() { # $1: arbitrary text -> same text without URL userinfo
    printf '%s' "$1" | sed -E -e 's#([a-zA-Z][a-zA-Z0-9+.-]+://)[^/@]+@#\1#g'
}

# Print only scheme://host[:port] (no userinfo/path/query/fragment).
RPC_SAFE="$(sanitize_url "$RPC")"
echo "fork preflight: verifying pinned header at block ${FORK_BLOCK} via ${RPC_SAFE}" >&2

rpc_call() { # $1: method, $2: params json array
    local body resp
    body=$(printf '{"jsonrpc":"2.0","id":1,"method":"%s","params":%s}' "$1" "$2")
    for attempt in 1 2 3 4 5; do
        if resp=$(curl -sS --max-time 45 -H 'content-type: application/json' \
            -H 'user-agent: curve-gauge-lister-fork-preflight/1.0' \
            --data "$body" "$RPC" 2>&1); then
            if [[ "${resp}" != *'"error"'* ]]; then
                printf '%s' "$resp"
                return 0
            fi
        fi
        sleep $((attempt * 2))
    done
    echo "fork preflight: RPC failure after bounded retries (same pinned request only)" >&2
    redact "${resp:0:400}" >&2
    echo >&2
    return 1
}

extract() { # $1: json, $2: key
    printf '%s' "$1" | python3 -c "
import sys,json
try:
    d=json.load(sys.stdin)
    r=d.get('result')
    v=(r if isinstance(r,(str,int)) else (r or {}).get('$2'))
    print(v if v is not None else 'MISSING')
except Exception:
    print('MISSING')
"
}

# Failures flow through as MISSING into the strict comparisons below; the
# run then exits nonzero with the BLOCKED: RPC label (fail-closed either way).
#
# CX-FORK-CLOCK: this preflight is the SELECTED-FORK-IDENTITY check — it
# compares the RPC-returned pinned block header (hash/number/timestamp) and
# chain id, fail-closed, BEFORE any test runs. It is separate from, and
# neither substitutes for, the fixture-side checks in
# test/fork/ForkFixture.sol `_freshFork`: (1) the in-EVM chain-id/block-
# number assertions confirm what the node served this test builds on, and
# (2) the optional timestamp warp is only a SCENARIO CLOCK RESTORATION after
# earlier subcases warped the env clock. Header verification here is not a
# clock restoration; clock restoration there is not header verification.
CHAIN_HEX=$(extract "$(rpc_call eth_chainId '[]' || true)" "")
BLOCK=$(rpc_call eth_getBlockByNumber "[\"${FORK_BLOCK_HEX}\",false]" || true)
BLOCK_HASH=$(extract "$BLOCK" hash)
BLOCK_NUMBER=$(extract "$BLOCK" number)
BLOCK_TS=$(extract "$BLOCK" timestamp)

echo "fork preflight: chainId=${CHAIN_HEX} number=${BLOCK_NUMBER} hash=${BLOCK_HASH} timestamp=${BLOCK_TS}" >&2

fail=0
[ "${CHAIN_HEX}" = "${EXPECTED_CHAIN_HEX}" ] || { echo "MISMATCH chainId (expected ${EXPECTED_CHAIN_HEX})" >&2; fail=1; }
[ "${BLOCK_NUMBER}" = "${FORK_BLOCK_HEX}" ] || { echo "MISMATCH number (expected ${FORK_BLOCK_HEX})" >&2; fail=1; }
[ "${BLOCK_HASH}" = "${FORK_HASH}" ] || { echo "MISMATCH hash (expected ${FORK_HASH})" >&2; fail=1; }
[ "${BLOCK_TS}" = "${FORK_TS_HEX}" ] || { echo "MISMATCH timestamp (expected ${FORK_TS_HEX})" >&2; fail=1; }
if [ "$fail" -ne 0 ]; then
    echo "fork preflight: BLOCKED: RPC — pinned header verification failed; refusing to run fork tests" >&2
    exit 1
fi
echo "fork preflight: pinned block ${FORK_BLOCK} hash ${FORK_HASH} VERIFIED — proceeding" >&2

export MAINNET_RPC_URL="$RPC"
exec env FOUNDRY_PROFILE=fork forge test --offline -vvv "$@"
