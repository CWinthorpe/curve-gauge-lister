// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @notice Stateless ABI boundary for the Curve GaugeController operations the
/// lister depends on. Execution authority for `add_gauge` belongs to the
/// upstream GaugeAdder/admin integration, not the public lister caller.
interface IListingController {
    /// @notice Immediate permanent registry addition; execution authority belongs
    /// to the upstream GaugeAdder/admin integration, not the public lister caller.
    function add_gauge(address gauge, int128 gaugeType, uint256 weight) external;

    /// @notice Return the REAL controller's latest scheduled raw bias, exactly as
    /// `points_weight[gauge][time_weight[gauge]].bias`; never a wrapper kill flag.
    function get_gauge_weight(address gauge) external view returns (uint256);

    /// @notice Return type; revert for a gauge absent from the permanent registry.
    function gauge_types(address gauge) external view returns (int128);

    /// @notice Upper bound for valid type identifiers.
    function n_gauge_types() external view returns (int128);
}
