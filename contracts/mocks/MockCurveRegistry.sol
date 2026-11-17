// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ICurveRegistry} from "../interfaces/ICurveRegistry.sol";

/// @title MockCurveRegistry
/// @notice Test-only authenticated registry fixture. Unknown pool/handler and
/// invalid index revert; a known but unregistered pool returns false for
/// is_registered.
contract MockCurveRegistry is ICurveRegistry {
    struct PoolRecord {
        bool exists;
        bool registered;
        address lpToken;
        address[8] coins;
        uint256 nCoins;
    }

    struct GaugeRecord {
        bool exists;
        address gauge;
        int128 gaugeType;
    }

    mapping(address => mapping(uint256 => PoolRecord)) private _pools;
    mapping(address => mapping(uint256 => mapping(uint256 => GaugeRecord))) private _gauges;
    bool private _readsRevert;

    error UnknownPool();
    error UnknownGaugeIndex();
    error ReadFailed();

    /// @notice Empty authenticated registry fixture.
    constructor() {}

    /// @notice Set pool metadata and mark registered (allow invalid metadata
    /// for rejection tests).
    function setPool(address pool, uint256 handlerId, address lpToken, address[8] calldata coins, uint256 nCoins)
        external
    {
        PoolRecord storage rec = _pools[pool][handlerId];
        rec.exists = true;
        rec.registered = true;
        rec.lpToken = lpToken;
        rec.coins = coins;
        rec.nCoins = nCoins;
    }

    /// @notice Set trusted gauge/type pair, independent of controller membership.
    function setGauge(address pool, uint256 handlerId, uint256 gaugeIndex, address gauge, int128 gaugeType) external {
        GaugeRecord storage rec = _gauges[pool][handlerId][gaugeIndex];
        rec.exists = true;
        rec.gauge = gauge;
        rec.gaugeType = gaugeType;
    }

    /// @notice Toggle pool provenance for tests.
    function setRegistered(address pool, uint256 handlerId, bool registered) external {
        PoolRecord storage rec = _pools[pool][handlerId];
        if (!rec.exists) revert UnknownPool();
        rec.registered = registered;
    }

    /// @notice Inject dependency failure.
    function setReadsRevert(bool enabled) external {
        _readsRevert = enabled;
    }

    function is_registered(address pool, uint256 handlerId) external view returns (bool) {
        _check();
        PoolRecord storage rec = _pools[pool][handlerId];
        if (!rec.exists) revert UnknownPool();
        return rec.registered;
    }

    function get_lp_token(address pool, uint256 handlerId) external view returns (address) {
        _check();
        PoolRecord storage rec = _pools[pool][handlerId];
        if (!rec.exists) revert UnknownPool();
        return rec.lpToken;
    }

    function get_gauge(address pool, uint256 gaugeIndex, uint256 handlerId) external view returns (address) {
        _check();
        GaugeRecord storage rec = _gauges[pool][handlerId][gaugeIndex];
        if (!rec.exists) revert UnknownGaugeIndex();
        return rec.gauge;
    }

    function get_gauge_type(address pool, uint256 gaugeIndex, uint256 handlerId) external view returns (int128) {
        _check();
        GaugeRecord storage rec = _gauges[pool][handlerId][gaugeIndex];
        if (!rec.exists) revert UnknownGaugeIndex();
        return rec.gaugeType;
    }

    function get_n_coins(address pool, uint256 handlerId) external view returns (uint256) {
        _check();
        PoolRecord storage rec = _pools[pool][handlerId];
        if (!rec.exists) revert UnknownPool();
        return rec.nCoins;
    }

    function get_coins(address pool, uint256 handlerId) external view returns (address[8] memory) {
        _check();
        PoolRecord storage rec = _pools[pool][handlerId];
        if (!rec.exists) revert UnknownPool();
        return rec.coins;
    }

    function _check() private view {
        if (_readsRevert) revert ReadFailed();
    }
}
