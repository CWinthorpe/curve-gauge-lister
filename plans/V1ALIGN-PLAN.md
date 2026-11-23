# v1align — authority ruling and released qwen work order

Status: RELEASE IMPLEMENTATION; NOT DEPLOYMENT APPROVAL.
Candidate reviewed: e18bee54c08832dd7fd6d0a11932290155bf9178 (main).
Authority: V1ALIGN-BRIEF.md and the operator's no-bounty order. This plan supersedes historical V1 source-freeze, V2-only trust-gate, split-confiscation and bounty shipping instructions for this prospective release. It does not rewrite historical findings or certify a future implementation.

## 1. Ruling

Amend contracts/CurveGaugeLister.sol in place. Do not create V3, an optional-hook variant, a compatibility wrapper, or a dummy bounty argument. The operator states V1 has never deployed; the tracked README also says not deployed, and the tracked tree supplies no production deployment receipt. This is adequate authority for a source amendment, not an exhaustive on-chain negative search. If any actual deployment or liability is discovered, STOP before representing this as a migration or upgrade. The old source remains addressable at the candidate SHA.

Port these non-bounty production requirements:

1. The constructor-parameterized immutable trustedGaugeValidator, its code-presence check and getter, ITrustedGaugeValidator.validateGauge, the exact V2 strict-return helper, and UntrustedGauge/TrustedGaugeCheckFailed errors.
2. WrongChain and the chain-1 constructor guard, FIRST in the constructor. Mainnet dependencies and source-chain venue behavior are independent of reporter economics.
3. paused = true in construction. This is classified PRODUCTION-PARITY-MISSING, not retired as incidental bounty wiring: there are still owner-authenticated, write-once adapter bindings, controller authorization and deployment checks to complete. Readiness remains an independent backstop if the owner unpauses too early.

Keep the original V1 Listing, stored record, confiscation event, settlement implementation, token handling, ownership, configurations and adapter implementations. In particular, leave V1's inline _confiscate intact. Extracting it into FeeDistributorAccounting gains no safety parity; that library currently imports BountyScripts. Removing that entire unused branch is narrower and avoids accidentally importing the split hook.

Remove V2, GaugeBounty and their exclusive dependencies and tests from the shipping tree after transplanting the trust witnesses. Do not retain executable quarantine under contracts/, test/ or fork/, and do not retain an optional bounty deployment path. Git history at the full candidate SHA is the quarantine/audit archive. New documentation must state the current product without reporter/stake/claim sections. Historical review/plan receipts remain historical and are not mechanically rewritten to say that old split tests tested all-FD economics.

No unresolved economic/operator decision was found. Deployment authorization, real upstream seating and current pin/venue readiness remain expressly unapproved.

## 2. Binding product law

### 2.1 Constructor and admission

The exact target constructor, nonpayable, is:

    CurveGaugeLister(
        address owner_,
        address crvUSD_,
        address controller_,
        address feeDistributor_,
        AdmissionConfig memory admission_,
        PlatformConfig memory platforms_,
        address trustedGaugeValidator_
    )

AdmissionConfig remains (address registry,uint8 maxCoins). PlatformConfig remains (address votium,address voteMarket,uint16 votiumBps). The validator is the SEVENTH argument, not V2's eighth argument: bounty_ is removed, not replaced with zero or a reserved slot. Preserve the first six argument names/order/types. No configuration-tuple extension, default, setter, per-listing override or local factory allowlist.

Constructor order: WrongChain if block.chainid != 1; existing nonzero-owner and token/controller/FD code checks; validator.code.length != 0 using NoCode(address), including zero and EOA inputs; existing decimals==18 and FD token/not-killed checks; immutable assignments, owner, paused=true; existing admission/platform validation and storage. No constructor validateGauge call, adapter-readiness call, fee pull, venue approval or external bounty dependency. Deploying a code-bearing wrong checker is still possible: code is wiring validation, not pin authentication.

listGauge: lock/pause -> snapshot admission and platforms -> unchanged _admit -> _requireTrustedGauge(gauge) -> unchanged _requirePlatformsReady(snapshot) -> existing record/totalEscrow effects -> exact FEE pull -> controller.add_gauge(gauge,derivedType,0) -> membership/type postcondition -> original GaugeListed. The lock word and structural controller reads already occur earlier; the prohibition is against fee/record/liability/controller-add effects before trust, not against those reads or lock acquisition.

The helper is V2's exact executable body, using one top-level STATICCALL to the supplied validator with abi.encodeCall(ITrustedGaugeValidator.validateGauge,(gauge)). Accept exactly 32 bytes with uint256 word 1. Successful canonical zero -> UntrustedGauge(gauge). Failed call, wrong length (including oversized true-with-tail), or word >1 -> TrustedGaugeCheckFailed(gauge). Do not ABI-decode bool before validating; do not bubble checker errors, accept a prefix, cache true, call validateProposalGauges, or substitute pool/LP/factory/caller. An out-of-gas abort still reverts but need not yield a custom error.

The operational validator pin is 0x888888c34a46d0b2A34e9204e5273208E670e784. Its pointer is immutable; upstream factory/module/manager policy is not. An owner using listGauge pays and passes the same gate. Every new paid listing rechecks policy. listGaugeNoEscrow performs NO validator read and stays available while paused or adapters/checker are unavailable, subject to owner authorization and unchanged registry/structural/controller law. Existing settlement, views, checkpointFees and owner administration gain no validator dependence.

### 2.2 Settlement and all-FD confiscation — mandatory unchanged law

FEE=10_000e18; QUARTER=2_500e18; EPOCHS=4; WEEK=604800; BPS=10000; INITIAL_WEIGHT=0. A listing's Thursday-floor epoch and snapshotted venues/split are permanent. Each matured quarter funds once, chronologically, capped at four. Elapsed time is not the funded counter. Late funds buy execution-time venue participation, not historical votes.

For Active records, gauge.is_killed() is the only kill oracle, before due arithmetic/no-due return and before each later catch-up tranche. True enters the same _confiscate from checkpoint or confiscate. False with zero weight does not seize. Gauge-read/ABI failure reverts, never permits funding or declares a kill. Settlement reads no controller weight, validator, ballot, report or local kill latch. Unknown gauge reverts; Exhausted/Confiscated/DaoExempt settlement no-ops return before external reads. An observed successful confiscation stays terminal after unkill. An unobserved historical kill is not reconstructible.

For the current gauge only, R = FEE - QUARTER*epochsReleased. All R goes directly to the immutable crvUSD FeeDistributor at the operational pin 0xD16d5eC345Dd86Fb63C6a9C43c517210F1027914. No caller, payer, reporter, owner or other gauge receives any part. Previous venue expenditure is not recoverable escrow. deposited = remaining + released + confiscated; totalEscrow is the sum of paid active remainders, not unsolicited surplus.

Preserve this atomic ordering exactly:

1. FD code/token/not-killed; t=last_token_time nonzero and not future; now <= epochStart(t)+20*WEEK. H equality passes; H+1 fails, including partial-first-week cases.
2. Effects: capture R and receiptWeek; mark Confiscated; totalEscrow -= R.
3. SafeToken direct transfer of exactly R; verify exact lister debit AND FD credit. No approval to FD; never burn(address).
4. Mandatory checkpoint_token in the SAME transaction, without catch or pre-transfer checkpoint. Require last_token_time==now and token_last_balance==actual FD custody. Any call/decode/postcondition failure rolls back everything, including earlier tranches in this checkpoint.
5. Emit original EscrowConfiscated(gauge,feeDistributor,R,receiptWeek), then FeeCheckpointResult(true).

checkpointFees remains a separate permissionless best-effort maintenance call; its true means the upstream call returned, not that arbitrary stale money was safely allocated. No payer refund, alternate FD, sweep, migration, emergency bypass or weakened accounting. Preserve normal upstream integer-rounding dust; freshness prevents the bounded-loop omitted-tail loss, not all rounding.

### 2.3 Adapter/shared protections already present

Keep both adapter sources and all original shared interfaces/SafeToken byte-for-byte, with hashes in V1ALIGN-MANIFEST.json. Preserve owner-only, one-time nonzero/code-bearing setLister and no rebind; every positive-share adapter must name this lister on each paid admission; zero-share and DAO-free exemptions; config staging without binding circularity; exact approvals/debits/receipts and allowance clearing; local token/ingress code checks; VoteMarket worst-case 50-exclusion arithmetic bound; real-venue configuration controls and one-way ETH float. These are composed V1 protections, including changes historically delivered under bounty-named work. They are not ports and must not be removed with the bounty.

## 3. ABI, storage and deletion manifest

V1ALIGN-MANIFEST.json is the complete normative ABI (not a selector-count substitute), copied from fresh baseline V1 compiler ABI plus only the four entries and constructor input above. Target: 30 functions, 10 events, 33 errors including the three SafeToken errors, one constructor, no receive/fallback/payable. Retain all 29 V1 function entries with their complete inputs/outputs/mutability and all original event indexing. Three errors are added: WrongChain(), UntrustedGauge(address), TrustedGaugeCheckFailed(address). No bounty(), listingId(), bounty errors, hooks or allocation fields.

getListing returns the original 15 fields, in order: pool, lpToken, payer, admissionRegistry, gaugeType, listingEpoch, status, epochsReleased, deposited, remaining, released, confiscated, votium, voteMarket, votiumBps. Status wire values remain Unlisted=0, Active=1, Exhausted=2, Confiscated=3, DaoExempt=4. Return names/internalType also remain as the baseline ABI; do not copy V2's named result or uint8 cast into the source needlessly.

Keep V1's recursive storage layout: roots owner slot0, pendingOwner slot1/offset0, paused slot1/offset20, admission slot2, platforms slots3–4, listings mapping slot5, totalEscrow slot6, lock slot7. StoredListing remains eight slots; no reporterReward/rewardReportId append. The new address is immutable and has no storage slot. Compare recursive members/widths/offsets/order after stripping only compiler AST/type IDs, not meaningful layout.

Delete these exact product files in package 3 (full manifest is machine-readable):

- contracts/CurveGaugeListerV2.sol
- contracts/GaugeBounty.sol
- contracts/bounty/BountyTypes.sol
- contracts/interfaces/IBountyGovernance.sol
- contracts/interfaces/ICurveGaugeListerV2.sol
- contracts/interfaces/IGaugeBounty.sol
- contracts/interfaces/IOwnershipVoting.sol
- contracts/libraries/BountyRead.sol
- contracts/libraries/BountyScripts.sol
- contracts/libraries/FeeDistributorAccounting.sol

Retain ITrustedGaugeValidator; update its obsolete V2-only NatSpec to this plan without widening its one-method ABI. Preserve the other composed source hashes. Test-only mocks in contracts/mocks remain test fixtures, not deployments.

## 4. Witness authority and census

V1ALIGN-WITNESSES.md is binding at the assertion/cell level. V1ALIGN-WITNESS-INVENTORY.json enumerates EVERY native baseline file:contract:test identity and its retained/ported/retired disposition, including exact V2-twin counterpart mappings. The JSON was derived from both real Forge --list inventories, not a text grep count. Forge's JSON inventory uses bare test names; the additional baseline_signature, target_signature_or_counterpart and target_match_test_regex fields come from native compiled methodIdentifiers. Compare executed signatures with those fields, not bare names or an assumed () suffix for fuzz tests.

Retain all 69 original non-bounty offline identities: 18 admission, 25 settlement, 21 adapters and five AdapterConfigR2 tests. Keep test/bountyfix02/AdapterConfig.t.sol at its exact historical path and retain AdapterConfigR2Test identities; its name is not permission to delete non-bounty protections. Retain all 11 original non-bounty fork identities. Move the eight TrustedFactoryTest identities from test/v2/TrustedFactory.t.sol to test/TrustedFactory.t.sol with their names unchanged, and keep the two fork/TrustedFactory.t.sol runner identities, rewritten to V1/no-bounty fixtures.

Retire 64 V2-twin and 57 bounty offline identities; retire nine bounty fork identities. Consequently, if only these named identities ship, expect 77 offline and 13 fork identities. This is a derived expectation, NOT a quota and not a passing receipt. Extra justified regressions require inventory rows and new actual counts; do not delete a valid witness to hit 77. Missing, accidentally inherited/duplicated or skipped identities block acceptance. Count fuzz identities once, not each run.

No all-green claim may rely on BountyFixture/BountyTestBase/MockBountyHook or BountyForkFixture inheritance. Transplant only needed generic assertion/fixture helpers into a no-test abstract test/TrustedFactoryFixture.sol if needed; move trusted mocks to test/mocks/TrustedFactoryMocks.sol and fix its relative import. Do not inherit a concrete test suite. Remove test/bounty/, test/v2/ after transplant, test/fork/bounty/, and fork/bounty/. Do not delete test/bountyfix02/.

## 5. Required final gates

Apply gates to the exact committed implementation candidate in a clean isolated checkout/archive, with no existing out/cache. Preserve foundry.toml compiler policy: Solidity 0.8.30, optimizer enabled/runs200, no viaIR waiver; default Paris and fork Cancun/chain1. Record resolved relevant config and Forge/compiler versions. No new dependency or compiler-policy change is authorized.

G1. git diff --check and forge fmt --check; build both profiles offline. Keep native stdout/stderr and exit. Warnings are disclosed, not silently called a warning-free build.

G2. Fresh full compiler ABI, methodIdentifiers and recursive layout against V1ALIGN-MANIFEST.json under BOTH profiles. Compare complete arrays/tuples/indexing/mutability/constructors; normalize entry order only. Independently check absent bounty capability and import closure. Compare adapters' full ABI/methodIdentifiers/source/runtime hashes to the same-profile baseline. V1 bytecode MUST change; do not demand old whole-V1 bytecode identity. Its untouched monetary routine source tokens MUST not change.

G3. Native --list --json and full offline suite twice: MAINNET_RPC_URL unset, then explicitly http://127.0.0.1:1. Exact discovered IDs must equal the updated approved inventory; PASS IDs must equal discovered IDs with zero failures/skips. Existing adapter ABI tests read hardcoded out/ paths: run with the fresh default out at that relative path, not a redirected fresh build plus stale out/. Default must not execute fork tests.

G4. All 13 planned fork identities, unchanged block 26401019 / hash 0x55810b079923a14fb97ad548f5024f65530dbc4fb2357a38f41e13b3d27cb6d3 / timestamp1794512471 / chain1, through scripts/test-fork.sh. Fresh isolated HOME with only installed solc copied and no .foundry/cache/rpc; run cold, then warm, then the same wrapper with unreachable RPC (must fail preflight before tests even with cache warm). Use an archive-capable endpoint override, never a block override. Preserve a failed endpoint attempt; retry only the SAME pin with a working endpoint. No code etching, fabricated storage, mocks or skipped live positives. Authority has not waived a network block: implementation acceptance stays HOLD if this gate cannot run. Funding/DAO impersonation remain disclosed fork simulations, never broadcasts or production seating proof.

G5. forge build --offline --sizes for default and fork AND independently decode deployedBytecode.object (strip 0x, reject unresolved placeholders, count bytes including metadata) for CurveGaugeLister, VotiumAdapter, VoteMarketAdapter. Require each runtime <=24,576; record exact size/headroom and creation size separately. Check actual constructor/initcode limit for deployment too. No test-runtime ceiling waiver, alternate profile or optimizer change can substitute for the product gate. Current baseline sizes are in review/v1align/DIFF.md; amended V1 size is UNKNOWN until compiled. Do not manufacture a projected acceptance number.

G6. Execute the named product-only falsifiers in V1ALIGN-WITNESSES.md in disposable copies, with byte-identical final tests and actual nonempty selected native IDs. For each retain pristine-green/mutant-red/restored-green and exact patch. Compiler errors, no-tests-found and unrelated setup failures are not sensitivity. ABI-only corruption checks are separate from behavioral selected reds. No surviving required mutant may be waved away on suite totals.

G7. Apply V1ALIGN-DOC-DELTAS.md verbatim; check exact section extraction against files, deleted bounty docs absent, links/identifiers coherent, shipping paths free of bounty deployment/economic claims. Old review/plan evidence may mention removed mechanisms as history. Produce review/v1align-execution/FINAL.md with exact commit(s), file disposition, native inventories, failures/skips, full gate exits, sizes, ABI/layout/source checks, mutants and deployment-open items. Do not edit this authority evidence to match the implementation.

## 6. Qwen work order — numbered packages, one commit each

Do not merge/squash packages. No implementation broadcast or deploy. Work only on the baseline plus this authority commit; if unrelated work appears, stop and bind the new base before continuing. Commit messages begin v1align:.

1. Core parity and fixture wiring.
   Amend only CurveGaugeLister and ITrustedGaugeValidator as above. Introduce/move the non-bounty trusted mock module. Update ALL V1 constructor sites, including nested failure/alternate-controller/horizon/catch-up tests and both ForkFixture deployment helpers: chain1 before ordinary deployment, explicit healthy code-bearing validator for offline downstream tests, actual pinned validator/code hash for fork tests, owner unpause after binding. Preserve deliberate post-deployment wrong-chain venue tests. Update still-live V2/bounty tests' references to the moved mock and their isolated V1 constructor probe if needed so the intermediate repository compiles. Never weaken original expected reverts or accounting assertions to accommodate changed setup. Run original default suite, both builds, focused trust/core constructor checks if available. Commit: v1align: port non-bounty admission and deployment guards.

2. Trust witnesses without bounty fixtures.
   Port the eight trust identities and two fork identities and their exact non-bounty obligations; add the explicitly named cells in the matrix. Remove the old offline trust file in this move (no duplicate suite). Use original V1 Listing/event and all-FD assertions. Fork fixture carries validator identity independently of bounty dependencies. Run native inventories (intermediate total includes not-yet-retired suites), full default, both fork trust identities through the wrapper and the named trust falsifiers. Commit: v1align: port trusted admission witnesses to the no-bounty core.

3. Retire bounty shipping tree and publish no-bounty docs.
   Delete exactly the product/test/runners listed above after dependency-closure check. Preserve every survivor and historical evidence. Delete docs/BOUNTY-ABI.md and docs/BOUNTY-OPERATIONS.md, create docs/ABI.md and docs/OPERATIONS.md, replace README/proposal/pins exactly from DOC-DELTAS. Mark the old venue intel as historical via the exact provided replacement. Do not blanket-delete a bounty-prefixed directory containing AdapterConfigR2. Re-derive census and run the entire G1–G7 set, including all surviving kill/FD fork tests, both-profile size/ABI guards and remaining safety falsifiers. Commit: v1align: remove bounty product and align public documentation.

4. Evidence and release accounting only.
   No further product/test/doc logic changes. Publish append-only implementation receipts and FINAL.md, inventory/manifest comparisons, final candidate hash and exact commands/exits. Recheck the committed package-3 product in isolation; if a defect needs code changes, fix/amend the responsible unfinalized package and re-run its dependent gates rather than sneaking a change into this evidence package. Commit: v1align: record no-bounty release gates and census.

Implementation release is conditional on these gates, not on an assumed count or historical audit headline. Current authority leg writes plans/ and review/ only. Mainnet rollout still requires independently approved upstream controller authorization, current pin/policy checks, real venue/destination readiness, owner/binding receipts, committed ETH float and a funded trial. Do not describe the fork-only transfer of controller admin as the production GaugeAdder integration.
