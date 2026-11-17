// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC20Minimal} from "../interfaces/IERC20Minimal.sol";
import {IFeeDistributor} from "../interfaces/IFeeDistributor.sol";
import {SafeToken} from "./SafeToken.sol";
import {BountyScripts} from "./BountyScripts.sol";

/// @title FeeDistributorAccounting
/// @notice Shared exact-FD transfer/accounting routine for V2 confiscations
/// and GaugeBounty slash flushes (plans/BOUNTY-PLAN.md §1.1, §4.1, §4.3).
/// Its preflight and postflight are the accepted auditfix001 policy; V1 is
/// NOT modified to consume it. No public/external functions; no storage.
/// @dev The failure selectors are the accepted ones: `DistributorUnusable`
/// for destination/accounting failures and `ConfiscationDeltaMismatch` for
/// custody-delta failures, so archived attack replays stay recognizable.
library FeeDistributorAccounting {
    error DistributorUnusable();
    error ConfiscationDeltaMismatch();

    uint256 private constant WEEK = 604800;
    uint256 private constant ACCOUNTING_HORIZON_WEEKS = 20;

    /// @dev Accepted freshness/accounting policy, evaluated IN THIS ORDER:
    /// code, token identity, not killed, then cursor: `t != 0`, `t <= now`
    /// and `now - floor(t/WEEK)*WEEK <= 20*WEEK`. The boundary is the
    /// cursor's WEEK FLOOR, not t+20 weeks: H = floor(t/W)*W + 20W is
    /// allowed, H+1 rejected.
    function preflight(address fd, address token) internal view {
        if (fd.code.length == 0) revert DistributorUnusable();
        if (IFeeDistributor(fd).token() != token) revert DistributorUnusable();
        if (IFeeDistributor(fd).is_killed()) revert DistributorUnusable();
        uint256 t = IFeeDistributor(fd).last_token_time();
        if (t == 0) revert DistributorUnusable();
        if (t > block.timestamp) revert DistributorUnusable();
        if (block.timestamp - BountyScripts.weekFloor(t) > ACCOUNTING_HORIZON_WEEKS * WEEK) {
            revert DistributorUnusable();
        }
    }

    /// @dev Exact direct transfer from the calling contract to the pinned FD
    /// with two-sided delta verification, then MANDATORY same-transaction
    /// accounting: `checkpoint_token()` without catching failure, requiring
    /// `last_token_time == now` and `token_last_balance == balanceOf(fd)`.
    /// No approval to the FD, never `burn(address)`. A later failure in the
    /// enclosing transaction rolls this back together with it.
    function depositAndAccount(address fd, address token, uint256 amount) internal {
        uint256 senderBefore = IERC20Minimal(token).balanceOf(address(this));
        uint256 fdBefore = IERC20Minimal(token).balanceOf(fd);
        SafeToken.safeTransfer(token, fd, amount);
        if (IERC20Minimal(token).balanceOf(address(this)) != senderBefore - amount) {
            revert ConfiscationDeltaMismatch();
        }
        if (IERC20Minimal(token).balanceOf(fd) != fdBefore + amount) revert ConfiscationDeltaMismatch();

        IFeeDistributor(fd).checkpoint_token();
        if (IFeeDistributor(fd).last_token_time() != block.timestamp) revert DistributorUnusable();
        if (IFeeDistributor(fd).token_last_balance() != IERC20Minimal(token).balanceOf(fd)) {
            revert DistributorUnusable();
        }
    }
}
