// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IOwnershipVoting} from "../../../contracts/interfaces/IOwnershipVoting.sol";

/// @dev Extended escrow reads the Voting model needs (snapshot accounting).
/// Model boundary: `balanceOfAt`/`totalSupplyAt` return the CURRENT decayed
/// values (no per-block history); all governance predicates are enforced.
interface IVotingEscrowModel {
    function balanceOf(address) external view returns (uint256);
    function balanceOfAt(address, uint256) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function totalSupplyAt(uint256) external view returns (uint256);
}

/// @dev Aragon script-executor entrypoint as the deployed CallsScript exposes
/// it: `execScript(bytes,bytes,address[3])`.
interface IScriptExecutorModel {
    function execScript(bytes calldata script, bytes calldata input, address[3] calldata blacklist) external;
}

/// @title MockOwnershipVoting
/// @notice Faithful offline Ownership Voting model (plans/BOUNTY-PLAN.md
/// §5.1): enforces the real ACL gate, caller balance floor, creation cooldown,
/// start/snapshot fields, the full seven-day open guard, strictly-greater
/// floored support/YES-acceptance predicates, explicit false,false creation,
/// executed-before-script and ATOMIC Agent/CallsScript failures (a reverted
/// script rolls the executed flag back with it). Models that always create,
/// extend or execute successfully are unacceptable; every fault mode is
/// labelled. Test-only vote/execute methods live here, never in
/// IOwnershipVoting.
contract MockOwnershipVoting is IOwnershipVoting {
    uint256 private constant RATIO_BASE = 1e18;

    struct Vote {
        bool exists;
        bool executed;
        uint256 startDate;
        uint256 snapshotBlock;
        uint256 supportRequired;
        uint256 minAcceptQuorum;
        uint256 yea;
        uint256 nay;
        uint256 votingPower;
        bytes script;
        mapping(address => uint8) voteRecord; // 0 none, 1 yea, 2 nay
    }

    IVotingEscrowModel private _token;
    address private _dao;
    address private _implementation;
    uint256 private _minBalance = 2500e18;
    uint256 private _minTime = 43200;
    uint256 private _voteTime = 604800;
    uint256 private _supportRequired = 510000000000000000;
    uint256 private _minAcceptQuorum = 300000000000000000;
    bool private _creationEnabled = true;
    bool private _aclEnabled = true;
    mapping(bytes4 => address) private _executors;
    mapping(address => uint256) private _lastCreate;
    Vote[] private _votes;
    mapping(address => bool) private _blockedAcl;

    // --------------------------- labelled fault modes --------------------
    uint8 public constant NF_NONE = 0;
    uint8 public constant NF_REVERT = 1; // newVote reverts outright

    uint8 public constant GF_NONE = 0;
    uint8 public constant GF_REVERT = 1; // getVote reverts
    uint8 public constant GF_MALFORMED = 2; // truncated 31-byte return
    uint8 public constant GF_BAD_FLAGS = 3; // reports executed=true
    uint8 public constant GF_HUGE_OFFSET = 4; // dynamic script offset != 320
    uint8 public constant GF_OVERSIZED_LEN = 5; // script length word > 8192
    uint8 public constant GF_BAD_BOOL = 6; // open flag word = 2

    uint8 private _newVoteFault;
    uint8 private _getVoteFault;
    bool private _executeRevert; // make script execution fail (rollback proof)

    // ------- bountyfix01 V-L03 labelled observation seams -----------------
    // Malformed-timestamp OBSERVATION overrides. Each substitutes ONLY the
    // returned word: the underlying stored creation timestamps and cooldown,
    // the honest open/executed flags, the actual tally, the scripts and the
    // execution state are untouched, and every surviving fault mode keeps
    // its numbers and behavior. getVote computes `open` from the GENUINE
    // stored date before substituting its returned startDate, so the mock
    // itself cannot panic before the product consumer is exercised.
    bool private _startDateObsOverridden;
    uint256 private _startDateObsValue;

    event StartVote(uint256 indexed id, address indexed creator, string metadata);

    error VoteCreationFailed();
    error VoteNotFound();
    error VoteStillOpen();
    error VoteAlreadyExecuted();
    error TallyFailed();
    error ScriptExecutorMissing();
    error ScriptExecutionFailed();
    error NotDao();

    /// @notice Fix the escrow model, the mock's governance admin (setters and
    /// `enableVoteCreation`) and the implementation identity probe target.
    constructor(address token_, address dao_, address implementation_) {
        _token = IVotingEscrowModel(token_);
        _dao = dao_;
        _implementation = implementation_;
    }

    // ------------------------------- IOwnershipVoting ---------------------

    function token() external view returns (address) {
        return address(_token);
    }

    function implementation() external view returns (address) {
        return _implementation;
    }

    function getEVMScriptExecutor(bytes calldata script) public view returns (address) {
        require(script.length >= 4, "short script");
        return _executors[bytes4(script[0:4])];
    }

    function minBalance() external view returns (uint256) {
        return _minBalance;
    }

    function minTime() external view returns (uint256) {
        return _minTime;
    }

    function lastCreateVoteTimes(address creator) external view returns (uint256) {
        return _lastCreate[creator];
    }

    function voteTime() external view returns (uint256) {
        return _voteTime;
    }

    function supportRequiredPct() external view returns (uint256) {
        return _supportRequired;
    }

    function minAcceptQuorumPct() external view returns (uint256) {
        return _minAcceptQuorum;
    }

    /// @notice Fixture-only control: overwrite a stored ballot script (used by
    /// the canonical-binding mutation fuzz; never used by product code).
    function setScriptFor(uint256 voteId, bytes calldata script_) external {
        _at(voteId).script = script_;
    }

    function votesLength() external view returns (uint256) {
        return _votes.length;
    }

    function canCreateNewVote(address creator) public view returns (bool) {
        if (!_creationEnabled || !_aclEnabled || _blockedAcl[creator]) return false;
        if (_votes.length > 0 && block.timestamp < _lastCreate[creator] + _minTime) return false;
        return _token.balanceOf(creator) >= _minBalance;
    }

    function canForward(address sender, bytes calldata) external view returns (bool) {
        // Real ACL folds the creation check and the CREATE_VOTES permission.
        return canCreateNewVote(sender);
    }

    function enableVoteCreation() external returns (bool) {
        if (msg.sender != _dao) revert NotDao();
        _creationEnabled = !_creationEnabled;
        return _creationEnabled;
    }

    function newVote(bytes calldata script, string calldata metadata, bool castVote, bool executesIfDecided)
        external
        returns (uint256)
    {
        if (_newVoteFault == NF_REVERT) revert VoteCreationFailed();
        require(_creationEnabled, "creation disabled");
        require(_aclEnabled && !_blockedAcl[msg.sender], "acl");
        require(block.timestamp >= _lastCreate[msg.sender] + _minTime, "cooldown");
        uint256 power = _token.balanceOf(msg.sender);
        require(power >= _minBalance, "balance");

        uint256 id = _votes.length;
        Vote storage v;
        _votes.push();
        v = _votes[id];
        v.exists = true;
        v.executed = false;
        v.startDate = block.timestamp;
        v.snapshotBlock = block.number - 1;
        v.supportRequired = _supportRequired;
        v.minAcceptQuorum = _minAcceptQuorum;
        v.votingPower = _token.totalSupplyAt(block.number - 1);
        v.script = script;
        _lastCreate[msg.sender] = block.timestamp;

        if (castVote) {
            v.voteRecord[msg.sender] = 1;
            v.yea += _token.balanceOfAt(msg.sender, v.snapshotBlock);
        }
        emit StartVote(id, msg.sender, metadata);

        if (executesIfDecided && _canExecute(id)) {
            _execute(id);
        }
        return id;
    }

    function getVote(uint256 voteId)
        external
        view
        returns (
            bool open,
            bool executed,
            uint256 startDate,
            uint256 snapshotBlock,
            uint256 supportRequired,
            uint256 minAcceptQuorum,
            uint256 yea,
            uint256 nay,
            uint256 votingPower,
            bytes memory script
        )
    {
        if (voteId >= _votes.length) revert VoteNotFound();
        if (_getVoteFault == GF_REVERT) revert VoteNotFound();
        Vote storage v = _votes[voteId];
        if (_getVoteFault == GF_HUGE_OFFSET || _getVoteFault == GF_OVERSIZED_LEN || _getVoteFault == GF_BAD_BOOL) {
            // Labelled raw-return tampering against the strict getVote parser:
            // malformed dynamic offset, oversized declared tail, or an
            // out-of-range boolean word. The honest decoded value is built
            // first and only one word is corrupted, isolating one parser
            // check per fault.
            bytes memory enc = abi.encode(
                true,
                false,
                v.startDate,
                v.snapshotBlock,
                v.supportRequired,
                v.minAcceptQuorum,
                v.yea,
                v.nay,
                v.votingPower,
                v.script
            );
            uint8 mode = _getVoteFault;
            assembly {
                let pb := add(enc, 0x20)
                switch mode
                case 4 { mstore(add(pb, 288), not(0)) } // offset word = 2^256-1
                case 5 { mstore(add(pb, 320), 0x20000) } // script length 131072 > bound
                case 6 { mstore(pb, 2) } // open word out of bool range
                return(add(enc, 0), mload(enc))
            }
        }
        if (_getVoteFault == GF_MALFORMED) {
            // Return-data truncation: 31 bytes instead of the full tuple.
            bytes memory enc = abi.encode(
                true,
                false,
                v.startDate,
                v.snapshotBlock,
                v.supportRequired,
                v.minAcceptQuorum,
                v.yea,
                v.nay,
                v.votingPower,
                v.script
            );
            assembly {
                return(add(enc, 0), 31)
            }
        }
        open = block.timestamp < v.startDate + _voteTime;
        executed = v.executed || _getVoteFault == GF_BAD_FLAGS;
        // bountyfix01 V-L03 seam: honest open/executed computed above from
        // the genuine stored values; only the returned startDate word is
        // substituted when the labelled observation override is active.
        startDate = _startDateObsOverridden ? _startDateObsValue : v.startDate;
        snapshotBlock = v.snapshotBlock;
        supportRequired = v.supportRequired;
        minAcceptQuorum = v.minAcceptQuorum;
        yea = v.yea;
        nay = v.nay;
        votingPower = v.votingPower;
        script = v.script;
    }

    // ------------------------- test-only voter/executor paths -------------

    /// @notice Real `vote(uint256,bool)` path: snapshot balances, one vote per
    /// address, only while open.
    function vote(uint256 voteId, bool supportYes) external {
        Vote storage v = _at(voteId);
        require(block.timestamp < v.startDate + _voteTime, "closed");
        require(v.voteRecord[msg.sender] == 0, "already voted");
        uint256 power = _token.balanceOfAt(msg.sender, v.snapshotBlock);
        require(power > 0, "no power");
        v.voteRecord[msg.sender] = supportYes ? 1 : 2;
        if (supportYes) v.yea += power;
        else v.nay += power;
    }

    /// @notice Real `votePct` late-vote attenuation: power scaled by
    /// pctNumerator/pctDenominator, floored.
    function votePct(uint256 voteId, uint256 pctNumerator, uint256 pctDenominator, bool supportYes) external {
        Vote storage v = _at(voteId);
        require(block.timestamp < v.startDate + _voteTime, "closed");
        require(pctDenominator > 0, "denom");
        require(v.voteRecord[msg.sender] == 0, "already voted");
        uint256 power = (_token.balanceOfAt(msg.sender, v.snapshotBlock) * pctNumerator) / pctDenominator;
        require(power > 0, "no power");
        v.voteRecord[msg.sender] = supportYes ? 1 : 2;
        if (supportYes) v.yea += power;
        else v.nay += power;
    }

    /// @notice Permissionless execution after the ballot: no veCRV floor.
    /// Marks executed BEFORE running the script; a script failure rolls the
    /// whole transaction back including the flag.
    function executeVote(uint256 voteId) external {
        Vote storage v = _at(voteId);
        require(block.timestamp >= v.startDate + _voteTime, "still open");
        if (v.executed) revert VoteAlreadyExecuted();
        if (!_canExecute(voteId)) revert TallyFailed();
        v.executed = true; // executed-before-script
        if (v.script.length > 0) {
            _execute(voteId);
        }
    }

    function canExecute(uint256 voteId) external view returns (bool) {
        if (voteId >= _votes.length) return false;
        if (!_isOpen(voteId) && !_votes[voteId].executed) return _canExecute(voteId);
        return false;
    }

    function scriptOf(uint256 voteId) external view returns (bytes memory) {
        return _at(voteId).script;
    }

    function _isOpen(uint256 voteId) private view returns (bool) {
        return block.timestamp < _votes[voteId].startDate + _voteTime;
    }

    function _at(uint256 voteId) private view returns (Vote storage v) {
        if (voteId >= _votes.length || !_votes[voteId].exists) revert VoteNotFound();
        v = _votes[voteId];
    }

    /// @dev Both real branches, floored 1e18 ratios, STRICTLY greater.
    function _canExecute(uint256 voteId) private view returns (bool) {
        Vote storage v = _votes[voteId];
        if (v.votingPower == 0) return false;
        if ((v.yea * RATIO_BASE) / v.votingPower > v.supportRequired) return true;
        if (v.yea + v.nay == 0) return false;
        if (
            (v.yea * RATIO_BASE) / (v.yea + v.nay) > v.supportRequired
                && (v.yea * RATIO_BASE) / v.votingPower > v.minAcceptQuorum
        ) {
            return true;
        }
        return false;
    }

    function _execute(uint256 voteId) private {
        Vote storage v = _votes[voteId];
        bytes memory sc = v.script;
        require(sc.length >= 4, "short script");
        bytes4 sig;
        assembly {
            // Keep the first four bytes in their natural (left-aligned)
            // bytes4 position.
            sig := and(mload(add(sc, 0x20)), 0xffffffff00000000000000000000000000000000000000000000000000000000)
        }
        address executor = _executors[sig];
        if (executor == address(0)) revert ScriptExecutorMissing();
        if (_executeRevert) revert ScriptExecutionFailed();
        address[3] memory blacklist;
        IScriptExecutorModel(executor).execScript(sc, abi.encodePacked(voteId), blacklist);
    }

    // ------------------------------- fixture controls ---------------------

    function setDao(address dao_) external {
        _dao = dao_;
    }

    function daoAdmin() external view returns (address) {
        return _dao;
    }

    function setImplementation(address impl_) external {
        if (msg.sender != _dao) revert NotDao();
        _implementation = impl_;
    }

    function setEVMScriptExecutor(bytes4 scriptType, address executor_) external {
        if (msg.sender != _dao) revert NotDao();
        _executors[scriptType] = executor_;
    }

    function setMinBalance(uint256 value) external {
        if (msg.sender != _dao) revert NotDao();
        _minBalance = value;
    }

    function setMinTime(uint256 value) external {
        if (msg.sender != _dao) revert NotDao();
        _minTime = value;
    }

    function setVoteTime(uint256 value) external {
        if (msg.sender != _dao) revert NotDao();
        _voteTime = value;
    }

    function setSupportRequired(uint256 value) external {
        if (msg.sender != _dao) revert NotDao();
        _supportRequired = value;
    }

    function setMinAcceptQuorum(uint256 value) external {
        if (msg.sender != _dao) revert NotDao();
        _minAcceptQuorum = value;
    }

    function setAclEnabled(bool enabled) external {
        if (msg.sender != _dao) revert NotDao();
        _aclEnabled = enabled;
    }

    function blockAcl(address who) external {
        if (msg.sender != _dao) revert NotDao();
        _blockedAcl[who] = true;
    }

    /// @notice Admin un-revoke for the ACL-block fault cell (labelled
    /// governance control, mirrors ACL grantManager-style removals).
    function unblockAcl(address who) external {
        if (msg.sender != _dao) revert NotDao();
        _blockedAcl[who] = false;
    }

    function setCreationEnabled(bool enabled) external {
        if (msg.sender != _dao) revert NotDao();
        _creationEnabled = enabled;
    }

    /// @notice 0 none, 1 revert. Unknown values revert.
    function setNewVoteFault(uint8 mode) external {
        require(mode <= 1, "unknown newVote fault");
        _newVoteFault = mode;
    }

    /// @notice 0 none, 1 revert, 2 malformed 31-byte return, 3 forged
    /// executed flag. Unknown values revert.
    function setGetVoteFault(uint8 mode) external {
        require(mode <= 6, "unknown getVote fault");
        _getVoteFault = mode;
    }

    function setExecuteRevert(bool enabled) external {
        _executeRevert = enabled;
    }

    /// @notice bountyfix01 V-L03 seam: when enabled, `getVote` returns
    /// `value` INSTEAD of the stored startDate, after the honest open/
    /// executed flags were computed from the genuine stored date.
    function setStartDateObservation(bool enabled, uint256 value) external {
        _startDateObsOverridden = enabled;
        _startDateObsValue = value;
    }
}
