// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {GaugeControllerAdmin} from "../../contracts/GaugeControllerAdmin.sol";

/// @dev NEW test-local cheatcode declarations for the router witnesses only
/// (repo discipline: the shared TestBase Vm interface is never edited; this
/// is the same cheatcode dispatcher, extra subset).
interface RouterVm {
    struct Log {
        bytes32[] topics;
        bytes data;
        address emitter;
    }

    function readFile(string memory path) external view returns (string memory);
    function parseJson(string calldata json, string calldata key) external pure returns (bytes memory);
    function parseJsonString(string calldata json, string calldata key) external pure returns (string memory);
    function parseJsonBool(string calldata json, string calldata key) external pure returns (bool);
    function keyExistsJson(string calldata json, string calldata key) external pure returns (bool);
    function parseJsonKeys(string calldata json, string calldata key) external pure returns (string[] memory);
    function deal(address who, uint256 newBalance) external;
    function load(address account, bytes32 slot) external view returns (bytes32);
    function expectCall(address callee, bytes calldata data, uint256 expectedCount) external;
    function recordLogs() external;
    function getRecordedLogs() external view returns (Log[] memory);
}

/// @dev Raw controller rejection the mock emits for invalid admin attempts,
/// mirroring the upstream `assert msg.sender == self.admin` shape but with
/// recognizable data so bubbling can be told apart from R's own guards.
/// @notice Test-only model of the upstream GaugeController (role C) for the
/// router witness matrix ONLY. It models the admin-gated add/type/weight
/// surface, the two-step commit/apply ownership state machine with the real
/// quirk that apply does NOT clear future_admin, plus explicit fault-
/// injection modes (hostile C modelling per the witness matrix evidence
/// rules). It is not evidence of real-C behavior; the fork suite witnesses
/// against the pinned real controller separately.
contract RouterControllerMock {
    // ---- storage (test-local; no layout claim) ----
    address public admin;
    address public future_admin;
    int128 private _nTypes;
    uint256 private _nGauges;
    mapping(address => int128) private _gaugeType;
    mapping(address => bool) private _registered;
    mapping(address => uint256) private _weight;
    mapping(int128 => uint256) private _typeWeight;
    string[] private _typeNames;

    // ---- observation ----
    uint256 public addCalls; // successful registered adds
    uint256 public addAttempts; // every entry, incl. rejected
    address public lastAddSender;
    uint256 public markCalls;
    address public lastMarkTarget;
    address public lastMarkSender;
    uint256 public commitCalls;
    uint256 public applyCalls;
    uint256 public weightChangeCalls;
    uint256 public typeWeightChangeCalls;

    // ---- injection modes ----
    uint8 public addMode; // 0 normal, 1 revert data, 2 revert empty
    uint256 public defaultInitialWeight; // used by the raw 2-arg overload
    uint8 public commitMode; // 0 normal, 1 revert, 2 lie (store wrongFuture)
    uint8 public applyMode; // 0 normal, 1 revert, 2 lie (admin := wrongAdmin)
    uint8 public absentMode; // 0 revert Absent(), 1 revert empty bytes
    uint8 public typesMode; // 0 normal, 1 lie (+100), 2 malformed (31 bytes)
    address public wrongFuture;
    address public wrongAdmin;

    // ---- reentry hook ----
    // point bit flags: 1=after add, 2=after apply admin write
    address public hookTarget;
    bytes public hookData;
    bool public hookCatch; // true: swallow hook failure; false: bubble
    uint256 public hookPoint;

    error MockNotAdmin();
    error MockBadType(int128 gaugeType);
    error MockAlreadyAdded(address gauge);
    error MockRejected(); // nonempty add failure payload
    error MockAbsent(); // gauge_types absence payload (absentMode 0)
    error MockNotRegistered();

    event NewGauge(address gauge, int128 gaugeType, uint256 weight);
    event MockTypeAdded(string name, int128 index, uint256 weight);
    event MockGaugeWeight(address gauge, uint256 weight);
    event MockTypeWeight(int128 gaugeType, uint256 weight);

    constructor(address admin_, int128 initialTypes) {
        admin = admin_;
        require(initialTypes > 0, "types");
        for (int128 i = 0; i < initialTypes; ++i) {
            _typeNames.push(string(abi.encodePacked("type-", _itoa(uint256(int256(i))))));
        }
        _nTypes = initialTypes;
    }

    // ------------------------------------------------------------------
    // admin-gated controller surface (mirrors upstream authority rules)
    // ------------------------------------------------------------------

    function add_gauge(address gauge, int128 gaugeType, uint256 weight) external {
        _add(gauge, gaugeType, weight);
    }

    /// @dev The raw two-argument overload (upstream default weight).
    function add_gauge(address gauge, int128 gaugeType) external {
        _add(gauge, gaugeType, defaultInitialWeight);
    }

    function _add(address gauge, int128 gaugeType, uint256 weight) private {
        if (msg.sender != admin) revert MockNotAdmin();
        addAttempts += 1;
        lastAddSender = msg.sender;
        if (addMode == 1) revert MockRejected();
        if (addMode == 2) _revertEmpty();
        if (gaugeType < 0 || gaugeType >= _nTypes) revert MockBadType(gaugeType);
        if (_registered[gauge]) revert MockAlreadyAdded(gauge);
        _registered[gauge] = true;
        _gaugeType[gauge] = gaugeType;
        _weight[gauge] = weight;
        _nGauges += 1;
        addCalls += 1;
        emit NewGauge(gauge, gaugeType, weight);
        _runHook(1);
    }

    function add_type(string calldata name) external {
        if (msg.sender != admin) revert MockNotAdmin();
        _addType(name, 100_000);
    }

    function add_type(string calldata name, uint256 weight) external {
        if (msg.sender != admin) revert MockNotAdmin();
        _addType(name, weight);
    }

    function _addType(string memory name, uint256 weight) private {
        _typeNames.push(name);
        int128 idx = _nTypes;
        _nTypes += 1;
        _typeWeight[idx] = weight;
        emit MockTypeAdded(name, idx, weight);
    }

    function change_gauge_weight(address gauge, uint256 weight) external {
        if (msg.sender != admin) revert MockNotAdmin();
        if (!_registered[gauge]) revert MockNotRegistered();
        _weight[gauge] = weight;
        weightChangeCalls += 1;
        emit MockGaugeWeight(gauge, weight);
    }

    function change_type_weight(int128 gaugeType, uint256 weight) external {
        if (msg.sender != admin) revert MockNotAdmin();
        _typeWeight[gaugeType] = weight;
        typeWeightChangeCalls += 1;
        emit MockTypeWeight(gaugeType, weight);
    }

    function gauge_types(address gauge) external view returns (int128) {
        if (!_registered[gauge]) {
            if (absentMode == 1) _revertEmpty();
            revert MockAbsent();
        }
        if (typesMode == 2) {
            // malformed upstream return: 31 bytes must never fabricate a value
            assembly ("memory-safe") {
                mstore(0x00, 0x7)
                return(0x00, 0x1F)
            }
        }
        int128 t = _gaugeType[gauge];
        if (typesMode == 1) return t + 100; // lie: membership read disagrees
        return t;
    }

    function n_gauge_types() external view returns (int128) {
        return _nTypes;
    }

    function get_gauge_weight(address gauge) external view returns (uint256) {
        return _weight[gauge];
    }

    function type_weight(int128 gaugeType) external view returns (uint256) {
        return _typeWeight[gaugeType];
    }

    function get_type_name(uint256 index) external view returns (string memory) {
        return _typeNames[index];
    }

    function n_gauges() external view returns (int128) {
        return int128(int256(_nGauges));
    }

    function registered(address gauge) external view returns (bool) {
        return _registered[gauge];
    }

    function echoBytes(bytes calldata payload) external view returns (bytes memory) {
        return payload;
    }

    /// @dev Accepts ONLY empty calldata (models the controller's own
    /// zero-selector path for the Executed selector=0 witness); any unknown
    /// nonempty selector still dies at dispatch like a fallback-less
    /// contract.
    fallback() external {
        // accept only sub-selector inputs (models the Executed selector=0
        // lane); any 4+-byte unknown selector reverts empty, exactly like a
        // contract with no fallback arm.
        if (msg.data.length >= 4) {
            assembly ("memory-safe") {
                revert(0x00, 0x00)
            }
        }
    }

    function commit_transfer_ownership(address successor) external {
        if (msg.sender != admin) revert MockNotAdmin();
        commitCalls += 1;
        if (commitMode == 1) revert MockRejected();
        future_admin = commitMode == 2 ? wrongFuture : successor;
    }

    function apply_transfer_ownership() external {
        if (msg.sender != admin) revert MockNotAdmin();
        applyCalls += 1;
        if (applyMode == 1) revert MockRejected();
        admin = applyMode == 2 ? wrongAdmin : future_admin;
        // Real controller: future_admin is NOT cleared by apply.
        _runHook(2);
    }

    /// @dev Recording destination for the pinned-target witnesses.
    function mark(address sentinel, uint256 tag) external {
        markCalls += 1;
        lastMarkTarget = sentinel;
        lastMarkSender = msg.sender;
        // hook point 4: generic-execute callback lane (nonretiring call)
        _runHook(4);
    }

    // ------------------------------------------------------------------
    // test-side configuration (models hostile/faulty upstream only)
    // ------------------------------------------------------------------

    function setAddMode(uint8 mode) external {
        addMode = mode;
    }

    function setDefaultInitialWeight(uint256 w) external {
        defaultInitialWeight = w;
    }

    function setCommitMode(uint8 mode, address lieTo) external {
        commitMode = mode;
        wrongFuture = lieTo;
    }

    function setApplyMode(uint8 mode, address lieTo) external {
        applyMode = mode;
        wrongAdmin = lieTo;
    }

    function setAbsentMode(uint8 mode) external {
        absentMode = mode;
    }

    /// @dev Hostile-C modelling only (matrix evidence rules): displace the
    /// incumbent without going through R, to witness the NotControllerAdmin
    /// guard, and force the raw future_admin slot to model a local/raw
    /// mismatch state. Never used against the real controller.
    function forceAdmin(address who) external {
        admin = who;
    }

    function forceFuture(address who) external {
        future_admin = who;
    }

    function setTypesMode(uint8 mode) external {
        typesMode = mode;
    }

    function setHook(address target, bytes calldata data, bool catchFailure, uint256 point) external {
        hookTarget = target;
        hookData = data;
        hookCatch = catchFailure;
        hookPoint = point;
    }

    function _runHook(uint256 point) private {
        if (hookTarget == address(0) || (hookPoint & point) == 0) return;
        (bool ok, bytes memory ret) = hookTarget.call(hookData);
        if (!ok && !hookCatch) {
            assembly ("memory-safe") {
                revert(add(ret, 32), mload(ret))
            }
        }
    }

    function _revertEmpty() private pure {
        assembly ("memory-safe") {
            revert(0x00, 0x00)
        }
    }

    function _itoa(uint256 v) private pure returns (string memory) {
        bytes memory b = new bytes(1);
        b[0] = bytes1(uint8(48 + v % 10));
        return string(b);
    }
}

/// @notice The router-side counterpart contract playing role D. It is the
/// literal dao_ pinned in R, so a controller-initiated callback into this
/// shim re-enters R as an AUTHORIZED caller (matrix: lock witnesses must not
/// be masked by an earlier onlyDao rejection).
contract RouterDaoShim {
    GaugeControllerAdmin public r;

    bool public planEnabled;
    bytes public planData;
    bool public bubble; // true: propagate reentry failure; false: swallow

    bool public lastInnerAttempted;
    bool public lastInnerOk;
    bytes public lastInnerData;
    uint256 public hookCalls;

    function setRouter(GaugeControllerAdmin r_) external {
        require(address(r) == address(0), "once");
        r = r_;
    }

    function setPlan(bytes calldata data, bool bubbleFailure) external {
        planData = data;
        bubble = bubbleFailure;
        planEnabled = true;
    }

    function clearPlan() external {
        planEnabled = false;
    }

    /// @dev Called by the mock controller hook. Attempts the planned
    /// reentrant R mutator call as this contract (== R.dao).
    function onControllerHook() external {
        hookCalls += 1;
        if (!planEnabled) return;
        // one-shot: exactly one bounded reentry attempt per plan (matrix:
        // avoid recursion/out-of-gas masquerading as sensitivity).
        planEnabled = false;
        lastInnerAttempted = true;
        (bool ok, bytes memory ret) = address(r).call(planData);
        lastInnerOk = ok;
        lastInnerData = ret;
        if (!ok && bubble) {
            assembly ("memory-safe") {
                revert(add(ret, 32), mload(ret))
            }
        }
    }

    // Convenience direct lanes (used when the test wants real execution as D
    // rather than a prank): forward one call to R from this address.
    function callR(bytes calldata data) external returns (bool ok, bytes memory ret) {
        (ok, ret) = address(r).call(data);
    }
}

/// @notice Granted-adder counterpart contract for the add lane witnesses and
/// for adder-authorized reentry through the controller hook.
contract RouterAdderShim {
    GaugeControllerAdmin public r;

    bool public planEnabled;
    bytes public planData;
    bool public bubble;
    bool public lastInnerAttempted;
    bool public lastInnerOk;
    bytes public lastInnerData;
    uint256 public hookCalls;

    function setRouter(GaugeControllerAdmin r_) external {
        require(address(r) == address(0), "once");
        r = r_;
    }

    function setPlan(bytes calldata data, bool bubbleFailure) external {
        planData = data;
        bubble = bubbleFailure;
        planEnabled = true;
    }

    function onControllerHook() external {
        hookCalls += 1;
        if (!planEnabled) return;
        // one-shot: exactly one bounded reentry attempt per plan (matrix:
        // avoid recursion/out-of-gas masquerading as sensitivity).
        planEnabled = false;
        lastInnerAttempted = true;
        (bool ok, bytes memory ret) = address(r).call(planData);
        lastInnerOk = ok;
        lastInnerData = ret;
        if (!ok && bubble) {
            assembly ("memory-safe") {
                revert(add(ret, 32), mload(ret))
            }
        }
    }

    /// @dev Plain authorized add when not hooked.
    function addViaRouter(address gauge, int128 gaugeType, uint256 weight) external {
        r.add_gauge(gauge, gaugeType, weight);
    }
}

/// @notice Plain code-bearing address for "reviewed mock successor"
/// nominations and delegatecall-storage-escape sentinels.
contract RouterSuccessorMock {
    uint256 public touched;
    bool public receivedAdmin;

    function poke() external {
        touched += 1;
    }

    function noteAdmin() external {
        receivedAdmin = true;
    }
}

/// @notice Code-bearing recipient used as the execute-payload sentinel for
/// the pinned-target witness: if the router ever diverted the call, this
/// contract records it (markRecords).
contract RouterSentinel {
    uint256 public markRecords;
    address public lastMarkCaller;

    function mark(address, uint256) external {
        markRecords += 1;
        lastMarkCaller = msg.sender;
    }
}
