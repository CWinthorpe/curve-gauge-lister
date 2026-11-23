// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title CurveWeek
/// @notice One production Curve-week floor convention (Thursday 00:00 UTC
/// boundaries; Unix epoch zero is a Thursday, so plain flooring needs no
/// extra offset). Shared by the core's public `epochStart` and the
/// VoteMarketAdapter's execution-week label so the shipping tree has a
/// single arithmetic definition of the production week floor.
/// @dev Deliberately does NOT absorb the settlement/allocator model
/// boundaries: real Votium round selection (venue `activeRound()` at deposit
/// time), the FeeDistributor's own bounded allocation loop and test
/// reference anchors keep their own independent expectations and are not
/// derived from this helper.
library CurveWeek {
    /// @notice Seconds in one Curve week.
    uint256 internal constant WEEK = 604800;

    /// @notice Floor a Unix timestamp to its Thursday-aligned Curve week.
    /// @dev The multiplication cannot overflow: `(timestamp / WEEK) * WEEK
    /// <= timestamp` for every uint256 input.
    function floorWeek(uint256 timestamp) internal pure returns (uint256) {
        unchecked {
            return (timestamp / WEEK) * WEEK;
        }
    }
}
