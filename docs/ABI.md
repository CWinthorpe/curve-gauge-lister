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

## Errors (33, including shared token errors)

No-argument errors:

`BadAdmissionConfig()`, `BadCoin()`, `BadCoinCount()`, `BadGaugeType()`, `BadLpToken()`, `BadPlatformConfig()`, `ConfiscationDeltaMismatch()`, `DistributorUnusable()`, `FeeDeltaMismatch()`, `GaugeKilledAtAdmission()`, `GaugeMismatch()`, `IndexOutOfRange()`, `ListingsPaused()`, `MembershipFailed()`, `NotOwner()`, `NotPendingOwner()`, `PoolNotRegistered()`, `Reentrancy()`, `WrongChain()`, `ZeroOwner()`, `ZeroTarget()`.

Address-bearing product errors:

`AlreadyListed(address gauge)`, `ControllerRegistryOccupied(address gauge)`, `NoCode(address target)`, `PlatformDeltaMismatch(address platform)`, `PlatformNotReady(address platform)`, `PlatformReceiptMissing(address platform)`, `TrustedGaugeCheckFailed(address gauge)`, `UnknownGauge(address gauge)`, `UntrustedGauge(address gauge)`.

Shared errors:

`SafeTokenBadReturn(address token)`, `SafeTokenCallFailed(address token)`, `SafeTokenNoCode(address token)`.

The new getter selector is `trustedGaugeValidator() = 0x3ca09961`. The only validator predicate used is `validateGauge(address) = 0xe92cd3d3`, with the candidate gauge as its argument. A successful exact-32-byte zero returns `UntrustedGauge(address) = 0x6c706dca`; call failure, nonexact length or a word greater than one returns `TrustedGaugeCheckFailed(address) = 0x7835e9b7`. Only word one passes. The external validator's internal faults may collapse to false and therefore yield UntrustedGauge. Out-of-gas and other dependency ABI failures need not have a uniform custom error.

## Adapter interfaces and invariant boundary

The full unchanged VotiumAdapter and VoteMarketAdapter ABIs/method identifiers are included in the manifest. Their constructors remain `(address crvUSD_,address owner_,address votium_)` and `(address crvUSD_,address owner_,address campaignRemoteManager_,address votemarket_)`, respectively.

Both implement `rewardToken()`, `lister()` and `deposit(address gauge,uint256 scheduledEpoch,uint256 amount) returns (bytes32 receipt)`. `setLister(address)` is owner-authenticated and write-once. They accept deposits only from that bound core, use exact bounded token approvals and clear allowances (a zero approval request is one checked zero approval; the final allowance is always cleared to zero). VoteMarket also accepts native ETH through `receive()` as committed message float; neither adapter exposes withdrawal, rescue or arbitrary execution. Its `getDeposit`, `depositCount` and `depositAt` expose recorded L1 ingress from the adapter's own chain-1 log — receipt values are opaque adapter-domain identifiers (a keccak tuple plus a local ordinal) attested by the emitting adapter and its deposit events, not proof of asynchronous destination delivery. The compiled-ABI allowlist witness in `test/Adapters.t.sol` checks the fresh artifact's signature-key set against the intended allowlist in both directions plus one no-fallback calldata probe; it does not attest deployed-byte equality or enumerate the dispatcher — the exact runtime/immutables byte comparison is a distinct release gate recorded with the release evidence package (see `README.md`). See `OPERATIONS.md` for mutable venue settings, gas arithmetic and residual-loss limits.
