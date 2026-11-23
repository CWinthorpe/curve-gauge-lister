// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @notice Stateless ABI boundary for the Curve GaugeController operations the
/// lister PRODUCT depends on — exactly add/type/count (S20). Execution
/// authority for `add_gauge` belongs to the upstream GaugeAdder/admin
/// integration, not the public lister caller. The real controller's weight
/// surface (`get_gauge_weight`) is an OBSERVATION used only by tests and fork
/// reference reads; it is deliberately not declared here, and retaining the
/// observation does not widen the core's callable dependency subset.
interface IListingController {
    /// @notice Immediate permanent registry addition; execution authority belongs
    /// to the upstream GaugeAdder/admin integration, not the public lister caller.
    function add_gauge(address gauge, int128 gaugeType, uint256 weight) external;

    /// @notice Return type; revert for a gauge absent from the permanent registry.
    function gauge_types(address gauge) external view returns (int128);

    /// @notice Upper bound for valid type identifiers.
    function n_gauge_types() external view returns (int128);
    // Fork-side venue mirror: test/fork/ForkFixture.sol `IControllerVenue`
    // (S26): these three declarations must agree with its product-subset
    // members; its additional fields are observation/authority roles.
}
