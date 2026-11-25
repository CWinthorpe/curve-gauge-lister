# CurveGaugeLister — no-bounty interface

This reference describes the v1align target. The complete normative ABI manifest, the fresh-compiler ABI/method-identifier comparisons under both profiles and the layout receipts are held by the project owner inside the candidate-bound release evidence package and producible on demand; a disagreement between the contract and that manifest blocks release, and neither this prose nor a matching function count silently overrides the contract.

## Constructor and tuples

Nonpayable constructor, in exact order:

`(address owner_,address crvUSD_,address controller_,address feeDistributor_,AdmissionConfig admission_,PlatformConfig platforms_,address trustedGaugeValidator_)`

- `AdmissionConfig`: `(address registry,uint8 maxCoins)`.
- `PlatformConfig`: `(address votium,address voteMarket,uint16 votiumBps)`.
- `Listing`: `(address pool,address lpToken,address payer,address admissionRegistry,int128 gaugeType,uint256 listingEpoch,uint8 status,uint8 epochsReleased,uint256 deposited,uint256 remaining,uint256 released,uint256 confiscated,address votium,address voteMarket,uint16 votiumBps)`.

`status`: Unlisted=0, Active=1, Exhausted=2, Confiscated=3, DaoExempt=4. Unknown `getListing` returns the all-zero tuple. A DAO-exempt record has zero monetary fields and platform snapshots. `confiscated` is the entire amount sent to the fixed FeeDistributor, not a gross split allocation. The gauge is the mapping key; no separate listing-ID API exists.

Chain 1 is checked first. The owner must be nonzero; the token/controller/FD/validator must have code; crvUSD decimals are 18; FD token and not-killed checks plus admission/platform validation apply. The core starts paused. Validator and positive-share adapters need not accept a candidate or be bound during construction; paid readiness is enforced at admission. The seventh argument is the validator, with no reserved extra argument.

## Complete callable core surface (30)

Nonpayable mutators:

- `listGauge(address pool,address gauge,uint256 gaugeIndex,uint256 handlerId)` -> `()`
- `listGaugeNoEscrow(address pool,address gauge,uint256 gaugeIndex,uint256 handlerId,uint256 initialWeight)` -> `()`
- `checkpoint(address gauge)` -> `(uint256 releasedNow,uint256 confiscatedNow)`
- `confiscate(address gauge)` -> `(uint256 amount)`
- `checkpointFees()` -> `(bool checkpointed)`
- `setPaused(bool paused_)` -> `()`
- `setAdmissionConfig((address registry,uint8 maxCoins) config)` -> `()`
- `setPlatformConfig((address votium,address voteMarket,uint16 votiumBps) config)` -> `()`
- `transferOwnership(address newOwner)` -> `()`
- `acceptOwnership()` -> `()`

Views:

- `BPS()`, `EPOCHS()`, `FEE()`, `INITIAL_WEIGHT()`, `QUARTER()`, `WEEK()` -> `uint256` each.
- `controller()`, `crvUSD()`, `feeDistributor()`, `owner()`, `pendingOwner()`, `trustedGaugeValidator()` -> `address` each.
- `paused()` -> `bool`.
- `totalEscrow()` -> `uint256`.
- `getAdmissionConfig()` -> `AdmissionConfig`.
- `getPlatformConfig()` -> `PlatformConfig`.
- `getListing(address gauge)` -> `Listing`.
- `epochsElapsed(address gauge)` -> `uint256`.
- `releasable(address gauge)` -> `uint256`.

Monetary views are gross escrow accounting, not venue-delivery or funded-execution quotes: `releasable` is the current status/flag-conditioned gross matured-unpaid projection; `remaining` is the Active unreleased liability; `totalEscrow` is the aggregate paid Active liability, not surplus and not a guarantee that a venue or the FeeDistributor can currently execute; `epochsElapsed` is capped age under the four-quarter schedule, not a count of funded quarters.

`releasable` kill-flag semantics: a non-Active record returns zero without consulting the gauge, and an Active listing whose readable `is_killed()` flag is true also returns zero. For an Active gauge whose kill-flag read or decode fails, `releasable` does not coerce the failure to zero — the view itself fails. A consumer scheduling releases must not silently interpret that failed view as no amount due, as a kill, or as executable readiness; it must surface the failure and decide separately. This product ships no scheduler and none is implied here.

Pure:

- `epochStart(uint256 timestamp)` -> `uint256`.

There is no payable core entrypoint, receive or fallback. Owner setters and two-step transfer cannot move funds, replace immutable destinations, alter existing listing snapshots or execute arbitrary calls.

## Events (10)

- `GaugeListed(address indexed gauge,address indexed pool,address indexed payer,int128 gaugeType,uint256 listingEpoch,uint256 fee,bool daoExempt)`
- `PlatformDeposit(address indexed gauge,address indexed platform,uint256 indexed scheduledEpoch,uint256 executionEpoch,uint256 amount,bytes32 receipt)`
- `QuarterReleased(address indexed gauge,uint256 indexed scheduledEpoch,uint256 amount,uint256 remaining)`
- `EscrowConfiscated(address indexed gauge,address indexed feeDistributor,uint256 amount,uint256 receiptWeek)`
- `FeeCheckpointResult(bool success)`
- `PauseSet(bool paused)`
- `AdmissionConfigSet(address registry,uint8 maxCoins)`
- `PlatformConfigSet(address votium,address voteMarket,uint16 votiumBps)`
- `OwnershipTransferStarted(address indexed owner,address indexed pendingOwner)`
- `OwnershipTransferred(address indexed previousOwner,address indexed newOwner)`

Successful confiscation emits `EscrowConfiscated` then `FeeCheckpointResult(true)` after exact custody and mandatory accounting succeed. `EscrowConfiscated` is the completion signal for escrow accounting (CX-MAINT, current ABI): the mandatory same-transaction accounting postchecks have already passed when it commits. `FeeCheckpointResult` carries two documented meanings under this ABI — standalone best-effort maintenance telemetry from the retained `checkpointFees()` wrapper, and retained compatibility telemetry emitted after `EscrowConfiscated` on the confiscation path — and neither is separately load-bearing accounting evidence beyond the fields it names. Its receipt week is the transfer's week floor, not a promise that all fees enter one upstream week bucket. A standalone `checkpointFees` result reports only whether that upstream call returned; the wrapper's Boolean, its failure log and the caller identity are not equivalent to a direct FeeDistributor maintenance call (which stays available under the documented ordinary-caller policy), and no local change removes upstream shared-window contention.

`PlatformDeposit.amount` and `QuarterReleased.amount` are gross escrow expenditure — the amount pulled from escrow toward the platform, not a measured net venue reward: the independently observed net reward plus the current platform fee equals gross at the pinned Votium venue, and no fixed future fee, net reward or guaranteed vote count is promised; a VoteMarket deposit records funded L1 ingress, not L2 delivery.

## Errors (33, including shared token errors)

No-argument errors:

`BadAdmissionConfig()`, `BadCoin()`, `BadCoinCount()`, `BadGaugeType()`, `BadLpToken()`, `BadPlatformConfig()`, `ConfiscationDeltaMismatch()`, `DistributorUnusable()`, `FeeDeltaMismatch()`, `GaugeKilledAtAdmission()`, `GaugeMismatch()`, `IndexOutOfRange()`, `ListingsPaused()`, `MembershipFailed()`, `NotOwner()`, `NotPendingOwner()`, `PoolNotRegistered()`, `Reentrancy()`, `WrongChain()`, `ZeroOwner()`, `ZeroTarget()`.

`BadAdmissionConfig()` diagnostic note: this error is not limited to invalid registry/maxCoins configuration. A successfully decoded constructor `decimals()` return other than 18 also reverts with `BadAdmissionConfig()`. Diagnose by call context — construction versus a `setAdmissionConfig`/admission-validation site imply different candidate causes. A dependency call or decode failure (for example a `decimals()` call that reverts or returns malformed data) need not produce this local error, and not every constructor failure shares this diagnostic. No rename or new error is introduced.

Address-bearing product errors:

`AlreadyListed(address gauge)`, `ControllerRegistryOccupied(address gauge)`, `NoCode(address target)`, `PlatformDeltaMismatch(address platform)`, `PlatformNotReady(address platform)`, `PlatformReceiptMissing(address platform)`, `TrustedGaugeCheckFailed(address gauge)`, `UnknownGauge(address gauge)`, `UntrustedGauge(address gauge)`.

Shared errors:

`SafeTokenBadReturn(address token)`, `SafeTokenCallFailed(address token)`, `SafeTokenNoCode(address token)`.

Shared-token error boundary: a successful call returning empty data, or a
canonical 32-byte `true` word, is accepted. A `false` return, or any nonempty
return whose length is not exactly 32 bytes, reaches `SafeTokenBadReturn`. A
length-32 word that is not a canonical Boolean can revert inside the decoder
before `SafeTokenBadReturn` is reached. A failed low-level call is wrapped in
`SafeTokenCallFailed`; dependency revert bytes are not bubbled through.
`SafeTokenNoCode` covers an interaction attempted against an address without
deployed code.

The new getter selector is `trustedGaugeValidator() = 0x3ca09961`. The only validator predicate used is `validateGauge(address) = 0xe92cd3d3`, with the candidate gauge as its argument. A successful exact-32-byte zero returns `UntrustedGauge(address) = 0x6c706dca`; call failure, nonexact length or a word greater than one returns `TrustedGaugeCheckFailed(address) = 0x7835e9b7`. Only word one passes. The external validator's internal faults may collapse to false and therefore yield UntrustedGauge. Out-of-gas and other dependency ABI failures need not have a uniform custom error.

## Adapter interfaces and invariant boundary

The full unchanged VotiumAdapter and VoteMarketAdapter ABIs/method identifiers are included in the manifest. Their constructors remain `(address crvUSD_,address owner_,address votium_)` and `(address crvUSD_,address owner_,address campaignRemoteManager_,address votemarket_)`, respectively.

Both implement `rewardToken()`, `lister()` and `deposit(address gauge,uint256 scheduledEpoch,uint256 amount) returns (bytes32 receipt)`. `setLister(address)` is owner-authenticated and write-once. They accept deposits only from that bound core, use exact bounded token approvals and clear allowances (a zero approval request is one checked zero approval; the final allowance is always cleared to zero). VoteMarket also accepts native ETH through `receive()` as committed message float; neither adapter exposes withdrawal, rescue or arbitrary execution. Its `getDeposit`, `depositCount` and `depositAt` expose recorded L1 ingress from the adapter's own chain-1 log — receipt values are opaque adapter-domain identifiers (a keccak tuple plus a local ordinal) attested by the emitting adapter and its deposit events, not proof of asynchronous destination delivery. The compiled-ABI allowlist witness in `test/Adapters.t.sol` checks the fresh artifact's signature-key set against the intended allowlist in both directions plus one no-fallback calldata probe; it does not attest deployed-byte equality or enumerate the dispatcher — the exact runtime/immutables byte comparison is a distinct release gate recorded with the release evidence package (see `README.md`). See `OPERATIONS.md` for mutable venue settings, gas arithmetic and residual-loss limits.


## GaugeControllerAdmin — fixed-authority DAO controller router (role R)

This is the additional shipped contract of the selected composition; every core/adapter description above is unchanged by it. The router is a new standalone manifest: the lister's three-function dependency subset in `contracts/interfaces/IListingController.sol` was not widened, and R declares its narrow controller interface locally (zero imports, exact `pragma solidity 0.8.30`). Compiled-surface equality against this section and the normative manifest is an owner-held candidate gate; this prose does not substitute for that comparison.

### Constructor

`(address controller_,address dao_)`, nonpayable. Both parameters are explicit, never derived from `msg.sender`/`tx.origin`, and stored as embedded immutables. Construction rejects `controller_ == 0` or `== address(this)` with `InvalidController(controller_)`, a code-less `controller_` with `NoCode(controller_)`, and `dao_` equal to zero, `address(this)` or `controller_` with `InvalidDao(dao_)`. There is deliberately no requirement that `controller_`'s admin be R at construction (deployment precedes installation), no requirement that `dao_` have code in the reusable ABI (production verification must pin its literal D address, chain 1 and real governance route separately), no auto-grants, no token calls, no value acceptance and no authority transfer.

### Storage

`controller` and `dao` are embedded immutables (no slots). `isAdder` is `mapping(address=>bool)` at slot 0 (key location `keccak256(abi.encode(key,uint256(0)))`); `pendingControllerAdmin` is an `address` at slot 1 offset 0; `retired` is a `bool` at slot 1 offset 20; the single mutual-exclusion word `_lock` is a `uint256` at slot 2, initially 1 (idle), 2 while entered. There are no other persistent fields: no adder array, no lister economics record, no controller cache, no epoch/budget/nonce/fee/allowance/delegate state. The public mapping plus `AdderSet` logs allow off-chain enumeration; the adder set at any release pin must be reconstructed from deployment logs and re-read, because no getter grants more than the rules below.

### Complete callable surface (12 external functions, 5 events, 14 declared errors)

Views/getters (public, lock-free, callable after retirement; they confer no write capability):

- `controller()` -> `address` (immutable C)
- `dao()` -> `address` (immutable D)
- `isAdder(address)` -> `bool` (raw grant flag; history, not a promise of present capability after retirement or authority loss)
- `pendingControllerAdmin()` -> `address` (local fresh nomination; zero means no fresh R-authorized commit)
- `retired()` -> `bool` (permanent lifecycle latch)
- `gauge_types(address)` -> `int128` — typed STATICCALL read-through to C; a valid stored zero is preserved, an absent gauge reverts with C's exact upstream bytes (including an empty revert), and a malformed upstream return reverts rather than fabricating membership
- `n_gauge_types()` -> `int128` — typed read-through of C's canonical exclusive type bound

Nonpayable mutators (authority checked first, then retirement, then the single shared lock):

- `grant(address adder,bool enabled)` — D only; rejects `adder` equal to zero, R, C or D with `InvalidAdder(adder)` before any effect; writes the flag and emits `AdderSet(adder,enabled)` even when unchanged. Usable after deployment but before seating: `grant` is an authorization-key lane, not a controller-mutating lane.
- `add_gauge(address gauge,int128 gaugeType,uint256 weight)` — D or a currently granted `msg.sender` (`NotAdder(caller)` otherwise); additionally requires C.admin() == R at R's own guard (`NotControllerAdmin(actual)`; that revert is R's guard, never a reached raw call). Synchronous `C.add_gauge` with the exact arguments — R adds no type/weight clamp, fee, validator, pool, pause, gauge-code or registry policy — and emits `GaugeAdded` only after C returns.
- `execute(bytes data)` — D only. One ordinary zero-value CALL whose destination is only the immutable C: the ABI carries no target and no value. It is arbitrary valid CONTROLLER function execution, not arbitrary-target forwarding. Ownership selectors are mediated (below); every other payload reaches C unchanged, keeps C's exact return bytes, and bubbles C's failure bytes exactly, including an empty revert. `Executed` is emitted only on success, hashing the full input and returned byte arrays; it is an audit record, not a governance approval, fee receipt or emissions event, and never substitutes for the raw controller's own events.
- `commit_transfer_ownership(address successor)` — D only; the shared commit.
- `apply_transfer_ownership()` — D only; the shared apply.

There is no receive or fallback function; no other external entry exists.

### Ownership encoding rule

`execute(bytes)` decodes only the leading inner selector. For `commit_transfer_ownership(address)` the complete input must be exactly 36 bytes with a canonical 160-bit address word (upper bits zero); for `apply_transfer_ownership()` exactly 4 bytes. Anything else fails with `InvalidOwnershipCalldata()` before any C call, state write or log. Valid ownership payloads route to the SAME internal commit/apply state machine as the typed methods (returning empty bytes; the ownership event precedes `Executed`) — no raw-call escape bypasses retirement. `Executed` uses `selector = 0` for inputs shorter than four bytes.

### Shared commit/apply law

Commit requires C.admin() == R (`NotControllerAdmin`), rejects successor zero/R/C (`InvalidSuccessor`), sets the local nomination, calls C.commit as R, requires `C.future_admin()` to equal the nomination (`PendingAdminMismatch(expected,actual)`) and emits `ControllerTransferCommitted`. Any failure rolls back local and C effects together (same transaction). Apply requires C.admin() == R and a fresh local nomination (`NoPendingTransfer`) — C's `future_admin` is stale after seating and is never proof — then saves the successor, clears the nomination, latches `retired = true` BEFORE the external `C.apply_transfer_ownership()` as the incumbent, requires `C.admin()` to equal the successor (`ControllerAdminMismatch(expected,actual)`) and emits `ControllerTransferApplied`. Any revert/postcondition failure rolls back retirement, nomination, controller state and logs together. Both steps are incumbent-only; a pending successor never accepts. Two-step does not mean two transactions or a delay.

### Lifecycle limits and funding boundary

After a successful handback apply, ALL mutations revert permanently with `Retired()` — including `grant` and generic `execute` of otherwise-public controller functions — even when called by D; stale grant flags are history, not capability. Canonical reads survive. There is no selfdestruct and no revival/rescue/accept/cancel/rename surface; a pending transfer neither transfers authority nor pauses adds, and D may leave a nomination pending or replace it with another valid successor. Production handback policy revokes delegated adders first; the state machine deliberately does not require that, and retirement never erases historical grant flags. A retired router must never be reseated. R has no intended custody or money-handling path (nonpayable everywhere, zero-value C calls, no deposit/withdrawal/rescue/sweep/approve API and no balance-dependent behavior), but forced ETH and unsolicited ERC20 balances can arrive and remain stranded: they create no privilege, block no operation, and no recovery API exists or may be assumed. Upstream reverts bubble unwrapped; standard ABI-decoding and nonpayable/unknown-selector rejections are compiler behavior, not additional declared errors.

### Errors (14, exact)

No-argument: `Retired()`, `ReentrantCall()`, `InvalidOwnershipCalldata()`. Address-bearing: `InvalidController(address controller)`, `NoCode(address target)`, `InvalidDao(address dao)`, `NotDao(address caller)`, `NotAdder(address caller)`, `NotControllerAdmin(address actual)`, `InvalidAdder(address adder)`, `InvalidSuccessor(address successor)`, `NoPendingTransfer()`. Two-address: `PendingAdminMismatch(address expected,address actual)`, `ControllerAdminMismatch(address expected,address actual)`.

### Events (5, exact)

`AdderSet(address indexed adder,bool enabled)`, `GaugeAdded(address indexed caller,address indexed gauge,int128 gaugeType,uint256 weight)`, `Executed(bytes4 indexed selector,bytes32 calldataHash,bytes32 returndataHash)`, `ControllerTransferCommitted(address indexed successor)`, `ControllerTransferApplied(address indexed successor)`.
