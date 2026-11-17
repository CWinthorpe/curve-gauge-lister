// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title SafeToken
/// @notice Safe low-level ERC20 calls: require token code; accept empty return
/// data or ABI true, reject false/malformed returns, bubble/revert on failed
/// calls. For approval use zero-then-exact-amount, and zero again after a
/// successful deposit. Kept minimal and locally tested rather than introducing
/// a runtime dependency.
/// @dev No storage, constructor or public/external functions.
library SafeToken {
    /// @dev Reverts when an ERC20 interaction is attempted against an address
    /// without deployed code.
    error SafeTokenNoCode(address token);

    /// @dev Reverts when a token call fails outright.
    error SafeTokenCallFailed(address token);

    /// @dev Reverts when a token call returns malformed (non-empty, non-true) data.
    error SafeTokenBadReturn(address token);

    function safeTransfer(address token, address to, uint256 amount) internal {
        _call(token, abi.encodeWithSignature("transfer(address,uint256)", to, amount));
    }

    function safeTransferFrom(address token, address from, address to, uint256 amount) internal {
        _call(token, abi.encodeWithSignature("transferFrom(address,address,uint256)", from, to, amount));
    }

    /// @notice Zero-then-exact-amount approval; used around each funded platform
    /// deposit so no enduring allowance is ever left behind.
    function forceApprove(address token, address spender, uint256 amount) internal {
        // An existing non-zero approval must be reset before the exact-amount
        // set; the zero step goes through the same safe path so a false/malformed
        // approve cannot silently leave a dangling allowance.
        _call(token, abi.encodeWithSignature("approve(address,uint256)", spender, 0));
        _call(token, abi.encodeWithSignature("approve(address,uint256)", spender, amount));
    }

    function _call(address token, bytes memory callData) private {
        if (token.code.length == 0) revert SafeTokenNoCode(token);
        (bool ok, bytes memory ret) = token.call(callData);
        if (!ok) revert SafeTokenCallFailed(token);
        if (ret.length != 0) {
            if (ret.length != 32 || abi.decode(ret, (bool)) != true) {
                revert SafeTokenBadReturn(token);
            }
        }
    }
}
