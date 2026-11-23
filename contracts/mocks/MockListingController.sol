// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IListingController} from "../interfaces/IListingController.sol";

/// @title MockListingController
/// @notice Test-only scheduled-weight controller fixture modelling the upstream
/// GaugeController points layout (S1 semantics): `get_gauge_weight` returns
/// `points_weight[gauge][time_weight[gauge]].bias`; admin changes and additions
/// write the NEXT Thursday scheduled point while updating `time_weight`
/// immediately. Explicitly NOT the real veCRV slope/power implementation: no
/// slope decay, no voting-power limits, no minter. This model boundary is
/// disclosed here and in the README.
contract MockListingController is IListingController {
    struct Point {
        uint256 bias;
    }

    struct GaugeState {
        bool registered;
        int128 kind;
        uint256 timeWeight;
        uint256[] pointTimes;
        mapping(uint256 => Point) points;
    }

    address private _dao;
    address private _lister;
    int128 private _gaugeTypeCount;
    mapping(address => GaugeState) private _gauges;
    uint256 private _addCalls;
    bool private _readsRevert;
    bool private _addRevert;

    error NotDao();
    error NotAuthorized();
    error ListerAlreadySet();
    error BadLister();
    error GaugeNotAdded();
    error GaugeAlreadyAdded();
    error BadGaugeType();
    error AddFailed();
    error ReadFailed();

    /// @notice Establish the upstream DAO fixture admin and positive count of
    /// valid types.
    constructor(address dao_, int128 gaugeTypeCount_) {
        require(dao_ != address(0), "dao zero");
        require(gaugeTypeCount_ > 0, "types");
        _dao = dao_;
        _gaugeTypeCount = gaugeTypeCount_;
    }

    /// @notice Immediate permanent registry addition. Permitted by the DAO or
    /// the designated lister to model the composed GaugeAdder/admin path; this
    /// does NOT claim mainnet GaugeController grants two independent raw admin
    /// roles. Public+virtual (ABI-identical to external) so narrow test-local
    /// faulty deployments can extend the REAL registration behavior.
    function add_gauge(address gauge, int128 gaugeType, uint256 weight) public virtual {
        if (msg.sender != _dao && msg.sender != _lister) revert NotAuthorized();
        if (_addRevert) revert AddFailed();
        if (gaugeType < 0 || gaugeType >= _gaugeTypeCount) revert BadGaugeType();
        GaugeState storage st = _gauges[gauge];
        if (st.registered) revert GaugeAlreadyAdded();
        st.registered = true;
        st.kind = gaugeType;
        uint256 nextTime = _epochStart(block.timestamp) + WEEK;
        _writePoint(st, nextTime, weight);
        st.timeWeight = nextTime;
        _addCalls += 1;
    }

    /// @notice Return the REAL controller's latest scheduled raw bias, exactly
    /// as `points_weight[gauge][time_weight[gauge]].bias`. Observation/test-only
    /// surface (S20): the product's declared controller dependency is
    /// add/type/count only; witnesses keep this read through the concrete mock
    /// (and, on fork, the real venue) types. Virtual so a test-local deployment
    /// can fault ONLY this read while add/membership stay functional (exec7:
    /// proving paid admission needs no weight read).
    function get_gauge_weight(address gauge) external view virtual returns (uint256) {
        _checkRead();
        GaugeState storage st = _gauges[gauge];
        return st.points[st.timeWeight].bias;
    }

    /// @notice Return type; revert for a gauge absent from the permanent
    /// registry.
    function gauge_types(address gauge) external view returns (int128) {
        _checkRead();
        GaugeState storage st = _gauges[gauge];
        if (!st.registered) revert GaugeNotAdded();
        return st.kind;
    }

    function n_gauge_types() external view returns (int128) {
        _checkRead();
        return _gaugeTypeCount;
    }

    /// @notice DAO-only, one-time setup of the wrapper-authorized add path;
    /// nonzero with code.
    function setLister(address lister_) external {
        if (msg.sender != _dao) revert NotDao();
        if (_lister != address(0)) revert ListerAlreadySet();
        if (lister_ == address(0) || lister_.code.length == 0) revert BadLister();
        _lister = lister_;
    }

    /// @notice DAO-only emissions-weight change: update next-week scheduled
    /// bias and time_weight; do not change the gauge flag. Require registered
    /// gauge. Weight is an emissions fact only — never a kill oracle under A2.
    function change_gauge_weight(address gauge, uint256 weight) external {
        if (msg.sender != _dao) revert NotDao();
        GaugeState storage st = _gauges[gauge];
        if (!st.registered) revert GaugeNotAdded();
        uint256 nextTime = _epochStart(block.timestamp) + WEEK;
        _writePoint(st, nextTime, weight);
        st.timeWeight = nextTime;
    }

    /// @notice Test-only voting surrogate: require membership, add raw scheduled
    /// weight for next week. Upstream GaugeController propagates the previous
    /// point before voting and combines old bias with the new increment
    /// (GaugeController.vy _get_weight / voting), so the next bias carries
    /// forward from the CURRENT scheduled point, never from an unwritten future
    /// slot. Explicitly NOT the real veCRV power/slope implementation.
    function voteForGauge(address gauge, uint256 addedWeight) external {
        GaugeState storage st = _gauges[gauge];
        if (!st.registered) revert GaugeNotAdded();
        uint256 nextTime = _epochStart(block.timestamp) + WEEK;
        uint256 nextBias = st.points[st.timeWeight].bias + addedWeight;
        _writePoint(st, nextTime, nextBias);
        st.timeWeight = nextTime;
    }

    /// @notice Latest scheduled-point timestamp, matching the upstream view
    /// concept.
    function time_weight(address gauge) external view returns (uint256) {
        _checkRead();
        return _gauges[gauge].timeWeight;
    }

    /// @notice Test-only find latest stored scheduled weight at/before
    /// epochStart(timestamp), or zero before the first scheduled point. Show
    /// next-week effectiveness separately from immediate get_gauge_weight
    /// visibility.
    function effectiveWeight(address gauge, uint256 timestamp) external view returns (uint256) {
        _checkRead();
        GaugeState storage st = _gauges[gauge];
        uint256 floor = _epochStart(timestamp);
        uint256 bestTime = 0;
        uint256 len = st.pointTimes.length;
        // Scheduled points are always written at epochStart(x) + WEEK > 0, so
        // bestTime == 0 can only mean "no stored point at/before the floor".
        for (uint256 i = 0; i < len; ++i) {
            uint256 t = st.pointTimes[i];
            if (t <= floor && t > bestTime) {
                bestTime = t;
            }
        }
        if (bestTime == 0) return 0;
        return st.points[bestTime].bias;
    }

    /// @notice Observe immediate additions.
    function addCalls() external view returns (uint256) {
        return _addCalls;
    }

    /// @notice Inject getter failure.
    function setReadsRevert(bool enabled) external {
        _readsRevert = enabled;
    }

    /// @notice Inject atomic admission failure.
    function setAddRevert(bool enabled) external {
        _addRevert = enabled;
    }

    uint256 private constant WEEK = 604800;

    function _epochStart(uint256 t) private pure returns (uint256) {
        return (t / WEEK) * WEEK;
    }

    function _checkRead() private view {
        if (_readsRevert) revert ReadFailed();
    }

    function _writePoint(GaugeState storage st, uint256 time, uint256 bias) private {
        bool known = false;
        uint256 len = st.pointTimes.length;
        for (uint256 i = 0; i < len; ++i) {
            if (st.pointTimes[i] == time) {
                known = true;
                break;
            }
        }
        if (!known) st.pointTimes.push(time);
        st.points[time].bias = bias;
    }
}
