// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IFeeDistributor} from "../interfaces/IFeeDistributor.sol";
import {IERC20Minimal} from "../interfaces/IERC20Minimal.sol";

/// @title MockFeeDistributor
/// @notice Test-only crvUSD fee destination with REAL balance-delta accounting
/// mirroring deployed S4 `CurveFeeDistribution.vy`: `checkpoint_token()` gates
/// on `(caller == admin) || (canCheckpoint && block.timestamp > last_token_time
/// + 86400)` and apportions the received delta pro-rata over the interval since
/// the prior checkpoint, looping at most 20 weeks, including the
/// same-timestamp case. No transferFrom-on-checkpoint, no simulated veCRV
/// distribution, no fake successful claims.
contract MockFeeDistributor is IFeeDistributor {
    uint256 private constant WEEK = 604800;
    uint256 private constant TOKEN_CHECKPOINT_DEADLINE = 86400;

    address private immutable _token;
    address private immutable _admin;

    bool private _killed;
    bool private _canCheckpoint = true;
    bool private _checkpointRevert;
    uint8 private _cursorReadMode;
    uint8 private _checkpointMode;
    uint256 private _lastTokenTime;
    uint256 private _tokenLastBalance;
    mapping(uint256 => uint256) private _tokensPerWeek;
    uint256 private _checkpointCalls;

    error NotAdmin();
    error CannotCheckpoint();
    error CheckpointFailed();
    error WrongCoin();
    error IsKilled();
    error UnknownFaultMode();
    error CursorReadFailed();

    /// @notice Set fixture token/admin; floor initial last_token_time; start
    /// with zero accounted balance.
    constructor(address token_, address admin_, uint256 startTime_) {
        require(token_ != address(0) && admin_ != address(0), "zero");
        _token = token_;
        _admin = admin_;
        _lastTokenTime = (startTime_ / WEEK) * WEEK;
    }

    function token() external view returns (address) {
        return _token;
    }

    function is_killed() external view returns (bool) {
        return _killed;
    }

    /// @notice Token and killed getters plus REAL balance-delta accounting in
    /// checkpoint_token, NOT transferFrom-on-checkpoint. auditfix001 §4: the
    /// deterministic fault seams below (cursor override, cursor-read fault,
    /// checkpoint fault) model upstream failures for negative tests; they are
    /// fixture-only controls applied AFTER the real caller/cooldown checks and
    /// the existing injected-revert check, and only checkpoint mode 0 executes
    /// the real accounting loop.
    function checkpoint_token() external {
        if (msg.sender != _admin) {
            if (!_canCheckpoint) revert CannotCheckpoint();
            if (block.timestamp <= _lastTokenTime + TOKEN_CHECKPOINT_DEADLINE) revert CannotCheckpoint();
        }
        if (_checkpointRevert) revert CheckpointFailed();
        uint8 mode = _checkpointMode;
        if (mode == 1) return; // return normally without accounting
        if (mode == 2) {
            // Cursor-only false success: advance the time cursor without any
            // balance/bucket accounting.
            _lastTokenTime = block.timestamp;
            return;
        }
        _doCheckpointToken();
    }

    /// @notice Configure public gate.
    function setCanCheckpoint(bool enabled) external {
        _canCheckpoint = enabled;
    }

    /// @notice Exercise unavailable destination.
    function setKilled(bool killed) external {
        _killed = killed;
    }

    /// @notice Inject checkpoint failure.
    function setCheckpointRevert(bool enabled) external {
        _checkpointRevert = enabled;
    }

    /// @notice auditfix001 §4 fixture-only control: raw cursor override for
    /// zero/future and boundary cases. Does NOT change the balance, accounted
    /// balance or weekly allocations.
    function setLastTokenTime(uint256 value) external {
        _lastTokenTime = value;
    }

    /// @notice auditfix001 §4 fixture-only control over `last_token_time()`:
    /// 0 normal, 1 revert, 2 return fewer than 32 bytes. Other values revert.
    function setCursorReadMode(uint8 mode) external {
        if (mode > 2) revert UnknownFaultMode();
        _cursorReadMode = mode;
    }

    /// @notice auditfix001 §4 fixture-only control over
    /// `checkpoint_token()`: 0 normal, 1 return without accounting, 2 update
    /// only the cursor to now without balance/bucket accounting. Other values
    /// revert. Faults apply AFTER the real caller/cooldown checks and the
    /// injected-revert check.
    function setCheckpointMode(uint8 mode) external {
        if (mode > 2) revert UnknownFaultMode();
        _checkpointMode = mode;
    }

    function last_token_time() external view returns (uint256) {
        if (_cursorReadMode == 1) revert CursorReadFailed();
        if (_cursorReadMode == 2) {
            // Malformed: fewer than 32 bytes of returndata.
            uint256 value = _lastTokenTime;
            assembly {
                mstore(0, value)
                return(0, 31)
            }
        }
        return _lastTokenTime;
    }

    function token_last_balance() external view returns (uint256) {
        return _tokenLastBalance;
    }

    function tokens_per_week(uint256 epoch) external view returns (uint256) {
        return _tokensPerWeek[epoch];
    }

    /// @notice Inspect actual accounting and successful checkpoint count.
    function checkpointCalls() external view returns (uint256) {
        return _checkpointCalls;
    }

    /// @notice Negative-test fidelity: pull sender's ENTIRE balance of the
    /// configured token and optionally checkpoint using the same public
    /// eligibility rule. Never used by product code.
    function burn(address coin) external returns (bool) {
        if (coin != _token) revert WrongCoin();
        if (_killed) revert IsKilled();
        uint256 amount = IERC20Minimal(_token).balanceOf(msg.sender);
        if (amount != 0) {
            IERC20Minimal(_token).transferFrom(msg.sender, address(this), amount);
            if (_canCheckpoint && (block.timestamp > _lastTokenTime + TOKEN_CHECKPOINT_DEADLINE)) {
                _doCheckpointToken();
            }
        }
        return true;
    }

    /// @dev Faithful port of deployed S4 `_checkpoint_token` proportional
    /// interval allocation (bounded 20-week loop), including the
    /// same-timestamp case that credits the current week in full.
    function _doCheckpointToken() private {
        uint256 tokenBalance = IERC20Minimal(_token).balanceOf(address(this));
        uint256 toDistribute = tokenBalance - _tokenLastBalance;
        _tokenLastBalance = tokenBalance;

        uint256 t = _lastTokenTime;
        uint256 sinceLast = block.timestamp - t;
        _lastTokenTime = block.timestamp;
        uint256 thisWeek = (t / WEEK) * WEEK;

        for (uint256 i = 0; i < 20; ++i) {
            uint256 nextWeek = thisWeek + WEEK;
            if (block.timestamp < nextWeek) {
                if (sinceLast == 0 && block.timestamp == t) {
                    _tokensPerWeek[thisWeek] += toDistribute;
                } else {
                    _tokensPerWeek[thisWeek] += (toDistribute * (block.timestamp - t)) / sinceLast;
                }
                break;
            } else {
                if (sinceLast == 0 && nextWeek == t) {
                    _tokensPerWeek[thisWeek] += toDistribute;
                } else {
                    _tokensPerWeek[thisWeek] += (toDistribute * (nextWeek - t)) / sinceLast;
                }
            }
            t = nextWeek;
            thisWeek = nextWeek;
        }
        _checkpointCalls += 1;
    }
}
