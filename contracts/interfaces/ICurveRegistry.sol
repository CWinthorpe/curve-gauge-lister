// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @notice Stateless, verified MetaRegistry ABI subset; always use explicit indices.
interface ICurveRegistry {
    /// @notice Authenticate pool through a trusted registry handler; a revert fails admission.
    function is_registered(address pool, uint256 handlerId) external view returns (bool);

    /// @notice Obtain the registry-authenticated LP token.
    function get_lp_token(address pool, uint256 handlerId) external view returns (address);

    /// @notice Authenticate the particular gauge; never accept the gauge's own claim alone.
    function get_gauge(address pool, uint256 gaugeIndex, uint256 handlerId) external view returns (address);

    /// @notice Derive the type from the trusted handler, not caller discretion.
    function get_gauge_type(address pool, uint256 gaugeIndex, uint256 handlerId) external view returns (int128);

    /// @notice Get number of immediate pool coins (not recursively expanded underlying coins).
    function get_n_coins(address pool, uint256 handlerId) external view returns (uint256);

    /// @notice Get padded immediate coin addresses.
    function get_coins(address pool, uint256 handlerId) external view returns (address[8] memory);
}
