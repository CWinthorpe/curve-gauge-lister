// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ForkFixture, FVm, IErc20Venue, IControllerVenue, IMetaRegistryVenue, IGaugeVenue} from "./ForkFixture.sol";
import {CurveGaugeLister} from "../../contracts/CurveGaugeLister.sol";

/// @dev Live pinned-validator surface (read-only). The REAL deployed
/// validator answers these; no mockCall/etch/storage write is used anywhere
/// in this file for provenance.
interface ITrustedValidatorVenue {
    function owner() external view returns (address);
    function policyForFactory(address factory) external view returns (address module, uint8 method);
    function validateGauge(address gauge) external view returns (bool);
}

/// @dev Real factory reverse lookup and legacy LP minter routes.
interface IFactoryReverseVenue {
    function get_gauge(address token) external view returns (address);
}

interface ILpMinterVenue {
    function minter() external view returns (address);
}

/// @title ForkTrustedFactoryScenarios
/// @notice The two fork trust identities (plans/V1ALIGN-WITNESSES.md §2 fork
/// rows), rewritten onto the no-bounty ForkFixture/Trio kit: the AMENDED V1
/// paid admission running against the REAL deployed validator, gauge modules,
/// factories, MetaRegistry, crvUSD and GaugeController at the unchanged pin
/// (chain 1 / block 26401019 / hash
/// 0x55810b079923a14fb97ad548f5024f65530dbc4fb2357a38f41e13b3d27cb6d3).
/// Positives use real state only; underlying fork probe failures are BLOCKED
/// (suite-red), never skipped or substituted. Disclosed fixtures inherited
/// from the frozen fork kit: local deployments of the production V1/adapters,
/// crvUSD holder-prank funding, and the fork-only controller two-step
/// seating — simulation, NOT production GaugeAdder authorization. The
/// validator identity is carried independently of any bounty dependency; the
/// secondary-candidate constants below are copied from the retired bounty
/// fixture provenance, not its governance dependencies.
abstract contract ForkTrustedFactoryScenarios is ForkFixture {
    // ---------------- pinned live identities (V1ALIGN manifest) ----------
    address internal constant GAUGE_MODULE = 0x999902533033Cc63c8128C501e307477932B742E;
    uint256 internal constant GAUGE_MODULE_SIZE = 1336;
    bytes32 internal constant H_GAUGE_MODULE = 0xfc5562e86bbf44b97a41e6e1e1f578a396c0fd4a5aaac85805ef62630fca36ff;
    uint256 internal constant SSNG_POLICY_METHOD = 1;
    uint256 internal constant LEGACY_POLICY_METHOD = 2;

    /// @dev Retained secondary-gauge predicate control (copied from the
    /// retired bounty fork fixture's re-proven provenance, no governance
    /// dependency): the live validator must still answer true for this
    /// candidate, so the suite cannot silently depend on a different checker.
    address internal constant GAUGE_SECOND = 0x9D81d64A0e17d02EA8FD962FA13F4B89146d9a43;

    // ---------------- §4.1 verified legacy candidate ---------------------
    address internal constant POOL_LEGACY = 0x03470B57B05089EE40c651dAC9E0387F1f3cb46f;
    address internal constant GAUGE_LEGACY = 0xfB389aCa09ddC676fC9D5aC3cfD2Cd133bf44E19;
    address internal constant LP_LEGACY = 0x1AEa495539B514A5538878D3D3695c7AEDdC61F1;
    address internal constant LEGACY_FACTORY = 0xF18056Bbd320E96A48e3Fbf8bC061322531aac99;
    uint256 internal constant LEGACY_HANDLER_ID = 0;
    uint256 internal constant LEGACY_GAUGE_INDEX = 0;
    int128 internal constant LEGACY_GAUGE_TYPE = 5;

    bytes32 internal constant T_LISTED = keccak256("GaugeListed(address,address,address,int128,uint256,uint256,bool)");

    /// @dev Validator core identity + module code identity at the CURRENT
    /// fork block (read-only). Owner at both verification blocks was the DAO
    /// org.
    function _assertValidatorIdentity() internal view {
        _assertValidatorPinAtFork();
        assertEq(ITrustedValidatorVenue(TRUSTED_VALIDATOR).owner(), DAO, "fork: validator owner is the DAO org");
        bytes memory mcode = GAUGE_MODULE.code;
        assertEq(uint256(mcode.length), GAUGE_MODULE_SIZE, "fork: gauge module runtime size 1336");
        assertEq(keccak256(mcode), H_GAUGE_MODULE, "fork: gauge module runtime keccak");
    }

    /// @dev Extract and verify the EIP-1167 minimal-proxy implementation the
    /// §4.1 note records for the 45-byte clones: prefix
    /// 363d3d373d3d3d363d73, 20-byte target at bytes 10..30, suffix
    /// 5af43d82803e903d91602b57fd5bf3. These are STRUCTURAL proxy-shape
    /// assertions: they pin the clone shape and that the target carries code,
    /// NOT the exact underlying implementation bytes; no stronger identity
    /// proof may be claimed from them.
    function _proxyTarget(address clone) internal view returns (address impl) {
        bytes memory code = clone.code;
        require(code.length == 45, "fork: 45-byte minimal proxy expected");
        uint80 prefix;
        for (uint256 i = 0; i < 10; ++i) {
            prefix = (prefix << 8) | uint8(code[i]);
        }
        require(prefix == 0x363d3d373d3d3d363d73, "fork: EIP-1167 prefix");
        uint120 suffix;
        for (uint256 j = 30; j < 45; ++j) {
            suffix = (suffix << 8) | uint8(code[j]);
        }
        require(suffix == 0x5af43d82803e903d91602b57fd5bf3, "fork: EIP-1167 suffix");
        assembly {
            impl := shr(96, mload(add(code, 42)))
        }
        require(impl != address(0), "fork: proxy target nonzero");
    }

    // ------------------------------------------------------------------
    // identity A — real SS-ng trusted-factory paid admission
    // ------------------------------------------------------------------

    function test_Fork_TF_SsNgTrustedFactoryAdmission() public {
        _freshFork();

        // TF_FORK_PIN_IDENTITY: real pinned validator owner/code/policy and
        // gauge-module code identity, read-only at the pin.
        _assertValidatorIdentity();
        (address ssngModule, uint8 ssngMethod) = ITrustedValidatorVenue(TRUSTED_VALIDATOR).policyForFactory(FACTORY);
        assertEq(ssngModule, GAUGE_MODULE, "TF_FORK_PIN_IDENTITY: SS-ng policy module");
        assertEq(uint256(ssngMethod), SSNG_POLICY_METHOD, "TF_FORK_PIN_IDENTITY: SS-ng method 1");

        // Real SS-ng gauge factory/LP/reverse proof reads (live, no mocks).
        address lpPrimary = IMetaRegistryVenue(METAREGISTRY).get_lp_token(POOL_PRIMARY, HANDLER_ID);
        assertEq(IGaugeVenue(GAUGE_PRIMARY).factory(), FACTORY, "TF_FORK_SSNG_TRUE: gauge names regular factory");
        assertEq(IGaugeVenue(GAUGE_PRIMARY).lp_token(), lpPrimary, "TF_FORK_SSNG_TRUE: lp association");
        assertEq(
            IFactoryReverseVenue(FACTORY).get_gauge(lpPrimary), GAUGE_PRIMARY, "TF_FORK_SSNG_TRUE: reciprocal get_gauge"
        );
        assertTrue(
            ITrustedValidatorVenue(TRUSTED_VALIDATOR).validateGauge(GAUGE_PRIMARY),
            "TF_FORK_SSNG_TRUE: live predicate true for the real gauge"
        );
        assertFalse(
            ITrustedValidatorVenue(TRUSTED_VALIDATOR).validateGauge(FACTORY),
            "TF_FORK_SSNG_TRUE: the factory itself is not a gauge (false)"
        );
        // Retained secondary-gauge predicate control: the shared checker must
        // still be the one the provenance was recorded against.
        assertTrue(
            ITrustedValidatorVenue(TRUSTED_VALIDATOR).validateGauge(GAUGE_SECOND),
            "TF_FORK_SSNG_TRUE: secondary fixture gauge predicate still true"
        );

        // Amended V1 paid admission with real crvUSD/controller: the no-bounty
        // trio deploy asserts the pin code/hash BEFORE construction.
        Trio memory t = _deployTrio(5000);
        assertEq(
            t.lister.trustedGaugeValidator(),
            TRUSTED_VALIDATOR,
            "TF_FORK_PIN_IDENTITY: core pinned to the real validator"
        );
        _seat(t.lister);

        _fundPayerOnce(payer());
        fvm.prank(payer());
        IErc20Venue(CRVUSD).approve(address(t.lister), FEE);
        // S05: explicit final activation once the prerequisites above hold.
        _activatePaidAdmission(t);
        uint256 payerBefore = IErc20Venue(CRVUSD).balanceOf(payer());
        uint256 nGaugesBefore = uint256(int256(IControllerVenue(CONTROLLER).n_gauges()));
        fvm.recordLogs();
        fvm.prank(payer());
        t.lister.listGauge(POOL_PRIMARY, GAUGE_PRIMARY, GAUGE_INDEX, HANDLER_ID);
        FVm.Log[] memory logs = fvm.getRecordedLogs();

        // TF_FORK_PAID_EXACT: exact fee custody, complete original 15-field
        // Active record, type, raw weight zero, GaugeListed and controller
        // membership.
        assertEq(IErc20Venue(CRVUSD).balanceOf(payer()), payerBefore - FEE, "TF_FORK_PAID_EXACT: payer exact debit");
        assertEq(IErc20Venue(CRVUSD).balanceOf(address(t.lister)), FEE, "TF_FORK_PAID_EXACT: core exact credit");
        assertEq(t.lister.totalEscrow(), FEE, "TF_FORK_PAID_EXACT: totalEscrow FEE");
        CurveGaugeLister.Listing memory rec = t.lister.getListing(GAUGE_PRIMARY);
        assertEq(uint256(rec.status), uint256(CurveGaugeLister.Status.Active), "TF_FORK_PAID_EXACT: Active");
        assertEq(rec.pool, POOL_PRIMARY, "TF_FORK_PAID_EXACT: pool");
        assertEq(rec.lpToken, lpPrimary, "TF_FORK_PAID_EXACT: lp");
        assertEq(rec.payer, payer(), "TF_FORK_PAID_EXACT: payer");
        assertEq(rec.admissionRegistry, METAREGISTRY, "TF_FORK_PAID_EXACT: admission registry");
        assertEq(rec.gaugeType, DERIVED_TYPE, "TF_FORK_PAID_EXACT: real derived type");
        assertEq(rec.listingEpoch, LISTING_EPOCH, "TF_FORK_PAID_EXACT: listing epoch");
        assertEq(uint256(rec.epochsReleased), 0, "TF_FORK_PAID_EXACT: epochsReleased");
        assertEq(rec.deposited, FEE, "TF_FORK_PAID_EXACT: deposited");
        assertEq(rec.remaining, FEE, "TF_FORK_PAID_EXACT: remaining");
        assertEq(rec.released, 0, "TF_FORK_PAID_EXACT: released");
        assertEq(rec.confiscated, 0, "TF_FORK_PAID_EXACT: confiscated");
        assertEq(rec.votium, address(t.va), "TF_FORK_PAID_EXACT: votium snapshot");
        assertEq(rec.voteMarket, address(t.vma), "TF_FORK_PAID_EXACT: votemarket snapshot");
        assertEq(uint256(rec.votiumBps), 5000, "TF_FORK_PAID_EXACT: bps snapshot");
        assertEq(
            IControllerVenue(CONTROLLER).gauge_types(GAUGE_PRIMARY),
            DERIVED_TYPE,
            "TF_FORK_PAID_EXACT: real controller membership type"
        );
        assertEq(IControllerVenue(CONTROLLER).get_gauge_weight(GAUGE_PRIMARY), 0, "TF_FORK_PAID_EXACT: raw weight zero");
        assertEq(
            uint256(int256(IControllerVenue(CONTROLLER).n_gauges())),
            nGaugesBefore + 1,
            "TF_FORK_PAID_EXACT: gauge count advanced"
        );
        bool listed;
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].emitter == address(t.lister) && logs[i].topics.length == 4 && logs[i].topics[0] == T_LISTED) {
                listed = true;
                assertEq(uint256(logs[i].topics[1]), uint256(uint160(GAUGE_PRIMARY)), "GaugeListed gauge");
                assertEq(uint256(logs[i].topics[2]), uint256(uint160(POOL_PRIMARY)), "GaugeListed pool");
                assertEq(uint256(logs[i].topics[3]), uint256(uint160(payer())), "GaugeListed payer");
                (int128 ty, uint256 ep, uint256 fee, bool dao) =
                    abi.decode(logs[i].data, (int128, uint256, uint256, bool));
                assertEq(ty, DERIVED_TYPE, "GaugeListed type");
                assertEq(ep, LISTING_EPOCH, "GaugeListed epoch");
                assertEq(fee, FEE, "GaugeListed fee");
                assertFalse(dao, "GaugeListed paid");
            }
        }
        assertTrue(listed, "TF_FORK_PAID_EXACT: GaugeListed emitted and decoded");
    }

    // ------------------------------------------------------------------
    // identity B — real distinct-LP legacy paid admission
    // ------------------------------------------------------------------

    function test_Fork_TF_LegacyTrustedFactoryAdmission() public {
        _freshFork();

        // §4.1 reads and code identities, re-asserted live, including the
        // underlying minimal-proxy targets of the 45-byte clones (shape
        // evidence only; see _proxyTarget).
        _assertValidatorPinAtFork();
        address poolImpl = _proxyTarget(POOL_LEGACY);
        address gaugeImpl = _proxyTarget(GAUGE_LEGACY);
        address lpImpl = _proxyTarget(LP_LEGACY);
        assertTrue(
            poolImpl.code.length > 0 && gaugeImpl.code.length > 0 && lpImpl.code.length > 0,
            "TF_FORK_LEGACY_MINTER_ROUTE: minimal-proxy targets carry code"
        );
        assertEq(LEGACY_FACTORY.code.length, 4435, "TF_FORK_LEGACY_MINTER_ROUTE: legacy factory runtime size");
        assertTrue(
            POOL_LEGACY != LP_LEGACY && LP_LEGACY != GAUGE_LEGACY && GAUGE_LEGACY != POOL_LEGACY,
            "TF_FORK_LEGACY_MINTER_ROUTE: pool/LP/gauge distinct"
        );

        // Live method-2 policy, direct lookup zero, minter pool, reverse
        // match, predicate true.
        (address legacyModule, uint8 legacyMethod) =
            ITrustedValidatorVenue(TRUSTED_VALIDATOR).policyForFactory(LEGACY_FACTORY);
        assertEq(legacyModule, GAUGE_MODULE, "TF_FORK_LEGACY_MINTER_ROUTE: current gauge module policy");
        assertEq(uint256(legacyMethod), LEGACY_POLICY_METHOD, "TF_FORK_LEGACY_MINTER_ROUTE: method 2 policy");
        assertEq(IGaugeVenue(GAUGE_LEGACY).factory(), LEGACY_FACTORY, "TF_FORK_LEGACY_MINTER_ROUTE: gauge factory");
        assertEq(IGaugeVenue(GAUGE_LEGACY).lp_token(), LP_LEGACY, "TF_FORK_LEGACY_MINTER_ROUTE: lp association");
        assertEq(
            IFactoryReverseVenue(LEGACY_FACTORY).get_gauge(LP_LEGACY),
            address(0),
            "TF_FORK_LEGACY_MINTER_ROUTE: direct LP lookup is zero"
        );
        assertEq(
            ILpMinterVenue(LP_LEGACY).minter(), POOL_LEGACY, "TF_FORK_LEGACY_MINTER_ROUTE: minter route to the pool"
        );
        assertEq(
            IFactoryReverseVenue(LEGACY_FACTORY).get_gauge(POOL_LEGACY),
            GAUGE_LEGACY,
            "TF_FORK_LEGACY_MINTER_ROUTE: reverse match on the pool"
        );
        assertTrue(
            ITrustedValidatorVenue(TRUSTED_VALIDATOR).validateGauge(GAUGE_LEGACY),
            "TF_FORK_LEGACY_MINTER_ROUTE: live predicate true for the distinct-LP legacy gauge"
        );
        assertFalse(IGaugeVenue(GAUGE_LEGACY).is_killed(), "TF_FORK_LEGACY_MINTER_ROUTE: live flag false");

        // MetaRegistry authentication at handler/index 0, type 5, two
        // distinct nonzero coins, and genuine controller absence.
        IMetaRegistryVenue reg = IMetaRegistryVenue(METAREGISTRY);
        assertTrue(reg.is_registered(POOL_LEGACY, LEGACY_HANDLER_ID), "TF_FORK_LEGACY_MINTER_ROUTE: registered");
        assertEq(
            reg.get_lp_token(POOL_LEGACY, LEGACY_HANDLER_ID), LP_LEGACY, "TF_FORK_LEGACY_MINTER_ROUTE: registry lp"
        );
        assertEq(
            reg.get_gauge(POOL_LEGACY, LEGACY_GAUGE_INDEX, LEGACY_HANDLER_ID),
            GAUGE_LEGACY,
            "TF_FORK_LEGACY_MINTER_ROUTE: registry gauge"
        );
        assertEq(
            reg.get_gauge_type(POOL_LEGACY, LEGACY_GAUGE_INDEX, LEGACY_HANDLER_ID),
            LEGACY_GAUGE_TYPE,
            "TF_FORK_LEGACY_MINTER_ROUTE: gauge type 5"
        );
        assertEq(reg.get_n_coins(POOL_LEGACY, LEGACY_HANDLER_ID), 2, "TF_FORK_LEGACY_MINTER_ROUTE: two coins");
        address[8] memory coins = reg.get_coins(POOL_LEGACY, LEGACY_HANDLER_ID);
        assertTrue(
            coins[0] != address(0) && coins[1] != address(0) && coins[0] != coins[1],
            "TF_FORK_LEGACY_MINTER_ROUTE: two distinct nonzero coins"
        );
        assertTrue(
            coins[0].code.length > 0 && coins[1].code.length > 0, "TF_FORK_LEGACY_MINTER_ROUTE: coins carry code"
        );
        try IControllerVenue(CONTROLLER).gauge_types(GAUGE_LEGACY) returns (int128 absentType) {
            absentType;
            assertTrue(false, "TF_FORK_LEGACY_MINTER_ROUTE: gauge unexpectedly already in controller");
        } catch (bytes memory ret) {
            assertEq(uint256(ret.length), 0, "TF_FORK_LEGACY_MINTER_ROUTE: absence is an empty revert");
        }

        // Actual paid listing on the amended V1 with real custody/record/
        // membership.
        Trio memory t = _deployTrio(5000);
        _seat(t.lister);
        _fundPayerOnce(payer());
        fvm.prank(payer());
        IErc20Venue(CRVUSD).approve(address(t.lister), FEE);
        // S05: explicit final activation once the prerequisites above hold.
        _activatePaidAdmission(t);
        uint256 payerBefore = IErc20Venue(CRVUSD).balanceOf(payer());
        uint256 nGaugesBefore = uint256(int256(IControllerVenue(CONTROLLER).n_gauges()));
        fvm.recordLogs();
        fvm.prank(payer());
        t.lister.listGauge(POOL_LEGACY, GAUGE_LEGACY, LEGACY_GAUGE_INDEX, LEGACY_HANDLER_ID);
        FVm.Log[] memory logs = fvm.getRecordedLogs();

        // TF_FORK_LEGACY_PAID_EXACT.
        assertEq(IErc20Venue(CRVUSD).balanceOf(payer()), payerBefore - FEE, "TF_FORK_LEGACY_PAID_EXACT: payer debit");
        assertEq(IErc20Venue(CRVUSD).balanceOf(address(t.lister)), FEE, "TF_FORK_LEGACY_PAID_EXACT: core credit");
        assertEq(t.lister.totalEscrow(), FEE, "TF_FORK_LEGACY_PAID_EXACT: totalEscrow FEE");
        CurveGaugeLister.Listing memory rec = t.lister.getListing(GAUGE_LEGACY);
        assertEq(uint256(rec.status), uint256(CurveGaugeLister.Status.Active), "TF_FORK_LEGACY_PAID_EXACT: Active");
        assertEq(rec.pool, POOL_LEGACY, "TF_FORK_LEGACY_PAID_EXACT: pool");
        assertEq(rec.lpToken, LP_LEGACY, "TF_FORK_LEGACY_PAID_EXACT: distinct LP recorded");
        assertEq(rec.payer, payer(), "TF_FORK_LEGACY_PAID_EXACT: payer");
        assertEq(rec.admissionRegistry, METAREGISTRY, "TF_FORK_LEGACY_PAID_EXACT: registry");
        assertEq(rec.gaugeType, LEGACY_GAUGE_TYPE, "TF_FORK_LEGACY_PAID_EXACT: type 5 recorded");
        assertEq(rec.listingEpoch, LISTING_EPOCH, "TF_FORK_LEGACY_PAID_EXACT: epoch");
        assertEq(rec.deposited, FEE, "TF_FORK_LEGACY_PAID_EXACT: deposited");
        assertEq(rec.remaining, FEE, "TF_FORK_LEGACY_PAID_EXACT: remaining");
        assertEq(uint256(rec.epochsReleased), 0, "TF_FORK_LEGACY_PAID_EXACT: epochsReleased");
        assertEq(rec.confiscated, 0, "TF_FORK_LEGACY_PAID_EXACT: confiscated");
        // The legacy row mirrors the SS-ng row's complete original 15-field
        // record coverage.
        assertEq(rec.released, 0, "TF_FORK_LEGACY_PAID_EXACT: released");
        assertEq(rec.votium, address(t.va), "TF_FORK_LEGACY_PAID_EXACT: votium");
        assertEq(rec.voteMarket, address(t.vma), "TF_FORK_LEGACY_PAID_EXACT: votemarket");
        assertEq(uint256(rec.votiumBps), 5000, "TF_FORK_LEGACY_PAID_EXACT: bps");
        assertEq(
            IControllerVenue(CONTROLLER).gauge_types(GAUGE_LEGACY),
            LEGACY_GAUGE_TYPE,
            "TF_FORK_LEGACY_PAID_EXACT: real controller membership type 5"
        );
        assertEq(
            IControllerVenue(CONTROLLER).get_gauge_weight(GAUGE_LEGACY), 0, "TF_FORK_LEGACY_PAID_EXACT: raw weight zero"
        );
        assertEq(
            uint256(int256(IControllerVenue(CONTROLLER).n_gauges())),
            nGaugesBefore + 1,
            "TF_FORK_LEGACY_PAID_EXACT: gauge count advanced"
        );
        bool listed;
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].emitter == address(t.lister) && logs[i].topics.length == 4 && logs[i].topics[0] == T_LISTED) {
                listed = true;
                assertEq(uint256(logs[i].topics[1]), uint256(uint160(GAUGE_LEGACY)), "GaugeListed legacy gauge");
                assertEq(uint256(logs[i].topics[2]), uint256(uint160(POOL_LEGACY)), "GaugeListed legacy pool");
                // Parity with the SS-ng row: the legacy payload pins the
                // payer topic too.
                assertEq(uint256(logs[i].topics[3]), uint256(uint160(payer())), "GaugeListed legacy payer");
                (int128 ty, uint256 ep, uint256 fee, bool dao) =
                    abi.decode(logs[i].data, (int128, uint256, uint256, bool));
                assertEq(ty, LEGACY_GAUGE_TYPE, "GaugeListed legacy type");
                assertEq(ep, LISTING_EPOCH, "GaugeListed legacy epoch");
                assertEq(fee, FEE, "GaugeListed legacy fee");
                assertFalse(dao, "GaugeListed legacy paid");
            }
        }
        assertTrue(listed, "TF_FORK_LEGACY_PAID_EXACT: GaugeListed emitted and decoded");
        // There is no legacy bounty route to prove here; the legacy factory
        // remains outside the retired supported-kill governance machinery.
    }
}
