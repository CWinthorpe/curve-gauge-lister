// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC20Minimal} from "../../../contracts/interfaces/IERC20Minimal.sol";

/// @title BountyFaultActors
/// @notice Adversarial callback actors for the safety suites
/// (plans/BOUNTY-PLAN.md §4.3, §5.2 tests 50/54/67). Callbacks must exercise
/// VALID authority and funded prerequisites, not fail earlier on unrelated
/// checks: the reentry token is wired as a token dependency of the system
/// under attack, and each armed action is a payload the product must reject
/// through its guards, not through a missing precondition.
contract ReentrantToken is IERC20Minimal {
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    uint8 private immutable _dec;

    address private _reentryTarget;
    bytes private _reentryCalldata;
    bool private _attackTransfer; // arm on transfer()
    bool private _attackTransferFrom; // arm on transferFrom()
    bool private _lastReentryReturned;
    bytes4 private _reentrySel;
    bool private _malformedReturn; // labelled mode: return 32 bytes of zero

    error InBalance();
    error InAllowance();

    constructor(uint8 decimals_) {
        _dec = decimals_;
    }

    function decimals() external view returns (uint8) {
        return _dec;
    }

    function balanceOf(address a) external view returns (uint256) {
        return _balances[a];
    }

    function allowance(address a, address s) external view returns (uint256) {
        return _allowances[a][s];
    }

    function mint(address to, uint256 amount) external {
        _balances[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        _allowances[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool ok) {
        if (_malformedReturn) {
            // 32 bytes of zero: non-empty and not ABI true.
            assembly {
                mstore(0, 0)
                return(0, 32)
            }
        }
        _move(msg.sender, to, amount);
        if (_attackTransfer) _fire();
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool ok) {
        if (_malformedReturn) {
            assembly {
                mstore(0, 0)
                return(0, 32)
            }
        }
        uint256 allowed = _allowances[from][msg.sender];
        if (allowed < amount) revert InAllowance();
        _allowances[from][msg.sender] = allowed - amount;
        _move(from, to, amount);
        if (_attackTransferFrom) _fire();
        return true;
    }

    /// @notice Labelled malformed-return ERC20 mode (non-empty, non-true).
    function setMalformedReturn(bool enabled) external {
        _malformedReturn = enabled;
    }

    function _move(address from, address to, uint256 amount) private {
        uint256 bal = _balances[from];
        if (bal < amount) revert InBalance();
        _balances[from] = bal - amount;
        _balances[to] += amount;
    }

    function _fire() private {
        address t = _reentryTarget;
        if (t == address(0)) return;
        _lastReentryReturned = false;
        (bool ok,) = t.call(_reentryCalldata);
        _lastReentryReturned = ok;
        // Swallowed by design: the product guard must reject the REENTRY,
        // which only manifests through its state/custody effects.
    }

    /// @notice Arm the callback: during the next transfer/transferFrom of the
    /// chosen kind, invoke `target.call(data)` once.
    function armAttack(address target, bytes calldata data, bool onTransfer, bool onTransferFrom) external {
        _reentryTarget = target;
        _reentryCalldata = data;
        _attackTransfer = onTransfer;
        _attackTransferFrom = onTransferFrom;
        _reentrySel = bytes4(data[0:4]);
    }

    function disarm() external {
        _reentryTarget = address(0);
        _reentryCalldata = "";
        _attackTransfer = false;
        _attackTransferFrom = false;
    }

    function lastReentryReturned() external view returns (bool) {
        return _lastReentryReturned;
    }

    function reentrySelector() external view returns (bytes4) {
        return _reentrySel;
    }
}

/// @dev Forwards an arbitrary call as itself; used to exercise full plausible
/// payloads as Agent/owner/treasury/outsider from a contract caller (not just
/// EOAs), without granting any real authority.
contract ContractCaller {
    bool private _ok;
    bytes private _ret;

    function fire(address target, bytes calldata data) external returns (bool ok, bytes memory ret) {
        (ok, ret) = target.call(data);
        _ok = ok;
        _ret = ret;
    }

    function fireValue(address target, uint256 value, bytes calldata data) external payable returns (bool ok) {
        (ok,) = target.call{value: value}(data);
        _ok = ok;
    }

    function lastOk() external view returns (bool) {
        return _ok;
    }

    function lastRet() external view returns (bytes memory) {
        return _ret;
    }

    receive() external payable {}
}

/// @dev Honest-looking reporter/recipient stand-in whose receive path is
/// inert: used where a payment to a contract recipient must NOT open a
/// callback (the plan forbids reporter external calls in settlement).
contract SilentRecipient {
    uint256 private _beeps;

    function beeps() external view returns (uint256) {
        return _beeps;
    }

    /// @notice Non-view seam: increments only when the OWNER of this actor
    /// pokes it, never from an inbound token transfer.
    function poke() external {
        _beeps += 1;
    }
}
