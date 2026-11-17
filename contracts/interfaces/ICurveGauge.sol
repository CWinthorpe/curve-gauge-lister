// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @notice Same-chain LP-token gauge checks used at admission and as the
/// settlement kill oracle. No storage. Root/child cross-chain gauge validation
/// requires an appropriate later production integration, not substituting an
/// L2 address into this same-chain LP-token check.
interface ICurveGauge {
    /// @notice Check staked token matches authenticated pool LP token.
    function lp_token() external view returns (address);

    /// @notice Reject a gauge already disabled at admission. After admission
    /// this same getter is the ONLY settlement kill oracle under Amendment A2
    /// (plans/PLAN.md): true confiscates; controller weight is never consulted.
    function is_killed() external view returns (bool);
}
