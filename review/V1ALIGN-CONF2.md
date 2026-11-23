Verdict: NO-BOUNTY V1 ACCEPTED — deployment-pending.

V1ALIGN-CONF2 — bounded closure of VC-01 and VC-02

Binding and scope

Reviewed candidate: 2c7c1f01c11bd7231887452f8e6d4a80ccd812b5.
Review checkout: main at 58158ed27585a96b9d51588f2033759734b6b805; its only committed delta from the candidate is plans/V1ALIGN-CONF2-BRIEF.md.
Product/test predecessor: b37e5333a07050e7ea87da98712c0edc483673fa.

VC-01 is CLOSED by independent reproduction at its original required frame. VC-02 is CLOSED by an explicit, applied authority amendment accepting the offset-1 H+1 guard-level sensitivity. No bounded conformance item remains open. This supersedes the two-item HOLD in review/V1ALIGN-CONF.md; that report and the executor's existing receipts remain unchanged.

This is the requested closure leg, not a new whole-product audit or deployment approval. The previously credited product, ABI/layout, preservation, documentation, size and fork findings carry forward because contracts/, test/, fork/, scripts/ and foundry.toml have an empty diff against b37e533. The supplied orchestrator verification of 77/77 offline and 13/13 fork is consistent with review/v1align-execution/gates/v1align-fix-final-gates.txt. This reviewer additionally reran the exact 77-identity offline suite; no fork or other network gate was rerun in this leg.

1. VC-01 — CREDIT, original witness authority satisfied

Authority: plans/V1ALIGN-WITNESSES.md:74 and plans/V1ALIGN-FIX-BRIEF.md:10-19. Selected identity:
  test/Settlement.t.sol:SettlementTest:test_KillAtEachReleaseCount()

Independent execution used a fresh candidate archive, not the executor's disposable tree or its hash booleans. The exact F-NB-SPLIT-R2 mutation from vc01_falsifiers.py was reproduced in contracts/CurveGaugeLister.sol only:
  - Send amount/2 to FD and amount-amount/2 to the inert 0x000000000000000000000000000000000000dEaD sink.
  - Align only the FD-credit postcheck to fdBefore+amount/2; retain its mismatch rejection.

The aligned FD-credit predicate is a changed predicate, not an assertion that both original balance checks stayed literal. This coherent FD-credit-side corruption is within the fix brief's authorization. The gross lister-debit predicate, earlier destination/cursor guards, gross liability debit, terminal effect, mandatory checkpoint, cursor/accounted-custody postconditions and events are unchanged. The exact diff changes only those transfer/FD-credit sites. No test, mock, helper, dependency or shipping product was changed. VC-01 requires no witness amendment.

Native Forge exits, pristine / mutant / restored: 0 / 1 / 0. Each run selects exactly one compiled identity with zero skips. Both green stages report 1 passed, 0 failed. Red reports:
  [FAIL: FD got exactly the unreleased] test_KillAtEachReleaseCount()

Decisive fresh trace, review/v1align-conf2/receipts.tar.gz member receipts/vc01.red.stdout:
  :148       confiscate enters for the first, zero-release-count listing.
  :161-164   FD receives 5000000000000000000000; the sink receives the other half.
  :165-168   lister custody reads zero; FD custody reads 5000000000000000000000.
  :169-178   mandatory checkpoint completes; cursor and accounted-custody reads satisfy the unchanged postconditions.
  :179-181   events are emitted in the call trace; confiscate returns gross 10000000000000000000000.
  :182-183   the test reads actual FD custody, 5000000000000000000000.
  :184       [Revert] FD got exactly the unreleased

The :184 label maps exactly to test/Settlement.t.sol:2341, after the returned-seizure assertion at :2340. There is no ConfiscationDeltaMismatch in the red output. The earlier listing gauge_types revert displayed in Forge's generic backtrace is not the decisive failure; the actual terminal call trace above is. This credits the required FD-delta frame, not merely the test name. The red aborts at n=0; it is not five separately executed mutant cells. The unchanged loop passes pristine/restored across release counts 0..4. Traced events in the reverting test are not persistent production receipts.

The historical half-transfer-only and F-NB-SPLIT-LITERAL guard-level reds remain historical guard-level evidence. They have not been relabeled as reaching :2341.

2. VC-02 — ACCEPT amendment A, guard-level sensitivity only

Request read: review/v1align-execution/gates/AMENDMENT-REQUEST-VC02.md, especially :22-78. Both historical archives' member checksum lists were verified, nine listed members each. The stored horizon red confirms cursor 1818633601, warp 1830729601 and the failed expectRevert; its decisive frame is vc02/test_AuditM01_AccountingHorizonIncludesPartialWeekEdges.red.log:1081. The named near-end cursor 1837382399 is absent from that red.

I also independently reproduced the uniform epochStart(t)->t mutation at contracts/CurveGaugeLister.sol:767, with exact final test bytes and native exits 0 / 1 / 0. Selected identity:
  test/Settlement.t.sol:SettlementTest:test_AuditM01_AccountingHorizonIncludesPartialWeekEdges()

Fresh trace, bundle member receipts/vc02.red.stdout:
  :939        setLastTokenTime(1818633601), the offset-1 cursor.
  :1039       VM::warp(1830729601), its floored H+1.
  :1045       VM::expectRevert(DistributorUnusable()).
  :1047-1078  mutant confiscation transfers/accounts the full fee and returns normally.
  :1079       [Revert] next call did not revert as expected

This is the expected-revert pair at test/Settlement.t.sol:2083-2084, not a setup failure. The first partial-week H+1 cell detects the lost week floor: the mutant permits confiscation beyond the safe accounting horizon. It proves H+1 partial-week horizon guard liveness. It does not prove executed WEEK-1 mutant coverage or a reached allocation-loss assertion.

Independent trace attribution (cursor-setting frames; each successful full cell has its H-1/H/H+1 probes):
  Offset    Cursor       Pristine   Mutant   Restored
  0         1800489600    3          3        3
  1         1818633601    3          3        3
  WEEK-1    1837382399    3          0        3

The offset-1 red's third probe aborts. All three near-end probe warps, 1848873599/1848873600/1848873601, are absent from red and each occurs once in both green stages. Full attribution, including line numbers, is in receipts/verification.json.

Reachability ruling: test/Settlement.t.sol:2023-2040 is one unparameterized compiled function, with offsets [0,1,WEEK-1] executed in order. The fresh native inventory and compiler methodIdentifiers expose only that whole-function identity, not selectable loop branches. All three fresh per-offset selectors returned exit 0 with "No tests found" and no execution; these are not three green tests. The no-match probes corroborate the source/inventory proof, rather than purporting to exhaust all regexes. Within frozen tests, function-level selection and the uniform authorized mutation, no reachable per-offset alternative skips the preceding failure. A split/reordered witness or a mutation conditional on the cursor would require different authority.

Approved and applied amendment:
  Original required cell: H+1 near-end cursor.
  Replacement: H+1 partial-week horizon guard liveness at cursor offset 1 (guard-level sensitivity); WEEK-1 mutant cell is not reached under frozen test selection.

The normative row is amended at plans/V1ALIGN-WITNESSES.md:76, with the bounded ruling at :83-91 in the same commit as this report. All pristine H-1/H/H+1 obligations at all three offsets remain binding, as do the production floored bound, frozen tests, compiled identity, inventory and other falsifiers. This is an evidence-scope amendment, not a production weakening or retrospective claim that near-end mutant execution occurred. The request remains unchanged as submitted history.

3. Evidence custody, integrity and verification

Fresh execution root:
  /home/winny/.hermes/profiles/gpt6-astra-auditor/cache/scratch/v1align-conf2-msvv4opo
Durable, committed bundle:
  review/v1align-conf2/receipts.tar.gz
SHA-256:
  16ebc45950fc932c5ee13b116a165bd06fa0a39ca89eac5f0de64ef622955a28

The bundle has 58 verified file members, including the exact candidate input archive, raw stdout/stderr, native argv/cwd/exits, actual-copy input hashes, exact mutant diffs, independent attribution/inventory verification, runner/verifier scripts, and authority before/after/diff/ruling records. receipt-manifest.json hashes every other member. Archive readback verified every member against its source bytes. REPLAY.txt distinguishes the runner's successful validation exit from the native Forge child's intentional red exit.

Each case starts from a separate candidate copy with no out/cache. Both mutations exactly match the committed generator edits; both patches were reconstructed with patch --fuzz=0. All 43 candidate input files were independently bound to Git. All 19 test/fork files were checked before and after every stage in the actual execution copy. Only contracts/CurveGaugeLister.sol differs during red/probe stages; both complete input trees are byte-identical to the candidate after restoration.

Historical pinning limitation, not relied upon for closure: vc01_falsifiers.py:87-93,114-118 and vc02_falsifiers.py:69-75,182-184 construct absolute candidate paths and then use os.path.join(d,p), which discards disposable directory d when p is absolute. The archived vc01/hashes.txt confirms absolute candidate paths. VC-02's attribution supplies only an after-restore boolean, not the per-stage SHA pins claimed by the request. Those historical scripts/receipts remain untouched. This review remedies the evidentiary gap through its own relative-path, actual-copy before/after snapshots for BOTH fresh reproductions; no product defect or remaining closure dependency follows from relying on those new verified receipts instead.

Toolchain: Forge 1.7.1, commit 4072e48705af9d93e3c0f6e29e93b5e9a40caed8; compiler metadata 0.8.30+commit.73712a01. Resolved default settings: optimizer enabled, 200 runs, no viaIR, Paris, test=test, out=out. FOUNDRY_*/DAPP_* overrides and MAINNET_RPC_URL were removed for the recorded commands, then the default profile was explicitly selected. Compiled witness selectors: babf416f and 2dd16515 respectively.

Exact selected command form in each disposable copy:
  forge test --offline --match-path test/Settlement.t.sol --match-contract '^SettlementTest$' --match-test '^<exact-name>\(\)$' -vvvv
The JSON records contain the complete argv, not the placeholder above.

Additional fresh checks:
  forge test --offline -vvv: exit 0; 77 passed, 0 failed, 0 skipped. Executed file/contract/signature identities equal the native list and the authoritative live inventory, with no duplicates.
  forge fmt --check: exit 0.
  Independent receipts/inventory/patch verification: exit 0.
  Authority amendment reconstruction: exit 0, byte-equal to the approved row replacement plus appended section only.
  git diff --check: exit 0.
  Product/test/script/config diff against b37e533: empty.
  Existing execution receipts and prior review diff against 2c7c1f0: empty.

The supplemental offline compilation reports five existing warnings: two unused try/catch parameters and three restrictive-mutability suggestions. They remain visible in the raw log; no warning-free build is claimed. No compiler, optimizer, dependency or test-runtime waiver was used.

Authority serialization hashes:
  Before: 9c61d7996b6f2023bf2ee29064df0f987515aec5df1ca49333f5f079f59e1ce5
  After:  f41b8487b1fe611106fcc12c80e9b0189d1ebcaa96560ee2636dfdc3599cd882
  Diff:   f9666bab943827a6ae1d18b1cfe83632144bbdfe8eeaa9bf4f072bd0faf3943f

4. Certificate and deployment remainder

NO-BOUNTY V1 ACCEPTED for candidate 2c7c1f01c11bd7231887452f8e6d4a80ccd812b5, under the explicitly amended witness authority. VC-01 and VC-02 are closed; no bounded review remainder.

Deployment remains pending. Current pin/source/role/validator-policy verification, actual controller integration/seating, authorized adapter binding and ownership readbacks, committed ETH float, real venue/destination readiness and delivery, a safe FD accounting/cooldown window, operational staffing and a funded trial remain open as recorded in review/V1ALIGN-CONF.md:175 and plans/V1ALIGN-PLAN.md:138. Historical fork impersonations do not close these obligations. No broadcast, deployment, production authorization or custody operation was performed.
