# r3docs — gate outputs (native exits retained in artifacts/)

Toolchain: forge Version 1.7.1 (commit 4072e48705af9d93e3c0f6e29e93b5e9a40caed8,
2026-05-08). Compiler settings untouched: Solidity 0.8.30, optimizer 200
runs, no viaIR, default profile EVM Paris, fork profile Cancun chain 1 —
foundry.toml is byte-identical to its BINDING.json baseline hash
(f8ea5f0f3abfcb9c9987ef508cf5565cd840a5492f21960d7654c3ddbc79fac5).
No toolchain/dependency/configuration edit was made anywhere in this leg.

Candidate custody: all product-side commands ran inside isolated exact
detached worktrees — baseline at `d88d633c64fde7b3f37e29d846f744747186a688`,
candidate at `a9de6ffc99343801575b72a2be78ea83bd73508c` — each with fresh
`out/`, `out-fork/`, `cache/`, `cache-fork/` from this leg only.

## G-fmt — `forge fmt --check`

- pre-edit tree at 62c8326 (product == d88d633): exit 0
- after P1 commit 340db1d: exit 0
- after P2 commit a9de6ff (repo): exit 0
- inside isolated candidate worktree wt-cand: exit 0 (artifacts/ has the
  invocations' captured absence of output; exit codes verified live)

## G-build — `forge build --offline --sizes`, both profiles

- wt-base default: exit 0 (artifacts/build-base-default.txt)
- wt-base fork:    exit 0 (artifacts/build-base-fork.txt)
- wt-cand default: exit 0 (artifacts/build-cand-default.txt)
- wt-cand fork:    exit 0 (artifacts/build-cand-fork.txt)
- `git diff --check` over the leg range: exit 0
- Warnings retained as emitted (native output kept): divide-before-multiply,
  block-timestamp and erc20-unchecked-transfer lint advisories, all on
  pre-existing lines identical to baseline; zero compile errors; no waiver.

## G-offline — default suite, two runs, exact 77-identity equality

- Run 1 (RPC-unset): `env -u MAINNET_RPC_URL forge test --offline --json`
  exit 0 — 77 executed identities, all status Success, zero failures/skips,
  zero duplicates (artifacts/test-cand-default.json).
- Run 2 (unreachable RPC control): `MAINNET_RPC_URL=http://127.0.0.1:1
  forge test --offline --json` exit 0 — same 77 identities, all Success
  (artifacts/test-cand-unreachable.json). Two executions of the SAME
  identity set; the census is not increased.
- Discovered set `forge test --offline --list` (artifacts/list-cand-default.txt):
  77 identities, no duplicates.
- Executed (both runs) == discovered == BINDING.json `census.default`
  (77, exact path:contract:signature set equality, including the legacy
  `test/bountyfix02/AdapterConfig.t.sol:AdapterConfigR2Test` identities).
  Checker: artifacts/census_check.py → "CENSUS GATES PASS" (native stdout
  retained in compare-final.txt / this receipt).

## G-fork — pinned mainnet fork, ONCE, via scripts/test-fork.sh

- Command: `scripts/test-fork.sh` (no filters) in wt-cand with the
  script-default endpoint `https://ethereum-rpc.publicnode.com`
  (MAINNET_RPC_URL unset; no credential printed).
- Fail-closed preflight (native lines, artifacts/fork-run.log): chainId=0x1,
  number=0x192d8fb, hash=0x55810b079923a14fb97ad548f5024f65530dbc4fb2357a38f41e13b3d27cb6d3,
  timestamp=0x6af61657 → "VERIFIED — proceeding". Pin unchanged:
  block 26401019 / hash 0x5581…cb6d3 / ts 1794512471 / chain 1. No repin,
  no mocks/etch/store, no skipped live positives, no changed expectations.
- Native exit: FORK_RC=0. Result: 13 passed, 0 failed, 0 skipped across the
  5 fork suites.
- Executed PASS identity set == BINDING.json `census.fork` (13, exact)
  (artifacts/fork_identity_check.py → "FORK CENSUS PASS").
- Cache mode, recorded honestly: forge build ran fresh in this worktree
  immediately before ("No files changed, compilation skipped" at test
  start refers to that fresh same-session build). This bounded
  comment-only leg makes NO new cold/warm qualification; historical
  cold/warm/preflight evidence from simplify2/r3gate stays historical
  (see AUTH index O-16 and review/r3gate documents).

## G-diff — hunk-by-hunk review

24 -U0 hunks across the 10 allowlisted files; every hunk cited to its row
in ROW-HUNK-MAP.md; the string-aware comment-strip lexer (artifacts/
token_cmp.py, adversarial probe artifacts/lexer_selftest.py) proves ZERO
executable/declaration/import/test-literal token delta on all six admitted
Solidity files; the other 43 BINDING-listed files are byte-identical to
their bound baseline hashes (artifacts/compare-final.txt section (a)).

## Bytecode proof

See BYTECODE-PROOF.md: executable (validated-metadata-stripped) creation
AND runtime hashes of the three product deployables are identical to the
d88d633 baseline under both profiles; full-object drift is confined to the
validated Solidity metadata trailer (source-keccak change), disclosed and
retained with raw trailer bytes — never claimed byte-identical.

## Sealed-law spot checks (work order §4)

No executable token moved ⇒ FEE=10,000e18, QUARTER=2,500e18, four
Thursday tranches, frozen endpoints/split, zero-share no-call, current
`is_killed()` sole kill oracle, read cadence, atomicity, exact all-FD
remainder, rollback, admission precedence, locks, token guards/approval
sequence, receipt semantics and ABI/layout are preserved by construction
(G0 identity above). Docs kept every named amount, pin and restriction;
no new status, quote, recovery right or kill policy was introduced.
"Modulo deployment" language unchanged; ACTIVATION-OPEN statuses restated,
not closed.
