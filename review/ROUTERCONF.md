ROUTERCONF — bounded GaugeControllerAdmin conformance review

Verdict: NONCONFORMS / HOLD
Candidate: 4ec0ac760a0870161c79f2406247a3255ddd38ec
Candidate product tree: d55c948e791b98701634f5bbc7ceb24e3ea17b4e
Review execution date: 2026-11-25 UTC

ROUTER ACCEPTED is NOT issued. The router-surface blind fleet round is not
released by this review. Scheduling remains with the orchestrator. This
review identifies missing or defective conformance evidence and missing
public-document work; it does not establish an exploitable authorization,
forwarding, retirement or economic defect in the candidate router.

Authority is plans/ROUTERPLAN-SPEC.md, plans/ROUTERPLAN-ABI.json,
plans/ROUTERPLAN-DEPLOYMENT.md and review/routerplan/RULING.md, including the
witness matrix and work-order gates incorporated by that ruling. SPEC §7
actually contains TEN statements, SP01–SP10, not seven. All ten are addressed
below. No authority file was changed to fit the candidate.

The requested publication exception is confined to this report. Product
source, tests, configuration, existing public documents and historical
receipts were not edited. The three product mutants ran only in a disposable
archive and were restored byte-for-byte. No signing, deployment broadcast,
mainnet state change or activation authorization occurred.

1. Six requested review cells

1. Contract fidelity: PASS for source, compiled surface and layout.
   Fresh independent builds under both profiles reproduce the entire new ABI,
   method identifiers and recursive storage types. Constructor and runtime
   behavior agree with the written law, subject to the defective value-probe
   witness described in CONF-03. That witness defect does not make the
   compiler-generated nonpayable constructor payable.

2. Construction statements/falsifiers: source arguments supported; required
   independent three-row falsifier reproduction PASS. All eleven retained
   native falsifier receipts were also checked. This does not close missing
   positive/negative cells elsewhere in the normative witness matrix.

3. Lifecycle/deployment rehearsal: PARTIAL / BLOCKED. The state machine works
   in the executed tests, but the selected Paris instance never undergoes
   the prescribed lifecycle, the genuine-governance handback omits revoke,
   and restored direct type/weight administration and interrupted recovery
   are absent from the required fork rehearsal. See CONF-01/02/04.

4. Non-economics: PASS for the specified no-intended-custody boundary and
   byte preservation. R has no L records, epoch/budget state or funds-handling
   API. L and every pre-existing contracts/-defined artifact are unchanged
   under the corresponding compiler profile. Forced holdings remain possible.

5. Census: PASS. Exact discovery/PASS sets equal the baseline union ledger:
   77 + 26 = 103 default; 13 + 10 = 23 fork. No duplicate identities or test
   signatures, no baseline removal, and no extra inherited concrete suite.
   These are identity results, not proof that every named cell is asserted.

6. Public documentation: FAIL. The five required P4 hooks were not applied.
   Public prose still describes an unsupplied/prospective router, omits its
   complete ABI and lifecycle limits, and source NatSpec contains two
   overbroad claims. See CONF-05.

2. Fresh execution and artifact results

Environment and provenance

- Exact candidate and ff18d92 archives were built separately in fresh output
  directories; all existing tracked files also compare equal to f54ca9d,
  the certified authority base. The only candidate delta is seven added
  files: the router and six test/helper files.
- Forge 1.7.1, commit 4072e48705af9d93e3c0f6e29e93b5e9a40caed8;
  solc 0.8.30+commit.73712a01; optimizer enabled/200; viaIR=false.
  Default Paris; fork Cancun/chain 1. The isolated compiler executable's
  SHA-256 is 54f48274e5ec8a58b378f07c226fa1e25801526b6b0d16129f3a14a18efe72cd.
- Native command receipts retain argv, cwd, profile/environment, timestamps,
  separate stdout/stderr and child exit. No shell success label replaces a
  Forge result. Initial reviewer-script bookkeeping corrections are disclosed
  in review/routerconf/harness-notes.txt, not counted as product failures.

Native runs

- forge build --offline --sizes --extra-output storageLayout --ast:
  candidate default/fork and baseline default/fork all exited 0.
- forge test --offline --list --json: both candidate and baseline profiles
  discovered exactly their expected full identities.
- Full default forge test --offline --json, RPC unset: 103 Success, no
  failure/skip. Repeat with MAINNET_RPC_URL=http://127.0.0.1:1: the identical
  103 Success identities. Native result kinds contain no fuzz identities;
  no iterations, subcases, repeated runs or mutation experiments are added
  to the census. A future fuzz identity must still count once.
- First cold fork attempt through PublicNode verified the header but failed
  archive-state access with HTTP 403. It is retained as fork-cold.* and is
  NOT a passing behavioral negative or a successful fork gate.
- A separate initially empty HOME/XDG cache, with only the installed compiler
  seeded, was used with https://eth-mainnet.public.blastapi.io. The unchanged
  scripts/test-fork.sh passed 23/23 cold and the same 23/23 warm, zero skips.
- The wrapper verified chainId 0x1, block 26401019 (0x192d8fb), timestamp
  1794512471 (0x6af61657), and hash
  0x55810b079923a14fb97ad548f5024f65530dbc4fb2357a38f41e13b3d27cb6d3.
  No moving-head retry, repin, mocked C or replaced upstream runtime was used.
- Warm-cache unreachable-RPC repeat exited 1 with BLOCKED: RPC before any
  Forge PASS/test execution. Header success was not treated as archive access.
- Focused native -vvvv reruns of F01/F07/F09/F10 and O01/O20/I05 each passed
  their existing identity. Their actual frames establish the evidence gaps
  below. They are reruns, not additional census entries.
- The authority encoder's synthetic seating/unpause/handback self-test exited
  0. This validates encoding/decoding only, not selected addresses, ACL or a
  production vote. Its three-action handback differs from F09's two actions.

Full artifact equality

The comparator matches artifacts by source path:contract name. It compares
complete ABI entry objects as multisets, not selected fields/signatures or
counts; method identifiers; slot/offset/type structure; full decoded creation
and runtime bytes INCLUDING metadata; named immutable references; and link
references. Only numeric compiler AST bookkeeping in structural layouts is
normalized. Empty interface bytecode is explicitly included, not omitted.

For EACH profile all 26 pre-existing contracts/-defined artifacts match the
baseline in every comparison. The only new product artifacts are the narrow
local interface and GaugeControllerAdmin. Existing test/source files are
also byte-equal. The old byte-equality conclusion does not depend on stripping
metadata or comparing only a few deployables.

GaugeControllerAdmin compiled surface, both profiles:
  constructor 1; external functions 12; events 5; declared errors 14.
  Full entry objects, including names/internalType/indexing/returns/mutability,
  equal ROUTERPLAN-ABI.json. There is no receive or fallback.

Storage:
  controller, dao: embedded immutable addresses, independently named through AST.
  isAdder: mapping(address => bool), slot 0.
  pendingControllerAdmin: address, slot 1 offset 0, 20 bytes.
  retired: bool, slot 1 offset 20, 1 byte.
  _lock: uint256, slot 2 offset 0, initially 1.
  No other persistent fields.

Sizes, decoded with metadata intact:
  Paris:  runtime 4,786; creation 5,332; initcode + two arguments 5,396 bytes.
  Cancun: runtime 4,683; creation 5,220; initcode + two arguments 5,284 bytes.
  Both satisfy runtime <=24,576 and initcode <=49,152.

Source pin SHA-256:
  R: a9627151440407dcfad188f0b08cef3a2d37f446020acb6209b7ea15461ecdbc
  L: c9f7b8fc859c51a7991616be3328826e7ca253c62633acf55ab0822ee9c54c67

For L, independently rebuilt full-byte SHA-256 values:
  Paris creation: a160d73f34642c1ba4ba59ef8b0b52575757b8593229c34df01eafb529baf473
  Paris runtime:  3049aa3dc2615abf867eb79c36352caa85c5e1adc7ed3ecbc6a043ebd6a155cc
  Cancun creation: f2ba5c5b9275ec692a6612c270695483df6f640caec6cf6db1b20e697f708bdc
  Cancun runtime:  dcdf030bb5241bde1b4b972f8f689171a2fb8e8d21b6ea11957eadf4e9e6429b
These are identical to the corresponding baseline artifacts; they are not a
claim that an unselected production instance has been deployed.

Contract-fidelity clarifications

contracts/GaugeControllerAdmin.sol:123–129 rejects zero/self C, no-code C and
zero/self/C D; assigns both parameters explicitly; and performs no seating,
auto-grant or fund movement. SPEC:15 expressly does NOT require D to have code
in the reusable ABI, and does not hard-code the production address literals
into constructor validation. Production must separately pin C and D. The
fork fixtures use canonical C=0x2F50D538606Fa9EDD2B11E2446BEb18C9D5846bB and
D=0x40907540d8a6C65c637785e8f8B742ae6b0b9968. Absence of a D-code requirement
is therefore not a finding.

Exact pragma is 0.8.30 and R has zero imports. IListingController remains
unchanged with its three-function subset. Every administrative mutator has
onlyDao then activeLock; add has onlyDaoOrAdder then activeLock. Typed and
execute ownership paths share _commit/_apply, strict ownership encodings and
postconditions. Authorization precedes retirement, which precedes the lock.
Fresh local pending state prevents stale-future-admin apply. Retirement is
set before the external apply and never cleared. Reads remain public.

All R external destinations are immutable C; the sole low-level generic call
is controller.call(data), without value. The typed calls also use C. An
instruction-aligned runtime inventory excluding CBOR metadata and PUSH data
found four CALL sites and six STATICCALL sites in each profile; no
DELEGATECALL, CALLCODE, CREATE, CREATE2, SELFDESTRUCT, BALANCE or SELFBALANCE.
This inventory supplements the source/ABI/storage proof; it is not presented
as a standalone complete control-flow theorem.

3. Blocking conformance gaps

CONF-01 — selected Paris lifecycle rehearsal is missing

Authority: DEPLOYMENT:15; SPEC:122; WORK-ORDER:29,53; RULING:43.
Sites: test/fork/ForkGaugeControllerAdmin.t.sol:135–136,351–376.

F01 CREATEs the Paris artifact and checks runtime length, C/D getters and a
canonical count read. It never seats that Paris instance, grants L, exercises
both L lanes, performs independent D administration, revokes, or hands back.
F02–F10 create their routers with new GaugeControllerAdmin under the Cancun
fork profile. A Paris constructor/read smoke is not the prescribed selected-
byte installation-and-handback rehearsal. F01's own runtime assertion also
compares length, not the immutable-patched full runtime.

Fresh F01-trace.stdout records the 4,683-byte Cancun creation and the separate
4,786-byte Paris creation, followed only by reads on the latter. The source
and fresh artifact comparator bind which creation bytes were supplied; they
do not turn those reads into a lifecycle execution.

Required closure: run the full prescribed lifecycle using the exact selected
Paris artifact with independently bound immutables/runtime, on real C at the
fixed fork pin. Keep this separate from a Cancun analog and from production
address/approval selection, which remains open.

CONF-02 — prescribed handback/recovery sequence is not fully rehearsed

Authority: SPEC:30,73–77; DEPLOYMENT:15,31–44,70–75;
WITNESSES F07/F09; WORK-ORDER:53,59.
Sites: test/fork/ForkGaugeControllerAdmin.t.sol:843–911,1081–1120.

F07 genuinely performs incumbent seating, a paid L addition, revocation,
nominee replacement, handback to D and a direct raw D addition. Credit those
facts. However:
  - the claimed restored direct add/type/weight check at :877–881 only calls
    add_gauge with initial weight 5. There is no post-handback add_type,
    change_type_weight or change_gauge_weight call;
  - the full rehearsal does not include both L lanes plus the independent
    D→R route in that lifecycle; F04 supplies separate partial mechanics;
  - :883–886 checks C count/type/weight, not the asserted unchanged L
    settlement entitlement/liability/custody;
  - F02's S1 intermediate observation is not the interrupted-install cleanup
    C.commit_transfer_ownership(D). No exact interrupted rollback rehearsal
    supplies the DEPLOYMENT:15 obligation.

F09's genuine-governance install has S1/S2/S3 in the correct order. Its later
handback has only commit/apply, omitting D→R.grant(L,false). The authority
encoder at review/routerplan/encode_payload.py:69–72 instead includes revoke,
commit, apply. F09-trace.stdout contains one grant, enabled=true, and no
revocation. Its passing handback therefore does not execute the prescribed
script as written. This is a policy/rehearsal gap, not an on-chain requirement
that _apply erase historical grant flags: the spec deliberately permits stale
flags after irreversible retirement.

F07-trace.stdout confirms the direct add and retirement errors, with no
post-handback type/weight mutator. O15 proves direct add/type/gauge-weight on
a mock, not real-C completion of this fork cell. F08 correctly proves a
callable successor and disposable no-revival reseat; legitimate nominee
replacement is present and is NOT incorrectly required to revert.

Required closure: correct the exact governance action list; rehearse the
required pre-production sequence, direct D add/type/weight restoration and
interrupted cleanup/recovery. Do not alter the authority to match the shorter
script or claim that production authorization has already occurred.

CONF-03 — two native negative witnesses are masked or misdirected

Authority: WITNESSES O01/O18/O20; SPEC:15,101,110;
WORK-ORDER:49,51; RULING:39–43.

(a) Constructor value rejection never reaches the constructor.
    test/GaugeControllerAdmin.t.sol:81–84 creates ValueLauncher but does not
    fund it. :1614–1619 issues CREATE(value=1) from that unfunded launcher.
    Funding the outer test contract at :38 or :1374 does not fund the actual
    CREATE executor. Fresh O01-trace.stdout:87–92 explicitly records
    OutOfFunds and return false. O18 uses the same helper at :1415.
    This is not native proof of a nonpayable constructor rejection. Full ABI
    equality independently confirms the actual constructor is nonpayable.
    Fund the immediate launcher and assert the intended failure cause, with
    a deployable/funded positive control. Value probes for administrative
    functions also use the unprivileged test caller; use otherwise-authorized
    successful controls to prevent authorization masking, and cover the
    claimed complete surface rather than only five mutators.

(b) O20 calls the revoked holder addresses, not R from those holders.
    test/GaugeControllerAdmin.t.sol:1547–1552 passes a1/a2 as _call targets.
    RouterHarness.sol:29–31 is target.call(data), not caller impersonation.
    Fresh O20-trace.stdout:79–82 shows RouterAdderShim::add_gauge and
    RouterSuccessorMock::add_gauge reverting for unrecognized selector
    0x18dfe921/no fallback. Neither negative reaches R's NotAdder gate.
    Invoke R from each revoked actor and assert exact NotAdder(actor), no
    C-frame/effect, while retaining successful granted controls.

O05, I03 and F05 do contain genuine router authorization negatives and passed
freshly. Revocation itself is not shown broken. The defective O20 row cannot
borrow their credit and claim its own two negative calls reached R.

CONF-04 — required assertion/observation cells remain incomplete

Authority: SPEC:59,88,97–99; WITNESSES O03/O04/O11/O14/I01–I06/F04–F07/F09/F10;
DEPLOYMENT:16,42; RULING:43. These are witness limitations, not demonstrated
state-corruption or governance exploits.

- F10's _f10AclReads (:1147–1158) calls only three-argument hasPermission,
  despite its comment claiming target/value/selector context. It does not
  read canPerform(V,EXECUTE_ROLE,[uint160(target),0,uint32(selector)]) for
  the prescribed C/R/L actions. Its direct-Voting negative uses bare
  expectRevert (:1181); the outsider Agent probe discards failure bytes and
  uses empty C calldata (:1141–1144), so a downstream failure could satisfy
  that oracle. The positive control is a different action (commit, not grant).
  Fresh F10 trace DOES show NotDao(VOTING) and APP_AUTH_FAILED in this run;
  those observed causes are credited, but the witness does not enforce them
  and the required parameter-specific ACL/read coverage remains absent.
- F09 reads nonzero kernel and a hardcoded registry's executor (:1069–1076),
  but does not bind the complete Voting/Agent/proxy/Kernel/ACL implementation
  graph in its assertions. _runGovernanceVote counts Voting event signatures
  (:1059–1062); it does not assert exact Agent/C/R payloads or positively
  reread getVote.executed. The actual native transport frames are present and
  are not denied. Local R/L deployment and D-impersonated adapter binding are
  setup mechanics, not governance-transport credit.
- O04's caller loop starts at index 1 (:322), after testing outsider grant
  only. It does not run the entire administrative selector set for that
  outsider; its C-role address comes from p1 rather than the fresh fx. F06's
  unauthorized grid (:805–823) covers outsider, not L and another granted
  adder as its row requires. Test every owed actor/selector on its actual
  fixture, including nested ownership paths.
- I05 explicitly unpauses L (:402); its required positive starts with L
  paused and revoked. Its only attempted L lane reaches already-occupied
  membership (:431–434), not all the asserted restriction contrasts. Fresh
  I05 trace confirms setPaused(false). The independent D route works, but
  that does not make the named paused/both-lane cell complete.
- The I03/I04 World snapshot (:121–155) does not capture all required
  allowances/receipts/logs/controller membership weights. F05's snapshot
  (:641–672) likewise omits logs and complete approval/receipt/platform state;
  the listing key is hardcoded rather than taken from each selected negative
  candidate. These are substantial snapshots, not the full snapshots claimed
  by their row descriptions. F07's entitlement claim has the related omission
  described in CONF-02. Keep the real exact-error/fee/record rollback evidence;
  add the missing keyed observations rather than relabel it full coverage.
- Additional per-row limits are recorded in section 5: idempotent-revoke event
  checking, complete ownership event payloads, and postcondition rollback
  snapshots are not supplied merely by counting green test identities.

Governance simulation boundary: _fundSimulatedHolder (:991–1005) writes a
synthetic veCRV user point/epoch, including historical coordinates and zero
slope, to supply quorum; it does not obtain that power by a natural historical
holder deposit. Real newVote/vote/executeVote and real CallsScript/Agent/ACL
are exercised, and tallies/ACL/C-admin slots are not directly overwritten by
that helper. WORK-ORDER:27 permits disclosed funding/holder/time simulation.
Credit conditional transport, not authentic historical quorum or production
approval; do not call the permitted simulation itself a router exploit.

CONF-05 — public router documentation work is absent; two claims overreach

Authority: WORK-ORDER P4 and §4; RULING:14,43; SPEC:28,55,61,75,77,101,116.
All five required public files are byte-identical to ff18d92 AND f54ca9d.

- README.md:7 still leaves implementation/address selection jointly open;
  :30–37 omits GaugeControllerAdmin from layout. It lacks the implemented
  immutable C/D, fixed-controller execute and permanent-retirement disclosure.
- docs/ABI.md ends with the older core/adapters (:100–104); there is no separate
  full router constructor/function/error/event/encoding/lifecycle section.
- docs/CURVE-PROPOSAL.md:30–35 correctly retains independent DAO powers and
  supplied-weight L behavior, but omits immutable D, exact execute(bytes)
  ownership mediation, full raw-initial-weight capability of EVERY adder,
  selected operator-predeployment/S1–S3/conditional-unpause sequencing and
  irreversible-retirement/rollback limits. :37,41,45 remain prospective.
- docs/OPERATIONS.md:3 says the router is not already supplied. :9–17 do not
  provide the selected (C,D) predeployment and complete pre-apply rehearsal,
  distinct Agent/R execute ABIs, pre-seat rollback reset, no-reseat hazard or
  forced-donation stranding/no-guaranteed-recovery limits.
- docs/DEPLOYMENT-PINS.md:21,34 still describe prospective implementation;
  :25–30 omit the router constructor/binding entry. Generic W1/W2 obligations
  are not the separate R artifact/runtime-with-immutables/ABI/layout fields,
  explicit pending/retired/grant readbacks and full adder reconstruction or
  exact proposal/script-hash bindings required by P4.

Source NatSpec also needs precision:
  contracts/GaugeControllerAdmin.sol:28, “R is never a funds holder,” omits
  SPEC:101's unavoidable forced ETH/unsolicited token exception. Actual code
  has no intended custody; donations can remain stranded. O18 models this.
  :238–239 calls incumbency a precondition for “every mutating lane,” although
  grant intentionally works before seating (:135–143; SPEC:77).

Required closure is candidate-true product documentation, not an invented
production address or a claim of deployment/review/activation completion.
Preserve all existing FD/venue/float/kill/settlement limitations. Immutable D,
DAO-directed weight administration and delegated supplied-initial-weight
addition are intended powers; “no weight/emissions-affecting authority at all”
would be false. No economic amendment is authorized by these corrections.

CONF-06 — range-sensitive whitespace gate fails

WORK-ORDER:45 requires git diff --check. The candidate-range invocation
  git diff --check ff18d92 4ec0ac7
exited 2: test/router/RouterMocks.sol:452, new blank line at EOF. The builder's
clean-worktree-only git diff --check did not examine this committed addition.
Fresh forge fmt --check passed for both candidate and baseline. This is a
minor hygiene failure, not a Solidity security defect, but the stated G0 gate
has not passed for the relevant range. Do not reformat frozen old files.

4. Construction statements and falsifier receipts

Source and current native evidence, with evidence limitations kept distinct:

SP01 — immutable D is the only admin authority. onlyDao at R:99–102 gates
  grant/execute/typed ownership. O01/O04/O11/F06/F09 support the claim; M05/M06
  retained native reds discriminate grant authority and ownership mediation.
  The complete actor/selector matrix still needs CONF-04's corrections.
SP02 — non-D administration fails before effects. Authority modifier precedes
  retirement/lock; public reads are deliberately open. O04/O05/F06/F10 and
  fresh F10 NotDao(V) trace support current behavior; missing actor cells are
  not hidden by those successes.
SP03 — fixed destination, zero value, ordinary CALL. Complete ABI, AST/source,
  opcode inventory and O08/O18 support this. Independently reproduced M02
  reaches the sentinel, then fails exactly at its named assertion.
SP04 — fresh matched nomination, incumbent apply, correct successor and
  permanent retirement. R:247–276; O10–O16/F07/F08 and M03/M04/M06/M09 support
  code behavior. Independently reproduced M03 accepts stale future=R and fails
  the no-fresh-commit assertion. Required deployment rehearsal remains open.
SP05 — unchanged L's only C mutation route is the gated R add when active and
  incumbent. O05/O06/O19, I01–I05 and F02–F05 support this; independently
  reproduced M01 admits the outsider and fails AUTH_UNLISTED_REJECT.
SP06 — revoke blocks future additions, not old memberships/settlement or D's
  independent route. grant only changes one authorization key; O05/O20,
  I03/I05/I06, F04/F05/F07 support complementary parts. O20's two misdirected
  negative calls receive no authorization-gate credit; CONF-03 applies.
SP07 — no autonomous mint/ve/weight-setting path. The full surface has no such
  autonomous entry; only D executes arbitrary C administration. O06/O09,
  I01/I02/I05 and F03/F04/F06 show paid zero and supplied-weight delegation.
  A grant is raw-add capability, not a zero-weight-only credential.
SP08 — C is the registry and failure is synchronous/atomic. Typed reads, raw
  revert bubbling and ownership postconditions are present; O07/O09/O14,
  I03/I04/I06 and F01/F05 support them. M08/M10 retained native reds cover
  fabricated absence and swallowed failure. Full snapshot cells are partial.
SP09 — one lock, authorized cross-mutator reentry rejected, retirement effects
  before external apply. O17 exercises an authorized D shim and adder shim,
  all mutator reentries, finalizing Retired priority and rollback. M11 has a
  native named red. Reads have no lock; callback-time static-read coverage is
  not inferred from the mutation counter assertions.
SP10 — no intended funds path or balance-dependent authority. ABI/storage,
  source and O08/O18/I01/I02/I06 support it; unsolicited balances remain
  possible. No deposit/withdraw/rescue/sweep/approve API exists. The constructor
  value-negative helper is masked as CONF-03 describes; do not overclaim it.

Independent falsifiers: exact unmodified candidate tests, disposable router
source only. Each stage selected one full identity, not a no-match filter.
Native exits were 0 → 1 → 0, one test each, and every original source/test hash
was checked at each stage. Red is behavioral, not compilation failure.

M01 / O05
  Mutation: remove onlyDaoOrAdder from add_gauge, retain lock/incumbency.
  Red: AUTH_UNLISTED_REJECT.
  Trace: the outsider reaches C.add_gauge successfully before the unchanged
  test requires !ok. Restored source matches the candidate hash and passes.
M02 / O08
  Mutation: choose generic-call target from data[4:36], retaining other gates.
  Red: XPIN_DESTINATION_SENTINEL_UNTOUCHED.
  Trace: RouterSentinel.mark succeeds; markRecords()==1; the named require
  fails. This is destination broadening, NOT an added-overload ABI negative.
M03 / O10
  Mutation: _apply sources C.future_admin() and drops the local-freshness guard.
  Red: APPLY_WITHOUT_COMMIT_REJECT.
  Trace: stale future=R permits the otherwise forbidden apply. Restored local
  pending source/NoPendingTransfer guard passes the same identity.

Fresh receipts: review/routerconf/M01-*, M02-*, M03-* and exact M01.patch,
M02.patch, M03.patch. M01-restored-confirm additionally confirms the corrected
reviewer wrapper; the original native restored PASS was preserved.

Remaining retained native rows, checked against the authority's exact identity,
label, one-test green/red/green logs, reported child exits, and current R hash:
  M04 O14 COMMIT_RETURNS_SUCCESS
  M05 O04 ADMIN_NON_D_GRANT_REJECT
  M06 O11 EXECUTE_COMMIT_RECORDS_PENDING
  M07 O06 FORWARDED_WEIGHT
  M08 O07 READ_ABSENCE_REJECT pending (the named-label prefix is preserved)
  M09 O16 RETIRED_RESEAT_ADD_REJECT
  M10 O09 EXECUTE_BUBBLES_FAILURE
  M11 O17 LOCK_AUTHORIZED_CALLBACK_REJECT
Their raw evidence is review/routerplan-exec/receipts/falsifiers/. The retained
M01–M03 logs were checked too, but the independent replays above provide this
reviewer's fresh credit. Retained builder logs are not relabelled fresh runs.

5. Per-row positive/negative conformance ledger

Every identity below independently executed PASS in the new full runs. “Gap”
means that native identity's positive/negative/assertion cells do not establish
all the normative claims, NOT that its test failed or that the product is
necessarily defective. Full exact path:contract:signature inventories and
both set differences are bound in review/routerconf/verification.json. O rows
are in test/GaugeControllerAdmin.t.sol; I rows in
 test/GaugeControllerAdminIntegration.t.sol; F rows in
 test/fork/ForkGaugeControllerAdmin.t.sol, exposed once by the abstract-to-
concrete fork/GaugeControllerAdmin.t.sol wrapper.

O01 :37  Positive: explicit C/D, initial slots, deployer exclusion.
          Negative: exact constructor-address guards; value case masked by
          unfunded ValueLauncher. CTOR_EXPLICIT_PINS / CONF-03.
O02 :172 Positive: complete artifact ABI/method/layout; reviewer independently
          compares full objects for BOTH profiles. Negative: forbidden
          selectors/fallback. ABI_EXACT_SURFACE. The comment at :179–181
          promises an extcode/hash check not implemented in that body; do not
          substitute this test for the separate byte-binding gate.
O03 :212 Positive: grant/regrant/revoke values and exact expected events.
          Negative: bad keys and other-key independence. Final repeated-revoke
          call :244 has no event assertion; invalid-call logs are not captured.
          GRANT_ONLY_REQUESTED_KEY: partial event/no-effects cell.
O04 :272 Positive: D admin success controls. Negative: exact NotDao for exercised
          cells; outsider-grid/C-fixture gaps in CONF-04.
          ADMIN_NON_D_GRANT_REJECT has retained M05 named sensitivity.
O05 :340 Positive: D and granted adder add. Negative: outsider and revoked adder
          reach NotAdder with no membership/counter delta; no explicit log
          snapshot. AUTH_UNLISTED_REJECT has fresh M01 named sensitivity.
O06 :382 Positive: actual R sender, zero/nonzero weights, exact type readback.
          Negative: signed boundaries and duplicate preserve raw errors.
          FORWARDED_WEIGHT has retained M07 named sensitivity.
O07 :445 Positive: zero/nonzero canonical reads, changing type count, pre-seat/
          pending/retired reads. Negative: empty/nonempty absence and malformed
          response. READ_ABSENCE_REJECT has retained M08 named sensitivity.
O08 :507 Positive: C/sentinel/sender/value/storage-context checks. Negative:
          payload naming sentinel or R cannot divert. Returned bytes are
          discarded here; O09 supplies their independent witness.
          XPIN_DESTINATION_SENTINEL_UNTOUCHED has fresh M02 named sensitivity.
O09 :549 Positive: overloads, dynamic return bytes, exact Executed hashes and
          short-selector behavior. Negative: raw empty/nonempty/unknown errors.
          The type-weight call's success is checked, not its literal resulting
          weight. EXECUTE_BUBBLES_FAILURE has retained M10 named sensitivity.
O10 :687 Positive: fresh commit/apply. Negative: typed and execute stale apply,
          then repeat-after-retirement. APPLY_WITHOUT_COMMIT_REJECT has fresh
          M03 named sensitivity.
O11 :746 Positive: four typed/execute combinations and apply-event ordering.
          Negative: raw ownership cannot bypass local pending or retirement.
          Event counts/order do not fully assert successor payloads or both
          execute returns. EXECUTE_COMMIT_RECORDS_PENDING / retained M06.
O12 :862 Positive: canonical ownership encodings and ordinary payload.
          Negative: short/trailing/dirty ownership, exact error, state/call/log
          checks. OWNERSHIP_CANONICAL_DECODE is reached.
O13 :941 Positive: D/other nominee, replacement, unchanged incumbent and pending
          additions. Negative: forbidden nominees, non-D and nonexistent accept/
          cancel surface. COMMIT_REPLACES_PENDING is reached.
O14 :1006 Positive: ordinary commit/apply, matched pending. Negative: upstream
           reverts, false postconditions and artificial pending mismatch.
           Checks cover selected fields, not the promised full R/C/log equality
           and lock reuse after every failure. COMMIT_RETURNS_SUCCESS / M04.
O15 :1118 Positive: mock D handback and direct add/type/gauge-weight restored;
           old membership survives. Negative: raw D before handback and every
           retired mutator. HANDBACK_DIRECT_D_RESTORED is reached; not real-C
           replacement for F07's missing type/weight operations.
O16 :1185 Positive: distinct successor, pending cleared, read survival.
           Negative: all mutations and stale adder blocked after mock reseat;
           no revival API. RETIRED_RESEAT_ADD_REJECT / retained M09.
O17 :1248 Positive: bounded authorized D/adder callback, outer success/lock reuse.
           Negative: all mutator reentries, finalizing Retired priority,
           uncaught rollback. LOCK_AUTHORIZED_CALLBACK_REJECT / retained M11.
O18 :1372 Positive: forced-balance fixture and unsolicited token balance stranded,
           ordinary operation still works. Negative: no custody APIs/value
           probes, but constructor OutOfFunds and authorization masking/omitted
           getter probes limit the complete-value-cell claim. CONF-03.
O19 :1436 Positive: pre-seat grant/read, seated add/execute. Negative: unseated/
           displaced exact NotControllerAdmin for all four guarded lanes.
           INCUMBENT_REQUIRED is reached; source does not gate pre-seat grant.
O20 :1523 Positive: preserved membership/count/weights, D route, regrant.
           Negative: both revoked calls target holder contracts rather than R.
           REVOCATION_PRESERVES_MEMBERSHIP does not prove those negatives;
           fresh trace confirms dispatch failures. CONF-03.

I01 :165 Positive: payer and owner-paid exact-zero additions, actual L economics,
          nonzero default contrast. Negative/observation limits: “before”
          snapshot unused, no complete listing/log snapshot comparison.
          PAID_RAW_WEIGHT_ZERO is reached; complete matrix snapshot claim open.
I02 :212 Positive: paused DAO-free supplied/zero weights, no fee/escrow,
          nonowner rejected. Observation limits: “before” unused, no asserted
          validator-call count. DAO_FREE_SUPPLIED_WEIGHT is reached. Unchanged
          L source independently establishes the validator-free lane.
I03 :252 Positive: granted paid control and existing membership after revoke.
          Negative: both pregrant/revoked L lanes exact NotAdder(L), substantial
          world rollback; missing full approval/receipt/log cells, CONF-04.
          LISTER_AUTH_FRAME_AND_FULL_ROLLBACK is not a full-snapshot certificate.
I04 :338 Positive: synchronous membership control. Negative: raw failure,
          malformed membership and lying postcheck, exact error/record rollback;
          same snapshot limitations. LISTER_POSTCHECK_FULL_ROLLBACK / CONF-04.
I05 :400 Positive: independent D add/type operation with revoked L, no L liability.
          Negative: occupied-membership paid rejection and non-D execute.
          L is unpaused, and both restricted L lanes are not contrasted as
          required. DAO_ROUTE_NO_LISTER_DEPENDENCY / CONF-04.
I06 :465 Positive: actual old L checkpoint/confiscation after revoke+handback,
          exact transferred totals/liability and retained membership.
          Counters at :510 only observe add/mark attempts, not every possible
          static read; unchanged settlement source supplies the no-dependency
          argument. SETTLEMENT_NO_ROUTER_DEPENDENCY is reached.

F01 :312 Positive: fixed chain/header/runtime/roles and canonical C reads;
          both profile constructors observed. Negative: absence reverts and
          wrapper fails closed on RPC. Paris lifecycle absent, CONF-01.
F02 :402 Positive: incumbent-D commit/apply intermediate/final state and fresh L.
          Negative: pending-R self-apply and stale local apply rejected. The
          deliberate R impersonation is a negative fixture, not a callable
          production route. Interrupted cleanup not supplied, CONF-02.
F03 :461 Positive: real valid paid candidate, exact fee/count/type/zero weight,
          no R fee and counted C/R events. Negative: pre-absence asserted.
          Event topic counts do not assert complete NewGauge/GaugeAdded payloads.
F04 :503 Positive: paused DAO-free supplied weight and independent D adds,
          including post-revoke add. Negative/observation limit: no complete
          count delta or post-revocation independent ADMIN operation assertion.
F05 :546 Positive: genuine paid granted control; negative pregrant/revoked
          paid/DAO-free exact NotAdder(L), regrant control. Full rollback
          snapshot/log cells incomplete; no earlier committed member in the
          revoked subfixture despite its comment. CONF-04.
F06 :679 Positive: real raw overloads, type-count changes, type-weight readback
          and return-byte parity. Negative: raw D fails while R incumbent,
          outsider rejected, invalid type bubbles. Missing L/other-adder grid,
          literal changed-gauge-weight assertion and full event cells. CONF-04.
F07 :843 Positive: paid/revoke/replace-nominee/handback/direct add, memberships,
          retirement/read survival. Negative: stale local apply and selected
          retired routes. Direct type/weight, full entitlement observations and
          complete lifecycle/recovery missing. CONF-01/02/04.
F08 :918 Positive: usable successor router administers and returns C to D;
          original L endpoint does not migrate. Negative: original R and a
          deliberately reseated retired R cannot add. Do not perform reseating
          on mainnet; it is an explicit disposable negative.
F09 :1065 Positive: actual Voting/CallsScript/Agent install/grant then handback
           under disclosed synthetic quorum. Negative/observation limits:
           missing revoke action, complete governance bindings/events/executed
           readback and lifecycle operations. CONF-01/02/04.
F10 :1123 Positive: real wrapped commit vote. Negative: real direct-Voting
           NotDao(V) and outsider APP_AUTH_FAILED observed in fresh trace;
           witness accepts generic reverts and only unparameterized ACL reads.
           Required per-action caller/target/value/selector cell open, CONF-04.

6. Non-economic and lifecycle boundaries that remain valid

R's only storage is authorization/lifecycle/lock state. There is no duplicated
L listing record, fee liability, epoch, budget, registry mirror, token allowance
or escrow balance accounting. Zero imports and immutable C are not a claim
that a privileged D cannot influence C allocations: D retains controller
add/type/weight administration, and delegated adders can supply initial weight.
The paid-zero rule remains in unchanged L, not in an invented R clamp.

The full old byte comparison preserves the earlier economic surface rather
than relabelling this leg a new economic audit. I06 executes existing settlement
after revoke/handback. Revocation does not erase memberships or create a kill,
refund or migration. Successful handback installs the nominated successor,
clears local pending, permanently retires R and leaves reads available. A
retired R must never be reseated. There is no guaranteed rescue if governance
chooses an unusable successor or strands raw C administration.

Unsolicited ETH/ERC20 can arrive and remain stranded. They do not create
privileges or block operations. “No intended custody or money-handling path”
is supported; “balance zero forever” is not. No code change was made to evade
that EVM limitation.

7. Receipt custody, binding and disposition

Owner-held evidence directory:
  /home/winny/curve-gauge-lister/review/routerconf/

Principal reproducible records:
  run.py, fork_retry.py, verify.py, seal.py
  context.json, fork-blast-context.json
  candidate-*/base-* build/config/discovery receipts
  offline.*, offline-unreachable.*
  fork-cold.* (failed PublicNode attempt, retained)
  fork-blast-cold.*, fork-blast-warm.*, fork-blast-unreachable.*
  F01/F07/F09/F10-trace.*, O01/O20/I05-trace.*
  M01/M02/M03 pristine/red/restored receipts, source pins and exact patches
  payload-selftest.*, candidate-diff-check.*, candidate-fmt.*, base-fmt.*
  verification.json (all artifact comparisons and exact full test inventories)
  SUMMARY.json (independent falsifier and trace verification)
  BINDING.json (hashes/sizes for native evidence, scripts, authority and retained
                falsifier receipts; this report/publication state excluded)

BINDING.json SHA-256:
  8e6a5fbf99860fb1eaed49d2652191e2cdceed7d11248fd19a896f81cb5ba04c

The census ledger's native PASS claims are confirmed as identity counts.
Its stronger implication of complete matrix acceptance is not. Compile,
manifest equality, mutation sensitivity and totals cannot waive the named
lifecycle, assertion and documentation gaps. RULING:43 explicitly keeps missing
evidence on HOLD.

Disposition: return for a bounded builder correction of CONF-01–CONF-06 and
all partial cells identified above, followed by fresh affected gates and exact
candidate binding. Preserve the certified old source/tests/economics and the
normative authority; do not solve gaps with relaxed assertions, quota changes
or fabricated deployment inputs. No ROUTER ACCEPTED certificate, blind-fleet
release, production installation or PAO activation follows from this review.
