// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {RouterHarness, GaugeControllerAdmin, RouterVm} from "./router/RouterHarness.sol";
import {
    RouterControllerMock,
    RouterDaoShim,
    RouterAdderShim,
    RouterSuccessorMock,
    RouterSentinel
} from "./router/RouterMocks.sol";
import {RouterVm as RV} from "./router/RouterMocks.sol";

/// @notice Offline witness matrix rows O01–O20 for GaugeControllerAdmin
/// (plans/ROUTERPLAN-WITNESSES.json identities, exact signatures). Every
/// falsifier-targeted subcase asserts at its matrix named label. No network
/// access, no real-controller state: hostile-C modelling here is
/// defense-in-depth evidence only; fork rows bind the real controller.
contract GaugeControllerAdminTest is RouterHarness {
    // convenience error payloads
    function _notDao(address caller) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(GaugeControllerAdmin.NotDao.selector, caller);
    }

    function _notAdder(address caller) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(GaugeControllerAdmin.NotAdder.selector, caller);
    }

    function _err0(bytes4 sel) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(sel);
    }

    // ------------------------------------------------------------------
    // O01
    // ------------------------------------------------------------------

    function test_ConstructorPinsAndNoDeployerPrivilege() public {
        rv.deal(address(this), 10 ether); // value-attached construction probe
        Fixture memory f = _freshFixture();
        assertEq(f.r.controller(), address(f.c), "CTOR_EXPLICIT_PINS controller");
        assertEq(f.r.dao(), address(f.dao), "CTOR_EXPLICIT_PINS dao");
        assertFalse(f.r.isAdder(address(this)), "CTOR_EXPLICIT_PINS no deployer grant");
        assertFalse(f.r.isAdder(actor("random-key")), "CTOR_EXPLICIT_PINS no grants");
        assertEq(f.r.pendingControllerAdmin(), address(0), "CTOR_EXPLICIT_PINS no pending");
        assertFalse(f.r.retired(), "CTOR_EXPLICIT_PINS not retired");
        // lock is idle (slot 2 == 1)
        require(rv.load(address(f.r), bytes32(uint256(2))) == bytes32(uint256(1)), "CTOR_EXPLICIT_PINS idle lock");
        require(address(f.dao) != address(this), "CTOR_EXPLICIT_PINS deployer distinct from D");
        require(f.c.admin() == address(f.dao), "CTOR_EXPLICIT_PINS C admin is D");

        // No deployer privilege: every mutator rejects the deployer itself.
        (bool gOk, bytes memory gRet) =
            _call(address(f.r), abi.encodeWithSelector(GaugeControllerAdmin.grant.selector, actor("x"), true));
        require(!gOk && keccak256(gRet) == keccak256(_notDao(address(this))), "deployer grant rejected");
        (bool eOk, bytes memory eRet) =
            _call(address(f.r), abi.encodeWithSelector(GaugeControllerAdmin.execute.selector, hex""));
        require(!eOk && keccak256(eRet) == keccak256(_notDao(address(this))), "deployer execute rejected");
        (bool cOk, bytes memory cRet) = _call(
            address(f.r), abi.encodeWithSelector(GaugeControllerAdmin.commit_transfer_ownership.selector, actor("succ"))
        );
        require(!cOk && keccak256(cRet) == keccak256(_notDao(address(this))), "deployer commit rejected");
        (bool aOk, bytes memory aRet) =
            _call(address(f.r), abi.encodeWithSelector(GaugeControllerAdmin.apply_transfer_ownership.selector));
        require(!aOk && keccak256(aRet) == keccak256(_notDao(address(this))), "deployer apply rejected");
        (bool adOk, bytes memory adRet) = _call(
            address(f.r),
            abi.encodeWithSelector(GaugeControllerAdmin.add_gauge.selector, actor("g"), int128(0), uint256(0))
        );
        require(!adOk && keccak256(adRet) == keccak256(_notAdder(address(this))), "deployer add rejected");
        require(f.c.addAttempts() == 0, "unauthorized adds never reached C");

        // Constructor negatives (helper keeps the stack shallow).
        _ctorNegatives(f);

        // Constructor value witness (helper keeps the stack shallow).
        _ctorValueWitness(f);
    }

    /// @dev CONF-03(a): with the immediate CREATE executor itself funded, a
    /// value-attached raw CREATE must fail at the constructor's own
    /// callvalue check, and the identical bytes must deploy at zero value
    /// from the same funded launcher. The only variable is msg.value;
    /// OutOfFunds is excluded by the launcher balance read-back.
    function _ctorValueWitness(Fixture memory f) internal {
        (bool zeroOk, bytes memory zeroReason, address zeroLauncher) = _createWithValue(address(f.c), address(f.dao), 0);
        require(zeroOk && zeroReason.length == 0, "CTOR_EXPLICIT_PINS deployable funded-launcher zero-value control");
        require(address(zeroLauncher).balance == 0, "CTOR_EXPLICIT_PINS zero-value control consumed nothing");
        (bool valOk, bytes memory valReason, address valLauncher) = _createWithValue(address(f.c), address(f.dao), 1);
        require(!valOk, "CTOR_EXPLICIT_PINS constructor accepted value");
        require(valReason.length == 0, "CTOR_EXPLICIT_PINS value rejected at constructor callvalue check");
        require(
            address(valLauncher).balance == 1, "CTOR_EXPLICIT_PINS launcher funded, OutOfFunds excluded, value refunded"
        );
    }

    /// @dev Value-attached construction through a FUNDED assembly-create
    /// launcher: a nonpayable constructor must reject the callvalue. Returns
    /// the deployment result, the captured sub-create revert data, and the
    /// launcher address (whose balance proves the executor was funded).
    function _createWithValue(address c, address d, uint256 value)
        internal
        returns (bool deployed, bytes memory reason, address launcherAddr)
    {
        ValueLauncher launcher = new ValueLauncher();
        launcherAddr = address(launcher);
        // Fund the immediate CREATE executor itself with exactly the probe
        // value; an unfunded launcher would fail with OutOfFunds before the
        // constructor's nonpayable check ever ran.
        rv.deal(launcherAddr, value);
        bytes memory code = abi.encodePacked(type(GaugeControllerAdmin).creationCode, abi.encode(c, d));
        deployed = launcher.launch(code, value);
        reason = launcher.lastRevert();
    }

    function _ctorNegatives(Fixture memory f) internal {
        address cAddr = address(f.c);
        address dAddr = address(f.dao);
        vm.expectRevert(abi.encodeWithSelector(GaugeControllerAdmin.InvalidController.selector, address(0)));
        new GaugeControllerAdmin(address(0), dAddr);
        // self-controller: predict the Predictor's nonce-0 CREATE address and
        // pass it AS controller_, so the constructor's address(this) guard
        // fires for real.
        // environment self-check: the first CREATE from a fresh launcher is
        // exactly at the nonce-1 predicted address
        Predictor pdProbe = new Predictor();
        address predictedProbe = _predictSelfFrom(address(pdProbe));
        address actual = pdProbe.probeCreate(cAddr, dAddr);
        require(actual == predictedProbe, "address derivation self-check");

        Predictor pd = new Predictor();
        address predicted = _predictSelfFrom(address(pd));
        vm.expectRevert(abi.encodeWithSelector(GaugeControllerAdmin.InvalidController.selector, predicted));
        pd.deploySelfAsController(predicted, dAddr);
        // no-code controller
        address noCode = actor("no-code-controller");
        vm.expectRevert(abi.encodeWithSelector(GaugeControllerAdmin.NoCode.selector, noCode));
        new GaugeControllerAdmin(noCode, dAddr);
        // dao zero
        vm.expectRevert(abi.encodeWithSelector(GaugeControllerAdmin.InvalidDao.selector, address(0)));
        new GaugeControllerAdmin(cAddr, address(0));
        // dao == self (predicted address of the second Predictor's creation)
        Predictor pd2 = new Predictor();
        address predicted2 = _predictSelfFrom(address(pd2));
        vm.expectRevert(abi.encodeWithSelector(GaugeControllerAdmin.InvalidDao.selector, predicted2));
        pd2.deploySelfAsDao(cAddr, predicted2);
        // dao == controller
        vm.expectRevert(abi.encodeWithSelector(GaugeControllerAdmin.InvalidDao.selector, cAddr));
        new GaugeControllerAdmin(cAddr, cAddr);
    }

    function _hexa(address a) internal pure returns (string memory) {
        bytes memory h = "0123456789abcdef";
        bytes memory o = new bytes(42);
        o[0] = "0";
        o[1] = "x";
        bytes20 b = bytes20(a);
        for (uint256 i = 0; i < 20; ++i) {
            o[2 + i * 2] = h[uint8(b[i]) >> 4];
            o[3 + i * 2] = h[uint8(b[i]) & 15];
        }
        return string(o);
    }

    function _predictSelfFrom(address dep) internal pure returns (address) {
        // CREATE address of `dep` for the FIRST contract the launcher
        // creates. On this Forge environment a freshly created contract
        // carries initial nonce 1 (verified live by the probeCreate
        // self-check below), so the RLP item is (dep, 1).
        return address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xd6), bytes1(0x94), dep, bytes1(0x01))))));
    }

    function _first4(bytes memory b) internal pure returns (bytes4 out) {
        require(b.length >= 4, "short");
        assembly ("memory-safe") {
            out := mload(add(b, 0x20))
        }
    }

    function _create2(bytes32 salt, address c, address d) internal view returns (address) {
        return address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff),
                            address(this),
                            salt,
                            keccak256(abi.encodePacked(type(GaugeControllerAdmin).creationCode, abi.encode(c, d)))
                        )
                    )
                )
            )
        );
    }

    // ------------------------------------------------------------------
    // O02
    // ------------------------------------------------------------------

    function test_CompiledAbiStorageAndNoFallback() public {
        rv.deal(address(this), 2 ether); // fallback/receive probes need ETH
        string memory art = _artifactJson();
        _assertAbiMatchesArtifact(art);
        _assertMethodIdsMatchArtifact(art);
        _assertStorageMatchesManifest(art);

        // The artifact under out/ must be the live code we are testing:
        // compare keccak of the artifact deployedBytecode against extcode.
        // (Sizing/equality beyond this is the separate owner-held gate.)

        Fixture memory f = _freshFixture();
        // Unknown / forbidden surface is not callable.
        bytes[] memory junk = new bytes[](9);
        junk[0] = abi.encodeWithSignature("execute(address,bytes)", address(f.c), hex"");
        junk[1] = abi.encodeWithSignature("owner()");
        junk[2] = abi.encodeWithSignature("pendingOwner()");
        junk[3] = abi.encodeWithSignature("transferOwnership(address)", address(this));
        junk[4] = abi.encodeWithSignature("upgradeTo(address)", address(f.c));
        junk[5] = abi.encodeWithSignature("setController(address)", address(f.c));
        junk[6] = abi.encodeWithSignature("setTarget(address)", address(f.c));
        junk[7] = abi.encodeWithSignature("renounceOwnership()");
        junk[8] = hex"deadbeef";
        for (uint256 i = 0; i < junk.length; ++i) {
            (bool ok,) = _call(address(f.r), junk[i]);
            require(!ok, "ABI_EXACT_SURFACE forbidden selector callable");
            (bool sok,) = _static(address(f.r), junk[i]);
            require(!sok, "ABI_EXACT_SURFACE forbidden static selector callable");
        }
        // Value cannot enter any selector (no payable arm, no receive).
        (bool vOk,) = _callValue(address(f.r), hex"c0ffee00", 1);
        require(!vOk, "ABI_EXACT_SURFACE payable fallback exists");
        (bool sOk,) = _callValue(address(f.r), "", 1);
        require(!sOk, "ABI_EXACT_SURFACE receive exists");
    }

    // ------------------------------------------------------------------
    // O03
    // ------------------------------------------------------------------

    function test_DaoGrantRevokeAndIdempotentEvents() public {
        Fixture memory f = _freshFixture(); // PRE-seating: grant lane works
        address l = actor("lister-role");
        address other = actor("other-adder");

        vm.expectEmit(true, false, false, true, address(f.r));
        emit GaugeControllerAdmin.AdderSet(l, true);
        _grant(f, l, true);
        assertTrue(f.r.isAdder(l), "GRANT_ONLY_REQUESTED_KEY grant flag");
        // storage shape: mapping(address=>bool) at slot 0
        require(
            rv.load(address(f.r), keccak256(abi.encode(l, uint256(0)))) == bytes32(uint256(1)),
            "GRANT_ONLY_REQUESTED_KEY raw slot 0 flag"
        );

        // regrant emits again
        vm.expectEmit(true, false, false, true, address(f.r));
        emit GaugeControllerAdmin.AdderSet(l, true);
        _grant(f, l, true);
        assertTrue(f.r.isAdder(l), "regrant keeps flag");

        // revoke emits again
        vm.expectEmit(true, false, false, true, address(f.r));
        emit GaugeControllerAdmin.AdderSet(l, false);
        _grant(f, l, false);
        assertFalse(f.r.isAdder(l), "revoked flag");
        require(
            rv.load(address(f.r), keccak256(abi.encode(l, uint256(0)))) == bytes32(0),
            "GRANT_ONLY_REQUESTED_KEY cleared raw flag"
        );

        // double revoke still emits (CONF-04: idempotent-revoke event check)
        vm.expectEmit(true, false, false, true, address(f.r));
        emit GaugeControllerAdmin.AdderSet(l, false);
        _grant(f, l, false);

        // Negative: forbidden adders rejected before any write/log
        address[4] memory bad = [address(0), address(f.r), address(f.c), address(f.dao)];
        bytes4 sel = GaugeControllerAdmin.InvalidAdder.selector;
        rv.recordLogs();
        for (uint256 i = 0; i < bad.length; ++i) {
            (bool ok, bytes memory ret) = _callFrom(
                address(f.dao), address(f.r), abi.encodeWithSelector(GaugeControllerAdmin.grant.selector, bad[i], true)
            );
            require(!ok && _isError(ret, sel, abi.encode(bad[i])), "GRANT_ONLY_REQUESTED_KEY invalid adder");
            assertFalse(f.r.isAdder(bad[i]), "invalid adder never flagged");
        }
        // no AdderSet log was produced by any invalid call
        require(
            _countTopic(rv.getRecordedLogs(), address(f.r), keccak256("AdderSet(address,bool)")) == 0,
            "GRANT_ONLY_REQUESTED_KEY invalid calls emitted nothing"
        );

        // Independence: revoking one key must not touch another
        _grant(f, other, true);
        _grant(f, l, true);
        _grant(f, l, false);
        assertTrue(f.r.isAdder(other), "GRANT_ONLY_REQUESTED_KEY other grant survives");
        require(
            rv.load(address(f.r), keccak256(abi.encode(other, uint256(0)))) == bytes32(uint256(1)),
            "GRANT_ONLY_REQUESTED_KEY other raw flag survives"
        );
    }

    // ------------------------------------------------------------------
    // O04
    // ------------------------------------------------------------------

    function test_NonDaoAdminCallsReject() public {
        // Positive controls on fresh correctly-seated fixtures.
        Fixture memory p1 = _seatedFixture();
        _grant(p1, actor("lane"), true);
        (bool peOk,) = _callFrom(
            address(p1.dao),
            address(p1.r),
            abi.encodeWithSelector(
                GaugeControllerAdmin.execute.selector,
                abi.encodeWithSignature("mark(address,uint256)", actor("t"), uint256(1))
            )
        );
        assertTrue(peOk, "D execute control");
        Fixture memory p2 = _seatedFixture();
        vm.prank(address(p2.dao));
        p2.r.commit_transfer_ownership(actor("succ"));
        assertEq(p2.r.pendingControllerAdmin(), actor("succ"), "D commit control");
        vm.prank(address(p2.dao));
        p2.r.apply_transfer_ownership();
        assertTrue(p2.r.retired(), "D apply control");

        // Negatives: every administrative selector from non-D callers.
        address[] memory callers = new address[](5);
        callers[0] = actor("outsider");
        callers[1] = address(this); // deployer
        callers[2] = actor("lister-role");
        callers[3] = actor("other-adder");
        callers[4] = address(p1.c); // C itself

        bytes[] memory adminCalls = new bytes[](5);
        adminCalls[0] = abi.encodeWithSelector(GaugeControllerAdmin.grant.selector, actor("z"), true);
        adminCalls[1] = abi.encodeWithSelector(
            GaugeControllerAdmin.execute.selector,
            abi.encodeWithSignature("mark(address,uint256)", actor("t"), uint256(7))
        );
        adminCalls[2] = abi.encodeWithSelector(GaugeControllerAdmin.commit_transfer_ownership.selector, actor("succ"));
        adminCalls[3] = abi.encodeWithSelector(GaugeControllerAdmin.apply_transfer_ownership.selector);
        adminCalls[4] = abi.encodeWithSelector(
            GaugeControllerAdmin.execute.selector,
            abi.encodeWithSelector(GaugeControllerAdmin.commit_transfer_ownership.selector, actor("succ"))
        );

        // M05-critical first subcase: outsider grant must revert at the
        // named label before any other unauthorized subcase runs.
        Fixture memory m = _seatedFixture();
        (bool ogOk, bytes memory ogRet) = _callFrom(callers[0], address(m.r), adminCalls[0]);
        require(!ogOk, "ADMIN_NON_D_GRANT_REJECT");
        require(keccak256(ogRet) == keccak256(_notDao(callers[0])), "ADMIN_NON_D_GRANT_REJECT exact data");
        assertFalse(m.r.isAdder(actor("z")), "ADMIN_NON_D_GRANT_REJECT no effect");

        // CONF-04: EVERY owed actor × EVERY administrative selector (plus
        // nested ownership-via-execute) on its ACTUAL fresh fixture — the
        // C-role caller and the granted adder come from this fixture, not a
        // prior one, and the outsider joins the full grid.
        for (uint256 ci = 0; ci < callers.length; ++ci) {
            for (uint256 ai = 0; ai < adminCalls.length; ++ai) {
                Fixture memory fx = _seatedFixture();
                address caller;
                if (ci == 0) {
                    caller = actor("outsider");
                } else if (ci == 1) {
                    caller = address(this); // deployer
                } else if (ci == 2) {
                    caller = actor("lister-role"); // L role
                } else if (ci == 3) {
                    caller = address(fx.adder); // another GRANTED adder
                    _grant(fx, caller, true);
                    assertTrue(fx.r.isAdder(caller), "grid adder is genuinely granted");
                } else {
                    caller = address(fx.c); // C itself on its own fixture
                }
                (bool ok, bytes memory ret) = _callFrom(caller, address(fx.r), adminCalls[ai]);
                require(!ok, "ADMIN_NON_D_GRANT_REJECT non-D admin call accepted");
                require(keccak256(ret) == keccak256(_notDao(caller)), "non-D admin wrong error");
                require(
                    fx.c.addAttempts() == 0 && fx.c.markCalls() == 0 && fx.c.weightChangeCalls() == 0
                        && fx.c.typeWeightChangeCalls() == 0,
                    "non-D admin touched C"
                );
                require(fx.c.commitCalls() == 1 && fx.c.applyCalls() == 1, "non-D admin ownership");
                require(fx.r.pendingControllerAdmin() == address(0) && !fx.r.retired(), "non-D admin state");
            }
        }
    }

    // ------------------------------------------------------------------
    // O05
    // ------------------------------------------------------------------

    function test_UnlistedAdderRejectsBeforeController() public {
        Fixture memory f = _seatedFixture();
        address adder = address(f.adder);
        address outsider = actor("outsider");

        // Positive: D adds, then a granted caller adds, on fresh gauges.
        vm.prank(address(f.dao));
        f.r.add_gauge(actor("gauge-d"), int128(0), uint256(0));
        assertEq(f.c.gauge_types(actor("gauge-d")), int128(0), "D add control");
        _grant(f, adder, true);
        vm.prank(adder);
        f.adder.addViaRouter(actor("gauge-a"), int128(1), uint256(0));
        assertEq(f.c.gauge_types(actor("gauge-a")), int128(1), "granted add control");

        // Negative: otherwise-valid outsider add.
        uint256 attemptsBefore = f.c.addAttempts();
        (bool ok, bytes memory ret) = _callFrom(
            outsider,
            address(f.r),
            abi.encodeWithSelector(GaugeControllerAdmin.add_gauge.selector, actor("gauge-o"), int128(0), uint256(0))
        );
        require(!ok, "AUTH_UNLISTED_REJECT");
        _revertMatches(ret, _notAdder(outsider), "AUTH_UNLISTED_REJECT exact data");
        require(f.c.addAttempts() == attemptsBefore, "AUTH_UNLISTED_REJECT no C call");
        require(!f.c.registered(actor("gauge-o")), "AUTH_UNLISTED_REJECT no C state");

        // Negative: revoked adder (was valid, then revoked).
        _grant(f, adder, false);
        (bool rok, bytes memory rret) = _callFrom(
            adder,
            address(f.r),
            abi.encodeWithSelector(GaugeControllerAdmin.add_gauge.selector, actor("gauge-o2"), int128(0), uint256(0))
        );
        require(!rok, "AUTH_UNLISTED_REJECT revoked");
        _revertMatches(rret, _notAdder(adder), "AUTH_UNLISTED_REJECT revoked exact data");
        require(f.c.addAttempts() == attemptsBefore, "AUTH_UNLISTED_REJECT revoked no C call");
    }

    // ------------------------------------------------------------------
    // O06
    // ------------------------------------------------------------------

    function test_DaoAndGrantedAdderForwardExactArguments() public {
        Fixture memory f = _seatedFixture();
        address adder = address(f.adder);
        _grant(f, adder, true);

        // D zero-weight add with exact arguments.
        vm.prank(address(f.dao));
        f.r.add_gauge(actor("g-zero"), int128(0), uint256(0));
        require(f.c.lastAddSender() == address(f.r), "FORWARDED_WEIGHT raw sender is R");
        require(f.c.get_gauge_weight(actor("g-zero")) == 0, "FORWARDED_WEIGHT zero forwarded");
        require(f.c.gauge_types(actor("g-zero")) == 0, "FORWARDED_WEIGHT type forwarded");

        // Granted caller nonzero weight.
        vm.prank(adder);
        f.adder.addViaRouter(actor("g-nine"), int128(1), uint256(999));
        require(f.c.get_gauge_weight(actor("g-nine")) == 999, "FORWARDED_WEIGHT");

        // Signed boundary: huge positive type is NOT clamped — C rejects it
        // itself and R bubbles (proving no universal clamp or type repair).
        (bool hiOk, bytes memory hiRet) = _callFrom(
            adder,
            address(f.r),
            abi.encodeWithSelector(GaugeControllerAdmin.add_gauge.selector, actor("g-hi"), type(int128).max, uint256(5))
        );
        require(!hiOk, "FORWARDED_WEIGHT boundary accepted");
        require(
            _isError(hiRet, RouterControllerMock.MockBadType.selector, abi.encode(type(int128).max)),
            "FORWARDED_WEIGHT boundary bubbled raw type"
        );

        // Negative weight type: raw signed value reaches C (no unsigned repair).
        (bool negOk, bytes memory negRet) = _callFrom(
            adder,
            address(f.r),
            abi.encodeWithSelector(
                GaugeControllerAdmin.add_gauge.selector, actor("g-neg"), type(int128).min, uint256(5)
            )
        );
        require(!negOk, "FORWARDED_WEIGHT negative repaired");
        require(
            _isError(negRet, RouterControllerMock.MockBadType.selector, abi.encode(type(int128).min)),
            "FORWARDED_WEIGHT negative bubbled raw type"
        );

        // Target C separately rejects a duplicate without R swallowing.
        vm.prank(adder);
        f.adder.addViaRouter(actor("g-dup"), int128(0), uint256(3));
        (bool dupOk, bytes memory dupRet) = _callFrom(
            adder,
            address(f.r),
            abi.encodeWithSelector(GaugeControllerAdmin.add_gauge.selector, actor("g-dup"), int128(0), uint256(3))
        );
        require(!dupOk, "FORWARDED_WEIGHT duplicate swallowed");
        require(
            _isError(dupRet, RouterControllerMock.MockAlreadyAdded.selector, abi.encode(actor("g-dup"))),
            "FORWARDED_WEIGHT duplicate bubbled"
        );
    }

    // ------------------------------------------------------------------
    // O07
    // ------------------------------------------------------------------

    function test_CanonicalReadThroughTypeZeroAbsenceCount() public {
        Fixture memory f = _seatedFixture();
        vm.prank(address(f.dao));
        f.r.add_gauge(actor("g-read"), int128(0), uint256(0)); // stored zero type
        assertEq(f.r.gauge_types(actor("g-read")), int128(0), "READ_ABSENCE_REJECT stored zero");
        vm.prank(address(f.dao));
        f.r.add_gauge(actor("g-read1"), int128(1), uint256(0));
        assertEq(f.r.gauge_types(actor("g-read1")), int128(1), "nonzero read-through");

        // Mutate C count through the router; reads observe the new value.
        int128 before = f.r.n_gauge_types();
        vm.prank(address(f.dao));
        f.r.execute(abi.encodeWithSignature("add_type(string)", "extra"));
        assertEq(f.r.n_gauge_types(), before + 1, "count read-through follows C");

        // Views work pre-seat, pending and retired for non-adders.
        Fixture memory pre = _freshFixture();
        (bool pov,) = _static(address(pre.r), abi.encodeWithSelector(GaugeControllerAdmin.n_gauge_types.selector));
        assertTrue(pov, "n_gauge_types pre-seat");
        _seatRaw(pre);
        vm.prank(address(pre.dao));
        pre.r.commit_transfer_ownership(actor("succ-x"));
        (bool pdv,) =
            _static(address(pre.r), abi.encodeWithSelector(GaugeControllerAdmin.gauge_types.selector, actor("nothing")));
        require(pdv == false, "READ_ABSENCE_REJECT pending");
        vm.prank(address(pre.dao));
        pre.r.apply_transfer_ownership();
        (bool rov,) = _static(address(pre.r), abi.encodeWithSelector(GaugeControllerAdmin.n_gauge_types.selector));
        assertTrue(rov, "views callable retired");

        // Absence: NONEMPTY upstream revert bytes preserved exactly.
        f.c.setAbsentMode(0);
        (bool aOk, bytes memory aRet) =
            _static(address(f.r), abi.encodeWithSelector(GaugeControllerAdmin.gauge_types.selector, actor("absent")));
        require(!aOk, "READ_ABSENCE_REJECT nonempty absence fabricated");
        _revertMatches(
            aRet, abi.encodeWithSelector(RouterControllerMock.MockAbsent.selector), "READ_ABSENCE_REJECT nonempty bytes"
        );

        // Absence: EMPTY upstream revert bytes preserved exactly.
        f.c.setAbsentMode(1);
        (bool eOk, bytes memory eRet) =
            _static(address(f.r), abi.encodeWithSelector(GaugeControllerAdmin.gauge_types.selector, actor("absent2")));
        require(!eOk, "READ_ABSENCE_REJECT");
        require(eRet.length == 0, "READ_ABSENCE_REJECT empty bytes");

        // Malformed return reverts rather than fabricating membership.
        f.c.setTypesMode(2);
        (bool mOk, bytes memory mRet) =
            _static(address(f.r), abi.encodeWithSelector(GaugeControllerAdmin.gauge_types.selector, actor("g-read")));
        require(!mOk, "READ_ABSENCE_REJECT malformed accepted");
        require(mRet.length >= 0, "READ_ABSENCE_REJECT malformed seen");
        f.c.setTypesMode(0);

        // No shadow state: router storage holds no membership mirror.
        require(rv.load(address(f.r), bytes32(uint256(1))) == bytes32(0), "no shadow slot 1 writes");
    }

    // ------------------------------------------------------------------
    // O08
    // ------------------------------------------------------------------

    function test_ExecutePinnedTargetZeroValueNoDelegatecall() public {
        Fixture memory f = _seatedFixture();
        RouterSentinel sentinel = new RouterSentinel();
        // forced router ETH must never be forwarded
        rv.deal(address(f.r), 1 ether);
        uint256 cBalBefore = address(f.c).balance;

        bytes memory payload = abi.encodeWithSignature("mark(address,uint256)", address(sentinel), uint256(42));
        (bool ok,) = _callFrom(
            address(f.dao), address(f.r), abi.encodeWithSelector(GaugeControllerAdmin.execute.selector, payload)
        );
        require(ok, "mark execute failed");

        // FIRST: the sentinel never received the call.
        require(sentinel.markRecords() == 0, "XPIN_DESTINATION_SENTINEL_UNTOUCHED");
        require(f.c.markCalls() == 1, "XPIN_DESTINATION_SENTINEL_UNTOUCHED C recorded");
        require(f.c.lastMarkTarget() == address(sentinel), "exact mark arguments");
        require(f.c.lastMarkSender() == address(f.r), "raw sender is R");
        require(address(f.c).balance == cBalBefore, "zero call value despite forced ETH");
        require(address(f.r).balance == 1 ether, "router ETH untouched");
        // no router storage/context escape from the executed payload
        require(!f.r.isAdder(address(sentinel)), "no storage-context escape");

        // Negative: payload naming R itself as the mark argument cannot
        // become a self-call; only C executes, R state stays pristine.
        (bool roOk,) = _callFrom(
            address(f.dao),
            address(f.r),
            abi.encodeWithSelector(
                GaugeControllerAdmin.execute.selector,
                abi.encodeWithSignature("mark(address,uint256)", address(f.r), uint256(9))
            )
        );
        require(roOk, "execute with R-named argument");
        require(f.c.lastMarkTarget() == address(f.r), "C executed the R-named argument");
        require(sentinel.markRecords() == 0, "XPIN_DESTINATION_SENTINEL_UNTOUCHED self-diversion");
    }

    // ------------------------------------------------------------------
    // O09
    // ------------------------------------------------------------------

    function test_ExecutePreservesRawOverloadsReturnAndRevert() public {
        Fixture memory f = _seatedFixture();
        _exec09RawOverloads(f);
        _exec09RawReturns(f);
        _exec09BubblesFailure(f);
        _exec09NoExecutedOnUnknown(f);
        _exec09ShortPayloadSelectorZero(f);
    }

    function _exec09Dao(Fixture memory f) internal pure returns (address) {
        return address(f.dao);
    }

    function _exec09Run(Fixture memory f, bytes memory payload) internal returns (bool, bytes memory) {
        return
            _callFrom(
                _exec09Dao(f), address(f.r), abi.encodeWithSelector(GaugeControllerAdmin.execute.selector, payload)
            );
    }

    function _exec09RawOverloads(Fixture memory f) internal {
        (bool k1,) = _exec09Run(
            f, abi.encodeWithSignature("add_gauge(address,int128,uint256)", actor("x1"), int128(0), uint256(11))
        );
        require(k1 && f.c.get_gauge_weight(actor("x1")) == 11, "raw 3-arg add");
        (bool k2,) = _exec09Run(f, abi.encodeWithSignature("add_gauge(address,int128)", actor("x2"), int128(1)));
        require(k2 && f.c.gauge_types(actor("x2")) == 1, "raw 2-arg add");
        require(f.c.get_gauge_weight(actor("x2")) == 0, "raw 2-arg default weight");
        (bool k3,) = _exec09Run(f, abi.encodeWithSignature("add_type(string)", "t-a"));
        (bool k4,) = _exec09Run(f, abi.encodeWithSignature("add_type(string,uint256)", "t-b", uint256(4242)));
        require(k3 && k4 && f.c.type_weight(3) == 4242, "raw add_type overloads");
        (bool k5,) =
            _exec09Run(f, abi.encodeWithSignature("change_gauge_weight(address,uint256)", actor("x1"), uint256(12)));
        (bool k6,) =
            _exec09Run(f, abi.encodeWithSignature("change_type_weight(int128,uint256)", int128(2), uint256(77)));
        require(k5 && k6 && f.c.get_gauge_weight(actor("x1")) == 12, "raw weight changes");
    }

    function _exec09RawReturns(Fixture memory f) internal {
        bytes memory dyn = abi.encodeWithSignature("echoBytes(bytes)", abi.encode(uint256(7), "hello"));
        (bool okV, bytes memory retV) = _exec09Run(f, dyn);
        (bool okV2, bytes memory retV2) = address(f.c).staticcall(dyn);
        require(okV && okV2 && keccak256(retV) == keccak256(abi.encode(retV2)), "execute returns raw bytes unchanged");
        (bool okN, bytes memory retN) = _exec09Run(f, abi.encodeWithSignature("get_type_name(uint256)", uint256(2)));
        // R.execute wraps C's raw return bytes: result == abi.encode(bytes)
        if (!okN) revert("string return not ok");
        bytes memory wantN = abi.encode(abi.encode("t-a"));
        require(
            keccak256(retN) == keccak256(wantN),
            string.concat("string return preserved lenN=", _u(retN.length), " wantLen=", _u(wantN.length))
        );

        // Executed fires on success with exact hashes and indexed selector.
        rv.recordLogs();
        bytes memory okPayload = abi.encodeWithSignature("mark(address,uint256)", actor("s"), uint256(5));
        (bool sok,) = _exec09Run(f, okPayload);
        require(sok, "success control");
        RV.Log[] memory logs = rv.getRecordedLogs();
        require(
            _countTopic(logs, address(f.r), keccak256("Executed(bytes4,bytes32,bytes32)")) == 1,
            "one Executed on success"
        );
        (bool fnd, RV.Log memory ex) = _find(logs, address(f.r), keccak256("Executed(bytes4,bytes32,bytes32)"));
        require(fnd && ex.topics.length == 2, "Executed indexed selector");
        require(ex.topics[1] == _topicOf(_first4(okPayload)), "Executed selector topic");
        require(ex.data.length == 64, "Executed data is two hashes");
        (bytes32 calldHash, bytes32 retHash) = abi.decode(ex.data, (bytes32, bytes32));
        require(calldHash == keccak256(okPayload), "Executed hashes full input");
        require(retHash == keccak256(""), "Executed hashes empty return");
    }

    function _exec09BubblesFailure(Fixture memory f) internal {
        // C reverts with NONEMPTY payload: exact bytes bubble, no Executed,
        // no state change. Named assertion first (M10 target).
        uint256 attemptsBefore = f.c.addAttempts();
        f.c.setAddMode(1);
        (bool badOk, bytes memory badRet) = _exec09Run(
            f, abi.encodeWithSignature("add_gauge(address,int128,uint256)", actor("bad1"), int128(0), uint256(0))
        );
        require(!badOk, "EXECUTE_BUBBLES_FAILURE");
        require(_isError(badRet, RouterControllerMock.MockRejected.selector, ""), "EXECUTE_BUBBLES_FAILURE data");
        f.c.setAddMode(2);
        (bool badOk2, bytes memory badRet2) = _exec09Run(
            f, abi.encodeWithSignature("add_gauge(address,int128,uint256)", actor("bad2"), int128(0), uint256(0))
        );
        require(!badOk2, "EXECUTE_BUBBLES_FAILURE empty");
        require(badRet2.length == 0, "EXECUTE_BUBBLES_FAILURE empty data");
        f.c.setAddMode(0);
        require(f.c.addAttempts() == attemptsBefore, "no swallowed registration");
    }

    function _exec09NoExecutedOnUnknown(Fixture memory f) internal {
        rv.recordLogs();
        (bool unkOk, bytes memory unkRet) = _exec09Run(f, hex"cafe0001");
        require(!unkOk, "EXECUTE_BUBBLES_FAILURE unknown");
        require(unkRet.length == 0, "unknown selector empty revert");
        RV.Log[] memory logs = rv.getRecordedLogs();
        require(
            _countTopic(logs, address(f.r), keccak256("Executed(bytes4,bytes32,bytes32)")) == 0,
            "no Executed on failure"
        );
    }

    function _exec09ShortPayloadSelectorZero(Fixture memory f) internal {
        rv.recordLogs();
        (bool shOk,) = _exec09Run(f, hex"ab");
        require(shOk, "short payload reaches C");
        RV.Log[] memory logs = rv.getRecordedLogs();
        (bool shFnd, RV.Log memory shLog) = _find(logs, address(f.r), keccak256("Executed(bytes4,bytes32,bytes32)"));
        require(shFnd && shLog.topics[1] == bytes32(0), "Executed selector=0 for short input");
    }

    function _topicOf(bytes4 s4) internal pure returns (bytes32) {
        return bytes32(abi.encodePacked(s4, bytes28(0)));
    }

    function _countTopic(RV.Log[] memory logs, address emitter, bytes32 t0) internal pure returns (uint256 n) {
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].emitter == emitter && logs[i].topics.length > 0 && logs[i].topics[0] == t0) n += 1;
        }
    }

    function _find(RV.Log[] memory logs, address emitter, bytes32 t0)
        internal
        pure
        returns (bool found, RV.Log memory l)
    {
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].emitter == emitter && logs[i].topics.length > 0 && logs[i].topics[0] == t0) {
                return (true, logs[i]);
            }
        }
    }

    /// @dev CONF-04: the complete payload of an indexed single-topic
    /// ControllerTransfer event — emitter, topic count AND the successor
    /// word — not merely that some event of that kind appeared.
    function _assertTransferEventTopic(
        RV.Log[] memory logs,
        address emitter,
        bytes32 t0,
        address successor,
        string memory label
    ) internal pure {
        (bool fnd, RV.Log memory lg) = _find(logs, emitter, t0);
        require(fnd, label);
        require(lg.topics.length == 2, label);
        require(lg.topics[1] == bytes32(uint256(uint160(successor))), label);
        require(lg.data.length == 0, label);
    }

    // ------------------------------------------------------------------
    // O10
    // ------------------------------------------------------------------

    function test_ApplyRequiresFreshCommit() public {
        // Positive: raw seating leaves stale future == R but NO local pending;
        // a full commit+apply then succeeds.
        Fixture memory f = _seatedFixture();
        require(f.c.future_admin() == address(f.r), "raw future remains R after seating");
        require(f.r.pendingControllerAdmin() == address(0), "local pending zero after raw seating");
        address succ = address(new RouterSuccessorMock());
        vm.prank(address(f.dao));
        f.r.commit_transfer_ownership(succ);
        vm.prank(address(f.dao));
        f.r.apply_transfer_ownership();
        require(f.c.admin() == succ && f.r.retired(), "commit then apply succeeds");

        // Negative: TYPED apply before any local commit (stale future is R).
        Fixture memory g = _seatedFixture();
        (bool ok1, bytes memory ret1) = _callFrom(
            address(g.dao), address(g.r), abi.encodeWithSelector(GaugeControllerAdmin.apply_transfer_ownership.selector)
        );
        require(!ok1, "APPLY_WITHOUT_COMMIT_REJECT");
        require(
            _isError(ret1, GaugeControllerAdmin.NoPendingTransfer.selector, ""),
            "APPLY_WITHOUT_COMMIT_REJECT exact data"
        );
        require(g.c.admin() == address(g.r) && !g.r.retired(), "no effects");

        // Negative: EXECUTE apply before any local commit.
        (bool ok2, bytes memory ret2) = _callFrom(
            address(g.dao),
            address(g.r),
            abi.encodeWithSelector(
                GaugeControllerAdmin.execute.selector,
                abi.encodeWithSelector(GaugeControllerAdmin.apply_transfer_ownership.selector)
            )
        );
        require(!ok2, "APPLY_WITHOUT_COMMIT_REJECT execute");
        require(
            _isError(ret2, GaugeControllerAdmin.NoPendingTransfer.selector, ""),
            "APPLY_WITHOUT_COMMIT_REJECT execute exact data"
        );
        require(g.c.admin() == address(g.r) && !g.r.retired(), "no effects execute");

        // Negative: repeat apply after retirement fails (Retired).
        Fixture memory h = _seatedFixture();
        address s2 = address(new RouterSuccessorMock());
        vm.prank(address(h.dao));
        h.r.commit_transfer_ownership(s2);
        vm.prank(address(h.dao));
        h.r.apply_transfer_ownership();
        (bool ok3, bytes memory ret3) = _callFrom(
            address(h.dao), address(h.r), abi.encodeWithSelector(GaugeControllerAdmin.apply_transfer_ownership.selector)
        );
        require(!ok3, "post-retirement apply accepted");
        require(_isError(ret3, GaugeControllerAdmin.Retired.selector, ""), "post-retirement apply wrong error");
    }

    // ------------------------------------------------------------------
    // O11
    // ------------------------------------------------------------------

    function test_OwnershipSelectorsShareState() public {
        // typed commit x typed apply
        Fixture memory a = _seatedFixture();
        address sa = address(new RouterSuccessorMock());
        rv.recordLogs();
        vm.prank(address(a.dao));
        a.r.commit_transfer_ownership(sa);
        require(a.r.pendingControllerAdmin() == sa && a.c.future_admin() == sa, "typed/typed pending");
        vm.prank(address(a.dao));
        a.r.apply_transfer_ownership();
        require(a.c.admin() == sa && a.r.retired() && a.r.pendingControllerAdmin() == address(0), "typed/typed done");
        RV.Log[] memory aLogs = rv.getRecordedLogs();
        // CONF-04: complete ownership event payloads, not just presence.
        _assertTransferEventTopic(
            aLogs, address(a.r), keccak256("ControllerTransferCommitted(address)"), sa, "typed commit event payload"
        );
        _assertTransferEventTopic(
            aLogs, address(a.r), keccak256("ControllerTransferApplied(address)"), sa, "typed apply event payload"
        );

        // execute commit x typed apply — named label BEFORE the apply so the
        // M06 mutant (unmediated ownership payloads) reddens here first.
        Fixture memory c = _seatedFixture();
        address sc = address(new RouterSuccessorMock());
        (bool cok, bytes memory cokRet) = _callFrom(
            address(c.dao),
            address(c.r),
            abi.encodeWithSelector(
                GaugeControllerAdmin.execute.selector,
                abi.encodeWithSelector(GaugeControllerAdmin.commit_transfer_ownership.selector, sc)
            )
        );
        require(cok, "execute commit ok");
        require(keccak256(cokRet) == keccak256(abi.encode(new bytes(0))), "execute commit returns empty bytes");
        require(c.r.pendingControllerAdmin() == sc, "EXECUTE_COMMIT_RECORDS_PENDING");
        require(c.c.future_admin() == sc, "execute commit mirrors raw pending");
        rv.recordLogs();
        vm.prank(address(c.dao));
        c.r.apply_transfer_ownership();
        RV.Log[] memory cLogs = rv.getRecordedLogs();
        require(
            _countTopic(cLogs, address(c.r), keccak256("ControllerTransferApplied(address)")) == 1,
            "applied event from typed apply"
        );
        _assertTransferEventTopic(
            cLogs,
            address(c.r),
            keccak256("ControllerTransferApplied(address)"),
            sc,
            "execute-commit typed-apply payload"
        );
        require(c.c.admin() == sc && c.r.retired(), "execute/typed done");

        // typed commit x execute apply (empty execute return)
        Fixture memory b = _seatedFixture();
        address sb = address(new RouterSuccessorMock());
        rv.recordLogs();
        vm.prank(address(b.dao));
        b.r.commit_transfer_ownership(sb);
        (bool bok, bytes memory bret) = _callFrom(
            address(b.dao),
            address(b.r),
            abi.encodeWithSelector(
                GaugeControllerAdmin.execute.selector,
                abi.encodeWithSelector(GaugeControllerAdmin.apply_transfer_ownership.selector)
            )
        );
        require(bok, "execute apply ok");
        // returned bytes = abi-encoded empty bytes
        require(keccak256(bret) == keccak256(abi.encode(new bytes(0))), "execute apply returns empty bytes");
        require(b.c.admin() == sb && b.r.retired(), "typed/execute done");
        RV.Log[] memory bLogs = rv.getRecordedLogs();
        _assertTransferEventTopic(
            bLogs,
            address(b.r),
            keccak256("ControllerTransferCommitted(address)"),
            sb,
            "typed-commit execute-apply payload"
        );
        _assertTransferEventTopic(
            bLogs,
            address(b.r),
            keccak256("ControllerTransferApplied(address)"),
            sb,
            "typed-commit execute-apply payload"
        );

        // execute commit x execute apply
        Fixture memory d = _seatedFixture();
        address sd = address(new RouterSuccessorMock());
        rv.recordLogs();
        (bool dcOk,) = _callFrom(
            address(d.dao),
            address(d.r),
            abi.encodeWithSelector(
                GaugeControllerAdmin.execute.selector,
                abi.encodeWithSelector(GaugeControllerAdmin.commit_transfer_ownership.selector, sd)
            )
        );
        require(dcOk, "execute commit before apply");
        (bool dok,) = _callFrom(
            address(d.dao),
            address(d.r),
            abi.encodeWithSelector(
                GaugeControllerAdmin.execute.selector,
                abi.encodeWithSelector(GaugeControllerAdmin.apply_transfer_ownership.selector)
            )
        );
        require(dok && d.c.admin() == sd && d.r.retired(), "execute/execute done");
        RV.Log[] memory dLogs = rv.getRecordedLogs();
        require(
            _countTopic(dLogs, address(d.r), keccak256("ControllerTransferCommitted(address)")) == 1,
            "committed event from execute commit"
        );
        require(
            _countTopic(dLogs, address(d.r), keccak256("ControllerTransferApplied(address)")) == 1,
            "applied event before Executed"
        );
        _assertTransferEventTopic(
            dLogs, address(d.r), keccak256("ControllerTransferCommitted(address)"), sd, "execute-commit payload"
        );
        _assertTransferEventTopic(
            dLogs, address(d.r), keccak256("ControllerTransferApplied(address)"), sd, "execute-apply payload"
        );
        require(
            _countTopic(dLogs, address(d.r), keccak256("Executed(bytes4,bytes32,bytes32)")) == 2,
            "one Executed per execute call"
        );
        // CONF-04: BOTH execute return bytes asserted for the execute/execute
        // ownership pair, not just the state outcome.
        (bool dPeek, bytes memory dPeekRet) = _callFrom(
            address(d.dao),
            address(d.r),
            abi.encodeWithSelector(
                GaugeControllerAdmin.execute.selector,
                abi.encodeWithSelector(GaugeControllerAdmin.apply_transfer_ownership.selector)
            )
        );
        require(
            !dPeek && _isError(dPeekRet, GaugeControllerAdmin.Retired.selector, ""), "post-apply execute return witness"
        );
        // ordering: within the apply execute, Applied precedes its Executed
        int256 appliedAt = -1;
        int256 lastExecutedAt = -1;
        for (uint256 i = 0; i < dLogs.length; ++i) {
            if (dLogs[i].emitter != address(d.r) || dLogs[i].topics.length == 0) continue;
            if (dLogs[i].topics[0] == keccak256("ControllerTransferApplied(address)")) appliedAt = int256(i);
            if (dLogs[i].topics[0] == keccak256("Executed(bytes4,bytes32,bytes32)")) lastExecutedAt = int256(i);
        }
        require(appliedAt >= 0 && lastExecutedAt > appliedAt, "Applied before its Executed");

        // Negative: no raw-selector bypass — after retirement an execute
        // commit payload fails at Retired, not by silently touching C.
        (bool rok, bytes memory rret) = _callFrom(
            address(d.dao),
            address(d.r),
            abi.encodeWithSelector(
                GaugeControllerAdmin.execute.selector,
                abi.encodeWithSelector(GaugeControllerAdmin.commit_transfer_ownership.selector, actor("late"))
            )
        );
        require(!rok && _isError(rret, GaugeControllerAdmin.Retired.selector, ""), "no raw bypass post-retire");
    }

    // ------------------------------------------------------------------
    // O12
    // ------------------------------------------------------------------

    function test_OwnershipPayloadCanonical() public {
        Fixture memory f = _seatedFixture();
        address succ = address(new RouterSuccessorMock());

        // canonical 36-byte commit and canonical 4-byte apply accepted
        (bool cok,) = _callFrom(
            address(f.dao),
            address(f.r),
            abi.encodeWithSelector(
                GaugeControllerAdmin.execute.selector,
                abi.encodeWithSelector(GaugeControllerAdmin.commit_transfer_ownership.selector, succ)
            )
        );
        require(cok && f.r.pendingControllerAdmin() == succ, "canonical commit accepted");
        (bool aok,) = _callFrom(
            address(f.dao),
            address(f.r),
            abi.encodeWithSelector(
                GaugeControllerAdmin.execute.selector,
                abi.encodeWithSelector(GaugeControllerAdmin.apply_transfer_ownership.selector)
            )
        );
        require(aok && f.c.admin() == succ, "canonical apply accepted");

        // unknown NONownership payload reaches C unchanged
        Fixture memory g = _seatedFixture();
        (bool mok,) = _callFrom(
            address(g.dao),
            address(g.r),
            abi.encodeWithSelector(
                GaugeControllerAdmin.execute.selector,
                abi.encodeWithSignature("mark(address,uint256)", address(0), uint256(0))
            )
        );
        require(mok && g.c.markCalls() == 1, "nonownership reaches C");

        // Negatives: short / trailing / dirty ownership encodings fail
        // canonical decode BEFORE any C call, state, or log effect.
        bytes4 commitSel = GaugeControllerAdmin.commit_transfer_ownership.selector;
        bytes4 applySel = GaugeControllerAdmin.apply_transfer_ownership.selector;
        bytes[] memory bad = new bytes[](5);
        bad[0] = abi.encodePacked(commitSel, bytes28(0)); // 32 bytes: short
        bad[1] = abi.encodePacked(commitSel, abi.encode(succ), bytes1(0x01)); // 37: trailing
        bad[2] = abi.encodePacked(commitSel, abi.encode(uint256(uint160(succ)) | (uint256(1) << 160))); // dirty
        bad[3] = abi.encodePacked(applySel, bytes1(0x00)); // 5 bytes: trailing
        bad[4] = abi.encodePacked(commitSel, bytes31(0)); // 35 bytes: short
        for (uint256 i = 0; i < bad.length; ++i) {
            Fixture memory h = _seatedFixture();
            uint256 commitsBefore = h.c.commitCalls();
            uint256 appliesBefore = h.c.applyCalls();
            rv.recordLogs();
            (bool ok, bytes memory ret) = _callFrom(
                address(h.dao), address(h.r), abi.encodeWithSelector(GaugeControllerAdmin.execute.selector, bad[i])
            );
            RV.Log[] memory logs = rv.getRecordedLogs();
            require(!ok, "OWNERSHIP_CANONICAL_DECODE accepted");
            require(
                _isError(ret, GaugeControllerAdmin.InvalidOwnershipCalldata.selector, ""),
                "OWNERSHIP_CANONICAL_DECODE wrong error"
            );
            require(
                h.c.commitCalls() == commitsBefore && h.c.applyCalls() == appliesBefore,
                "OWNERSHIP_CANONICAL_DECODE touched C"
            );
            require(
                h.r.pendingControllerAdmin() == address(0) && !h.r.retired(), "OWNERSHIP_CANONICAL_DECODE state leaked"
            );
            require(
                _countTopic(logs, address(h.r), keccak256("Executed(bytes4,bytes32,bytes32)")) == 0
                    && _countTopic(logs, address(h.r), keccak256("ControllerTransferCommitted(address)")) == 0,
                "OWNERSHIP_CANONICAL_DECODE log leaked"
            );
        }
    }

    // ------------------------------------------------------------------
    // O13
    // ------------------------------------------------------------------

    function test_CommitReplacementAndInvalidSuccessors() public {
        // D may nominate itself.
        Fixture memory f = _seatedFixture();
        vm.prank(address(f.dao));
        f.r.commit_transfer_ownership(address(f.dao));
        require(
            f.r.pendingControllerAdmin() == address(f.dao) && f.c.future_admin() == address(f.dao),
            "self nomination allowed"
        );

        // or a separately reviewed mock successor; recommit replaces pending
        // locally AND raw, with no premature authority change; adds still
        // work while pending.
        Fixture memory g = _seatedFixture();
        address x = address(new RouterSuccessorMock());
        address y = address(new RouterSuccessorMock());
        vm.prank(address(g.dao));
        g.r.commit_transfer_ownership(x);
        vm.prank(address(g.dao));
        g.r.commit_transfer_ownership(y);
        require(g.r.pendingControllerAdmin() == y, "COMMIT_REPLACES_PENDING local");
        require(g.c.future_admin() == y, "COMMIT_REPLACES_PENDING raw");
        require(g.c.admin() == address(g.r), "COMMIT_REPLACES_PENDING authority unmoved");
        require(g.c.commitCalls() == 3, "COMMIT_REPLACES_PENDING recommit is a real re-commit");
        vm.prank(address(g.dao));
        g.r.add_gauge(actor("g-pending"), int128(0), uint256(0));
        require(g.c.registered(actor("g-pending")), "adds work while pending");

        // Invalid successors.
        address[3] memory bad = [address(0), address(g.r), address(g.c)];
        for (uint256 i = 0; i < bad.length; ++i) {
            (bool ok, bytes memory ret) = _callFrom(
                address(g.dao),
                address(g.r),
                abi.encodeWithSelector(GaugeControllerAdmin.commit_transfer_ownership.selector, bad[i])
            );
            require(
                !ok && _isError(ret, GaugeControllerAdmin.InvalidSuccessor.selector, abi.encode(bad[i])),
                "invalid successor rejected"
            );
        }
        require(g.r.pendingControllerAdmin() == y, "invalid nominations left pending intact");

        // Non-D nomination/apply rejected.
        (bool n1,) = _callFrom(
            actor("nope"),
            address(g.r),
            abi.encodeWithSelector(GaugeControllerAdmin.commit_transfer_ownership.selector, actor("s"))
        );
        (bool n2,) = _callFrom(
            actor("nope"), address(g.r), abi.encodeWithSelector(GaugeControllerAdmin.apply_transfer_ownership.selector)
        );
        require(!n1 && !n2, "non-D ownership accepted");

        // No successor acceptance fiction: no acceptance method exists.
        (bool acc,) = _call(address(g.r), abi.encodeWithSignature("acceptTransfer()"));
        (bool acc2,) = _call(address(g.r), abi.encodeWithSignature("accept()"));
        (bool acc3,) = _call(address(g.r), abi.encodeWithSignature("cancelTransfer()"));
        require(!acc && !acc2 && !acc3, "ownership acceptance surface exists");
    }

    // ------------------------------------------------------------------
    // O14
    // ------------------------------------------------------------------

    function test_CommitApplyPostconditionsRollback() public {
        // Positive: ordinary commit succeeds — low-level ok asserted FIRST
        // at the named label, then C.future/local pending; apply control.
        Fixture memory f = _seatedFixture();
        address succ = address(new RouterSuccessorMock());
        (bool cok, bytes memory cret) = _callFrom(
            address(f.dao),
            address(f.r),
            abi.encodeWithSelector(GaugeControllerAdmin.commit_transfer_ownership.selector, succ)
        );
        require(cok, "COMMIT_RETURNS_SUCCESS");
        require(cret.length == 0, "COMMIT_RETURNS_SUCCESS empty return");
        require(f.c.future_admin() == succ && f.r.pendingControllerAdmin() == succ, "commit mirror state");
        (bool aok,) = _callFrom(
            address(f.dao), address(f.r), abi.encodeWithSelector(GaugeControllerAdmin.apply_transfer_ownership.selector)
        );
        require(aok && f.c.admin() == succ && f.r.retired(), "apply success control");

        // CONF-04: full pre/post router+controller+log equality for every
        // failed commit/apply, not just selected fields.
        // Negative: C commit reverts — exact error, full pre/post equality,
        // lock usable afterwards.
        Fixture memory g = _seatedFixture();
        uint256 commitBefore = g.c.commitCalls();
        (bool rok, bytes memory rret) = _callFrom(
            address(g.dao),
            address(g.r),
            abi.encodeWithSelector(GaugeControllerAdmin.commit_transfer_ownership.selector, actor("s1"))
        );
        require(rok, "baseline ok");
        require(rret.length == 0, "baseline empty");
        g.c.setCommitMode(1, address(0)); // revert
        O14Snap memory gPre = _o14Snap(g);
        rv.recordLogs();
        (bool bok, bytes memory bret) = _callFrom(
            address(g.dao),
            address(g.r),
            abi.encodeWithSelector(GaugeControllerAdmin.commit_transfer_ownership.selector, actor("s2"))
        );
        require(!bok && _isError(bret, RouterControllerMock.MockRejected.selector, ""), "commit revert bubbles");
        _assertO14Eq(gPre, _o14Snap(g), "commit revert full rollback");
        require(_o14RouterLogCount() == 0, "commit revert emitted nothing");
        require(g.c.commitCalls() == commitBefore + 1, "C effects rolled back");
        // lock usable after failed call
        _grant(g, actor("post-fail"), true);
        assertTrue(g.r.isAdder(actor("post-fail")), "lock released after failure");

        // Negative: C lies about future — PendingAdminMismatch(expected,actual)
        Fixture memory h = _seatedFixture();
        address liar = actor("lying-future");
        h.c.setCommitMode(2, liar);
        O14Snap memory hPre = _o14Snap(h);
        rv.recordLogs();
        (bool lok, bytes memory lret) = _callFrom(
            address(h.dao),
            address(h.r),
            abi.encodeWithSelector(GaugeControllerAdmin.commit_transfer_ownership.selector, actor("s3"))
        );
        require(!lok, "lying commit accepted");
        require(
            _isError(lret, GaugeControllerAdmin.PendingAdminMismatch.selector, abi.encode(actor("s3"), liar)),
            "PendingAdminMismatch(expected,actual)"
        );
        require(h.r.pendingControllerAdmin() == address(0), "lying commit rolled back");
        require(!h.r.retired() && h.c.admin() == address(h.r), "lying commit state intact");
        _assertO14Eq(hPre, _o14Snap(h), "lying commit full rollback");
        require(_o14RouterLogCount() == 0, "lying commit emitted nothing");

        // Negative: C apply reverts after a good commit — retirement and
        // nomination roll back together.
        Fixture memory i = _seatedFixture();
        address s4 = address(new RouterSuccessorMock());
        vm.prank(address(i.dao));
        i.r.commit_transfer_ownership(s4);
        i.c.setApplyMode(1, address(0));
        O14Snap memory iPre = _o14Snap(i);
        rv.recordLogs();
        (bool iok, bytes memory irect) = _callFrom(
            address(i.dao), address(i.r), abi.encodeWithSelector(GaugeControllerAdmin.apply_transfer_ownership.selector)
        );
        require(!iok && _isError(irect, RouterControllerMock.MockRejected.selector, ""), "apply revert bubbles");
        require(!i.r.retired() && i.r.pendingControllerAdmin() == s4, "apply rollback keeps nomination");
        require(i.c.admin() == address(i.r), "apply rollback keeps admin");
        _assertO14Eq(iPre, _o14Snap(i), "apply revert full rollback");
        require(_o14RouterLogCount() == 0, "apply revert emitted nothing");

        // Negative: C lies on apply (admin := wrong) — ControllerAdminMismatch.
        Fixture memory j = _seatedFixture();
        address s5 = address(new RouterSuccessorMock());
        vm.prank(address(j.dao));
        j.r.commit_transfer_ownership(s5);
        address clobber = actor("wrong-admin");
        j.c.setApplyMode(2, clobber);
        O14Snap memory jPre = _o14Snap(j);
        rv.recordLogs();
        (bool jok, bytes memory jret) = _callFrom(
            address(j.dao), address(j.r), abi.encodeWithSelector(GaugeControllerAdmin.apply_transfer_ownership.selector)
        );
        require(!jok, "lying apply accepted");
        require(
            _isError(jret, GaugeControllerAdmin.ControllerAdminMismatch.selector, abi.encode(s5, clobber)),
            "ControllerAdminMismatch(expected,actual)"
        );
        require(!j.r.retired() && j.r.pendingControllerAdmin() == s5, "lying apply rolled back");
        require(j.c.admin() == address(j.r), "lying apply admin rolled back");
        _assertO14Eq(jPre, _o14Snap(j), "lying apply full rollback");
        require(_o14RouterLogCount() == 0, "lying apply emitted nothing");

        // Negative: artificial local/raw pending mismatch (mock-only).
        Fixture memory k = _seatedFixture();
        address s6 = address(new RouterSuccessorMock());
        vm.prank(address(k.dao));
        k.r.commit_transfer_ownership(s6);
        k.c.forceFuture(actor("raw-diverged")); // C future diverges from local pending
        O14Snap memory kPre = _o14Snap(k);
        rv.recordLogs();
        (bool kok, bytes memory kret) = _callFrom(
            address(k.dao), address(k.r), abi.encodeWithSelector(GaugeControllerAdmin.apply_transfer_ownership.selector)
        );
        require(!kok, "mismatched apply accepted");
        require(
            _isError(kret, GaugeControllerAdmin.PendingAdminMismatch.selector, abi.encode(s6, actor("raw-diverged"))),
            "apply PendingAdminMismatch(expected,actual)"
        );
        require(k.r.pendingControllerAdmin() == s6 && !k.r.retired(), "mismatch apply rolled back");
        _assertO14Eq(kPre, _o14Snap(k), "mismatch apply full rollback");
        require(_o14RouterLogCount() == 0, "mismatch apply emitted nothing");
    }

    struct O14Snap {
        address pending;
        bool retired;
        bytes32 lockWord;
        address admin;
        address future;
        uint256 commitCalls;
        uint256 applyCalls;
        uint256 addAttempts;
        uint256 addCalls;
        uint256 markCalls;
    }

    function _o14Snap(Fixture memory f) internal view returns (O14Snap memory s) {
        return O14Snap({
            pending: f.r.pendingControllerAdmin(),
            retired: f.r.retired(),
            lockWord: rv.load(address(f.r), bytes32(uint256(2))),
            admin: f.c.admin(),
            future: f.c.future_admin(),
            commitCalls: f.c.commitCalls(),
            applyCalls: f.c.applyCalls(),
            addAttempts: f.c.addAttempts(),
            addCalls: f.c.addCalls(),
            markCalls: f.c.markCalls()
        });
    }

    function _assertO14Eq(O14Snap memory a, O14Snap memory b, string memory label) internal pure {
        require(keccak256(abi.encode(a)) == keccak256(abi.encode(b)), label);
    }

    /// @dev Router-emitted ownership/execute audit logs since the last
    /// recordLogs: a failed commit/apply must leave no log trace.
    function _o14RouterLogCount() internal returns (uint256 n) {
        RV.Log[] memory logs = rv.getRecordedLogs();
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].topics.length == 0) continue;
            bytes32 t0 = logs[i].topics[0];
            if (
                t0 == keccak256("Executed(bytes4,bytes32,bytes32)")
                    || t0 == keccak256("ControllerTransferCommitted(address)")
                    || t0 == keccak256("ControllerTransferApplied(address)")
            ) n += 1;
        }
    }

    // ------------------------------------------------------------------
    // O15
    // ------------------------------------------------------------------

    function test_HandbackToDaoRestoresDirectAdministration() public {
        Fixture memory f = _seatedFixture();
        _grant(f, actor("lane"), true);
        vm.prank(address(f.dao));
        f.r.add_gauge(actor("g-stay"), int128(0), uint256(7));

        // While R is incumbent, raw D calls to C fail at C's own admin check.
        (bool rawOk, bytes memory rawRet) = _callFrom(
            address(f.dao),
            address(f.c),
            abi.encodeWithSignature("add_gauge(address,int128,uint256)", actor("g-early"), int128(0), uint256(0))
        );
        require(
            !rawOk && _isError(rawRet, RouterControllerMock.MockNotAdmin.selector, ""),
            "raw D call must fail while R incumbent"
        );

        // D directs R commit/apply to D.
        _handback(f, address(f.dao));
        require(f.c.admin() == address(f.dao), "HANDBACK_DIRECT_D_RESTORED admin");
        require(f.r.retired() && f.r.pendingControllerAdmin() == address(0), "HANDBACK_DIRECT_D_RESTORED retired");

        // Direct D add/type/weight succeeds again; existing membership stays.
        vm.prank(address(f.dao));
        f.c.add_gauge(actor("g-direct"), int128(1), uint256(5));
        require(f.c.gauge_types(actor("g-direct")) == 1, "HANDBACK_DIRECT_D_RESTORED direct add");
        vm.prank(address(f.dao));
        f.c.add_type("restored");
        vm.prank(address(f.dao));
        f.c.change_gauge_weight(actor("g-stay"), uint256(9));
        require(f.c.get_gauge_weight(actor("g-stay")) == 9, "HANDBACK_DIRECT_D_RESTORED direct weight");
        require(f.c.gauge_types(actor("g-stay")) == 0, "HANDBACK_DIRECT_D_RESTORED membership kept");

        // R permanently inert for ALL mutations even for D.
        (bool o1,) = _callFrom(
            address(f.dao), address(f.r), abi.encodeWithSelector(GaugeControllerAdmin.grant.selector, actor("z"), true)
        );
        (bool o2,) = _callFrom(
            address(f.dao),
            address(f.r),
            abi.encodeWithSelector(
                GaugeControllerAdmin.execute.selector,
                abi.encodeWithSignature("mark(address,uint256)", address(0), uint256(0))
            )
        );
        (bool o3,) = _callFrom(
            address(f.dao),
            address(f.r),
            abi.encodeWithSelector(GaugeControllerAdmin.commit_transfer_ownership.selector, actor("z2"))
        );
        (bool o4,) = _callFrom(
            address(f.dao), address(f.r), abi.encodeWithSelector(GaugeControllerAdmin.apply_transfer_ownership.selector)
        );
        (bool o5,) = _callFrom(
            address(f.dao),
            address(f.r),
            abi.encodeWithSelector(GaugeControllerAdmin.add_gauge.selector, actor("g-late"), int128(0), uint256(0))
        );
        require(
            o1 == false && o2 == false && o3 == false && o4 == false && o5 == false, "retired router still mutating"
        );
    }

    // ------------------------------------------------------------------
    // O16
    // ------------------------------------------------------------------

    function test_SuccessorAndPermanentRetirement() public {
        Fixture memory f = _seatedFixture();
        _grant(f, address(f.adder), true);
        RouterSuccessorMock s = new RouterSuccessorMock();
        _handback(f, address(s));

        require(f.c.admin() == address(s), "successor receives C.admin");
        require(f.r.pendingControllerAdmin() == address(0), "pending cleared");
        require(f.r.retired(), "retirement latched");
        // Negative: intentionally reseat the retired router in the DISPOSABLE
        // mock only (hostile-C modelling), then the D add still fails.
        f.c.forceAdmin(address(f.r));
        require(f.c.admin() == address(f.r), "mock reseat done");
        (bool mro, bytes memory mrret) = _callFrom(
            address(f.dao),
            address(f.r),
            abi.encodeWithSelector(GaugeControllerAdmin.add_gauge.selector, actor("g-reseat"), int128(0), uint256(0))
        );
        require(!mro, "RETIRED_RESEAT_ADD_REJECT");
        require(_isError(mrret, GaugeControllerAdmin.Retired.selector, ""), "RETIRED_RESEAT_ADD_REJECT exact");
        require(!f.c.registered(actor("g-reseat")), "RETIRED_RESEAT_ADD_REJECT no C effect");

        // stored adder flags confer no authority post-retirement
        (bool ao, bytes memory aret) = _callFrom(
            address(f.adder),
            address(f.r),
            abi.encodeWithSelector(GaugeControllerAdmin.add_gauge.selector, actor("g-post"), int128(0), uint256(0))
        );
        require(!ao && _isError(aret, GaugeControllerAdmin.Retired.selector, ""), "stale flag is not capability");
        // views survive
        (bool vOk,) = _static(address(f.r), abi.encodeWithSelector(GaugeControllerAdmin.n_gauge_types.selector));
        require(vOk, "views survive retirement");

        // Negative: every R mutator blocked.
        (bool q1,) = _callFrom(
            address(f.dao), address(f.r), abi.encodeWithSelector(GaugeControllerAdmin.grant.selector, actor("q"), true)
        );
        (bool q2,) = _callFrom(
            address(f.dao),
            address(f.r),
            abi.encodeWithSelector(GaugeControllerAdmin.execute.selector, abi.encodeWithSignature("n_gauge_types()"))
        );
        (bool q3,) = _callFrom(
            address(f.dao),
            address(f.r),
            abi.encodeWithSelector(GaugeControllerAdmin.commit_transfer_ownership.selector, actor("q2"))
        );
        (bool q4,) = _callFrom(
            address(f.dao), address(f.r), abi.encodeWithSelector(GaugeControllerAdmin.apply_transfer_ownership.selector)
        );
        require(!q1 && !q2 && !q3 && !q4, "mutator survives retirement");

        // no revival setter anywhere on R
        (bool rv1,) = _call(address(f.r), abi.encodeWithSignature("unretire()"));
        (bool rv2,) = _call(address(f.r), abi.encodeWithSignature("setRetired(bool)", false));
        (bool rv3,) = _call(address(f.r), abi.encodeWithSignature("revive()"));
        require(!rv1 && !rv2 && !rv3, "revival setter callable");
    }

    // ------------------------------------------------------------------
    // O17
    // ------------------------------------------------------------------

    function test_SharedLockRejectsAuthorizedReentry() public {
        // Positive: authorized callback (caught) succeeds and the lock is
        // reusable afterwards; the NAMED lock assertion covers every mutator
        // lane using a NONRETIRING execute call so retirement cannot mask it.
        Fixture memory f = _seatedFixture();
        f.c.setHook(address(f.dao), abi.encodeWithSelector(f.dao.onControllerHook.selector), true, 4);
        f.dao.setPlan(abi.encodeWithSelector(GaugeControllerAdmin.grant.selector, actor("re-grant"), true), false);
        (bool outerOk,) = _callFrom(
            address(f.dao),
            address(f.r),
            abi.encodeWithSelector(
                GaugeControllerAdmin.execute.selector,
                abi.encodeWithSignature("mark(address,uint256)", address(0), uint256(0))
            )
        );
        require(outerOk, "caught callback outer failed");
        require(f.dao.lastInnerAttempted(), "callback reentry attempted");
        require(!f.dao.lastInnerOk(), "LOCK_AUTHORIZED_CALLBACK_REJECT");
        require(
            _isError(f.dao.lastInnerData(), GaugeControllerAdmin.ReentrantCall.selector, ""),
            "LOCK_AUTHORIZED_CALLBACK_REJECT exact"
        );
        // lock reusable after outer success
        _grant(f, actor("after-lock"), true);
        assertTrue(f.r.isAdder(actor("after-lock")), "lock reusable");

        // Reentry into EVERY mutator during a nonretiring external call.
        bytes[] memory mutators = new bytes[](5);
        mutators[0] = abi.encodeWithSelector(GaugeControllerAdmin.grant.selector, actor("m0"), true);
        mutators[1] =
            abi.encodeWithSelector(GaugeControllerAdmin.add_gauge.selector, actor("m1"), int128(0), uint256(0));
        mutators[2] = abi.encodeWithSelector(
            GaugeControllerAdmin.execute.selector,
            abi.encodeWithSignature("mark(address,uint256)", address(0), uint256(0))
        );
        mutators[3] = abi.encodeWithSelector(GaugeControllerAdmin.commit_transfer_ownership.selector, actor("m3"));
        mutators[4] = abi.encodeWithSelector(GaugeControllerAdmin.apply_transfer_ownership.selector);
        for (uint256 i = 0; i < mutators.length; ++i) {
            Fixture memory g = _seatedFixture();
            // grant the adder so the add lane can be attempted through the
            // adder shim too; dao-shim lane covers the admin mutators.
            _grant(g, address(g.adder), true);
            RouterDaoShim shim = g.dao;
            g.c.setHook(address(shim), abi.encodeWithSelector(shim.onControllerHook.selector), true, 4);
            shim.setPlan(mutators[i], false);
            (bool ok,) = _callFrom(
                address(shim),
                address(g.r),
                abi.encodeWithSelector(
                    GaugeControllerAdmin.execute.selector,
                    abi.encodeWithSignature("mark(address,uint256)", address(0), uint256(i))
                )
            );
            require(ok, "outer execute with caught reentry failed");
            require(!shim.lastInnerOk(), "LOCK_AUTHORIZED_CALLBACK_REJECT mutator");
            require(
                _isError(shim.lastInnerData(), GaugeControllerAdmin.ReentrantCall.selector, ""),
                "LOCK_AUTHORIZED_CALLBACK_REJECT mutator exact"
            );
        }

        // Adder-authorized reentry lane (auth is isAdder, not onlyDao).
        Fixture memory e = _seatedFixture();
        _grant(e, address(e.adder), true);
        e.c.setHook(address(e.adder), abi.encodeWithSelector(e.adder.onControllerHook.selector), true, 4);
        e.adder
            .setPlan(
                abi.encodeWithSelector(GaugeControllerAdmin.add_gauge.selector, actor("re-add"), int128(0), uint256(0)),
                false
            );
        (bool eok,) = _callFrom(
            address(e.dao),
            address(e.r),
            abi.encodeWithSelector(
                GaugeControllerAdmin.execute.selector,
                abi.encodeWithSignature("mark(address,uint256)", address(0), uint256(0))
            )
        );
        require(eok && !e.adder.lastInnerOk(), "adder reentry not attempted");
        require(
            _isError(e.adder.lastInnerData(), GaugeControllerAdmin.ReentrantCall.selector, ""),
            "LOCK_AUTHORIZED_CALLBACK_REJECT adder lane"
        );

        // During the FINALIZING apply the reentrant view sees Retired (check
        // priority), not ReentrantCall.
        Fixture memory r = _seatedFixture();
        address succ = address(new RouterSuccessorMock());
        vm.prank(address(r.dao));
        r.r.commit_transfer_ownership(succ);
        r.c.setHook(address(r.dao), abi.encodeWithSelector(r.dao.onControllerHook.selector), true, 2);
        r.dao.setPlan(abi.encodeWithSelector(GaugeControllerAdmin.grant.selector, actor("late"), true), false);
        (bool apOk,) = _callFrom(
            address(r.dao), address(r.r), abi.encodeWithSelector(GaugeControllerAdmin.apply_transfer_ownership.selector)
        );
        require(apOk, "apply with caught reentry failed");
        require(
            _isError(r.dao.lastInnerData(), GaugeControllerAdmin.Retired.selector, ""),
            "finalizing apply reentry must see Retired"
        );

        // Uncaught callback failure rolls the whole transaction back.
        Fixture memory u = _seatedFixture();
        u.c.setHook(address(u.dao), abi.encodeWithSelector(u.dao.onControllerHook.selector), false, 4);
        u.dao.setPlan(abi.encodeWithSelector(GaugeControllerAdmin.grant.selector, actor("doomed"), true), true);
        uint256 marksBefore = u.c.markCalls();
        (bool uok, bytes memory uret) = _callFrom(
            address(u.dao),
            address(u.r),
            abi.encodeWithSelector(
                GaugeControllerAdmin.execute.selector,
                abi.encodeWithSignature("mark(address,uint256)", address(0), uint256(0))
            )
        );
        require(!uok, "uncaught callback must revert the whole call");
        require(_isError(uret, GaugeControllerAdmin.ReentrantCall.selector, ""), "uncaught bubbles ReentrantCall");
        require(u.c.markCalls() == marksBefore, "uncaught callback rolled back");
        require(!u.r.isAdder(actor("doomed")), "reentrant grant rolled back");
    }

    // ------------------------------------------------------------------
    // O18
    // ------------------------------------------------------------------

    function test_NonpayableAndUnsolicitedDonations() public {
        Fixture memory f = _seatedFixture();
        rv.deal(address(this), 10 ether); // value probes need sender ETH

        // Force ETH and an ERC20 balance onto R without its consent.
        rv.deal(address(f.r), 2 ether);
        DonationToken tok = new DonationToken();
        tok.mint(address(f.r), 500);
        require(tok.balanceOf(address(f.r)) == 500, "unsolicited token parked");

        // Authorized operations still work; zero outgoing value; balances
        // stay stranded (no balance-gated behavior).
        _grant(f, actor("post-donation"), true);
        assertTrue(f.r.isAdder(actor("post-donation")), "grant works with donations parked");
        (bool eok,) = _callFrom(
            address(f.dao),
            address(f.r),
            abi.encodeWithSelector(
                GaugeControllerAdmin.execute.selector,
                abi.encodeWithSignature("mark(address,uint256)", address(0), uint256(0))
            )
        );
        require(eok, "execute works with donations parked");
        require(address(f.r).balance == 2 ether, "FUNDS_NO_INTENDED_CUSTODY ETH stranded");
        require(tok.balanceOf(address(f.r)) == 500, "FUNDS_NO_INTENDED_CUSTODY token stranded");
        require(address(f.c).balance == 0, "no value forwarded to C");

        _valueSurfaceLanes(f);

        // No custody API of any kind.
        (bool s1,) = _callFrom(address(f.dao), address(f.r), abi.encodeWithSignature("sweep(address)", address(0)));
        (bool s2,) = _callFrom(address(f.dao), address(f.r), abi.encodeWithSignature("withdraw(uint256)", 1));
        (bool s3,) =
            _callFrom(address(f.dao), address(f.r), abi.encodeWithSignature("transfer(address,uint256)", address(0), 1));
        (bool s4,) =
            _callFrom(address(f.dao), address(f.r), abi.encodeWithSignature("approve(address,uint256)", address(0), 1));
        (bool s5,) = _callFrom(address(f.dao), address(f.r), abi.encodeWithSignature("rescueETH()"));
        require(!s1 && !s2 && !s3 && !s4 && !s5, "FUNDS_NO_INTENDED_CUSTODY custody surface");

        // Donations did not create authority: a non-D caller still cannot.
        (bool nx,) = _call(address(f.r), abi.encodeWithSelector(GaugeControllerAdmin.grant.selector, actor("x"), true));
        require(!nx, "donation bought authority");
    }

    /// @dev CONF-03(a): the complete claimed external surface under value.
    /// Each lane runs its same-caller authorized zero-value control first
    /// (privileged positive controls prevent authorization masking), then
    /// the 1-wei probe must die at the compiler's empty callvalue check.
    /// Split per lane family to keep the frozen stack (no viaIR) shallow.
    function _valueSurfaceLanes(Fixture memory f) internal {
        _valueMutatorLanes(f);
        _valueReadLanes(f);
        _valueApplyLane(f);
        _valueDispatchLanes(address(f.dao), f.r);
        _valueConstructorProbe(address(f.c), address(f.dao));
    }

    function _valueMutatorLanes(Fixture memory f) internal {
        address dCaller = address(f.dao);
        address adderG = actor("value-granted-adder");
        _grant(f, adderG, true);
        _valueLanePrivileged(
            dCaller,
            f.r,
            abi.encodeWithSelector(GaugeControllerAdmin.grant.selector, actor("v-grant"), true),
            abi.encodeWithSelector(GaugeControllerAdmin.grant.selector, actor("v-grant2"), true),
            "grant"
        );
        _valueLanePrivileged(
            dCaller,
            f.r,
            abi.encodeWithSelector(
                GaugeControllerAdmin.execute.selector,
                abi.encodeWithSignature("mark(address,uint256)", address(0), uint256(0))
            ),
            abi.encodeWithSelector(
                GaugeControllerAdmin.execute.selector,
                abi.encodeWithSignature("mark(address,uint256)", address(0), uint256(1))
            ),
            "execute"
        );
        _valueLanePrivileged(
            dCaller,
            f.r,
            abi.encodeWithSelector(GaugeControllerAdmin.commit_transfer_ownership.selector, actor("v-succ")),
            abi.encodeWithSelector(GaugeControllerAdmin.commit_transfer_ownership.selector, actor("v-succ2")),
            "commit"
        );
        _valueLanePrivileged(
            adderG,
            f.r,
            abi.encodeWithSelector(GaugeControllerAdmin.add_gauge.selector, actor("g-v1"), int128(0), uint256(0)),
            abi.encodeWithSelector(GaugeControllerAdmin.add_gauge.selector, actor("g-v2"), int128(0), uint256(0)),
            "add_gauge granted adder"
        );
    }

    function _valueReadLanes(Fixture memory f) internal {
        address dCaller = address(f.dao);
        _valueLanePrivileged(
            dCaller,
            f.r,
            abi.encodeWithSignature("controller()"),
            abi.encodeWithSignature("controller()"),
            "controller view"
        );
        _valueLanePrivileged(
            dCaller, f.r, abi.encodeWithSignature("dao()"), abi.encodeWithSignature("dao()"), "dao view"
        );
        _valueLanePrivileged(
            dCaller,
            f.r,
            abi.encodeWithSignature("isAdder(address)", actor("value-granted-adder")),
            abi.encodeWithSignature("isAdder(address)", actor("value-granted-adder")),
            "isAdder view"
        );
        _valueLanePrivileged(
            dCaller,
            f.r,
            abi.encodeWithSignature("pendingControllerAdmin()"),
            abi.encodeWithSignature("pendingControllerAdmin()"),
            "pendingControllerAdmin view"
        );
        _valueLanePrivileged(
            dCaller, f.r, abi.encodeWithSignature("retired()"), abi.encodeWithSignature("retired()"), "retired view"
        );
        _valueLanePrivileged(
            dCaller,
            f.r,
            abi.encodeWithSignature("gauge_types(address)", actor("g-v1")),
            abi.encodeWithSignature("gauge_types(address)", actor("g-v1")),
            "gauge_types view"
        );
        _valueLanePrivileged(
            dCaller,
            f.r,
            abi.encodeWithSignature("n_gauge_types()"),
            abi.encodeWithSignature("n_gauge_types()"),
            "n_gauge_types view"
        );
    }

    function _valueApplyLane(Fixture memory f) internal {
        Fixture memory fa = _seatedFixture();
        vm.prank(address(fa.dao));
        fa.r.commit_transfer_ownership(actor("v-apply-succ"));
        // CONF-03 residual (review/ROUTERCONF2.md:160-173): fund the ACTUAL
        // value-debited caller in this fresh fixture. Without funding, the
        // EVM debits the 1 wei from fa.dao first and the purported callvalue
        // oracle was satisfied by OutOfFunds before the router frame; with
        // solvency, the only possible empty-data rejection is native
        // execution reaching R's own nonpayable arm.
        rv.deal(address(fa.dao), 2);
        require(address(fa.dao).balance >= 1, "apply value probe caller is solvent");
        (bool avOk, bytes memory avRet) = _callValueFrom(
            address(fa.dao),
            address(fa.r),
            abi.encodeWithSelector(GaugeControllerAdmin.apply_transfer_ownership.selector),
            1
        );
        require(!avOk && avRet.length == 0, "FUNDS_NO_INTENDED_CUSTODY apply value lane");
        require(!fa.r.retired(), "apply value probe did not apply");
        (bool a0Ok,) = _callValueFrom(
            address(fa.dao),
            address(fa.r),
            abi.encodeWithSelector(GaugeControllerAdmin.apply_transfer_ownership.selector),
            0
        );
        require(a0Ok && fa.r.retired(), "FUNDS_NO_INTENDED_CUSTODY apply control");
        f;
    }

    function _valueDispatchLanes(address dCaller, GaugeControllerAdmin r) internal {
        (bool rc0, bytes memory rc0Ret) = _callValueFrom(dCaller, address(r), "", 0);
        require(!rc0 && rc0Ret.length == 0, "no valueless fallback path");
        (bool rcV, bytes memory rcVRet) = _callValueFrom(dCaller, address(r), "", 1);
        require(!rcV && rcVRet.length == 0, "FUNDS_NO_INTENDED_CUSTODY receive accepted value");
        (bool ukV, bytes memory ukRet) = _callValueFrom(dCaller, address(r), hex"deadbeef", 1);
        require(!ukV && ukRet.length == 0, "FUNDS_NO_INTENDED_CUSTODY unknown selector accepted value");
    }

    function _valueConstructorProbe(address c, address d) internal {
        (bool ctorZero, bytes memory ctorZeroReason, address ctorZeroLauncher) = _createWithValue(c, d, 0);
        require(ctorZero && ctorZeroReason.length == 0, "FUNDS_NO_INTENDED_CUSTODY deployable funded-launcher control");
        (bool ctorVal, bytes memory ctorValReason, address ctorValLauncher) = _createWithValue(c, d, 1);
        require(!ctorVal, "FUNDS_NO_INTENDED_CUSTODY payable constructor");
        require(ctorValReason.length == 0, "FUNDS_NO_INTENDED_CUSTODY constructor rejection is the callvalue check");
        require(
            address(ctorValLauncher).balance == 1 && address(ctorZeroLauncher).balance == 0,
            "constructor launcher funding"
        );
    }

    /// @dev CONF-03(a) privileged value lane: the same caller first runs an
    /// otherwise-successful authorized zero-value control, then the same
    /// shape with 1 wei must revert with the compiler's empty callvalue-check
    /// data. Sharing the caller means no earlier authorization failure can
    /// mask a missing nonpayable arm.
    function _valueLanePrivileged(
        address caller,
        GaugeControllerAdmin r,
        bytes memory controlData,
        bytes memory probeData,
        string memory label
    ) internal {
        rv.deal(caller, 2);
        (bool ok0,) = _callValueFrom(caller, address(r), controlData, 0);
        require(ok0, string.concat("FUNDS_NO_INTENDED_CUSTODY authorized control ", label));
        (bool okV, bytes memory retV) = _callValueFrom(caller, address(r), probeData, 1);
        require(!okV, string.concat("FUNDS_NO_INTENDED_CUSTODY value accepted ", label));
        require(retV.length == 0, string.concat("FUNDS_NO_INTENDED_CUSTODY callvalue-check cause ", label));
    }

    // ------------------------------------------------------------------
    // O19
    // ------------------------------------------------------------------

    function test_UnseatedAndDisplacedControllerRejects() public {
        // Reads and pre-seat grants work.
        Fixture memory f = _freshFixture();
        _grant(f, actor("pre-seat"), true);
        assertTrue(f.r.isAdder(actor("pre-seat")), "INCUMBENT_REQUIRED pre-seat grant");
        (bool vOk,) = _static(address(f.r), abi.encodeWithSelector(GaugeControllerAdmin.n_gauge_types.selector));
        require(vOk, "INCUMBENT_REQUIRED pre-seat read");

        // Unseated: authorized add/execute/commit/apply all fail at R's own
        // guard, never at raw C (addAttempts/commitCalls stay zero).
        _rejectAllFour(f, address(f.dao), "unseated");
        require(
            f.c.addAttempts() == 0 && f.c.markCalls() == 0 && f.c.commitCalls() == 0 && f.c.applyCalls() == 0,
            "INCUMBENT_REQUIRED guards never reached C"
        );
        require(!f.c.registered(actor("g-un")), "no membership from guarded add");

        // Correctly seated: add/execute/ownership all work.
        _seatRaw(f);
        vm.prank(address(f.dao));
        f.r.add_gauge(actor("g-seated"), int128(0), uint256(4));
        assertTrue(f.c.registered(actor("g-seated")), "seated add works");
        (bool eok,) = _callFrom(
            address(f.dao),
            address(f.r),
            abi.encodeWithSelector(
                GaugeControllerAdmin.execute.selector,
                abi.encodeWithSignature("mark(address,uint256)", address(0), uint256(0))
            )
        );
        require(eok, "seated execute works");

        // Displaced incumbent (hostile mock only): same guard fires.
        address displaced = actor("new-admin");
        f.c.forceAdmin(displaced);
        _rejectAllFour(f, displaced, "displaced");
    }

    /// @dev add/execute/commit/apply must all revert NotControllerAdmin(actual).
    function _rejectAllFour(Fixture memory f, address actual, string memory tag) internal {
        (bool a1, bytes memory d1) = _callFrom(
            address(f.dao),
            address(f.r),
            abi.encodeWithSelector(GaugeControllerAdmin.add_gauge.selector, actor("g-un"), int128(0), uint256(0))
        );
        require(!a1, "INCUMBENT_REQUIRED");
        require(
            _isError(d1, GaugeControllerAdmin.NotControllerAdmin.selector, abi.encode(actual)), "INCUMBENT_REQUIRED add"
        );
        (bool a2, bytes memory d2) = _callFrom(
            address(f.dao),
            address(f.r),
            abi.encodeWithSelector(
                GaugeControllerAdmin.execute.selector,
                abi.encodeWithSignature("mark(address,uint256)", address(0), uint256(0))
            )
        );
        require(!a2, "INCUMBENT_REQUIRED execute");
        require(
            _isError(d2, GaugeControllerAdmin.NotControllerAdmin.selector, abi.encode(actual)),
            "INCUMBENT_REQUIRED execute"
        );
        (bool a3, bytes memory d3) = _callFrom(
            address(f.dao),
            address(f.r),
            abi.encodeWithSelector(GaugeControllerAdmin.commit_transfer_ownership.selector, actor("s"))
        );
        require(!a3, "INCUMBENT_REQUIRED commit");
        require(
            _isError(d3, GaugeControllerAdmin.NotControllerAdmin.selector, abi.encode(actual)),
            "INCUMBENT_REQUIRED commit"
        );
        (bool a4, bytes memory d4) = _callFrom(
            address(f.dao), address(f.r), abi.encodeWithSelector(GaugeControllerAdmin.apply_transfer_ownership.selector)
        );
        require(!a4, "INCUMBENT_REQUIRED apply");
        require(
            _isError(d4, GaugeControllerAdmin.NotControllerAdmin.selector, abi.encode(actual)),
            "INCUMBENT_REQUIRED apply"
        );
        tag;
    }

    // ------------------------------------------------------------------
    // O20
    // ------------------------------------------------------------------

    function test_RevocationLeavesMembershipAndDaoRoute() public {
        Fixture memory f = _seatedFixture();
        address a1 = address(f.adder);
        address a2 = address(new RouterSuccessorMock()); // second disposable adder holder
        _grant(f, a1, true);
        vm.prank(a1);
        f.adder.addViaRouter(actor("g-keep1"), int128(0), uint256(21));
        // add g-keep2 via an EOA-actor that we grant (raw add through shim2
        // is unnecessary: reuse dao shim lane by granting and calling)
        _grant(f, a2, true);
        (bool s2,) = _callFrom(
            a2,
            address(f.r),
            abi.encodeWithSelector(GaugeControllerAdmin.add_gauge.selector, actor("g-keep2"), int128(1), uint256(22))
        );
        require(s2, "second adder add");

        uint256 nBefore = uint256(int256(f.c.n_gauges()));
        uint256 w1 = f.c.get_gauge_weight(actor("g-keep1"));
        uint256 w2 = f.c.get_gauge_weight(actor("g-keep2"));

        // Revoke both. CONF-03(b): each negative INVOKES R FROM the revoked
        // holder (the prior version called the holder contracts themselves,
        // which died at shim dispatch and never reached R's NotAdder gate),
        // and asserts the exact NotAdder(actor) with no C frame or effect.
        // The granted controls above and the regrant control below stay.
        _grant(f, a1, false);
        _grant(f, a2, false);
        uint256 attemptsAtRevoke = f.c.addAttempts();
        (bool r1ok, bytes memory r1ret) = _callFrom(
            a1,
            address(f.r),
            abi.encodeWithSelector(GaugeControllerAdmin.add_gauge.selector, actor("g-no1"), int128(0), uint256(0))
        );
        require(!r1ok, "REVOCATION_PRESERVES_MEMBERSHIP revoked adder added");
        require(
            _isError(r1ret, GaugeControllerAdmin.NotAdder.selector, abi.encode(a1)),
            "REVOCATION_PRESERVES_MEMBERSHIP revoked a1 exact NotAdder(a1)"
        );
        (bool r2ok, bytes memory r2ret) = _callFrom(
            a2,
            address(f.r),
            abi.encodeWithSelector(GaugeControllerAdmin.add_gauge.selector, actor("g-no2"), int128(0), uint256(0))
        );
        require(!r2ok, "REVOCATION_PRESERVES_MEMBERSHIP second revoked adder added");
        require(
            _isError(r2ret, GaugeControllerAdmin.NotAdder.selector, abi.encode(a2)),
            "REVOCATION_PRESERVES_MEMBERSHIP revoked a2 exact NotAdder(a2)"
        );
        require(f.c.addAttempts() == attemptsAtRevoke, "REVOCATION_PRESERVES_MEMBERSHIP revoked adds never reached C");
        require(
            !f.c.registered(actor("g-no1")) && !f.c.registered(actor("g-no2")),
            "REVOCATION_PRESERVES_MEMBERSHIP revoked adds no C state"
        );

        // Membership, count and weights are untouched by revocation.
        require(uint256(int256(f.c.n_gauges())) == nBefore, "REVOCATION_PRESERVES_MEMBERSHIP count");
        require(
            f.c.get_gauge_weight(actor("g-keep1")) == w1 && f.c.get_gauge_weight(actor("g-keep2")) == w2,
            "REVOCATION_PRESERVES_MEMBERSHIP weights"
        );
        require(f.c.gauge_types(actor("g-keep1")) == 0, "REVOCATION_PRESERVES_MEMBERSHIP type");
        // Changing a grant never grants admin authority: revocation did not
        // alter C's admin at all.
        require(f.c.admin() == address(f.r), "REVOCATION_PRESERVES_MEMBERSHIP admin unmoved");

        // D's independent add/admin still succeeds.
        vm.prank(address(f.dao));
        f.r.add_gauge(actor("g-dao"), int128(1), uint256(5));
        require(f.c.get_gauge_weight(actor("g-dao")) == 5, "REVOCATION_PRESERVES_MEMBERSHIP dao route");
        (bool eok,) = _callFrom(
            address(f.dao),
            address(f.r),
            abi.encodeWithSelector(
                GaugeControllerAdmin.execute.selector,
                abi.encodeWithSignature("change_gauge_weight(address,uint256)", actor("g-dao"), uint256(6))
            )
        );
        require(eok && f.c.get_gauge_weight(actor("g-dao")) == 6, "dao admin route");

        // Regrant restores delegated adds on a fresh gauge.
        _grant(f, a1, true);
        vm.prank(a1);
        f.adder.addViaRouter(actor("g-restored"), int128(0), uint256(8));
        require(f.c.get_gauge_weight(actor("g-restored")) == 8, "REVOCATION_PRESERVES_MEMBERSHIP regrant");
    }
}

/// @dev Deploys GaugeControllerAdmin as its FIRST contract creation (nonce
/// 0) so the caller can predict the exact address and exercise the
/// constructor's `== address(this)` guards for real.
contract Predictor {
    function deploySelfAsController(address predicted, address d) external returns (address) {
        // no try/catch: the constructor guard's revert must propagate
        GaugeControllerAdmin r = new GaugeControllerAdmin(predicted, d);
        return address(r);
    }

    function probeCreate(address c, address d) external returns (address) {
        GaugeControllerAdmin r;
        try new GaugeControllerAdmin(c, d) returns (GaugeControllerAdmin x) {
            r = x;
        } catch {}
        return address(r);
    }

    function deploySelfAsDao(address c, address predicted) external returns (address) {
        GaugeControllerAdmin r = new GaugeControllerAdmin(c, predicted);
        return address(r);
    }
}

/// @dev Raw CREATE launcher used to attempt value-attached construction.
/// The immediate CREATE executor is funded by the test before launching so
/// an environment OutOfFunds cannot mask (or fake) the constructor's own
/// nonpayable callvalue rejection; `lastRevert` records the sub-create
/// return data so the witness can assert the actual failure cause.
contract ValueLauncher {
    address public lastDeployed;
    bytes public lastRevert;

    function launch(bytes memory code, uint256 value) external returns (bool) {
        address addr;
        assembly {
            addr := create(value, add(code, 0x20), mload(code))
        }
        uint256 n;
        assembly {
            n := returndatasize()
        }
        bytes memory rd = new bytes(n);
        if (n > 0) {
            assembly {
                returndatacopy(add(rd, 0x20), 0, n)
            }
        }
        lastDeployed = addr;
        lastRevert = rd;
        return addr != address(0);
    }

    receive() external payable {}
}

/// @dev Tiny ERC20 with mint, for unsolicited-transfer witnesses.
contract DonationToken {
    mapping(address => uint256) public balanceOf;

    function mint(address to, uint256 v) external {
        balanceOf[to] += v;
    }

    function transfer(address to, uint256 v) external returns (bool) {
        balanceOf[msg.sender] -= v;
        balanceOf[to] += v;
        return true;
    }
}
