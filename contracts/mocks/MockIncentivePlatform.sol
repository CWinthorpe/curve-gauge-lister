// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IIncentivePlatform} from "../interfaces/IIncentivePlatform.sol";
import {IERC20Minimal} from "../interfaces/IERC20Minimal.sol";
import {SafeToken} from "../libraries/SafeToken.sol";

/// @title MockIncentivePlatform
/// @notice Test-only funded platform ingress. Deploy TWO instances, representing
/// Votium and VoteMarket ingress respectively. Normal receipts are keyed by the
/// original maturity while executionEpoch is epochStart(now). Token balances
/// must back receipt amounts. No withdraw/rescue API. This mock emulates the
/// defined funded ingress, not Votium's biweekly computation or VoteMarket's
/// bridge/claims.
contract MockIncentivePlatform is IIncentivePlatform {
    uint256 private constant WEEK = 604800;

    struct Deposit {
        uint256 amount;
        uint256 executionEpoch;
        bytes32 receipt;
    }

    address private immutable _token;
    address private _lister;
    mapping(bytes32 => Deposit) private _deposits;
    uint256 private _depositCount;
    uint256 private _nonce;
    uint8 private _failureMode;
    address private _reentryTarget;
    bytes private _reentryData;
    bool private _reentrySucceeded;

    error NotLister();
    error ListerAlreadySet();
    error BadLister();
    error UnknownFailureMode();
    error DuplicateDeposit();
    error DepositFailed();
    error ReceiptUnderfunded();

    /// @notice Fix reward token.
    constructor(address token_) {
        require(token_ != address(0), "zero token");
        _token = token_;
    }

    function rewardToken() external view returns (address) {
        return _token;
    }

    /// @notice Fixture view of the bound lister (auditfix001 §1/§4). The
    /// mock's unrestricted `setLister` is fixture-only setup and is NOT the
    /// production authorization model: production adapters bind through an
    /// owner-gated one-time `setLister`. Honest fixtures bind their own core;
    /// this getter must never return the caller just to pass readiness.
    function lister() external view returns (address) {
        return _lister;
    }

    /// @notice Deposit pulls real tokens, records gauge/scheduled epoch/
    /// execution epoch/gross amount and returns a unique nonzero receipt;
    /// duplicate gauge+scheduled epoch reverts.
    function deposit(address gauge, uint256 scheduledEpoch, uint256 amount) external returns (bytes32 receipt) {
        if (msg.sender != _lister) revert NotLister();
        uint8 mode = _failureMode;
        if (mode == 1) revert DepositFailed();

        bytes32 key = keccak256(abi.encode(gauge, scheduledEpoch));
        if ((mode == 0 || mode == 3) && _deposits[key].receipt != bytes32(0)) revert DuplicateDeposit();

        if (mode == 2) {
            // Return a receipt without pulling.
            return _makeReceipt(gauge, scheduledEpoch);
        }

        uint256 pull = amount;
        if (mode == 3) {
            // Underpull by one token unit: the mock still pulls what it asked
            // for and records the FULL-face receipt, so the product must catch
            // the one-unit shortfall on the lister's debit side.
            pull = amount - 1;
        }
        // SafeERC20 pull: supports empty-return tokens and rejects
        // false/malformed returns. The mock's own balance delta must equal the
        // pull it performed before any receipt is recorded — a taxed transfer
        // that delivers less than pulled cannot mint a funded-looking receipt.
        uint256 custodyBefore = IERC20Minimal(_token).balanceOf(address(this));
        SafeToken.safeTransferFrom(_token, msg.sender, address(this), pull);
        if (IERC20Minimal(_token).balanceOf(address(this)) != custodyBefore + pull) {
            revert ReceiptUnderfunded();
        }

        if (mode == 0 || mode == 3) {
            // Mode 3 presents a valid funded-looking receipt while pulling one
            // unit short; the product must catch the balance delta, not the
            // receipt shape.
            receipt = _makeReceipt(gauge, scheduledEpoch);
            _deposits[key] =
                Deposit({amount: amount, executionEpoch: (block.timestamp / WEEK) * WEEK, receipt: receipt});
            _depositCount += 1;
        }

        // During deposit attempt perform the configured low-level callback and
        // record success; callback failure need not make the outer normal
        // deposit fail.
        address target = _reentryTarget;
        if (target != address(0)) {
            (bool ok,) = target.call(_reentryData);
            _reentrySucceeded = ok;
        }

        if (mode == 4) {
            // Pull then return zero receipt.
            return bytes32(0);
        }
    }

    /// @notice One-time fixture authorization; deposits only from that lister,
    /// preventing outsider receipt spam.
    function setLister(address lister_) external {
        if (_lister != address(0)) revert ListerAlreadySet();
        if (lister_ == address(0) || lister_.code.length == 0) revert BadLister();
        _lister = lister_;
    }

    /// @notice 0 normal, 1 revert, 2 return receipt without pulling, 3
    /// underpull by one token unit, 4 pull then return zero receipt; unknown
    /// modes revert. These are test faults, not product menus.
    function setFailureMode(uint8 mode) external {
        if (mode > 4) revert UnknownFailureMode();
        _failureMode = mode;
    }

    /// @notice During deposit attempt perform the configured low-level callback
    /// and record success; callback failure need not make the outer normal
    /// deposit fail.
    function setReentry(address target, bytes calldata data) external {
        _reentryTarget = target;
        _reentryData = data;
        _reentrySucceeded = false;
    }

    /// @notice Inspect callback result.
    function reentrySucceeded() external view returns (bool) {
        return _reentrySucceeded;
    }

    /// @notice Inspect receipt and actual token funding evidence.
    function getDeposit(address gauge, uint256 scheduledEpoch)
        external
        view
        returns (uint256 amount, uint256 executionEpoch, bytes32 receipt)
    {
        Deposit storage d = _deposits[keccak256(abi.encode(gauge, scheduledEpoch))];
        return (d.amount, d.executionEpoch, d.receipt);
    }

    /// @notice Call/receipt count.
    function depositCount() external view returns (uint256) {
        return _depositCount;
    }

    function _makeReceipt(address gauge, uint256 scheduledEpoch) private returns (bytes32) {
        _nonce += 1;
        return keccak256(abi.encode(gauge, scheduledEpoch, _nonce, address(this)));
    }
}
