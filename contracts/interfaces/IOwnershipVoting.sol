// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title IOwnershipVoting
/// @notice Actual deployed Aragon/Ownership `Voting` ABI subset used by the
/// bounty (plans/BOUNTY-REWORK-PLAN.md §3.2/§3.3). No interface aliases that
/// accidentally add getters. The retired creation-side surface
/// (newVote/canCreate/canForward/enableVoteCreation/minBalance/minTime/
/// lastCreateVoteTimes) is GONE from this bounty-facing file: the beneficiary-
/// bound protocol never creates or authorizes ballots, and the removed
/// proposal-rights controls are not admitted against. Reporter-side ballot
/// creation interfaces are separate test-fixture declarations, never here.
interface IOwnershipVoting {
    /// @notice Complete ten-field record in deployed order, including the raw
    /// script bytes.
    function getVote(uint256 voteId)
        external
        view
        returns (
            bool open,
            bool executed,
            uint256 startDate,
            uint256 snapshotBlock,
            uint256 supportRequired,
            uint256 minAcceptQuorum,
            uint256 yea,
            uint256 nay,
            uint256 votingPower,
            bytes memory script
        );

    /// @notice Deployed Voting execution predicate on a closed, unexecuted
    /// ballot (validated-rejection read in resolve only — never required
    /// true inside an execution callback, where it is false after execution).
    function canExecute(uint256 voteId) external view returns (bool);

    function voteTime() external view returns (uint256);

    function supportRequiredPct() external view returns (uint256);

    function minAcceptQuorumPct() external view returns (uint256);

    function votesLength() external view returns (uint256);

    function implementation() external view returns (address);

    function getEVMScriptExecutor(bytes calldata script) external view returns (address);
}
