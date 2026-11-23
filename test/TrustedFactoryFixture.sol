// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {TestBase, Vm} from "./TestBase.sol";
import {CurveGaugeLister} from "../contracts/CurveGaugeLister.sol";
import {MockERC20} from "../contracts/mocks/MockERC20.sol";
import {MockPool} from "../contracts/mocks/MockPool.sol";
import {MockGauge} from "../contracts/mocks/MockGauge.sol";
import {MockCurveRegistry} from "../contracts/mocks/MockCurveRegistry.sol";
import {MockListingController} from "../contracts/mocks/MockListingController.sol";
import {MockFeeDistributor} from "../contracts/mocks/MockFeeDistributor.sol";
import {MockIncentivePlatform} from "../contracts/mocks/MockIncentivePlatform.sol";
import {
    AlwaysTrueTrustedValidator,
    ConfigurableTrustedValidator,
    GaugeValidationModuleModel,
    TrustedFactoryModel,
    FactoryClaimGauge,
    LegacyLpToken,
    PoisonAddController
} from "./mocks/TrustedFactoryMocks.sol";

/// @dev Generic cheatcode addition needed by the fault-injection cells
/// (disclosed runtime-code removal). Same dispatcher, no forge-std.
interface VmEtch {
    function etch(address target, bytes calldata newRuntime) external;
}

/// @title TrustedFactoryFixture
/// @notice No-bounty offline world scaffolding for the eight trusted-factory
/// trust identities (plans/V1ALIGN-PLAN.md §4; V1ALIGN-WITNESSES.md §2):
/// generic assertion/fixture helpers transplanted from the retired V2 kit
/// onto the amended V1 core with the original V1 Listing/event law. Contains
/// NO test methods and NO product-law assertions — the identities live in
/// test/TrustedFactory.t.sol, which is the only concrete suite here.
/// @dev DISCLOSURES:
///  * The validator/module/factory fixtures in mocks/TrustedFactoryMocks.sol
///    are a LOCAL POLICY MODEL of the pinned GaugeValidator/
///    GaugeValidationModuleV1 reciprocal-proof semantics — a disclosed
///    fixture, NOT the deployed validator. Live factory policy semantics are
///    certified by the two fork identities (fork/TrustedFactory.t.sol), not
///    by these mocks alone.
///  * Fault injection (revert/short/oversized/noncanonical returns, code
///    removal, poisoned effects) is disclosed fixture control, never a
///    mock-only happy path.
abstract contract TrustedFactoryFixture is TestBase {
    VmEtch internal constant vmx = VmEtch(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    uint256 internal constant FEE_AMOUNT = 10_000e18;
    uint256 internal constant QUARTER_AMOUNT = 2_500e18;
    uint256 internal constant WEEK = 604800;
    /// @notice Thursday 2026-11-12 00:00 UTC (baseline fixture anchor).
    uint256 internal constant T0 = 1794441600;

    bytes32 internal constant T_GAUGE_LISTED =
        keccak256("GaugeListed(address,address,address,int128,uint256,uint256,bool)");
    bytes32 internal constant T_QUARTER_RELEASED = keccak256("QuarterReleased(address,uint256,uint256,uint256)");
    bytes32 internal constant T_ESCROW_CONFISCATED = keccak256("EscrowConfiscated(address,address,uint256,uint256)");
    bytes32 internal constant T_FEE_CHECKPOINT_RESULT = keccak256("FeeCheckpointResult(bool)");

    // ------------------------------- roles --------------------------------
    address internal daoOwner;
    address internal controllerDao;
    address internal fdAdmin;
    address internal payer;
    address internal stranger;

    // ------------------------------ systems -------------------------------
    MockERC20 internal crvUSD;
    MockFeeDistributor internal fd;
    MockCurveRegistry internal registry;
    MockListingController internal controller;
    MockIncentivePlatform internal votium;
    MockIncentivePlatform internal voteMarket;

    /// @dev Per-suite pool/gauge counter keeps registry keys unique.
    uint256 internal _nextSlot = 1;

    struct Candidate {
        address pool;
        address gauge;
        address lp;
        address factory;
        uint256 slot;
    }

    struct World {
        CurveGaugeLister core_;
        MockListingController ctl;
        MockIncentivePlatform pv;
        MockIncentivePlatform pm;
    }

    struct Receipt {
        uint256 amount;
        uint256 executionEpoch;
        bytes32 receipt;
    }

    /// @dev The complete observable snapshot surface (V1ALIGN-WITNESSES.md §2
    /// snapshot port rule): the whole public V1 Listing, totalEscrow, ACTOR
    /// balance/allowance toward the core, core/FD/venue balances,
    /// core-to-venue allowances, controller membership/type/weight/count and
    /// the venue receipt state touched by the fixture. Compared to PRE-STATE,
    /// never only to zero. Bounty hook fields are dropped as authorized; no
    /// surviving custody field is.
    struct Snap {
        address pool;
        address lpToken;
        address payerAddr;
        address admissionRegistry;
        int128 gaugeType;
        uint256 listingEpoch;
        uint8 status;
        uint8 epochsReleased;
        uint256 deposited;
        uint256 released;
        uint256 remaining;
        uint256 confiscated;
        address votium;
        address voteMarket;
        uint16 votiumBps;
        uint256 totalEscrow;
        uint256 balActor;
        uint256 balCore;
        uint256 balFd;
        uint256 balVotium;
        uint256 balVoteMarket;
        uint256 allowActorCore;
        uint256 allowCoreVotium;
        uint256 allowCoreVm;
        bool ctlMember;
        int128 ctlType;
        uint256 ctlWeight;
        uint256 ctlTimeWeight;
        int128 ctlNTypes;
        uint256 ctlAdds;
        uint256 pvDeposits;
        uint256 pmDeposits;
        Receipt pvR1;
        Receipt pvR2;
        Receipt pmR1;
        Receipt pmR2;
    }

    // ---------------------------------------------------------------
    // world construction (no-bounty V1 wiring)
    // ---------------------------------------------------------------

    function setupTrustedWorld() internal {
        // The amended V1 constructor requires chain 1 (WrongChain FIRST,
        // V1ALIGN §2.1); forge's offline default is 1 today but pin it
        // explicitly so the fixtures never depend on a profile default.
        vm.chainId(1);
        daoOwner = actor("daoMultisig");
        controllerDao = actor("controllerDao");
        fdAdmin = actor("fdAdmin");
        payer = actor("feePayer");
        stranger = actor("stranger");

        vm.warp(T0);

        crvUSD = new MockERC20(18);
        fd = new MockFeeDistributor(address(crvUSD), fdAdmin, T0);
        registry = new MockCurveRegistry();
        controller = new MockListingController(controllerDao, int128(2));
        votium = new MockIncentivePlatform(address(crvUSD));
        voteMarket = new MockIncentivePlatform(address(crvUSD));
    }

    /// @notice Deploy the amended V1 core against explicit dependency
    /// addresses with a caller-supplied validator. NO seating, NO binding and
    /// NO unpause (constructor-negative cells exercise the wiring order
    /// deliberately). The validator is the SEVENTH argument; there is no
    /// bounty argument.
    function _deployCore(address controller_, address votium_, address voteMarket_, address validator_)
        internal
        returns (CurveGaugeLister core_)
    {
        core_ = new CurveGaugeLister(
            daoOwner,
            address(crvUSD),
            controller_,
            address(fd),
            CurveGaugeLister.AdmissionConfig(address(registry), 8),
            CurveGaugeLister.PlatformConfig(votium_, voteMarket_, 5000),
            validator_
        );
    }

    /// @notice Full honest wiring for a fresh core: seat the controller (via
    /// its DAO), bind both platform mocks, then the owner unpauses after the
    /// bindings (V1ALIGN §1.3 readiness-backstop discipline).
    function _bindAndUnpause(CurveGaugeLister core_, MockListingController ctl, address votium_, address voteMarket_)
        internal
    {
        vm.prank(controllerDao);
        ctl.setLister(address(core_));
        MockIncentivePlatform(votium_).setLister(address(core_));
        MockIncentivePlatform(voteMarket_).setLister(address(core_));
        vm.prank(daoOwner);
        core_.setPaused(false);
        vm.startPrank(payer);
        crvUSD.approve(address(core_), type(uint256).max);
        vm.stopPrank();
    }

    function _newWorld(address validator_) internal returns (World memory w) {
        return _newWorldWithController(validator_, new MockListingController(controllerDao, int128(2)));
    }

    function _newWorldWithController(address validator_, MockListingController ctl) internal returns (World memory w) {
        w.ctl = ctl;
        w.pv = new MockIncentivePlatform(address(crvUSD));
        w.pm = new MockIncentivePlatform(address(crvUSD));
        w.core_ = _deployCore(address(ctl), address(w.pv), address(w.pm), validator_);
        _bindAndUnpause(w.core_, ctl, address(w.pv), address(w.pm));
    }

    // ---------------------------------------------------------------
    // candidate fixtures
    // ---------------------------------------------------------------

    function _coins2() internal returns (address[8] memory c) {
        c[0] = address(new MockERC20(18));
        c[1] = address(new MockERC20(18));
    }

    /// @dev Registry-authenticated pool/gauge from a configured trusted
    /// factory with the method-1 (DIRECT_LP) reciprocal match. Pool, LP,
    /// gauge and factory are pairwise distinct so an argument mutant cannot
    /// pass by collision.
    function _method1Candidate(ConfigurableTrustedValidator v) internal returns (Candidate memory c) {
        TrustedFactoryModel f = new TrustedFactoryModel();
        GaugeValidationModuleModel m = new GaugeValidationModuleModel();
        v.setPolicy(address(f), address(m), 1);
        c.factory = address(f);
        c.lp = address(new MockERC20(18));
        c.pool = address(new MockPool());
        c.gauge = address(new FactoryClaimGauge(c.lp, c.factory));
        f.setGauge(c.lp, c.gauge);
        c.slot = _nextSlot++ % 10;
        registry.setPool(c.pool, c.slot, c.lp, _coins2(), 2);
        registry.setGauge(c.pool, c.slot, 0, c.gauge, int128(0));
    }

    /// @dev Distinct-LP legacy model: method 2, direct lookup ZERO, then
    /// lp.minter() -> pool -> factory.get_gauge(pool) == gauge.
    function _legacyCandidate(ConfigurableTrustedValidator v) internal returns (Candidate memory c) {
        TrustedFactoryModel f = new TrustedFactoryModel();
        GaugeValidationModuleModel m = new GaugeValidationModuleModel();
        v.setPolicy(address(f), address(m), 2);
        c.factory = address(f);
        c.pool = address(new MockPool());
        c.lp = address(new LegacyLpToken(c.pool));
        c.gauge = address(new FactoryClaimGauge(c.lp, c.factory));
        f.setGauge(c.pool, c.gauge); // reverse proof through the minter route
        c.slot = _nextSlot++ % 10;
        registry.setPool(c.pool, c.slot, c.lp, _coins2(), 2);
        registry.setGauge(c.pool, c.slot, 0, c.gauge, int128(0));
    }

    /// @dev Registry-authenticated pool/gauge whose gauge is a plain
    /// non-factory MockGauge: it self-asserts nothing (no factory() function
    /// at all) and no policy exists for it.
    function _plainCandidate() internal returns (Candidate memory c) {
        c.lp = address(new MockERC20(18));
        c.pool = address(new MockPool());
        c.gauge = address(new MockGauge(c.lp));
        c.factory = address(0);
        c.slot = _nextSlot++ % 10;
        registry.setPool(c.pool, c.slot, c.lp, _coins2(), 2);
        registry.setGauge(c.pool, c.slot, 0, c.gauge, int128(0));
    }

    // ---------------------------------------------------------------
    // call wrappers and expectation helpers
    // ---------------------------------------------------------------

    function _paidCall(World memory w, address from, Candidate memory c) internal returns (bool ok, bytes memory ret) {
        vm.prank(from);
        (ok, ret) =
            address(w.core_).call(abi.encodeCall(CurveGaugeLister.listGauge, (c.pool, c.gauge, uint256(0), c.slot)));
    }

    function _freeCall(World memory w, address from, Candidate memory c, uint256 initialWeight)
        internal
        returns (bool ok, bytes memory ret)
    {
        vm.prank(from);
        (ok, ret) = address(w.core_)
            .call(
                abi.encodeCall(CurveGaugeLister.listGaugeNoEscrow, (c.pool, c.gauge, uint256(0), c.slot, initialWeight))
            );
    }

    function _wantUntrusted(address gauge) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(CurveGaugeLister.UntrustedGauge.selector, gauge);
    }

    function _wantCheckFailed(address gauge) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(CurveGaugeLister.TrustedGaugeCheckFailed.selector, gauge);
    }

    function _wantE(bytes4 selector) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(selector);
    }

    function _expectRevertedWith(bool ok, bytes memory ret, bytes memory want, string memory name) internal pure {
        require(!ok, string.concat(name, ": expected revert with the named error, call succeeded"));
        bytesEq(ret, want, name);
    }

    function _expectSucceeded(bool ok, bytes memory ret, string memory name) internal pure {
        require(ok, string.concat(name, ": unexpected revert, data ", _hex(ret)));
    }

    function _hex(bytes memory data) internal pure returns (string memory) {
        bytes16 hexd = "0123456789abcdef";
        bytes memory out = new bytes(data.length * 2);
        for (uint256 i = 0; i < data.length; ++i) {
            uint8 b = uint8(data[i]);
            out[i * 2] = hexd[b >> 4];
            out[i * 2 + 1] = hexd[b & 0x0F];
        }
        return string(out);
    }

    // ---------------------------------------------------------------
    // snapshots
    // ---------------------------------------------------------------

    function _snap(World memory w, address gauge) internal view returns (Snap memory) {
        return _snapActor(w, gauge, payer);
    }

    /// @dev Actor-parameterized snapshot: the payer-side balance/allowance
    /// rows track the ACTUAL actor of the exercised call (V1ALIGN-WITNESSES
    /// §2 snapshot port rule), never a fixed unrelated payer.
    function _snapActor(World memory w, address gauge, address who) internal view returns (Snap memory s) {
        CurveGaugeLister.Listing memory rec = w.core_.getListing(gauge);
        s.pool = rec.pool;
        s.lpToken = rec.lpToken;
        s.payerAddr = rec.payer;
        s.admissionRegistry = rec.admissionRegistry;
        s.gaugeType = rec.gaugeType;
        s.listingEpoch = rec.listingEpoch;
        s.status = uint8(rec.status);
        s.epochsReleased = rec.epochsReleased;
        s.deposited = rec.deposited;
        s.released = rec.released;
        s.remaining = rec.remaining;
        s.confiscated = rec.confiscated;
        s.votium = rec.votium;
        s.voteMarket = rec.voteMarket;
        s.votiumBps = rec.votiumBps;
        s.totalEscrow = w.core_.totalEscrow();
        s.balActor = crvUSD.balanceOf(who);
        s.balCore = crvUSD.balanceOf(address(w.core_));
        s.balFd = crvUSD.balanceOf(address(fd));
        s.balVotium = crvUSD.balanceOf(address(w.pv));
        s.balVoteMarket = crvUSD.balanceOf(address(w.pm));
        s.allowActorCore = crvUSD.allowance(who, address(w.core_));
        s.allowCoreVotium = crvUSD.allowance(address(w.core_), address(w.pv));
        s.allowCoreVm = crvUSD.allowance(address(w.core_), address(w.pm));
        try w.ctl.gauge_types(gauge) returns (int128 t) {
            s.ctlMember = true;
            s.ctlType = t;
        } catch {
            s.ctlMember = false;
            s.ctlType = -99999;
        }
        s.ctlWeight = w.ctl.get_gauge_weight(gauge);
        s.ctlTimeWeight = w.ctl.time_weight(gauge);
        s.ctlNTypes = w.ctl.n_gauge_types();
        s.ctlAdds = w.ctl.addCalls();
        uint256 e0 = (block.timestamp / WEEK) * WEEK;
        (s.pvR1.amount, s.pvR1.executionEpoch, s.pvR1.receipt) = w.pv.getDeposit(gauge, e0 + WEEK);
        (s.pvR2.amount, s.pvR2.executionEpoch, s.pvR2.receipt) = w.pv.getDeposit(gauge, e0 + 2 * WEEK);
        (s.pmR1.amount, s.pmR1.executionEpoch, s.pmR1.receipt) = w.pm.getDeposit(gauge, e0 + WEEK);
        (s.pmR2.amount, s.pmR2.executionEpoch, s.pmR2.receipt) = w.pm.getDeposit(gauge, e0 + 2 * WEEK);
        s.pvDeposits = w.pv.depositCount();
        s.pmDeposits = w.pm.depositCount();
    }

    function _assertSnapUnchanged(Snap memory beforeState, Snap memory afterState, string memory name) internal pure {
        bytes32 a = keccak256(abi.encode(beforeState));
        bytes32 b = keccak256(abi.encode(afterState));
        assertEq(a, b, name);
    }

    function _expectLog(Vm.Log[] memory logs, address emitter, bytes32 topic0, string memory name) internal pure {
        assertTrue(hasEventFrom(logs, emitter, topic0), name);
    }

    function _expectNoLog(Vm.Log[] memory logs, address emitter, bytes32 topic0, string memory name) internal pure {
        assertEq(countEvents(logs, emitter, topic0), 0, name);
    }

    // ---------------------------------------------------------------
    // generic assertions transplanted for this suite
    // ---------------------------------------------------------------

    function assertEq(bool a, bool b, string memory label) internal pure {
        require(a == b, label);
    }

    function bytesEq(bytes memory a, bytes memory b, string memory label) internal pure {
        require(keccak256(a) == keccak256(b), label);
    }
}
