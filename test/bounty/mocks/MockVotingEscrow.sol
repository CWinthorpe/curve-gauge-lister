// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC20Minimal} from "../../../contracts/interfaces/IERC20Minimal.sol";
import {SafeToken} from "../../../contracts/libraries/SafeToken.sol";

/// @dev Mock-local escrow vocabulary (plans/BOUNTY-REWORK-PLAN.md §2): the
/// production IVotingEscrow file is retired with the standing lock; the
/// reporter-owned veCRV model keeps its own declarations and depends on no
/// production checker interface.
interface IVotingEscrowModel {
    function locked(address addr) external view returns (int128 amount, uint256 end);
    function balanceOf(address addr) external view returns (uint256);
    function create_lock(uint256 value, uint256 unlock_time) external;
    function increase_amount(uint256 value) external;
}

interface IWalletCheckerModel {
    function check(address addr) external view returns (bool);
}

/// @title MockVotingEscrow
/// @notice Faithful offline veCRV model (plans/BOUNTY-PLAN.md §5.1): integer
/// slope/decay (`slope = amount * 1e18 / MAX_TIME`, ve = `slope * (end-now) /
/// 1e18`), Thursday flooring of unlock targets and checker failures.
/// Rework role (§2): minimal reporter-owned proposal-rights model only — the
/// bounty holds no principal here and admits nothing from it.
contract MockVotingEscrow is IVotingEscrowModel {
    uint256 private constant WEEK = 604800;
    uint256 private constant MAX_TIME = 126144000;

    struct Lock {
        int128 amount;
        uint256 end;
    }

    IERC20Minimal private immutable _crv;
    address private _checker;
    address[] private _lockers;
    mapping(address => uint256) private _lockerIndex; // 1-based
    mapping(address => Lock) private _locks;

    // --------------------------- labelled fault modes --------------------
    bool private _checkerBlock;

    error AlreadyLocked();
    error NoLock();
    error ZeroAmount();
    error BadUnlockTime();
    error CheckerBlocked();

    /// @notice Fix the underlying CRV token and the initial smart-wallet
    /// checker identity.
    constructor(address crv_, address checker_) {
        require(crv_ != address(0) && checker_ != address(0), "zero");
        _crv = IERC20Minimal(crv_);
        _checker = checker_;
    }

    /// @dev Model boundary (disclosed): snapshot reads return CURRENT decayed
    /// values; no per-block history is simulated.
    function balanceOfAt(address addr, uint256) external view returns (uint256) {
        return balanceOf(addr);
    }

    /// @dev Model boundary (disclosed): aggregate decay over live locks.
    function totalSupply() public view returns (uint256 total) {
        uint256 nowTime = block.timestamp;
        for (uint256 i = 0; i < _lockers.length; ++i) {
            Lock storage l = _locks[_lockers[i]];
            if (l.amount > 0 && nowTime < l.end) {
                total += (uint256(uint128(l.amount)) * 1e18 / MAX_TIME) * (l.end - nowTime) / 1e18;
            }
        }
    }

    function totalSupplyAt(uint256) external view returns (uint256) {
        return totalSupply();
    }

    function locked(address addr) external view returns (int128 amount, uint256 end) {
        amount = _locks[addr].amount;
        end = _locks[addr].end;
    }

    function balanceOf(address addr) public view returns (uint256) {
        Lock storage l = _locks[addr];
        if (l.amount <= 0 || block.timestamp >= l.end) return 0;
        uint256 slope = (uint256(uint128(l.amount)) * 1e18) / MAX_TIME;
        return (slope * (l.end - block.timestamp)) / 1e18;
    }

    function create_lock(uint256 value, uint256 unlockTime) external {
        if (value == 0) revert ZeroAmount();
        address sender = msg.sender;
        if (_locks[sender].amount != 0) revert AlreadyLocked();
        if (!_checkerPass(sender)) revert CheckerBlocked();
        uint256 nowTime = block.timestamp;
        if (unlockTime <= nowTime || unlockTime > nowTime + MAX_TIME) revert BadUnlockTime();
        if (unlockTime % WEEK != 0) revert BadUnlockTime(); // Thursday-aligned only
        SafeToken.safeTransferFrom(address(_crv), sender, address(this), value);
        _locks[sender] = Lock({amount: int128(uint128(value)), end: unlockTime});
        if (_lockerIndex[sender] == 0) {
            _lockers.push(sender);
            _lockerIndex[sender] = _lockers.length;
        }
    }

    function increase_amount(uint256 value) external {
        if (value == 0) revert ZeroAmount();
        address sender = msg.sender;
        Lock storage l = _locks[sender];
        if (l.amount == 0) revert NoLock();
        SafeToken.safeTransferFrom(address(_crv), sender, address(this), value);
        l.amount += int128(uint128(value));
        if (_lockerIndex[sender] == 0) {
            _lockers.push(sender);
            _lockerIndex[sender] = _lockers.length;
        }
    }

    function _checkerPass(address sender) private view returns (bool) {
        if (_checkerBlock) return false;
        return IWalletCheckerModel(_checker).check(sender);
    }

    // ------------------------------- fixture controls ---------------------

    function setCheckerBlock(bool blocked) external {
        _checkerBlock = blocked;
    }
}
