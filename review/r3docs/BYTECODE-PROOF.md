# r3docs — bytecode-hash proof (before/after forge build)


Baseline and candidate were built in ISOLATED exact git worktrees of the
same repository, each with fresh `out/`, `out-fork/`, `cache/`, `cache-fork/`
(no shared or stale build state):

- baseline: `d88d633c64fde7b3f37e29d846f744747186a688` (product candidate
  bound by `review/r3gate/BINDING.json`)
- candidate: `a9de6ffc99343801575b72a2be78ea83bd73508c` (r3docs P2+P0; the
  final product/docs tree — P1 `340db1d40882f4a3a8432e9bc0e5505023faf99d`
  is its only product-side ancestor commit in this leg)

## Method (retained verbatim in artifacts/hash_artifacts.py)

For every artifact JSON under each profile's out dir, the `0x`-stripped
`bytecode.object` (creation) and `deployedBytecode.object` (runtime) hex are
hashed (sha256 over the lowercase hex string) in two ways:

1. FULL hash — the whole object as emitted by solc.
2. EXECUTABLE hash — the validated Solidity metadata trailer is separated
   first: the last two bytes are a big-endian CBOR length `L`; the trailer
   is the preceding `L` bytes and MUST parse as a 2-item CBOR map with keys
   exactly `{ipfs, solc}` (minimal CBOR walker; interfaces/libraries without
   code carry no trailer); the executable prefix is everything before
   `L + 2` trailing bytes. Raw trailer bytes are retained in
   `artifacts/hashes-*.json` (`metadata_trailer`).

This is the comparison method named by `plans/R3GATE-WORK-ORDER.md` G2
("compare executable runtime bytecode separately from a validated Solidity
metadata trailer, with the parsing method and raw bytes retained") and its
rule "comment metadata is not expected to be byte-identical".

## Three product deployables — hash comparison, both profiles

### Profile `default` (forge build --offline, fresh outputs)

| contract : side | executable base | executable cand | equal | full base | full cand | trailer drift |
| --- | --- | --- | --- | --- | --- | --- |
| CurveGaugeLister:creation | `3976b982f41d7ebffa7294585b52fcaf75784eab35a70ce46ed504afe9970055` | `3976b982f41d7ebffa7294585b52fcaf75784eab35a70ce46ed504afe9970055` | YES | `e742792a1b198f79…` | `e24811152c019997…` | ipfs-CID only; solc entry `6c634300081e` unchanged |
| CurveGaugeLister:runtime | `581bc2173a6e908103756677f4a143e39f92be216d2b3aa557f5fae7f8c4cb4e` | `581bc2173a6e908103756677f4a143e39f92be216d2b3aa557f5fae7f8c4cb4e` | YES | `41f617655f633183…` | `a754e151af78c615…` | ipfs-CID only; solc entry `6c634300081e` unchanged |
| VoteMarketAdapter:creation | `c02e7a2a0072a74aa72867d727ff598ae8612631754cbd0ff2c69c1e793477f9` | `c02e7a2a0072a74aa72867d727ff598ae8612631754cbd0ff2c69c1e793477f9` | YES | `a6b53fd767f9b642…` | `b6f715092895b926…` | ipfs-CID only; solc entry `6c634300081e` unchanged |
| VoteMarketAdapter:runtime | `1d0e2f0ce46323dad91b8e2fcc8c2553e3ba946203ed86e95ed9a9e341fda931` | `1d0e2f0ce46323dad91b8e2fcc8c2553e3ba946203ed86e95ed9a9e341fda931` | YES | `05184a9a0f6e90c6…` | `60a7481e625c1f1a…` | ipfs-CID only; solc entry `6c634300081e` unchanged |
| VotiumAdapter:creation | `4823e0874f19f0f518ad5cf96853ab4b082c7a7c00a06dbe565f900c094ff3c5` | `4823e0874f19f0f518ad5cf96853ab4b082c7a7c00a06dbe565f900c094ff3c5` | YES | `487a26844706afe0…` | `a8fce32a1644fde6…` | ipfs-CID only; solc entry `6c634300081e` unchanged |
| VotiumAdapter:runtime | `a10ee31cdeb4e7dcf825f3f9cab19cf9f1b1e4a5a19115b3473916814dbaa7a0` | `a10ee31cdeb4e7dcf825f3f9cab19cf9f1b1e4a5a19115b3473916814dbaa7a0` | YES | `8dc5c72988b08ce0…` | `15b4911e70528f47…` | ipfs-CID only; solc entry `6c634300081e` unchanged |

### Profile `fork` (forge build --offline, fresh outputs)

| contract : side | executable base | executable cand | equal | full base | full cand | trailer drift |
| --- | --- | --- | --- | --- | --- | --- |
| CurveGaugeLister:creation | `d316f8a3cef30cb43cf555c17e59f39763d0929667412968953e759b6b1ed6f5` | `d316f8a3cef30cb43cf555c17e59f39763d0929667412968953e759b6b1ed6f5` | YES | `e3560e0efabaad7c…` | `f7cf03c728e4c045…` | ipfs-CID only; solc entry `6c634300081e` unchanged |
| CurveGaugeLister:runtime | `371c5cb74890f8ad0f44b215a4bcbb5f23884f79ff3ae0592c8955b7511437bb` | `371c5cb74890f8ad0f44b215a4bcbb5f23884f79ff3ae0592c8955b7511437bb` | YES | `67a31f1c7e187686…` | `97b865ed4eb72da4…` | ipfs-CID only; solc entry `6c634300081e` unchanged |
| VoteMarketAdapter:creation | `c38a023a6fbdf308f5b897ed1a5c4010d1e2bc25093988780fac4215e9b9a3fe` | `c38a023a6fbdf308f5b897ed1a5c4010d1e2bc25093988780fac4215e9b9a3fe` | YES | `1a63c6fe2a975bf5…` | `34e5ce4401086670…` | ipfs-CID only; solc entry `6c634300081e` unchanged |
| VoteMarketAdapter:runtime | `9de8ca67ad3b8d568d46fba9e5c9662428ec80d9626d78503990e79fbafc1ad0` | `9de8ca67ad3b8d568d46fba9e5c9662428ec80d9626d78503990e79fbafc1ad0` | YES | `4b5fbf66d655cd88…` | `68b8de9c40443ee9…` | ipfs-CID only; solc entry `6c634300081e` unchanged |
| VotiumAdapter:creation | `f472fd0fa98c28ca61e21027a31c45f94fb1b749c59d27abd0204e778a55c406` | `f472fd0fa98c28ca61e21027a31c45f94fb1b749c59d27abd0204e778a55c406` | YES | `9322797279718a84…` | `ab0c9204cffb0b6c…` | ipfs-CID only; solc entry `6c634300081e` unchanged |
| VotiumAdapter:runtime | `81307cf268a838af6d557968a8c8193cf3b81c302af97f2e5650e99d18858c08` | `81307cf268a838af6d557968a8c8193cf3b81c302af97f2e5650e99d18858c08` | YES | `f5c86a4f944e958a…` | `da8a62cece5145bd…` | ipfs-CID only; solc entry `6c634300081e` unchanged |


**Verdict:** every executable (validated-metadata-stripped) creation and
runtime hash of all three product deployables is IDENTICAL to the
`d88d633` baseline under both profiles — the byte-proof requirement.

FULL-object hashes differ ONLY inside the validated metadata trailer: a
comment edit changes each source file's keccak, which is embedded in the
per-compilation Solidity metadata (the `ipfs` CID), which solc appends to
both creation and deployed code. The `solc` trailer entry (`43 00081e` =
0.8.30) is unchanged; the trailer structure still validates; no byte outside
the trailer moved. Per the work order this drift MUST be disclosed and is
never claimed away: no claim of byte-identical compiler metadata is made
from this comment-only diff. (The leg-brief shorthand "runtime AND creation
bytecode identical hashes" is satisfied on the executable bytes; the naive
whole-object comparison is unsatisfiable for ANY comment change, and the
sole-authority work order prescribes the executable-vs-trailer split above.)

Auxiliary same-session in-repo captures (P1 stage, before the isolated
rebuild) are retained in artifacts/ as `hashes-default-baseline.json`,
`hashes-fork-baseline.json`, `hash-default-p1run.json`,
`hash-fork-p1run.json`; they agree with the worktree captures.

## Test-contract artifacts (disclosure, per G2)

`new CurveGaugeLister(...)`, `new VoteMarketAdapter(...)` and
`new VotiumAdapter(...)` inline the products' FULL creation bytes — metadata
trailer included — into the CALLER's code, so test artifacts embed product
metadata. Their outer trailer stripping is therefore not a test-equivalence
proof; per the work order, test executable identity is instead frozen at
G0-level and is evidenced in this package by:

- all 43 non-allowlisted product/test files byte-equal (sha256) to the
  `BINDING.json` product baseline (`compare_g0_g2.py` section (a)); and
- the six admitted Solidity files passing a string-aware comment-strip
  executable-TOKEN comparison against `git show d88d633:<file>` — zero
  executable/declaration/import/literal token delta
  (`token_cmp.py`; the lexer keeps string literals whole and strips only
  out-of-string `//` and `/* */` comments; adversarial probe in
  artifacts/lexer_selftest.py output).

Contracts whose executable region moved (embedded product metadata only):
default profile — AdapterConfigR2Test, AdaptersTest, CurveGaugeListerTest,
SettlementTest, TrustedFactoryTest; fork profile — AdmissionForkTest,
KillForkTest, TrustedFactoryForkTest, VoteMarketForkTest, VotiumForkTest.
Every one of these source files is byte-identical to its BINDING hash.

## Size retention (both profiles, candidate == baseline table)

- CurveGaugeLister runtime 15,031 B; VoteMarketAdapter 7,136 B;
  VotiumAdapter 4,949 B — each ≤ 24,576 decoded bytes. Initcode sizes
  17,494 / 7,727 / 5,468; constructor/initcode table retained in
  artifacts/build-{base,cand}-{default,fork}.txt (identical columns).
