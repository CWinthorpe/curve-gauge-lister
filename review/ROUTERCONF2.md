ROUTERCONF2 — bounded re-check of the six ROUTERCONF dispositions

Verdict: NONCONFORMS / HOLD
Candidate: 21f4846e057bbaa99e2c33942e853b5c2e706982
Candidate product tree: 900b07d991c3505a5bc133b19e36ef3f824dc9b5
Review execution date: 2026-11-25 UTC

ROUTER ACCEPTED is NOT issued. This review does not release the blind
router-surface fleet round; scheduling remains with the orchestrator.
The remaining issues are conformance-evidence gaps within the original six
CONF dispositions, not newly established exploitable router defects.

Scope is review/ROUTERCONF.md:182–379 and its expressly incorporated per-row
limits. The original SPEC/DEPLOYMENT/WITNESSES/RULING obligations are not
weakened by a passing identity census or a correction comment. This is not
a new economic or router-security audit. Only this report is published;
product source, tests, public documents and authorities were not edited.

Disposition summary

  CONF-01  PARTIAL: selected Paris lifecycle genuinely executes; the required
           selected-instance post-handback direct type/weight tail is absent.
  CONF-02  CLOSED: prescribed three-action handback, actual payload bindings,
           restored real-C administration and interrupted recovery execute.
  CONF-03  PARTIAL: constructor and revoked-caller probes repaired; the new
           complete-value-surface claim still contains an OutOfFunds apply.
  CONF-04  OPEN: repaired observations receive credit below; exact remaining
           ACL, return, graph, snapshot and per-row cells are enumerated.
  CONF-05  CLOSED for the requested public-document remedy, with the explicit
           SPEC:101/77 boundaries; frozen NatSpec is not literally corrected.
  CONF-06  CLOSED: both relevant committed-range whitespace checks pass.
  Census   PASS: exact 103 default / 25 fork discovery and native PASS sets.

1. Fresh execution and preservation

An exact git archive of the candidate was built in an isolated directory
with fresh HOME/XDG state and initially no RPC cache. The installed solc
0.8.30 executable was the only compiler seed. Default Paris and fork Cancun
builds and native --list --json discovery exited 0. Full default execution
returned 103 Success, zero failures/skips; the unreachable-RPC default
repeat returned the identical 103 identities. Full fork execution returned
25 Success, zero failures/skips. These are independently parsed native
results, not the orchestrator's or repair ledger's totals.

The unchanged scripts/test-fork.sh verified chain 1, block 26401019,
timestamp 1794512471 and hash
0x55810b079923a14fb97ad548f5024f65530dbc4fb2357a38f41e13b3d27cb6d3
before fork execution through https://eth-mainnet.public.blastapi.io.
Fresh focused -vvvv reruns of F11, F12, F09, F10, O01, O18 and O20 also
exited 0. The full fork run was cold in the isolated state; focused runs
then reused that state. This review did not independently repeat the
repair leg's full warm-fork/unreachable-fork or M12–M14 mutation runs.
Those retained repair receipts are not relabelled fresh reviewer execution.

No archived source changed during execution. Between 4ec0ac7 and 21f4846,
contracts/, foundry.toml, scripts/ and fork/ have no diff. The correction
range changes only the five public documents and five already-added
router test/helper files recorded in verification.json; no frozen baseline
test was changed or removed. The router source is byte-identical to 4ec0ac7:
  SHA-256 a9627151440407dcfad188f0b08cef3a2d37f446020acb6209b7ea15461ecdbc
The existing artifact-fidelity conclusions are not expanded into a fresh
all-artifact comparison here. The selected Paris instance was freshly
constructed and exercised as described next.

2. CONF-01 — genuine selected lifecycle; exact remaining tail

Original requirement: review/ROUTERCONF.md:182–203; in particular the full
prescribed lifecycle under plans/ROUTERPLAN-DEPLOYMENT.md:15, which expressly
includes restored direct D add/type/weight and repeats with selected Paris
bytes, not only a Cancun analog.

F11 is real execution, not a renamed constructor smoke. At
 test/fork/ForkGaugeControllerAdmin.t.sol:1538–1714 it loads the default
out/ Paris artifact, constructs initcode with C/D, compares the entire
runtime of raw CREATE against a deployCode reference from that artifact,
checks embedded C/D/getters, and distinguishes the Cancun analog. Native
F11-trace.stdout records the selected 4,786-byte runtime. On that instance:
  - incumbent D seats R on the real pinned controller;
  - fresh unchanged L is wired to R and explicitly granted;
  - paused DAO-free admission forwards 4242; paid admission forwards zero;
  - independent D addition, add_type and change_gauge_weight execute;
  - L's grant is revoked and an independent D addition still succeeds;
  - R commits/applies back to D, becomes retired, clears local pending,
    rejects a subsequent grant and retains public reads;
  - restored D directly calls raw C.add_gauge with initial weight 5.
Native F11-trace.stdout:1184–1250 contains the final handback, Retired and
raw direct-add frames. Credit all these operations. Both F11 and F12 were
read and independently rerun, not merely accepted from repair receipts.

Remaining cell: _f11Handback at
 test/fork/ForkGaugeControllerAdmin.t.sol:1644–1669 stops after that direct
add. It does not call post-handback raw add_type, change_type_weight or
change_gauge_weight. The improved F07 does those operations on its Cancun
instance; it cannot supply the expressly required selected-byte repetition.
This is the residual of the original CONF-01 full-rehearsal obligation, not
a denial that F11 now seats and exercises Paris. Add those restored-direct
operations and exact readbacks to the selected-instance rehearsal. No new
production address, live transaction or new census identity is required.

3. CONF-02 — closed within its sequence/recovery scope

F09 now executes grant(L,false), commit_transfer_ownership(D), then
apply_transfer_ownership(), each wrapped by Agent.execute(target,0,data),
in the real Voting→CallsScript→Agent route. See
 test/fork/ForkGaugeControllerAdmin.t.sol:1213–1320. Exact outer/inner call
expectations and positive getVote.executed readback are present. This review
also extracted the ACTUAL two newVote scripts from fresh F09-trace.stdout
and compared the complete bytes against review/routerplan/encode_payload.py
for those exact simulated R/L addresses. Both ordered three-action scripts
match. SHA-256 of the decoded script bytes:
  seating:  3a5da3734fff836ff3b41aea17fbe53be196072071a9c5a599446224346b6948
  handback: ba16b88c244a4f8c4d297b31fecc41d4a4e4f4429f7bfa90269c4768195fe36b
These are local simulation payload bindings, not production proposal hashes.

F07 now supplies both L lanes, independent D additions, nominee replacement,
handback, raw direct D add/add_type/change_type_weight/change_gauge_weight
with exact readbacks, and retained paid-record/liability/custody checks:
 test/fork/ForkGaugeControllerAdmin.t.sol:889–1049. It passed in the fresh
full fork set. Its selected-byte repetition remains in CONF-01, not waived.

F12 now enforces real grouped-script failure at InvalidAdder(R), with
admin/future/grant/local-state rollback for atomic S1–S3; an earlier committed
S1 survives the later failed S2/S3 group. D's explicit cleanup commit(D)
restores admin=D/future=D, never-seated R cannot add, nominee replacement
works, and a corrected real S2/S3 vote seats/grants the composition. A real
paid admission and revoke/commit/apply handback then succeed. Source:
 test/fork/ForkGaugeControllerAdmin.t.sol:1747–1895. Fresh native invalid-S3
frames are F12-trace.stdout:644–654 and :1164–1169; subsequent recovery and
final handback are in that same successful trace. F12 is an interruption
recovery drill, not a second claim to repeat F11's two-lane Paris lifecycle.

D impersonation for lower-level setup/cleanup/handback is credited as
mechanics only. The grouped ballots use real newVote/vote/executeVote,
CallsScript and Agent. The disclosed synthetic veCRV holder-point funding
and clock changes remain simulation, not historical quorum or governance
approval. No source/runtime/ACL replacement or mainnet write is credited.

4. CONF-03 — repaired named guards, residual masked value cell

Constructor credit: O01 now funds the immediate ValueLauncher executing
CREATE, supplies a successful zero-value control, and checks empty rejection
data and launcher balance. Fresh O01-trace.stdout:99–106 shows deal(launcher,1)
then child creation ending at [Revert], not OutOfFunds. O18's corresponding
funded constructor frame is O18-trace.stdout:273–280. Constructor-address
negatives and deployer exclusions also reach their intended guards. This
closes the original constructor-masking defect, without relying on an ABI
comparison as a substitute for native rejection.

Revocation credit: O20 calls R FROM each revoked actor. Fresh final frames:
  O20-trace.stdout:83–84
    GaugeControllerAdmin::add_gauge(...)
    [Revert] NotAdder(0x5991A2dF15A8F6A256D3Ec51E99254Cd3fb576A9)
  O20-trace.stdout:87–88
    GaugeControllerAdmin::add_gauge(...)
    [Revert] NotAdder(0xc7183455a4C133Ae270771860664b6B7ec320bB1)
Neither failure descends into C. Granted positives, unchanged memberships/
weights/counters, independent D addition and regrant remain. The old
unrecognized-selector failures at the holder contracts are gone.

Remaining cell: the expanded O18 surface still does not prove nonpayable
apply. test/GaugeControllerAdmin.t.sol:1708–1726 creates a new seated fixture
fa, commits correctly, but never funds fa.dao before its 1-wei call. The
funding in _valueLanePrivileged(:1756–1768) belongs to other callers/fixtures.
Fresh O18-trace.stdout:230–231 is unambiguous:
    [0] GaugeControllerAdmin::apply_transfer_ownership{value: 1}()
        [OutOfFunds] EvmError: OutOfFunds
The zero-value apply subsequently succeeds (:236 onward). The test accepts
!avOk && avRet.length==0, so insolvency satisfies its purported callvalue
oracle. Fund the actual value-debited caller in this fresh fixture and retain
the otherwise-successful control; require native execution to reach the
router's nonpayable rejection. The remaining getters/privileged mutator
probes and funded constructor improvement are credited. This is residual
CONF-03 complete-surface evidence, not a claim the real apply is payable.

5. CONF-04 — load-bearing repairs and exact residual cells

Repaired credit: O03 enforces repeated-revoke AdderSet and no invalid-key
logs; O04 now includes the outsider throughout and uses its own fixture's C;
F06 includes actual L and another granted adder. I05 now starts paused and
revoked and contrasts the restricted L lanes against independent D access.
I03/I04 add selected-candidate membership/type/weight, platform allowances
and log checks. O14 adds lock/local/controller snapshots. O11 adds several
successor payload and return assertions. F07's liability/record/custody
repair is credited above. These assertions were exercised by the fresh
passing identity sets; their existence does not close the residuals below.

(a) F10: parameter-specific canPerform evidence still wrong.
    test/fork/ForkGaugeControllerAdmin.t.sol:1434–1445 calls ACL.hasPermission,
    not Agent.canPerform, and shifts BOTH uint160(target) and uint32(selector)
    left by eight. DEPLOYMENT:16 requires the RAW values. The retained verified
    Agent source, review/routerplan/evidence/agent.sol:1253–1268,1501–1503,
    forwards its runtime parameter array without those shifts. Fresh
    F10-trace.stdout:406–419 shows the shifted arguments. For commit(C):
      required target: 270125199945504599111523101509100263416079599291
      observed target: 69152051186049177372549913986329667434516377418496
      required selector: 1799625280
      observed selector: 460704071680
    The role's parameter length is asserted zero (:1392–1397), so a true
    unparameterized result cannot validate those malformed action contexts.
    Call the real Agent.canPerform with the prescribed unshifted triples for
    every C/R/L action. This is the original permission-read cell, not an
    allegation that the actual successful governance calls lack authority.
    The negative repair IS effective: exact NotDao(Voting) is enforced and
    appears at F10-trace.stdout:645–651; exact APP_AUTH_FAILED appears at
    :879–880. The legitimate control now uses the same commit/arguments, and
    failed-ballot executed rollback is enforced. Do not withdraw that credit.

(b) F09: complete governance binding/event cell remains partial.
    test/fork/ForkGaugeControllerAdmin.t.sol:1238–1248 checks nonzero kernel/
    ACL, token equality and a hardcoded registry's executor. It does not bind
    the full Voting/Agent/proxy/Kernel/ACL implementation/runtime graph or the
    actual graph-to-registry relation. Positive executed readback and exact
    script/call binding are repaired; the event checks at :1269–1270 and
    :1304–1313 remain topic counts rather than complete Agent/C/R event
    payload checks. Native transport is real; these missing assertions are
    not supplied merely by its presence in a trace.

(c) O04/F06: the actor repair covers their listed outer selectors, but both
    arrays omit execute(encode(apply_transfer_ownership())). They include
    nested commit only: test/GaugeControllerAdmin.t.sol:337–348 and
    test/fork/ForkGaugeControllerAdmin.t.sol:845–855. Complete the original
    every-actor/nested-ownership cell with nested apply, retaining exact
    NotDao and no-effect assertions on the actual fixture.

(d) O11: execute/execute success returns are still discarded at
    test/GaugeControllerAdmin.t.sol:911–927. The new claim at :948–960 instead
    probes an already-retired apply and checks Retired; it does not inspect
    either successful return. Capture/assert both successful empty-byte
    results. In the execute-commit/typed-apply case, log recording starts
    after commit (:844–856), so that commit's complete event payload remains
    unobserved. Other mixed/typed successor-payload and return repairs stand.

(e) O14: test/GaugeControllerAdmin.t.sol:1261–1305 is a selected snapshot,
    not full R/C/log equality. Grant flags and C membership/type/weight state
    are not captured; the log filter selects only three R event signatures,
    not all relevant C/R committed logs. Lock-word equality is checked for
    every failure, but an actual successful post-failure mutator appears only
    after the first rejection (:1175–1177). Complete the original full-state/
    log and reusable-lock observations, without confusing reverted recorder
    trace logs with committed receipt logs.

(f) I03/I04: test/GaugeControllerAdminIntegration.t.sol:121–176 now captures
    more keyed C state and L→platform allowances. It still has deposit counts,
    not keyed AND chronological adapter receipts/approvals, and no R grant/
    pending/retired snapshot. I04's :395–426 filters lister/venue recorder
    events; that is not a complete committed-log rollback oracle for C/R/token
    effects. Keep exact errors and the added comparisons; complete the
    original snapshot definition in plans/ROUTERPLAN-WITNESSES.md:10.

(g) F05: test/fork/ForkGaugeControllerAdmin.t.sol:621–693 still has the old
    limited snapshot. getListing(GAUGE_PRIMARY) is hardcoded rather than keyed
    to each selected negative candidate; platform approvals, keyed and
    chronological receipts, full relevant balances/C type-weight/R lifecycle
    state and committed logs are not all observed. The revoked subfixture
    at :602–618 still revokes before its first admitted member, despite the
    earlier 'used once' description. Preserve the genuine NotAdder(L) frames
    and regrant control, but supply the originally owed full keyed rollback
    and earlier-committed-member observation.

(h) The additional per-row limits explicitly incorporated in the original
    CONF-04 at review/ROUTERCONF.md:319–321 remain as follows; these are not
    new audit findings:
      O05: no explicit negative log delta, unit test :397–433.
      O09: change_type_weight success but no literal resulting weight,
           unit test :637–641.
      I01: 'before' unused and no complete listing/log comparison,
           integration test :183–223, especially :190,208.
      I02: 'before' unused and no validator-call non-occurrence assertion,
           integration test :230–263, especially :237,256. Unchanged L source
           still independently supports the validator-free behavior.
      F03: NewGauge/GaugeAdded counts, not full payloads, fork test :494–506.
      F04: no full count delta or post-revoke independent ADMIN operation,
           fork test :524–560; a post-revoke add is present and credited.
      F06: changed gauge weight lacks its literal-value assertion; direct/
           routed return parity and a counted NewGauge are not that value
           or full event payload, fork test :766–813.
    Here 'unit test', 'integration test' and 'fork test' refer respectively
    to the three fully named test files cited above. The earlier I06 boundary
    is unchanged: executed settlement/counters plus unchanged source support
    no router dependency; counters alone do not observe every static read.

Closure is the missing observations on these existing rows, not another
headline PASS count or an expanded product API. No new mutation-reproduction
requirement is invented in this re-check.

6. CONF-05 — public hooks supplied; stated boundaries retained

README.md:20–31,46 supplies the router and layout, immutable C/D, fixed-target
zero-value execute, full granted raw-add weights, mediated ownership and
permanent retirement. docs/ABI.md:107–159 supplies the separate constructor,
complete callable signatures/events/errors, storage, encodings and lifecycle
reference. docs/CURVE-PROPOSAL.md:28–37 states immutable D, intended delegated
weights/retained administration, predeployment, S1–S3 and separate conditional
unpause, retirement and rollback limits. docs/OPERATIONS.md:17–26 supplies
predeployment verification, rehearsal, cleanup, execute-ABI distinction,
no-reseat and donation response. docs/DEPLOYMENT-PINS.md:36–47 supplies the
artifact/embedded-immutable/readback/grant-history/script-hash bindings.

Funds/incumbency are read precisely as SPEC:101/77: no intended custody or
money-handling API, NOT zero balances forever; forced ETH/unsolicited tokens
can remain stranded with no recovery promise. Incumbency gates C-reaching
mutation, NOT pre-seat grant. README:28,31 and ABI:133,151 make these limits
explicit. D's full controller administration and every adder's controller-
valid initial-weight power are intended, not erased by a 'no emissions power'
slogan. Production addresses, approval, installation and activation remain
unselected/unapproved; existing FD/venue/kill/settlement limitations remain.

The two short source NatSpec statements flagged in the first report remain
byte-identical at contracts/GaugeControllerAdmin.sol:28,238–239. This closes
the requested candidate-true PUBLIC documentation remedy, not a claim those
source sentences were edited or become literally true without the published
SPEC qualifications. No source change or economic amendment is inferred.

7. CONF-06 and exact census

Fresh git diff --check ff18d92 21f4846 and
 git diff --check 4ec0ac7 21f4846
both exited 0 with no whitespace diagnostics. Fresh forge fmt --check also
exited 0. This examines the committed range, not only a clean worktree.

verification.json independently reconciles BASELINE.json with the updated
review/routerfix/receipts/CENSUS-LEDGER.md and both native discovery/PASS sets:
  default: 77 baseline + 26 router rows = 103; all set differences empty.
  fork:    13 baseline + 12 router rows = 25; all set differences empty.
No duplicate identity, baseline deletion, skip or extra concrete inherited
suite was admitted. Versus 4ec0ac7, the ONLY new identities are:
  ledger line 47, F11:
  fork/GaugeControllerAdmin.t.sol:GaugeControllerAdminForkTest:test_Fork_SelectedParisArtifactFullLifecycleRehearsal()
  ledger line 48, F12:
  fork/GaugeControllerAdmin.t.sol:GaugeControllerAdminForkTest:test_Fork_InterruptedSeatingRollbackAndRecovery()
Their explanatory ledger entries are lines 65–66. Repeated/focused runs,
loop subcases and retained mutations do not add census entries. The ledger's
PASS totals are confirmed; its stronger complete-conformance implication is
not confirmed by those totals.

8. Evidence custody and disposition

Owner-local evidence:
  /home/winny/curve-gauge-lister/review/routerconf2/
Principal files: run.py, verify.py, seal.py, context.json,
source-preservation.json, verification.json; separate .stdout/.stderr/.run.json
for both builds/discoveries, full offline/unreachable/fork runs, the seven
focused traces, format and both range-sensitive whitespace gates.
BINDING.json covers 105 evidence/input files, including scripts, native
receipts, authorities, ledger, relevant source/tests and public documents.
The report and publication metadata are excluded to avoid recursive hashes.
BINDING.json SHA-256:
  3f840f45c451b62f94f1f97a617d2461ce7fc63d37f25666ab9f2714a9ae3cc6
Evidence is owner-held and producible on demand, not added to the public
commit. Native receipt hashes and every bound file were checked.

Disposition: CONF-01, CONF-03 and CONF-04 remain open to the precise extent
above. CONF-02, the requested CONF-05 public-document remedy and CONF-06 are
closed; census/preservation pass. No ROUTER ACCEPTED certificate or blind
fleet release is issued. No signing, broadcast, mainnet state change,
production deployment, activation approval or new economic review occurred.
