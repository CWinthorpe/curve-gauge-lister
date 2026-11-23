// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @notice Minimal stateless ERC20 surface the PRODUCTION code type-reads for
/// fee settlement: the fee-token unit check and balance deltas. Token
/// movement/approval never goes through this typed declaration — it uses
/// SafeToken's checked low-level calls — and fixture-side movement lives on
/// `IERC20Fixture` below. Do not require optional pool-coin
/// metadata/symbol/decimals calls beyond `decimals` for the fee token unit
/// check.
interface IERC20Minimal {
    /// @notice Fee-token unit check.
    function decimals() external view returns (uint8);

    /// @notice Balance deltas.
    function balanceOf(address account) external view returns (uint256);
}

/// @notice Fixture/test-only extended ERC20 declaration (S23): minting,
/// funding and approval inspection used by mocks and retained-hardening
/// helpers that hold token positions (for example the negative-test FD
/// `burn()` route and fixture approval drivers). The dependency token's
/// protocol is unchanged and production code never calls these members
/// through a typed interface; SafeToken's low-level calls own all production
/// movement.
interface IERC20Fixture is IERC20Minimal {
    /// @notice Approval inspection (fixture evidence).
    function allowance(address account, address spender) external view returns (uint256);

    /// @notice Fixture transfer.
    function transfer(address to, uint256 amount) external returns (bool);

    /// @notice Fixture pull of approved tokens.
    function transferFrom(address from, address to, uint256 amount) external returns (bool);

    /// @notice Fixture bounded approval.
    function approve(address spender, uint256 amount) external returns (bool);
}
