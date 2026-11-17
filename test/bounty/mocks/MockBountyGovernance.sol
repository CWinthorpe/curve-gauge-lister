// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {
    IAgent,
    IKillProxy,
    ISupportedFactory,
    ISupportedGauge
} from "../../../contracts/interfaces/IBountyGovernance.sol";
import {BountyScripts} from "../../../contracts/libraries/BountyScripts.sol";

/// @title MockWalletChecker
/// @notice veCRV smart-wallet checker model: configurable `check(address)`,
/// including the deployed-true behavior and a blocking mode.
contract MockWalletChecker {
    bool private _allow = true;

    function check(address) external view returns (bool) {
        return _allow;
    }

    function setAllow(bool allow_) external {
        _allow = allow_;
    }
}

/// @title MockSupportedFactory
/// @notice Stableswap-NG factory model. `admin()` is the gauge kill-route
/// identity; the admin is the AMM owner proxy in the honest wiring.
contract MockSupportedFactory is ISupportedFactory {
    address private _admin;

    error NotDao();

    constructor(address admin_) {
        require(admin_ != address(0), "zero");
        _admin = admin_;
    }

    function admin() external view returns (address) {
        return _admin;
    }

    /// @notice Fixture transfer of factory administration (models the DAO-only
    /// `set_admin` route for changed-role rejection tests).
    function setAdmin(address admin_) external {
        require(admin_ != address(0), "zero");
        _admin = admin_;
    }
}

/// @title GovernanceGauge
/// @notice Gauge provenance model: constructor-recorded factory, real
/// `set_killed(bool)` authorization (factory admin only), `is_killed()` with
/// labelled read faults for the bounded-read no-award tests.
contract GovernanceGauge is ISupportedGauge {
    address private immutable _lpToken;
    address private immutable _factory;
    bool private _killed;

    // ------------------------- labelled is_killed faults ------------------
    uint8 public constant IF_NONE = 0;
    uint8 public constant IF_REVERT = 1;
    uint8 public constant IF_MALFORMED = 2; // 31-byte return
    uint8 public constant IF_BOMB = 3; // oversized (> 8192-byte) return
    uint8 public constant IF_GAS = 4; // burns beyond the 200k read cap

    uint8 private _flagFault;

    error FlagReadFailed();

    constructor(address lpToken_, address factory_) {
        require(lpToken_ != address(0) && factory_ != address(0), "zero");
        _lpToken = lpToken_;
        _factory = factory_;
    }

    function lp_token() external view returns (address) {
        return _lpToken;
    }

    function factory() external view returns (address) {
        return _factory;
    }

    function is_killed() external view returns (bool) {
        if (_flagFault == IF_REVERT) revert FlagReadFailed();
        if (_flagFault == IF_MALFORMED) {
            uint256 value = _killed ? 1 : 0;
            assembly {
                mstore(0, value)
                return(0, 31)
            }
        }
        if (_flagFault == IF_BOMB) {
            bytes memory bomb = new bytes(9000);
            assembly {
                return(add(bomb, 0), add(32, 9000))
            }
        }
        if (_flagFault == IF_GAS) {
            uint256 x;
            for (uint256 i = 0; i < 1; ++i) {
                // unbounded burn loop: the capped read must fail closed
                while (true) {
                    x += 1;
                    if (x == type(uint256).max) {
                        break;
                    }
                }
            }
            return x != 0;
        }
        return _killed;
    }

    /// @notice Real gauge authorization: only the factory admin (the AMM owner
    /// proxy in the honest wiring) may set the flag.
    function set_killed(bool killed) external {
        require(msg.sender == ISupportedFactory(_factory).admin(), "not factory admin");
        _killed = killed;
    }

    /// @notice 0 none, 1 revert, 2 malformed 31-byte, 3 return-data bomb.
    function setFlagFault(uint8 mode) external {
        require(mode <= 4, "unknown fault");
        _flagFault = mode;
    }
}

/// @title MockKillProxy
/// @notice AMM owner proxy model. `set_killed(address)` is authorized only by
/// `dao()` (the Ownership Agent) or `emergency_dao()` (the emergency Safe)
/// and hardcodes the gauge boolean to true; the generic `execute` route
/// models the DAO-only unkill/ownership path.
contract MockKillProxy is IKillProxy {
    address private _dao;
    address private _emergencyDao;

    error NotDao();
    error NotEmergency();

    constructor(address dao_, address emergencyDao_) {
        require(dao_ != address(0) && emergencyDao_ != address(0), "zero");
        _dao = dao_;
        _emergencyDao = emergencyDao_;
    }

    function dao() external view returns (address) {
        return _dao;
    }

    function emergency_dao() external view returns (address) {
        return _emergencyDao;
    }

    function set_killed(address gauge) external {
        require(msg.sender == _dao || msg.sender == _emergencyDao, "not dao");
        GovernanceGauge(gauge).set_killed(true);
    }

    /// @notice Generic DAO-only forwarding (real AMM `execute(address,bytes)`).
    function execute(address target, bytes calldata data) external {
        if (msg.sender != _dao) revert NotDao();
        (bool ok, bytes memory ret) = target.call(data);
        _bubble(ok, ret);
    }

    function setDao(address dao_) external {
        if (msg.sender != _dao) revert NotDao();
        _dao = dao_;
    }

    function setEmergencyDao(address emergency_) external {
        if (msg.sender != _dao) revert NotDao();
        _emergencyDao = emergency_;
    }

    function _bubble(bool ok, bytes memory ret) private pure {
        if (!ok) {
            assembly {
                revert(add(ret, 0x20), mload(ret))
            }
        }
    }
}

/// @title MockOwnershipAgent
/// @notice Aragon Agent model: `execute(address,uint256,bytes)` is gated to
/// the configured script executor (the CALLS_ROLE holder), forwards the call
/// with the given value and propagates any failure atomically (the whole
/// executeVote rolls back, including Voting's executed flag).
contract MockOwnershipAgent is IAgent {
    address private _implementation;
    address private _scriptExecutor;
    bool private _executeBlocked;

    error NotExecutor();
    error ExecuteBlocked();
    error TargetFailed();
    error NotDao();

    constructor(address implementation_, address scriptExecutor_) {
        require(implementation_ != address(0), "zero impl");
        _implementation = implementation_;
        _scriptExecutor = scriptExecutor_;
    }

    function implementation() external view returns (address) {
        return _implementation;
    }

    function execute(address target, uint256 value, bytes calldata data) external {
        if (msg.sender != _scriptExecutor) revert NotExecutor();
        if (_executeBlocked) revert ExecuteBlocked();
        (bool ok, bytes memory ret) = target.call{value: value}(data);
        if (!ok) {
            assembly {
                revert(add(ret, 0x20), mload(ret))
            }
        }
    }

    /// @notice Fixture maintenance controls (labelled as role pranks in the
    /// fork suite; here they are plain test seams).
    function setScriptExecutor(address executor_) external {
        _scriptExecutor = executor_;
    }

    function setImplementation(address impl_) external {
        _implementation = impl_;
    }

    function setExecuteBlocked(bool blocked) external {
        _executeBlocked = blocked;
    }
}

/// @title MockCallsScript
/// @notice Aragon CallsScript executor model: entries are
/// 20-byte target || uint32 big-endian calldata length || calldata; each
/// entry target is called with its data; ANY entry failure reverts the whole
/// script (and, through the caller chain, Voting's executed flag).
contract MockCallsScript {
    address private _voting;

    error NotVoting();
    error BadScriptType();
    error TrailingBytes();
    error EntryFailed();

    constructor(address voting_) {
        require(voting_ != address(0), "zero");
        _voting = voting_;
    }

    function execScript(bytes calldata script, bytes calldata, address[3] calldata) external {
        if (msg.sender != _voting) revert NotVoting();
        if (script.length < 4 || bytes4(script[0:4]) != BountyScripts.CALLS_SCRIPT_TYPE) revert BadScriptType();
        uint256 i = 4;
        while (i < script.length) {
            if (i + 24 > script.length) revert BadScriptType();
            address target = address(bytes20(script[i:i + 20]));
            uint256 len = uint256(uint32(bytes4(script[i + 20:i + 24])));
            if (i + 24 + len > script.length) revert TrailingBytes();
            (bool ok,) = target.call(script[i + 24:i + 24 + len]);
            if (!ok) revert EntryFailed();
            i += 24 + len;
        }
        if (i != script.length) revert TrailingBytes();
    }

    function setVoting(address voting_) external {
        _voting = voting_;
    }
}
