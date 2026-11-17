// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title BountyTypes
/// @notice Shared type/enum vocabulary for the beneficiary-bound bounty
/// surface (plans/BOUNTY-REWORK-PLAN.md §6). No deployable runtime, no public
/// functions: this file exists so `IGaugeBounty`, `CurveGaugeListerV2`, the
/// internal libraries and the offline models agree on one exact field order.
/// @dev Enum fields in *views* are `uint8` per the manifest; enums below are
/// storage/transition vocabularies only.

/// @notice Report lifecycle phase. Exact order is ABI-binding (rework plan
/// §6): None=0, Proposed=1, Armed=2, Recognized=3, Rewarded=4, Rejected=5,
/// Expired=6, NoAward=7. The retired Queued phase is gone: admission is
/// immediate against a pre-created beneficiary-bound ballot; no protocol
/// queue, no shared creation capacity.
/// Existence of a report is `reporter != address(0)`, never a default enum.
enum Phase {
    None,
    Proposed,
    Armed,
    Recognized,
    Rewarded,
    Rejected,
    Expired,
    NoAward
}

/// @notice Bond disposition. Exact order is ABI-binding (rework plan §6):
/// None=0, Bonded=1, Refundable=2, Refunded=3, Forfeited=4. heldStakes
/// counts Bonded and Refundable only.
enum StakeState {
    None,
    Bonded,
    Refundable,
    Refunded,
    Forfeited
}

/// @notice Complete flat local report view (rework plan §6). Unknown IDs
/// return the all-zero view; callers must not treat a zero enum as
/// existence — a nonzero stored reporter establishes existence, and
/// proposalId zero is a legal binding, not an absence marker.
struct ReportView {
    address reporter;
    address gauge;
    bytes32 listingId;
    bytes32 evidenceHash;
    uint256 proposalId;
    uint256 voteEnd;
    uint256 executeBy;
    uint8 phase;
    uint8 stakeState;
    uint256 rewardCredit;
}

/// @notice Complete immutable GaugeBounty construction configuration
/// (rework plan §6): the exact nine-address tuple, both the constructor input
/// and the `config()` output. All fields are fixed for the deployment;
/// changes require a new deployment. The retired crv/votingEscrow/
/// projectTreasury/walletChecker capital fields are gone — the bounty holds
/// no project capital and depends on no proposal-rights checker.
struct BountyConfig {
    address crvUSD;
    address feeDistributor;
    address ownershipVoting;
    address ownershipAgent;
    address killProxy;
    address supportedFactory;
    address votingImplementation;
    address agentImplementation;
    address callsScriptExecutor;
}
