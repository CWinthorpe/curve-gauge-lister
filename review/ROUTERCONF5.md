ROUTERCONF5 — final bounded router conformance close

Verdict: CONFORMS
ROUTER ACCEPTED
Reviewed tip: 60956b62879916081325ef0a66c502d3be85f913
Candidate Git tree: d571c74bf905b73696a3b8776cc6343cc6493aec
Review execution date: 2026-11-26 UTC

CONF-04(f), (g), and the remaining (h)/I01 slice are CLOSED. No residual
remains within this leg. Prior credited cells remain credited. ROUTER
ACCEPTED is certified at the reviewed tip; the blind router-surface fleet
round is released to the orchestrator for scheduling. This releases the
round; it does not claim that the fleet has started or completed.

1. Scope and disposition

Sole scope: review/ROUTERCONF4.md:231–251,269–296,310–323, under the final
routerconf5 brief. No new identity, mutant, product API, settlement exercise,
security-audit dimension or deployment authorization is imposed. The
ROUTERCONF4 hold is superseded by this terminal disposition.

Source abbreviations at the reviewed tip:
  I = test/GaugeControllerAdminIntegration.t.sol
  F = test/fork/ForkGaugeControllerAdmin.t.sol
Receipt paths below are relative to review/routerconf5/.

2. (f) I03/I04 — CLOSED

I:259–269 now reads both mock venues' complete getDeposit triples for each
nonzero scoped gauge at E through E+4*WEEK. This includes every scheduled
maturity, E+WEEK through E+4*WEEK, rather than treating E as a maturity.
The horizon agrees with contracts/CurveGaugeLister.sol:530–543,708–710.
These admission fixtures do not advance the scenario week between listing
and the compared snapshots.

The raw ladder and its digest enter World at I:237–239; the whole World is
compared at I:286–287. I03's revoked snapshots now include retained gaugeC
at I:776,788. Its full ladder is additionally captured before revocation
at I:748–750,757–770 and compared after both negatives at I:798–807. I04's
three negative helpers all carry gaugeOk as the retained ladder member
(I:873–875,879–981). The earlier record/log and rollback assertions remain.

I:281–283 probes depositAt(0) at each frozen mock and requires status false
with zero returned bytes. Both status and bytes enter the compared World
(I:180–188,245–246). This is an honest missing-API observation, not a
fabricated chronological record: MockIncentivePlatform exposes only the
keyed getter and count at contracts/mocks/MockIncentivePlatform.sol:149–162.
I:220–223 also captures gauge_types status and raw data for both candidate
slots regardless of registration, replacing the former absent-member skip.

Independent I03 PASS confirms the executed ladders and missing-getter
branches. I03-trace.stdout:313–356 shows all five keys and both dispatch
misses; :1259–1278 shows the retained member's final complete ladder.
The source comparison, not an additional reviewer run, verifies I04's
helper wiring and preservation of its credited malformed/lying/log cells.

3. (g) F05 — CLOSED

Actual upstream edges: F:1506 pins the adapter venue getters to VOTIUM and
CampaignRemoteManager; :1507–1510 collects adapter->VOTIUM and adapter->CRM
allowances plus both upstream token balances. Adapter custody remains
separately observed at :1494–1495. These are the actual approval/call
destinations in contracts/adapters/VotiumAdapter.sol:160–162 and
contracts/adapters/VoteMarketAdapter.sol:217–221. Fresh
F05-trace.stdout:1442–1453 shows the getter, allowance and balance frames.

Receipts: F:1435–1444 reads full keyed triples at E through E+4*WEEK for the
candidate slots and retained member. F:1462–1474 asserts no committed
chronological entries in these pre-settlement fixtures, probes slots 0–2,
and retains each call status and complete failure bytes, with the actual
Panic(0x32) payload asserted. The bare-catch zero-word collapse is gone.
The keyed and chronological observations feed the digest at :1412–1417.
Fresh :1454–1481 and :3266–3283 show the candidate and retained ladders and
ordered out-of-range failures. No settlement or invented deposit is claimed.

Absent controller state: F:349–350,1337–1361 captures membership status and
raw return/revert bytes, pins the present/absent shapes, and reads the
candidate's scan-known type weight even while unregistered. F:1523–1525
passes those known types; :1663–1666 requires a successful 32-byte raw
type-weight return before decoding it. The value is compared, not skipped
or replaced by the absence sentinel. Fresh :1494–1505 shows absent
candidate membership followed by real get_type_weight(int128) reads;
selector 0x72fdccfa was independently derived with cast sig.

All added observations enter the existing complete pre/post comparison
at F:1243,1279–1280. The genuinely committed first admission, revoke/regrant,
exact NotAdder(L) checks, full payloads and fee-trace/committed-log distinction
remain unchanged. Independent F05 PASS reaches the prescribed fixtures.

4. (h)/I01 — CLOSED

I:478 captures beforeB. I:483 performs the owner-paid admission, and :492
passes the actual post-admission World into _i01OwnerPaidDeltas. That helper
now requires BOTH post.escrow == pre.escrow + FEE and post.escrow == 2*FEE
at :545–546. Thus the collected owner-paid liability is used after the
second admission; a prior aggregate assertion or token-balance check is no
longer its substitute. Previously credited complete records, logs, exact
fee movements and first-payer deltas are preserved. This is source-verified
closure; I01 was not an additional independent execution in this leg.

5. Independent execution and census

An exact local clone used a fresh HOME and fresh XDG data/cache/config,
with only the installed solc seeded. Initial build directories and RPC
cache were absent. The integration ran before default discovery; F05 was
the first fork execution, with fork output/cache and HOME/XDG caches still
empty immediately beforehand (context.json; pre-fork-cold.json).

Forge 1.7.1, commit 4072e48705af9d93e3c0f6e29e93b5e9a40caed8.
Solc 0.8.30 executable SHA-256:
  54f48274e5ec8a58b378f07c226fa1e25801526b6b0d16129f3a14a18efe72cd

Exactly one integration identity and one fork identity were executed:
  test/GaugeControllerAdminIntegration.t.sol:GaugeControllerAdminIntegrationTest:test_PreGrantAndRevokedBothLanesRollback()
  fork/GaugeControllerAdmin.t.sol:GaugeControllerAdminForkTest:test_Fork_UnmaskedPreGrantRevokedRollback()
Each returned native exit 0, exactly one PASS, zero failures and zero skips.

Commands, in the isolated candidate checkout:
  forge test --offline --match-path test/GaugeControllerAdminIntegration.t.sol --match-test '^test_PreGrantAndRevokedBothLanesRollback\(\)$' -vvvv
  MAINNET_RPC_URL=https://eth-mainnet.public.blastapi.io bash scripts/test-fork.sh --match-path fork/GaugeControllerAdmin.t.sol --match-test '^test_Fork_UnmaskedPreGrantRevokedRollback\(\)$' -vvvv

The unchanged fork runner verified chain 1, block 26401019, timestamp
1794512471 and hash
0x55810b079923a14fb97ad548f5024f65530dbc4fb2357a38f41e13b3d27cb6d3
before invoking Forge (F05-trace.stderr:1–3). All governance/admission work
was local simulation; no signing, broadcast or production action occurred.

Fresh forge fmt --check and native --list --json in both profiles exited 0.
Discovery names were bound to compiled method signatures and compared as
full source-file:contract:signature sets, not counts:
  default: 77 baseline + 26 ledger = 103; exact set equality.
  fork:    13 baseline + 12 ledger = 25; exact set equality.
Both also equal ROUTERCONF4's retained discovery. No missing, unexpected or
duplicate identity. Authority: review/routerplan/BASELINE.json and
review/routerfix/receipts/CENSUS-LEDGER.md:11–48. The two selected runs are
not additional census identities. Full 103/103 offline and 25/25 cold+warm
fork passes remain the orchestrator's supplied verification, not a new
full-suite rerun by this reviewer.

6. Preservation and evidence

The entire 50f193c..60956b6 delta contains only I and F. The unit suite is
byte-identical. Every fork test function is token-identical; helper changes
are limited to the F05 snapshot repair and the equivalent status-only
_isRegistered wrapper around the new raw helper. F09/F10 and the other
credited fork cells retain their bodies and relevant assertions.

In I, I01's aggregate checks and the shared snapshot completion are additive;
I04's negatives were moved into called helpers without deleting their prior
assertions. Event/full-record helpers and the I02 validator controls remain.
A token-level comparison found no removed require/assertEq/assertTrue/
assertFalse expression in either changed file; source inspection additionally
checked call wiring and the moved I04 cases. This preservation check is not
misrepresented as another execution of those credited cells.

No contracts/ (including mocks), scripts/, fork/ or foundry.toml delta exists
since 4ec0ac7. All 46 frozen baseline contract/test/fork/script/config hashes
match. The sealed router, ABI manifest and configuration hashes still match
ROUTERCONF4:352–358. The isolated execution tree and original tracked tree
remained unchanged; git diff --check passed. Only this report is authorized
for the publication commit; source, tests, authorities and receipts are not
included in that commit.

Owner-local evidence:
  /home/winny/curve-gauge-lister/review/routerconf5/
Includes exact argv/environment bindings, native traces, discovery/census
sets, source preservation, and executable verification. BINDING.json binds
27 evidence files plus the named authority-input digests. Its SHA-256 is:
  679f93898d4615c388c3f9dc7c336e73b5379e9277e940ba7153df0f25a11fd7

Final disposition: CONFORMS. ROUTER ACCEPTED at
60956b62879916081325ef0a66c502d3be85f913. The report-only descendant carries
this acceptance without changing the reviewed executable inputs. No open
item is carried from these bounded residuals. The blind router-surface fleet
round is released; scheduling remains with the orchestrator. This is not
fleet security convergence or production deployment authorization.
