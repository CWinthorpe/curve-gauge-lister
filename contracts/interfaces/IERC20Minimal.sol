// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @notice Minimal stateless ERC20 surface used for fee settlement. Do not
/// require optional pool-coin metadata/symbol/decimals calls beyond `decimals`
/// for the fee token unit check.
interface IERC20Minimal {
    /// @notice Fee-token unit check.
    function decimals() external view returns (uint8);

    /// @notice Balance deltas.
    function balanceOf(address account) external view returns (uint256);

    /// @notice Approval inspection.
    function allowance(address account, address spender) external view returns (uint256);

    /// @notice Send tokens.
    function transfer(address to, uint256 amount) external returns (bool);

    /// @notice Pull approved tokens.
    function transferFrom(address from, address to, uint256 amount) external returns (bool);

    /// @notice Set a bounded approval.
    function approve(address spender, uint256 amount) external returns (bool);
}
