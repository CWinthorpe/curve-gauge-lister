ROUTERCONF3 — bounded residual and provisioning re-check

Verdict: NONCONFORMS / HOLD
Candidate: fb663e7c912260635d53e3e14753858869f8ef4e
Candidate Git tree: 17f174414cef0066d63d6f71688494bf646ecf3d
Review execution date: 2026-11-25 UTC

ROUTER ACCEPTED is NOT issued. The blind router-surface fleet round is not
released by this review; scheduling remains with the orchestrator.

F11's selected-Paris tail, O18's apply-value witness, F09's exact event
payloads, routerfix4 provisioning and the exact 103/25 census are verified.
F09's implementation/runtime binding remains partial. Separately, the prior
CONF-04(a),(c)–(h) dispositions were not repaired or retired. These are
conformance-evidence limits, not newly demonstrated exploitable defects.

Scope and prior-disposition reconciliation

This is the requested F11/O18/F09/provisioning/census re-check, not a new
router-security or economic audit. The controlling comparisons are
review/ROUTERCONF.md:182–379 and review/ROUTERCONF2.md:65–284, limited to the
requested repairs and preservation of their existing dispositions.

ROUTERCONF2 left three DISPOSITION IDs open: CONF-01, CONF-03 and CONF-04.
It did not reduce CONF-04 to subsection (b). Its §5(a),(c)–(h) remain explicit
at review/ROUTERCONF2.md:187–206,218–280. The repair ledger itself confirms
this at review/routerfix2/receipts/CENSUS-LEDGER.md:99–102. A repair brief
restricted to three cells is not evidence that the other cells passed.
The unchanged-source reconciliation below preserves them without adding
new obligations. F09's remaining graph cell independently prevents even
the requested narrow all-cells-closed conclusion.

Disposition summary

  CONF-01 / F11       CLOSED for the selected-instance restored-direct tail.
  CONF-03 / O18       CLOSED; native rejection and named payable-mutant red.
  CONF-04(b) / F09    PARTIAL: events/registry routing repaired; exact
                     implementation/runtime graph binding still incomplete.
  Provisioning       CLOSED: documented commands independently reproduced.
  Census             PASS: exact 103 default / 25 fork set equality.
  Prior CONF-04      (a),(c)–(h) carried unchanged, not silently waived.
  Prior closed IDs   CONF-02, public-document CONF-05 and CONF-06 stay closed.

1. Fresh execution and provisioning

An independent fresh clone of fb663e7 was created under this reviewer's
scratch directory. It had no out/cache/out-fork/cache-fork or owner-held
plans. HOME and XDG data/config/cache were fresh; only the installed solc
0.8.30 executable was seeded. Its SHA-256 was
54f48274e5ec8a58b378f07c226fa1e25801526b6b0d16129f3a14a18efe72cd.
Forge was 1.7.1, commit 4072e48705af9d93e3c0f6e29e93b5e9a40caed8.
Resolved settings retained optimizer/200, viaIR=false, default Paris and
fork Cancun. No profile or environment setting supplied storageLayout.

README.md:58–63 was extracted and executed VERBATIM, in order:
  forge fmt --check
  rm -rf out cache
  forge build --offline --sizes --extra-output storageLayout
  forge test --offline
  FOUNDRY_PROFILE=fork forge build --offline --sizes --extra-output storageLayout
  MAINNET_RPC_URL=https://eth-mainnet.public.blastapi.io scripts/test-fork.sh

All six commands exited 0. Native default results were 103 passed, zero
failed/skipped. Native fork results were 25 passed, zero failed/skipped.
This was the first fork execution in the isolated HOME/XDG state. The
unchanged wrapper verified chain 1, block 26401019, timestamp 1794512471,
hash 0x55810b079923a14fb97ad548f5024f65530dbc4fb2357a38f41e13b3d27cb6d3.
The default repeat with MAINNET_RPC_URL=http://127.0.0.1:1 returned the same
103 successes. A warm fork JSON repeat returned the same 25 successes.
Focused F11/F09/O18 -vvvv runs also passed. No fresh unreachable-fork
preflight rerun or unrelated falsifier replay is claimed in this leg.

Independent BEFORE control: a separate clean clone at
c151881090b41a5e504192dc50290101d82743c1 ran the first three OLD README
commands verbatim. fmt/build exited 0; test exited 1 with exactly
  [FAIL: ABI_EXACT_SURFACE storage count] test_CompiledAbiStorageAndNoFallback()
and 102 passed / 1 failed / 0 skipped. Its artifact had no storageLayout.
The corrected clone's default and fork artifacts have the four exact
manifest storage entries and types; complete ABI objects and method IDs
also match. The embedded compact manifest remains authority-equal.

Thus ROUTERFIX3-BLOCKED's causal diagnosis and refusal to weaken the test
were correct. The relevant comparison code remains at
 test/router/RouterHarness.sol:249–325; the provisioning correction feeds
that same comparison rather than changing its expected values.

The active owner-held review/routerfix4/run_gates.py:81–105,129–153 executes
each clone's README block directly. Its AFTER builds therefore use the G1
canonical form for both profiles; :180–185 enforces the README-only delta.
review/routerfix2/run_gates.py:98–101 still contains the historical plain
builds. It is an archived runner, not the corrected entrypoint; routerfix4
explicitly preserves prior runners as historical receipts (:8–10). It must
not be presented as a newly corrected clean-output acceptance command.

2. F11 — selected Paris repetition closed, literals correctly bounded

Source: test/fork/ForkGaugeControllerAdmin.t.sol:1834–2057.
The existing selected-artifact binding still compares raw CREATE against
deployCode of the default out/ artifact, full immutable-patched runtime,
C/D getters/literals and distinct Cancun bytes. Fresh artifacts confirm
Paris runtime 4,786 bytes and initcode with arguments 5,396; the Cancun
runtime remains 4,683 bytes. F11 executes its lifecycle on the Paris R.

The new tail at :1979–2006 genuinely follows handback and the restored
raw add_gauge. Fresh F11-trace.stdout:1238–1293 records:
  raw D add_gauge(...,0,5), exact weight readback 5;
  raw D add_type("f11-selected-restored-type"), count 14 -> 15;
  raw D change_type_weight(14,4242), exact readback 4242;
  raw D change_gauge_weight(postHandback,77), exact readback 77;
  retired selected R read-through returning count 15 and membership type 0.
These are the missing ROUTERCONF2:90–98 selected-instance operations, not
borrowed credit from F07's Cancun instance.

The exact required literals appear in executable assertions, not only
comments:
  :2051–2054  uint160(C) = 270125199945504599111523101509100263416079599291
  :1974–1978  uint32(commit_transfer_ownership(address)) = 1799625280
Both were independently recomputed from the canonical address and installed
cast selector encoding. No shift is applied in these assertions.

Boundary: those values originated in ROUTERCONF2's separate F10 ACL finding
(:194–197). Correctly citing/asserting them in F11 does NOT repair F10's
still-shifted permission context or replace an Agent.canPerform call.

3. O18 — genuinely nonpayable apply, independent named sensitivity

Source: test/GaugeControllerAdmin.t.sol:1708–1735.
The fresh seated fa fixture commits a valid successor, then funds the
ACTUAL caller fa.dao with 2 wei (:1718) and checks solvency before sending
1 wei to R. The same-caller zero-value apply remains the positive control.

Fresh O18-trace.stdout:228–250 and O18-pristine.stdout:228–250 show deal,
prank, apply_transfer_ownership{value:1} entering R and reverting with empty
data, retired=false, then zero-value apply reaching C and retired=true.
There is no OutOfFunds anywhere in the focused native trace.

Independent mutation used a separate exact candidate archive and only
inserted payable into R.apply_transfer_ownership at contract line 230.
All test/helper bytes remained unchanged. Canonical builds succeeded.
Native selected-test exits were pristine 0, mutant 1, restored 0; each ran
exactly test_NonpayableAndUnsolicitedDonations(). The mutant's :232–243
successfully reaches C.apply, emits ControllerTransferApplied and returns,
then fails at precisely
  FUNDS_NO_INTENDED_CUSTODY apply value lane
(the require at test/GaugeControllerAdmin.t.sol:1726).
This is a compiled behavioral red at the required assertion, not a build,
ABI, authorization or insolvency failure. Full archive source restoration
and the original router hash were verified.

4. F09 — event closure credited; exact remaining graph cell

Closed event/payload portion

Source: test/fork/ForkGaugeControllerAdmin.t.sol:378–413,493–607,
1518–1626. The new comparisons require the full emitter, complete topics
array and exact data bytes, not just topic counts. Fresh recorded-log
arrays at F09-trace.stdout:765 and :1148 were independently parsed and
compared against the authority encoder's actual simulated R/L inputs.
Verified for BOTH three-action scripts:
  every Agent Execute sender/target/zero value/complete inner calldata;
  ScriptResult executor/complete script/empty input/empty return data;
  three complete LogScriptCall events with correct sender/src/dst;
  exact C CommitOwnership/ApplyOwnership successor payloads;
  exact R AdderSet key/bool, plus handback Committed/Applied successor topics.
The deployed Agent's unpadded trailing Execute bytes were compared exactly,
not silently replaced by modern padded encoding. The full native scripts
also equal the authority encoder, and executed-vote readback is retained.

Decoded script SHA-256 values, local simulation only:
  seating  3a5da3734fff836ff3b41aea17fbe53be196072071a9c5a599446224346b6948
  handback ba16b88c244a4f8c4d297b31fecc41d4a4e4f4429f7bfa90269c4768195fe36b

Improved graph observations also receive credit: shared kernel and raw
kernel/appId slots; ACL reverse link; base-namespace lookups; kernel base
slot; Voting runner -> kernel app namespace -> registry equality; executor
type; and executor resolution for each complete actual script. See
:426–491,:1561–1565,:1604–1608 and fresh trace :31–98,:774–794,:1157–1177.

Remaining CONF-04(b), within the original wording

ROUTERCONF2:208–216 requires the full implementation/RUNTIME graph, not
merely graph existence. DEPLOYMENT:16 and WITNESSES F09:262 expressly retain
source/runtime binding. At :467–478 the four base lookups and kernel base
are checked only for nonempty code (and selected proxy inequality). There
is no expected implementation-identity or full-runtime hash/byte comparison
for Voting, Agent, their proxies, Kernel, ACL, registry or CallsScript.
The new helper does not bind those runtimes to the reviewed source inputs.

There is also a concrete unbound graph edge: :470 reads the registry's
KERNEL base registration, but the actual registry proxy uses its OWN pinned
implementation pointer, not that lookup. Fresh read-only implementation()
and runtime-disassembly evidence identifies the registry as the 858-byte
pinned proxy. Its implementation dispatch follows 0x017b -> 0x01e3 ->
0x02b9 and SLOADs
  0xdee64df20d65e53d7f51cb6ab6d921a0a6a638a91e942e1d8d02df28e31c038e
before returning. The storage read and implementation() both return
  0xBF1Ce0Bc4EdaAD8e576b3b55e19c4C15Cf6999eb.
That DOES agree with the kernel base in this execution. But F09 never
reads/asserts that actual pointer or compares it with implRegistry. The
proxy's kernel/appId getters and successful executor lookup do not assert
its implementation identity. The Agent/Voting/ACL proxy runtimes, unlike
the registry, do use the kernel base lookup; their collected runtime bytes
are equal to each other, not to the registry proxy.

Required closure remains the original graph cell: bind actual proxy
resolution (including this pinned registry edge) and complete runtime
identities to the reviewed fixed-pin inputs, retaining the now-correct
registry relation, executor resolutions, scripts and events. No new mutant,
production address selection or mainnet action is required by this review.
The observed implementations are real and consistent; this is missing
load-bearing identity evidence, not a demonstrated bad deployed graph.

5. Preservation and exact census

The full committed diffs were inspected, including historical report paths:
  Since 3a2a260: only README.md and the two named unit/fork witness files.
  c151881: only the O18 funding insertion and F09/F11 test/helper changes.
  fb663e7: README.md ONLY; no test, contract, script or configuration edits.
  Since 21f4846: the above plus the prior review/ROUTERCONF2.md report.
  Since 4ec0ac7: the previously reviewed five public-document and five
  router-test/helper paths, plus review/ROUTERCONF.md and ROUTERCONF2.md.
Full path lists and unchanged carried-source ranges are in verification.json.
There is no contracts/, foundry.toml, scripts/ or fork/ delta since 4ec0ac7.
All 46 baseline contract/test/fork/script/config file hashes still match the
certified BASELINE.json. The fresh execution clone remained byte-unchanged.

Frozen SHA-256 bindings:
  GaugeControllerAdmin.sol
    a9627151440407dcfad188f0b08cef3a2d37f446020acb6209b7ea15461ecdbc
  ROUTERPLAN-ABI.json
    e85e45116d2301993ce5736358effbe62939e5c8a6397a662f6df522dff78d6d
  foundry.toml
    f8ea5f0f3abfcb9c9987ef508cf5565cd840a5492f21960d7654c3ddbc79fac5
The owner-held manifest matches BOTH previous review seals, whose full
binding-file hashes were verified against their published reports. The
compiled router ABI/method/layout comparisons were freshly repeated for
both profiles. Earlier all-old-artifact equality is preserved by the source
and configuration freeze, not relabelled a new full artifact-fleet rebuild.

Census is independently derived, not a quota or an inherited ledger total:
  default: 77 baseline + 26 router = 103;
  fork:    13 baseline + 12 router = 25.
BASELINE.json union review/routerfix/receipts/CENSUS-LEDGER.md equals each
fresh native discovery set, README native PASS set and repeated JSON PASS
set. All differences and duplicate sets are empty; no failure/skip or new
identity. routerfix2's three-row ledger is a delta ledger, not the entire
census; its unchanged-set claim is confirmed. Focused traces and mutants
are not additional identities.

Fresh git diff --check ff18d92 fb663e7, 4ec0ac7 fb663e7 and
21f4846 fb663e7 all exited 0. Fresh README forge fmt --check exited 0.

6. Carried prior cells — exact scope, no new audit expansion

The following original CONF-04 cells are source-identical to the reviewed
21f4846 regions. verification.json records old/current line mappings and
hash equality. They are not erased by the new PASS counts or by excluding
them from the repair executor's edit budget:

  (a) F10: test/fork/ForkGaugeControllerAdmin.t.sol:1730–1741 still calls
      ACL.hasPermission and left-shifts target AND selector by eight.
      Required: real Agent.canPerform with unshifted per-action triples.
      F11's new constant checks do not change this call path.
  (c) O04 :337–348 in test/GaugeControllerAdmin.t.sol and F06 :1129–1139 in
      test/fork/ForkGaugeControllerAdmin.t.sol still omit nested execute(apply)
      from the otherwise repaired actor/selector grids.
  (d) O11, test/GaugeControllerAdmin.t.sol:820–960: successful execute/execute
      return values remain discarded; execute-commit/typed-apply log
      recording still starts after commit. Preserve the other repaired cases.
  (e) O14, test/GaugeControllerAdmin.t.sol:1132–1305: full grant/membership/
      type/weight and relevant-log rollback, plus actual lock reuse after
      EVERY failure, remain absent as specified in ROUTERCONF2:233–240.
  (f) I03/I04: test/GaugeControllerAdminIntegration.t.sol is wholly unchanged
      since 21f4846. The missing keyed/chronological adapter receipt and
      approval, R lifecycle/grant and complete committed-log cells at
      ROUTERCONF2:242–248 remain.
  (g) F05, test/fork/ForkGaugeControllerAdmin.t.sol:886–977: selected-candidate
      keyed full rollback and earlier-committed-member observation remain
      incomplete, exactly as ROUTERCONF2:250–258 records.
  (h) ROUTERCONF2:260–280 per-row limits remain: O05 negative log delta;
      O09 literal type-weight result; I01 complete listing/log comparison;
      I02 validator-call non-occurrence; F03 full NewGauge/GaugeAdded payloads;
      F04 complete count delta and post-revoke independent ADMIN operation;
      F06 literal gauge-weight result and full event payload. Current fork
      ranges are F03 :778–790, F04 :808–844 and F06 :1050–1097; the relevant
      unit/integration ranges retain their previous line numbers.

This preserves prior dispositions, rather than reopening closed CONF-02,
CONF-05 or CONF-06 or asserting new product defects. An explicit authority
disposition could change what is owed; this candidate supplies no repair
or closure evidence for these retained cells and its own delta ledger says
that they remain open.

7. Evidence custody and final disposition

Owner-local evidence:
  /home/winny/curve-gauge-lister/review/routerconf3/
Principal records: run.py, verify.py, graph_reads.py, seal.py, context.json,
verification.json, receipt-notes.txt, source-preservation.json,
mutation-preservation.json, O18-payable.patch, fresh profile artifacts,
readme-*/before-readme-* native receipts, discovery/repeat receipts,
F11/F09/O18 traces, O18 pristine/mutant/restored receipts and graph-* reads.
The BEFORE comparison and temporary mutant are explicitly distinguished
from candidate failures in receipt-notes.txt. No owner-held package or
scratch output is added to the public commit; only this report is authorized.

BINDING.json covers 234 evidence/input files; every bound file was checked.
Its SHA-256 is
  400be9075c089dc87128ed93c3649b2306a86f387345a88c321dfa679756287f
The report and publication metadata are excluded to avoid hash recursion.

Disposition: retain the verified F11/O18/event/provisioning/census credit;
return the exact F09 graph remainder and reconcile the explicitly carried
CONF-04 cells. No ROUTER ACCEPTED certificate or blind-fleet release is
issued. No signing, broadcast, production installation, activation approval,
new economic audit or mainnet state change occurred.
