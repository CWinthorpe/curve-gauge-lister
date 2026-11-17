// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @notice Stateless subset only. Real `burn(address)`, `claim(address)` and
/// `checkpoint_total_supply()` are discussed in plan section 6, but are not
/// product call sites and intentionally absent here.
interface IFeeDistributor {
    /// @notice Check fee-token identity.
    function token() external view returns (address);

    /// @notice Check deposit destination remains live.
    function is_killed() external view returns (bool);

    /// @notice Account already-received tokens; does not pull allowances.
    function checkpoint_token() external;

    /// @notice Real allocation cursor (auditfix001 §3). The confiscation
    /// freshness policy keys off this getter, never `time_cursor`,
    /// `total_received` or a fixed week count.
    function last_token_time() external view returns (uint256);

    /// @notice Balance already accounted by the distributor's own checkpoint
    /// loop (auditfix001 §3); compared against actual custody after the
    /// mandatory in-confiscation accounting call.
    function token_last_balance() external view returns (uint256);
}
