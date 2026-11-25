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
}

interface IRouterAgent {
    function kernel() external view returns (address);
}

interface IRouterKernel {
    function acl() external view returns (address);
}

interface IRouterAcl {
    function hasPermission(address who, address where, bytes32 role) external view returns (bool);
}

interface IRouterScriptRegistry {
    function getScriptExecutor(bytes calldata script) external view returns (address);
}

/// @title ForkGaugeControllerAdminSpec
/// @notice Real-controller + real-governance witness matrix F01–F10 for
/// GaugeControllerAdmin (plans/ROUTERPLAN-WITNESSES.json). Abstract: the
/// concrete runner is fork/GaugeControllerAdmin.t.sol under the fork profile
/// only. Seating, handback, reseat, additions and governance votes are LOCAL
/// FORK SIMULATION at the pinned header — never production transactions, no
/// signing, no broadcast. D impersonation in F02–F08 is lower-level
/// mechanics evidence, explicitly disclosed; F09/F10 use the real
/// Voting→ScriptRegistry→CallsScript→Agent transport WITHOUT impersonating
/// D/V/R/L — a disclosed funded-holder simulation (declared only to close
/// quorum) and clock warp complete the ballot, and no vote tallies, ACL
/// roles or controller admin slots are edited.
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

    function _callFromAddr(address from, address target, bytes memory data) internal returns (bool, bytes memory) {
        fvm.prank(from);
        (bool ok, bytes memory ret) = target.call(data);
        return (ok, ret);
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
        GaugeControllerAdmin r = _router();
        _seatRouter(r);

        _f06AddsAndTypes(r);
        _f06TypesWeights(r);
        _f06Negatives(r);
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

    function _f06Negatives(GaugeControllerAdmin r) internal {
        // Negatives: direct D raw-admin calls fail while R is incumbent
        fvm.prank(DAO);
        (bool rawAdd, bytes memory rawAddRet) = CONTROLLER.call(
            abi.encodeCall(_c().add_gauge, (_synthGauge("router-exec f06 denied"), int128(0), uint256(0)))
        );
        require(!rawAdd && rawAddRet.length == 0, "FORK_FULL_RAW_ADMIN direct D must revert empty");

        // outsider cannot invoke R grant/execute/ownership
        (bool n1, bytes memory n1r) = _callFromAddr(
            rando(), address(r), abi.encodeWithSelector(GaugeControllerAdmin.grant.selector, rando(), true)
        );
        require(
            !n1 && keccak256(n1r) == keccak256(_routerErr(GaugeControllerAdmin.NotDao.selector, abi.encode(rando()))),
            "FORK_FULL_RAW_ADMIN outsider grant"
        );
        (bool n2,) =
            _callFromAddr(rando(), address(r), abi.encodeWithSelector(GaugeControllerAdmin.execute.selector, hex"2f50"));
        (bool n3,) = _callFromAddr(
            rando(),
            address(r),
            abi.encodeWithSelector(GaugeControllerAdmin.commit_transfer_ownership.selector, actor("succ"))
        );
        (bool n4,) = _callFromAddr(
            rando(), address(r), abi.encodeWithSelector(GaugeControllerAdmin.apply_transfer_ownership.selector)
        );
        require(!n2 && !n3 && !n4, "FORK_FULL_RAW_ADMIN outsider ownership/execute");

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
        uint256 nBefore = uint256(int256(_c().n_gauges()));

        // SIMULATION ONLY rehearsal before any production apply: revoke L; a
        // legitimate recommit replaces the nominee and apply follows the NEW
        // nominee (ruling-corrected cell).
        _grantLister(r, address(t.lister), false);
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

        // direct D raw add/type/weight works again
        fvm.prank(DAO);
        _c().add_gauge(_synthGauge("f07 direct"), int128(0), uint256(5));
        assertTrue(_isRegistered(_synthGauge("f07 direct")), "FORK_HANDBACK_DIRECT_D restored add");
        assertEq(_c().get_gauge_weight(_synthGauge("f07 direct")), 5, "direct weight exact");

        // membership/settlement entitlement unchanged through the transition
        assertEq(uint256(int256(_c().n_gauges())), nBefore + 1, "only the direct add advanced");
        _assertI128Eq(_c().gauge_types(GAUGE_PRIMARY), DERIVED_TYPE, "existing membership kept");
        assertEq(_c().get_gauge_weight(GAUGE_PRIMARY), 0, "zero raw weight entitlement kept");

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
    /// script through the real registry/executor/Agent transport.
    function _runGovernanceVote(Action[] memory actions, string memory tag, uint256 voterCount) internal {
        _holdingsChecks(tag);
        bytes memory script = _callsScript(actions);
        uint256 votesBefore = IRouterVoting(VOTING).votesLength();

        rvf.recordLogs();
        fvm.prank(HISTORIC_HOLDER);
        uint256 voteId = IRouterVoting(VOTING).newVote(script, tag, false, false);
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
        RouterForkVm.Log[] memory logs = rvf.getRecordedLogs();
        require(_logCount(logs, VOTING, T_EXECUTE_VOTE) == 1, "FORK_REAL_GOVERNANCE_TRANSPORT ExecuteVote");
        require(_logCount(logs, VOTING, T_CAST_VOTE) == voterCount, "real casts observed");
        require(_logCount(logs, VOTING, T_START_VOTE) == 1, "StartVote observed");
    }

    function test_Fork_RealGovernanceInstallGrantAndHandback() public {
        _freshFork();
        _assertActorsDistinct();

        // transport bindings re-read live (fail closed, no guessed selectors)
        address kernel = IRouterAgent(DAO).kernel();
        require(kernel != address(0), "FORK_REAL_GOVERNANCE_TRANSPORT kernel");
        require(
            IRouterScriptRegistry(SCRIPT_REGISTRY).getScriptExecutor(abi.encodePacked(bytes4(0x00000001)))
                == CALLS_EXECUTOR,
            "FORK_REAL_GOVERNANCE_TRANSPORT executor bound"
        );

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
        _runGovernanceVote(install, "router-exec install", 2);

        assertEq(_c().admin(), address(r), "FORK_REAL_GOVERNANCE_TRANSPORT seated by genuine vote");
        assertEq(_c().future_admin(), address(r), "future R kept (stale, real behaviour)");
        assertTrue(r.isAdder(address(t.lister)), "FORK_REAL_GOVERNANCE_TRANSPORT L granted by genuine vote");
        assertEq(r.pendingControllerAdmin(), address(0), "no local pending after install");
        assertFalse(r.retired(), "active after install");
        require(!r.retired() && _c().admin() == address(r), "readbacks bound together");

        // ---- separate genuine vote completes the handback through R
        Action[] memory handback = new Action[](2);
        handback[0] = Action(
            DAO,
            _agentCalldata(
                address(r), abi.encodeWithSelector(GaugeControllerAdmin.commit_transfer_ownership.selector, DAO)
            )
        );
        handback[1] = Action(
            DAO,
            _agentCalldata(address(r), abi.encodeWithSelector(GaugeControllerAdmin.apply_transfer_ownership.selector))
        );
        _runGovernanceVote(handback, "router-exec handback", 2);

        assertEq(_c().admin(), DAO, "FORK_REAL_GOVERNANCE_TRANSPORT handback restored D by genuine vote");
        assertTrue(r.retired(), "FORK_REAL_GOVERNANCE_TRANSPORT router retired");
        assertEq(r.pendingControllerAdmin(), address(0), "pending cleared by genuine apply");
    }

    function test_Fork_GovernanceWrongCallerAndAclNegative() public {
        _freshFork();
        _assertActorsDistinct();
        GaugeControllerAdmin r = _router();
        _seatRouter(r); // mechanics seating so the wrong-caller negative
        // targets a genuinely seated router

        // ACL precondition reads with the ACTUAL target/value/selector
        // context (not role-name inference):
        _f10AclReads();

        // genuinely passed script targeting R DIRECTLY (Voting context)
        address simHolder = _f10WrongCallerBallot(r);

        // positive control: SAME real route, legitimately addressed via D
        _f10GenuineRoute(r, simHolder);

        // outsider D.execute fails the genuine ACL
        (bool x1,) = _callFromAddr(
            rando(), DAO, abi.encodePacked(AGENT_EXECUTE_SELECTOR, abi.encode(CONTROLLER, uint256(0), hex""))
        );
        require(!x1, "FORK_GOVERNANCE_WRONG_CALLER outsider agent call");
    }

    function _f10AclReads() internal view {
        address kernel = IRouterAgent(DAO).kernel();
        require(kernel != address(0), "kernel");
        address acl = IRouterKernel(kernel).acl();
        require(
            IRouterAcl(acl).hasPermission(address(type(uint160).max), VOTING, keccak256("CREATE_VOTES_ROLE")),
            "FORK_GOVERNANCE_WRONG_CALLER create role open"
        );
        require(
            IRouterAcl(acl).hasPermission(VOTING, DAO, keccak256("EXECUTE_ROLE")),
            "FORK_GOVERNANCE_WRONG_CALLER agent execute role (Voting actor)"
        );
    }

    /// @dev Builds, passes and executes a DIRECT-targeting script: R must
    /// see caller=Voting (not D) and reject; the executed flag rolls back.
    function _f10WrongCallerBallot(GaugeControllerAdmin r) internal returns (address simHolder) {
        Action[] memory direct = new Action[](1);
        // DIRECTLY targeting R (no D/agent hop): the callee sees V, not D
        direct[0] = Action(address(r), abi.encodeWithSelector(GaugeControllerAdmin.grant.selector, rando(), true));
        _holdingsChecks("FORK_GOVERNANCE_WRONG_CALLER");
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

        vm.expectRevert(); // the inner NotDao(V) propagates as a hard revert
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
        good[0] = Action(
            DAO,
            _agentCalldata(
                address(r),
                abi.encodeWithSelector(
                    GaugeControllerAdmin.commit_transfer_ownership.selector, actor("f10 approved successor")
                )
            )
        );
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
        assertEq(
            r.pendingControllerAdmin(),
            actor("f10 approved successor"),
            "FORK_GOVERNANCE_WRONG_CALLER genuine route works"
        );
    }
}
