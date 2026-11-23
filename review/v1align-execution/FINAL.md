# v1align-execution — FINAL implementation and gate receipt

Status: IMPLEMENTATION GATES COMPLETE for the no-bounty V1 parity candidate. This is **not** deployment
approval: mainnet rollout remains subject to the open items at the end of this file and
plans/V1ALIGN-PLAN.md §6 (deployment authorization, real upstream controller seating, current
pin/venue readiness). No broadcast or deploy was performed in any package.

## 1. Package commits (never merged/squashed; pushed to origin/main throughout)

| Package | Commit | Message |
| --- | --- | --- |
| Baseline | `58944f0` | authority + released work order (e18bee5 lineage) |
| P1 | `803a1bb` | `v1align: port non-bounty admission and deployment guards` |
| P2 | `0cc9d43` | `v1align: port trusted admission witnesses to the no-bounty core` |
| P3 | `cbc52a4` | `v1align: remove bounty product and align public documentation` |
| P4 | (this commit) | `v1align: record no-bounty release gates and census` |

Final candidate hash (package-3 product, rechecked in isolation for every gate): **`cbc52a407473726bec712426f335cc34ef204027`** (P3 commit `cbc52a4`; P4 carries evidence only and changes no product/test/doc logic).

## 2. Toolchain and resolved compiler policy (unchanged)

- forge `1.7.1` (commit `4072e48705af9d93e3c0f6e29e93b5e9a40caed8`, dist, 2026-05-08).
- solc `0.8.30+commit.73712a01.Linux.g++` (`~/.local/share/svm/0.8.30`).
- Default profile: src `contracts`, test `test`, out `out`, optimizer true/200 runs, evm `paris`, via_ir false, `solc_version=0.8.30`.
- Fork profile: test `fork`, out `out-fork`, cache `cache-fork`, evm `cancun`, `chain_id=mainnet`, same optimizer/solc/via-ir.
- Full resolved dumps: `gates/config-resolved.txt`. No dependency added, no compiler-policy change, no waivers.

## 3. File dispositions

### P1 — core parity + fixture wiring (product edits + call-site wiring)
- Modified `contracts/CurveGaugeLister.sol`: seventh-arg `trustedGaugeValidator_` constructor exactly per plan §2.1 (WrongChain first, then owner/code checks incl. validator `NoCode`, decimals, FD checks, immutables, `owner`, `paused = true`, admission/platform validation); `address public immutable trustedGaugeValidator` + generated getter; errors `WrongChain()`, `UntrustedGauge(address)`, `TrustedGaugeCheckFailed(address)`; V2's exact `_requireTrustedGauge` staticcall helper body; `listGauge` calls trust after `_admit`, before readiness/effects/fee/add. `_confiscate` and every monetary routine kept from V1 source; inline `_confiscate` retained.
- Modified `contracts/interfaces/ITrustedGaugeValidator.sol`: obsolete V2-only NatSpec replaced with the V1ALIGN plan reference; one-method ABI unchanged.
- Moved `test/v2/mocks/TrustedFactoryMocks.sol` → `test/mocks/TrustedFactoryMocks.sol` (relative import fixed).
- Constructor sites updated (19 total, all compile+green at each commit): `test/CurveGaugeLister.t.sol` ×9, `test/Settlement.t.sol` ×5 (incl. nested failure/alternate-controller/horizon/mid-catch-up fixtures), `test/Adapters.t.sol` ×2 (incl. `_h01Core`), `test/bountyfix02/AdapterConfig.t.sol` ×1, `test/fork/ForkFixture.sol` ×2 (both trio helpers, actual pin `0x888888…e784` + `_assertValidatorPinAtFork()` before construction, owner unpause after verified bindings), interim-live `test/bounty/thin/Wiring.t.sol` ×1. Offline sites use the disclosed healthy `AlwaysTrueTrustedValidator` stand-in; retained fresh-core `paused` assertions precede explicit owner unpauses; deliberate post-deployment wrong-chain venue tests untouched; no original expected revert or accounting assertion weakened.
- `test/fork/bounty/BountyForkFixture.sol`: `TRUSTED_VALIDATOR`/size/hash constants and `_assertValidatorPinAtFork` moved out to the no-bounty `test/fork/ForkFixture.sol` (kit carries validator identity independently of bounty deps; bounty fixture kept the inherited call until its own P3 deletion).

### P2 — trust witnesses without bounty fixtures
- Created `test/TrustedFactory.t.sol` (`TrustedFactoryTest`, eight identities, names exactly per inventory: `test_TF_ConstructorPinAndGuards`, `test_TF_TrustedPaidAdmissionAndExactTarget`, `test_TF_LegacyFactoryAndNonFactoryPolicy`, `test_TF_UntrustedPaidAdmissionBeforeEffects`, `test_TF_CheckerReadFaultsFailClosed`, `test_TF_RegistryAuthenticationPrecedesTrust`, `test_TF_DaoFreeLaneIsTrustIndependent`, `test_TF_TrustIsAdmissionOnly`) and the no-test abstract `test/TrustedFactoryFixture.sol` (generic world/assertion helpers only; no BountyFixture/BountyTestBase/MockBountyHook inheritance).
- Added matrix cells: `TF_NO_CONSTRUCTOR_CHECK` (reverting code-bearing checker still constructs), `TF_BEFORE_READINESS` (false checker beats unbound AND misbound positive-share venues), `TF_NO_RETROACTIVE_VIEW_GATE`, `TF_NO_RETROACTIVE_FEE_GATE` on TF8; `TF8`'s `_tf8ClaimPath` deleted entirely; hook fields/balances dropped as authorized; owner-paid cell takes an ACTOR-SPECIFIC owner snapshot after owner mint/approval; snapshots carry the original 15-field Listing, totalEscrow, actual actor balances/allowances, core/FD/venue custody, core-to-venue allowances, controller membership/type/raw/scheduled weight/addCalls and touched keyed receipts; rejected paths assert full pre-state equality and no persisted product events.
- Deleted `test/v2/TrustedFactory.t.sol` in the move (no duplicate suite).
- Rewrote `test/fork/ForkTrustedFactory.t.sol` onto the no-bounty `ForkFixture`/`Trio` (validator identity, DAO owner, module code1336/hash, method1/method2 policies, factory/LP/reverse mappings, live true/false predicate controls, retained `GAUGE_SECOND` predicate control and constants copied from the removed bounty fixture provenance only), original V1 `getListing` 15-field and original `EscrowConfiscated(gauge,feeDistributor,amount,receiptWeek)` law; added the missing legacy payer-topic assertion; kept the proxy-shape assertions as structural evidence with the non-identity-proof disclosure; removed the `k.b` binding assertion. `fork/TrustedFactory.t.sol` runner kept outside the recursive default root, same contract/identity names.

### P3 — bounty retirement + documentation
- Deleted exactly the ten manifest product sources (`contracts/CurveGaugeListerV2.sol`, `contracts/GaugeBounty.sol`, `contracts/bounty/BountyTypes.sol`, `contracts/interfaces/{IBountyGovernance,ICurveGaugeListerV2,IGaugeBounty,IOwnershipVoting}.sol`, `contracts/libraries/{BountyRead,BountyScripts,FeeDistributorAccounting}.sol`) after dependency closure; deleted `test/bounty/`, the remaining `test/v2/` (twins), `test/fork/bounty/`, `fork/bounty/` — **kept `test/bountyfix02/` and every survivor**; no executable quarantine under contracts/, test/ or fork/.
- Deleted `docs/BOUNTY-ABI.md`, `docs/BOUNTY-OPERATIONS.md`; created `docs/ABI.md`, `docs/OPERATIONS.md`; applied the five whole-file replacements (README/proposal/ABI/OPERATIONS/pins) verbatim from `plans/V1ALIGN-DOC-DELTAS.md` (byte-identical to the authority block extractions; final newlines included) and the exact literal replacement in `docs/INTEL-YB-HELPERS.md`. Shipping docs carry no reporter/stake/claim sections; historical review/plan receipts were not rewritten.
- `contracts/mocks/` retained as test fixtures; the 11 `unchanged_shared_source_sha256` sources verified byte-identical (adapters, interfaces, SafeToken).

## 4. Native inventory and census honesty

Executed as native `forge test --offline --list --json` inventories plus full-run `[PASS] <signature>` receipts; both bare names and compiled signatures are retained:

- `gates/inventory-77-bare.txt` / `gates/inventory-77-executed-signatures.txt` (offline, 5 suites: 18 CurveGaugeLister + 21 Adapters + 25 Settlement + 5 AdapterConfigR2 + 8 TrustedFactory).
- `gates/inventory-13-fork-bare.txt` / `gates/inventory-13-fork-executed-signatures.txt` (fork profile: Admission 3, Kill 3, Votium 2, VoteMarket 3, TrustedFactory 2).
- Comparators `gates/reconcile.py` runs: default p3 77/77, fork p3 13/13 — **zero missing, zero extra, zero skipped, zero duplicates, zero signature mismatches**.

Actual counts equal the plan's DERIVED expectation 77 offline / 13 fork (69 RETAIN_V1 + 8 PORT_TRUST offline; 11 RETAIN_V1 + 2 PORT_TRUST fork). No new justified regressions were needed, no inventory row was added, and no valid witness was deleted to reach a number. The single baseline fuzz identity (`testFuzz_Thin_CustodyConservation`, bounty) retired with its mechanism; the final suite contains no fuzz identities. Intermediate inventories were reconciled at P1 (198/22, all baseline identities) and P2 (198 with the eight trust identities at their new file, 22 fork).

## 5. Gate exits (run on the exact committed `cbc52a4` product in a clean isolated `git archive` checkout with no pre-existing out/cache)

| Gate | Result | Evidence |
| --- | --- | --- |
| G1 | `git diff --check` clean (repo tree); `forge fmt --check` exit 0; `forge build --offline --sizes --extra-output storageLayout --ast` exit 0 both profiles. **Warnings disclosed, not claimed warning-free**: default build emits 5 warnings (3× mutability 2018 — `test/CurveGaugeLister.t.sol:35`, `test/fork/ForkAdmission.t.sol:65`, `test/TrustedFactory.t.sol:857`; 2× unused-try-catch 5667 — `test/fork/ForkFixture.sol:1167,1197`), fork build 3 (same sites less two). `test/TrustedFactory.t.sol:857` is a warning newly introduced by the ported suite. | `gates/g1-*.txt` |
| G2 | Fresh full compiler ABI (74 entries), `methodIdentifiers` (30) and recursive storage layout compared entry-object-wise against `plans/V1ALIGN-MANIFEST.json` under BOTH profiles: EQUAL, entry order normalized only; tuple components/internalType/mutability/constructor input order/indexing preserved; counts `{constructor:1, function:30, event:10, error:33}`. Absent bounty capability independently checked (`bounty()`, `listingId(…)` absent; no receive/fallback/payable). All 13 shipping sources free of the 12 forbidden tokens; import closure names no retired dependency. Adapter full ABIs/methodIdentifiers/decoded runtime hashes equal to the same-profile baseline expectations (4921/6889 default, 4803/6725 fork bytes, manifest hashes reproduced exactly). V1 whole-bytecode identity NOT demanded: amended core runtime changed to sha256 `2d046bde…` (default) / `2354f7bf…` (fork) with untouched monetary routine source preserved; the mandatory unchanged shared sources hash-match `unchanged_shared_source_sha256`. | `gates/g2_g5_report.json`, `gates/g2_g5.err` |
| G3 | `--list --json` discovered IDs == approved updated inventory (77). Full offline suite TWICE — `MAINNET_RPC_URL` unset then explicitly `http://127.0.0.1:1` — 77 PASS each, 0 failed, 0 skipped; PASS IDs == discovered IDs exactly; default profile executed no fork identity. Adapter artifact tests ran against the FRESH default `out/` built at that relative path inside the candidate (no redirected build over stale artifacts). | `gates/test-unset.txt`, `gates/test-unreachable.txt`, `gates/list-default.json` |
| G4 | All 13 fork identities through `scripts/test-fork.sh` at the unchanged pin — block `26401019`, hash `0x55810b079923a14fb97ad548f5024f65530dbc4fb2357a38f41e13b3d27cb6d3`, timestamp `1794512471`, chain 1: `fork preflight: chainId=0x1 number=0x192d8fb hash=0x55810b079923a14fb97ad548f5024f65530dbc4fb2357a38f41e13b3d27cb6d3 timestamp=0x6af61657` — in a fresh isolated HOME containing only the installed solc (no `.foundry`, no cache): **cold** exit 0 (64.97s wall — real fetches), **warm** exit 0, then the same wrapper with unreachable `http://127.0.0.1:1`: exit 1, failing the preflight with `BLOCKED: RPC … refusing to run fork tests` and NO `Ran N tests for` line even with cache warm. Endpoint override only (`MAINNET_RPC_URL=https://eth-mainnet.public.blastapi.io`); no block override anywhere. The failed historical endpoint attempt is preserved: publicnode served the pinned header (preflight pass) then returned HTTP 403 `Archive requests require a personal token` on archive state reads — both trust identities went suite-RED (never empty-code, never skipped) and the run exited 1: `gates/g4-publicnode-attempt.txt`. No code etching, fabricated storage, mocks on live dependencies, or skipped live positives. Funding/DAO impersonations remain disclosed fork simulations, not broadcasts or production seating proof. | `gates/g4-cold.txt`, `gates/g4-warm.txt`, `gates/g4-unreachable.txt` |
| G5 | `forge build --offline --sizes` exit 0 both profiles, plus INDEPENDENT `deployedBytecode.object` decode (strip 0x, reject unresolved `__` placeholders, count bytes INCLUDING metadata): CurveGaugeLister runtime **15,226 B (headroom 9,350)** default / **14,965 B (headroom 9,611)** fork; VotiumAdapter 4,921/4,803; VoteMarketAdapter 6,889/6,725 — every product runtime ≤ 24,576 with no waiver, no alternate profile, no optimizer change. Creation/initcode recorded separately: 17,588 default / 17,280 fork core (within the 49,152 initcode cap; solc enforced it under Cancun). Amended V1 sizes were unknown before compilation; none was manufactured. | `gates/g1-build-*.txt`, `gates/g2_g5_report.json` |
| G6 | See §6 (behavioral) and §7 (ABI). | `gates/p3-falsify-logs.tar.gz`, `gates/g6-abi-falsifiers.json` |
| G7 | DOC-DELTAS applied verbatim (byte-identical staged copies; deleted bounty docs absent; cross-references resolve within docs/plans/review; shipping paths free of bounty deployment/economic claims — residual 'bounty' mentions in surviving test files are only retirement disclosures). Selector literals in `docs/ABI.md` re-derived with `cast sig`: `trustedGaugeValidator()=0x3ca09961`, `validateGauge(address)=0xe92cd3d3`, `UntrustedGauge(address)=0x6c706dca`, `TrustedGaugeCheckFailed(address)=0x7835e9b7`. | this file, `gates/` |

## 6. Named product-only falsifiers — 26/26

Run inside the disposable copies (`gates/p3_falsifiers.py`, from the archived candidate; tests never mutated — byte-identical final tests, actual non-empty single-test selections `Ran 1 test for`); each row: fresh-baseline pristine green → named compiled mutant RED at the first discriminating label → restored green (`gates/p2-trust-falsify-logs.tar.gz` additionally preserves the earlier 19/19 trust-battery legs at the byte-identical P2 test files). Compiler errors / no-tests-found never counted. Full per-run logs + exact patches in `gates/p3-falsify-logs.tar.gz` (`<id>.patch.txt`, `<id>.*.{pristine,red,restored}.log`); summary `gates/p3-falsifiers-summary.out`.

| ID | Single product mutation | Required witness / first discriminating frame | Restored |
| --- | --- | --- | --- |
| F-TF-CHAIN | Remove constructor chain check | TF1 / TF_CHAIN_FIRST; test_TF_ConstructorPinAndGuards(): TF_CHAIN_FIRST: WrongChain precedes every later guard | green |
| F-TF-CODE | Remove validator code guard | TF1 / TF_PIN_NO_CODE; test_TF_ConstructorPinAndGuards(): TF_PIN_NO_CODE: zero validator must be rejected | green |
| F-TF-PIN | Ignore supplied checker; fixed stand-in pin | TF1 / TF_PIN_EXACT (compiles; constructor assertion reached); test_TF_ConstructorPinAndGuards(): TF_PIN_EXACT: supplied checker retained exactly | green |
| F-TF-PAUSE | Omit paused=true | TF1 / TF_PIN_EXACT paused start; test_TF_ConstructorPinAndGuards(): TF_PIN_EXACT: fresh core starts paused | green |
| F-TF-FALSE | Delete canonical-false rejection | TF4 / TF_FALSE_REJECTS; test_TF_UntrustedPaidAdmissionBeforeEffects(): TF_FALSE_REJECTS: canonical false exact error: expected revert with the named error, call succeeded | green |
| F-TF-FAULT | Return normally on failed staticcall | TF5 / TF_READ_FAULT_REJECTS; test_TF_CheckerReadFaultsFailClosed(): TF_READ_FAULT_REJECTS: top-level revert: expected revert with the named error, call succeeded | green |
| F-TF-LENGTH | Exact-32 guard to data.length<32 | TF5 / TF_EXACT_RETURN_LENGTH; test_TF_CheckerReadFaultsFailClosed(): TF_EXACT_RETURN_LENGTH: 64-byte true-with-tail: expected revert with the named error, call succeeded | green |
| F-TF-BOOL | Remove verdict>1 rejection | TF5 / TF_CANONICAL_BOOL; test_TF_CheckerReadFaultsFailClosed(): TF_CANONICAL_BOOL: word 2: expected revert with the named error, call succeeded | green |
| F-TF-ARG | Call validator with pool instead of gauge | TF2 / TF_EXACT_GAUGE_ARGUMENT; test_TF_TrustedPaidAdmissionAndExactTarget(): TF_EXACT_GAUGE_ARGUMENT: only the exact gauge is accepted and admitted: unexpected revert, data 7835e9b70000000000000... | green |
| F-TF-SELECTOR | Encode validateProposalGauges(uint256) | TF2 / TF_EXACT_GAUGE_ARGUMENT; test_TF_TrustedPaidAdmissionAndExactTarget(): TF_EXACT_GAUGE_ARGUMENT: only the exact gauge is accepted and admitted: unexpected revert, data 7835e9b70000000000000... | green |
| F-TF-AFTER-ADD | Move trust after controller.add_gauge | TF4 / TF_BEFORE_ADD_GAUGE; test_TF_UntrustedPaidAdmissionBeforeEffects(): TF_BEFORE_ADD_GAUGE: trust error precedes the poisoned add_gauge | green |
| F-TF-AFTER-FEE | Move trust after fee pull before add_gauge | TF4 / TF_BEFORE_TRANSFER (controller-poison cell stayed green); test_TF_UntrustedPaidAdmissionBeforeEffects(): TF_BEFORE_TRANSFER: trust error precedes the poisoned transferFrom | green |
| F-TF-AFTER-READY | Move trust after platform readiness | TF4 / TF_BEFORE_READINESS (added cell); test_TF_UntrustedPaidAdmissionBeforeEffects(): TF_BEFORE_READINESS: false checker beats unbound/misbound venues | green |
| F-TF-REGISTRY | Move trust before _admit | TF6 / TF_REGISTRY_FIRST; test_TF_RegistryAuthenticationPrecedesTrust(): TF_REGISTRY_FIRST: registry authentication precedes the trust read | green |
| F-TF-OWNER | Skip trust when msg.sender==owner | TF4 / TF_OWNER_PAID_NOT_EXEMPT (funded owner); test_TF_UntrustedPaidAdmissionBeforeEffects(): TF_OWNER_PAID_NOT_EXEMPT: owner pays the same law: expected revert with the named error, call succeeded | green |
| F-TF-FREE | Add trust to listGaugeNoEscrow | TF7 / TF_DAO_NO_CHECKER_DEPENDENCE; test_TF_DaoFreeLaneIsTrustIndependent(): TF_DAO_NO_CHECKER_DEPENDENCE: false checker does not gate the free lane: unexpected revert, data 6c706dca000000000000... | green |
| F-TF-RETRO | Add trust to active checkpoint | TF8 / TF_NO_RETROACTIVE_DRIP_GATE (no setup failure); test_TF_TrustIsAdmissionOnly(): TF_NO_RETROACTIVE_DRIP_GATE: settlement of an admitted gauge performs no trust read: unexpected revert, data 7835e9b7... | green |
| F-TF-RECORD | Remove paid rec.votium assignment | TF2 / TF_TRUSTED_PAID_ACTIVE configured venue; test_TF_TrustedPaidAdmissionAndExactTarget(): TF_TRUSTED_PAID_ACTIVE: votium is the configured venue | green |
| F-TF-FREE-EVENT | Remove DAO-free GaugeListed emission | TF7 / TF_DAO_NO_FACTORY_ALLOWED complete event; test_TF_DaoFreeLaneIsTrustIndependent(): TF_DAO_NO_FACTORY_ALLOWED: free-lane GaugeListed emitted | green |
| F-NB-SPLIT | Send only half R to FD | test_KillAtEachReleaseCount exact FD delta; test_KillAtEachReleaseCount(): ConfiscationDeltaMismatch() | green |
| F-NB-WEIGHT | Restore controller-weight-zero as kill signal | test_WeightZeroWithoutKilledFlagDoesNotConfiscate (seizure attempt reached); test_WeightZeroWithoutKilledFlagDoesNotConfiscate(): CannotCheckpoint() | green |
| F-NB-HORIZON | Use t rather than epochStart(t) in freshness bound | test_AuditM01_AccountingHorizonIncludesPartialWeekEdges H+1 near-end; test_AuditM01_AccountingHorizonIncludesPartialWeekEdges(): next call did not revert as expected | green |
| F-NB-ACCOUNT | Swallow mandatory checkpoint failure; drop postconditions | test_CheckpointCooldownRevertsConfiscationUntilAccountingEligible AND test_AuditM01_MidCatchUpAccountingFailureRollsBackEarlierQuarter; test_AuditM01_MidCatchUpAccountingFailureRollsBackEarlierQuarter(): next call did not revert as expected; test_CheckpointCooldownRevertsConfiscationUntilAccountingEligible(): next call did not revert as expected | green |
| F-NB-POST | Remove token_last_balance postcheck only | test_AuditM01_InvalidCursorAndIncompleteCheckpointRevert cursor-only cell; test_AuditM01_InvalidCursorAndIncompleteCheckpointRevert(): next call did not revert as expected | green |
| F-NB-BIND-VOTIUM | Remove onlyOwner from VotiumAdapter.setLister | test_Adapter_VotiumNonListerAndBindingRejects outsider-bind refusal; test_Adapter_VotiumNonListerAndBindingRejects(): next call did not revert as expected | green |
| F-NB-BIND-VOTEMARKET | Remove onlyOwner from VoteMarketAdapter.setLister | test_AuditH01_VoteMarketCaptureCannotSpendEthFloat outsider-bind refusal; test_AuditH01_VoteMarketCaptureCannotSpendEthFloat(): next call did not revert as expected | green |

Exact mutant patches (OLD → NEW) as executed:

```
file: contracts/CurveGaugeLister.sol

OLD:
        if (block.chainid != 1) revert WrongChain();

NEW:
```
```
file: contracts/CurveGaugeLister.sol

OLD:
        if (trustedGaugeValidator_.code.length == 0) revert NoCode(trustedGaugeValidator_);

NEW:
```
```
file: contracts/CurveGaugeLister.sol

OLD:
        trustedGaugeValidator = trustedGaugeValidator_;
NEW:
        trustedGaugeValidator = 0x888888c34a46d0b2A34e9204e5273208E670e784; // MUTANT F-TF-PIN
```
```
file: contracts/CurveGaugeLister.sol

OLD:
        owner = owner_;
        paused = true;

NEW:
        owner = owner_;
```
```
file: contracts/CurveGaugeLister.sol

OLD:
        if (verdict == 0) revert UntrustedGauge(gauge);

NEW:
```
```
file: contracts/CurveGaugeLister.sol

OLD:
        if (!ok) revert TrustedGaugeCheckFailed(gauge);
NEW:
        if (!ok) return; // MUTANT F-TF-FAULT
```
```
file: contracts/CurveGaugeLister.sol

OLD:
        if (data.length != 32) revert TrustedGaugeCheckFailed(gauge);
NEW:
        if (data.length < 32) revert TrustedGaugeCheckFailed(gauge); // MUTANT F-TF-LENGTH
```
```
file: contracts/CurveGaugeLister.sol

OLD:
        if (verdict > 1) revert TrustedGaugeCheckFailed(gauge);

NEW:
```
```
file: contracts/CurveGaugeLister.sol

OLD:
        _requireTrustedGauge(gauge);

        // auditfix001
NEW:
        _requireTrustedGauge(pool); // MUTANT F-TF-ARG

        // auditfix001
```
```
file: contracts/CurveGaugeLister.sol

OLD:
trustedGaugeValidator.staticcall(abi.encodeCall(ITrustedGaugeValidator.validateGauge, (gauge)));
NEW:
trustedGaugeValidator.staticcall(abi.encodeWithSelector(bytes4(0x2da285c4), uint256(uint160(gauge)))); // MUTANT F-TF-SELECTOR
```
```
file: contracts/CurveGaugeLister.sol

OLD:

        // V1ALIGN §2.1 ordering: exactly here, after `_admit` returns and
        // before readiness, listing write, `totalEscrow` accounting, fee
        // transfer or `controller.add_gauge`.
        _requireTrustedGauge(gauge);

NEW:


OLD:
        if (IListingController(controller).gauge_types(gauge) != derivedType) revert MembershipFailed();

        emit GaugeListed(gauge, pool, msg.sender, derivedType, rec.listingEpoch, FEE, false);
NEW:
        if (IListingController(controller).gauge_types(gauge) != derivedType) revert MembershipFailed();
        _requireTrustedGauge(gauge); // MUTANT F-TF-AFTER-ADD

        emit GaugeListed(gauge, pool, msg.sender, derivedType, rec.listingEpoch, FEE, false);
```
```
file: contracts/CurveGaugeLister.sol

OLD:

        // V1ALIGN §2.1 ordering: exactly here, after `_admit` returns and
        // before readiness, listing write, `totalEscrow` accounting, fee
        // transfer or `controller.add_gauge`.
        _requireTrustedGauge(gauge);

NEW:


OLD:
        IListingController(controller).add_gauge(gauge, derivedType, INITIAL_WEIGHT);
NEW:
        _requireTrustedGauge(gauge); // MUTANT F-TF-AFTER-FEE
        IListingController(controller).add_gauge(gauge, derivedType, INITIAL_WEIGHT);
```
```
file: contracts/CurveGaugeLister.sol

OLD:

        // V1ALIGN §2.1 ordering: exactly here, after `_admit` returns and
        // before readiness, listing write, `totalEscrow` accounting, fee
        // transfer or `controller.add_gauge`.
        _requireTrustedGauge(gauge);

NEW:


OLD:
        _requirePlatformsReady(plat);
NEW:
        _requirePlatformsReady(plat);
        _requireTrustedGauge(gauge); // MUTANT F-TF-AFTER-READY
```
```
file: contracts/CurveGaugeLister.sol

OLD:

        // V1ALIGN §2.1 ordering: exactly here, after `_admit` returns and
        // before readiness, listing write, `totalEscrow` accounting, fee
        // transfer or `controller.add_gauge`.
        _requireTrustedGauge(gauge);

NEW:


OLD:
        (address lpToken, int128 derivedType) = _admit(pool, gauge, gaugeIndex, handlerId, cfg);

        // auditfix001
NEW:
        _requireTrustedGauge(gauge); // MUTANT F-TF-REGISTRY
        (address lpToken, int128 derivedType) = _admit(pool, gauge, gaugeIndex, handlerId, cfg);

        // auditfix001
```
```
file: contracts/CurveGaugeLister.sol

OLD:
        _requireTrustedGauge(gauge);

        // auditfix001
NEW:
        if (msg.sender != owner) _requireTrustedGauge(gauge); // MUTANT F-TF-OWNER

        // auditfix001
```
```
file: contracts/CurveGaugeLister.sol

OLD:
        if (msg.sender != owner) revert NotOwner();
        AdmissionConfig memory cfg = _admissionConfig;
        (address lpToken, int128 derivedType) = _admit(pool, gauge, gaugeIndex, handlerId, cfg);
NEW:
        if (msg.sender != owner) revert NotOwner();
        AdmissionConfig memory cfg = _admissionConfig;
        (address lpToken, int128 derivedType) = _admit(pool, gauge, gaugeIndex, handlerId, cfg);
        _requireTrustedGauge(gauge); // MUTANT F-TF-FREE
```
```
file: contracts/CurveGaugeLister.sol

OLD:
        if (st != Status.Active) return (0, 0);

NEW:
        if (st != Status.Active) return (0, 0);
        _requireTrustedGauge(gauge); // MUTANT F-TF-RETRO
```
```
file: contracts/CurveGaugeLister.sol

OLD:
        rec.votium = plat.votium;

NEW:
```
```
file: contracts/CurveGaugeLister.sol

OLD:
        emit GaugeListed(gauge, pool, address(0), derivedType, rec.listingEpoch, 0, true);

NEW:
```
```
file: contracts/CurveGaugeLister.sol

OLD:
        SafeToken.safeTransfer(crvUSD, fd, amount);
NEW:
        SafeToken.safeTransfer(crvUSD, fd, amount / 2); // MUTANT F-NB-SPLIT
```
```
file: contracts/CurveGaugeLister.sol

OLD:
        return ICurveGauge(gauge).is_killed();
NEW:
        return ICurveGauge(gauge).is_killed() || IListingController(controller).get_gauge_weight(gauge) == 0; // MUTANT F-NB-WEIGHT
```
```
file: contracts/CurveGaugeLister.sol

OLD:
        if (block.timestamp - epochStart(t) > 20 * WEEK) revert DistributorUnusable();
NEW:
        if (block.timestamp - t > 20 * WEEK) revert DistributorUnusable(); // MUTANT F-NB-HORIZON
```
```
file: contracts/CurveGaugeLister.sol

OLD:
        IFeeDistributor(fd).checkpoint_token();
        if (IFeeDistributor(fd).last_token_time() != block.timestamp) revert DistributorUnusable();
        if (IFeeDistributor(fd).token_last_balance() != IERC20Minimal(crvUSD).balanceOf(fd)) {
            revert DistributorUnusable();
        }

NEW:
        try IFeeDistributor(fd).checkpoint_token() {} catch {} // MUTANT F-NB-ACCOUNT
```
```
file: contracts/CurveGaugeLister.sol

OLD:
        if (IFeeDistributor(fd).token_last_balance() != IERC20Minimal(crvUSD).balanceOf(fd)) {
            revert DistributorUnusable();
        }

NEW:
```
```
file: contracts/adapters/VotiumAdapter.sol

OLD:
    function setLister(address lister_) external onlyOwner {
NEW:
    function setLister(address lister_) external { // MUTANT F-NB-BIND-VOTIUM
```
```
file: contracts/adapters/VoteMarketAdapter.sol

OLD:
    function setLister(address lister_) external onlyOwner {
NEW:
    function setLister(address lister_) external { // MUTANT F-NB-BIND-VOTEMARKET
```

No required mutant survived; none was waved away on suite totals.

## 7. ABI falsifiers (separate from behavioral reds)

Independent entry-object comparator (same keyed logic as G2; a selector-only map demonstrably blind to the event-indexing case) on disposable compiler-ABI JSONs: pristine accepted; each of append-unexpected-callable, constructor-order swap, appended Listing field, confiscation-event indexing change, removed surfaced error, changed mutability REJECTED; a shipping source importing a retired dependency is REJECTED by the closure check while the real tree passes (`gates/g6-abi-falsifiers.json`, 10/10 true).

## 8. Deployment-open items (expressly unapproved; unchanged from authority)

- Current pin/source/role + validator-policy re-verification at a freshly recorded block (validator owner/managers, factory/module policies, actual candidate predicates; code presence ≠ authenticity).
- Independently approved upstream controller authorization for the exact lister→`add_gauge` path; real GaugeAdder seating (the fork-only impersonated admin transfer is NOT that integration).
- Owner-authenticated one-time adapter bindings by the ACTUAL adapter owners; two-step ownership completion; committed VoteMarket ETH float; Votium crvUSD acceptance/round timing; remote VoteMarket whitelist/periods and destination-chain delivery verification.
- FeeDistributor public-checkpoint availability + strict cooldown window, 20-week horizon cursor, safe mandatory accounting at send time.
- Assigned operational roles, funded trial listing, current venue/destination readiness, emergency-kill route verification through the real authority (never contingent on confiscation).

Nothing in this execution broadcast, deployed, or represented a migration/upgrade. Historical receipts under `review/` and `plans/` were not edited to match the implementation; this file is append-only candidate-bound evidence.
