# GaugeBounty — beneficiary-bound ballot ABI

Describes the shipped `GaugeBounty` compiled surface; where this document and the compiler output disagree, the compiler output wins. The bounty has 14 callable functions, 7 events, 16 product errors, 5 surfaced shared/library errors, and one constructor. The bounty ABI is unchanged by the trusted-factory amendment; V2's revised full-surface delta is specified below.

## Functions (14)

- `accounting()` [view] -> `(uint256 heldStakes,uint256 rewardCredits,uint256 daoLiability)` `0x9624e83e`
- `bindLister(address lister_)` [nonpayable] -> `()` `0x9389f319`
- `claim(bytes32 reportId)` [nonpayable] -> `(uint256 stakeAmount,uint256 rewardAmount)` `0xbd66528a`
- `config()` [view] -> `BountyConfig` `0x79502c55`
- `creditBallot(bytes32 reportId,address reporter)` [nonpayable] -> `()` `0xbe1acbef`
- `creditReward(bytes32 reportId,uint256 amount)` [nonpayable] -> `()` `0xb8491252`
- `flushDao(uint256 amount)` [nonpayable] -> `(uint256 flushed)` `0x23cc88b8`
- `getReport(bytes32 reportId)` [view] -> `ReportView` `0x171c4f11`
- `lister()` [view] -> `(address)` `0x2cdc1c74`
- `markFrivolous(bytes32 reportId)` [nonpayable] -> `(bool applied)` `0x948bfa9d`
- `recognizeKill(bytes32 reportId)` [nonpayable] -> `()` `0xe1e58a40`
- `resolve(bytes32 reportId)` [nonpayable] -> `(bool changed)` `0x5c23bdf5`
- `rewardTerms(address gauge)` [view] -> `(bytes32 reportId,address reporter,bool eligible)` `0xc249734c`
- `submit(address gauge,uint256 proposalId,bytes32 evidenceHash,uint256 reportNonce)` [nonpayable] -> `(bytes32 reportId)` `0x12980769`

`submit` validates an already-created Ownership ballot. It does not create, authorize, queue, or service a ballot. The canonical script binds `reportId`, the beneficiary/reporter, and gauge; only the encoded beneficiary may submit. A sponsor may create the upstream ballot for that beneficiary.

## BountyConfig tuple (9 fields)

`(address crvUSD,address feeDistributor,address ownershipVoting,address ownershipAgent,address killProxy,address supportedFactory,address votingImplementation,address agentImplementation,address callsScriptExecutor)`

The constructor takes `BountyConfig config_` in this exact order. The reworked bounty has no project CRV, escrow, treasury, or wallet-checker constructor dependency.

## ReportView tuple (10 fields)

`(address reporter,address gauge,bytes32 listingId,bytes32 evidenceHash,uint256 proposalId,uint256 voteEnd,uint256 executeBy,uint8 phase,uint8 stakeState,uint256 rewardCredit)`

`phase` encoding: `None=0, Proposed=1, Armed=2, Recognized=3, Rewarded=4, Rejected=5, Expired=6, NoAward=7`.

`stakeState` encoding: `None=0, Bonded=1, Refundable=2, Refunded=3, Forfeited=4`.

Unknown report IDs return the zero tuple. An accepted submit enters `Proposed` and `Bonded` immediately. `voteEnd` and `executeBy` derive from the original ballot clock; submission does not restart it.

## Events (7)

- `Claimed(bytes32 indexed reportId,address indexed reporter,uint256 stakeAmount,uint256 rewardAmount)`
- `DaoFlushed(uint256 amount,uint256 receiptWeek)`
- `ListerBound(address indexed lister)`
- `ReportStateChanged(bytes32 indexed reportId,uint8 phase)`
- `ReportSubmitted(bytes32 indexed reportId,address indexed reporter,address indexed gauge,uint256 proposalId,uint256 reportNonce,bytes32 evidenceHash,uint256 voteEnd,uint256 executeBy)`
- `RewardCredited(bytes32 indexed reportId,uint256 amount)`
- `StakeForfeited(bytes32 indexed reportId)`

## Product errors (16)

`AlreadyBound`, `BadAmount`, `BadConfiguration`, `BadEvidence`, `BadPhase`, `BadVote`, `DuplicateProposal`, `DuplicateReport`, `IneligibleGauge`, `NotAgent`, `NotDao`, `NotLister`, `Reentrancy`, `TokenDeltaMismatch`, `UnknownReport`, `WrongChain`

## Surfaced shared/library errors (5)

- `SafeTokenNoCode(address token)`
- `SafeTokenCallFailed(address token)`
- `SafeTokenBadReturn(address token)`
- `DistributorUnusable()`
- `ConfiscationDeltaMismatch()`

These errors are surfaced by frozen/shared libraries and are not product-declared errors.

## Removed callable surface

The compiled ABI contains none of the old standing-lock, queue, bounty-side ballot-creation, or old submit/kill selectors. The manifest records the removed selectors for the negative ABI gate. Ballot creation remains fixture/test-only; production-facing `IOwnershipVoting` retains the deployed `getVote(uint256)` read surface.

## V2 full surface and unchanged consumer hook

The trusted-factory amendment preserves all 31 existing V2 callables and adds `trustedGaugeValidator()` [view] -> `(address)` (`0x3ca09961`). The amended V2 surface is 32 functions, 10 events, 36 errors including surfaced library errors, one constructor, no receive/fallback. Full compiler ABI and methodIdentifiers must equal this list under both build profiles; counts alone are insufficient.

Append `address trustedGaugeValidator_` after `address bounty_` as the eighth constructor argument; the preceding owner/token/controller/FD/admission/platform/bounty arguments and tuple shapes are unchanged. It is an immutable address with no setter or default. Chain 1 remains mandatory; absent validator code reuses `NoCode(address)`.

Exactly two new errors are introduced: `UntrustedGauge(address gauge)` (`0x6c706dca`) for a canonical false result, and `TrustedGaugeCheckFailed(address gauge)` (`0x7835e9b7`) for a failed staticcall, response length other than 32 or bool word above 1. Only exact 32-byte canonical true from `validateGauge(gauge)` on the pinned validator passes. Underlying factory/module faults that the validator returns as false are rejected as UntrustedGauge. Out-of-gas still reverts without a guaranteed custom error.

No events, existing function signatures, ListingV2 components, storage slots, split-hook custody checks or `ICurveGaugeListerV2` hook methods change. The free DAO lane does not query the validator. V1, GaugeBounty and both adapters retain their complete source/ABI/bytecode; the new interface `ITrustedGaugeValidator` is V2-only. The external validator's module/proposal management functions do not become lister callables.
