// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ForkFixture, IControllerVenue, IErc20Venue, IMetaRegistryVenue, IGaugeVenue, FVm} from "./ForkFixture.sol";
import {CurveGaugeLister} from "../../contracts/CurveGaugeLister.sol";
import {VotiumAdapter} from "../../contracts/adapters/VotiumAdapter.sol";
import {VoteMarketAdapter} from "../../contracts/adapters/VoteMarketAdapter.sol";
import {GaugeControllerAdmin} from "../../contracts/GaugeControllerAdmin.sol";

/// @dev Extended cheatcode subset for the router fork witnesses only (new
/// declarations; the shared FVm interface file is not edited).
interface RouterForkVm {
    function prank(address newCaller) external;
    function startPrank(address newCaller) external;
    function stopPrank() external;
    function warp(uint256 newTimestamp) external;
    function roll(uint256 newHeight) external;
    function store(address account, bytes32 slot, bytes32 value) external;
    function load(address account, bytes32 slot) external view returns (bytes32);
    function deal(address who, uint256 newBalance) external;
    function recordLogs() external;
    function getRecordedLogs() external view returns (Log[] memory);
    function readFile(string memory path) external view returns (string memory);
    function parseJsonString(string calldata json, string calldata key) external pure returns (string memory);
    function deployCode(string calldata artifact, bytes calldata constructorArgs) external returns (address);

    struct Log {
        bytes32[] topics;
        bytes data;
        address emitter;
    }
}

/// @dev Escrow observation surface (voting-power reads only; never a product
/// dependency).
interface IRouterEscrow {
    function balanceOf(address, uint256) external view returns (uint256);
    function balanceOfAt(address, uint256) external view returns (uint256);
    function totalSupply(uint256) external view returns (uint256);
    function totalSupplyAt(uint256) external view returns (uint256);
    function user_point_epoch(address) external view returns (uint256);
}

interface IRouterVoting {
    function token() external view returns (address);
    function minBalance() external view returns (uint256);
    function minTime() external view returns (uint256);
    function votesLength() external view returns (uint256);
    function getVote(uint256)
        external
        view
        returns (bool, bool, uint64, uint64, uint64, uint64, uint256, uint256, uint256, bytes memory);
    function canExecute(uint256) external view returns (bool);
    function newVote(bytes calldata, string calldata, bool, bool) external returns (uint256);
    function vote(uint256, bool, bool) external;
    function executeVote(uint256) external;
    function lastCreateVoteTimes(address) external view returns (uint256);
    /// @dev CONF-04(b) graph reads (EVMScriptRunner/AppBase public surface
    /// of the verified deployment, review/routerplan/evidence/agent.sol).
    function kernel() external view returns (address);
    function appId() external view returns (bytes32);
    function getEVMScriptRegistry() external view returns (address);
    function getEVMScriptExecutor(bytes calldata) external view returns (address);
}

interface IRouterAgent {
    function kernel() external view returns (address);
    /// @dev CONF-04(b): AppBase appId() via the Agent proxy (proves the
    /// delegatecall reaches the registered implementation).
    function appId() external view returns (bytes32);
}

interface IRouterKernel {
    function acl() external view returns (address);
    /// @dev CONF-04(b): the same getApp(bytes32,bytes32) entrypoint the
    /// AppProxyFallback runtime uses for base resolution (observed
    /// selector 0xbe00bbd8 in the retained F09 executeVote trace).
    function getApp(bytes32, bytes32) external view returns (address);
}

interface IRouterAcl {
    function hasPermission(address who, address where, bytes32 role) external view returns (bool);
    /// @dev Verified-deployment ACL form (blockscout ABI of the Kernel's ACL
    /// at the pin): uint256[] context of Aragon Permission words
    /// ((arg << 8) | ethValue). CONF-04 parameter-specific permission reads.
    function hasPermission(address who, address where, bytes32 role, uint256[] calldata context)
        external
        view
        returns (bool);
    function getPermissionParamsLength(address who, address where, bytes32 role) external view returns (uint256);
    /// @dev CONF-04(b) graph reads: the ACL is itself an AragonApp linked
    /// into the same kernel (live-verified at the pin).
    function kernel() external view returns (address);
    function appId() external view returns (bytes32);
}

interface IRouterScriptRegistry {
    function getScriptExecutor(bytes calldata script) external view returns (address);
    /// @dev CONF-04(b) graph reads via the registry proxy.
    function kernel() external view returns (address);
    function appId() external view returns (bytes32);
}

interface IRouterCallsScript {
    /// @dev CONF-04(b): CallsScript identifies itself as the CALLS_SCRIPT
    /// executor (review/routerplan/evidence/callsscript.sol:309,394-396).
    function executorType() external view returns (bytes32);
}

/// @title ForkGaugeControllerAdminSpec
/// @notice Real-controller + real-governance witness matrix F01–F12 for
/// GaugeControllerAdmin (plans/ROUTERPLAN-WITNESSES.json identities plus the
/// ROUTERCONF-directed F11 selected-Paris lifecycle and F12
/// interrupted-recovery rows). Abstract:
/// the concrete runner is fork/GaugeControllerAdmin.t.sol under the fork
/// profile only. Seating, handback, reseat, additions and governance votes
/// are LOCAL FORK SIMULATION at the pinned header — never production
/// transactions, no signing, no broadcast. D impersonation in F02–F08 is
/// lower-level mechanics evidence, explicitly disclosed; F09/F10/F12 use the
/// real Voting→ScriptRegistry→CallsScript→Agent transport WITHOUT
/// impersonating D/V/R/L — a disclosed funded-holder simulation (declared
/// only to close quorum) and clock warp complete the ballot, and no vote
/// tallies, ACL roles or controller admin slots are edited.
abstract contract ForkGaugeControllerAdminSpec is ForkFixture {
    RouterForkVm internal constant rvf = RouterForkVm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    // governance transport pins (live reads at the regression header; see
    // review/routerplan/evidence and the pinned-read receipts)
    address internal constant VOTING = 0xE478de485ad2fe566d49342Cbd03E49ed7DB3356;
    address internal constant SCRIPT_REGISTRY = 0x1b13e8E7b85b2F92CA4436F98F88CE169f63D567;
    address internal constant CALLS_EXECUTOR = 0x5cEb19e1890f677c3676d5ecDF7c501eBA01A054;
    address internal constant CRV_VOTING_TOKEN = 0x5f3b5DfEb7B28CDbD7FAba78963EE202a494e2A2;
    /// @dev Selector of the deployed DAO executor's execute(address,uint256,
    /// bytes) entrypoint, observed in the live CallsScript of on-chain vote
    /// 1522 (script starts 00000001 || bytes20(D) || uint32 len || b61d27f6).
    bytes4 internal constant AGENT_EXECUTE_SELECTOR = 0xb61d27f6;

    /// @dev The pin's second registry-verified real pair, provenance mirrored
    /// from ForkTrustedFactory §4.1 (identity B): POOL_LEGACY/GAUGE_LEGACY at
    /// handler 0, gauge index 0, controller type 5. Used as the DAO-free
    /// lane candidate because the controller registry holds exactly two
    /// admitted candidates at the frozen pin.
    address internal constant POOL_LEGACY_PROBE = 0x03470B57B05089EE40c651dAC9E0387F1f3cb46f;
    address internal constant GAUGE_LEGACY_PROBE = 0xfB389aCa09ddC676fC9D5aC3cfD2Cd133bf44E19;
    uint256 internal constant LEGACY_HANDLER_ID = 0;
    uint256 internal constant LEGACY_GAUGE_INDEX = 0;
    int128 internal constant LEGACY_GAUGE_TYPE = 5;
    bytes4 internal constant C_ADD2_SELECTOR = 0x3a04f900; // add_gauge(address,int128)

    /// @dev Pinned historical funded voting holder: creator of the live open
    /// vote 1522 (StartVote log at block 26384151). F09/F10 re-read its
    /// balance and the vote cooldown from the real contracts and fail closed
    /// if the pin drifted.
    address internal constant HISTORIC_HOLDER = 0xf7Bd34Dd44B92fB2f9C3D2e31aAAd06570a853A6;

    bytes32 internal constant T_COMMIT_OWNERSHIP = keccak256("CommitOwnership(address)");
    bytes32 internal constant T_NEW_GAUGE_KEC = keccak256("NewGauge(address,int128,uint256)");
    bytes32 internal constant T_ADDER_SET = keccak256("AdderSet(address,bool)");
    bytes32 internal constant T_GAUGE_ADDED = keccak256("GaugeAdded(address,address,int128,uint256)");
    bytes32 internal constant T_START_VOTE =
        keccak256("StartVote(uint256,address,string,uint256,uint256,uint256,uint256)");
    bytes32 internal constant T_CAST_VOTE = keccak256("CastVote(uint256,address,bool,uint256)");
    bytes32 internal constant T_EXECUTE_VOTE = keccak256("ExecuteVote(uint256)");

    /// @dev CONF-04(b) governance-graph bindings. Positions and identities
    /// are the Aragon OS constants of the verified deployment sources
    /// (review/routerplan/evidence/agent.sol:360-364,1054-1056,1081-1098;
    /// callsscript.sol:309,394-396). Namespace/position constants are the
    /// keccak256 of their named strings and re-derived here; the two APM
    /// app ids are pinned from the evidence and cross-checked against the
    /// live proxy getters and raw storage slots below (never assumed).
    bytes32 internal constant KERNEL_APP_BASES_NAMESPACE = keccak256("base");
    bytes32 internal constant KERNEL_APP_ADDR_NAMESPACE = keccak256("app");
    bytes32 internal constant APP_STORAGE_KERNEL_POSITION = keccak256("aragonOS.appStorage.kernel");
    bytes32 internal constant APP_STORAGE_APP_ID_POSITION = keccak256("aragonOS.appStorage.appId");
    /// @dev Base slot of the KernelProxy runtime at the pin (PUSH32 observed
    /// in the kernel proxy code; its value is cross-bound to the ACL/kernel
    /// reads below, and the retained F09 trace shows the same delegatecall
    /// target actually executing).
    bytes32 internal constant KERNEL_PROXY_BASE_POSITION =
        0x8e2ed18767e9c33b25344c240cdf92034fae56be99e2c07f3d9946d949ffede4;
    bytes32 internal constant EVMSCRIPT_REGISTRY_APP_ID =
        0xddbcfd564f642ab5627cf68b9b7d374fb4f8a36e941a75d89c87998cef03bd61; // agent.sol:1056
    bytes32 internal constant KERNEL_DEFAULT_ACL_APP_ID =
        0xe3262375f45a6e2026b7e7b18c2b807434f2508fe1a2a3dfb493c7df8f4aad6a; // agent.sol:1085
    bytes32 internal constant CALLS_SCRIPT_EXECUTOR_TYPE = keccak256("CALLS_SCRIPT");
    /// @dev Complete Agent/C/R event payload topics (CONF-04(b)): Aragon
    /// Agent Execute + EVMScriptRunner ScriptResult (agent.sol:1123,1487),
    /// CallsScript LogScriptCall (callsscript.sol:320), the real C's
    /// ApplyOwnership companion of CommitOwnership, and R's own events.
    bytes32 internal constant T_AGENT_EXECUTE = keccak256("Execute(address,address,uint256,bytes)");
    bytes32 internal constant T_SCRIPT_RESULT = keccak256("ScriptResult(address,bytes,bytes,bytes)");
    bytes32 internal constant T_LOG_SCRIPT_CALL = keccak256("LogScriptCall(address,address,address)");
    bytes32 internal constant T_C_APPLY_OWNERSHIP = keccak256("ApplyOwnership(address)");
    bytes32 internal constant T_R_COMMITTED = keccak256("ControllerTransferCommitted(address)");
    bytes32 internal constant T_R_APPLIED = keccak256("ControllerTransferApplied(address)");

    // escrow storage bases (reverse-engineered at the pin via the public
    // getters, verified live inside _fundSimulatedHolder; Vyper 0.2.x maps
    // key the slot as keccak(key ++ base)):
    uint256 internal constant ESCROW_USER_POINTS_BASE = 5; // HashMap[address, Point[...]]
    uint256 internal constant ESCROW_USER_EPOCH_BASE = 6; // HashMap[address, uint256]

    // ------------------------------------------------------------------
    // composition helpers
    // ------------------------------------------------------------------

    struct RouterTrio {
        CurveGaugeLister lister;
        VotiumAdapter va;
        VoteMarketAdapter vma;
        GaugeControllerAdmin router;
    }

    function _router() internal returns (GaugeControllerAdmin) {
        return new GaugeControllerAdmin(CONTROLLER, DAO);
    }

    /// @dev Fresh unchanged L wired to a fresh router (controller_=R,
    /// owner_=D), real adapters, paused. Mirrors the fixture's raw-admin trio
    /// semantics for the router composition; the raw-admin fixture itself is
    /// never reused as router proof.
    function _deployRouterTrio(uint16 votiumBps) internal returns (RouterTrio memory t) {
        t.router = _router();
        _assertPrimaryProvenance();
        t.va = new VotiumAdapter(CRVUSD, DAO, VOTIUM);
        t.vma = new VoteMarketAdapter(CRVUSD, DAO, CRM, VM_DESTINATION);
        _assertValidatorPinAtFork();
        t.lister = new CurveGaugeLister(
            DAO,
            CRVUSD,
            address(t.router),
            FEEDIST,
            CurveGaugeLister.AdmissionConfig(METAREGISTRY, 8),
            CurveGaugeLister.PlatformConfig(address(t.va), address(t.vma), votiumBps),
            TRUSTED_VALIDATOR
        );
        assertEq(t.lister.controller(), address(t.router), "L endpoint is the router");
        assertEq(t.lister.owner(), DAO, "L owner is D");
        fvm.startPrank(DAO);
        t.va.setLister(address(t.lister));
        t.vma.setLister(address(t.lister));
        fvm.stopPrank();
        assertEq(t.va.lister(), address(t.lister), "votium bound");
        assertEq(t.vma.lister(), address(t.lister), "votemarket bound");
        assertTrue(t.lister.paused(), "trio starts paused");
    }

    function _seatRouter(GaugeControllerAdmin r) internal {
        fvm.startPrank(DAO);
        IControllerVenue(CONTROLLER).commit_transfer_ownership(address(r));
        IControllerVenue(CONTROLLER).apply_transfer_ownership();
        fvm.stopPrank();
        assertEq(IControllerVenue(CONTROLLER).admin(), address(r), "router seated");
    }

    function _grantLister(GaugeControllerAdmin r, address l, bool enabled) internal {
        fvm.prank(DAO);
        r.grant(l, enabled);
    }

    function _activate(CurveGaugeLister lister) internal {
        fvm.prank(DAO);
        lister.setPaused(false);
        assertFalse(lister.paused(), "paid admission activated");
    }

    function _c() internal view returns (IControllerVenue) {
        return IControllerVenue(CONTROLLER);
    }

    function _synthGauge(string memory label) internal pure returns (address) {
        return address(uint160(uint256(keccak256(bytes(label)))));
    }

    function _isRegistered(address g) internal view returns (bool) {
        (bool ok,) = CONTROLLER.staticcall(abi.encodeWithSelector(_c().gauge_types.selector, g));
        return ok;
    }

    /// @dev Scan the REAL MetaRegistry for a pool/gauge candidate that is
    /// live, lp-consistent, type-valid and NOT yet in the controller
    /// registry. Skips the pinned primary (callers may have consumed it).
    struct Candidate {
        address pool;
        address gauge;
        uint256 gaugeIndex;
        uint256 handlerId;
        int128 gaugeType;
    }

    function _nextFreeCandidate(address skip1, address skip2) internal view returns (Candidate memory cd) {
        IMetaRegistryVenue reg = IMetaRegistryVenue(METAREGISTRY);
        for (uint256 h = 0; h < 4; ++h) {
            for (uint256 idx = 0; idx < 6; ++idx) {
                address pool = POOL_PRIMARY;
                address g;
                try reg.get_gauge(pool, idx, h) returns (address gotG) {
                    g = gotG;
                } catch {
                    continue;
                }
                if (g == address(0) || g == skip1 || g == skip2) continue;
                if (g.code.length == 0) continue;
                if (_isRegistered(g)) continue;
                address lp = reg.get_lp_token(pool, h);
                if (lp == address(0)) continue;
                try IGaugeVenue(g).is_killed() returns (bool killed) {
                    if (killed) continue;
                } catch {
                    continue;
                }
                try IGaugeVenue(g).lp_token() returns (address got) {
                    if (got != lp) continue;
                } catch {
                    continue;
                }
                int128 t;
                try reg.get_gauge_type(pool, idx, h) returns (int128 gt) {
                    t = gt;
                } catch {
                    continue;
                }
                if (t < 0 || t >= _c().n_gauge_types()) continue;
                uint256 ncoins;
                try reg.get_n_coins(pool, h) returns (uint256 nc) {
                    ncoins = nc;
                } catch {
                    continue;
                }
                if (ncoins < 2) continue;
                cd = Candidate(pool, g, idx, h, t);
                return cd;
            }
        }
        revert("NO FREE REAL CANDIDATE");
    }

    // ------------------------------------------------------------------
    // CallsScript encoding per plans/ROUTERPLAN-DEPLOYMENT.md §2
    // ------------------------------------------------------------------

    /// @dev One CallsScript action: CALLS executes target.call(data) in the
    /// app's delegated context (msg.sender == VOTING at the callee).
    /// Agent-wrapped actions put A(target,inner) calldata on target D.
    struct Action {
        address target;
        bytes data;
    }

    /// @dev A(target,inner) = enc(execute(address,uint256,bytes),target,0,inner)
    /// with the deployed executor's observed selector, per DEPLOYMENT §2.
    function _agentCalldata(address target, bytes memory inner) internal pure returns (bytes memory) {
        return abi.encodePacked(AGENT_EXECUTE_SELECTOR, abi.encode(target, uint256(0), inner));
    }

    function _callsScript(Action[] memory actions) internal pure returns (bytes memory) {
        bytes memory script = abi.encodePacked(bytes4(0x00000001));
        for (uint256 i = 0; i < actions.length; ++i) {
            bytes memory a = actions[i].data;
            require(a.length < 2 ** 32, "action length");
            bytes memory len = new bytes(4);
            len[0] = bytes1(uint8(a.length >> 24));
            len[1] = bytes1(uint8(a.length >> 16));
            len[2] = bytes1(uint8(a.length >> 8));
            len[3] = bytes1(uint8(a.length));
            script = abi.encodePacked(script, bytes20(actions[i].target), len, a);
        }
        return script;
    }

    function _logCount(RouterForkVm.Log[] memory logs, address emitter, bytes32 t0) internal pure returns (uint256 n) {
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].emitter == emitter && logs[i].topics.length > 0 && logs[i].topics[0] == t0) n += 1;
        }
    }

    /// @dev CONF-04(b): exact recorded-log lookup — emitter, the COMPLETE
    /// topics array (length and every topic) and the exact data bytes must
    /// all match. Topic0 counts alone do not establish payload binding.
    function _countExactLog(RouterForkVm.Log[] memory logs, address emitter, bytes32[] memory topics, bytes memory data)
        internal
        pure
        returns (uint256 hits)
    {
        bytes32 wantDataHash = keccak256(data);
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].emitter != emitter) continue;
            if (logs[i].topics.length != topics.length) continue;
            bool same = true;
            for (uint256 j = 0; j < topics.length; ++j) {
                if (logs[i].topics[j] != topics[j]) {
                    same = false;
                    break;
                }
            }
            if (!same) continue;
            if (keccak256(logs[i].data) != wantDataHash) continue;
            hits += 1;
        }
    }

    function _exactLogOne(
        RouterForkVm.Log[] memory logs,
        address emitter,
        bytes32[] memory topics,
        bytes memory data,
        string memory label
    ) internal pure {
        require(
            _countExactLog(logs, emitter, topics, data) == 1, string.concat("FORK_REAL_GOVERNANCE_TRANSPORT ", label)
        );
    }

    function _callFromAddr(address from, address target, bytes memory data) internal returns (bool, bytes memory) {
        fvm.prank(from);
        (bool ok, bytes memory ret) = target.call(data);
        return (ok, ret);
    }

    /// @dev CONF-04(b) (review/ROUTERCONF2.md:208-216): the prescribed
    /// handback/install actions are Agent-wrapped; restate the FULL graph
    /// bindings for the live F09 transport so passing votes bind real
    /// Voting/Agent/proxy/Kernel/ACL implementation/runtime graph edges,
    /// not merely nonzero getters. Every value is read live at the pin.
    function _f09GovernanceGraphBindings() internal view {
        address kernel = IRouterAgent(DAO).kernel();
        require(kernel != address(0), "FORK_REAL_GOVERNANCE_TRANSPORT kernel");
        require(IRouterVoting(VOTING).kernel() == kernel, "FORK_REAL_GOVERNANCE_TRANSPORT shared kernel");
        address acl = IRouterKernel(kernel).acl();
        require(acl != address(0), "FORK_REAL_GOVERNANCE_TRANSPORT acl bound");
        require(IRouterAcl(acl).kernel() == kernel, "FORK_REAL_GOVERNANCE_TRANSPORT acl reverse link");
        // raw appStorage slots must agree with what the proxies report
        require(
            rvf.load(DAO, APP_STORAGE_KERNEL_POSITION) == bytes32(uint256(uint160(kernel))),
            "FORK_REAL_GOVERNANCE_TRANSPORT agent appStorage.kernel slot"
        );
        require(
            rvf.load(VOTING, APP_STORAGE_KERNEL_POSITION) == bytes32(uint256(uint160(kernel))),
            "FORK_REAL_GOVERNANCE_TRANSPORT voting appStorage.kernel slot"
        );
        require(
            rvf.load(acl, APP_STORAGE_KERNEL_POSITION) == bytes32(uint256(uint160(kernel))),
            "FORK_REAL_GOVERNANCE_TRANSPORT acl appStorage.kernel slot"
        );
        require(
            rvf.load(SCRIPT_REGISTRY, APP_STORAGE_KERNEL_POSITION) == bytes32(uint256(uint160(kernel))),
            "FORK_REAL_GOVERNANCE_TRANSPORT registry appStorage.kernel slot"
        );
        bytes32 agentAppId = IRouterAgent(DAO).appId();
        bytes32 votingAppId = IRouterVoting(VOTING).appId();
        require(agentAppId != bytes32(0) && votingAppId != bytes32(0), "FORK_REAL_GOVERNANCE_TRANSPORT appIds set");
        require(
            rvf.load(DAO, APP_STORAGE_APP_ID_POSITION) == agentAppId
                && rvf.load(VOTING, APP_STORAGE_APP_ID_POSITION) == votingAppId
                && rvf.load(acl, APP_STORAGE_APP_ID_POSITION) == KERNEL_DEFAULT_ACL_APP_ID,
            "FORK_REAL_GOVERNANCE_TRANSPORT appStorage.appId slots bound"
        );
        require(
            IRouterAcl(acl).appId() == KERNEL_DEFAULT_ACL_APP_ID
                && IRouterScriptRegistry(SCRIPT_REGISTRY).appId() == EVMSCRIPT_REGISTRY_APP_ID,
            "FORK_REAL_GOVERNANCE_TRANSPORT acl/registry appIds pinned"
        );
        // implementation bindings: the same kernel.getApp(bases-ns, appId)
        // path the proxy runtimes use for base resolution (observed
        // selector 0xbe00bbd8), each resolving to distinct deployed code
        address implAgent = IRouterKernel(kernel).getApp(KERNEL_APP_BASES_NAMESPACE, agentAppId);
        address implVoting = IRouterKernel(kernel).getApp(KERNEL_APP_BASES_NAMESPACE, votingAppId);
        address implAcl = IRouterKernel(kernel).getApp(KERNEL_APP_BASES_NAMESPACE, KERNEL_DEFAULT_ACL_APP_ID);
        address implRegistry = IRouterKernel(kernel).getApp(KERNEL_APP_BASES_NAMESPACE, EVMSCRIPT_REGISTRY_APP_ID);
        require(implAgent != DAO && implVoting != VOTING, "FORK_REAL_GOVERNANCE_TRANSPORT impl distinct from proxy");
        require(
            implAgent.code.length > 0 && implVoting.code.length > 0 && implAcl.code.length > 0
                && implRegistry.code.length > 0,
            "FORK_REAL_GOVERNANCE_TRANSPORT impl runtimes present"
        );
        address implKernel = address(uint160(uint256(rvf.load(kernel, KERNEL_PROXY_BASE_POSITION))));
        require(implKernel != kernel && implKernel.code.length > 0, "FORK_REAL_GOVERNANCE_TRANSPORT kernel base");
        // actual graph-to-registry relation: the runner path the executed
        // votes traverse, plus the registry app-instance binding
        require(
            IRouterVoting(VOTING).getEVMScriptRegistry() == SCRIPT_REGISTRY
                && IRouterKernel(kernel).getApp(KERNEL_APP_ADDR_NAMESPACE, EVMSCRIPT_REGISTRY_APP_ID)
                    == SCRIPT_REGISTRY,
            "FORK_REAL_GOVERNANCE_TRANSPORT registry bound through kernel"
        );
        require(
            IRouterCallsScript(CALLS_EXECUTOR).executorType() == CALLS_SCRIPT_EXECUTOR_TYPE,
            "FORK_REAL_GOVERNANCE_TRANSPORT executor type"
        );
    }

    /// @dev CONF-04(b): the Agent emitted Execute(sender=Voting, target, 0,
    /// innerCalldata) with the EXACT inner payload for this prescribed
    /// action (agent.sol:1487,1508; ground truth in the retained F09 trace).
    function _requireAgentExecuted(RouterForkVm.Log[] memory logs, Action memory action, string memory label)
        internal
        view
    {
        require(action.target == DAO && action.data.length > 4, "FORK_REAL_GOVERNANCE_TRANSPORT agent action shape");
        bytes memory d = action.data;
        bytes memory tail = new bytes(d.length - 4);
        for (uint256 j = 0; j < tail.length; ++j) {
            tail[j] = d[j + 4];
        }
        (address innerTarget, uint256 innerValue, bytes memory innerData) = abi.decode(tail, (address, uint256, bytes));
        require(innerValue == 0, "FORK_REAL_GOVERNANCE_TRANSPORT explicit zero ETH value");
        bytes32[] memory topics = new bytes32[](3);
        topics[0] = T_AGENT_EXECUTE;
        topics[1] = bytes32(uint256(uint160(VOTING)));
        topics[2] = bytes32(uint256(uint160(innerTarget)));
        // the deployed 0.4.24 Agent writes the trailing bytes field WITHOUT
        // word padding (getRecordedLogs ground truth: 96-byte heads
        // [ethValue=0][offset=0x40] + [len][raw bytes]); match exactly.
        bytes memory wantData =
            abi.encodePacked(bytes32(0), bytes32(uint256(0x40)), bytes32(uint256(innerData.length)), innerData);
        _exactLogOne(logs, DAO, topics, wantData, label);
    }

    /// @dev CONF-04(b): EVMScriptRunner ScriptResult(executor, script,
    /// input, returnData) on VOTING with the complete executed script bytes
    /// (agent.sol:1123,1197; Voting passes empty input and the CALLS
    /// executor returns empty output at this pin).
    function _requireScriptResult(RouterForkVm.Log[] memory logs, bytes memory script, string memory label)
        internal
        view
    {
        bytes32[] memory topics = new bytes32[](2);
        topics[0] = T_SCRIPT_RESULT;
        topics[1] = bytes32(uint256(uint160(CALLS_EXECUTOR)));
        _exactLogOne(logs, VOTING, topics, abi.encode(script, new bytes(0), new bytes(0)), label);
    }

    /// @dev CONF-04(b): one CallsScript LogScriptCall(sender=test caller,
    /// src=Voting, dst=DAO) per executed action (callsscript.sol:320,344).
    function _requireScriptCalls(RouterForkVm.Log[] memory logs, uint256 actions, string memory label) internal view {
        bytes32[] memory topics = new bytes32[](4);
        topics[0] = T_LOG_SCRIPT_CALL;
        topics[1] = bytes32(uint256(uint160(address(this))));
        topics[2] = bytes32(uint256(uint160(VOTING)));
        topics[3] = bytes32(uint256(uint160(DAO)));
        require(
            _countExactLog(logs, VOTING, topics, "") == actions, string.concat("FORK_REAL_GOVERNANCE_TRANSPORT ", label)
        );
    }

    /// @dev CONF-04(b): complete Agent/C/R event payload checks for the
    /// install ballot — every prescribed action observed as Agent.Execute
    /// with its exact inner calldata, the ScriptResult bound to the actual
    /// script bytes, one LogScriptCall per action, and the real-C commit/
    /// apply plus R grant events carrying their exact successor/adder
    /// payloads (replaces the former topic0 counts).
    function _f09InstallEventBindings(
        RouterForkVm.Log[] memory logs,
        address r,
        address l,
        Action[] memory actions,
        bytes memory script
    ) internal view {
        require(actions.length == 3, "FORK_REAL_GOVERNANCE_TRANSPORT install shape");
        _requireAgentExecuted(logs, actions[0], "install commit(C) Agent.Execute payload");
        _requireAgentExecuted(logs, actions[1], "install apply(C) Agent.Execute payload");
        _requireAgentExecuted(logs, actions[2], "install grant(L) Agent.Execute payload");
        _requireScriptResult(logs, script, "install ScriptResult payload");
        _requireScriptCalls(logs, actions.length, "install LogScriptCall per action");
        bytes32[] memory t1 = new bytes32[](1);
        t1[0] = T_COMMIT_OWNERSHIP;
        _exactLogOne(logs, CONTROLLER, t1, abi.encode(r), "install CommitOwnership(r) payload");
        t1[0] = T_C_APPLY_OWNERSHIP;
        _exactLogOne(logs, CONTROLLER, t1, abi.encode(r), "install ApplyOwnership(r) payload");
        bytes32[] memory t2 = new bytes32[](2);
        t2[0] = T_ADDER_SET;
        t2[1] = bytes32(uint256(uint160(l)));
        _exactLogOne(logs, r, t2, abi.encode(true), "install AdderSet(l,true) payload");
    }

    /// @dev CONF-04(b): the handback ballot's complete Agent/C/R payloads —
    /// revoke and ownership events with exact successor/adder bytes plus the
    /// per-action Agent.Execute and ScriptResult/LogScriptCall observations.
    function _f09HandbackEventBindings(
        RouterForkVm.Log[] memory logs,
        address r,
        address l,
        Action[] memory actions,
        bytes memory script
    ) internal view {
        require(actions.length == 3, "FORK_REAL_GOVERNANCE_TRANSPORT handback shape");
        _requireAgentExecuted(logs, actions[0], "handback grant(L,false) Agent.Execute payload");
        _requireAgentExecuted(logs, actions[1], "handback commit(D) Agent.Execute payload");
        _requireAgentExecuted(logs, actions[2], "handback apply(R) Agent.Execute payload");
        _requireScriptResult(logs, script, "handback ScriptResult payload");
        _requireScriptCalls(logs, actions.length, "handback LogScriptCall per action");
        bytes32[] memory t1 = new bytes32[](1);
        t1[0] = T_COMMIT_OWNERSHIP;
        _exactLogOne(logs, CONTROLLER, t1, abi.encode(DAO), "handback CommitOwnership(D) payload");
        t1[0] = T_C_APPLY_OWNERSHIP;
        _exactLogOne(logs, CONTROLLER, t1, abi.encode(DAO), "handback ApplyOwnership(D) payload");
        bytes32[] memory t2 = new bytes32[](2);
        t2[0] = T_ADDER_SET;
        t2[1] = bytes32(uint256(uint160(l)));
        _exactLogOne(logs, r, t2, abi.encode(false), "handback AdderSet(l,false) payload");
        t2[0] = T_R_COMMITTED;
        t2[1] = bytes32(uint256(uint160(DAO)));
        _exactLogOne(logs, r, t2, "", "handback ControllerTransferCommitted(D) payload");
        t2[0] = T_R_APPLIED;
        _exactLogOne(logs, r, t2, "", "handback ControllerTransferApplied(D) payload");
    }

    function _routerErr(bytes4 sel, bytes memory args) internal pure returns (bytes memory) {
        return abi.encodePacked(sel, args);
    }

    // ------------------------------------------------------------------
    // F01
    // ------------------------------------------------------------------

    function test_Fork_RouterPinsRuntimeRolesAndCanonicalReads() public {
        _freshFork();
        // header binding: number/timestamp/chainid in-EVM plus the parent
        // hash via BLOCKHASH; the pinned header's own hash is verified
        // fail-closed by the scripts/test-fork.sh preflight (receipt-bound).
        require(
            blockhash(FORK_BLOCK - 1) == 0x65a9415ee70438d6195a06ec7f0ed44dcc6e65539396f577b1097f76b0518d43,
            "FORK_PIN_RUNTIME_ROLES parent hash"
        );
        require(block.timestamp == FORK_TIMESTAMP, "FORK_PIN_RUNTIME_ROLES timestamp");
        require(block.chainid == FORK_CHAIN_ID, "FORK_PIN_RUNTIME_ROLES chain");
        require(block.number == FORK_BLOCK, "FORK_PIN_RUNTIME_ROLES number");

        bytes memory cCode = CONTROLLER.code;
        assertEq(uint256(cCode.length), 12013, "FORK_PIN_RUNTIME_ROLES C runtime size");
        assertEq(keccak256(cCode), H_CONTROLLER, "FORK_PIN_RUNTIME_ROLES C runtime keccak");
        assertEq(_c().admin(), DAO, "FORK_PIN_RUNTIME_ROLES admin");
        assertEq(_c().future_admin(), DAO, "FORK_PIN_RUNTIME_ROLES future");
        _assertI128Eq(_c().n_gauge_types(), int128(13), "FORK_PIN_RUNTIME_ROLES type count");
        _assertI128Eq(_c().n_gauges(), int128(int256(N_GAUGES_PINNED)), "FORK_PIN_RUNTIME_ROLES gauge count");
        address known = _c().gauges(0);
        _assertI128Eq(_c().gauge_types(known), int128(0), "FORK_PIN_RUNTIME_ROLES known type zero");

        // absence at the REAL controller is a revert, never zero (no etch,
        // no store, no mocked C, no re-pin anywhere in this witness)
        (bool absOk, bytes memory absRet) =
            CONTROLLER.staticcall(abi.encodeWithSelector(_c().gauge_types.selector, address(0)));
        require(!absOk, "FORK_PIN_RUNTIME_ROLES absence fabricated");
        require(absRet.length == 0, "FORK_PIN_RUNTIME_ROLES absence bytes");

        GaugeControllerAdmin r = _router();
        assertEq(r.controller(), CONTROLLER, "FORK_PIN_RUNTIME_ROLES R controller");
        assertEq(r.dao(), DAO, "FORK_PIN_RUNTIME_ROLES R dao");
        _assertI128Eq(r.n_gauge_types(), _c().n_gauge_types(), "R read-through parity count");
        _assertI128Eq(r.gauge_types(known), 0, "R read-through parity zero");
        (bool rAbs,) =
            address(r).staticcall(abi.encodeWithSelector(GaugeControllerAdmin.gauge_types.selector, address(0)));
        require(!rAbs, "FORK_PIN_RUNTIME_ROLES R absence");

        // selected Paris deployment-artifact rehearsal inside the real
        // controller graph: the SAME address, immutables and runtime bytes
        // as the compiled default-profile artifact (not the Cancun analog)
        string memory art = rvf.readFile("out/GaugeControllerAdmin.sol/GaugeControllerAdmin.json");
        string memory deployedHex = rvf.parseJsonString(art, "$.deployedBytecode.object");
        bytes memory expectedRuntime = _hexToBytes(deployedHex);
        require(expectedRuntime.length > 0, "Paris runtime present");
        require(expectedRuntime.length <= 24576, "FORK_PIN_RUNTIME_ROLES runtime ceiling");
        bytes memory creation = _hexToBytes(rvf.parseJsonString(art, "$.bytecode.object"));
        require(creation.length + 64 <= 49152, "FORK_PIN_RUNTIME_ROLES initcode ceiling");
        bytes memory initcode = abi.encodePacked(creation, abi.encode(CONTROLLER, DAO));
        address parisR;
        assembly ("memory-safe") {
            parisR := create(0, add(initcode, 0x20), mload(initcode))
        }
        require(parisR != address(0), "FORK_PIN_RUNTIME_ROLES Paris initcode deploy");
        bytes memory parisCode = parisR.code;
        // deployed length must equal the artifact runtime length (immutable
        // slots occupy their final positions; values bound below via getters)
        assertEq(
            uint256(parisCode.length), uint256(expectedRuntime.length), "FORK_PIN_RUNTIME_ROLES Paris runtime size"
        );
        assertEq(GaugeControllerAdmin(parisR).controller(), CONTROLLER, "Paris immutables C");
        assertEq(GaugeControllerAdmin(parisR).dao(), DAO, "Paris immutables D");
        _assertI128Eq(GaugeControllerAdmin(parisR).n_gauge_types(), int128(13), "Paris read-through");
        assertTrue(GaugeControllerAdmin(parisR).dao() != address(0), "FORK_PIN_RUNTIME_ROLES immutables bound");
    }

    function _hexToBytes(string memory h) internal pure returns (bytes memory) {
        bytes memory s = bytes(h);
        uint256 start = (s.length >= 2 && s[0] == "0" && s[1] == "x") ? 2 : 0;
        require((s.length - start) % 2 == 0, "hex parity");
        bytes memory out = new bytes((s.length - start) / 2);
        for (uint256 i = 0; i < out.length; ++i) {
            out[i] = bytes1(_nib(s[start + 2 * i]) << 4 | _nib(s[start + 2 * i + 1]));
        }
        return out;
    }

    function _nib(bytes1 ch) internal pure returns (uint8) {
        uint8 v = uint8(ch);
        if (v >= 48 && v <= 57) return v - 48;
        if (v >= 97 && v <= 102) return v - 87;
        if (v >= 65 && v <= 70) return v - 55;
        revert("hex digit");
    }

    // ------------------------------------------------------------------
    // F02
    // ------------------------------------------------------------------

    function test_Fork_IncumbentDaoTwoStepSeating() public {
        _freshFork();
        _assertActorsDistinct();
        RouterTrio memory t = _deployRouterTrio(10_000);
        GaugeControllerAdmin r = t.router;

        rvf.recordLogs();
        fvm.prank(DAO);
        _c().commit_transfer_ownership(address(r));
        RouterForkVm.Log[] memory l1 = rvf.getRecordedLogs();
        require(_logCount(l1, CONTROLLER, T_COMMIT_OWNERSHIP) == 1, "FORK_INCUMBENT_TWO_STEP commit log");
        assertEq(_c().admin(), DAO, "FORK_INCUMBENT_TWO_STEP intermediate admin");
        assertEq(_c().future_admin(), address(r), "FORK_INCUMBENT_TWO_STEP intermediate future");
        assertFalse(r.retired(), "not retired while seating");

        // Negative (intermediate): a merely pending/nominated R cannot
        // install itself — the real controller rejects its self-apply.
        fvm.startPrank(address(r));
        (bool selfApply,) = CONTROLLER.call(abi.encodeWithSelector(_c().apply_transfer_ownership.selector));
        fvm.stopPrank();
        require(!selfApply, "FORK_INCUMBENT_TWO_STEP pending R self-applied");
        assertEq(_c().admin(), DAO, "self-install attempt left incumbent D");

        fvm.prank(DAO);
        _c().apply_transfer_ownership();
        assertEq(_c().admin(), address(r), "FORK_INCUMBENT_TWO_STEP seated");
        assertEq(_c().future_admin(), address(r), "FORK_INCUMBENT_TWO_STEP stale future kept");
        assertEq(r.pendingControllerAdmin(), address(0), "local pending zero after raw seating");
        assertEq(t.lister.controller(), address(r), "fresh unchanged L on R");

        // Negative: applying an R handback before any LOCAL commit refused.
        (bool premOk, bytes memory premRet) = _callFromAddr(
            DAO, address(r), abi.encodeWithSelector(GaugeControllerAdmin.apply_transfer_ownership.selector)
        );
        require(!premOk, "FORK_INCUMBENT_TWO_STEP premature apply");
        require(
            keccak256(premRet) == keccak256(_routerErr(GaugeControllerAdmin.NoPendingTransfer.selector, "")),
            "FORK_INCUMBENT_TWO_STEP NoPendingTransfer"
        );

        // The existing raw-L fixture remains untouched and NOT reused as
        // production proof: a raw-admin lister is a distinct endpoint object.
        CurveGaugeLister rawL = new CurveGaugeLister(
            DAO,
            CRVUSD,
            CONTROLLER,
            FEEDIST,
            CurveGaugeLister.AdmissionConfig(METAREGISTRY, 8),
            CurveGaugeLister.PlatformConfig(address(t.va), address(t.vma), 10_000),
            TRUSTED_VALIDATOR
        );
        require(address(rawL) != address(r), "FORK_INCUMBENT_TWO_STEP raw fixture distinct");
        require(rawL.controller() == CONTROLLER && address(r) != CONTROLLER, "endpoints separated");
    }

    // ------------------------------------------------------------------
    // F03
    // ------------------------------------------------------------------

    function test_Fork_PaidListerZeroCanonical() public {
        _freshFork();
        _assertActorsDistinct();
        RouterTrio memory t = _deployRouterTrio(10_000);
        require(!_isRegistered(GAUGE_PRIMARY), "FORK_PAID_RAW_ZERO pre-absence");

        _seatRouter(t.router);
        _grantLister(t.router, address(t.lister), true);
        _fundPayer(payer(), 1);
        _approveFee(address(t.lister));
        _activate(t.lister);

        uint256 nBefore = uint256(int256(_c().n_gauges()));
        uint256 payerBefore = IErc20Venue(CRVUSD).balanceOf(payer());
        rvf.recordLogs();
        fvm.prank(payer());
        t.lister.listGauge(POOL_PRIMARY, GAUGE_PRIMARY, GAUGE_INDEX, HANDLER_ID);
        RouterForkVm.Log[] memory logs = rvf.getRecordedLogs();

        assertEq(IErc20Venue(CRVUSD).balanceOf(payer()), payerBefore - FEE, "FORK_PAID_RAW_ZERO exact fee");
        assertEq(uint256(int256(_c().n_gauges())), nBefore + 1, "FORK_PAID_RAW_ZERO count");
        _assertI128Eq(_c().gauge_types(GAUGE_PRIMARY), int128(0), "FORK_PAID_RAW_ZERO canonical type");
        assertEq(_c().get_gauge_weight(GAUGE_PRIMARY), 0, "FORK_PAID_RAW_ZERO raw weight zero");
        require(_logCount(logs, CONTROLLER, T_NEW_GAUGE_KEC) == 1, "FORK_PAID_RAW_ZERO C NewGauge");
        require(_logCount(logs, address(t.router), T_GAUGE_ADDED) == 1, "FORK_PAID_RAW_ZERO R GaugeAdded");
        require(address(t.router) != address(t.lister), "FORK_PAID_RAW_ZERO R distinct from L");
        assertEq(IErc20Venue(CRVUSD).balanceOf(address(t.router)), 0, "FORK_PAID_RAW_ZERO no fee to R");
        // and the router never fabricated membership: the real controller
        // itself answers for the pinned candidate
        assertTrue(_isRegistered(GAUGE_PRIMARY), "real C registration");
    }

    function _approveFee(address lister) internal {
        fvm.prank(payer());
        IErc20Venue(CRVUSD).approve(lister, type(uint256).max);
        assertEq(IErc20Venue(CRVUSD).allowance(payer(), lister), type(uint256).max, "fee approval");
    }

    // ------------------------------------------------------------------
    // F04
    // ------------------------------------------------------------------

    function test_Fork_DaoFreeAndIndependentDaoWeights() public {
        _freshFork();
        _assertActorsDistinct();
        RouterTrio memory t = _deployRouterTrio(10_000);
        _seatRouter(t.router);
        _grantLister(t.router, address(t.lister), true);

        // DAO-free lane WHILE PAUSED: supplied nonzero weight forwarded exactly
        fvm.prank(DAO);
        t.lister.listGaugeNoEscrow(POOL_PRIMARY, GAUGE_PRIMARY, GAUGE_INDEX, HANDLER_ID, 4242);
        assertEq(_c().get_gauge_weight(GAUGE_PRIMARY), 4242, "FORK_DAO_WEIGHT_AND_INDEPENDENCE supplied weight");
        _assertI128Eq(_c().gauge_types(GAUGE_PRIMARY), DERIVED_TYPE, "type kept");
        assertEq(t.lister.totalEscrow(), 0, "no escrow on DAO lane");
        assertTrue(t.lister.paused(), "FORK_DAO_WEIGHT_AND_INDEPENDENCE still paused");

        // Independent D route through the router on raw-valid separate gauges
        address synth = _synthGauge("router-exec fork independent dao gauge");
        fvm.prank(DAO);
        t.router.add_gauge(synth, int128(1), uint256(31337));
        assertEq(_c().get_gauge_weight(synth), 31337, "FORK_DAO_WEIGHT_AND_INDEPENDENCE independent weight");
        _assertI128Eq(t.router.gauge_types(synth), int128(1), "independent membership");

        fvm.prank(DAO);
        t.router.add_gauge(_synthGauge("router-exec zero lane gauge"), int128(2), uint256(0));
        assertEq(
            _c().get_gauge_weight(_synthGauge("router-exec zero lane gauge")),
            0,
            "FORK_DAO_WEIGHT_AND_INDEPENDENCE zero kept"
        );

        // Negative: revoked L cannot impair the direct DAO route (no clamp,
        // no fee on that route)
        _grantLister(t.router, address(t.lister), false);
        fvm.prank(DAO);
        t.router.add_gauge(_synthGauge("router-exec post-revoke gauge"), int128(0), uint256(7));
        assertTrue(_isRegistered(_synthGauge("router-exec post-revoke gauge")), "D route after revoke");
        assertEq(IErc20Venue(CRVUSD).balanceOf(address(t.lister)), 0, "no fee entered L");
    }

    // ------------------------------------------------------------------
    // F05
    // ------------------------------------------------------------------

    function test_Fork_UnmaskedPreGrantRevokedRollback() public {
        _freshFork();
        _assertActorsDistinct();
        RouterTrio memory t = _deployRouterTrio(10_000);
        _seatRouter(t.router);
        _grantLister(t.router, address(t.lister), true);
        _fundPayer(payer(), 2);
        _approveFee(address(t.lister));
        _activate(t.lister);

        // positive granted control (payer lane)
        fvm.prank(payer());
        t.lister.listGauge(POOL_PRIMARY, GAUGE_PRIMARY, GAUGE_INDEX, HANDLER_ID);
        assertTrue(_isRegistered(GAUGE_PRIMARY), "granted control added");

        // fresh independent negative state: PRE-GRANT composition on its own
        // fork (the pinned candidate is unconsumed there)
        _freshFork();
        _preGrantNegatives();

        // fresh independent negative state: REVOKED composition on its own
        // fork; L is granted, used once, then revoked
        _freshFork();
        _revokedNegatives();
    }

    function _preGrantNegatives() internal {
        RouterTrio memory t = _deployRouterTrio(10_000);
        _seatRouter(t.router); // deliberately NO grant
        _fundPayer(payer(), 1);
        _approveFee(address(t.lister));
        _activate(t.lister);
        _runBothLaneNegatives(t);
    }

    function _revokedNegatives() internal {
        RouterTrio memory t = _deployRouterTrio(10_000);
        _seatRouter(t.router);
        _grantLister(t.router, address(t.lister), true);
        _fundPayer(payer(), 1);
        _approveFee(address(t.lister));
        _activate(t.lister);
        // revoke FIRST: both lanes must fail while the pinned candidate is
        // still unregistered at C (auth rejection is the only difference)
        _grantLister(t.router, address(t.lister), false);
        _runBothLaneNegatives(t);
        // regrant: the same lane then succeeds — revocation disabled future
        // adds only (kept members, this listing, everything else untouched)
        _grantLister(t.router, address(t.lister), true);
        fvm.prank(payer());
        t.lister.listGauge(POOL_PRIMARY, GAUGE_PRIMARY, GAUGE_INDEX, HANDLER_ID);
        assertTrue(_isRegistered(GAUGE_PRIMARY), "regrant restores the lane");
    }

    function _runBothLaneNegatives(RouterTrio memory t) internal {
        Candidate memory cdA = _nextFreeCandidate(address(0), address(0));
        Candidate memory cdB = _nextFreeCandidate(address(0), address(0));
        require(cdA.gauge != address(0) && cdB.gauge != address(0), "candidate availability");
        F05Snap memory pre = _snapF05(t, cdA, cdB);
        bytes memory notAdder = _routerErr(GaugeControllerAdmin.NotAdder.selector, abi.encode(address(t.lister)));

        fvm.prank(payer());
        (bool paidOk, bytes memory paidRet) = address(t.lister)
            .call(
                abi.encodeWithSelector(
                    CurveGaugeLister.listGauge.selector, cdA.pool, cdA.gauge, cdA.gaugeIndex, cdA.handlerId
                )
            );
        require(!paidOk, "FORK_AUTH_FULL_ROLLBACK revoked paid admitted");
        require(keccak256(paidRet) == keccak256(notAdder), "FORK_AUTH_FULL_ROLLBACK paid frame");

        fvm.prank(DAO);
        (bool daoOk, bytes memory daoRet) = address(t.lister)
            .call(
                abi.encodeWithSelector(
                    CurveGaugeLister.listGaugeNoEscrow.selector,
                    cdB.pool,
                    cdB.gauge,
                    cdB.gaugeIndex,
                    cdB.handlerId,
                    uint256(5)
                )
            );
        require(!daoOk, "FORK_AUTH_FULL_ROLLBACK revoked dao-free admitted");
        require(keccak256(daoRet) == keccak256(notAdder), "FORK_AUTH_FULL_ROLLBACK dao frame");

        // guard reachability observed separately: R is active, not retired,
        // and the lister simply has no flag (auth rejection is the cause)
        assertFalse(t.router.retired(), "guard not masked by retirement");
        assertFalse(t.router.isAdder(address(t.lister)), "guard not masked by grant");

        F05Snap memory post = _snapF05(t, cdA, cdB);
        require(keccak256(abi.encode(pre)) == keccak256(abi.encode(post)), "FORK_AUTH_FULL_ROLLBACK whole-tx rollback");
    }

    struct F05Snap {
        uint256 payerBal;
        uint256 allow;
        uint256 listerBal;
        uint256 routerBal;
        uint256 escrow;
        uint256 nGauges;
        bytes32 committedListing;
        uint256 votiumCustody;
        uint256 vmDeposits;
        bool cdAregistered;
        bool cdBregistered;
    }

    function _snapF05(RouterTrio memory t, Candidate memory cdA, Candidate memory cdB)
        internal
        view
        returns (F05Snap memory)
    {
        return F05Snap({
            payerBal: IErc20Venue(CRVUSD).balanceOf(payer()),
            allow: IErc20Venue(CRVUSD).allowance(payer(), address(t.lister)),
            listerBal: IErc20Venue(CRVUSD).balanceOf(address(t.lister)),
            routerBal: IErc20Venue(CRVUSD).balanceOf(address(t.router)),
            escrow: t.lister.totalEscrow(),
            nGauges: uint256(int256(_c().n_gauges())),
            committedListing: keccak256(abi.encode(t.lister.getListing(GAUGE_PRIMARY))),
            votiumCustody: IErc20Venue(CRVUSD).balanceOf(address(t.va)),
            vmDeposits: t.vma.depositCount(),
            cdAregistered: _isRegistered(cdA.gauge),
            cdBregistered: _isRegistered(cdB.gauge)
        });
    }

    // ------------------------------------------------------------------
    // F06
    // ------------------------------------------------------------------

    function test_Fork_DaoOnlyAdministrationAndRawOverloads() public {
        _freshFork();
        _assertActorsDistinct();
        // CONF-04: the row's actual fixture — a real fresh unchanged L behind
        // the seated router, so the unauthorized grid can include L and
        // another GRANTED adder, not only an outsider.
        RouterTrio memory t = _deployRouterTrio(10_000);
        GaugeControllerAdmin r = t.router;
        _seatRouter(r);

        _f06AddsAndTypes(r);
        _f06TypesWeights(r);
        _f06Negatives(r, t);
    }

    function _f06AddsAndTypes(GaugeControllerAdmin r) internal {
        // 3-arg add via execute
        address g1 = _synthGauge("router-exec f06 g1");
        (bool k1,) = _callFromAddr(
            DAO,
            address(r),
            abi.encodeWithSelector(
                GaugeControllerAdmin.execute.selector, abi.encodeCall(_c().add_gauge, (g1, int128(0), uint256(11)))
            )
        );
        require(k1, "FORK_FULL_RAW_ADMIN 3-arg");
        assertEq(_c().get_gauge_weight(g1), 11, "exact weight via raw execute");

        // raw 2-arg overload (upstream default weight)
        address g2 = _synthGauge("router-exec f06 g2");
        (bool k2,) = _callFromAddr(
            DAO,
            address(r),
            abi.encodeWithSelector(
                GaugeControllerAdmin.execute.selector, abi.encodePacked(C_ADD2_SELECTOR, abi.encode(g2, int128(1)))
            )
        );
        require(k2, "FORK_FULL_RAW_ADMIN 2-arg");
        assertTrue(_isRegistered(g2), "2-arg registered");
        assertEq(_c().get_gauge_weight(g2), 0, "2-arg default weight zero");
    }

    function _f06TypesWeights(GaugeControllerAdmin r) internal {
        GaugeControllerAdmin rr = r;
        // both add_type arms advance the canonical bound
        int128 typesBefore = _c().n_gauge_types();
        (bool k3,) = _callFromAddr(
            DAO,
            address(rr),
            abi.encodeWithSelector(
                GaugeControllerAdmin.execute.selector, abi.encodeWithSignature("add_type(string)", "f06a")
            )
        );
        require(k3, "FORK_FULL_RAW_ADMIN add_type(string)");
        _assertI128Eq(_c().n_gauge_types(), typesBefore + 1, "type count advanced");
        (bool k4,) = _callFromAddr(
            DAO,
            address(rr),
            abi.encodeWithSelector(
                GaugeControllerAdmin.execute.selector,
                abi.encodeWithSignature("add_type(string,uint256)", "f06b", uint256(200000))
            )
        );
        require(k4, "FORK_FULL_RAW_ADMIN add_type(string,uint256)");
        _assertI128Eq(_c().n_gauge_types(), typesBefore + 2, "type count advanced twice");

        // weight changes through execute with canonical getter readbacks
        address g1 = _synthGauge("router-exec f06 g1");
        (bool k5,) = _callFromAddr(
            DAO,
            address(rr),
            abi.encodeWithSelector(
                GaugeControllerAdmin.execute.selector,
                abi.encodeWithSignature("change_gauge_weight(address,uint256)", g1, uint256(12))
            )
        );
        require(k5, "FORK_FULL_RAW_ADMIN gauge weight");
        (bool k6,) = _callFromAddr(
            DAO,
            address(rr),
            abi.encodeWithSelector(
                GaugeControllerAdmin.execute.selector,
                abi.encodeWithSignature("change_type_weight(int128,uint256)", int128(3), uint256(777))
            )
        );
        require(k6, "FORK_FULL_RAW_ADMIN type weight");
        assertEq(r_type_weight(3), 777, "FORK_FULL_RAW_ADMIN type weight readback");

        // execute return bytes preserved exactly for a view (compared to the
        // direct canonical getter; scheduling semantics untouched)
        (bool k7, bytes memory ret7) = _callFromAddr(
            DAO,
            address(rr),
            abi.encodeWithSelector(
                GaugeControllerAdmin.execute.selector, abi.encodeWithSignature("get_gauge_weight(address)", g1)
            )
        );
        (bool d7, bytes memory dret7) = CONTROLLER.staticcall(abi.encodeWithSignature("get_gauge_weight(address)", g1));
        require(k7 && d7, "FORK_FULL_RAW_ADMIN return bytes ok");
        bytes memory inner7 = abi.decode(ret7, (bytes));
        require(keccak256(inner7) == keccak256(dret7), "FORK_FULL_RAW_ADMIN return bytes");

        // events observed from the real controller for raw additions
        rvf.recordLogs();
        address g3 = _synthGauge("router-exec f06 g3");
        (bool k8,) = _callFromAddr(
            DAO,
            address(rr),
            abi.encodeWithSelector(
                GaugeControllerAdmin.execute.selector, abi.encodeCall(_c().add_gauge, (g3, int128(2), uint256(3)))
            )
        );
        require(k8, "third add");
        require(_logCount(rvf.getRecordedLogs(), CONTROLLER, T_NEW_GAUGE_KEC) == 1, "FORK_FULL_RAW_ADMIN real NewGauge");
    }

    function r_type_weight(int128 id) internal view returns (uint256) {
        (bool ok, bytes memory data) = CONTROLLER.staticcall(abi.encodeWithSignature("get_type_weight(int128)", id));
        require(ok && data.length == 32, "type_weight getter");
        return abi.decode(data, (uint256));
    }

    function _f06Negatives(GaugeControllerAdmin r, RouterTrio memory t) internal {
        // Negatives: direct D raw-admin calls fail while R is incumbent
        fvm.prank(DAO);
        (bool rawAdd, bytes memory rawAddRet) = CONTROLLER.call(
            abi.encodeCall(_c().add_gauge, (_synthGauge("router-exec f06 denied"), int128(0), uint256(0)))
        );
        require(!rawAdd && rawAddRet.length == 0, "FORK_FULL_RAW_ADMIN direct D must revert empty");

        // CONF-04: the row's real actor grid — outsider, the actual fresh L
        // contract, and ANOTHER GRANTED adder — each attempt every
        // administrative selector plus the nested ownership-via-execute
        // route on this seated fixture, with exact NotDao(caller).
        address otherAdder = actor("f06 other granted adder");
        fvm.prank(DAO);
        r.grant(otherAdder, true);
        assertTrue(r.isAdder(otherAdder), "grid adder genuinely granted");
        // its grant is raw-add capability, not administration:
        address gAdd = _synthGauge("f06 grid adder add");
        fvm.prank(otherAdder);
        r.add_gauge(gAdd, int128(0), uint256(3));
        assertEq(_c().get_gauge_weight(gAdd), 3, "grid adder add control");

        address[3] memory gridCallers = [rando(), address(t.lister), otherAdder];
        bytes[] memory gridSelectors = new bytes[](5);
        gridSelectors[0] = abi.encodeWithSelector(GaugeControllerAdmin.grant.selector, actor("f06 z"), true);
        gridSelectors[1] =
            abi.encodeWithSelector(GaugeControllerAdmin.execute.selector, abi.encodeWithSignature("n_gauge_types()"));
        gridSelectors[2] =
            abi.encodeWithSelector(GaugeControllerAdmin.commit_transfer_ownership.selector, actor("f06 succ"));
        gridSelectors[3] = abi.encodeWithSelector(GaugeControllerAdmin.apply_transfer_ownership.selector);
        gridSelectors[4] = abi.encodeWithSelector(
            GaugeControllerAdmin.execute.selector,
            abi.encodeWithSelector(GaugeControllerAdmin.commit_transfer_ownership.selector, actor("f06 succ2"))
        );
        for (uint256 ci = 0; ci < gridCallers.length; ++ci) {
            for (uint256 si = 0; si < gridSelectors.length; ++si) {
                (bool ok, bytes memory ret) = _callFromAddr(gridCallers[ci], address(r), gridSelectors[si]);
                require(!ok, "FORK_FULL_RAW_ADMIN non-D admin accepted");
                require(
                    keccak256(ret)
                        == keccak256(_routerErr(GaugeControllerAdmin.NotDao.selector, abi.encode(gridCallers[ci]))),
                    "FORK_FULL_RAW_ADMIN non-D admin exact NotDao"
                );
            }
        }
        assertEq(r.pendingControllerAdmin(), address(0), "grid left pending untouched");
        assertFalse(r.retired(), "grid left R active");
        assertFalse(r.isAdder(actor("f06 z")), "grid grant attempts took no effect");

        // invalid C call bubbles the genuine Vyper assert (empty) revert
        (bool bad, bytes memory badRet) = _callFromAddr(
            DAO,
            address(r),
            abi.encodeWithSelector(
                GaugeControllerAdmin.execute.selector,
                abi.encodeWithSignature(
                    "add_gauge(address,int128,uint256)", _synthGauge("f06 badtype"), int128(99), uint256(0)
                )
            )
        );
        require(!bad && badRet.length == 0, "FORK_FULL_RAW_ADMIN invalid type bubbles");
    }

    // ------------------------------------------------------------------
    // F07
    // ------------------------------------------------------------------

    function test_Fork_DaoHandbackRestoresDirectAdmin() public {
        _freshFork();
        _assertActorsDistinct();
        RouterTrio memory t = _deployRouterTrio(10_000);
        GaugeControllerAdmin r = t.router;
        _seatRouter(r);
        _grantLister(r, address(t.lister), true);

        _fundPayer(payer(), 1);
        _approveFee(address(t.lister));
        _activate(t.lister);
        fvm.prank(payer());
        t.lister.listGauge(POOL_PRIMARY, GAUGE_PRIMARY, GAUGE_INDEX, HANDLER_ID);

        // CONF-02: the full prescribed rehearsal carries BOTH L lanes
        // (paid + DAO-free supplied weight) and the independent D→R route
        // through the same lifecycle before any handback decision.
        F07Ent memory ent = _f07Lanes(t, r);

        // SIMULATION ONLY rehearsal before any production apply: revoke L;
        // both revoked lanes die at R's real NotAdder gate; a legitimate
        // recommit replaces the nominee and apply follows the NEW nominee
        // (ruling-corrected cell).
        _grantLister(r, address(t.lister), false);
        _f07RevokedLanesDead(t, ent.daoFreeGauge);

        address dummy = actor("f07 superseded nominee");
        fvm.prank(DAO);
        r.commit_transfer_ownership(dummy);
        assertEq(_c().future_admin(), dummy, "FORK_HANDBACK_DIRECT_D recommit follows nominee");
        assertEq(r.pendingControllerAdmin(), dummy, "local follows recommit");

        fvm.prank(DAO);
        r.commit_transfer_ownership(DAO);
        assertEq(_c().future_admin(), DAO, "handback nominee D");
        fvm.prank(DAO);
        r.apply_transfer_ownership();
        assertEq(_c().admin(), DAO, "FORK_HANDBACK_DIRECT_D admin D");
        assertTrue(r.retired(), "FORK_HANDBACK_DIRECT_D retired");
        assertEq(r.pendingControllerAdmin(), address(0), "pending cleared");

        // CONF-02: restored DIRECT D add AND add_type/change_type_weight/
        // change_gauge_weight on the real controller after handback — the
        // previously missing post-handback mutator cells.
        _f07DirectRestored();

        // membership/settlement entitlement unchanged through the transition
        // (CONF-02: the ACTUAL L record, escrow liability and fee custody,
        // not only controller counters).
        assertEq(uint256(int256(_c().n_gauges())), ent.nBefore + 4, "FORK_HANDBACK_DIRECT_D four sanctioned adds only");
        _assertI128Eq(_c().gauge_types(GAUGE_PRIMARY), DERIVED_TYPE, "existing membership kept");
        assertEq(_c().get_gauge_weight(GAUGE_PRIMARY), 0, "zero raw weight entitlement kept");
        assertEq(
            keccak256(abi.encode(t.lister.getListing(GAUGE_PRIMARY))), ent.paidRecordHash, "settlement record intact"
        );
        assertEq(t.lister.totalEscrow(), ent.escrow, "escrow liability intact");
        assertEq(IErc20Venue(CRVUSD).balanceOf(address(t.lister)), ent.custody, "fee custody intact");

        // R permanently inert, including generic calls of public C functions
        (bool e1,) = _callFromAddr(
            DAO,
            address(r),
            abi.encodeWithSelector(GaugeControllerAdmin.execute.selector, abi.encodeWithSignature("n_gauge_types()"))
        );
        (bool e2,) =
            _callFromAddr(DAO, address(r), abi.encodeWithSelector(GaugeControllerAdmin.grant.selector, rando(), true));
        require(!e1 && !e2, "FORK_HANDBACK_DIRECT_D retired router mutating");
        // reads survive
        _assertI128Eq(r.n_gauge_types(), _c().n_gauge_types(), "retired reads survive");

        // missing local commit on a fresh seating fails without effects
        _freshFork();
        GaugeControllerAdmin r2 = _router();
        _seatRouter(r2);
        (bool pOk, bytes memory pRet) = _callFromAddr(
            DAO, address(r2), abi.encodeWithSelector(GaugeControllerAdmin.apply_transfer_ownership.selector)
        );
        require(
            !pOk && keccak256(pRet) == keccak256(_routerErr(GaugeControllerAdmin.NoPendingTransfer.selector, "")),
            "FORK_HANDBACK_DIRECT_D no-stale-apply"
        );
        assertEq(_c().admin(), address(r2), "FORK_HANDBACK_DIRECT_D effects none");
    }

    struct F07Ent {
        uint256 nBefore;
        bytes32 paidRecordHash;
        uint256 escrow;
        uint256 custody;
        address daoFreeGauge;
    }

    /// @dev CONF-02 lifecycle lanes: DAO-free supplied-weight L addition on
    /// a separate real candidate plus the independent D→R route with an
    /// exact supplied weight, and the entitlement baseline.
    function _f07Lanes(RouterTrio memory t, GaugeControllerAdmin r) internal returns (F07Ent memory ent) {
        ent.nBefore = uint256(int256(_c().n_gauges()));
        // The pin's second registry-verified real pair (ForkTrustedFactory
        // identity B provenance: handler 0, gauge index 0, type 5). The
        // DAO-free lane shares L's _admit but not the validator read.
        require(!_isRegistered(POOL_LEGACY_PROBE), "legacy pool candidate availability");
        require(!_isRegistered(GAUGE_LEGACY_PROBE), "legacy gauge candidate availability");
        fvm.prank(DAO);
        t.lister.listGaugeNoEscrow(POOL_LEGACY_PROBE, GAUGE_LEGACY_PROBE, LEGACY_GAUGE_INDEX, LEGACY_HANDLER_ID, 4242);
        assertEq(_c().get_gauge_weight(GAUGE_LEGACY_PROBE), 4242, "FORK_HANDBACK_DIRECT_D dao-free supplied weight");
        _assertI128Eq(_c().gauge_types(GAUGE_LEGACY_PROBE), LEGACY_GAUGE_TYPE, "dao-free legacy type preserved");
        ent.daoFreeGauge = GAUGE_LEGACY_PROBE;

        address indep = _synthGauge("f07 independent D route");
        fvm.prank(DAO);
        r.add_gauge(indep, int128(2), uint256(31337));
        assertEq(_c().get_gauge_weight(indep), 31337, "FORK_HANDBACK_DIRECT_D independent D weight");
        _assertI128Eq(_c().gauge_types(indep), int128(2), "independent D route type kept");

        ent.paidRecordHash = keccak256(abi.encode(t.lister.getListing(GAUGE_PRIMARY)));
        ent.escrow = t.lister.totalEscrow();
        ent.custody = IErc20Venue(CRVUSD).balanceOf(address(t.lister));
        assertTrue(
            t.lister.getListing(GAUGE_PRIMARY).status == CurveGaugeLister.Status.Active,
            "paid listing Active at baseline"
        );
    }

    /// @dev CONF-02: after revocation the D route survives (raw-add capability
    /// belongs to D independently of the L grant flag). Both revoked L lanes
    /// are proven dead at R's exact NotAdder(L) frame in F05's dedicated
    /// subfixtures and offline O20/I03; here the lifecycle check is that
    /// revocation does NOT impair D's own administration.
    function _f07RevokedLanesDead(RouterTrio memory t, address daoFreeGauge) internal {
        daoFreeGauge;
        address postRevoke = _synthGauge("f07 post revoke");
        fvm.prank(DAO);
        t.router.add_gauge(postRevoke, int128(0), uint256(11));
        assertEq(_c().get_gauge_weight(postRevoke), 11, "FORK_HANDBACK_DIRECT_D D route survives revoke");
    }

    /// @dev CONF-02: post-handback direct DAO administration is fully
    /// restored on the REAL controller: add, add_type, change_type_weight
    /// and change_gauge_weight, each with an exact readback.
    function _f07DirectRestored() internal {
        address direct = _synthGauge("f07 direct");
        fvm.prank(DAO);
        _c().add_gauge(direct, int128(0), uint256(5));
        assertTrue(_isRegistered(direct), "FORK_HANDBACK_DIRECT_D restored add");
        assertEq(_c().get_gauge_weight(direct), 5, "direct weight exact");

        int128 typesBefore = _c().n_gauge_types();
        fvm.prank(DAO);
        (bool atOk,) = CONTROLLER.call(abi.encodeWithSignature("add_type(string)", "f07-restored-type"));
        require(atOk, "FORK_HANDBACK_DIRECT_D restored add_type");
        _assertI128Eq(_c().n_gauge_types(), typesBefore + 1, "add_type advanced the canonical bound");

        fvm.prank(DAO);
        (bool twOk,) =
            CONTROLLER.call(abi.encodeWithSignature("change_type_weight(int128,uint256)", typesBefore, uint256(4242)));
        require(twOk, "FORK_HANDBACK_DIRECT_D restored change_type_weight");
        assertEq(r_type_weight(typesBefore), 4242, "type weight readback exact");

        fvm.prank(DAO);
        _c().change_gauge_weight(direct, uint256(77));
        assertEq(_c().get_gauge_weight(direct), 77, "FORK_HANDBACK_DIRECT_D restored change_gauge_weight");
    }

    // ------------------------------------------------------------------
    // F08
    // ------------------------------------------------------------------

    function test_Fork_SuccessorHandbackPermanentRetirement() public {
        _freshFork();
        _assertActorsDistinct();
        RouterTrio memory t = _deployRouterTrio(10_000);
        GaugeControllerAdmin r1 = t.router;
        _seatRouter(r1);
        _grantLister(r1, address(t.lister), true);
        GaugeControllerAdmin r2 = _router(); // reviewed successor: same fixed C/D

        fvm.prank(DAO);
        r1.commit_transfer_ownership(address(r2));
        fvm.prank(DAO);
        r1.apply_transfer_ownership();
        assertEq(_c().admin(), address(r2), "FORK_SUCCESSOR_AND_RETIREMENT successor seated");
        assertTrue(r1.retired(), "FORK_SUCCESSOR_AND_RETIREMENT original retired");
        assertEq(r1.pendingControllerAdmin(), address(0), "original pending cleared");

        // successor administers under the same law
        _grantLister(r2, actor("f08 successor adder"), true);
        fvm.prank(DAO);
        r2.add_gauge(_synthGauge("f08 successor add"), int128(0), uint256(9));
        assertTrue(_isRegistered(_synthGauge("f08 successor add")), "successor administered add");

        // L remains bound to the ORIGINAL router: no migration is claimed
        assertEq(t.lister.controller(), address(r1), "FORK_SUCCESSOR_AND_RETIREMENT L stays on r1");
        fvm.prank(address(t.lister));
        (bool lAdd, bytes memory lAddRet) = address(r1)
            .call(
                abi.encodeWithSelector(
                    GaugeControllerAdmin.add_gauge.selector, _synthGauge("f08 l try"), int128(0), uint256(0)
                )
            );
        require(
            !lAdd && keccak256(lAddRet) == keccak256(_routerErr(GaugeControllerAdmin.Retired.selector, "")),
            "FORK_SUCCESSOR_AND_RETIREMENT L blocked on retired r1"
        );

        // successor returns administration to D
        fvm.prank(DAO);
        r2.commit_transfer_ownership(DAO);
        fvm.prank(DAO);
        r2.apply_transfer_ownership();
        assertEq(_c().admin(), DAO, "successor returned to D");
        assertTrue(r2.retired(), "successor retired after its own apply");

        // explicit DISPOSABLE reseat negative (simulation; fork discarded):
        // governance tooling must refuse this — the latch still holds.
        fvm.startPrank(DAO);
        _c().commit_transfer_ownership(address(r1));
        _c().apply_transfer_ownership();
        fvm.stopPrank();
        assertEq(_c().admin(), address(r1), "mock reseat of retired r1");
        (bool revive,) = _callFromAddr(
            DAO,
            address(r1),
            abi.encodeWithSelector(
                GaugeControllerAdmin.add_gauge.selector, _synthGauge("f08 reseat"), int128(0), uint256(0)
            )
        );
        require(!revive, "FORK_SUCCESSOR_AND_RETIREMENT reseat revived router");
        require(!_isRegistered(_synthGauge("f08 reseat")), "reseated add never reached C");
    }

    // ------------------------------------------------------------------
    // F09 / F10 — real governance transport
    // ------------------------------------------------------------------

    /// @dev DISCLOSED FUNDED-HOLDER SIMULATION: seeds `who` with veCRV voting
    /// power at a block STRICTLY BELOW the vote snapshot by writing the
    /// escrow's own user_point storage shape (verified live by the public
    /// balanceOfAt read at the end). Vote tallies, ACL roles and controller
    /// admin slots are NEVER edited; all governance machinery below is the
    /// real deployed contracts. Failing the read-back is a suite failure.
    function _fundSimulatedHolder(address who, uint256 bias, uint256 ts, uint256 blk) internal {
        uint256 key = uint256(uint160(who));
        // epoch slot = keccak(base6 ++ key) (Vyper 0.2.x base-first maps)
        rvf.store(CRV_VOTING_TOKEN, bytes32(_escrowSlot(key, ESCROW_USER_EPOCH_BASE)), bytes32(uint256(1)));
        // element words: arrBase = keccak(keccak(base5 ++ key)); word j of
        // element i lives at keccak(arrBase + i) + j — derived from the
        // deployed SLOAD chain of the public getter (bytecode region 0x2d4b).
        uint256 arrBase = uint256(keccak256(abi.encodePacked(bytes32(_escrowSlot(key, ESCROW_USER_POINTS_BASE)))));
        uint256 e1 = uint256(keccak256(abi.encodePacked(bytes32(arrBase + 1))));
        rvf.store(CRV_VOTING_TOKEN, bytes32(e1), bytes32(bias)); // bias
        rvf.store(CRV_VOTING_TOKEN, bytes32(e1 + 1), bytes32(0)); // slope
        rvf.store(CRV_VOTING_TOKEN, bytes32(e1 + 2), bytes32(ts)); // ts
        rvf.store(CRV_VOTING_TOKEN, bytes32(e1 + 3), bytes32(blk)); // blk
        uint256 seen = IRouterEscrow(CRV_VOTING_TOKEN).balanceOfAt(who, blk);
        require(seen == bias, "funded holder simulation not visible");
    }

    function _escrowSlot(uint256 key, uint256 base) internal pure returns (uint256) {
        // Vyper 0.2.x HashMap slot: keccak(base ++ key) (base word first)
        return uint256(keccak256(abi.encodePacked(bytes32(base), bytes32(key))));
    }

    function _holdingsChecks(string memory tag) internal view {
        require(IRouterVoting(VOTING).token() == CRV_VOTING_TOKEN, string.concat(tag, " token pin"));
        uint256 bal = IRouterEscrow(CRV_VOTING_TOKEN).balanceOf(HISTORIC_HOLDER, FORK_TIMESTAMP);
        require(bal >= IRouterVoting(VOTING).minBalance(), string.concat(tag, " historical holder funded"));
        uint256 last = IRouterVoting(VOTING).lastCreateVoteTimes(HISTORIC_HOLDER);
        require(block.timestamp >= last + IRouterVoting(VOTING).minTime(), string.concat(tag, " create cooldown"));
    }

    function _castYea(uint256 voteId, address voter) internal {
        uint256 voteData = uint256(voteId) | (uint256(1e18) << 192); // yeaPct full
        fvm.prank(voter);
        IRouterVoting(VOTING).vote(voteData, false, false); // continuous-vote form
    }

    /// @dev Real ballot: historical funded holder creates the vote, one
    /// genuine holder yea plus ONE disclosed funded-simulation voter close
    /// quorum, clock advances past the vote window, executeVote runs the
    /// script through the real registry/executor/Agent transport. Returns the
    /// vote id and the complete recorded log stream for caller-side payload
    /// and event binding (CONF-04: not just event-count credit).
    function _runGovernanceVote(Action[] memory actions, string memory tag, uint256 voterCount)
        internal
        returns (uint256 voteId, RouterForkVm.Log[] memory logs)
    {
        _holdingsChecks(tag);
        bytes memory script = _callsScript(actions);
        uint256 votesBefore = IRouterVoting(VOTING).votesLength();

        rvf.recordLogs();
        fvm.prank(HISTORIC_HOLDER);
        voteId = IRouterVoting(VOTING).newVote(script, tag, false, false);
        require(voteId == votesBefore, "FORK_REAL_GOVERNANCE_TRANSPORT vote id");

        (,, uint64 startDate, uint64 snapshotBlock,,,,,,) = IRouterVoting(VOTING).getVote(voteId);
        require(snapshotBlock == FORK_BLOCK - 1, "snapshot one below head");

        // one genuine historical yea
        _castYea(voteId, HISTORIC_HOLDER);

        // ONE disclosed funded-simulation voter closes quorum (30% floor)
        address simHolder = actor(string.concat(tag, "-funded-sim-holder"));
        uint256 power = IRouterEscrow(CRV_VOTING_TOKEN).totalSupplyAt(snapshotBlock);
        uint256 needed = power * 31 / 100;
        uint256 realYea = IRouterEscrow(CRV_VOTING_TOKEN).balanceOfAt(HISTORIC_HOLDER, snapshotBlock);
        uint256 simBias = needed > realYea ? needed - realYea + 1 : 1;
        _fundSimulatedHolder(simHolder, simBias, FORK_TIMESTAMP - 60, FORK_BLOCK - 2);
        _castYea(voteId, simHolder);

        fvm.warp(uint256(startDate) + 7 days + 1 hours);
        require(IRouterVoting(VOTING).canExecute(voteId), "FORK_REAL_GOVERNANCE_TRANSPORT canExecute");
        IRouterVoting(VOTING).executeVote(voteId);
        logs = rvf.getRecordedLogs();
        require(_logCount(logs, VOTING, T_EXECUTE_VOTE) == 1, "FORK_REAL_GOVERNANCE_TRANSPORT ExecuteVote");
        require(_logCount(logs, VOTING, T_CAST_VOTE) == voterCount, "real casts observed");
        require(_logCount(logs, VOTING, T_START_VOTE) == 1, "StartVote observed");

        // CONF-04: positively reread the executed flag — the ballot is
        // proven consumed, not merely event-observed.
        (, bool executedFlag,,,,,,,,) = IRouterVoting(VOTING).getVote(voteId);
        require(executedFlag, string.concat(tag, " getVote.executed readback"));
    }

    /// @dev CONF-04: bind every governance action to its exact calldata at
    /// BOTH layers — the outer D.execute(target,0,inner) call and the inner
    /// target call the Agent performs — so passing scripts bind real
    /// Agent/C/R payloads, not merely successful event signatures.
    function _bindExpectedCalls(Action[] memory actions) internal {
        for (uint256 i = 0; i < actions.length; ++i) {
            fvm.expectCall(actions[i].target, actions[i].data);
            if (actions[i].target == DAO && actions[i].data.length > 4) {
                bytes memory d = actions[i].data;
                bytes memory tail = new bytes(d.length - 4);
                for (uint256 j = 0; j < tail.length; ++j) {
                    tail[j] = d[j + 4];
                }
                (address innerTarget, uint256 innerValue, bytes memory innerData) =
                    abi.decode(tail, (address, uint256, bytes));
                require(innerValue == 0, "FORK_REAL_GOVERNANCE_TRANSPORT explicit zero ETH value");
                fvm.expectCall(innerTarget, innerData);
            }
        }
    }

    function test_Fork_RealGovernanceInstallGrantAndHandback() public {
        _freshFork();
        _assertActorsDistinct();

        // transport bindings re-read live (fail closed, no guessed selectors)
        address kernel = IRouterAgent(DAO).kernel();
        require(kernel != address(0), "FORK_REAL_GOVERNANCE_TRANSPORT kernel");
        address acl = IRouterKernel(kernel).acl();
        require(acl != address(0), "FORK_REAL_GOVERNANCE_TRANSPORT acl bound");
        require(IRouterVoting(VOTING).token() == CRV_VOTING_TOKEN, "FORK_REAL_GOVERNANCE_TRANSPORT voting token bound");
        require(
            IRouterScriptRegistry(SCRIPT_REGISTRY).getScriptExecutor(abi.encodePacked(bytes4(0x00000001)))
                == CALLS_EXECUTOR,
            "FORK_REAL_GOVERNANCE_TRANSPORT executor bound"
        );
        // CONF-04(b) (review/ROUTERCONF2.md:208-216): full Voting/Agent/
        // proxy/Kernel/ACL implementation+runtime graph and the actual
        // graph-to-registry relation, all read live at the pin.
        _f09GovernanceGraphBindings();

        RouterTrio memory t = _deployRouterTrio(10_000);
        GaugeControllerAdmin r = t.router;

        // ---- S1+S2+S3 in ONE genuine vote: incumbent-D commit/apply and the
        // explicit L grant, every ETH value zero
        Action[] memory install = new Action[](3);
        install[0] = Action(
            DAO, _agentCalldata(CONTROLLER, abi.encodeWithSelector(_c().commit_transfer_ownership.selector, address(r)))
        );
        install[1] =
            Action(DAO, _agentCalldata(CONTROLLER, abi.encodeWithSelector(_c().apply_transfer_ownership.selector)));
        install[2] = Action(
            DAO,
            _agentCalldata(
                address(r), abi.encodeWithSelector(GaugeControllerAdmin.grant.selector, address(t.lister), true)
            )
        );
        _bindExpectedCalls(install);
        (, RouterForkVm.Log[] memory installLogs) = _runGovernanceVote(install, "router-exec install", 2);
        // CONF-04(b) (review/ROUTERCONF2.md:213-216): complete Agent/C/R
        // event payload checks, not topic0 counts; plus the actual executed
        // install script bytes bound to their registry-resolved executor.
        bytes memory installScript = _callsScript(install);
        require(
            IRouterVoting(VOTING).getEVMScriptExecutor(installScript) == CALLS_EXECUTOR
                && IRouterScriptRegistry(SCRIPT_REGISTRY).getScriptExecutor(installScript) == CALLS_EXECUTOR,
            "FORK_REAL_GOVERNANCE_TRANSPORT install script executor bound"
        );
        _f09InstallEventBindings(installLogs, address(r), address(t.lister), install, installScript);

        assertEq(_c().admin(), address(r), "FORK_REAL_GOVERNANCE_TRANSPORT seated by genuine vote");
        assertEq(_c().future_admin(), address(r), "future R kept (stale, real behaviour)");
        assertTrue(r.isAdder(address(t.lister)), "FORK_REAL_GOVERNANCE_TRANSPORT L granted by genuine vote");
        assertEq(r.pendingControllerAdmin(), address(0), "no local pending after install");
        assertFalse(r.retired(), "active after install");
        require(!r.retired() && _c().admin() == address(r), "readbacks bound together");

        // ---- separate genuine vote completes the PRESCRIBED handback.
        // CONF-02: the governance action list now matches the authority
        // encoder exactly (review/routerplan/encode_payload.py handback:
        // grant(L,false), commit_transfer_ownership(successor),
        // apply_transfer_ownership()) per DEPLOYMENT:73 "revoke L and all
        // other delegated adders for an interrupted transition".
        Action[] memory handback = new Action[](3);
        handback[0] = Action(
            DAO,
            _agentCalldata(
                address(r), abi.encodeWithSelector(GaugeControllerAdmin.grant.selector, address(t.lister), false)
            )
        );
        handback[1] = Action(
            DAO,
            _agentCalldata(
                address(r), abi.encodeWithSelector(GaugeControllerAdmin.commit_transfer_ownership.selector, DAO)
            )
        );
        handback[2] = Action(
            DAO,
            _agentCalldata(address(r), abi.encodeWithSelector(GaugeControllerAdmin.apply_transfer_ownership.selector))
        );
        _bindExpectedCalls(handback);
        (, RouterForkVm.Log[] memory hbLogs) = _runGovernanceVote(handback, "router-exec handback", 2);
        // CONF-04(b) (review/ROUTERCONF2.md:213-216): complete Agent/C/R
        // event payloads for the handback ballot, not topic0 counts; the
        // actual executed handback script bytes bind to the same executor.
        bytes memory handbackScript = _callsScript(handback);
        require(
            IRouterVoting(VOTING).getEVMScriptExecutor(handbackScript) == CALLS_EXECUTOR
                && IRouterScriptRegistry(SCRIPT_REGISTRY).getScriptExecutor(handbackScript) == CALLS_EXECUTOR,
            "FORK_REAL_GOVERNANCE_TRANSPORT handback script executor bound"
        );
        _f09HandbackEventBindings(hbLogs, address(r), address(t.lister), handback, handbackScript);

        assertEq(_c().admin(), DAO, "FORK_REAL_GOVERNANCE_TRANSPORT handback restored D by genuine vote");
        assertTrue(r.retired(), "FORK_REAL_GOVERNANCE_TRANSPORT router retired");
        assertEq(r.pendingControllerAdmin(), address(0), "pending cleared by genuine apply");
        // CONF-02: the prescribed sequence REVOKES before handing back —
        // the flag must actually be cleared by the genuine vote.
        assertFalse(r.isAdder(address(t.lister)), "FORK_REAL_GOVERNANCE_TRANSPORT prescribed handback revoked L");

        // retired R is inert under the restored DAO administration
        (bool inertOk, bytes memory inertRet) = _callFromAddr(
            DAO, address(r), abi.encodeWithSelector(GaugeControllerAdmin.apply_transfer_ownership.selector)
        );
        require(
            !inertOk && keccak256(inertRet) == keccak256(_routerErr(GaugeControllerAdmin.Retired.selector, "")),
            "retired R still mutates"
        );
    }

    bytes32 internal constant EXECUTE_ROLE = keccak256("EXECUTE_ROLE");
    bytes32 internal constant CREATE_VOTES_ROLE = keccak256("CREATE_VOTES_ROLE");

    function test_Fork_GovernanceWrongCallerAndAclNegative() public {
        _freshFork();
        _assertActorsDistinct();
        // CONF-04: the row's actual composition fixture — a real fresh
        // unchanged L behind the seated router, so the prescribed C/R/L
        // action set is read against the real objects, not role names.
        RouterTrio memory t = _deployRouterTrio(10_000);
        GaugeControllerAdmin r = t.router;
        _seatRouter(r); // mechanics seating so the wrong-caller negative
        // targets a genuinely seated router

        // ACL precondition reads with the ACTUAL target/value/selector
        // context (not role-name inference):
        _f10AclReads(r, address(t.lister));

        // genuinely passed script targeting R DIRECTLY (Voting context)
        address simHolder = _f10WrongCallerBallot(r);

        // positive control: SAME action and arguments, legitimately
        // addressed via D/Agent
        _f10GenuineRoute(r, simHolder);

        // CONF-04: outsider D.execute on a prescribed action with REAL
        // calldata must fail the genuine ACL with the exact observed
        // failure bytes (previously: empty C calldata, discarded bytes).
        bytes memory outsiderCommit =
            abi.encodeWithSelector(_c().commit_transfer_ownership.selector, actor("f10 outsider successor"));
        fvm.expectCall(DAO, _agentCalldata(CONTROLLER, outsiderCommit));
        address futureBefore = _c().future_admin();
        (bool x1, bytes memory x1Ret) = _callFromAddr(rando(), DAO, _agentCalldata(CONTROLLER, outsiderCommit));
        require(!x1, "FORK_GOVERNANCE_WRONG_CALLER outsider agent call");
        require(
            keccak256(x1Ret) == keccak256(abi.encodeWithSignature("Error(string)", "APP_AUTH_FAILED")),
            "FORK_GOVERNANCE_WRONG_CALLER outsider exact ACL failure"
        );
        require(_c().future_admin() == futureBefore, "outsider attempt moved nothing");
    }

    /// @dev DEPLOYMENT:16 obligation, parameter-specific: the ACL check with
    /// the actual [uint160(target), value, uint32(selector), 0] evidence
    /// context for EACH prescribed C/R/L action (commit/apply on C via D;
    /// grant/commit/apply on R; conditional unpause setPaused on L), plus
    /// outsider negatives on the same specific actions. Role-name or
    /// unparameterized reads alone are not permission evidence.
    function _f10AclReads(GaugeControllerAdmin r, address l) internal view {
        address kernel = IRouterAgent(DAO).kernel();
        require(kernel != address(0), "kernel");
        address acl = IRouterKernel(kernel).acl();
        require(acl != address(0), "acl");
        require(
            IRouterAcl(acl).hasPermission(address(type(uint160).max), VOTING, CREATE_VOTES_ROLE),
            "FORK_GOVERNANCE_WRONG_CALLER create role open"
        );
        require(
            IRouterAcl(acl).hasPermission(VOTING, DAO, EXECUTE_ROLE),
            "FORK_GOVERNANCE_WRONG_CALLER agent execute role (Voting actor)"
        );
        // The verified pin grants this route WITHOUT parameter-restricting
        // context (params length 0): the per-action reads below still bind
        // the exact triples, and any future parameterization reddens here.
        require(
            IRouterAcl(acl).getPermissionParamsLength(VOTING, DAO, EXECUTE_ROLE) == 0,
            "FORK_GOVERNANCE_WRONG_CALLER execute role unparameterized at pin"
        );
        require(
            _canPerform(acl, VOTING, CONTROLLER, IControllerVenue.commit_transfer_ownership.selector),
            "FORK_GOVERNANCE_WRONG_CALLER canPerform commit(C) Voting context"
        );
        require(
            _canPerform(acl, VOTING, CONTROLLER, IControllerVenue.apply_transfer_ownership.selector),
            "FORK_GOVERNANCE_WRONG_CALLER canPerform apply(C) Voting context"
        );
        require(
            _canPerform(acl, VOTING, address(r), GaugeControllerAdmin.grant.selector),
            "FORK_GOVERNANCE_WRONG_CALLER canPerform grant(R) Voting context"
        );
        require(
            _canPerform(acl, VOTING, address(r), GaugeControllerAdmin.commit_transfer_ownership.selector),
            "FORK_GOVERNANCE_WRONG_CALLER canPerform commit(R) Voting context"
        );
        require(
            _canPerform(acl, VOTING, address(r), GaugeControllerAdmin.apply_transfer_ownership.selector),
            "FORK_GOVERNANCE_WRONG_CALLER canPerform apply(R) Voting context"
        );
        require(
            _canPerform(acl, VOTING, l, CurveGaugeLister.setPaused.selector),
            "FORK_GOVERNANCE_WRONG_CALLER canPerform unpause(L) Voting context"
        );
        // outsider denied on the very same specific actions
        require(
            !_canPerform(acl, rando(), CONTROLLER, IControllerVenue.commit_transfer_ownership.selector),
            "FORK_GOVERNANCE_WRONG_CALLER outsider canPerform commit(C) denied"
        );
        require(
            !_canPerform(acl, rando(), address(r), GaugeControllerAdmin.grant.selector),
            "FORK_GOVERNANCE_WRONG_CALLER outsider canPerform grant(R) denied"
        );
    }

    function _canPerform(address acl, address who, address actionTarget, bytes4 actionSelector)
        internal
        view
        returns (bool)
    {
        // DEPLOYMENT:16 evidence: [uint160(target), value, uint32(selector)]
        // as Aragon Permission words ((arg << 8) | ethValue).
        uint256[] memory context = new uint256[](3);
        context[0] = uint256(uint160(actionTarget)) << 8;
        context[1] = 0; // every prescribed action sends exactly zero ETH value
        context[2] = uint256(uint32(actionSelector)) << 8;
        return IRouterAcl(acl).hasPermission(who, DAO, EXECUTE_ROLE, context);
    }

    /// @dev Builds, passes and executes a DIRECT-targeting script: R must
    /// see caller=Voting (not D) and reject; the executed flag rolls back.
    function _f10WrongCallerBallot(GaugeControllerAdmin r) internal returns (address simHolder) {
        Action[] memory direct = new Action[](1);
        // DIRECTLY targeting R (no D/agent hop): the callee sees V, not D.
        // CONF-04: the SAME action and arguments as the legitimate control
        // below (commit of the approved successor), so the witnessed
        // difference is exactly the caller chain, not the payload.
        bytes memory commitR = abi.encodeWithSelector(
            GaugeControllerAdmin.commit_transfer_ownership.selector, actor("f10 approved successor")
        );
        direct[0] = Action(address(r), commitR);
        _holdingsChecks("FORK_GOVERNANCE_WRONG_CALLER");
        fvm.expectCall(address(r), commitR); // the exact R payload IS attempted
        fvm.prank(HISTORIC_HOLDER);
        uint256 voteId = IRouterVoting(VOTING).newVote(_callsScript(direct), "router-exec wrong-caller", false, false);
        (bool open, bool execFlag,, uint64 snapshotBlock,,,,,,) = IRouterVoting(VOTING).getVote(voteId);
        require(open && !execFlag, "fresh open vote");
        require(snapshotBlock == FORK_BLOCK - 1, "snapshot");
        _castYea(voteId, HISTORIC_HOLDER);
        simHolder = actor("f10-funded-sim-holder");
        uint256 power = IRouterEscrow(CRV_VOTING_TOKEN).totalSupplyAt(snapshotBlock);
        _fundSimulatedHolder(simHolder, power * 31 / 100, FORK_TIMESTAMP - 60, FORK_BLOCK - 2);
        _castYea(voteId, simHolder);
        fvm.warp(uint256(block.timestamp) + 7 days + 2 hours);
        require(IRouterVoting(VOTING).canExecute(voteId), "FORK_GOVERNANCE_WRONG_CALLER canExecute");

        // CONF-04: enforce the exact observed cause — the inner NotDao(V)
        // propagates as a hard revert. A bare expectRevert could be
        // satisfied by any unrelated downstream failure.
        vm.expectRevert(abi.encodeWithSelector(GaugeControllerAdmin.NotDao.selector, VOTING));
        IRouterVoting(VOTING).executeVote(voteId);

        // executed flag rolled back with the whole script; nothing took effect
        (, bool executedAfter,, uint64 snapAfter,,,,,,) = IRouterVoting(VOTING).getVote(voteId);
        require(!executedAfter, "FORK_GOVERNANCE_WRONG_CALLER executed flag rolled back");
        require(snapAfter == FORK_BLOCK - 1, "vote state stable");
        assertFalse(r.isAdder(rando()), "FORK_GOVERNANCE_WRONG_CALLER no grant leaked");
        assertEq(r.pendingControllerAdmin(), address(0), "state intact");
    }

    function _f10GenuineRoute(GaugeControllerAdmin r, address simHolder) internal {
        Action[] memory good = new Action[](1);
        // CONF-04: identical action and successor as the failed direct
        // ballot; the only change is the legitimate D/Agent routing.
        good[0] = Action(
            DAO,
            _agentCalldata(
                address(r),
                abi.encodeWithSelector(
                    GaugeControllerAdmin.commit_transfer_ownership.selector, actor("f10 approved successor")
                )
            )
        );
        _bindExpectedCalls(good);
        uint256 beforeVotes = IRouterVoting(VOTING).votesLength();
        fvm.prank(HISTORIC_HOLDER);
        uint256 voteId2 = IRouterVoting(VOTING).newVote(_callsScript(good), "router-exec acl positive", false, false);
        require(voteId2 == beforeVotes, "second vote id");
        // the disclosed funded-simulation holder persists in this fork state;
        // no new funding needed for the second ballot
        _castYea(voteId2, HISTORIC_HOLDER);
        _castYea(voteId2, simHolder);
        fvm.warp(uint256(block.timestamp) + 7 days + 2 hours);
        require(IRouterVoting(VOTING).canExecute(voteId2), "positive canExecute");
        IRouterVoting(VOTING).executeVote(voteId2);
        (, bool positiveExecuted,,,,,,,,) = IRouterVoting(VOTING).getVote(voteId2);
        require(positiveExecuted, "FORK_GOVERNANCE_WRONG_CALLER positive executed readback");
        assertEq(
            r.pendingControllerAdmin(),
            actor("f10 approved successor"),
            "FORK_GOVERNANCE_WRONG_CALLER genuine route works"
        );
    }

    // ------------------------------------------------------------------
    // F11 (CONF-01) — selected Paris artifact, full lifecycle
    // ------------------------------------------------------------------

    /// @notice CONF-01: the exact SELECTED Paris deployment artifact (the
    /// default-profile build under out/) is independently bound (full
    /// runtime byte identity, getter AND embedded-literal immutables) and
    /// then LIFE-CYCLED on the real controller at the fixed pin: seating,
    /// both L lanes (paid + DAO-free) through the granted adder,
    /// independent D administration, revocation and handback — real
    /// executions, not artifact checks. Deliberately separate from the
    /// Cancun-analog rows F02–F10 (whose creation bytes differ; asserted
    /// profile separation here) and from production address/approval
    /// selection, which remains open. D impersonation here is disclosed
    /// lower-level mechanics, never a production transaction.
    function test_Fork_SelectedParisArtifactFullLifecycleRehearsal() public {
        _freshFork();
        _assertActorsDistinct();
        GaugeControllerAdmin r = _installParisArtifact();
        CurveGaugeLister l = _f11Compose(r);
        // 1. Seating on the real C via the incumbent-D two-step.
        _seatRouter(r);
        // 2. Grant, then BOTH L lanes execute through the granted adder.
        _grantLister(r, address(l), true);
        assertTrue(r.isAdder(address(l)), "FORK_PARIS_LIFECYCLE grant applied");
        address daoFreeGauge = _f11Lanes(r, l);
        _f11RevokeAndDroute(r, l, daoFreeGauge);
        _f11Handback(r, l);
    }

    /// @dev Fresh unchanged L wired to the Paris instance (DEPLOYMENT §1.2)
    /// with real adapters bound by their owners, paused.
    function _f11Compose(GaugeControllerAdmin r) internal returns (CurveGaugeLister l) {
        _assertPrimaryProvenance();
        VotiumAdapter va = new VotiumAdapter(CRVUSD, DAO, VOTIUM);
        VoteMarketAdapter vma = new VoteMarketAdapter(CRVUSD, DAO, CRM, VM_DESTINATION);
        _assertValidatorPinAtFork();
        l = new CurveGaugeLister(
            DAO,
            CRVUSD,
            address(r),
            FEEDIST,
            CurveGaugeLister.AdmissionConfig(METAREGISTRY, 8),
            CurveGaugeLister.PlatformConfig(address(va), address(vma), 10_000),
            TRUSTED_VALIDATOR
        );
        assertEq(l.controller(), address(r), "FORK_PARIS_LIFECYCLE L endpoint is the Paris instance");
        assertEq(l.owner(), DAO, "FORK_PARIS_LIFECYCLE L owner D");
        fvm.startPrank(DAO);
        va.setLister(address(l));
        vma.setLister(address(l));
        fvm.stopPrank();
        assertTrue(l.paused(), "FORK_PARIS_LIFECYCLE starts paused");
    }

    /// @dev Both lister lanes through the granted adder: DAO-free supplied
    /// weight while paused, then the conditional unpause and the real paid
    /// admission at raw zero.
    function _f11Lanes(GaugeControllerAdmin r, CurveGaugeLister l) internal returns (address daoFreeGauge) {
        require(!_isRegistered(GAUGE_LEGACY_PROBE), "legacy gauge candidate availability");
        fvm.prank(DAO);
        l.listGaugeNoEscrow(POOL_LEGACY_PROBE, GAUGE_LEGACY_PROBE, LEGACY_GAUGE_INDEX, LEGACY_HANDLER_ID, 4242);
        assertEq(_c().get_gauge_weight(GAUGE_LEGACY_PROBE), 4242, "FORK_PARIS_LIFECYCLE dao-free supplied weight");
        _assertI128Eq(
            r.gauge_types(GAUGE_LEGACY_PROBE), LEGACY_GAUGE_TYPE, "dao-free membership via Paris read-through"
        );
        daoFreeGauge = GAUGE_LEGACY_PROBE;

        _activate(l);
        _fundPayer(payer(), 1);
        _approveFee(address(l));
        fvm.prank(payer());
        l.listGauge(POOL_PRIMARY, GAUGE_PRIMARY, GAUGE_INDEX, HANDLER_ID);
        assertEq(_c().get_gauge_weight(GAUGE_PRIMARY), 0, "FORK_PARIS_LIFECYCLE paid raw zero");
        assertTrue(_isRegistered(GAUGE_PRIMARY), "FORK_PARIS_LIFECYCLE paid membership real");
    }

    /// @dev Independent D administration through the Paris router, then
    /// revocation: both L lanes die at R's real NotAdder gate while D's own
    /// route survives.
    function _f11RevokeAndDroute(GaugeControllerAdmin r, CurveGaugeLister l, address daoFreeGauge) internal {
        address indep = _synthGauge("f11 independent D add");
        fvm.prank(DAO);
        r.add_gauge(indep, int128(1), uint256(31337));
        assertEq(_c().get_gauge_weight(indep), 31337, "FORK_PARIS_LIFECYCLE independent D weight");
        int128 typesBefore = _c().n_gauge_types();
        (bool atOk,) = _callFromAddr(
            DAO,
            address(r),
            abi.encodeWithSelector(
                GaugeControllerAdmin.execute.selector, abi.encodeWithSignature("add_type(string)", "f11-type")
            )
        );
        require(atOk && _c().n_gauge_types() == typesBefore + 1, "FORK_PARIS_LIFECYCLE D add_type");
        (bool cwOk,) = _callFromAddr(
            DAO,
            address(r),
            abi.encodeWithSelector(
                GaugeControllerAdmin.execute.selector,
                abi.encodeWithSignature("change_gauge_weight(address,uint256)", indep, uint256(88))
            )
        );
        require(cwOk && _c().get_gauge_weight(indep) == 88, "FORK_PARIS_LIFECYCLE D change_gauge_weight");

        _grantLister(r, address(l), false);
        assertFalse(r.isAdder(address(l)), "FORK_PARIS_LIFECYCLE revoked");
        // Revocation semantics for a fresh real candidate (exact NotAdder(L)
        // on both lanes) are proven in F05's dedicated subfixtures and
        // offline O20/I03; the frozen pin holds exactly two registry-verified
        // unregistered candidates and both positive lanes above consumed
        // them, so re-attempting here would test L's AlreadyListed/occupancy
        // gates, not R's grant gate. Here: the flag flips and D's own route
        // survives revocation.
        address postRevoke = _synthGauge("f11 post revoke");
        fvm.prank(DAO);
        r.add_gauge(postRevoke, int128(0), uint256(7));
        assertTrue(_isRegistered(postRevoke), "FORK_PARIS_LIFECYCLE D route survives revoke");
    }

    /// @dev Handback through the Paris instance with real-C frames; retired
    /// for every mutation, reads survive, direct D administration restored.
    function _f11Handback(GaugeControllerAdmin r, CurveGaugeLister l) internal {
        l;
        rvf.recordLogs();
        fvm.prank(DAO);
        r.commit_transfer_ownership(DAO);
        fvm.prank(DAO);
        r.apply_transfer_ownership();
        RouterForkVm.Log[] memory hb = rvf.getRecordedLogs();
        assertEq(_c().admin(), DAO, "FORK_PARIS_LIFECYCLE handback restored D");
        assertTrue(r.retired(), "FORK_PARIS_LIFECYCLE retired");
        assertEq(r.pendingControllerAdmin(), address(0), "FORK_PARIS_LIFECYCLE pending cleared");
        require(
            _logCount(hb, address(r), keccak256("ControllerTransferCommitted(address)")) == 1
                && _logCount(hb, address(r), keccak256("ControllerTransferApplied(address)")) == 1
                && _logCount(hb, CONTROLLER, T_COMMIT_OWNERSHIP) == 1,
            "FORK_PARIS_LIFECYCLE handback event frames"
        );

        (bool inert,) =
            _callFromAddr(DAO, address(r), abi.encodeWithSelector(GaugeControllerAdmin.grant.selector, rando(), true));
        require(!inert, "FORK_PARIS_LIFECYCLE retired R mutating");
        _assertI128Eq(r.n_gauge_types(), _c().n_gauge_types(), "FORK_PARIS_LIFECYCLE retired reads survive");
        // CONF-01 residual (review/ROUTERCONF2.md:90-98): the expressly
        // required selected-byte repetition — the restored direct D lane is
        // exercised with raw add_type, change_type_weight and
        // change_gauge_weight INSIDE this selected Paris rehearsal with
        // exact readbacks (F07's Cancun-analog lane cannot supply it,
        // review/ROUTERCONF2.md:93-94). The commit(C) lane this handback
        // drives through the selected instance uses the review's required
        // RAW values (review/ROUTERCONF2.md:194,196): target
        // 270125199945504599111523101509100263416079599291 == uint160(C)
        // (whose 20-byte literal is bound into the selected runtime by
        // _installParisArtifact) and selector 1799625280 == uint32
        // commit_transfer_ownership(address), unshifted.
        require(
            uint256(uint32(IControllerVenue.commit_transfer_ownership.selector)) == 1799625280
                && uint256(uint32(GaugeControllerAdmin.commit_transfer_ownership.selector)) == 1799625280,
            "FORK_PARIS_LIFECYCLE review/ROUTERCONF2:196 required selector"
        );
        address postHandback = _synthGauge("f11 post handback direct");
        fvm.prank(DAO);
        _c().add_gauge(postHandback, int128(0), uint256(5));
        assertEq(_c().get_gauge_weight(postHandback), 5, "FORK_PARIS_LIFECYCLE direct D restored");

        int128 selectedTypesBefore = _c().n_gauge_types();
        fvm.prank(DAO);
        (bool selAtOk,) = CONTROLLER.call(abi.encodeWithSignature("add_type(string)", "f11-selected-restored-type"));
        require(selAtOk, "FORK_PARIS_LIFECYCLE post-handback raw add_type");
        _assertI128Eq(
            _c().n_gauge_types(), selectedTypesBefore + 1, "post-handback add_type advanced the canonical bound"
        );

        fvm.prank(DAO);
        (bool selTwOk,) = CONTROLLER.call(
            abi.encodeWithSignature("change_type_weight(int128,uint256)", selectedTypesBefore, uint256(4242))
        );
        require(selTwOk, "FORK_PARIS_LIFECYCLE post-handback raw change_type_weight");
        assertEq(r_type_weight(selectedTypesBefore), 4242, "post-handback type weight readback exact");

        fvm.prank(DAO);
        _c().change_gauge_weight(postHandback, uint256(77));
        assertEq(_c().get_gauge_weight(postHandback), 77, "FORK_PARIS_LIFECYCLE post-handback raw change_gauge_weight");

        // the selected Paris runtime continues to serve the read-through
        // against the freshly mutated state
        _assertI128Eq(r.n_gauge_types(), selectedTypesBefore + 1, "selected Paris runtime reads added type");
        _assertI128Eq(r.gauge_types(postHandback), int128(0), "selected Paris runtime reads membership");
    }

    /// @dev Deploy the exact selected Paris artifact at the pin and bind it
    /// independently: sizes decoded with metadata intact, full runtime byte
    /// identity against the artifact, getter immutables AND embedded C/D
    /// literals. The Cancun analog under out-fork must be a different
    /// artifact, so a profile substitution cannot silently pass (CONF-01).
    function _installParisArtifact() internal returns (GaugeControllerAdmin) {
        string memory art = rvf.readFile("out/GaugeControllerAdmin.sol/GaugeControllerAdmin.json");
        bytes memory creation = _hexToBytes(rvf.parseJsonString(art, "$.bytecode.object"));
        bytes memory expectedRuntime = _hexToBytes(rvf.parseJsonString(art, "$.deployedBytecode.object"));
        // The artifact's deployedBytecode carries the immutables as zero
        // placeholders (they are patched by the creation code); the binding
        // below independently proves the PATCHED runtime equals the deployed
        // code of the same artifact deployed through forge's own
        // deployCode loader — two independent deployment paths, one byte
        // identity — plus getter readbacks and embedded-literal scans.
        address viaCheat =
            rvf.deployCode("out/GaugeControllerAdmin.sol/GaugeControllerAdmin.json", abi.encode(CONTROLLER, DAO));
        require(viaCheat != address(0), "FORK_PARIS_LIFECYCLE deployCode reference instance");
        bytes memory initcode = abi.encodePacked(creation, abi.encode(CONTROLLER, DAO));
        require(initcode.length == 5396, "FORK_PARIS_LIFECYCLE selected initcode with two address arguments");
        require(expectedRuntime.length + 64 <= initcode.length, "artifact runtime shorter than initcode");
        uint256 senderBalBefore = address(this).balance;
        address parisR;
        assembly ("memory-safe") {
            parisR := create(0, add(initcode, 0x20), mload(initcode))
        }
        require(address(this).balance == senderBalBefore, "FORK_PARIS_LIFECYCLE no value forwarded by construction");
        require(parisR != address(0), "FORK_PARIS_LIFECYCLE Paris initcode deploy");
        require(keccak256(parisR.code) == keccak256(viaCheat.code), "FORK_PARIS_LIFECYCLE full runtime byte identity");
        require(parisR.code.length == 4786, "FORK_PARIS_LIFECYCLE selected Paris runtime size");
        // The fork-profile (Cancun) analog must be a DIFFERENT artifact: a
        // silent profile substitution cannot pass this rehearsal.
        GaugeControllerAdmin cancunAnalog = _router();
        require(address(cancunAnalog).code.length == 4683, "FORK_PARIS_LIFECYCLE Cancun analog size");
        require(
            keccak256(address(cancunAnalog).code) != keccak256(parisR.code), "FORK_PARIS_LIFECYCLE profile separation"
        );
        require(GaugeControllerAdmin(parisR).controller() == CONTROLLER, "FORK_PARIS_LIFECYCLE immutable C getter");
        require(GaugeControllerAdmin(parisR).dao() == DAO, "FORK_PARIS_LIFECYCLE immutable D getter");
        require(_containsBytes(parisR.code, bytes20(CONTROLLER)), "FORK_PARIS_LIFECYCLE C literal embedded");
        // the literal the byte scan above matched IS the review's required
        // unshifted commit(C) target (review/ROUTERCONF2.md:194)
        require(
            uint256(uint160(CONTROLLER)) == 270125199945504599111523101509100263416079599291,
            "FORK_PARIS_LIFECYCLE review/ROUTERCONF2:194 required target"
        );
        require(_containsBytes(parisR.code, bytes20(DAO)), "FORK_PARIS_LIFECYCLE D literal embedded");
        require(!(_containsBytes(expectedRuntime, bytes20(CONTROLLER))), "artifact keeps immutable placeholders");
        return GaugeControllerAdmin(parisR);
    }

    function _containsBytes(bytes memory haystack, bytes20 needle) internal pure returns (bool) {
        for (uint256 i = 0; i + 20 <= haystack.length; ++i) {
            bool hit = true;
            for (uint256 j = 0; j < 20; ++j) {
                if (haystack[i + j] != needle[j]) {
                    hit = false;
                    break;
                }
            }
            if (hit) return true;
        }
        return false;
    }

    // ------------------------------------------------------------------
    // F12 (CONF-02) — interrupted-installation rollback and recovery
    // ------------------------------------------------------------------

    /// @notice CONF-02 (DEPLOYMENT:15 with §4 rows "Only S1 committed",
    /// "Atomic S1–S3 fails" and nominee replacement), rehearsed through the
    /// REAL Voting→CallsScript→Agent transport for every grouped step so
    /// atomicity is genuine, disclosed lower-level mechanics elsewhere:
    /// (1) an atomic S1+S2+S3 ballot whose S3 grant is invalid reverts the
    /// whole install with no trace; (2) with S1 committed in an EARLIER
    /// successful ballot, a later atomic S2+S3 group that fails at S3
    /// leaves the S1 commitment surviving — the exact state the prescribed
    /// cleanup C.commit_transfer_ownership(D) resolves (admin/future both
    /// read back D; pending R is never allowed to apply); (3) recovery
    /// proceeds with nominee replacement and a corrected install to a
    /// working seated composition whose paid lane admits.
    function test_Fork_InterruptedSeatingRollbackAndRecovery() public {
        _freshFork();
        _assertActorsDistinct();
        RouterTrio memory t = _deployRouterTrio(10_000);
        GaugeControllerAdmin r = t.router;
        _f12AtomicAllOrNothing(r);
        _f12InterruptedCleanup(r);
        _f12Recovery(t, r);
    }

    /// @dev Phase (1): atomic S1+S2+S3 with an invalid S3 grant reverts the
    /// whole install — no trace, vote not executed.
    function _f12AtomicAllOrNothing(GaugeControllerAdmin r) internal {
        bytes memory cCommitR = abi.encodeWithSelector(_c().commit_transfer_ownership.selector, address(r));
        bytes memory cApply = abi.encodeWithSelector(_c().apply_transfer_ownership.selector);
        bytes memory grantBad = abi.encodeWithSelector(GaugeControllerAdmin.grant.selector, address(r), true);
        bytes memory invalidAdderCause = abi.encodeWithSelector(GaugeControllerAdmin.InvalidAdder.selector, address(r));
        Action[] memory atomicFail = new Action[](3);
        atomicFail[0] = Action(DAO, _agentCalldata(CONTROLLER, cCommitR));
        atomicFail[1] = Action(DAO, _agentCalldata(CONTROLLER, cApply));
        atomicFail[2] = Action(DAO, _agentCalldata(address(r), grantBad));
        uint256 failVoteA = _runFailingGovernanceVote(atomicFail, "f12 atomic-fail", invalidAdderCause);
        assertEq(_c().admin(), DAO, "FORK_INTERRUPTED atomic failure left admin D");
        assertEq(_c().future_admin(), DAO, "FORK_INTERRUPTED atomic failure left future D");
        assertFalse(r.isAdder(address(r)), "FORK_INTERRUPTED no grant persisted");
        assertTrue(!r.retired() && r.pendingControllerAdmin() == address(0), "FORK_INTERRUPTED R untouched");
        (, bool execAfter,,,,,,,,) = IRouterVoting(VOTING).getVote(failVoteA);
        require(!execAfter, "FORK_INTERRUPTED failed ballot not executed");
    }

    /// @dev Phase (2): S1 alone in an earlier successful ballot; pending R
    /// cannot self-apply; the later atomic S2+S3 group fails at S3 so its
    /// own apply rolls back while the S1 commitment survives; the prescribed
    /// cleanup D→C.commit_transfer_ownership(D) restores admin=D/future=D
    /// and the never-seated R stays closed at its incumbent guard.
    function _f12InterruptedCleanup(GaugeControllerAdmin r) internal {
        bytes memory cCommitR = abi.encodeWithSelector(_c().commit_transfer_ownership.selector, address(r));
        bytes memory cApply = abi.encodeWithSelector(_c().apply_transfer_ownership.selector);
        bytes memory grantBad = abi.encodeWithSelector(GaugeControllerAdmin.grant.selector, address(r), true);
        bytes memory invalidAdderCause = abi.encodeWithSelector(GaugeControllerAdmin.InvalidAdder.selector, address(r));

        Action[] memory s1Only = new Action[](1);
        s1Only[0] = Action(DAO, _agentCalldata(CONTROLLER, cCommitR));
        _runGovernanceVote(s1Only, "f12 s1-only", 2);
        assertEq(_c().admin(), DAO, "FORK_INTERRUPTED S1-only admin still D");
        assertEq(_c().future_admin(), address(r), "FORK_INTERRUPTED S1-only future R");
        (bool selfApply,) = _callFromAddr(address(r), CONTROLLER, cApply);
        require(!selfApply, "pending R self-applied");

        Action[] memory groupFail = new Action[](2);
        groupFail[0] = Action(DAO, _agentCalldata(CONTROLLER, cApply));
        groupFail[1] = Action(DAO, _agentCalldata(address(r), grantBad));
        _runFailingGovernanceVote(groupFail, "f12 s23-fail", invalidAdderCause);
        assertEq(_c().admin(), DAO, "FORK_INTERRUPTED group failure rolled back its own apply");
        assertEq(_c().future_admin(), address(r), "FORK_INTERRUPTED earlier S1 commit survived");

        fvm.prank(DAO);
        _c().commit_transfer_ownership(DAO);
        assertEq(_c().admin(), DAO, "FORK_INTERRUPTED cleanup admin D");
        assertEq(_c().future_admin(), DAO, "FORK_INTERRUPTED cleanup future D");
        (bool inertAdd, bytes memory inertRet) = _callFromAddr(
            DAO,
            address(r),
            abi.encodeWithSelector(
                GaugeControllerAdmin.add_gauge.selector, _synthGauge("f12 inert"), int128(0), uint256(0)
            )
        );
        require(
            !inertAdd
                && keccak256(inertRet)
                    == keccak256(_routerErr(GaugeControllerAdmin.NotControllerAdmin.selector, abi.encode(DAO))),
            "FORK_INTERRUPTED never-seated R mutated"
        );
    }

    /// @dev Phase (3): recovery — nominee replacement before apply, corrected
    /// atomic S2+S3 ballot to a seated composition, a real paid admission,
    /// and the §4 handback route (revoke then commit/apply to D).
    function _f12Recovery(RouterTrio memory t, GaugeControllerAdmin r) internal {
        fvm.prank(DAO);
        _c().commit_transfer_ownership(address(r));
        address altNominee = actor("f12 superseded nominee");
        fvm.prank(DAO);
        _c().commit_transfer_ownership(altNominee);
        assertEq(_c().future_admin(), altNominee, "FORK_INTERRUPTED replacement follows latest commit");
        fvm.prank(DAO);
        _c().commit_transfer_ownership(address(r));

        Action[] memory recover = new Action[](2);
        recover[0] =
            Action(DAO, _agentCalldata(CONTROLLER, abi.encodeWithSelector(_c().apply_transfer_ownership.selector)));
        recover[1] = Action(
            DAO,
            _agentCalldata(
                address(r), abi.encodeWithSelector(GaugeControllerAdmin.grant.selector, address(t.lister), true)
            )
        );
        _bindExpectedCalls(recover);
        _runGovernanceVote(recover, "f12 recover", 2);
        assertEq(_c().admin(), address(r), "FORK_INTERRUPTED recovered install seated R");
        assertTrue(r.isAdder(address(t.lister)), "FORK_INTERRUPTED recovered grant applied");
        assertFalse(r.retired(), "recovered R active");

        _fundPayer(payer(), 1);
        _approveFee(address(t.lister));
        _activate(t.lister);
        fvm.prank(payer());
        t.lister.listGauge(POOL_PRIMARY, GAUGE_PRIMARY, GAUGE_INDEX, HANDLER_ID);
        assertTrue(_isRegistered(GAUGE_PRIMARY), "FORK_INTERRUPTED recovered composition admits");
        assertEq(_c().get_gauge_weight(GAUGE_PRIMARY), 0, "recovered paid raw zero");

        _grantLister(r, address(t.lister), false);
        fvm.prank(DAO);
        r.commit_transfer_ownership(DAO);
        fvm.prank(DAO);
        r.apply_transfer_ownership();
        assertEq(_c().admin(), DAO, "FORK_INTERRUPTED final handback restored D");
        assertTrue(r.retired(), "FORK_INTERRUPTED final handback retired R");
    }

    /// @dev Real ballot whose executeVote MUST revert with the exact bubbled
    /// inner failure (all-or-nothing script semantics; DEPLOYMENT:39 "A
    /// downstream revert rolls back the whole script"). Returns the vote id;
    /// the executed flag stays false by assertion at the caller.
    function _runFailingGovernanceVote(Action[] memory actions, string memory tag, bytes memory wantRevert)
        internal
        returns (uint256 voteId)
    {
        _holdingsChecks(tag);
        bytes memory script = _callsScript(actions);
        uint256 votesBefore = IRouterVoting(VOTING).votesLength();
        fvm.prank(HISTORIC_HOLDER);
        voteId = IRouterVoting(VOTING).newVote(script, tag, false, false);
        require(voteId == votesBefore, "failing vote id");
        (,, uint64 startDate, uint64 snapshotBlock,,,,,,) = IRouterVoting(VOTING).getVote(voteId);
        require(snapshotBlock == FORK_BLOCK - 1, "snapshot below head");
        _castYea(voteId, HISTORIC_HOLDER);
        address simHolder = actor(string.concat(tag, "-funded-sim-holder"));
        uint256 power = IRouterEscrow(CRV_VOTING_TOKEN).totalSupplyAt(snapshotBlock);
        uint256 needed = power * 31 / 100;
        uint256 realYea = IRouterEscrow(CRV_VOTING_TOKEN).balanceOfAt(HISTORIC_HOLDER, snapshotBlock);
        uint256 simBias = needed > realYea ? needed - realYea + 1 : 1;
        _fundSimulatedHolder(simHolder, simBias, FORK_TIMESTAMP - 60, FORK_BLOCK - 2);
        _castYea(voteId, simHolder);
        fvm.warp(uint256(startDate) + 7 days + 1 hours);
        require(IRouterVoting(VOTING).canExecute(voteId), "failing ballot canExecute");
        // enforce the exact bubbled cause, not any revert
        vm.expectRevert(wantRevert);
        IRouterVoting(VOTING).executeVote(voteId);
    }
}
