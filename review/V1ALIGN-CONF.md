Verdict: HOLD — two G6 conformance-evidence gaps. NO-BOUNTY V1 ACCEPTED is not certified.

# V1ALIGN-CONF — bounded no-bounty V1 parity review

## Binding and disposition

Reviewed candidate: `b37e5333a07050e7ea87da98712c0edc483673fa`.
Product predecessor: `cbc52a407473726bec712426f335cc34ef204027`; the candidate's intervening package adds execution evidence only.
Review checkout: clean `main` at `0ed674066f0fec1a9cc648d0802bdee88af0d6d5`, whose sole delta from the candidate is `plans/V1ALIGN-CONF-BRIEF.md`.
Baseline: `e18bee54c08832dd7fd6d0a11932290155bf9178`.

Authority: `plans/V1ALIGN-PLAN.md`, `plans/V1ALIGN-WITNESSES.md`, `plans/V1ALIGN-WITNESS-INVENTORY.json`, `plans/V1ALIGN-MANIFEST.json`, and `plans/V1ALIGN-DOC-DELTAS.md`. This is the bounded conformance leg, not a new whole-product security audit or deployment approval.

Fresh native execution, full-entry compiler comparisons, source preservation, deletion closure and exact documentation checks pass. The prescribed G6 claim is narrower than “a named test turned red”: `V1ALIGN-WITNESSES.md:51-54` binds the discriminating cell. Two receipts do not establish the specified frame. Neither finding demonstrates a defect in the pristine product. They prevent the requested unconditional certificate; all other verified results below remain credited.

## Exact gaps

### VC-01 — F-NB-SPLIT does not reach the required test-side FD-delta assertion

Authority: `plans/V1ALIGN-WITNESSES.md:74` requires `test_KillAtEachReleaseCount` / exact FD delta for the half-remainder split mutant.

The stored patch changes only `SafeToken.safeTransfer(crvUSD, fd, amount)` to `amount / 2` (`review/v1align-execution/gates/p3_falsifiers.py:89-91`). It leaves the gross lister-debit and FD-credit postconditions unchanged at `contracts/CurveGaugeLister.sol:778-782`. The receipt is a genuine compiled, selected RED, but reports `ConfiscationDeltaMismatch()`. The lister-debit check stops the mutated call; `test/Settlement.t.sol:2339` does not return, so the required `FD got exactly the unreleased` assertion at `:2341` is never evaluated.

Stored native evidence: `review/v1align-execution/gates/p3-falsify-logs.tar.gz`, members:

- `p3/F-NB-SPLIT.patch.txt`
- `p3/F-NB-SPLIT.test_KillAtEachReleaseCount.{pristine,red,restored}.log`

Native red: `[FAIL: ConfiscationDeltaMismatch()] test_KillAtEachReleaseCount()`; 0 passed, 1 failed, 0 skipped. Pristine/restored each pass the same identity. `FINAL.md:95` calls this an exact-FD-delta witness, but the raw failure establishes the earlier product guard, not that test assertion.

Required disposition: supply an authorized product-only split falsifier/receipt that reaches the specified FD-delta assertion with final tests unchanged, or explicitly amend the authority to accept the earlier guard-level sensitivity. Do not relabel or rewrite the existing receipt. No pristine transfer/accounting fix is indicated by this finding.

### VC-02 — F-NB-HORIZON aborts before the named near-end cursor cell

Authority: `plans/V1ALIGN-WITNESSES.md:76` specifies H+1 with a near-end cursor. I reproduced the exact stored mutation (`epochStart(t)` to `t`) with byte-identical final tests, obtaining native exits 0 / 1 / 0.

The actual first RED is the H+1 assertion at `test/Settlement.t.sol:2083-2084` for cursor offset **1**, not `WEEK-1`. The loop runs offsets `[0, 1, WEEK-1]` in that order (`:2023-2040`). Fresh trace:

- `MockFeeDistributor::setLastTokenTime(1818633601)` — `T0 + 40*WEEK + 1`.
- `VM::warp(1830729601)` — that cursor's floored H+1.
- `VM::expectRevert(DistributorUnusable())`.
- Mutated `confiscate` transfers/accounts the full fee and returns `10000000000000000000000`.
- Test reverts: `next call did not revert as expected`.

The named near-end cursor would be `1837382399` (`T0 + 70*WEEK + WEEK-1`); it is absent from the red trace because execution already stopped. This proves a genuine partial-week H+1 sensitivity, not the specifically named near-end cell. The pristine and restored test do execute all offsets successfully. The earlier receipt in `FINAL.md:97` cannot be credited as near-end mutant execution merely from its test name and generic revert-expectation failure.

Fresh evidence: bundle members `receipts/F-NB-HORIZON.{pristine,red,restored}.{json,stdout,stderr}` and `receipts/F-NB-HORIZON.patch`; decisive red trace lines 939, 1039-1079. Stored counterpart: `p3/F-NB-HORIZON.test_AuditM01_AccountingHorizonIncludesPartialWeekEdges.red.log` in the archive above.

Required disposition: make the specified near-end mutant cell actually execute in the authorized final witness and publish its 0/1/0 receipt, or explicitly accept the earlier one-second-offset cell through an authority amendment. No candidate product or test was changed during this review.

## Fresh execution and evidence custody

All execution used a separate `git archive` of the exact candidate, initially without `out`, `out-fork`, `cache` or `cache-fork`. Neither the working product tree nor historical receipts were edited. Mutants were applied only to two separate disposable copies; both sources were restored byte-for-byte afterward. All test/fork sources were SHA-256 compared to the candidate before and after each mutant stage.

Execution root:
`/home/winny/.hermes/profiles/gpt6-astra-auditor/cache/scratch/v1align-conf-s1wibf6y/`

Durable local receipt bundle (not part of the Git commit):
`/home/winny/.hermes/profiles/gpt6-astra-auditor/artifacts/v1align-conf-b37e533-receipts.tar.gz`

Bundle SHA-256: `b76b295c9f2ff1f88acdd55bee7e284f457065d20d566fffea23063d4db395bb`.
It contains 78 verified members: native stdout/stderr, argv/cwd/time/exit records, exact mutant patches, source/test hashes, full comparisons, six fresh product compiler artifacts and reviewer scripts. `receipt-manifest.json` hashes the other members. It is outside the scratch-pruning directory. The critical mismatches and native identity census are also preserved in this report; the historical G6 archive remains committed at the reviewed candidate.

Toolchain: Forge 1.7.1, commit `4072e48705af9d93e3c0f6e29e93b5e9a40caed8`; solc `0.8.30+commit.73712a01.Linux.g++`. Resolved settings: optimizer enabled, 200 runs, no viaIR, default Paris/test=`test`/out=`out`; fork Cancun/chain=`mainnet`/test=`fork`/out=`out-fork`. No dependency or compiler-policy change.

| Invocation | Exit | Observed result |
| --- | ---: | --- |
| `git diff --check` on the review checkout | 0 | clean |
| Baseline-to-candidate `git diff --check` scoped to product/tests/fork/scripts/config/current docs | 0 | clean |
| `forge fmt --check` | 0 | clean |
| Both-profile `forge build --offline --sizes --extra-output storageLayout --ast` | 0 / 0 | fresh compilation |
| Both-profile `forge test --offline --list --json` | 0 / 0 | exact 77 / 13 inventory |
| Default `forge test --offline -vvv`, `MAINNET_RPC_URL` unset | 0 | 77 passed, 0 failed, 0 skipped |
| Same default command, `MAINNET_RPC_URL=http://127.0.0.1:1` | 0 | 77 passed, 0 failed, 0 skipped |
| `scripts/test-fork.sh`, cold isolated HOME | 0 | 13 passed, 0 failed, 0 skipped |
| Same wrapper/HOME, warm | 0 | 13 passed, 0 failed, 0 skipped |
| Same wrapper/warm cache, unreachable RPC | 1 | preflight blocked; no test/PASS lines |
| Independent ABI/layout/source/docs/size/inventory comparison | 0 | 192 machine checks pass; G6 frame adjudication is separate |
| Independent six full-ABI corruptions | 0 | all six rejected; pristine accepted |
| Stored ABI/import comparator re-run on fresh artifacts | 0 | all 10 recorded predicates true |

Warnings are not suppressed: 5 solc warnings default / 3 fork (unused try/catch parameters and restrictive-mutability suggestions), plus 43 / 14 Forge lint warning records. The added `test/TrustedFactory.t.sol:857` mutability warning remains. An additional whole-history whitespace check exits 2 solely for trailing whitespace in 12 lines of the preserved native `review/v1align-execution/gates/g1-build-default.txt` log. This is disclosed, not cleaned out of historical evidence, and is not represented as a product-format failure.

Fork endpoint: `https://eth-mainnet.public.blastapi.io`; endpoint override only. The fresh HOME initially contained only `.local/share/svm/0.8.30/solc-0.8.30`, with no `.foundry/cache/rpc`. Cold run: 66.821 seconds; warm: 3.600 seconds; afterward the native cache was `mainnet/26401019`. Both online wrappers independently verified:

`chainId=0x1 number=0x192d8fb hash=0x55810b079923a14fb97ad548f5024f65530dbc4fb2357a38f41e13b3d27cb6d3 timestamp=0x6af61657`

Thus block 26401019 / timestamp 1794512471 remained unchanged. The unreachable warm-cache control returned `BLOCKED: RPC ... refusing to run fork tests`. No failed online attempt occurred in this reviewer run. The earlier PublicNode archive denial remains preserved in `review/v1align-execution/gates/g4-publicnode-attempt.txt`; it was not substituted with empty-code or skipped-positive results. DAO/controller seating and holder funding are disclosed fork impersonations, not broadcasts or production authorization.

## Cell-by-cell product conformance

### 1. Constructor, admission, ABI and recursive storage — conforms

- `contracts/CurveGaugeLister.sol:244-275`: validator is argument seven; all first-six ABI input objects (including names, tuple members and internal types) equal the baseline under both profiles. WrongChain is the first constructor check. Existing owner/code/decimals/FD/config checks retain their prescribed order, with validator `NoCode` after the original code checks. Owner/immutables are assigned and `paused=true` precedes configuration storage. There is no constructor predicate/readiness/fee/bounty call.
- `:337-345`: `_requireTrustedGauge` is byte-identical to the baseline V2 executable function. One STATICCALL uses `abi.encodeCall(ITrustedGaugeValidator.validateGauge,(gauge))`; exact 32-byte word 1 alone passes; canonical zero and failed/malformed/noncanonical replies retain the specified errors.
- `:365-403`: lock/pause, configuration snapshots, unchanged `_admit`, trust, positive-share readiness, record/liability writes, fee pull, zero-weight add, membership/type postcondition, original event. Owner-paid admission has no exemption; `listGaugeNoEscrow` remains trust/readiness independent.
- Full ABI objects compare equal after normalizing entry order only: 1 constructor, 30 functions, 10 events, 33 errors. Tuple/component order, names/internalType, mutability and indexed flags were compared, not only selectors. Exact methodIdentifier maps match. No bounty getter, listing ID, extra constructor slot, setter/default, payable core entrypoint, receive or fallback.
- Recursive storage comparison expands type references and preserves root/member order, slots, offsets, widths, encoding and mapping key/value definitions; only compiler AST/type identity is removed. Roots remain owner slot0; pendingOwner slot1/offset0; paused slot1/offset20; admission slot2; platforms slots3-4; listings slot5; totalEscrow slot6; lock slot7. StoredListing remains eight slots. Validator is immutable, with no storage slot. Original 15-field Listing and enum wire order are unchanged.

### 2. Settlement and confiscation law — conforms

The 28 pre-existing core functions other than the deliberately amended paid `listGauge` compare byte-for-byte to baseline, including `checkpoint`, `confiscate`, `checkpointFees`, views, `_admit`, `_gaugeKilled`, `_remaining`, routing and inline `_confiscate`. The whole core runtime properly changes; old whole-core bytecode equality is not required.

`contracts/CurveGaugeLister.sol:444-505,617-623,660-662,747-799` preserves the full law: Active flag read before due/no-due handling and later catch-up tranches; only gauge `is_killed`; no controller-weight/validator/ballot/report/latch settlement reads; flag/ABI faults revert; Unknown reverts and terminal records return before external reads; an observed successful seizure stays terminal after unkill.

For the current gauge, all `R=FEE-QUARTER*epochsReleased` goes to the immutable FD. The original order is intact: FD code/token/not-killed and nonzero/nonfuture floored 20-week cursor; effects and gross liability debit; exact direct transfer with both balance deltas; mandatory same-transaction checkpoint; exact cursor and accounted-custody postchecks; original EscrowConfiscated then FeeCheckpointResult(true). No FD approval/burn/split/refund/sweep is added. The standalone best-effort maintenance call remains separate. Native coverage includes all 25 retained settlement identities, the retained kill/FD fork identities and TF8; Appendix A binds every execution/signature. VC-01/VC-02 qualify falsifier evidence, not these pristine results.

### 3. Shared protection/deletion closure — conforms

All 11 manifest-protected adapter/interface/SafeToken files match both manifest SHA-256 and baseline bytes. Both adapters' complete ABI, methodIdentifier maps and metadata-inclusive runtime hashes match their same-profile baselines. `ITrustedGaugeValidator` changes only authorized NatSpec; its one-method ABI is unchanged.

Owner-only, nonzero/code-bearing, write-once/no-rebind `setLister` remains at `contracts/adapters/VotiumAdapter.sol:82-120` and `contracts/adapters/VoteMarketAdapter.sol:110-157`. Core paid readiness, positive-share snapshots, zero-share and DAO exemptions, staging, exact bounded approvals/debits/receipts and allowance clearing survive. Local-vs-remote code rules and VoteMarket's future 50-exclusion bound (`:316-328`) remain unchanged, as does one-way ETH float (`:274`). Retained native binding, wrong-owner/misbinding, arithmetic and funded retry tests pass.

Every surviving Solidity import in contracts/test/fork resolves and none reaches a deleted dependency. All ten manifest product deletions and retired executable test roots are absent; no case-insensitive `bounty` occurrence remains anywhere in `contracts/`. `test/bountyfix02/AdapterConfig.t.sol` and all five AdapterConfigR2 identities remain. No non-bounty assertion/expected-revert line was removed from retained offline suites; their diffs are constructor/chain/pause fixture wiring and additive paused checks. The 11 retained fork bodies are unchanged; shared fork fixture changes add validator verification and wiring. The trust runner's change is documentation only.

### 4. Witness truth and trust matrix — conforms, subject to G6 frame gaps

Native discovered IDs equal the authoritative live target set, and every PASS signature equals both its inventory signature and fresh compiled methodIdentifier key. Exact equality holds on both offline runs and both fork runs: 69 RETAIN_V1 + 8 PORT_TRUST offline; 11 RETAIN_V1 + 2 PORT_TRUST fork. Zero omissions, extras, duplicates, failures or skips. All 64 V2-twin and 57 bounty offline baseline identities, plus 9 bounty fork identities, are absent; every retired twin maps to its surviving counterpart. The one baseline fuzz identity, `testFuzz_Thin_CustodyConservation(uint256)`, is explicitly retired; the final suite contains no fuzz test. Runs were not counted as separate identities.

No concrete bounty/test-suite inheritance supplies a false green: TrustedFactoryFixture is abstract with no test methods; TestBase has no test methods. Concrete default suites are exactly the five expected suites. Fork scenarios under recursive `test/fork/` are abstract, and only the five `fork/` runners execute under the fork profile.

| Matrix cell | Current source | Verified surviving obligations |
| --- | --- | --- |
| TF1 | `test/TrustedFactory.t.sol:49-146` | Wrong-chain first with zero/EOA validator; chain1 exact NoCode; two supplied code-bearing pins; paused start; reverting checker constructs without validation |
| TF2 | `:152-254` | Exact gauge/selector; distinct pool/LP/factory/caller controls; all 15 Active fields; independent epoch; configured venues/split; custody/liability/type/raw-zero; complete GaugeListed topics/data |
| TF3 | `:260-356` | Legacy direct-zero/minter route; wrong nonzero direct result and failed read reject; spoof/no-policy/zero/unreadable/nonfactory reject; local-model disclosure retained |
| TF4 | `:362-511` | Healthy false first; funded/approved owner with actor-specific post-funding snapshot; add poison before transfer poison; trust before unbound/misbound readiness |
| TF5 | `:517-616` | False-vs-fault distinction; revert/empty/1/31/64 bytes/word2/maxuint/missing selector/removed code; full pre/post rollback; canonical true control |
| TF6 | `:622-741` | Registry/association/LP/index/code errors before trust; pause/duplicate precedence; valid pool reaches trust |
| TF7 | `:747-922` | False/fault/malformed/codeless checker independence; paused/unbound/nonfactory DAO admission; exact weight, all 15 fields, membership, zero custody and complete free event; outsider/registry rejection |
| TF8 | `:928-1129` | New-paid false/fault rejection; existing release, both seizure routes, releasable/views, standalone fee checkpoint and terminal no-op independent of checker; full-remainder FD deltas and original event/accounting; removed claim helper absent |
| Fork SS-ng | `test/fork/ForkTrustedFactory.t.sol:106-207` | Real validator/module identities and DAO owner, method1 reciprocal proof, true gauge/false factory plus secondary gauge; paid real-token full record/event/count/type/raw-zero |
| Fork legacy | `:213-362` | Real method2, distinct LP/minter/direct-zero/reverse proof, registry/type5/controller absence; code-bearing minimal-proxy targets; full paid tuple/event including payer topic. Proxy shape is not claimed as implementation-byte identity |

Snapshot port: `test/TrustedFactoryFixture.sol:100-144,333-389` compares the complete original tuple, liability, actual actor balance/allowance (owner explicitly at `test/TrustedFactory.t.sol:403-410`), core/FD/venue balances, venue allowances, membership/type/raw/scheduled weight/addCalls, counts and touched keyed receipts. Rejection calls are required to revert; reverted trace logs are not treated as persistent receipts. No removed hook custody is credited. Both original fork deployment helpers verify validator code3402/hash before core construction (`test/fork/ForkFixture.sol:600-670`).

### 5. G6 reproduction and remaining receipts — qualified, not complete

Two disposable product-only reproductions were performed, using exact committed final tests and escaped full-signature filters:

- F-TF-LENGTH: `data.length != 32` → `< 32`; selected `test/TrustedFactory.t.sol:TrustedFactoryTest:test_TF_CheckerReadFaultsFailClosed()`; native exits **0/1/0**. RED is exactly `TF_EXACT_RETURN_LENGTH: 64-byte true-with-tail: expected revert with the named error, call succeeded` (`test/TrustedFactory.t.sol:563-565`). Named frame satisfied.
- F-NB-HORIZON: floored cursor → raw cursor in the freshness bound; selected `test/Settlement.t.sol:SettlementTest:test_AuditM01_AccountingHorizonIncludesPartialWeekEdges()`; native exits **0/1/0**. Genuine H+1 assertion RED, but not the specified near-end subcase: VC-02 remains open.

Both use `forge test --offline --match-path <file> --match-contract '^<contract>$' --match-test '^<name>\(\)$' -vvvv`. Each native run selects exactly one compiled identity and has zero skips. Sources restored exactly; tests never changed. Compile errors, empty selection and setup faults are not counted.

The committed P3 archive was parsed member-by-member: 26 concrete mutants, 27 selected invocations per stage (ACCOUNT has two), 81 native logs. Every row has a real pristine PASS, selected compiled RED and restored PASS; all exact stored patches match their generator and apply to the final source. The archived final copy's 41 Solidity files plus foundry.toml are byte-identical to the candidate; P2 trust test/fixture/mock copies also match current bytes. Raw logs do not record individual process return codes; the stored generator/summary records its exit predicates. That provenance is distinguished from the reviewer-recorded 0/1/0 exit metadata above.

Archive SHA-256: `861f929edaf55f04c0bdadcb266ce587ef5a6b36c64d6be14c20c4aa13f3115a` (`review/v1align-execution/gates/p3-falsify-logs.tar.gz`). In Appendix B, each receipt stem denotes actual members `p3/<ID>.<testname>.{pristine,red,restored}.log`, with exact patch `p3/<ID>.patch.txt`. VC-01 and VC-02 are not waived by the 26-red headline. F-NB-WEIGHT's CannotCheckpoint is at the tested live-gauge `confiscate` call (`test/Settlement.t.sol:860`), not setup; the later zero-weight funded-release controls remain present and pass pristine/restored. It is not relabeled as a later quarter assertion.

Six full-ABI corruptions (unexpected callable, constructor order, appended Listing member, event indexing, removed error, mutability) were independently rejected. A valid-syntax in-memory retired import was also detected; no invalid source was shipped. These comparator checks are separate from behavioral red counts. The existing `g6_abi_falsifiers.py` and `g6-abi-falsifiers.json` predicates were also reproduced on fresh compiler artifacts.

### 6. Current docs and historical evidence — conforms

README, proposal, ABI, OPERATIONS and DEPLOYMENT-PINS are byte-identical to the five authority BEGIN_FILE/END_FILE payloads, including final newlines. Both old bounty docs are absent. INTEL-YB-HELPERS equals its baseline with only the prescribed historical-intro replacement. Current repository-relative references resolve; root-relative command examples such as `scripts/test-fork.sh` are commands, not broken docs-relative links. Four documented selector literals were re-derived with `cast sig` and match.

Shipping code/docs/scripts contain no retained reporter/stake/claim product economics. Explicit statements that reporter/staking services do not exist, Stake DAO venue names, external FD claim-interface exclusions and VoteMarket destination residual/claim windows are legitimate retained descriptions, not a bounty route. Historical research remains labeled historical. Every plans/review change from baseline through the candidate is an addition; no earlier historical evidence was modified or deleted in an intermediate implementation commit. Authority files were not edited to fit the candidate.

### 7. Metadata-inclusive runtime and creation limits — conforms

Independent strict hex decoding rejected unresolved/nonhex bytecode, retained all metadata (53 bytes including its length word per deployable), and measured these exact sizes. All deployed runtimes are below 24,576 bytes. Constructor arguments are entirely static ABI data; deployment initcode includes their actual encoded width, not only compiler creation bytecode, and is below 49,152 bytes in every case.

| Profile | Deployable | Runtime bytes | Runtime headroom | Creation bytes | Constructor args | Deployment initcode |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| default | CurveGaugeLister | 15,226 | 9,350 | 17,588 | 320 | 17,908 |
| default | VotiumAdapter | 4,921 | 19,655 | 5,440 | 96 | 5,536 |
| default | VoteMarketAdapter | 6,889 | 17,687 | 7,473 | 128 | 7,601 |
| fork | CurveGaugeLister | 14,965 | 9,611 | 17,280 | 320 | 17,600 |
| fork | VotiumAdapter | 4,803 | 19,773 | 5,310 | 96 | 5,406 |
| fork | VoteMarketAdapter | 6,725 | 17,851 | 7,295 | 128 | 7,423 |

## Deployment boundary and final ruling

Do not issue NO-BOUNTY V1 ACCEPTED on these receipts yet. Close VC-01 and VC-02 with the specified evidence or explicit authority disposition. No product change, witness change, history rewrite, broadcast or deployment was performed by this review.

Even after conformance acceptance, current pin/source/role/validator-policy re-verification, actual controller integration/seating, authorized adapter binding/ownership readbacks, committed ETH float, real venue and destination readiness/delivery, safe FD accounting/cooldown window, operational staffing and a funded trial remain open. The historical pinned fork does not close those production obligations.

## Appendix A — every live identity/signature reconciled

Every row below is discovered under its exact file/contract/name, is present in that contract's freshly compiled methodIdentifier map with the shown selector, and passes BOTH fresh native runs for its profile. All signatures are zero-argument; no assumed suffix was used in place of compiled validation. R = RETAIN_V1; P = PORT_TRUST.

### default

`test/Adapters.t.sol:AdaptersTest`

| Disposition | Compiled signature | Selector | Both runs |
| --- | --- | --- | --- |
| R | `test_Adapter_CompiledAbiSurfaceMatchesAllowlist()` | `0xa721c6c2` | PASS / PASS |
| R | `test_Adapter_ConfiscationMidCatchUpWithRealAdapters()` | `0x472e6e3d` | PASS / PASS |
| R | `test_Adapter_EndToEndFourQuartersSettleViaCheckpoint()` | `0x16df8ab3` | PASS / PASS |
| R | `test_Adapter_NoDrainFullPayloadsAsActualOwner()` | `0x40b9c65e` | PASS / PASS |
| R | `test_Adapter_OwnershipTransferTwoStep()` | `0x380494e7` | PASS / PASS |
| R | `test_Adapter_VoteMarketCampaignRequiresSourceChain()` | `0x3f87c2a4` | PASS / PASS |
| R | `test_Adapter_VoteMarketConfigParamsFidelityAndMockGuards()` | `0xf1913f1f` | PASS / PASS |
| R | `test_Adapter_VoteMarketDuplicateGuardAndNonceReceipts()` | `0xfdb3dda8` | PASS / PASS |
| R | `test_Adapter_VoteMarketEthShortfallRevertsAndRollsBack()` | `0x1222e36b` | PASS / PASS |
| R | `test_Adapter_VoteMarketExactPullRecordedCampaignParams()` | `0xa1119463` | PASS / PASS |
| R | `test_Adapter_VoteMarketNonListerRejection()` | `0x18321206` | PASS / PASS |
| R | `test_Adapter_VoteMarketReceiveIsOneWayFloat()` | `0x9da8ac28` | PASS / PASS |
| R | `test_Adapter_VotiumConfigOwnerOnlyAndPassedThrough()` | `0xdeca8ad2` | PASS / PASS |
| R | `test_Adapter_VotiumDeterministicNonzeroReceipts()` | `0x5f64cbd9` | PASS / PASS |
| R | `test_Adapter_VotiumHonorsVenueExclusionLimit()` | `0xc5859bd2` | PASS / PASS |
| R | `test_Adapter_VotiumNonListerAndBindingRejects()` | `0x8754fd09` | PASS / PASS |
| R | `test_Adapter_VotiumRejectsCapBeyondRealBound()` | `0x50cd0758` | PASS / PASS |
| R | `test_Adapter_VotiumRejectsUnsortedExclusions()` | `0xadbc54eb` | PASS / PASS |
| R | `test_Adapter_WrongTokenRejectedEverywhere()` | `0x26737dda` | PASS / PASS |
| R | `test_AuditH01_PaidAdmissionRejectsUnboundOrMisboundAdapters()` | `0xb90ec276` | PASS / PASS |
| R | `test_AuditH01_VoteMarketCaptureCannotSpendEthFloat()` | `0xb33da56a` | PASS / PASS |

`test/CurveGaugeLister.t.sol:CurveGaugeListerTest`

| Disposition | Compiled signature | Selector | Both runs |
| --- | --- | --- | --- |
| R | `test_AdmissionAllowsNativeCoinAndUnfundedPool()` | `0xa1e35511` | PASS / PASS |
| R | `test_AdmissionChangeDoesNotRevalidateExistingEscrow()` | `0x4cc516c0` | PASS / PASS |
| R | `test_AdmissionRejectsInvalidAddressesLpAndKilledGauge()` | `0x6375b51a` | PASS / PASS |
| R | `test_AdmissionRejectsUnknownPoolAndSpoofGauge()` | `0x2c0d9c0f` | PASS / PASS |
| R | `test_AdmissionValidatesCoinCountAndAddresses()` | `0xa8e87906` | PASS / PASS |
| R | `test_AuditH01_ReadinessGetterFailuresAndZeroShareExemption()` | `0x1faa423e` | PASS / PASS |
| R | `test_ConstructorRejectsAliasedEndpoints()` | `0xb124a57a` | PASS / PASS |
| R | `test_DaoZeroFeeListingNeverDrips()` | `0x3cdac8f5` | PASS / PASS |
| R | `test_DistinctAuthenticatedGaugesForSamePoolCanList()` | `0x11623951` | PASS / PASS |
| R | `test_DoubleListingRejectedAcrossAllPathsAndTerminalStates()` | `0xbee36914` | PASS / PASS |
| R | `test_ListingFailureRollsBackFeeAndRegistration()` | `0xa4ef2ce8` | PASS / PASS |
| R | `test_NoOwnerWithdrawalOrArbitraryExecutionSurface()` | `0x8bb069ed` | PASS / PASS |
| R | `test_OnlyOwnerCanConfigureAdmissionAndPlatforms()` | `0xc63ff0c7` | PASS / PASS |
| R | `test_OwnerPauseOnlyBlocksPermissionlessAdmission()` | `0x0240a30b` | PASS / PASS |
| R | `test_PaidListingTransfersExactFeeIntoEscrow()` | `0x7a3c0020` | PASS / PASS |
| R | `test_PaidListingUsesZeroWeightAndMembershipOnly()` | `0x511188a7` | PASS / PASS |
| R | `test_PlatformChangesCannotRedirectExistingEscrow()` | `0xf4f68eff` | PASS / PASS |
| R | `test_TwoStepOwnershipTransfer()` | `0x47ecce9f` | PASS / PASS |

`test/Settlement.t.sol:SettlementTest`

| Disposition | Compiled signature | Selector | Both runs |
| --- | --- | --- | --- |
| R | `test_AdapterCannotReenterListingReleaseOrConfiscation()` | `0xa4140678` | PASS / PASS |
| R | `test_AuditM01_AccountingHorizonIncludesPartialWeekEdges()` | `0x2dd16515` | PASS / PASS |
| R | `test_AuditM01_InvalidCursorAndIncompleteCheckpointRevert()` | `0x550ac2aa` | PASS / PASS |
| R | `test_AuditM01_MidCatchUpAccountingFailureRollsBackEarlierQuarter()` | `0xaa8d710d` | PASS / PASS |
| R | `test_AuditM01_StaleFortyWeekDistributorRevertsAndSafeRetryAllocatesAll()` | `0x5b7803f9` | PASS / PASS |
| R | `test_CheckpointCooldownRevertsConfiscationUntilAccountingEligible()` | `0x1e250538` | PASS / PASS |
| R | `test_ConfiscationTransfersOnlyKilledGaugeBalance()` | `0x3ba15e5d` | PASS / PASS |
| R | `test_FourEpochQuarterRelease()` | `0xfd6b528b` | PASS / PASS |
| R | `test_GaugeFlagReadFailureCannotSettle()` | `0xffb5c960` | PASS / PASS |
| R | `test_GaugeFlagReadFailureMidCatchUpRollsBack()` | `0x2ae1c674` | PASS / PASS |
| R | `test_KillAtEachReleaseCount()` | `0xbabf416f` | PASS / PASS |
| R | `test_KillViaGaugeFlagOnlyConfiscates()` | `0x86988491` | PASS / PASS |
| R | `test_KilledFeeDistributorRevertsWithoutAlternativeRecipient()` | `0xadf251c4` | PASS / PASS |
| R | `test_KilledFlagTrueAtMaturityStopsMidCatchUp()` | `0x3dcd5dd1` | PASS / PASS |
| R | `test_MissedEpochCatchUpIsBoundedAndPreservesMaturityLabels()` | `0x78971d68` | PASS / PASS |
| R | `test_ObservedConfiscationStaysTerminalAfterFlagCleared()` | `0x3a25ea6f` | PASS / PASS |
| R | `test_PlatformSplitsAndZeroShareRouting()` | `0x5f171cb2` | PASS / PASS |
| R | `test_ReceiptMustBeFundedAndAllowanceCleared()` | `0x9b63be76` | PASS / PASS |
| R | `test_ReleasableUsesGaugeFlagOnly()` | `0x5cc17673` | PASS / PASS |
| R | `test_SecondPlatformFailureRollsBackWholeCheckpoint()` | `0xba779e5b` | PASS / PASS |
| R | `test_SettlementNeverReadsControllerWeight()` | `0xa9f66401` | PASS / PASS |
| R | `test_TerminalStatesSkipKillOracleReads()` | `0xc17ba015` | PASS / PASS |
| R | `test_ThursdayBoundaryAndOneSecondEdges()` | `0x36942d51` | PASS / PASS |
| R | `test_TokenFalseReturnEmptyReturnAndTransferTax()` | `0x7581d9f6` | PASS / PASS |
| R | `test_WeightZeroWithoutKilledFlagDoesNotConfiscate()` | `0xb9ce1e83` | PASS / PASS |

`test/TrustedFactory.t.sol:TrustedFactoryTest`

| Disposition | Compiled signature | Selector | Both runs |
| --- | --- | --- | --- |
| P | `test_TF_CheckerReadFaultsFailClosed()` | `0x24b93518` | PASS / PASS |
| P | `test_TF_ConstructorPinAndGuards()` | `0xaed24fcb` | PASS / PASS |
| P | `test_TF_DaoFreeLaneIsTrustIndependent()` | `0x83fcec49` | PASS / PASS |
| P | `test_TF_LegacyFactoryAndNonFactoryPolicy()` | `0x8fc463d3` | PASS / PASS |
| P | `test_TF_RegistryAuthenticationPrecedesTrust()` | `0x5d3ade59` | PASS / PASS |
| P | `test_TF_TrustIsAdmissionOnly()` | `0x3021ad04` | PASS / PASS |
| P | `test_TF_TrustedPaidAdmissionAndExactTarget()` | `0x0a95be44` | PASS / PASS |
| P | `test_TF_UntrustedPaidAdmissionBeforeEffects()` | `0x82d20e1b` | PASS / PASS |

`test/bountyfix02/AdapterConfig.t.sol:AdapterConfigR2Test`

| Disposition | Compiled signature | Selector | Both runs |
| --- | --- | --- | --- |
| R | `test_R2_GasSettingsRejectOverflowWithoutMutation()` | `0x4506daa5` | PASS / PASS |
| R | `test_R2_GasSettingsWorstCaseBoundariesAndExclusionGrowth()` | `0x638ff2ee` | PASS / PASS |
| R | `test_R2_RejectedGasSettingsPreserveFundedCheckpoint()` | `0x9d6b85fc` | PASS / PASS |
| R | `test_R2_VoteMarketConstructorDistinguishesLocalAndRemotePins()` | `0x64540dd0` | PASS / PASS |
| R | `test_R2_VotiumConstructorRejectsCodeLessPins()` | `0x0cd3fa62` | PASS / PASS |

### fork

`fork/Admission.t.sol:AdmissionForkTest`

| Disposition | Compiled signature | Selector | Both runs |
| --- | --- | --- | --- |
| R | `test_Fork_ControllerSeatingAndUnseatedRollback()` | `0x1c7b7a28` | PASS / PASS |
| R | `test_Fork_DaoFreeListingNeverEscrowsOrDrips()` | `0x87c019fe` | PASS / PASS |
| R | `test_Fork_PaidListingTransfersExactFeeAtZeroWeight()` | `0x7bac5c0b` | PASS / PASS |

`fork/Kill.t.sol:KillForkTest`

| Disposition | Compiled signature | Selector | Both runs |
| --- | --- | --- | --- |
| R | `test_Fork_ConfiscationRequiresFreshAccountableFeeDistributor()` | `0x7258698e` | PASS / PASS |
| R | `test_Fork_MidDripKillStopsLaterTranchesAndSeizesRemainder()` | `0x5d761808` | PASS / PASS |
| R | `test_Fork_RealGaugeKillRequiresItsActualAuthority()` | `0x9ce0de3c` | PASS / PASS |

`fork/TrustedFactory.t.sol:TrustedFactoryForkTest`

| Disposition | Compiled signature | Selector | Both runs |
| --- | --- | --- | --- |
| P | `test_Fork_TF_LegacyTrustedFactoryAdmission()` | `0x3ed6a50a` | PASS / PASS |
| P | `test_Fork_TF_SsNgTrustedFactoryAdmission()` | `0xdee68fec` | PASS / PASS |

`fork/VoteMarket.t.sol:VoteMarketForkTest`

| Disposition | Compiled signature | Selector | Both runs |
| --- | --- | --- | --- |
| R | `test_Fork_MixedSplitFourWeeksFundsBothRealVenues()` | `0xc8f716f2` | PASS / PASS |
| R | `test_Fork_RealCRMRejectsWrongChainAndUnlistedPlatform()` | `0x7c45bac0` | PASS / PASS |
| R | `test_Fork_VoteMarketEthShortfallRollsBackMixedCheckpoint()` | `0x1f3d4862` | PASS / PASS |

`fork/Votium.t.sol:VotiumForkTest`

| Disposition | Compiled signature | Selector | Both runs |
| --- | --- | --- | --- |
| R | `test_Fork_VotiumFourWeeklyTranchesFundRealActiveRounds()` | `0x74bcb774` | PASS / PASS |
| R | `test_Fork_VotiumLateCatchUpPreservesScheduleNotHistoricalRounds()` | `0x2baf2bc4` | PASS / PASS |

## Appendix B — actual G6 receipt index

All rows have nonempty pristine/restored PASS receipts for the listed signature. The displayed RED is extracted from the first native FAIL line, not inferred from a test count. This table records observed results; the gap column controls named-frame acceptance.

| Mutant ID / receipt stem prefix | Exact selected test signature | Observed RED | Gap |
| --- | --- | --- | --- |
| F-TF-CHAIN | `test_TF_ConstructorPinAndGuards()` | TF_CHAIN_FIRST: WrongChain precedes every later guard | none |
| F-TF-CODE | `test_TF_ConstructorPinAndGuards()` | TF_PIN_NO_CODE: zero validator must be rejected | none |
| F-TF-PIN | `test_TF_ConstructorPinAndGuards()` | TF_PIN_EXACT: supplied checker retained exactly | none |
| F-TF-PAUSE | `test_TF_ConstructorPinAndGuards()` | TF_PIN_EXACT: fresh core starts paused | none |
| F-TF-FALSE | `test_TF_UntrustedPaidAdmissionBeforeEffects()` | TF_FALSE_REJECTS: canonical false exact error: expected revert with the named error, call succeeded | none |
| F-TF-FAULT | `test_TF_CheckerReadFaultsFailClosed()` | TF_READ_FAULT_REJECTS: top-level revert: expected revert with the named error, call succeeded | none |
| F-TF-LENGTH | `test_TF_CheckerReadFaultsFailClosed()` | TF_EXACT_RETURN_LENGTH: 64-byte true-with-tail: expected revert with the named error, call succeeded | none |
| F-TF-BOOL | `test_TF_CheckerReadFaultsFailClosed()` | TF_CANONICAL_BOOL: word 2: expected revert with the named error, call succeeded | none |
| F-TF-ARG | `test_TF_TrustedPaidAdmissionAndExactTarget()` | TF_EXACT_GAUGE_ARGUMENT: only the exact gauge is accepted and admitted: unexpected revert, data [ABI error bytes in raw log] | none |
| F-TF-SELECTOR | `test_TF_TrustedPaidAdmissionAndExactTarget()` | TF_EXACT_GAUGE_ARGUMENT: only the exact gauge is accepted and admitted: unexpected revert, data [ABI error bytes in raw log] | none |
| F-TF-AFTER-ADD | `test_TF_UntrustedPaidAdmissionBeforeEffects()` | TF_BEFORE_ADD_GAUGE: trust error precedes the poisoned add_gauge | none |
| F-TF-AFTER-FEE | `test_TF_UntrustedPaidAdmissionBeforeEffects()` | TF_BEFORE_TRANSFER: trust error precedes the poisoned transferFrom | none |
| F-TF-AFTER-READY | `test_TF_UntrustedPaidAdmissionBeforeEffects()` | TF_BEFORE_READINESS: false checker beats unbound/misbound venues | none |
| F-TF-REGISTRY | `test_TF_RegistryAuthenticationPrecedesTrust()` | TF_REGISTRY_FIRST: registry authentication precedes the trust read | none |
| F-TF-OWNER | `test_TF_UntrustedPaidAdmissionBeforeEffects()` | TF_OWNER_PAID_NOT_EXEMPT: owner pays the same law: expected revert with the named error, call succeeded | none |
| F-TF-FREE | `test_TF_DaoFreeLaneIsTrustIndependent()` | TF_DAO_NO_CHECKER_DEPENDENCE: false checker does not gate the free lane: unexpected revert, data [ABI error bytes in raw log] | none |
| F-TF-RETRO | `test_TF_TrustIsAdmissionOnly()` | TF_NO_RETROACTIVE_DRIP_GATE: settlement of an admitted gauge performs no trust read: unexpected revert, data [ABI error bytes in raw log] | none |
| F-TF-RECORD | `test_TF_TrustedPaidAdmissionAndExactTarget()` | TF_TRUSTED_PAID_ACTIVE: votium is the configured venue | none |
| F-TF-FREE-EVENT | `test_TF_DaoFreeLaneIsTrustIndependent()` | TF_DAO_NO_FACTORY_ALLOWED: free-lane GaugeListed emitted | none |
| F-NB-SPLIT | `test_KillAtEachReleaseCount()` | ConfiscationDeltaMismatch() | VC-01 |
| F-NB-WEIGHT | `test_WeightZeroWithoutKilledFlagDoesNotConfiscate()` | CannotCheckpoint() | none |
| F-NB-HORIZON | `test_AuditM01_AccountingHorizonIncludesPartialWeekEdges()` | next call did not revert as expected | VC-02 |
| F-NB-ACCOUNT | `test_CheckpointCooldownRevertsConfiscationUntilAccountingEligible()` | next call did not revert as expected | none |
| F-NB-ACCOUNT | `test_AuditM01_MidCatchUpAccountingFailureRollsBackEarlierQuarter()` | next call did not revert as expected | none |
| F-NB-POST | `test_AuditM01_InvalidCursorAndIncompleteCheckpointRevert()` | next call did not revert as expected | none |
| F-NB-BIND-VOTIUM | `test_Adapter_VotiumNonListerAndBindingRejects()` | next call did not revert as expected | none |
| F-NB-BIND-VOTEMARKET | `test_AuditH01_VoteMarketCaptureCannotSpendEthFloat()` | next call did not revert as expected | none |

Final bounded disposition: HOLD for VC-01 and VC-02; verified pristine product, ABI/layout, preservation, native census, fork, documentation and size results remain credited.
