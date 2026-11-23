// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Vm} from "./TestBase.sol";
import {CurveGaugeLister} from "../contracts/CurveGaugeLister.sol";
import {TrustedFactoryFixture} from "./TrustedFactoryFixture.sol";
import {MockERC20} from "../contracts/mocks/MockERC20.sol";
import {MockPool} from "../contracts/mocks/MockPool.sol";
import {MockListingController} from "../contracts/mocks/MockListingController.sol";
import {MockIncentivePlatform} from "../contracts/mocks/MockIncentivePlatform.sol";
import {
    AlwaysTrueTrustedValidator,
    NoSelectorValidator,
    ConfigurableTrustedValidator,
    GaugeValidationModuleModel,
    TrustedFactoryModel,
    FactoryClaimGauge,
    PoisonAddController,
    PreAdmissionObservingValidator
} from "./mocks/TrustedFactoryMocks.sol";

/// @title TrustedFactoryTest
/// @notice The eight no-bounty trust identities, ported with their names
/// unchanged from the retired V2 suite onto the amended V1 core
/// (plans/V1ALIGN-PLAN.md §4; V1ALIGN-WITNESSES.md §2): constructor
/// parameterization, exact target argument, legacy/non-factory policy,
/// untrusted-before-effects ordering, read-fault fail-closed normalization,
/// registry precedence, DAO-free-lane independence and admission-only
/// scoping. Bounty hook/report/claim scaffolding is not inherited; the
/// original V1 Listing/event and all-FD law is what these witnesses assert.
/// @dev SCOPE DISTINCTION (S04): these offline identities exercise CORE
/// BEHAVIOUR (the product's own ordering, error normalization and effect
/// law) against disclosed fixture models. Selected PINNED CASES (the two
/// fork identities at fork/TrustedFactory.t.sol) are the only place live
/// pinned state is observed. Current validator OWNER/MANAGER/POLICY values
/// are mutable upstream policy — reviewed operationally per
/// docs/DEPLOYMENT-PINS.md, never certified by a local fixture. Do not read
/// a fixture-policy cell as a live-policy certificate, or a pinned-case run
/// as core-behaviour coverage.
/// @dev Ordering cells follow plan §2.1: within the untrusted-before-effects
/// identity the healthy false-rejection cell runs first, then the
/// controller-poison cell BEFORE the transfer-poison cell, so the
/// after-add_gauge mutant fails at TF_BEFORE_ADD_GAUGE while the after-fee
/// mutant still passes that cell and later fails at TF_BEFORE_TRANSFER.
/// Named assertions wrap low-level call results (unexpected reverts fail AT
/// the named label, not at unlabelled setup), and every rejection cell
/// compares complete PRE-STATE snapshots — never only zeros. Staticcall
/// mocks maintain no call counters; argument identity is pinned by
/// exact-calldata revert gates and error identity.
contract TrustedFactoryTest is TrustedFactoryFixture {
    function setUp() public {
        setupTrustedWorld();
        crvUSD.mint(payer, FEE_AMOUNT * 24);
    }

    // ---------------------------------------------------------------
    // identity 1 — constructor pin and guards
    // ---------------------------------------------------------------

    function test_TF_ConstructorPinAndGuards() public {
        // TF_CHAIN_FIRST: a non-1 chain fails WrongChain FIRST, even with
        // arguments that violate later guards too (zero validator, EOA
        // validator). Seven arguments; no bounty argument/config/binding.
        bytes memory wantWrongChain = _wantE(CurveGaugeLister.WrongChain.selector);
        vm.chainId(31337);
        try new CurveGaugeLister(
            daoOwner,
            address(crvUSD),
            address(controller),
            address(fd),
            CurveGaugeLister.AdmissionConfig(address(registry), 8),
            CurveGaugeLister.PlatformConfig(address(votium), address(voteMarket), 5000),
            address(0)
        ) {
            assertTrue(false, "TF_CHAIN_FIRST: wrong-chain construction must revert");
        } catch (bytes memory rd) {
            bytesEq(rd, wantWrongChain, "TF_CHAIN_FIRST: WrongChain precedes every later guard");
        }
        try new CurveGaugeLister(
            daoOwner,
            address(crvUSD),
            address(controller),
            address(fd),
            CurveGaugeLister.AdmissionConfig(address(registry), 8),
            CurveGaugeLister.PlatformConfig(address(votium), address(voteMarket), 5000),
            actor("eoaValidator")
        ) {
            assertTrue(false, "TF_CHAIN_FIRST: wrong-chain EOA validator must revert");
        } catch (bytes memory rd) {
            bytesEq(rd, wantWrongChain, "TF_CHAIN_FIRST: WrongChain precedes the validator NoCode guard");
        }
        vm.chainId(1);

        // TF_PIN_NO_CODE: chain 1 with a zero validator fails exact
        // NoCode(address(0)); an EOA (no-code) input fails NoCode(validator).
        try new CurveGaugeLister(
            daoOwner,
            address(crvUSD),
            address(controller),
            address(fd),
            CurveGaugeLister.AdmissionConfig(address(registry), 8),
            CurveGaugeLister.PlatformConfig(address(votium), address(voteMarket), 5000),
            address(0)
        ) {
            assertTrue(false, "TF_PIN_NO_CODE: zero validator must be rejected");
        } catch (bytes memory rd) {
            bytesEq(
                rd,
                abi.encodeWithSelector(CurveGaugeLister.NoCode.selector, address(0)),
                "TF_PIN_NO_CODE: exact NoCode(address(0))"
            );
        }
        address eoaValidator = actor("eoaValidator");
        try new CurveGaugeLister(
            daoOwner,
            address(crvUSD),
            address(controller),
            address(fd),
            CurveGaugeLister.AdmissionConfig(address(registry), 8),
            CurveGaugeLister.PlatformConfig(address(votium), address(voteMarket), 5000),
            eoaValidator
        ) {
            assertTrue(false, "TF_PIN_NO_CODE: EOA validator must be rejected");
        } catch (bytes memory rd) {
            bytesEq(
                rd,
                abi.encodeWithSelector(CurveGaugeLister.NoCode.selector, eoaValidator),
                "TF_PIN_NO_CODE: code presence guard covers EOA inputs"
            );
        }

        // TF_PIN_EXACT: a code-bearing supplied checker is retained EXACTLY
        // and readable through the immutable getter; paused start preserved.
        ConfigurableTrustedValidator kept = new ConfigurableTrustedValidator();
        CurveGaugeLister coreA = _deployCore(address(controller), address(votium), address(voteMarket), address(kept));
        assertEq(coreA.trustedGaugeValidator(), address(kept), "TF_PIN_EXACT: supplied checker retained exactly");
        assertTrue(coreA.paused(), "TF_PIN_EXACT: fresh core starts paused");

        // TF_PIN_PARAMETERIZED: two DIFFERENT code-bearing checkers each land
        // on their own core — the pin is a constructor parameter, not a
        // hidden hardcoded address.
        AlwaysTrueTrustedValidator alt = new AlwaysTrueTrustedValidator();
        CurveGaugeLister coreB = _deployCore(address(controller), address(votium), address(voteMarket), address(alt));
        assertTrue(address(kept) != address(alt), "TF_PIN_PARAMETERIZED: distinct checkers");
        assertEq(coreB.trustedGaugeValidator(), address(alt), "TF_PIN_PARAMETERIZED: second pin honored");
        assertEq(coreA.trustedGaugeValidator(), address(kept), "TF_PIN_PARAMETERIZED: first pin unchanged");

        // TF_NO_CONSTRUCTOR_CHECK: a code-bearing checker whose validateGauge
        // unconditionally REVERTS still permits construction — there is no
        // candidate at construction time and no constructor validation read.
        ConfigurableTrustedValidator screaming = new ConfigurableTrustedValidator();
        screaming.setTopFault(ConfigurableTrustedValidator.TopFault.Revert);
        CurveGaugeLister coreC =
            _deployCore(address(controller), address(votium), address(voteMarket), address(screaming));
        assertEq(coreC.trustedGaugeValidator(), address(screaming), "TF_NO_CONSTRUCTOR_CHECK: reverting checker pinned");
        assertTrue(coreC.paused(), "TF_NO_CONSTRUCTOR_CHECK: construction succeeded paused");
    }

    // ---------------------------------------------------------------
    // identity 2 — trusted paid admission and the exact target argument
    // ---------------------------------------------------------------

    function test_TF_TrustedPaidAdmissionAndExactTarget() public {
        ConfigurableTrustedValidator v = new ConfigurableTrustedValidator();
        World memory w = _newWorld(address(v));
        Candidate memory c = _method1Candidate(v);
        // The checker accepts ONLY the exact gauge; pool, LP, factory and
        // caller are pairwise distinct from it.
        v.setArgumentGate(true, c.gauge);

        uint256 payerBefore = crvUSD.balanceOf(payer);
        vm.recordLogs();
        (bool ok, bytes memory ret) = _paidCall(w, payer, c);
        // TF_EXACT_GAUGE_ARGUMENT first, per the matrix argument-identity
        // rule: this cell fails if the intended predicate is replaced by the
        // incidental proposal selector (no such function on the checker ->
        // read fault) or by any other argument.
        _expectSucceeded(ok, ret, "TF_EXACT_GAUGE_ARGUMENT: only the exact gauge is accepted and admitted");
        Vm.Log[] memory logs = vm.getRecordedLogs();

        // The expected epoch is computed INDEPENDENTLY of the returned
        // record — the record's listingEpoch and the emitted epoch are both
        // checked against THIS value, never against each other.
        uint256 expectedEpoch = (block.timestamp / WEEK) * WEEK;

        // TF_TRUSTED_PAID_ACTIVE: full original 15-field Active listing,
        // controller type and zero raw weight.
        CurveGaugeLister.Listing memory rec = w.core_.getListing(c.gauge);
        assertEq(uint256(rec.status), uint256(CurveGaugeLister.Status.Active), "TF_TRUSTED_PAID_ACTIVE: Active");
        assertEq(rec.pool, c.pool, "TF_TRUSTED_PAID_ACTIVE: pool");
        assertEq(rec.lpToken, c.lp, "TF_TRUSTED_PAID_ACTIVE: lp");
        assertEq(rec.payer, payer, "TF_TRUSTED_PAID_ACTIVE: payer");
        assertEq(rec.admissionRegistry, address(registry), "TF_TRUSTED_PAID_ACTIVE: admission registry");
        assertEq(rec.gaugeType, int128(0), "TF_TRUSTED_PAID_ACTIVE: derived type");
        assertEq(uint256(rec.epochsReleased), 0, "TF_TRUSTED_PAID_ACTIVE: epochsReleased");
        assertEq(rec.deposited, FEE_AMOUNT, "TF_TRUSTED_PAID_ACTIVE: deposited");
        assertEq(rec.remaining, FEE_AMOUNT, "TF_TRUSTED_PAID_ACTIVE: remaining");
        assertEq(rec.released, 0, "TF_TRUSTED_PAID_ACTIVE: released");
        assertEq(rec.confiscated, 0, "TF_TRUSTED_PAID_ACTIVE: confiscated");
        // The paid record must carry the CONFIGURED venues and split
        // (PlatformConfig: votium=w.pv, voteMarket=w.pm, votiumBps=5000),
        // and the independently expected epoch. Deleting the
        // `rec.votium = plat.votium` assignment must fail HERE.
        assertEq(rec.votium, address(w.pv), "TF_TRUSTED_PAID_ACTIVE: votium is the configured venue");
        assertEq(rec.voteMarket, address(w.pm), "TF_TRUSTED_PAID_ACTIVE: voteMarket is the configured venue");
        assertEq(uint256(rec.votiumBps), 5000, "TF_TRUSTED_PAID_ACTIVE: votiumBps is the configured split");
        assertEq(rec.listingEpoch, expectedEpoch, "TF_TRUSTED_PAID_ACTIVE: listingEpoch independently expected");
        assertEq(w.ctl.gauge_types(c.gauge), int128(0), "TF_TRUSTED_PAID_ACTIVE: controller type");
        assertEq(w.ctl.get_gauge_weight(c.gauge), 0, "TF_TRUSTED_PAID_ACTIVE: raw weight zero at admission");

        // TF_EXACT_FEE_AND_MEMBERSHIP: exact 10,000e18 debit/credit,
        // totalEscrow, GaugeListed and controller membership.
        assertEq(crvUSD.balanceOf(payer), payerBefore - FEE_AMOUNT, "TF_EXACT_FEE_AND_MEMBERSHIP: payer debited FEE");
        assertEq(crvUSD.balanceOf(address(w.core_)), FEE_AMOUNT, "TF_EXACT_FEE_AND_MEMBERSHIP: core credited FEE");
        assertEq(w.core_.totalEscrow(), FEE_AMOUNT, "TF_EXACT_FEE_AND_MEMBERSHIP: totalEscrow FEE");
        _expectLog(logs, address(w.core_), T_GAUGE_LISTED, "TF_EXACT_FEE_AND_MEMBERSHIP: GaugeListed emitted");
        bool listed;
        for (uint256 i = 0; i < logs.length; ++i) {
            if (
                logs[i].emitter == address(w.core_) && logs[i].topics.length == 4 && logs[i].topics[0] == T_GAUGE_LISTED
            ) {
                listed = true;
                assertEq(uint256(logs[i].topics[1]), uint256(uint160(c.gauge)), "GaugeListed gauge topic");
                assertEq(uint256(logs[i].topics[2]), uint256(uint160(c.pool)), "GaugeListed pool topic");
                assertEq(uint256(logs[i].topics[3]), uint256(uint160(payer)), "GaugeListed payer topic");
                (int128 lgType, uint256 lEpoch, uint256 lFee, bool lDao) =
                    abi.decode(logs[i].data, (int128, uint256, uint256, bool));
                assertEq(lgType, int128(0), "GaugeListed type");
                assertEq(lFee, FEE_AMOUNT, "GaugeListed fee");
                assertFalse(lDao, "GaugeListed daoExempt false");
                assertEq(lEpoch, expectedEpoch, "GaugeListed epoch matches independently expected epoch");
            }
        }
        assertTrue(listed, "TF_EXACT_FEE_AND_MEMBERSHIP: GaugeListed payload fully decoded");

        // Negative argument controls: a checker that accepts only a DISTINCT
        // address rejects the product call — the lister passes the gauge and
        // NOTHING else (no pool/LP/factory/caller substitution, no
        // lister-side `gauge.factory()` call, no legacy fallback). Each wrong
        // argument is built from the ATTEMPTED candidate (S04): the gate
        // comparator and the call under test share one freshly deployed
        // world/candidate, so no cell silently compares against a prior
        // candidate's addresses.
        string[4] memory argNames = ["pool", "lp", "factory", "caller"];
        for (uint256 i = 0; i < argNames.length; ++i) {
            ConfigurableTrustedValidator vNeg = new ConfigurableTrustedValidator();
            World memory wn = _newWorld(address(vNeg));
            Candidate memory cn = _method1Candidate(vNeg);
            address wrongArg = i == 0 ? cn.pool : (i == 1 ? cn.lp : (i == 2 ? cn.factory : payer));
            assertTrue(wrongArg != cn.gauge, "negative control argument is distinct from the candidate gauge");
            vNeg.setArgumentGate(true, wrongArg);
            (bool nok, bytes memory nret) = _paidCall(wn, payer, cn);
            _expectRevertedWith(
                nok,
                nret,
                _wantCheckFailed(cn.gauge),
                string.concat(
                    "TF_EXACT_GAUGE_ARGUMENT: checker accepting only the ",
                    argNames[i],
                    " must not admit: the product argument is the gauge"
                )
            );
            // Sanity for the same candidate/core: with the gauge-gated
            // checker the identical call succeeds, pinning that the ONLY
            // difference is the accepted argument value.
            vNeg.setArgumentGate(true, cn.gauge);
            (bool yok, bytes memory yret) = _paidCall(wn, payer, cn);
            _expectSucceeded(yok, yret, "TF_EXACT_GAUGE_ARGUMENT: exact-gauge control admits");
        }
    }

    // ---------------------------------------------------------------
    // identity 3 — legacy distinct-LP route and non-factory policy
    // ---------------------------------------------------------------

    function test_TF_LegacyFactoryAndNonFactoryPolicy() public {
        // TF_LEGACY_DISTINCT_LP: method-2 direct-zero -> minter -> pool
        // reciprocal match succeeds with the LP distinct from the pool.
        ConfigurableTrustedValidator v = new ConfigurableTrustedValidator();
        World memory w = _newWorld(address(v));
        Candidate memory c = _legacyCandidate(v);
        assertTrue(c.lp != c.pool, "TF_LEGACY_DISTINCT_LP: LP is not the pool");
        (bool ok, bytes memory ret) = _paidCall(w, payer, c);
        _expectSucceeded(ok, ret, "TF_LEGACY_DISTINCT_LP: minter-route admission");
        assertEq(
            uint256(w.core_.getListing(c.gauge).status),
            uint256(CurveGaugeLister.Status.Active),
            "TF_LEGACY_DISTINCT_LP: Active record"
        );

        // Direct NONZERO wrong gauge: a successful direct response that is
        // not the candidate rejects — and only a successful ZERO response
        // could ever permit the minter fallback.
        ConfigurableTrustedValidator v2m = new ConfigurableTrustedValidator();
        World memory w2 = _newWorld(address(v2m));
        Candidate memory c2 = _legacyCandidate(v2m);
        TrustedFactoryModel(c2.factory).setGauge(c2.lp, actor("wrongGauge"));
        (bool nok1, bytes memory nret1) = _paidCall(w2, payer, c2);
        _expectRevertedWith(
            nok1, nret1, _wantUntrusted(c2.gauge), "TF_FACTORY_CLAIM_NOT_PROOF: direct nonzero wrong gauge is not proof"
        );

        // Faulting first lookup: a FAILED (not zero) direct read must NOT
        // fall back to the minter route even though that route would match
        // — establishing the no-lister-side-fallback shape as well (the
        // product never consults minter()/pool itself).
        ConfigurableTrustedValidator v3 = new ConfigurableTrustedValidator();
        World memory w3 = _newWorld(address(v3));
        Candidate memory c3 = _legacyCandidate(v3);
        TrustedFactoryModel(c3.factory).setGetGaugeRevert(c3.lp, true);
        (bool nok2, bytes memory nret2) = _paidCall(w3, payer, c3);
        _expectRevertedWith(
            nok2,
            nret2,
            _wantUntrusted(c3.gauge),
            "TF_FACTORY_CLAIM_NOT_PROOF: faulting first lookup does not permit fallback"
        );

        // Spoofed factory claim without reciprocal mapping: the gauge NAMES
        // the configured factory, but no reverse association matches it.
        ConfigurableTrustedValidator v4 = new ConfigurableTrustedValidator();
        World memory w4 = _newWorld(address(v4));
        Candidate memory c4 = _legacyCandidate(v4);
        TrustedFactoryModel(c4.factory).setGauge(c4.pool, address(0));
        (bool nok3, bytes memory nret3) = _paidCall(w4, payer, c4);
        _expectRevertedWith(
            nok3,
            nret3,
            _wantUntrusted(c4.gauge),
            "TF_FACTORY_CLAIM_NOT_PROOF: a factory claim without reciprocal mapping is not accepted"
        );

        // Factory with no configured policy, zero factory, no usable
        // factory(), and a plain non-factory gauge are all rejected on the
        // paid lane. Fixture-model policy semantics; the live equivalents
        // are certified by the two fork identities.
        ConfigurableTrustedValidator v5 = new ConfigurableTrustedValidator();
        World memory w5 = _newWorld(address(v5));
        Candidate memory c5 = _legacyCandidate(v5);
        GaugeValidationModuleModel dead = new GaugeValidationModuleModel();
        v5.setPolicy(c5.factory, address(dead), 0); // method 0: no configured policy
        (bool nok4, bytes memory nret4) = _paidCall(w5, payer, c5);
        _expectRevertedWith(
            nok4, nret4, _wantUntrusted(c5.gauge), "TF_NONFACTORY_PAID_REJECTED: factory without configured policy"
        );

        ConfigurableTrustedValidator v6 = new ConfigurableTrustedValidator();
        World memory w6 = _newWorld(address(v6));
        Candidate memory c6 = _legacyCandidate(v6);
        FactoryClaimGauge(c6.gauge).setFactory(address(0));
        (bool nok5, bytes memory nret5) = _paidCall(w6, payer, c6);
        _expectRevertedWith(
            nok5, nret5, _wantUntrusted(c6.gauge), "TF_NONFACTORY_PAID_REJECTED: zero factory is rejected"
        );

        ConfigurableTrustedValidator v7 = new ConfigurableTrustedValidator();
        World memory w7 = _newWorld(address(v7));
        Candidate memory c7 = _legacyCandidate(v7);
        FactoryClaimGauge(c7.gauge).setFactoryReadReverts(true);
        (bool nok6, bytes memory nret6) = _paidCall(w7, payer, c7);
        _expectRevertedWith(
            nok6, nret6, _wantUntrusted(c7.gauge), "TF_NONFACTORY_PAID_REJECTED: no usable factory() is rejected"
        );

        ConfigurableTrustedValidator v8 = new ConfigurableTrustedValidator();
        World memory w8 = _newWorld(address(v8));
        Candidate memory c8 = _plainCandidate();
        (bool nok7, bytes memory nret7) = _paidCall(w8, payer, c8);
        _expectRevertedWith(
            nok7, nret7, _wantUntrusted(c8.gauge), "TF_NONFACTORY_PAID_REJECTED: non-factory gauge on the paid lane"
        );
    }

    // ---------------------------------------------------------------
    // identity 4 — untrusted paid admission reverts before every effect
    // ---------------------------------------------------------------

    function test_TF_UntrustedPaidAdmissionBeforeEffects() public {
        // Cell order per the matrix: healthy false-rejection FIRST, then the
        // controller-poison cell BEFORE the transfer-poison cell, then the
        // readiness precedence cell. No hook prerequisite exists here.

        // (a) healthy false rejection + full snapshot equality.
        ConfigurableTrustedValidator v = new ConfigurableTrustedValidator();
        World memory w = _newWorld(address(v));
        Candidate memory c = _method1Candidate(v);
        // Authentic pool, healthy readiness, funded+approving payer and an
        // unused gauge keep the trust guard REACHABLE: the checker would
        // accept this exact gauge (argument gate armed on it) but answers
        // canonical false.
        v.setArgumentGate(true, c.gauge);
        v.setRejectAll(true);
        assertEq(w.pv.lister(), address(w.core_), "reachable: votium seated");
        assertEq(w.pm.lister(), address(w.core_), "reachable: votemarket seated");
        assertTrue(crvUSD.balanceOf(payer) >= FEE_AMOUNT, "reachable: payer funded");
        assertEq(crvUSD.allowance(payer, address(w.core_)), type(uint256).max, "reachable: payer approved");
        assertEq(uint256(w.core_.getListing(c.gauge).status), 0, "reachable: gauge unused");

        Snap memory s0 = _snap(w, c.gauge);
        vm.recordLogs();
        (bool ok, bytes memory ret) = _paidCall(w, payer, c);
        Vm.Log[] memory logsA = vm.getRecordedLogs();
        // TF_FALSE_REJECTS first: canonical false yields EXACTLY
        // UntrustedGauge(gauge).
        _expectRevertedWith(ok, ret, _wantUntrusted(c.gauge), "TF_FALSE_REJECTS: canonical false exact error");
        // TF_NO_CUSTODY_OR_LISTING: complete pre-state snapshot unchanged.
        _assertSnapUnchanged(s0, _snap(w, c.gauge), "TF_NO_CUSTODY_OR_LISTING: full snapshot unchanged");
        _expectNoLog(logsA, address(w.core_), T_GAUGE_LISTED, "TF_NO_CUSTODY_OR_LISTING: no persisted listing event");

        // Owner-paid calls are NOT exempt. The owner is explicitly funded
        // and approved so the ONLY reason the call can fail is the trust
        // guard itself (otherwise a mutant that moves the trust read after
        // the fee pull would die on the money precondition instead of the
        // poison cells that carry the ordering proof). The snapshot is
        // ACTOR-SPECIFIC (owner rows, not the ordinary payer's).
        crvUSD.mint(daoOwner, FEE_AMOUNT);
        vm.prank(daoOwner);
        crvUSD.approve(address(w.core_), FEE_AMOUNT);
        Snap memory sOwner = _snapActor(w, c.gauge, daoOwner);
        vm.recordLogs();
        (bool ook, bytes memory oret) = _paidCall(w, daoOwner, c);
        Vm.Log[] memory logsO = vm.getRecordedLogs();
        _expectRevertedWith(ook, oret, _wantUntrusted(c.gauge), "TF_OWNER_PAID_NOT_EXEMPT: owner pays the same law");
        _assertSnapUnchanged(
            sOwner, _snapActor(w, c.gauge, daoOwner), "TF_OWNER_PAID_NOT_EXEMPT: owner attempt changed nothing"
        );
        _expectNoLog(logsO, address(w.core_), T_GAUGE_LISTED, "TF_OWNER_PAID_NOT_EXEMPT: no persisted listing event");

        // (b) INDEPENDENT controller poison: an otherwise honest controller
        // whose add_gauge reverts with its own distinct sentinel. On the
        // correct product the trust error wins BEFORE the poison executes.
        ConfigurableTrustedValidator v2 = new ConfigurableTrustedValidator();
        PoisonAddController poisonCtl = new PoisonAddController(controllerDao, int128(2));
        poisonCtl.setPoisonAdd(true);
        World memory w2 = _newWorldWithController(address(v2), poisonCtl);
        Candidate memory c2 = _method1Candidate(v2);
        v2.setRejectAll(true);
        Snap memory s2 = _snap(w2, c2.gauge);
        (bool cok, bytes memory cret) = _paidCall(w2, payer, c2);
        _expectRevertedWith(
            cok, cret, _wantUntrusted(c2.gauge), "TF_BEFORE_ADD_GAUGE: trust error precedes the poisoned add_gauge"
        );
        _assertSnapUnchanged(s2, _snap(w2, c2.gauge), "TF_BEFORE_ADD_GAUGE: no listing/custody effects");

        // (c) INDEPENDENT transfer poison: transferFrom false-return makes
        // SafeToken revert with its own distinct sentinel error. The trust
        // error must win before the fee pull can even be attempted.
        ConfigurableTrustedValidator v3 = new ConfigurableTrustedValidator();
        World memory w3 = _newWorld(address(v3));
        Candidate memory c3 = _method1Candidate(v3);
        v3.setRejectAll(true);
        crvUSD.setTransferBehavior(0, true, false);
        Snap memory s3 = _snap(w3, c3.gauge);
        (bool tok, bytes memory tret) = _paidCall(w3, payer, c3);
        crvUSD.setTransferBehavior(0, false, false);
        _expectRevertedWith(
            tok, tret, _wantUntrusted(c3.gauge), "TF_BEFORE_TRANSFER: trust error precedes the poisoned transferFrom"
        );
        _assertSnapUnchanged(s3, _snap(w3, c3.gauge), "TF_BEFORE_TRANSFER: no custody/allowance effects");

        // (d) TF_BEFORE_READINESS: trust precedes paid-adapter binding.
        // A false checker against an UNBOUND positive-share endpoint must
        // still yield exactly UntrustedGauge — never PlatformNotReady —
        // proving the trust read runs before `_requireAdaptersBound`.
        _tf4ReadinessPrecedence();

        // (e) S04: ordering made directly observable from INSIDE the read
        // (post-revert equality alone does not prove pre-write ordering).
        _tf4ObservedPreWriteOrdering();
    }

    /// @dev Registry-authenticated candidate with no factory-policy wiring:
    // the observing validator witnesses effect ORDERING, not the reciprocal
    // proof, so the factory claim is never consulted (S04).
    function _observingCandidate() private returns (Candidate memory c) {
        c.lp = address(new MockERC20(18));
        c.pool = address(new MockPool());
        c.gauge = address(new FactoryClaimGauge(c.lp, address(0xDEAD)));
        c.factory = address(0xDEAD);
        c.slot = _nextSlot++ % 10;
        registry.setPool(c.pool, c.slot, c.lp, _coins2(), 2);
        registry.setGauge(c.pool, c.slot, 0, c.gauge, int128(0));
    }

    /// @dev Added matrix cell (S04; complete-observation form per CX-TRUST):
    /// a test-only validator OBSERVES the candidate's COMPLETE public
    /// `getListing` record (one keccak over the whole Listing — status and
    /// aggregate alone do not distinguish other already-written fields) and
    /// SEPARATELY the core's aggregate liability DURING the admission read,
    /// accepting only while both match the armed world. Cell 1 arms the
    /// pre-write world (all-zero Unlisted record hash, escrow 0): the honest
    /// call is admitted, so the acceptance itself is the mid-read observation
    /// of pre-write state. Cell 2 arms the complementary POST-WRITE world —
    /// the full written record (Active, fee/escrow cells, platform snapshot)
    /// plus escrow FEE — against an identical fresh world: the read observes
    /// the true pre-write state, matches neither, returns canonical false
    /// and the call reverts exactly UntrustedGauge. Together the cells make
    /// the ordering non-vacuous: a mutant moving the trust read after the
    /// StoredListing/totalEscrow writes flips which cell passes.
    function _tf4ObservedPreWriteOrdering() private {
        PreAdmissionObservingValidator obs = new PreAdmissionObservingValidator();
        MockListingController ctl = new MockListingController(controllerDao, int128(2));
        MockIncentivePlatform pv = new MockIncentivePlatform(address(crvUSD));
        MockIncentivePlatform pm = new MockIncentivePlatform(address(crvUSD));
        CurveGaugeLister core_ = _deployCore(address(ctl), address(pv), address(pm), address(obs));
        _bindAndUnpause(core_, ctl, address(pv), address(pm));
        Candidate memory c = _observingCandidate();
        // Pre-write world: the law's expectation is the ALL-ZERO Unlisted
        // record (status Unlisted zeroes every monetary/display cell) —
        // stated independently of the implementation's own read.
        CurveGaugeLister.Listing memory preWrite;
        obs.arm(address(core_), c.gauge, keccak256(abi.encode(preWrite)), 0);
        crvUSD.mint(payer, FEE_AMOUNT);
        World memory w = World({core_: core_, ctl: ctl, pv: pv, pm: pm});
        (bool ok, bytes memory ret) = _paidCall(w, payer, c);
        _expectSucceeded(ok, ret, "TF_OBSERVED_PRE_WRITE_ORDERING: read itself saw Unlisted/zero-liability state");
        assertEq(
            uint256(core_.getListing(c.gauge).status), 1, "TF_OBSERVED_PRE_WRITE_ORDERING: admitted record is Active"
        );
        assertEq(core_.totalEscrow(), FEE_AMOUNT, "TF_OBSERVED_PRE_WRITE_ORDERING: liability moved only after the read");

        PreAdmissionObservingValidator obs2 = new PreAdmissionObservingValidator();
        MockListingController ctl2 = new MockListingController(controllerDao, int128(2));
        MockIncentivePlatform pv2 = new MockIncentivePlatform(address(crvUSD));
        MockIncentivePlatform pm2 = new MockIncentivePlatform(address(crvUSD));
        CurveGaugeLister core2 = _deployCore(address(ctl2), address(pv2), address(pm2), address(obs2));
        _bindAndUnpause(core2, ctl2, address(pv2), address(pm2));
        Candidate memory c2 = _observingCandidate();
        // Arm the complementary POST-WRITE world: the complete record a
        // mutant that writes before reading would observe (paid-lane values
        // from the fixture law: exact fee, full remaining, configured
        // 5000-bps snapshot, floored listing epoch of this block) plus the
        // FEE liability. The honest product must fail here; only a mutant
        // that writes before reading would pass.
        CurveGaugeLister.Listing memory postWrite;
        postWrite.pool = c2.pool;
        postWrite.lpToken = c2.lp;
        postWrite.payer = payer;
        postWrite.admissionRegistry = address(registry);
        postWrite.gaugeType = int128(0);
        postWrite.listingEpoch = (block.timestamp / WEEK) * WEEK;
        postWrite.status = CurveGaugeLister.Status.Active;
        postWrite.epochsReleased = 0;
        postWrite.deposited = FEE_AMOUNT;
        postWrite.remaining = FEE_AMOUNT;
        postWrite.released = 0;
        postWrite.confiscated = 0;
        postWrite.votium = address(pv2);
        postWrite.voteMarket = address(pm2);
        postWrite.votiumBps = 5000;
        obs2.arm(address(core2), c2.gauge, keccak256(abi.encode(postWrite)), FEE_AMOUNT);
        crvUSD.mint(payer, FEE_AMOUNT);
        World memory w2 = World({core_: core2, ctl: ctl2, pv: pv2, pm: pm2});
        (bool nok, bytes memory nret) = _paidCall(w2, payer, c2);
        _expectRevertedWith(
            nok,
            nret,
            _wantUntrusted(c2.gauge),
            "TF_OBSERVED_PRE_WRITE_ORDERING: pre-write observation rejects the post-write arming"
        );
        assertEq(
            uint256(core2.getListing(c2.gauge).status), 0, "TF_OBSERVED_PRE_WRITE_ORDERING: control left no record"
        );
        assertEq(core2.totalEscrow(), 0, "TF_OBSERVED_PRE_WRITE_ORDERING: control left liability untouched");
    }

    /// @dev Added matrix cell: unbound AND misbound positive-share endpoints
    /// under a false checker; both keep the exact UntrustedGauge precedence.
    /// Split into two private cells to keep the frozen (no-viaIR) stack depth.
    function _tf4ReadinessPrecedence() private {
        _tf4UnboundReadiness();
        _tf4MisboundReadiness();
    }

    function _tf4UnboundReadiness() private {
        // Variant 1: fresh never-bound positive-share venues.
        ConfigurableTrustedValidator v = new ConfigurableTrustedValidator();
        MockListingController ctl = new MockListingController(controllerDao, int128(2));
        MockIncentivePlatform pv = new MockIncentivePlatform(address(crvUSD));
        MockIncentivePlatform pm = new MockIncentivePlatform(address(crvUSD));
        CurveGaugeLister core = _deployCore(address(ctl), address(pv), address(pm), address(v));
        // Seat the controller and fund/approve the payer, but NEVER bind the
        // venues: readiness would revert PlatformNotReady if reached.
        vm.prank(controllerDao);
        ctl.setLister(address(core));
        vm.prank(daoOwner);
        core.setPaused(false);
        vm.startPrank(payer);
        crvUSD.approve(address(core), type(uint256).max);
        vm.stopPrank();
        Candidate memory c = _method1Candidate(v);
        v.setRejectAll(true);
        World memory w = World({core_: core, ctl: ctl, pv: pv, pm: pm});
        _assertBeforeReadiness(w, c);
    }

    function _tf4MisboundReadiness() private {
        // Variant 2: venues bound to a DECOY lister (misbound readiness
        // fault) with the same false checker.
        ConfigurableTrustedValidator v = new ConfigurableTrustedValidator();
        MockListingController ctl = new MockListingController(controllerDao, int128(2));
        MockIncentivePlatform pv2 = new MockIncentivePlatform(address(crvUSD));
        MockIncentivePlatform pm2 = new MockIncentivePlatform(address(crvUSD));
        CurveGaugeLister core2 = _deployCore(address(ctl), address(pv2), address(pm2), address(v));
        CurveGaugeLister decoy = _deployCore(address(ctl), address(pv2), address(pm2), address(v));
        // pv2/pm2 point at the decoy core, never at core2.
        pv2.setLister(address(decoy));
        pm2.setLister(address(decoy));
        vm.prank(controllerDao);
        ctl.setLister(address(core2));
        vm.prank(daoOwner);
        core2.setPaused(false);
        Candidate memory c2 = _method1Candidate(v);
        v.setRejectAll(true);
        World memory w2 = World({core_: core2, ctl: ctl, pv: pv2, pm: pm2});
        _assertBeforeReadiness(w2, c2);
    }

    function _assertBeforeReadiness(World memory w, Candidate memory c) private {
        Snap memory s = _snap(w, c.gauge);
        (bool ok, bytes memory ret) = _paidCall(w, payer, c);
        _expectRevertedWith(
            ok, ret, _wantUntrusted(c.gauge), "TF_BEFORE_READINESS: false checker beats unbound/misbound venues"
        );
        _assertSnapUnchanged(s, _snap(w, c.gauge), "TF_BEFORE_READINESS: readiness-fault cell changed nothing");
    }

    // ---------------------------------------------------------------
    // identity 5 — checker read faults fail closed
    // ---------------------------------------------------------------

    function test_TF_CheckerReadFaultsFailClosed() public {
        ConfigurableTrustedValidator v = new ConfigurableTrustedValidator();
        World memory w = _newWorld(address(v));
        Candidate memory c = _method1Candidate(v);
        _tf5FalseControl(v, w, c);
        _tf5FaultLoop(v, w, c);
        _tf5MissingSelector(v, w, c);
        _tf5RemovedCodeAndTrueControl(v, w, c);
    }

    function _tf5FalseControl(ConfigurableTrustedValidator v, World memory w, Candidate memory c) private {
        // Canonical-false control expects UntrustedGauge (distinct error):
        // the read-fault label below is never satisfied by a false.
        v.setRejectAll(true);
        Snap memory sf = _snap(w, c.gauge);
        (bool fook, bytes memory fret) = _paidCall(w, payer, c);
        _expectRevertedWith(fook, fret, _wantUntrusted(c.gauge), "TF_READ_FAULT_REJECTS: canonical false control");
        _assertSnapUnchanged(sf, _snap(w, c.gauge), "TF_FAULT_NO_EFFECTS: false case unchanged");
        v.setRejectAll(false);
    }

    function _tf5FaultLoop(ConfigurableTrustedValidator v, World memory w, Candidate memory c) private {
        ConfigurableTrustedValidator.TopFault[7] memory faults = [
            ConfigurableTrustedValidator.TopFault.Revert,
            ConfigurableTrustedValidator.TopFault.Empty,
            ConfigurableTrustedValidator.TopFault.OneByte,
            ConfigurableTrustedValidator.TopFault.ThirtyOneByte,
            ConfigurableTrustedValidator.TopFault.TrueWithTail,
            ConfigurableTrustedValidator.TopFault.Word2,
            ConfigurableTrustedValidator.TopFault.MaxUint
        ];
        string[7] memory faultNames = [
            "top-level revert",
            "empty return",
            "1-byte return",
            "31-byte return",
            "64-byte true-with-tail",
            "word 2",
            "maximum uint256"
        ];
        for (uint256 i = 0; i < faults.length; ++i) {
            v.setTopFault(faults[i]);
            Snap memory s = _snap(w, c.gauge);
            (bool ok, bytes memory ret) = _paidCall(w, payer, c);
            if (i == 4) {
                // 64-byte true-with-tail: the EXACT-32 guard is what rejects.
                _expectRevertedWith(
                    ok, ret, _wantCheckFailed(c.gauge), string.concat("TF_EXACT_RETURN_LENGTH: ", faultNames[i])
                );
            } else if (i == 5 || i == 6) {
                // noncanonical bool words: only integer 1 may pass.
                _expectRevertedWith(
                    ok, ret, _wantCheckFailed(c.gauge), string.concat("TF_CANONICAL_BOOL: ", faultNames[i])
                );
            } else {
                _expectRevertedWith(
                    ok, ret, _wantCheckFailed(c.gauge), string.concat("TF_READ_FAULT_REJECTS: ", faultNames[i])
                );
            }
            _assertSnapUnchanged(s, _snap(w, c.gauge), "TF_FAULT_NO_EFFECTS: every read fault is effect-free");
        }
        v.setTopFault(ConfigurableTrustedValidator.TopFault.None);
    }

    function _tf5MissingSelector(ConfigurableTrustedValidator, World memory, Candidate memory) private {
        // Missing selector: a code-bearing validator WITHOUT validateGauge.
        NoSelectorValidator nv = new NoSelectorValidator();
        World memory wn = _newWorld(address(nv));
        ConfigurableTrustedValidator vn = new ConfigurableTrustedValidator();
        Candidate memory cn = _method1Candidate(vn);
        Snap memory sn0 = _snap(wn, cn.gauge);
        (bool n1ok, bytes memory n1ret) = _paidCall(wn, payer, cn);
        _expectRevertedWith(
            n1ok, n1ret, _wantCheckFailed(cn.gauge), "TF_READ_FAULT_REJECTS: missing function on the pinned address"
        );
        _assertSnapUnchanged(sn0, _snap(wn, cn.gauge), "TF_FAULT_NO_EFFECTS: missing-function case unchanged");
    }

    function _tf5RemovedCodeAndTrueControl(ConfigurableTrustedValidator v, World memory w, Candidate memory c) private {
        // Runtime code removal AFTER construction (disclosed fault injection).
        vmx.etch(address(v), "");
        Snap memory sR = _snap(w, c.gauge);
        (bool rok, bytes memory rret) = _paidCall(w, payer, c);
        _expectRevertedWith(
            rok, rret, _wantCheckFailed(c.gauge), "TF_READ_FAULT_REJECTS: code removed after construction"
        );
        _assertSnapUnchanged(sR, _snap(w, c.gauge), "TF_FAULT_NO_EFFECTS: removed-code case unchanged");

        // Canonical-true control still succeeds after every fault.
        ConfigurableTrustedValidator vh = new ConfigurableTrustedValidator();
        World memory wh = _newWorld(address(vh));
        Candidate memory ch = _method1Candidate(vh);
        (bool hok, bytes memory hret) = _paidCall(wh, payer, ch);
        _expectSucceeded(hok, hret, "TF_READ_FAULT_REJECTS: canonical true control still admits");
        assertEq(
            uint256(wh.core_.getListing(ch.gauge).status),
            uint256(CurveGaugeLister.Status.Active),
            "control: canonical true Active"
        );
    }

    // ---------------------------------------------------------------
    // identity 6 — registry authentication precedes trust
    // ---------------------------------------------------------------

    function test_TF_RegistryAuthenticationPrecedesTrust() public {
        // A checker that REVERTS any call: if the product reached the trust
        // read first, every precedence case below would surface
        // TrustedGaugeCheckFailed instead of the original error.
        ConfigurableTrustedValidator v = new ConfigurableTrustedValidator();
        v.setTopFault(ConfigurableTrustedValidator.TopFault.Revert);
        World memory w = _newWorld(address(v));
        _tf6RegistryChecks(v, w);
        _tf6StructuralPrecedence(v, w);
        _tf6PauseAndDuplicatePrecedence();
        _tf6ValidPoolReachesTrust();
    }

    function _tf6RegistryChecks(ConfigurableTrustedValidator v, World memory w) private {
        // Unregistered pool -> PoolNotRegistered (TF_REGISTRY_FIRST).
        Candidate memory c1 = _method1Candidate(v);
        registry.setRegistered(c1.pool, c1.slot, false);
        (bool ok1, bytes memory ret1) = _paidCall(w, payer, c1);
        _expectRevertedWith(
            ok1,
            ret1,
            _wantE(CurveGaugeLister.PoolNotRegistered.selector),
            "TF_REGISTRY_FIRST: registry authentication precedes the trust read"
        );

        // Registered pool, wrong gauge association -> GaugeMismatch
        // (TF_ASSOCIATION_FIRST): the registry's reverse association is
        // checked before any trust read.
        Candidate memory c3 = _method1Candidate(v);
        address wrongGauge = address(new FactoryClaimGauge(c3.lp, c3.factory));
        registry.setGauge(c3.pool, c3.slot, 0, wrongGauge, int128(0));
        (bool ok3, bytes memory ret3) = _paidCall(w, payer, c3);
        _expectRevertedWith(
            ok3,
            ret3,
            _wantE(CurveGaugeLister.GaugeMismatch.selector),
            "TF_ASSOCIATION_FIRST: reverse gauge association precedes the trust read"
        );

        // LP mismatch retains BadLpToken.
        Candidate memory c4 = _method1Candidate(v);
        address otherLp = address(new MockERC20(18));
        registry.setPool(c4.pool, c4.slot, otherLp, _coins2(), 2);
        (bool ok4, bytes memory ret4) = _paidCall(w, payer, c4);
        _expectRevertedWith(
            ok4,
            ret4,
            _wantE(CurveGaugeLister.BadLpToken.selector),
            "TF_ASSOCIATION_FIRST: LP association precedes the trust read"
        );
    }

    function _tf6StructuralPrecedence(ConfigurableTrustedValidator v, World memory w) private {
        // Retained earlier precedence: index bounds and code checks still
        // precede the trust read (this is NOT a trust-first rewrite).
        Candidate memory c5 = _method1Candidate(v);
        vm.prank(payer);
        (bool ok5, bytes memory ret5) =
            address(w.core_).call(abi.encodeCall(CurveGaugeLister.listGauge, (c5.pool, c5.gauge, uint256(10), c5.slot)));
        _expectRevertedWith(
            ok5,
            ret5,
            _wantE(CurveGaugeLister.IndexOutOfRange.selector),
            "TF_REGISTRY_FIRST: index bounds precede the trust read"
        );

        Candidate memory c6 = _method1Candidate(v);
        vm.prank(payer);
        (bool ok6, bytes memory ret6) = address(w.core_)
            .call(abi.encodeCall(CurveGaugeLister.listGauge, (c6.pool, actor("codelessGauge"), uint256(0), c6.slot)));
        _expectRevertedWith(
            ok6,
            ret6,
            abi.encodeWithSelector(CurveGaugeLister.NoCode.selector, actor("codelessGauge")),
            "TF_REGISTRY_FIRST: structural code checks precede the trust read"
        );
    }

    function _tf6PauseAndDuplicatePrecedence() private {
        ConfigurableTrustedValidator vp = new ConfigurableTrustedValidator();
        vp.setTopFault(ConfigurableTrustedValidator.TopFault.Revert);
        World memory wp = _newWorld(address(vp));
        vm.prank(daoOwner);
        wp.core_.setPaused(true);
        Candidate memory cp = _method1Candidate(vp);
        (bool okP, bytes memory retP) = _paidCall(wp, payer, cp);
        _expectRevertedWith(
            okP,
            retP,
            _wantE(CurveGaugeLister.ListingsPaused.selector),
            "TF_REGISTRY_FIRST: pause precedes the trust read"
        );

        // Duplicate: admit with a healthy checker, then REVERT the checker
        // and relist — AlreadyListed must win.
        ConfigurableTrustedValidator vd = new ConfigurableTrustedValidator();
        World memory wd = _newWorld(address(vd));
        Candidate memory cd = _method1Candidate(vd);
        (bool dok, bytes memory dret) = _paidCall(wd, payer, cd);
        _expectSucceeded(dok, dret, "control: healthy paid admission");
        vd.setTopFault(ConfigurableTrustedValidator.TopFault.Revert);
        (bool dok2, bytes memory dret2) = _paidCall(wd, payer, cd);
        _expectRevertedWith(
            dok2,
            dret2,
            abi.encodeWithSelector(CurveGaugeLister.AlreadyListed.selector, cd.gauge),
            "TF_REGISTRY_FIRST: duplicate protection precedes the trust read"
        );
    }

    function _tf6ValidPoolReachesTrust() private {
        // TF_VALID_POOL_REACHES_TRUST: otherwise-valid pool with a REJECTING
        // (non-faulting) checker reaches UntrustedGauge.
        ConfigurableTrustedValidator vr = new ConfigurableTrustedValidator();
        World memory wr = _newWorld(address(vr));
        Candidate memory cr = _method1Candidate(vr);
        vr.setRejectAll(true);
        (bool rok, bytes memory rret) = _paidCall(wr, payer, cr);
        _expectRevertedWith(rok, rret, _wantUntrusted(cr.gauge), "TF_VALID_POOL_REACHES_TRUST");
    }

    // ---------------------------------------------------------------
    // identity 7 — DAO free lane is trust-independent
    // ---------------------------------------------------------------

    function test_TF_DaoFreeLaneIsTrustIndependent() public {
        ConfigurableTrustedValidator v = new ConfigurableTrustedValidator();
        // A core whose validator is the shared honest-model checker; the
        // free lane must never read it, in ANY checker state.
        World memory w = _newWorld(address(v));
        _tf7CheckerStates(v, w);
        _tf7Paused();
        _tf7UnboundAndNoReadiness();
        _tf7AuthAndRegistryLaw();
    }

    function _tf7CheckerStates(ConfigurableTrustedValidator v, World memory w) private {
        // checker false
        v.setRejectAll(true);
        _tf7FreeCell(w, 42, "TF_DAO_NO_CHECKER_DEPENDENCE: false checker does not gate the free lane");

        // checker reverting
        v.setRejectAll(false);
        v.setTopFault(ConfigurableTrustedValidator.TopFault.Revert);
        _tf7FreeCell(w, 7, "TF_DAO_NO_CHECKER_DEPENDENCE: reverting checker does not gate the free lane");

        // checker malformed (64-byte true-with-tail)
        v.setTopFault(ConfigurableTrustedValidator.TopFault.TrueWithTail);
        _tf7FreeCell(w, 0, "TF_DAO_NO_CHECKER_DEPENDENCE: malformed checker does not gate the free lane");

        // checker code removed after construction (disclosed fault injection)
        vmx.etch(address(v), "");
        _tf7FreeCell(w, 1, "TF_DAO_NO_CHECKER_DEPENDENCE: removed-code checker does not gate the free lane");
    }

    /// @dev One successful free-lane admission cell: first-call success is
    /// asserted BEFORE record/custody assertions, then the complete DaoExempt
    /// expectations via _assertFreeListing. Returns the admitted gauge for
    /// caller-specific extra checks.
    function _tf7FreeCell(World memory w, uint256 initialWeight, string memory successLabel)
        private
        returns (address gauge)
    {
        Candidate memory c = _plainCandidate();
        (bool ok, bytes memory ret, Vm.Log[] memory logs) = _freeCallLogged(w, daoOwner, c, initialWeight);
        _expectSucceeded(ok, ret, successLabel);
        _assertFreeListing(w, c, initialWeight, logs);
        return c.gauge;
    }

    function _tf7Paused() private {
        ConfigurableTrustedValidator vp = new ConfigurableTrustedValidator();
        vp.setRejectAll(true);
        World memory wp = _newWorld(address(vp));
        vm.prank(daoOwner);
        wp.core_.setPaused(true);
        _tf7FreeCell(wp, 5, "TF_DAO_NO_CHECKER_DEPENDENCE: paused free lane succeeds");
    }

    /// @dev Without platform readiness: the controller is seated
    /// (add_gauge authority is the product's OWN requirement, not a paid
    /// readiness gate) while the two venues are NEVER bound and the core is
    /// still paused. Paid-adapter readiness belongs to the paid lane only.
    function _tf7UnboundAndNoReadiness() private {
        ConfigurableTrustedValidator vu = new ConfigurableTrustedValidator();
        vu.setTopFault(ConfigurableTrustedValidator.TopFault.Revert);
        MockListingController ctlU = new MockListingController(controllerDao, int128(2));
        MockIncentivePlatform pvU = new MockIncentivePlatform(address(crvUSD));
        MockIncentivePlatform pmU = new MockIncentivePlatform(address(crvUSD));
        CurveGaugeLister coreU = _deployCore(address(ctlU), address(pvU), address(pmU), address(vu));
        vm.prank(controllerDao);
        ctlU.setLister(address(coreU)); // controller authority only; no venue binding, stays paused
        World memory wu = World({core_: coreU, ctl: ctlU, pv: pvU, pm: pmU});
        // The unready/paused cell asserts its FULL expectations — supplied
        // weight, membership, complete original 15-field DaoExempt tuple,
        // event and zero custody — not just call success and status.
        address gaugeU = _tf7FreeCell(wu, 3, "TF_DAO_NO_CHECKER_DEPENDENCE: platform-unready paused lane succeeds");
        assertEq(
            uint256(coreU.getListing(gaugeU).status),
            uint256(CurveGaugeLister.Status.DaoExempt),
            "TF_DAO_NO_FACTORY_ALLOWED: DaoExempt with no readiness and no checker dependence"
        );
    }

    function _tf7AuthAndRegistryLaw() private {
        ConfigurableTrustedValidator vn = new ConfigurableTrustedValidator();
        World memory wn = _newWorld(address(vn));
        Candidate memory cs = _plainCandidate();
        (bool okS, bytes memory retS) = _freeCall(wn, stranger, cs, 1);
        _expectRevertedWith(
            okS,
            retS,
            _wantE(CurveGaugeLister.NotOwner.selector),
            "TF_DAO_AUTH_AND_REGISTRY_RETAINED: outsider still NotOwner"
        );
        Candidate memory cb = _plainCandidate();
        registry.setRegistered(cb.pool, cb.slot, false);
        (bool okB, bytes memory retB) = _freeCall(wn, daoOwner, cb, 1);
        _expectRevertedWith(
            okB,
            retB,
            _wantE(CurveGaugeLister.PoolNotRegistered.selector),
            "TF_DAO_AUTH_AND_REGISTRY_RETAINED: bad registry still rejected on the free lane"
        );
    }

    function _freeCallLogged(World memory w, address from, Candidate memory c, uint256 initialWeight)
        internal
        returns (bool ok, bytes memory ret, Vm.Log[] memory logs)
    {
        vm.recordLogs();
        (ok, ret) = _freeCall(w, from, c, initialWeight);
        logs = vm.getRecordedLogs();
    }

    function _assertFreeListing(World memory w, Candidate memory c, uint256 initialWeight, Vm.Log[] memory logs)
        private
    {
        // TF_DAO_NO_FACTORY_ALLOWED: otherwise-valid non-factory gauges are
        // admitted on the free lane with the exact original 15-field
        // DaoExempt record.
        CurveGaugeLister.Listing memory rec = w.core_.getListing(c.gauge);
        assertEq(
            uint256(rec.status),
            uint256(CurveGaugeLister.Status.DaoExempt),
            "TF_DAO_NO_FACTORY_ALLOWED: exact DaoExempt record"
        );
        assertEq(rec.pool, c.pool, "TF_DAO_NO_FACTORY_ALLOWED: pool");
        assertEq(rec.lpToken, c.lp, "TF_DAO_NO_FACTORY_ALLOWED: lp");
        assertEq(rec.payer, address(0), "TF_DAO_NO_FACTORY_ALLOWED: payer zero");
        assertEq(rec.admissionRegistry, address(registry), "TF_DAO_NO_FACTORY_ALLOWED: registry");
        assertEq(rec.gaugeType, int128(0), "TF_DAO_NO_FACTORY_ALLOWED: derived type");
        assertEq(rec.deposited, 0, "TF_DAO_NO_FACTORY_ALLOWED: no escrow");
        assertEq(rec.remaining, 0, "TF_DAO_NO_FACTORY_ALLOWED: no remaining");
        assertEq(rec.released, 0, "TF_DAO_NO_FACTORY_ALLOWED: no release");
        assertEq(w.ctl.gauge_types(c.gauge), int128(0), "TF_DAO_NO_FACTORY_ALLOWED: membership");
        assertEq(
            w.ctl.get_gauge_weight(c.gauge), initialWeight, "TF_DAO_NO_FACTORY_ALLOWED: supplied initialWeight stamped"
        );
        // The COMPLETE original 15-field DaoExempt tuple is load-bearing:
        // the free lane stamps no escrow, no release/confiscation and no
        // venue snapshot.
        assertEq(
            rec.listingEpoch,
            (block.timestamp / WEEK) * WEEK,
            "TF_DAO_NO_FACTORY_ALLOWED: listingEpoch independently expected"
        );
        assertEq(uint256(rec.epochsReleased), 0, "TF_DAO_NO_FACTORY_ALLOWED: epochsReleased zero");
        assertEq(rec.confiscated, 0, "TF_DAO_NO_FACTORY_ALLOWED: confiscated zero");
        assertEq(rec.votium, address(0), "TF_DAO_NO_FACTORY_ALLOWED: free lane stamps no votium venue");
        assertEq(rec.voteMarket, address(0), "TF_DAO_NO_FACTORY_ALLOWED: free lane stamps no voteMarket venue");
        assertEq(uint256(rec.votiumBps), 0, "TF_DAO_NO_FACTORY_ALLOWED: free lane stamps no votiumBps");
        // TF_DAO_ZERO_CUSTODY: zero fee/escrow.
        assertEq(crvUSD.balanceOf(address(w.core_)), 0, "TF_DAO_ZERO_CUSTODY: core holds no fee");
        assertEq(crvUSD.balanceOf(address(fd)), 0, "TF_DAO_ZERO_CUSTODY: FD saw nothing");
        assertEq(w.core_.totalEscrow(), 0, "TF_DAO_ZERO_CUSTODY: totalEscrow zero");

        // The free lane MUST emit the complete original free GaugeListed
        // payload — payer topic zero, fee zero, daoExempt true,
        // independently expected epoch. Removing the free-lane emit must
        // fail HERE (F-TF-FREE-EVENT).
        _expectLog(logs, address(w.core_), T_GAUGE_LISTED, "TF_DAO_NO_FACTORY_ALLOWED: free-lane GaugeListed emitted");
        bool freeListed;
        for (uint256 i = 0; i < logs.length; ++i) {
            if (
                logs[i].emitter == address(w.core_) && logs[i].topics.length == 4 && logs[i].topics[0] == T_GAUGE_LISTED
            ) {
                freeListed = true;
                assertEq(uint256(logs[i].topics[1]), uint256(uint160(c.gauge)), "free GaugeListed gauge topic");
                assertEq(uint256(logs[i].topics[2]), uint256(uint160(c.pool)), "free GaugeListed pool topic");
                assertEq(uint256(logs[i].topics[3]), uint256(uint160(address(0))), "free GaugeListed payer topic zero");
                (int128 lgType, uint256 lEpoch, uint256 lFee, bool lDao) =
                    abi.decode(logs[i].data, (int128, uint256, uint256, bool));
                assertEq(lgType, int128(0), "free GaugeListed type");
                assertEq(lEpoch, (block.timestamp / WEEK) * WEEK, "free GaugeListed epoch independently expected");
                assertEq(lFee, 0, "free GaugeListed fee zero");
                assertTrue(lDao, "free GaugeListed daoExempt true");
            }
        }
        assertTrue(freeListed, "TF_DAO_NO_FACTORY_ALLOWED: free-lane GaugeListed payload fully decoded");
    }

    // ---------------------------------------------------------------
    // identity 8 — trust is admission-only
    // ---------------------------------------------------------------

    function test_TF_TrustIsAdmissionOnly() public {
        ConfigurableTrustedValidator v = new ConfigurableTrustedValidator();
        World memory w = _newWorld(address(v));

        // Admit trusted paid gauge A.
        Candidate memory a = _method1Candidate(v);
        (bool aok, bytes memory aret) = _paidCall(w, payer, a);
        _expectSucceeded(aok, aret, "control: gauge A admitted while trusted");

        // REVOKE the checker; new paid candidates re-read trust, the
        // admitted gauge keeps settling without any new trust condition.
        v.setRejectAll(true);
        _tf8RecheckEachNewPaid(v, w);
        _tf8DripGate(v, w, a.gauge);
        Candidate memory d = _tf8KillViaCheckpoint(v, w);
        Candidate memory e = _tf8KillViaConfiscate(v, w);
        _tf8TerminalNoOp(v, w, e.gauge);
        // Added matrix cells (no bounty stand-ins): the admitted record's
        // views and the standalone fee maintenance call never read the
        // checker, under the same reverting policy.
        _tf8ViewGate(v, w, a.gauge);
        _tf8FeeGate(v, w);
        assertTrue(d.gauge != address(0), "TF_NO_RETROACTIVE_KILL_GATE: checkpoint cell ran");
    }

    /// @dev Revocation (false) and checker outage (fault) each block NEW
    /// paid candidates ("revoke/fault checker; new paid candidate fails").
    function _tf8RecheckEachNewPaid(ConfigurableTrustedValidator v, World memory w) private {
        Candidate memory b = _method1Candidate(v);
        (bool bok, bytes memory bret) = _paidCall(w, payer, b);
        _expectRevertedWith(bok, bret, _wantUntrusted(b.gauge), "TF_RECHECK_EACH_NEW_PAID: false recheck");
        v.setRejectAll(false);
        v.setTopFault(ConfigurableTrustedValidator.TopFault.Revert);
        Candidate memory cc = _method1Candidate(v);
        (bool cok, bytes memory cret) = _paidCall(w, payer, cc);
        _expectRevertedWith(cok, cret, _wantCheckFailed(cc.gauge), "TF_RECHECK_EACH_NEW_PAID: fault recheck");
    }

    function _tf8DripGate(ConfigurableTrustedValidator, World memory w, address gauge) private {
        // TF_NO_RETROACTIVE_DRIP_GATE: the already-admitted gauge (checker
        // still REVERTING) releases its exact due tranche. Call success is
        // asserted at the named label BEFORE the effect checks.
        vm.warp(block.timestamp + WEEK);
        uint256 coreBefore = crvUSD.balanceOf(address(w.core_));
        vm.recordLogs();
        vm.prank(stranger);
        (bool drop, bytes memory dret) =
            address(w.core_).call(abi.encodeWithSelector(CurveGaugeLister.checkpoint.selector, gauge));
        _expectSucceeded(
            drop, dret, "TF_NO_RETROACTIVE_DRIP_GATE: settlement of an admitted gauge performs no trust read"
        );
        Vm.Log[] memory dripLogs = vm.getRecordedLogs();
        (uint256 releasedNow, uint256 confiscatedNow) = abi.decode(dret, (uint256, uint256));
        assertEq(releasedNow, QUARTER_AMOUNT, "TF_NO_RETROACTIVE_DRIP_GATE: exact due tranche");
        assertEq(confiscatedNow, 0, "TF_NO_RETROACTIVE_DRIP_GATE: no seizure without a kill flag");
        assertEq(
            uint256(w.core_.getListing(gauge).status),
            uint256(CurveGaugeLister.Status.Active),
            "TF_NO_RETROACTIVE_DRIP_GATE: still Active after release"
        );
        assertEq(
            coreBefore - QUARTER_AMOUNT,
            crvUSD.balanceOf(address(w.core_)),
            "TF_NO_RETROACTIVE_DRIP_GATE: quarter routed out"
        );
        _expectLog(dripLogs, address(w.core_), T_QUARTER_RELEASED, "TF_NO_RETROACTIVE_DRIP_GATE: QuarterReleased");
        // (The checker remains in TopFault.Revert mode from the recheck cell:
        // any added trust read would have turned this very call into a
        // TrustedGaugeCheckFailed.)
    }

    function _tf8KillViaCheckpoint(ConfigurableTrustedValidator v, World memory w)
        private
        returns (Candidate memory d)
    {
        // Fresh cell: admit D healthy, then REVOKE + kill; checkpoint settles
        // the killed remainder through the checkpoint route with the
        // unchanged all-FD V1 law (no new trust condition).
        _fdSpace();
        v.setTopFault(ConfigurableTrustedValidator.TopFault.None);
        d = _method1Candidate(v);
        (bool dok, bytes memory dret0) = _paidCall(w, payer, d);
        _expectSucceeded(dok, dret0, "control: gauge D admitted while trusted");
        v.setTopFault(ConfigurableTrustedValidator.TopFault.Revert);
        FactoryClaimGauge(d.gauge).setKilled(true);
        uint256 fdBefore = crvUSD.balanceOf(address(fd));
        vm.recordLogs();
        vm.prank(stranger);
        (bool ckOk, bytes memory ckRet) =
            address(w.core_).call(abi.encodeWithSelector(CurveGaugeLister.checkpoint.selector, d.gauge));
        _expectSucceeded(
            ckOk, ckRet, "TF_NO_RETROACTIVE_KILL_GATE: checkpoint of an admitted killed gauge performs no trust read"
        );
        Vm.Log[] memory ckLogs = vm.getRecordedLogs();
        (uint256 relD, uint256 confD) = abi.decode(ckRet, (uint256, uint256));
        assertEq(relD, 0, "TF_NO_RETROACTIVE_KILL_GATE: kill settles before any release");
        assertEq(confD, FEE_AMOUNT, "TF_NO_RETROACTIVE_KILL_GATE: killed remainder fully seized");
        assertEq(crvUSD.balanceOf(address(fd)) - fdBefore, FEE_AMOUNT, "TF_NO_RETROACTIVE_KILL_GATE: FD law intact");
        assertEq(
            uint256(w.core_.getListing(d.gauge).status),
            uint256(CurveGaugeLister.Status.Confiscated),
            "TF_NO_RETROACTIVE_KILL_GATE: Confiscated record"
        );
        // Original (unversioned) V1 event shape with the full-remainder
        // amount and mandatory accounting-success event.
        _expectLog(ckLogs, address(w.core_), T_ESCROW_CONFISCATED, "TF_NO_RETROACTIVE_KILL_GATE: original V1 event");
        _expectLog(ckLogs, address(w.core_), T_FEE_CHECKPOINT_RESULT, "TF_NO_RETROACTIVE_KILL_GATE: accounting success");
        bool sawConfiscation;
        for (uint256 i = 0; i < ckLogs.length; ++i) {
            if (
                ckLogs[i].emitter == address(w.core_) && ckLogs[i].topics.length == 3
                    && ckLogs[i].topics[0] == T_ESCROW_CONFISCATED
            ) {
                sawConfiscation = true;
                assertEq(uint256(ckLogs[i].topics[1]), uint256(uint160(d.gauge)), "EscrowConfiscated gauge topic");
                assertEq(uint256(ckLogs[i].topics[2]), uint256(uint160(address(fd))), "EscrowConfiscated fd topic");
                (uint256 amount, uint256 receiptWeek) = abi.decode(ckLogs[i].data, (uint256, uint256));
                assertEq(amount, FEE_AMOUNT, "EscrowConfiscated full remainder");
                assertEq(receiptWeek, (block.timestamp / WEEK) * WEEK, "EscrowConfiscated receipt week");
            }
        }
        assertTrue(sawConfiscation, "TF_NO_RETROACTIVE_KILL_GATE: EscrowConfiscated payload fully decoded");
    }

    function _tf8KillViaConfiscate(ConfigurableTrustedValidator v, World memory w)
        private
        returns (Candidate memory e)
    {
        // confiscate route, same law on a fresh cell.
        _fdSpace();
        v.setTopFault(ConfigurableTrustedValidator.TopFault.None);
        e = _method1Candidate(v);
        (bool eok, bytes memory erset) = _paidCall(w, payer, e);
        _expectSucceeded(eok, erset, "control: gauge E admitted while trusted");
        v.setTopFault(ConfigurableTrustedValidator.TopFault.Revert);
        FactoryClaimGauge(e.gauge).setKilled(true);
        uint256 fdBefore = crvUSD.balanceOf(address(fd));
        vm.prank(stranger);
        (bool cfOk, bytes memory cfRet) =
            address(w.core_).call(abi.encodeWithSelector(CurveGaugeLister.confiscate.selector, e.gauge));
        _expectSucceeded(
            cfOk, cfRet, "TF_NO_RETROACTIVE_KILL_GATE: confiscate of an admitted killed gauge performs no trust read"
        );
        assertEq(abi.decode(cfRet, (uint256)), FEE_AMOUNT, "TF_NO_RETROACTIVE_KILL_GATE: exact seizure");
        assertEq(crvUSD.balanceOf(address(fd)) - fdBefore, FEE_AMOUNT, "TF_NO_RETROACTIVE_KILL_GATE: FD received");
    }

    function _tf8TerminalNoOp(ConfigurableTrustedValidator, World memory w, address gauge) private {
        // terminal no-op under a REVERTING checker: settled gauges answer
        // (0,0) with no dependency and no trust condition.
        vm.prank(stranger);
        (bool t1, bytes memory t1ret) =
            address(w.core_).call(abi.encodeWithSelector(CurveGaugeLister.checkpoint.selector, gauge));
        _expectSucceeded(t1, t1ret, "TF_NO_RETROACTIVE_KILL_GATE: terminal checkpoint no-op");
        (uint256 tr1, uint256 tr2) = abi.decode(t1ret, (uint256, uint256));
        assertEq(tr1 + tr2, 0, "TF_NO_RETROACTIVE_KILL_GATE: terminal (0,0)");
    }

    /// @dev Added matrix cell: with the checker still REVERTING, the views
    /// of an admitted live gauge answer with their exact expected values —
    /// no retroactive view gate may consult the validator.
    function _tf8ViewGate(ConfigurableTrustedValidator, World memory w, address gauge) private view {
        // _tf8DripGate released exactly one tranche; elapsed is one.
        assertEq(w.core_.epochsElapsed(gauge), 1, "TF_NO_RETROACTIVE_VIEW_GATE: epochsElapsed under reverting checker");
        assertEq(w.core_.releasable(gauge), 0, "TF_NO_RETROACTIVE_VIEW_GATE: releasable under reverting checker");
        assertEq(
            w.core_.getListing(gauge).remaining,
            FEE_AMOUNT - QUARTER_AMOUNT,
            "TF_NO_RETROACTIVE_VIEW_GATE: getListing under reverting checker"
        );
        assertEq(
            uint256(w.core_.getListing(gauge).status),
            uint256(CurveGaugeLister.Status.Active),
            "TF_NO_RETROACTIVE_VIEW_GATE: record stays Active"
        );
    }

    /// @dev Added matrix cell: the standalone permissionless fee maintenance
    /// call performs no trust read under the same reverting checker.
    function _tf8FeeGate(ConfigurableTrustedValidator, World memory w) private {
        _fdSpace();
        vm.recordLogs();
        vm.prank(stranger);
        (bool fOk, bytes memory fRet) =
            address(w.core_).call(abi.encodeWithSelector(CurveGaugeLister.checkpointFees.selector));
        _expectSucceeded(
            fOk, fRet, "TF_NO_RETROACTIVE_FEE_GATE: checkpointFees performs no trust read under a reverting checker"
        );
        assertTrue(abi.decode(fRet, (bool)), "TF_NO_RETROACTIVE_FEE_GATE: upstream checkpoint returned");
        assertEq(fd.last_token_time(), block.timestamp, "TF_NO_RETROACTIVE_FEE_GATE: cursor advanced");
        _expectLog(
            vm.getRecordedLogs(), address(w.core_), T_FEE_CHECKPOINT_RESULT, "TF_NO_RETROACTIVE_FEE_GATE: result event"
        );
    }

    /// @dev Space the FD cursor so this transaction's mandatory public
    /// checkpoint satisfies the accepted cooldown (the mock models the real
    /// 24h gate; retained settlement tests use the same disclosed control).
    function _fdSpace() private {
        fd.setLastTokenTime(block.timestamp - 2 days);
    }
}
