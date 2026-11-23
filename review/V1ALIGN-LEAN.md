Verdict: LEAN after two test-fixture cuts. No further retirement-only cut is justified.

V1ALIGN-LEAN — no-bounty V1 lean sweep

Binding

Reviewed candidate: ce0fe3ae957057564f76623b181ec825fe72a942.
Starting checkout: main at 14c2d9e3b2ab1b35c1228d38ab1d60ebcce71573; its only delta from the candidate was plans/V1ALIGN-LEAN-BRIEF.md.
Final source: 7bc866555ab5b8627db8f55f854fbe9334fb2aef.
Scope: the brief's retirement-only sweep, not a new security audit, redesign or deployment approval.

Proven cuts

All source anchors below refer to ce0fe3a. Historical consumer anchors refer to e18bee54c08832dd7fd6d0a11932290155bf9178.

Item  Cut in test/fork/ForkFixture.sol      Sole historical consumers                 Source bytes before -> after  Runtime/creation delta
L01   _hasLog, lines 937-944                ForkDuplicateBallot.t.sol:244,426          69,888 -> 69,540               0 / 0, both profiles
L02   log_named_bytes32, line 369           ForkDuplicateBallot.t.sol:162,163          69,540 -> 69,486               0 / 0, both profiles

Both historical consumer paths are test/fork/bounty/ForkDuplicateBallot.t.sol, deleted by v1align. Exact-name searches across contracts/, test/, fork/ and scripts/ find only the corresponding declaration in the reviewed tree; the pre-deletion tree has those two consumers and the declaration. No surviving call, test method, assertion or snapshot was removed. L01 was already optimizer-elided; L02 was an un-emitted console event. No gas saving is claimed.

Each cut was applied and fully gated in a detached disposable worktree on its cumulative predecessor, measured, then reverted. Whole tracked-input hashes and an empty diff prove restoration. Reapplication on main matched the exact trial patch and input bytes, followed by another complete gate. The actual commit trees were independently matched to those gated inputs.

Separate implementation commits:
  L01  0bb93506875d99842e71c877d21adfd3aaedded2  v1align-lean: remove retired duplicate-ballot log helper
  L02  7bc866555ab5b8627db8f55f854fbe9334fb2aef  v1align-lean: remove retired duplicate-ballot console event

Sweep dispositions

Product/import closure: FeeDistributorAccounting and BountyScripts are absent, along with every manifest-retired product file. No bounty text remains in contracts/; all surviving Solidity imports resolve. SafeToken's transfer, transferFrom, approval and private-call branches have live consumers. The inline all-FD routine remains untouched. No bounty-only product surface or storage branch remains.

Retain/DECLINED: certified monetary/FD/validator paths, manifest ABI fields/getters, adapters and protected shared interfaces are not cut candidates. IListingController.get_gauge_weight remains a live mock/test oracle despite its intentional absence from product settlement. VotiumV2 and VoteMarket v2 name the live venues, not the retired lister. test/bountyfix02/AdapterConfig.t.sol retains its exact five required adapter-hardening identities; its name is not dead-code evidence.

Already-unused generic helpers/mock setters are not relabeled as casualties of bounty retirement: the pre-deletion search already has no consumers. Two redundant named imports in TrustedFactoryFixture refer to types still used and directly imported by the ported concrete trust suite; their consumers survived. General import tidying and narrowing the local validator model are outside this causal sweep. Detailed dispositions and native searches are in bundle members sweep/dispositions.txt, sweep/screen.json and sweep/searches.json.

Docs: README, proposal, ABI, OPERATIONS and DEPLOYMENT-PINS are exact accepted replacement payloads. The old bounty docs remain absent; venue intel retains its explicit historical-status notice. No current instruction for a deleted subsystem was found. No doc cut is warranted; historical references, statements that reporting/staking do not exist, and destination-venue claim windows are not bounty machinery.

Size/gas

Fresh same-policy pre-amendment builds reproduce the historical baseline. CurveGaugeLister grew only for the explicitly ruled immutable validator/strict admission predicate, chain-1 constructor guard and paused start (plans/V1ALIGN-PLAN.md:11-17,39-47). Runtime growth: default +442 bytes; fork +436. Creation growth: +590 / +581. The exact core source diff contains those authorized changes, not an accounting rewrite. Both adapters have zero growth. No unruled product growth was found.

For EACH lean cut, metadata-inclusive product runtime/creation sizes before and after are identical:

Profile  Product             Before runtime/creation  After runtime/creation
Default  CurveGaugeLister    15,226 / 17,588          15,226 / 17,588
Default  VotiumAdapter        4,921 /  5,440           4,921 /  5,440
Default  VoteMarketAdapter    6,889 /  7,473           6,889 /  7,473
Fork     CurveGaugeLister    14,965 / 17,280          14,965 / 17,280
Fork     VotiumAdapter        4,803 /  5,310           4,803 /  5,310
Fork     VoteMarketAdapter    6,725 /  7,295           6,725 /  7,295

All compiled artifact size deltas, including test artifacts, are zero. Full product compiler artifacts are byte-identical across accepted stages, including ABI, method identifiers, storage layout and bytecode. Adapter runtime hashes match the certified manifest. Runtime and constructor-inclusive initcode limits pass.

Fresh gates

Forge 1.7.1, commit 4072e48705af9d93e3c0f6e29e93b5e9a40caed8; solc 0.8.30+commit.73712a01. Optimizer 200, no viaIR; default Paris, fork Cancun/chain1. foundry.toml unchanged.

Stage                   fmt/builds  Offline unset/dead RPC  Fork online/warm  Dead-RPC preflight  Frozen diff
baseline                0 / 0,0     77 / 77                 13 / 13           1, expected         PASS
L01 disposable trial    0 / 0,0     77 / 77                 13 / 13           1, expected         PASS
L01 clean main replay   0 / 0,0     77 / 77                 13 / 13           1, expected         PASS
L02 disposable trial    0 / 0,0     77 / 77                 13 / 13           1, expected         PASS
L02 main replay         0 / 0,0     77 / 77                 13 / 13           1, expected         PASS

Each suite cell means exact file:contract:compiled-signature equality with the approved inventory and baseline, not merely equal totals; zero failed/skipped identities. Both native --list inventories were reconciled on every stage. git diff --check passes. Offline commands were forge test --offline -vvv with MAINNET_RPC_URL unset and then http://127.0.0.1:1. Builds used forge build --offline --sizes --extra-output storageLayout under both profiles.

Forks ran through unchanged scripts/test-fork.sh at block 26401019, hash 0x55810b079923a14fb97ad548f5024f65530dbc4fb2357a38f41e13b3d27cb6d3, timestamp 1794512471, chain1, using https://eth-mainnet.public.blastapi.io. The baseline began with fresh outputs and an isolated HOME containing only installed solc, without RPC cache; later stages reused its warmed RPC cache. Every online invocation reverified the header. Every warm-cache unreachable control exited before Forge/test execution. No pin, mock, compiler-policy or runtime-limit substitution was made.

Disclosed collection issue: the first main replay passed all native gates, but its complete artifact comparison found ignored pre-retirement outputs. Common artifacts matched exactly. Both profiles were cleaned and all main gates repeated from fresh outputs; the initial receipts remain under L01-landed, the accepted replacement under L01-cleaned. The cleanup collector also rejected an empty residual cache directory after both successful forge clean commands; removing that empty directory resolved setup. Neither issue was a source/test failure. Existing warnings remain visible: the fresh baseline has 5/3 solc warnings and 43/14 Forge lint records for default/fork; no warning-free claim.

Freeze, evidence and remainder

All contracts/, monetary/FD/validator source, adapters' certified bytes, foundry.toml, scripts, concrete test bodies, witness authority and pre-existing review receipts remain unchanged. Only the two fixture deletions and new lean evidence/report are published beyond the already-present brief. No falsifier receipt or authority file was rewritten.

Committed evidence: review/v1align-lean/receipts.tar.gz
SHA-256: e7eef3e05a6e976aaf1f906c311f51766cf1c7148653a80452cbb99ecb8012eb
505 file members verified against source bytes; receipt-manifest.json hashes every other member. Included: native stdout/stderr and argv/cwd/environment/time/exits, source hashes, exact inventories, before/after sizes, both cut patches and restoration/reapplication proofs, historical searches/builds, collection failures, complete product artifacts and collector/verifier scripts. FINAL-VERIFICATION.json binds both committed cut trees to the accepted gates. Scripts retain their original execution paths; recorded argv/configs are the replay authority.

LEAN is certified within the retirement-only scope. No further qualifying cut or bounded review remainder. Deployment remains pending under the accepted no-bounty release conditions; fork impersonations are not production authorization or destination-delivery evidence. No broadcast, deployment or production custody action occurred.
