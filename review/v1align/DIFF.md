# v1align — systematic composed-source divergence ruling

Candidate: e18bee54c08832dd7fd6d0a11932290155bf9178. Product files were not edited in this leg. Ruling: release the bounded implementation in plans/V1ALIGN-PLAN.md; deployment is not approved.

## Evidence and comparison method

Fresh Forge 1.7.1 / Solidity 0.8.30 builds used the repository's optimizer200/default-Paris/fork-Cancun policy, with output/cache redirected into session scratch. Native build/size/list/test outputs and full product ABI/layout/runtime-hash summaries are preserved alongside this report. Source SHA256s are in baseline.json. `compare_sources.py` compares raw routine UTF-8 bytes and exact Solidity token sequences (only whitespace/comments removed; strings preserved), and records import closures. It does NOT call different whole-contract bytecode identical.

There are 35 distinct routine names including constructor/modifiers: 32 common, of which 23 have identical raw routine bytes and 28 identical executable tokens. The four changed common routines are constructor, listGauge, getListing and _confiscate. V2 adds only _requireBountyReady, _requireTrustedGauge and listingId. The complete line/hash/equality enumeration is source-comparison.json; no common routine is omitted. Declarations/imports/generated getters are covered separately below.

Historical cross-check: the locally available pre-trust object 74e536f32437f9813630f5c89a3427e11c40af29 has byte-identical CurveGaugeLister, both adapters, SafeToken, IFeeDistributor and IIncentivePlatform to this candidate (historical-source-check.json). This corroborates current-source preservation; the public audit anchor for this leg remains the full reviewed e18bee5 commit, not an assumption that the older local object is on public main history. Historical auditfix001/PLAN/REQUIREMENTS references in source are not present as current tracked authority; this leg re-states the operative law explicitly rather than requiring executors to find absent plans.

## Exhaustive divergence ledger

Classification labels have binding effect: BOUNTY-COUPLED stays out; PRODUCTION-PARITY-MISSING ports; HISTORICAL-NEUTRAL creates no product change. Retained equalities are listed to rule out a hidden port obligation.

| Row | V1 -> V2 difference and source anchors | Classification / disposition |
| --- | --- | --- |
| D01 | Contract title/name, NatSpec and plan references; V2 calls itself prospective and says V1 frozen (V1:12–16; V2:17–35) | HISTORICAL-NEUTRAL. Supersede freeze/new-version prose for the authorized never-deployed in-place amendment; not an upgrade/migration |
| D02 | Extra imports: FeeDistributorAccounting, ICurveGaugeListerV2, IGaugeBounty, BountyTypes and transitive BountyScripts/BountyRead/IBountyGovernance/IOwnershipVoting (V2:11–15; GaugeBounty:4–15) | BOUNTY-COUPLED for hook/interfaces/report/script/governance branch; remove after tests port. Accounting extraction itself is separately D16 |
| D03 | ITrustedGaugeValidator import, new immutable trustedGaugeValidator and getter (V2:14,:102–109) | PRODUCTION-PARITY-MISSING. Retain narrow interface and port pointer/getter; no validator code vendoring or external policy-management surface |
| D04 | Six-argument V1 constructor vs eight-argument V2 (V1:213–239; V2:263–303) | Split ruling: bounty_ seventh is BOUNTY-COUPLED; validator eighth is PRODUCTION-PARITY-MISSING but becomes seventh in no-bounty V1. Existing first-six shape and tuple component order remain |
| D05 | block.chainid!=1 / WrongChain first (V2:273) | PRODUCTION-PARITY-MISSING. Retain mainnet-only enforcement independent of bounty; V1 lacks it |
| D06 | Validator code check before decimals check (V2:278) and assignment (V2:295) | PRODUCTION-PARITY-MISSING. Reuse NoCode(address), accept any explicitly supplied code-bearing address at construction, require operational pin authenticity separately; no constructor predicate probe |
| D07 | Bounty code/config token/FD/lister checks, immutable bounty assignment (V2:284–294) | BOUNTY-COUPLED. No replacement dummy/stub/binding loop |
| D08 | paused=true in V2 constructor vs V1 default false (V2:297) | PRODUCTION-PARITY-MISSING by this authority ruling. Though introduced with bounty wiring, safe closed-start remains useful with write-once venue binding/controller/readiness; port explicitly, do not accidentally inherit a startup default |
| D09 | _requireTrustedGauge exact staticcall/parser + errors (V2:223–232,:347–367) | PRODUCTION-PARITY-MISSING. Exact canonical result, exact selector and gauge argument; normalized read-fault vs canonical-false errors; no owner exception/cache/fallback |
| D10 | Paid path calls trust after _admit, before platforms and before every fee/record/add effect (V1:301–335; V2:386–421) | PRODUCTION-PARITY-MISSING. Only this new admission predicate ports. Existing memory config snapshots and readiness stay intact |
| D11 | Paid _requireBountyReady and reciprocal lister() read (V2:341–345,:398) | BOUNTY-COUPLED. Remove dependence entirely; no zero-hook config or readiness exception |
| D12 | Local Listing15 replaced with interface ListingV2/18 outputs, named memory result, status cast, original gross confiscated plus reporterReward/fdConfiscated/rewardReportId (V1:44–60,:499–520; V2:559–583; ICurveGaugeListerV2:25–47) | BOUNTY-COUPLED for three allocation fields/calculation; HISTORICAL-NEUTRAL for named result/interface-qualified internalType/cast style. Retain V1 entire original ABI tuple and source getter; wire enum encoding itself is unchanged |
| D13 | StoredListing adds reporterReward and rewardReportId (V1:106–118; V2:119–135) | BOUNTY-COUPLED. V1 record 8 slots/256 bytes vs V2 10 slots/320 bytes. No fdConfiscated storage slot: V2 derives it. Do not append any of these |
| D14 | SPLIT_DIVISOR=2 (V2:85–87), immutable bounty() (V2:99–101), permanent listingId() hash with uint256(1)/core/gauge (V2:622–628) | BOUNTY-COUPLED. All are reward attribution/allocation plumbing; no independent paid-lane guarantee requires them |
| D15 | Same checkpoint/confiscate entry logic calls different _confiscate body: V2 always reads rewardTerms, eligible getReport consistency, computes floor(R/2), stores allocation, force-approves/funds credit and checks debit/zero allowance, then funds FD share (V1:678–730; V2:722–785) | BOUNTY-COUPLED. Remove both eligible and nominally ineligible hook branches. Even all-FD V2 still has a hook-read availability dependency; do NOT implement no-bounty as a configured ineligible hook. Keep V1 direct whole-R path |
| D16 | Inline V1 FD pre/postflight vs FeeDistributorAccounting.preflight/depositAndAccount, including BountyScripts.weekFloor helper (library:29–60; V1:681–725) | HISTORICAL-NEUTRAL extraction, NOT missing safety. Byte-slice and token comparisons prove equality after explicitly listed token/local-name/constant substitutions and single-revert braces. Library's checked week-floor multiplication and V1's unchecked product are equivalent because floor(t/W)*W<=t. Keep inline law and remove now-unused library/transitive script imports |
| D17 | EscrowConfiscated(address,address,uint256,uint256) with two indexed addresses vs V2(address,address,bytes32,uint256,uint256,uint256,uint256) with added indexed reportId and gross/B/F fields (V1:150; V2:167–178) | BOUNTY-COUPLED. Retain original event and amount meaning as exact FD custody; no split event or reporter metadata |
| D18 | BadBounty, BountyNotReady, BountyDeltaMismatch (V2:220–222) | BOUNTY-COUPLED. Do not port. WrongChain and two trust errors are the three non-bounty error additions, not all six V2 additions |
| D19 | DistributorUnusable/ConfiscationDeltaMismatch are library-qualified in V2 rather than locally declared (V1:187–188; V2 constructor/confiscation + library:18–19) | HISTORICAL-NEUTRAL. Same canonical selectors/types; retain V1 declarations. Compiler ABI has no duplicate error entries. V1 total30 vs V2 total36 errors reflects six additions, not a changed FD error contract |
| D20 | Separate GaugeBounty config/storage/guards/events/errors/functions and upstream ballot/read/parser/CallsScript machinery | BOUNTY-COUPLED in entirety. Nine-address config, stake custody, report/proposal bindings, winner/arm lifecycle, submit/creditBallot/recognizeKill/rewardTerms/creditReward/resolve/claim/markFrivolous/flushDao/accounting plus bind/config/report views do not implement ordinary DAO kill/confiscation. None ports; actual kill authority remains upstream |
| D21 | Source imports/interfaces/adapters shared by both compositions | HISTORICAL-NEUTRAL, already composed in V1. Both use the SAME SafeToken, IERC20Minimal, IFeeDistributor, ICurveRegistry, ICurveGauge, IListingController and IIncentivePlatform; adapters add same IVotiumV2/ICampaignRemoteManager. No second V2 adapter implementation exists |
| D22 | V2 tests/fixtures/deployment prose/ABI docs describe split hooks and V2-only guarantee; trusted tests inherit bounty worlds | BOUNTY-COUPLED for mechanism-specific fixtures/tests/docs; PRODUCTION-PARITY-MISSING for paid trust witnesses; HISTORICAL-NEUTRAL for twin non-bounty coverage and shared adapter hardening. Preserve original69/11 identities and port8/2; see exact inventory. Deleting paths by a broad bounty* glob would wrongly delete five shared hardening tests |
| D23 | Runtime/initcode and metadata differ due to name/imports/constructor/trust/split logic; compiler profiles differ | HISTORICAL-NEUTRAL measurement, not an extra feature to port. Runtime sizes below include metadata; future V1 size remains an implementation gate, not V1+V2 subtraction |

## Equal surfaces explicitly ruled retained

- Status names/order, AdmissionConfig, PlatformConfig; all original fee/quarter/week/epoch/bps/zero-initial-weight constants; native sentinel and registry-index bounds. No economic or epoch-constant drift.
- Ownership/pausing setters and two-step acceptance, lock and onlyOwner modifiers: exact raw routine bytes. The changed initial paused value is D08, not changed pause scope.
- _validateAdmission, _validatePlatformTarget, _requirePlatformsReady and _requirePlatformReady: exact raw routine bytes. _validatePlatforms is token-identical; only comments were shortened.
- _admit: token-identical. Same code/duplicate/controller-occupancy/registry/LP/flag/type/coin rules. listGaugeNoEscrow: exact raw routine bytes, including no paid readiness. It already avoids the V2 trust gate by keeping that gate outside _admit.
- checkpoint: token-identical, including initial authoritative flag, later-tranche reread, chronological loop, counter/liability effects, terminalization and QuarterReleased. confiscate, checkpointFees, releasable, epochStart, epochsElapsed, _remaining and _gaugeKilled: exact raw routine bytes. _cappedElapsed and _routeQuarter: token-identical. No epoch-math drift to port.
- _fundPlatform and _tryCheckpointToken: exact raw routine bytes. Same forceApprove/exact decrease/nonzero receipt/zero allowance/event ordering; standalone best-effort remains distinct from mandatory confiscation.
- Nine other event definitions, topics/indexing and emission semantics are unchanged. Only D17 changes the confiscation event. Full ABI still differs in contract-qualified internalType metadata for config structs and getter/constructor types; this is not a behavior port. Preserve original V1 metadata in the target manifest rather than equating selectors with full ABI.

## auditfix001 and later shared hardening — byte-bound verification

1. Adapter setLister: VotiumAdapter:110–126 and VoteMarketAdapter:147–163 each use onlyOwner, reject previously bound/zero/codeless target, set once and expose lister(). They are single shared source files, not V1/V2 copies. Their whole-source hashes match the historical local object and current baseline. Constructor local-code guards and VoteMarket maximum-length arithmetic also already appear in those same files (Votium:92–98; VoteMarket:123–134,:316–329).
2. Paid readiness: V1:277–286 is byte-identical at the routine level to V2:332–339. V1 listGauge:307–312 already enforces it before listing/totalEscrow/fee/add effects. Config staging still deliberately does not require binding. No port needed.
3. Mandatory FD accounting: V1:681–725 already has code/token/killed, nonzero/nonfuture cursor, week-floor horizon, exact two-sided transfer, direct uncaught checkpoint and both postchecks. source-comparison.json records matching preflight and deposit/account token sequences after the declared parameterization changes. This is NOT raw source/bytecode equality between the inlined V1 and the differently composed V2. Tests :1910–2265 exercise the actual partial-week/cooldown/loss/rollback cases, and both full default runs passed them.
4. ForkKill:256–402 already exercises real strict cooldown, admin-outer-caller non-bypass, stale zero-delta refresh and direct retry with actual bucket differences. These obligations remain in the no-bounty fork suite; removal of bounty FD tests cannot retire them.

## ABI and storage census

| Contract | Functions | Events | Errors incl. libraries | Constructor / receive |
| --- | ---: | ---: | ---: | --- |
| Current V1 | 29 | 10 | 30 | 1 / none |
| Current V2 | 32 | 10 | 36 | 1 / none |
| GaugeBounty | 14 | 7 | 21 | 1 / none |
| VotiumAdapter | 16 | 6 | 14 | 1 / none |
| VoteMarketAdapter | 26 | 7 | 16 | 1 / payable receive |
| Normative amended V1, not yet compiled | 30 | 10 | 33 | 1 / none |

Both profiles produce equal ABI objects. V2's three additional callables are bounty(), listingId(address), trustedGaugeValidator(); only the last ports. Target errors are V1's original30 plus WrongChain/UntrustedGauge/TrustedGaugeCheckFailed. Entire constructor and tuple/event arrays are in plans/V1ALIGN-MANIFEST.json, not inferred from these counts.

The two core storage root maps have the same slots/offsets; V2 extends only mapping-value tail as D13. Original roots: owner0, pendingOwner1@0, paused1@20, admission2, platforms3–4, listings5, totalEscrow6, lock7. All immutable/constant getters have no root storage slot. V1 StoredListing members: pool/status/epochsReleased packed at0 (offsets0/20/21), lpToken1, payer2, admissionRegistry3, gaugeType4, listingEpoch5, votium6, voteMarket7@0 and votiumBps7@20. V2 appends reporterReward8 and rewardReportId9. Target is the original V1 recursive layout with one new immutable, not a storage migration.

## Fresh baseline sizes

Bytes, decoded compiler objects including metadata; runtime ceiling24,576. Creation size excludes encoded constructor arguments. All native --sizes invocations exited0. These are BASELINE measurements, not estimates or acceptance receipts for the proposed amendment.

| Product | Default runtime / creation / runtime headroom | Fork runtime / creation / runtime headroom |
| --- | --- | --- |
| CurveGaugeLister | 14,784 / 16,998 / 9,792 | 14,529 / 16,699 / 10,047 |
| CurveGaugeListerV2 | 17,176 / 20,268 / 7,400 | 16,881 / 19,913 / 7,695 |
| GaugeBounty | 14,811 / 17,179 / 9,765 | 14,439 / 16,740 / 10,137 |
| VotiumAdapter | 4,921 / 5,440 / 19,655 | 4,803 / 5,310 / 19,773 |
| VoteMarketAdapter | 6,889 / 7,473 / 17,687 | 6,725 / 7,295 / 17,851 |

V2 minus V1 runtime is2,392 default and2,352 fork bytes; that is NOT the cost of just the trust gate. Internal libraries are inlined and not extra production deployments; compiler library-shell sizes and all interfaces are recorded in baseline.json. No amended-source sketch was built because this authority leg does not edit product. Actual target runtime must be measured under both unchanged profiles and pass independently decoded ceiling checks.

## Gate observations and limits

- Both fresh baseline builds and native inventories succeeded. Compiler/linter warnings remain visible in build-default.txt/build-fork.txt; they are not new authority fixes.
- Full default suite with RPC unset:198 PASS,0 fail,0 skip. Full default suite with explicitly unreachable RPC:198 PASS,0 fail,0 skip. Exact native inventories are list-default.txt and list-fork.txt.
- The adapter ABI tests read hardcoded existing out/ paths while the baseline collector redirected compilation. hardcoded-artifact-check.json verifies their read inputs' FULL ABI, methodIdentifiers and decoded runtime against the fresh default artifacts, all equal. Future implementation must run from clean out/ instead of relying on stale artifacts.
- Unchanged full baseline fork gate:22 PASS,0 fail,0 skip cold;22 PASS,0 fail,0 skip warm, at the exact header through the wrapper. Unreachable endpoint after warming exited1 before tests, as required. See fork-status.json and native fork-*.txt. Initial collector setup used the wrong compiler-directory assumption and exited before RPC; fork-setup-attempt1.txt preserves that fault. Corrected setup copied only the actually installed solc into fresh HOME/XDG paths; no RPC cache was carried in.
- Current tests include the retiring bounty product; these green results establish a baseline, not acceptance of the future no-bounty implementation or current mainnet deployment. No source mutations or future sensitivity receipts are claimed in this leg.

## Public-tree and authority outcome

Remove the ten exclusive product files in the target manifest plus mechanism-specific test/runners and old bounty ABI/operations docs; keep their history at the reviewed commit. No executable quarantine, disabled hook, split event, reporter storage or claim API belongs in shipping sources. Do not remove the shared adapters or test/bountyfix02 hardening suite. All current non-bounty operational disclosures survive, especially venue unavailability, residual forfeiture and FD contention; removed ballot-attribution risks belong only to history.

Four numbered qwen packages are released in plans/V1ALIGN-PLAN.md, one commit each. Exact public replacement text is plans/V1ALIGN-DOC-DELTAS.md. No operator decision remains blocking implementation. Production deployment still lacks a newly authorized controller integration, current pin/policy/venue verification and deployment/ownership/binding receipts. Nothing in this source diff silently supplies those approvals.
