R3CONFIRM — bounded independent confirmation

Verdict: ADMISSION PACKAGE CONFIRMED; LEAN CONVERGED — ACTIVATION OBLIGATIONS OPEN.
Candidate: b36281c9062a7222da13d5e672ba94d14fd7e0be (main at intake).
Baseline: d88d633c64fde7b3f37e29d846f744747186a688.
Execution window: 2026-11-23T22:50:57Z–22:52:48Z; subsequent receipt checks completed in this review.
Scope: the admitted C03/C05/C07/C13/C15 package and its existing gates only.

All required confirmation cells pass. The two predecessor HOLDs are closed below.
No broader round, executable refactor, new witness or sensitivity expansion was performed.
The named report commit is a publication-only child, not a substitute for this exact reviewed candidate.

1. Bounded disposition

C03-PUBLICATION-STALE — CLOSED

README.md:20,33 now states that the authority/evidence carriers are owner-held, producible on demand and not published in the source tree. Owner control, non-approval and ACTIVATION-OPEN qualifications remain. Commit b36281c changes only these two C03 publication statements. It does not republish the bulk package.

The same AUTH-EVIDENCE-INDEX.md:222-283 binds b36281c9062a7222da13d5e672ba94d14fd7e0be, the corrected README digest, inherited source/build evidence, current manifests and custody distinction. Its prior 26,111-byte / 219-line index from 2d0bc2f remains an exact prefix. All 52 other product paths are byte-identical to a9de6ff; all 33 explicit source/receipt digest rows in the two addenda verify against their correctly scoped candidates or retained receipts. Owner approval remains ABSENT / OPEN at :290-302.

The tree contains 53 product/test/doc/configuration files plus the previously authorized review/R3CONFIRM.md publication exception. No other review/ or plans/ path is tracked. That historical report was added by d15d168 and is unchanged at this candidate; it is explicitly accounted for in the net hunk ledger, not silently excluded.

G4-RPC-ARCHIVE — CLOSED / required cold fork gate PASS

The unchanged wrapper was invoked exactly once in this pass, without filters, using the documented archive-capable endpoint override https://eth-mainnet.public.blastapi.io and an isolated cold HOME. Before invocation that HOME contained only the copied installed Solidity 0.8.30 compiler; no RPC cache or prior Foundry configuration was copied. XDG locations were isolated as well. Build artifacts were fresh same-session artifacts, not historical fork-state caches. The pinned RPC cache first appeared during this invocation. No warm wrapper repeat was performed in this pass.

Pinned-header preflight passed: chain 1, block 26401019, hash 0x55810b079923a14fb97ad548f5024f65530dbc4fb2357a38f41e13b3d27cb6d3, timestamp 1794512471. The endpoint override changed no pin, source, assertion or expectation.

Native wrapper exit: 0. Native result: 13 passed, 0 failed, 0 skipped across 5 suites. Executed full file:contract:signature identities equal discovery and BINDING.json exactly, without duplicates. Native suite wall time: 72.34s.

Evidence: owner-local review/r3confirm2/candidate-cold-fork-wrapper.stderr:1-3, stdout:3-53 and candidate-cold-fork-wrapper.run.json. Exact identities are retained in census-comparison.json; isolation and pre/post cache inventories are in environment.json.

The predecessor's publicnode failure remains preserved in review/r3confirm/ and the builder's hash-bound copies; it is not rewritten as a pass. Historical builder cold/warm receipts remain historical. This current independent cold result supplies the required acceptance. No repin, mocks, skipped identities, source/assertion change, silent wrapper retry, cache-warm substitution or transport-green was used.

2. Claim-versus-work-order fidelity

Authoritative boundaries: review/r3gate/RULING.md:26-45 and plans/R3GATE-WORK-ORDER.md:8-55,59-92. These authorities are owner-local, not represented as tracked contents of this candidate.

Net comparison: exactly 25 zero-context hunks: 24 product hunks across the ten allowlisted files, plus the explicit historical-report exception. Zero unclaimed hunks. The following ledger enumerates every -U0 hunk against d88d633 by exact old/new range and row. Full headers and patch bytes are retained in review/r3confirm2/hunk-ledger.json and baseline-to-candidate.diff.

README.md
  @@ -19,0 +20,2 @@          C03 — ACCEPT, owner-held/on-demand publication boundary.
  @@ -31 +33 @@             C03 — ACCEPT, same boundary in Layout.

contracts/adapters/VoteMarketAdapter.sol
  @@ -15,8 +15,9 @@          C05 — ACCEPT, one funded gauge-bound L1 submission, not L2 creation.
  @@ -28 +29,3 @@           C05 — ACCEPT, adapter-side observations, not measured recipient credit.
  @@ -221,3 +224,6 @@        C05 — ACCEPT, exact pull credit and return to prior balance.

contracts/adapters/VotiumAdapter.sol
  @@ -35,2 +35,6 @@          C05 — ACCEPT, adapter balance boundary and gross/net distinction.
  @@ -161,3 +165,7 @@        C05 — ACCEPT, same custody boundary at the check.

contracts/interfaces/ICampaignRemoteManager.sol
  @@ -30 +30,4 @@           C05 — ACCEPT, L1 success does not establish destination registration/funding.

contracts/libraries/SafeToken.sol
  @@ -5,3 +5,7 @@           C13 — ACCEPT, accepted returns, decoder boundary, wrapped call failure.
  @@ -17 +21,2 @@           C13 — ACCEPT, dependency revert bytes are not bubbled.
  @@ -20 +25,4 @@           C13 — ACCEPT, noncanonical Boolean can fail before the local error.

docs/ABI.md
  @@ -45,0 +46,2 @@         C15 — ACCEPT, gross views and non-readiness distinction.
  @@ -66,0 +69,2 @@         C15 — ACCEPT, gross event expenditure versus venue net/delivery.
  @@ -80,0 +85,9 @@         C13 — ACCEPT, shared-token diagnostic boundary.

docs/CURVE-PROPOSAL.md
  @@ -5 +5 @@               C15 — ACCEPT, initial gross/net disclosure.
  @@ -7 +7 @@               C15 — ACCEPT, Active/current-observed flag and successful FD accounting.
  @@ -12 +12 @@             C15 — ACCEPT, gross funding and independently observed Votium fee/net.
  @@ -22 +22 @@             C15 — ACCEPT, conditional forfeiture and retained-on-revert escrow.

docs/OPERATIONS.md
  @@ -37,0 +38,2 @@         C15 — ACCEPT, gross expenditure, current projection and execution limits.
  @@ -71,0 +74,13 @@        C05 — ACCEPT, core/adapter/venue/FD observation boundaries.

review/R3CONFIRM.md
  @@ -0,0 +1,205 @@         Explicit operator-named report exception — historical HOLD at 3c6cd5e, added by d15d168; not a product C-row implementation or current verdict.

test/fork/ForkFixture.sol
  @@ -1019,10 +1019,15 @@   C07 — ACCEPT, scoped exact-exhaustion multiset, not ordered trace.
  @@ -1119 +1124,2 @@       C07 — ACCEPT, Votium evidence named as multiset.
  @@ -1121,16 +1127,20 @@   C07 — ACCEPT, expected members/multiplicity, no per-deposit ordering claim.

test/fork/ForkVoteMarket.t.sol
  @@ -107,4 +107,9 @@       C07 — ACCEPT, same multiset boundary for both product-owned legs.

C03 has two product hunks, C05 seven, C07 four, C13 four and C15 seven. Each is within its admitted boundary and accepted on the underlying code/observation semantics, not merely its row label. The separate historical-report hunk is authorized by the express report-publication instruction, not by association with a C-row.

Source/observation attribution:
  C05: core funding checks exact lister debit plus nonzero receipt at contracts/CurveGaugeLister.sol:863-875. Adapter checks are exact pull credit then return to baseline at VoteMarketAdapter.sol:182-185,224-231 and VotiumAdapter.sol:143-146,165-173. FD really checks both transfer sides at core :947-955. CRM is called once at VoteMarketAdapter.sol:218-220; test/fork/ForkVoteMarket.t.sol:95-149 observes L1 custody/message facts, not L2 delivery. IIncentivePlatform.deposit and its common receipt meaning are untouched.
  C07: test/fork/ForkFixture.sol:1043-1065 uses an unused-entry bitmap and nested value search, with exact exhaustion. No ordering cursor or per-deposit partition is present. Emitter/topic/pair/data-shape checks, diagnostic strings, Votium gross-fee, all multiplicities, independent transfers and final allowances are executable-token identical.
  C13: contracts/libraries/SafeToken.sol:52-60 checks code, wraps low-level failure, accepts empty success, short-circuits wrong length and decodes Boolean before the local bad-return error. No decoder, approval or diagnostic behavior changed.
  C15: Active/current-flag/terminal behavior follows core :479-518,553-560; exact all-FD transfer/accounting follows :897-978; gross views follow :638-702,720-740. Independent Votium net/fee observations remain at test/fork/ForkFixture.sol:1074-1093. The amount, timing, frozen endpoints/split, no-refund/no-migration and dependency limits are preserved. The current cold wrapper run reaches and passes the retained fork identities; its pin observations do not certify future venue economics or production activation.

Deferred and rejected rows: zero corresponding proposed product/test changes.
  C01 DEFER: FD guards, horizon and accounting unchanged; core :897-978.
  C02 DEFER: controller admission/seating and fixtures unchanged; core :406-470,833-835.
  C04 DEFER: test/Settlement.t.sol:2062-2095 remains one sequential identity; no split, rename or enlarged VC-02 reached-cell claim.
  C06 REJECT: VoteMarket receipt preimages/storage representation unchanged; adapter :259-276,331-356.
  C08 REJECT: repeated gas reads and shared pricing expression retained; adapter :191-193,306-320.
  C09 REJECT: AdapterCustody predicates retained, not inlined.
  C10 REJECT: initial and later-quarter kill-read cadence unchanged; core :485-518.
  C11 REJECT: test/Adapters.t.sol:946-1003 parser/independent ABI witness retained.
  C12 REJECT: separate best-effort maintenance helper retained; core :575-576,991-998.
  C14 REJECT: explicit zero-address exclusion guard retained; VotiumAdapter.sol:219-223.
  C16 REJECT: fixture-only interface remains in contracts/interfaces/IERC20Minimal.sol:19-38.

Historical scope is not conflated with the net candidate diff. Commit 2d0bc2f temporarily included receipt artifacts; 3c6cd5e removed 46 process paths, all under plans/ or review/. Those removals are not executable edits or additional net product hunks. The report exception arrived at d15d168; b36281c changes only the two C03 README statements. Current private custody does not erase earlier Git history; no history rewrite is authorized here.

3. Independent executable and artifact proof — PASS

Exact detached baseline and candidate worktrees began without out/, out-fork/, cache/ or cache-fork/. Fresh builds completed under both profiles. Installed Forge: 1.7.1, commit 4072e48705af9d93e3c0f6e29e93b5e9a40caed8. Installed compiler SHA-256: 54f48274e5ec8a58b378f07c226fa1e25801526b6b0d16129f3a14a18efe72cd. Settings: Solidity 0.8.30, optimizer enabled/200, no viaIR; default Paris; fork Cancun/chain 1. No configuration or dependency edit.

String-aware maximal-token comparison passes on all 44 tracked Solidity files, including the six changed files. It preserves string literals, operators and token boundaries; controls distinguish comment-looking literal text, separated identifiers and separated operators. The 43 baseline product files outside the allowlist are byte-identical to baseline. No declaration, import, executable token, test expectation or assertion changed.

Full fresh ABI objects, methodIdentifiers and recursively resolved storage layouts match the same-profile baseline for all 82 default and 56 fork artifacts. Full product ABIs and selectors also match the normative manifest; core recursive layout matches its normative layout. Adapter recursive layouts match the admitted d88d633 baseline. Entry ordering alone is normalized for ABIs; tuple component order, names, internal types, mutability and event indexing remain compared. Layout normalization removes AST/type-ID indirection, not member order, offsets, slots or widths. The compiled-ABI test reads the candidate's own freshly built default out/.

For every product creation and runtime object, decode the hex to bytes. Read the final two bytes as big-endian CBOR length L; bounds-check and fully decode exactly the preceding L bytes. Require a unique-key {ipfs, solc} map, a 34-byte sha2-256 multihash with 0x1220 prefix, and compiler bytes 00081e. The executable prefix excludes precisely L+2 trailing bytes. Both versions have equal executable bytes and immutable/link reference maps; all byte movement is confined to the validated trailer. Raw full bytecode and trailer/length bytes are retained.

The builder's BYTECODE-PROOF.md:14-32 method and artifacts/hash_artifacts.py were cross-checked against this independent bounds-checked decoder on every actual product artifact. Its hashes are SHA-256 of lowercase hex text, not decoded bytes; those recorded hashes and full hashes reproduce exactly. The hashes below deliberately use SHA-256 of decoded executable bytes. Both representations demonstrate the same equality. This validates the actual trailers, not a claim that the builder's minimal walker is a general CBOR validator.

Executable SHA-256, baseline == candidate in every cell:

  default / CurveGaugeLister / creation
    a4d222d9f2613fc39912312774beea6c43f9ff04715d142cbd8cbe1e0fd405c4
  default / CurveGaugeLister / runtime
    b9890cd7b99aa674714581650b7dfb8897b4ee475d7a638c067c4a31e0dad8f9
  default / VoteMarketAdapter / creation
    7dedbeb73b2850a1f03dbc54641025b8cd0f4b988557be861ef935421769e760
  default / VoteMarketAdapter / runtime
    dc012e0bed88a5177f0b60741d47469838800e6cd8ab2f30d916225a74d279d4
  default / VotiumAdapter / creation
    cc7199750ef9a09f0eeccffd9fa564fdc0c1d71882930c4192679de50e0a5094
  default / VotiumAdapter / runtime
    34a517d66fe7aeb5fb14742d703294549ef2f91005f5fb963aa3174cc8f4d785

  fork / CurveGaugeLister / creation
    212662a9bd899ddf471d346ae69a1be5f35d1c207710b27b7597ce7c00af7018
  fork / CurveGaugeLister / runtime
    c5420d10d532f42c22aec183bdc1434b11c00ce31ce762849e89ff3e8b11f4cd
  fork / VoteMarketAdapter / creation
    f2e483db99ce52ea3786ffe539ee9860b8eebef5a63a1611cff4163738e6f397
  fork / VoteMarketAdapter / runtime
    281b4f278aaea3cc23f5a4e7f39a038a2917ca1aa4ad31e04ce56a4d9cd42544
  fork / VotiumAdapter / creation
    5ea694c5b0ce292c671fa0c6130bb93b05bebb16ae470d3730e692c2ab7d4324
  fork / VotiumAdapter / runtime
    55be8e9a27d12a35f57cc725fec60ca87f332b84d08cbc7d00f1f055ec06d5bf

Result: 12 comparisons, zero executable delta. Full metadata differs as expected from source comments. Outer-trailer stripping is not used to claim test-contract bytecode equality: test contracts embed product creation metadata; their executable source/assertion identity is separately established above.

Decoded full sizes, baseline == candidate within each profile:
  Profile  Contract           Runtime B  Creation B  Constructor arguments B
  default  CurveGaugeLister      15031       17494                      320
  default  VoteMarketAdapter      7136        7727                      128
  default  VotiumAdapter          4949        5468                       96
  fork     CurveGaugeLister      14772       17183                      320
  fork     VoteMarketAdapter      6980        7557                      128
  fork     VotiumAdapter          4833        5340                       96

Each runtime is within 24,576 bytes; each creation object plus its static constructor arguments is within 49,152 bytes. BYTECODE-PROOF.md:104-109 labels its size summary "both profiles" but prints default-profile sizes only; the separate fork values above come from the fresh isolated builds. This carried receipt-label qualification is not an executable or size-limit failure.

4. Native census and gates

Native forge test --offline --list --json discoveries equal BINDING.json exactly: 77 default and 13 fork file:contract:signature identities, no duplicates. Forge lists bare test names; each is resolved uniquely against the same fresh artifact's compiled signatures and compilationTarget, not by blindly appending parentheses. The retained bountyfix02 path/contract identities are unchanged.

  git diff --check d88d633 b36281c                         exit 0
  forge fmt --check, baseline and candidate               exit 0 each
  forge build --offline --sizes --extra-output storageLayout
    baseline/default, baseline/fork, candidate/default,
    candidate/fork                                       exit 0 each
  default test, MAINNET_RPC_URL unset                     exit 0; 77 Success
  default test, MAINNET_RPC_URL=http://127.0.0.1:1         exit 0; 77 Success
  isolated-HOME cold bash scripts/test-fork.sh, no filters exit 0; 13 PASS

Both offline executions have zero failures/skips and executed == discovered == BINDING, including paths and contracts. They are two runs of the same census, not 154 distinct tests. Native compiler/linter warnings are retained; same-profile baseline/candidate warning-category multiplicities agree. No warning is suppressed or turned into a new cleanup task.

The independent comparison program exits 0 after exact source/artifact/census reconciliation. The wrapper independently exits 0. No orchestration exit substitutes for a child exit or an identity-level result.

5. Public tree, obligation register and custody

At b36281c, the 53 product files comprise product, fixtures/tests, documentation, runner and configuration only. The sole additional tracked path is review/R3CONFIRM.md, the named report exception. There are no tracked plans/ paths or bulk review artifacts. The operator's prohibited-reference check found no matches across all 54 tracked candidate files. Raw receipts, private authorities and full manifests remain owner-local and ignored; this pass publishes only the named report.

C03/C05/C07/C13/C15 corrected public/comment claims match the current tree, code and retained observation boundary. README and all five public documentation files were inspected for the corresponding corrected claims. No new semantic claim about destination delivery, universal net rewards, execution readiness, guaranteed confiscation completion or ordered approval matching is accepted.

PAO-FD: SATISFIED-TRACKING / ACTIVATION-OPEN. The carrier at FD-BOUND-OBLIGATION.md:118-153 retains invariant, evidence limits, selected runtime/total-delta certificate, eligibility/contended-window and stale-refresh conditions, approval roles and activation stop condition.

PAO-CTL: SATISFIED-TRACKING / ACTIVATION-OPEN. CTL-CALLER-ROLE-GATE.md:51-58,91-117 retains W1-W8, selected caller/grant graph and both retained routes, attributed unmasked negatives, simulations before authorization and funded broadcast after authorization. No fixture or fork is promoted into production grants.

PAO-AUTH: SATISFIED-TRACKING / ACTIVATION-OPEN. AUTH-EVIDENCE-INDEX.md:222-302 now supplies the exact final-candidate/publication bridge and retains absent owner approval, independently open deployment gates and the distinction between binding facts and approval. Admission citations and the legacy fork-clause resolution resolve; the archived authority objects remain available. The mandatory structural paragraph matches verbatim between RULING.md:97 and CONFIRMATION-BRIEF.md:36. No existing activation obligation is recounted as a new simplification.

Verified original manifest bindings: 10 source digests and 35 receipt digests; current manifest: 32 artifact digests and one gate-document digest. The current index additionally binds the corrected README and the current manifest. Historical source rows were checked at their historical candidates, not incorrectly against today's README. The current index digest is 75f54bccb78a73225601a87883dca02f823521eaca51c04a0a092a9b0090a92b.

Owner-local reproducibility package: review/r3confirm2/. It contains exact invocation argv/cwd/HOME/start/end/native exits, stdout/stderr, source/hunk/census comparisons, full bytecode and metadata separation, and a fresh-artifacts archive. Archive contents were compared byte-for-byte to all 280 archived artifact/build-info files before custody was sealed. All 91 receipt-file digests verify. No raw historical receipt or authority carrier was edited by this review. The prior HOLD report remains retrievable at d15d168.

Receipt manifest SHA-256:
  review/r3confirm2/RECEIPTS.json
  232626c39ce019c20946af7f43e13363cae9cd2fe3c08f8ae6c86144dc4082d2

Authority digests:
  review/r3gate/BINDING.json
  519d60328242e57550374bd280661edbb1a21ff3d9fb3c5e482b2249ab6780c0
  plans/R3GATE-WORK-ORDER.md
  2e90aefd7b83c4437061251827f98188225d089276fe52e046893350896d06bc
  review/r3gate/RULING.md
  201e9d9e69d25a9024076783e91f4209e4021e7ae62a3b3edd35e10fa03185db

No product file, assertion, witness identity, dependency, deployment pin or approval was changed by this review. Publication is limited to review/R3CONFIRM.md; its report commit is not substituted for the reviewed candidate.

Residual posture: LEAN CONVERGED for b36281c9062a7222da13d5e672ba94d14fd7e0be; PAO-FD/CTL/AUTH, owner approval and independent deployment gates remain ACTIVATION-OPEN. No deployment, broadcast or unpause is authorized.
