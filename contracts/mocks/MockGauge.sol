// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ICurveGauge} from "../interfaces/ICurveGauge.sol";

/// @title MockGauge
/// @notice Test-only same-chain LP-token gauge fixture. Storage: immutable LP
/// address, bool killed, and a killed-read fault toggle — no separate escrow
/// kill signal.
contract MockGauge is ICurveGauge {
    error KilledReadFailed();

    address private immutable _lpToken;
    bool private _killed;
    bool private _killedReadRevert;

    /// @notice Set immutable LP identity.
    constructor(address lpToken_) {
        _lpToken = lpToken_;
    }

    function lp_token() external view returns (address) {
        return _lpToken;
    }

    function is_killed() external view returns (bool) {
        if (_killedReadRevert) revert KilledReadFailed();
        return _killed;
    }

    /// @notice Test-only independent gauge kill/unkill switch for admission
    /// AND settlement; never changes weight. The unrestricted fixture setter
    /// does not model mainnet set_killed authorization — that binding is a
    /// deployment obligation under A2.4, not a property this mock proves.
    function setKilled(bool killed) external {
        _killed = killed;
    }

    /// @notice Test-only killed-read fault injection: make `is_killed()`
    /// revert with `KilledReadFailed()` while preserving stored kill state and
    /// LP identity.
    function setKilledReadRevert(bool enabled) external {
        _killedReadRevert = enabled;
    }
}
