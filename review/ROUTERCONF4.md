ROUTERCONF4 — bounded CONF-04 close-out

Verdict: NONCONFORMS / HOLD
Candidate: e2805c5ad669bba9b9866c1eb2cd6d3dea1092c2
Candidate Git tree: 09ae420ced2f55a067b8824ca6e74a9a9d35f5c8
Review execution date: 2026-11-26 UTC

ROUTER ACCEPTED is NOT issued. The blind router-surface fleet round remains
unreleased; scheduling remains with the orchestrator.

F10's real raw canPerform contexts and F09's complete runtime graph/event
payloads are now CLOSED. CONF-04(c), (d), (e) and six of the seven listed
(h) rows are also CLOSED. Residuals are confined to the originally required
snapshots in (f), (g), and the owner-paid liability comparison in (h)/I01.
These are assertion-coverage gaps, not newly demonstrated product defects.
All independently selected candidate identities passed.

Disposition ledger

  (a) F10           CLOSED: real Agent.canPerform, raw action triples/literals.
  (b) F09           CLOSED: actual implementation edges, runtimes and payloads.
  (c) O04/F06       CLOSED: nested execute(apply) in both actor grids.
  (d) O11           CLOSED: both successful returns; commit inside log window.
  (e) O14           CLOSED: seeded R/C snapshot, log discipline, lock reuse.
  (f) I03/I04       PARTIAL: receipt/absence snapshot still incomplete.
  (g) F05           PARTIAL: venue/approval/receipt/absence snapshot incomplete.
  (h) Per-row       CLOSED except I01 owner-paid aggregate-liability delta.
  Census           UNCHANGED: exact 103 default / 25 fork identities.

Scope

Only review/ROUTERCONF2.md §5(a)–(h), :187–280, and its original referenced
requirements are adjudicated. ROUTERCONF3's existing CONF-01/F11 and
CONF-03/O18 closures remain credited. CONF-02, public-document CONF-05 and
CONF-06 are not reopened. No new product API, mutant, production rehearsal,
security-audit dimension or deployment authorization is required here.

Source abbreviations below:
  U = test/GaugeControllerAdmin.t.sol
  I = test/GaugeControllerAdminIntegration.t.sol
  F = test/fork/ForkGaugeControllerAdmin.t.sol
Fork discovery uses the concrete fork/GaugeControllerAdmin.t.sol wrapper.
Receipt paths without a directory prefix are under review/routerconf4/.

1. Independent execution and evidence boundaries

An exact local clone used fresh HOME/XDG data/cache/config, with only the
installed solc seeded and initial RPC cache empty. Forge 1.7.1, commit
4072e48705af9d93e3c0f6e29e93b5e9a40caed8; solc 0.8.30 executable SHA-256:
54f48274e5ec8a58b378f07c226fa1e25801526b6b0d16129f3a14a18efe72cd.
Fresh forge fmt --check, canonical offline builds with --sizes and
--extra-output storageLayout in both profiles, and native --list --json
all exited zero. The configuration was not changed.

Required guard-critical unit identity, independently reproduced:
  test/GaugeControllerAdmin.t.sol:GaugeControllerAdminTest:test_CommitApplyPostconditionsRollback()
  O14 pristine 0 -> M04 mutant 1 -> restored 0, exactly one selected identity
  per invocation. The product-only patch removes C.commit_transfer_ownership
  from R._commit while retaining pending assignment and the postcheck.
  The mutant compiled, then failed precisely at COMMIT_RETURNS_SUCCESS:
  O14-mutant.stdout:33–39, not an ABI/build/no-test failure. M04.patch and
  M04-mutant-preservation.json bind the delta. Every tracked clone input and
  the original router hash were restored; final clone status was empty.

Required guard-critical fork identity, independently reproduced:
  fork/GaugeControllerAdmin.t.sol:GaugeControllerAdminForkTest:test_Fork_GovernanceWrongCallerAndAclNegative()
  F10 PASS, native exit zero; no named falsifier in its original row.

Additional independent PASS identities, each checked by full native identity:
  fork/GaugeControllerAdmin.t.sol:GaugeControllerAdminForkTest:test_Fork_RealGovernanceInstallGrantAndHandback()
  fork/GaugeControllerAdmin.t.sol:GaugeControllerAdminForkTest:test_Fork_UnmaskedPreGrantRevokedRollback()
  test/GaugeControllerAdminIntegration.t.sol:GaugeControllerAdminIntegrationTest:test_PreGrantAndRevokedBothLanesRollback()
  test/GaugeControllerAdminIntegration.t.sol:GaugeControllerAdminIntegrationTest:test_ControllerFailureAndPostcheckRollback()
  test/GaugeControllerAdminIntegration.t.sol:GaugeControllerAdminIntegrationTest:test_PaidZeroWeightCanonical()

F10 was the first fork execution in the fresh cache; F09/F05 reused it.
The unchanged scripts/test-fork.sh verified chain 1, block 26401019,
timestamp 1794512471, hash
0x55810b079923a14fb97ad548f5024f65530dbc4fb2357a38f41e13b3d27cb6d3,
using https://eth-mainnet.public.blastapi.io. Its internal exec sets the fork
profile; receipt metadata records the entry environment, as explained in
receipt-notes.txt. No fresh full 103/25 rerun is claimed by this reviewer.
The orchestrator's reported full green is separate from these fresh runs.

The retained routerfix5 native full PASS sets and M01/M04/M05/M06/M10
pristine/mutant/restored receipts were parsed, not merely their summaries.
All selected triples are 0/1/0 at their named assertions. Only M04 is also
an independent replay here. Other named mappings remain M01/O05
AUTH_UNLISTED_REJECT, M05/O04 ADMIN_NON_D_GRANT_REJECT, M06/O11
EXECUTE_COMMIT_RECORDS_PENDING, M10/O09 EXECUTE_BUBBLES_FAILURE. No falsifier
is newly imposed on the fork or integration rows.

2. (a) F10 — CLOSED

Original requirement: ROUTERCONF2:187–206, especially :200–202, requires the
real Agent.canPerform with unshifted action words; it expressly preserves
NotDao(Voting), APP_AUTH_FAILED and failed-ballot rollback credit.

F:2232–2237 now calls IRouterAgent(DAO).canPerform with exactly three words:
[uint160(target), 0, uint32(selector)]. F:2184–2206 checks all prescribed
commit/apply(C), grant/commit/apply(R), and unpause(L) contexts. The three
sender-negative calls at :2211–2221 use the same real channel.

The required commit(C) literals sit in executable requires IN F10 at
F:2176–2182, not merely in F11, comments or a receipt:
  target   270125199945504599111523101509100263416079599291
  selector 1799625280

Fresh F10-trace.stdout:406–585 contains six positive and three negative
Agent-proxy canPerform frames. verify.py independently extracts each raw
triple and checks byte-identical forwarding into the kernel permission
context. This agrees with agent.sol:1253–1268,1501–1503; neither argument
is shifted. The zero-parameter ACL is not used as evidence that arbitrary
contexts are well formed. The actual call bytes supply that binding.

The same-action legitimate route remains. Fresh :739–767 enforces and
reaches NotDao(Voting); :995–996 reaches APP_AUTH_FAILED. Failed executed
flag and unchanged pending state remain asserted at F:2270–2278.

3. (b) F09 — CLOSED

Original requirement: ROUTERCONF2:208–216, refined without expansion at
ROUTERCONF3:179–211: bind actual proxy resolutions and full runtime identities
to reviewed fixed-pin inputs, including the distinct pinned registry edge;
retain full action/script/executor/event payloads.

F:501–574 retains shared-kernel, ACL reverse-link, raw kernel/appId slots,
base-namespace lookups and Voting -> kernel app namespace -> registry
routing. F:580–646 now pins the kernel/ACL instances, compares each app
proxy's implementation() with its base lookup AND reviewed fixed address,
and checks complete runtime keccaks for proxies, all implementations and
CallsScript. Proxy lengths are additionally asserted: app proxies 1035,
kernel 898, registry 858 bytes. The registry is expressly distinct from
the app-proxy runtime, not silently treated as the same code.

Resolved reviewed implementations:
  Agent    0x3A93C17FC82CC33420d1809dDA9Fb715cc89dd37
  Voting   0xa4D1a2693589840BABb7f3A44D14Fdf41b3bF1Fe
  ACL      0x81F7564e413586f1f99fDe55740Ac52b43cA99c9
  Kernel   0x2b33CF282f867A7FF693A66e11B0FcC5552e4425
  Registry 0xBF1Ce0Bc4EdaAD8e576b3b55e19c4C15Cf6999eb
  Executor 0x5cEb19e1890f677c3676d5ecDF7c501eBA01A054

F:654–664 binds the registry's OWN SLOAD at
0xdee64df20d65e53d7f51cb6ab6d921a0a6a638a91e942e1d8d02df28e31c038e
to implementation(), the reviewed registry implementation and implRegistry.
Fresh F09-trace.stdout:99–124 contains the actual implementation reads and
this slot read. Thus the specific previously unbound edge is now asserted.

Independently rehashed every runtime in routerfix5/receipts/graph-pins.json
and matched the executable constants. Proxy bytes also match the sealed
ROUTERCONF3 raw reads. The retained verified Agent/CallsScript sources and
runtime bytes agree with their source-service records and these runtime
pins. This is retained-source/runtime binding, not a claimed fresh upstream
source recompilation or creation-bytecode verification.

F:453–488,667–781,1985–2094 retains complete emitter/topics/data comparisons.
Fresh recorded arrays at F09-trace.stdout:791 and :1174 were independently
decoded against the authority encoder with the actual simulated R/L inputs.
For BOTH prescribed three-action scripts, verified:
  every Agent Execute sender, target, zero value and complete inner calldata;
  ScriptResult executor, full script, empty input and empty returned bytes;
  all three LogScriptCall sender/src/dst payloads;
  C CommitOwnership/ApplyOwnership successor data;
  R AdderSet key/bool and handback Committed/Applied successor topics.
Historical Agent trailing Execute bytes are unpadded; exact emitted bytes,
not a substituted modern padded ABI, were compared. Positive executed-vote
readbacks and per-script executor resolutions remain inside F09.

Authority-equal decoded script SHA-256:
  seating  3a5da3734fff836ff3b41aea17fbe53be196072071a9c5a599446224346b6948
  handback ba16b88c244a4f8c4d297b31fecc41d4a4e4f4429f7bfa90269c4768195fe36b

This proves conditional transport in local simulation: real Voting,
CallsScript, Agent and ACL with disclosed synthetic holder funding/time
movement. It does not certify historical quorum or authorize production.

4. (c) O04/F06 — CLOSED

Original requirement: ROUTERCONF2:218–223, nested execute(apply) for every
owed actor, retaining exact NotDao and no effect on the actual fixture.
U:341–356 and F:1589–1606 now contain that sixth selector. The loops/checks at
U:370–397 and F:1607–1620 exercise it rather than merely declaring it;
actual per-cell controller/granted-adder selection and exact error/state
checks remain. Retained full native sets include both exact identities;
M05's named sensitivity remains credited, not mislabeled a fresh replay.

5. (d) O11 — CLOSED

Original requirement: ROUTERCONF2:225–231, assert BOTH successful
execute/execute returns and record the execute-commit event itself.
U:1022–1044 captures dcRet/doRet and compares each to the ABI-wrapped empty
bytes result after successful calls. U:942 starts recording before the
execute-mediated commit; :971–977 checks its complete successor event.
The separate retired-apply negative does not substitute for either return.
Other typed/mixed payload and return credit stands; retained native O11
PASS and M06 named 0/1/0 were verified.

6. (e) O14 — CLOSED

Original requirement: ROUTERCONF2:233–240, full relevant R/C state and logs,
plus a successful post-failure mutator after EVERY specified rejection.
U:1368–1447 collects keyed grants, pending/retired/lock, ownership/counters,
seeded member/type/weight and type-weight state into whole-struct equality.
The actual fixtures are seeded at :1455–1489 with grants, distinct gauge
states, add_type and both weight mutators. U:1497–1520 checks exact failure,
zero entire-array log delta, unchanged snapshot and a successful grant with
its complete AdderSet payload after each rejection.

U:1530–1588 distinguishes recorder-visible reverted hook/C logs from the
committed cleared-hook control using enclosing low-level failure, rollback
and successful state transition. No reverted trace log is credited as a
committed receipt. Independent O14 and its M04 triple establish the required
execution and named sensitivity; section 1 supplies native bindings.

7. (f) I03/I04 — PARTIAL; exact remaining snapshot cells

Original requirement: ROUTERCONF2:242–248 explicitly requires keyed AND
chronological receipts/approvals and completion of WITNESSES:10, not counts
alone. Original matrix I03/I04 also requires full receipt/approval rollback
(plans/ROUTERPLAN-WITNESSES.md:171–183).

Credit: I:169–211 adds router grant/pending/retired/lock and more approvals;
:214–215 compares the entire collected World. Exact router errors and fee
frames, all-emitter empty windows where appropriate, the I03 committed
control/kept complete record (:653–716), and I04's exact reverted C/R trace
payloads (:781–871) now distinguish committed effects from recorder traces.
Fresh I03-I04-trace.stdout passes both complete identities. These repairs
are retained; the log/lifecycle cells are not returned for repair.

Residual: I:199–209 only queries getDeposit for each selected gauge at
E, E+WEEK, E+2*WEEK. The first queried epoch is the listing epoch, not a
maturity. The unchanged lister schedules four quarters at E+WEEK through
E+4*WEEK (contracts/CurveGaugeLister.sol:530–543). Thus the claimed complete
receipt snapshot omits the third and fourth scheduled keys. Fresh native
queries confirm that exact horizon in verification.json. In I03's revoked
fixture, the receipt digest at :692/:704 also excludes the retained gaugeC;
its kept-record helper :711–717 compares record/membership, not receipts.

Moreover, the sorted keyed loop is not a chronological adapter-record read.
The frozen MockIncentivePlatform only exposes getDeposit and depositCount
(contracts/mocks/MockIncentivePlatform.sol:149–162); it has no chronological
getter. No raw absent-getter observation is captured. Nor does the World
capture raw gauge_types failure data for absent candidates: I:187–190 skips
that getter when registered is false. WITNESSES:10 expressly specifies
success/revert status AND raw data for absent getters.

Remaining closure is the original full receipt/key/absence comparison for
these fixtures, including the retained member, with absence represented
honestly where the frozen fixture lacks a getter. It does not require adding
a production/mock API, executing settlement here, or a new mutant.

8. (g) F05 — PARTIAL; used-once and keyed-member repairs credited

Original requirement: ROUTERCONF2:250–258, full keyed rollback including
platform approvals, receipts, relevant venue/C/R state and committed logs,
plus an earlier genuinely committed member before revoke.

Credit: F:1138–1204 now actually grants, admits the legacy candidate,
observes full C NewGauge/R GaugeAdded/L GaugeListed/fee Transfer payloads,
then revokes. F:1222–1269 catches both exact NotAdder(L) failures on the
fresh candidate and compares keyed snapshots, including the retained member.
The first record is no longer hardcoded to GAUGE_PRIMARY. Regrant succeeds.
F:1279–1300 bounds the negative recorder window to crvUSD fee traces; failed
outer calls are not presented as committed fee Transfers. Router lifecycle,
FD and adapter custody, and retained-member type/weight are now compared.
Fresh F05-trace.stdout passes. None of this credit is withdrawn.

Residuals within the same original snapshot obligation:

  Approvals/venue balances: F:1402–1414 reads payer->L and L->adapters only.
  It never reads adapter->VOTIUM or adapter->CampaignRemoteManager allowances.
  Those are real approval edges in contracts/adapters/VotiumAdapter.sol:
  154–162 and VoteMarketAdapter.sol:211–221. The balances at F:1410–1411 are
  adapter custody, not the upstream VOTIUM/CRM balances. At least the actual
  VOTIUM venue balance on this 10000-bps fixture remains absent; calling the
  two adapter balances "both venues" does not supply that observation.

  Receipts: F:1375–1379 queries only E+WEEK for candidate/retained members;
  the remaining three scheduled keys are unobserved. F:1384–1391 does add
  real chronological depositAt calls, but every revert collapses to one
  zero word. Native F05-trace.stdout:1403–1408 shows the absent-entry calls;
  their raw failure data is discarded instead of compared. This does not
  satisfy WITNESSES:10's explicit status/raw-data rule.

  Absent C state: _isRegistered at F:342–344 discards returned/reverted bytes.
  _f05Member at :1313–1322 then substitutes type 999 and skips weight/type
  reads for absent candidates. The candidate's known gaugeType is available
  in Candidate (:350–355), but its relevant type weight is only collected
  for already-registered members. The pre-grant no-member fixture therefore
  has no candidate type-weight observation at all.

Closure remains completion of those named state observations on the existing
negative fixtures. No production action, new endpoint, identity or falsifier
is required. A passing negative and EVM rollback are genuine behavior, not a
substitute for the expressly required full snapshot assertions.

9. (h) Additional listed rows — all CLOSED except the I01 slice below

Original requirements: ROUTERCONF2:260–280 and ROUTERCONF:547–550 for I01's
still-open complete matrix snapshot claim.

  O05 (:263): CLOSED. U:425–459 supplies live full-payload control followed by
  explicit all-emitter zero negative delta; :466–482 binds the revoke-only
  window's full AdderSet payload. M01 retained named triple checked.

  O09 (:264–265): CLOSED. U:677–697 now requires type_weight(2)==77 after the
  successful call. Return/revert/event credit remains; M10 triple checked.

  I01 (:266–267): PARTIAL. I:284–318 checks every Listing field; :245–280,
  :396–399,:421–433 compare complete C/R/L admission logs for both payers.
  The first paid before snapshot now drives explicit deltas at :447–460.
  However, the owner-paid beforeB at :406 is passed at :420 to
  _i01OwnerPaidDeltas (:465–475), which never compares post.escrow. Its helper
  _assertMoneyUntouched (:323–351) does not compare escrow either. The last
  aggregate-liability assertion is :387, BEFORE the owner-paid admission;
  :435–436 checks token balances, not aggregate liability. The original
  I01 requirement includes exact listing/LIABILITY/balance/log snapshots
  (WITNESSES:157–162). Thus the collected owner-paid escrow field remains
  unused: the required post.escrow == pre.escrow + FEE, equivalently the
  expected aggregate after both admissions, is not asserted. Fresh I01 PASS
  and its correct trace readback are credited, not relabelled that assertion.
  This is the sole residual I01 slice; the new records/logs remain CLOSED.

  I02 (:268–270): CLOSED for the listed repair. I:498–500 enforces zero
  validator calls for every DAO-free candidate, with a one-call paid control
  at :547–552. The before snapshot feeds :535 and the deltas at :557–567.

  F03 (:271): CLOSED. F:940–1005 now compares complete NewGauge/GaugeAdded,
  GaugeListed and fee-Transfer payloads, retaining fee/count/type/weight.

  F04 (:272–273): CLOSED. F:1018–1096 binds the full four-admission count delta
  and post-revoke independent D-mediated ADMIN calls with resulting gauge
  weight 99 and type weight 9001, in addition to the already credited add.

  F06 (:274–276): CLOSED. F:1472–1557 now asserts changed gauge weight 12
  and the full third-add NewGauge payload; raw overload/read-return credit
  remains. Its separate nested-apply grid is closed in section 4.

All these exact identities are in the verified retained native green sets.
The prior I06 static-read observation boundary at ROUTERCONF2:278–280 stays
unchanged, not newly promoted or returned as a residual.

10. Preservation, census and publication boundary

The candidate delta from routerfix5 entry 6448def contains ONLY U, I and F.
There is no contracts/, foundry.toml, scripts/ or fork/ delta since 4ec0ac7.
All 46 baseline contract/test/fork/script/config hashes still match the
frozen BASELINE.json. The reviewer changed no product, test, profile, ABI
manifest or authority input in the publication tree.

Frozen SHA-256 values independently checked:
  contracts/GaugeControllerAdmin.sol
    a9627151440407dcfad188f0b08cef3a2d37f446020acb6209b7ea15461ecdbc
  plans/ROUTERPLAN-ABI.json
    e85e45116d2301993ce5736358effbe62939e5c8a6397a662f6df522dff78d6d
  foundry.toml
    f8ea5f0f3abfcb9c9987ef508cf5565cd840a5492f21960d7654c3ddbc79fac5
The owner-held ABI manifest equals the previously sealed authority; that
prior BINDING.json's published hash was verified, not assumed from its name.

Fresh discovery equals baseline union the full approved ledger, equals
ROUTERCONF3 discovery, equals each retained routerfix5 native full PASS set:
  default: 77 baseline + 26 router = 103, ledger lines 11–36;
  fork:    13 baseline + 12 router = 25, ledger lines 37–48.
Ledger: review/routerfix/receipts/CENSUS-LEDGER.md. F11/F12 remain the prior
approved additions at :47–48; no routerfix5/routerconf4 additions, deletions,
renames, skips, duplicates or count-only substitutions. Focused runs and
mutants are not additional census identities. Fresh diff --check passed.

Owner-local evidence:
  /home/winny/curve-gauge-lister/review/routerconf4/
Principal files: run.py, verify.py, context.json, verification.json,
receipt-notes.txt, M04.patch, M04-triple.json, preservation records, both
profile build/discovery receipts and all native selected-test traces.
BINDING.json covers 306 evidence/input files, all read back and hash-checked.
Its SHA-256 is:
  37815f32e7dcfd50d40ace18756f792e2ad0a3aece39742854d765a66eec4832
The report/publication metadata are excluded to avoid hash recursion.
Only this report is authorized for the publication commit; owner-local
receipts and ignored authorities remain outside it.

Final disposition: CONF-04(a)–(e) CLOSED; (h) CLOSED except I01's owner-paid
aggregate-liability comparison. CONF-04(f), (g), and that (h)/I01 slice remain
PARTIAL for the exact observations above. No other residual is added.
NONCONFORMS / HOLD. ROUTER ACCEPTED and fleet release are withheld.
