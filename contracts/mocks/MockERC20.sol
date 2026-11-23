// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC20Fixture} from "../interfaces/IERC20Minimal.sol";

/// @title MockERC20
/// @notice Test-only fee/LP/coin fixture with injectable transfer behaviors.
/// No real token economics, ownership, symbol or totalSupply is needed by this
/// suite. Implements the fixture/test extended ERC20 surface; the production
/// typed surface (`IERC20Minimal`) carries only the reads product code uses.
contract MockERC20 is IERC20Fixture {
    uint8 private immutable _decimals;
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    uint16 private _feeBps;
    bool private _returnFalse;
    bool private _noReturn;

    error InsufficientBalance();
    error InsufficientAllowance();
    error BadBehavior();

    /// @notice Configure fee/LP/coin fixture units.
    constructor(uint8 decimals_) {
        _decimals = decimals_;
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function allowance(address account, address spender) external view returns (uint256) {
        return _allowances[account][spender];
    }

    /// @notice Real balances, approvals and transfers, with finite allowance
    /// consumption and insufficient-balance/allowance reverts.
    function transfer(address to, uint256 amount) external returns (bool) {
        return _move(msg.sender, to, amount);
    }

    /// @notice Real balances, approvals and transfers, with finite allowance
    /// consumption and insufficient-balance/allowance reverts.
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = _allowances[from][msg.sender];
        // Finite allowance consumption only: no infinite-allowance sentinel.
        if (allowed < amount) revert InsufficientAllowance();
        _allowances[from][msg.sender] = allowed - amount;
        return _move(from, to, amount);
    }

    /// @notice Set a bounded approval (ordinary successful ERC20 behavior).
    function approve(address spender, uint256 amount) external returns (bool) {
        _allowances[msg.sender][spender] = amount;
        return true;
    }

    /// @notice Fund fixtures.
    function mint(address to, uint256 amount) external {
        _balances[to] += amount;
    }

    /// @notice Inject transfer/transferFrom fee, false-return, or empty-return
    /// modes; feeBps <= 10,000, disallow simultaneous returnFalse and noReturn.
    /// False-return mode moves no tokens; fee mode burns the difference.
    /// Empty-return mode uses no return bytes on transfers.
    function setTransferBehavior(uint16 feeBps, bool returnFalse, bool noReturn) external {
        if (feeBps > 10_000) revert BadBehavior();
        if (returnFalse && noReturn) revert BadBehavior();
        _feeBps = feeBps;
        _returnFalse = returnFalse;
        _noReturn = noReturn;
    }

    function _move(address from, address to, uint256 amount) private returns (bool ok) {
        if (_returnFalse) {
            // False-return mode moves no tokens.
            return false;
        }
        uint256 fromBal = _balances[from];
        if (fromBal < amount) revert InsufficientBalance();
        uint256 delivered = amount;
        if (_feeBps > 0) {
            // Fee mode burns the difference.
            delivered = amount - (amount * uint256(_feeBps)) / 10_000;
        }
        _balances[from] = fromBal - amount;
        _balances[to] += delivered;
        if (_noReturn) {
            // Empty-return mode uses no return bytes on transfers.
            assembly {
                return(0, 0)
            }
        }
        return true;
    }
}
