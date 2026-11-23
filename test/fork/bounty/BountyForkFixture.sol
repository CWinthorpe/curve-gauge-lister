// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {
    ForkFixture,
    FVm,
    IErc20Venue,
    IControllerVenue,
    IMetaRegistryVenue,
    IGaugeVenue,
    IFactoryVenue,
    IProxyVenue
} from "../ForkFixture.sol";
import {GaugeBounty} from "../../../contracts/GaugeBounty.sol";
import {CurveGaugeListerV2} from "../../../contracts/CurveGaugeListerV2.sol";
import {BountyConfig} from "../../../contracts/bounty/BountyTypes.sol";
import {BountyScripts} from "../../../contracts/libraries/BountyScripts.sol";
import {VotiumAdapter} from "../../../contracts/adapters/VotiumAdapter.sol";
import {VoteMarketAdapter} from "../../../contracts/adapters/VoteMarketAdapter.sol";

/// @dev Abstract kit for the thin bounty fork suites (plans/BOUNTY-THIN-PLAN.md
/// §7.3). Inherits the FROZEN ForkFixture for provenance/transport helpers and
/// adds a separately typed V2/bounty deployment kit; no frozen fixture file or
/// its private helpers are edited or overridden. All pinned live facts below
/// were re-verified read-only at the frozen pin (block 26401019, hash
/// 0x55810b079923a14fb97ad548f5024f65530dbc4fb2357a38f41e13b3d27cb6d3,
/// timestamp 1794512471) with eth_call/eth_getCode BEFORE any mutation, and
/// are re-asserted here per run, before writes.
///
/// Disclosed fixtures (labelled, per §7.3 — all effects are LOCAL fork
/// simulations, never broadcasts):
///  * crvUSD uses the frozen fixture's disclosed
///    CRVUSD_HOLDER path. No token deal/storage edits, no invented gauges.
///  * Controller seating reuses the frozen fork-only two-step impersonation:
///    NOT production GaugeAdder authorization.
///  * Second-listing candidate (pool 0x123B0134930BD5cF8f26b3E3c621acbc791A294b,
///    gauge 0x9D81d64A0e17d02EA8FD962FA13F4B89146d9a43 = FORK-PLAN §4 fallback 1)
///    re-proved eligible at THIS pin: registry membership, lp association,
///    (0,0) gauge slot, two real coins, authentic factory, false kill flag,
///    genuine controller absence (empty-revert).
struct Kit {
    GaugeBounty b;
    CurveGaugeListerV2 core_;
    address va;
    address vma;
}

interface IOwnershipVotingFacts {
    function minBalance() external view returns (uint256);
    function minTime() external view returns (uint256);
    function voteTime() external view returns (uint256);
    function supportRequiredPct() external view returns (uint256);
    function minAcceptQuorumPct() external view returns (uint256);
    function enableVoteCreation() external view returns (bool);
}

/// @dev Reporter-side real Voting creation surface (fixture interfaces are
/// separate from the bounty-facing IOwnershipVoting per rework plan §2).
interface IVotingCreate {
    function newVote(bytes calldata script, string calldata metadata, bool castVote, bool executesIfDecided)
        external
        returns (uint256);
}

interface IVotingCreateFacts {
    function lastCreateVoteTimes(address creator) external view returns (uint256);
}

abstract contract BountyForkFixture is ForkFixture {
    // ----------------------- pinned live identities (verified at the pin) --
    address internal constant THIN_CRV = 0xD533a949740bb3306d119CC777fa900bA034cd52;
    address internal constant THIN_VE_CRV = 0x5f3b5DfEb7B28CDbD7FAba78963EE202a494e2A2;
    address internal constant THIN_VOTING_APP = 0xE478de485ad2fe566d49342Cbd03E49ed7DB3356;
    address internal constant THIN_VOTING_IMPL = 0xa4D1a2693589840BABb7f3A44D14Fdf41b3bF1Fe;
    address internal constant THIN_AGENT = 0x40907540d8a6C65c637785e8f8B742ae6b0b9968; // == DAO
    address internal constant THIN_AGENT_IMPL = 0x3A93C17FC82CC33420d1809dDA9Fb715cc89dd37;
    address internal constant THIN_CALLS_SCRIPT = 0x5cEb19e1890f677c3676d5ecDF7c501eBA01A054;

    address internal constant THIN_KILL_PROXY = 0xeDA0108D5bB8cdE2ba4A59E22F3Ed5d211C77187;
    address internal constant THIN_CRV_HOLDER = 0xf8191D98ae98d2f7aBDFB63A9b0b812b93C873AA;

    // Second-listing candidate (FORK-PLAN §4 fallback 1), re-proved at the pin.
    address internal constant POOL_SECOND = 0x123B0134930BD5cF8f26b3E3c621acbc791A294b;
    address internal constant GAUGE_SECOND = 0x9D81d64A0e17d02EA8FD962FA13F4B89146d9a43;

    uint256 internal constant STAKE = 1000e18;

    uint256 internal constant COOLDOWN = 43200;
    uint256 internal constant VOTE_TIME = 604800;

    /// @dev Real Voting app surface shared by the execution and custody specs.
    /// (The concrete voter set is injected via forkVoters().)
    /// @dev Executor fixture discovery (read-only log scan, disclosed): the
    /// 8 largest real YES voters whose pinned (block 26401019) veCRV
    /// `balanceOf` totals 290,708,349.4 veCRV — above the 30% acceptance
    /// quorum of the 772.6M pinned snapshot supply with ~25% margin. Each
    /// voter's positive pinned power is re-asserted at runtime before use;
    /// ballots are voted strictly inside their own window and executed
    /// through the genuine vote/executeVote APIs. No tally/flag writes.
    function forkVoters() internal pure returns (address[] memory v) {
        v = new address[](8);
        v[0] = 0x52f541764E6e90eeBc5c21Ff570De0e2D63766B6; // 118.19M
        v[1] = 0xF147b8125d2ef93FB6965Db97D6746952a133934; // 83.13M
        v[2] = 0x7a16fF8270133F063aAb6C9977183D9e72835428; // 24.75M
        v[3] = 0x9B44473E223f8a3c047AD86f387B80402536B029; // 24.01M
        v[4] = 0xF89501B77b2FA6329F94F5A05FE84cEbb5c8b1a0; // 20.63M
        v[5] = 0x425d16B0e08a28A3Ff9e4404AE99D78C0a076C5A; // 14.63M
        v[6] = 0x32D03DB62e464c9168e41028FFa6E9a05D8C6451; // 4.70M
        v[7] = 0x39415255619783A2E71fcF7d8f708A951d92e1b6; // 0.66M
    }

    uint256 internal constant QUORUM_POWER_MIN = 231_770_557e18; // 30% of pinned totalSupply

    /// @dev Read-only preflight of every governance fact the product itself
    /// re-checks, at the exact pin, BEFORE any deployment/mutation.
    function _assertThinFactsAtPin() internal view {
        assertEq(block.chainid, 1, "fork: mainnet");
        // Role bindings the constructor and submit re-check.
        assertEq(IFactoryVenue(FACTORY).admin(), THIN_KILL_PROXY, "fork: factory admin is the kill proxy");
        assertEq(IProxyVenue(THIN_KILL_PROXY).dao(), THIN_AGENT, "fork: proxy dao is the Ownership Agent");
        assertEq(IProxyVenue(THIN_KILL_PROXY).emergency_dao(), EMERGENCY_DAO, "fork: emergency dao");
        assertTrue(THIN_AGENT.code.length > 0, "fork: agent has code");
        // Escrow identity chain.
        assertEq(IErc20Venue(THIN_CRV).decimals(), 18, "fork: CRV 18");
        assertEq(IErc20Venue(CRVUSD).decimals(), 18, "fork: crvUSD 18");
        // FD identity via the accepted policy (also constructor-gated).
        // Voting parameters pinned by the product (§2.1).
        assertEq(IOwnershipVotingFacts(THIN_VOTING_APP).minBalance(), 2500e18, "fork: minBalance");
        assertEq(IOwnershipVotingFacts(THIN_VOTING_APP).minTime(), COOLDOWN, "fork: minTime");
        assertEq(IOwnershipVotingFacts(THIN_VOTING_APP).voteTime(), VOTE_TIME, "fork: voteTime");
        assertEq(IOwnershipVotingFacts(THIN_VOTING_APP).supportRequiredPct(), 510000000000000000, "fork: support");
        assertEq(IOwnershipVotingFacts(THIN_VOTING_APP).minAcceptQuorumPct(), 300000000000000000, "fork: quorum");
        assertTrue(IOwnershipVotingFacts(THIN_VOTING_APP).enableVoteCreation(), "fork: creation enabled");
        // CRV funding source: real holder, real balance at the pin, no code.
        assertTrue(IErc20Venue(THIN_CRV).balanceOf(THIN_CRV_HOLDER) >= 1_000_000e18, "fork: CRV holder funded");
        uint256 hc;
        assembly {
            hc := extcodesize(THIN_CRV_HOLDER)
        }
        assertEq(hc, 0, "fork: CRV holder is EOA-shaped");
    }

    /// @dev Minimal read subset for the pinned live Voting app.

    /// @dev Re-prove the FORK-PLAN §4 second candidate's prerequisites at this
    /// exact pin (registry membership, LP/coins, factory, false flag, absent
    /// from the controller with an EMPTY-data revert).
    function _assertSecondCandidateProvenance() internal {
        IMetaRegistryVenue reg = IMetaRegistryVenue(METAREGISTRY);
        assertTrue(reg.is_registered(POOL_SECOND, HANDLER_ID), "fork2: pool registered");
        assertEq(reg.get_lp_token(POOL_SECOND, HANDLER_ID), POOL_SECOND, "fork2: lp = pool");
        assertEq(reg.get_gauge(POOL_SECOND, GAUGE_INDEX, HANDLER_ID), GAUGE_SECOND, "fork2: gauge at (0,0)");
        assertEq(reg.get_n_coins(POOL_SECOND, HANDLER_ID), 2, "fork2: two coins");
        IGaugeVenue g = IGaugeVenue(GAUGE_SECOND);
        assertEq(g.lp_token(), POOL_SECOND, "fork2: gauge lp association");
        assertFalse(g.is_killed(), "fork2: live flag false");
        assertEq(g.factory(), FACTORY, "fork2: authentic factory");
        assertTrue(GAUGE_SECOND.code.length > 0 && POOL_SECOND.code.length > 0, "fork2: code present");
        try IControllerVenue(CONTROLLER).gauge_types(GAUGE_SECOND) returns (int128 t) {
            t;
            assertTrue(false, "fork2: gauge unexpectedly already in controller");
        } catch (bytes memory ret) {
            assertEq(uint256(ret.length), 0, "fork2: absence is an empty revert");
        }
    }

    /// @dev Deploy bounty + a fresh V2 core wired to the REAL venues/adapters
    /// with the frozen seating/funding paths. No V1 fixture helper is reused
    /// for the V2 side (separate typed kit).
    function _deployThinKit() internal returns (Kit memory k) {
        _assertThinFactsAtPin();
        BountyConfig memory cfg;
        cfg.crvUSD = CRVUSD;
        cfg.feeDistributor = FEEDIST;
        cfg.ownershipVoting = THIN_VOTING_APP;
        cfg.ownershipAgent = THIN_AGENT;
        cfg.killProxy = THIN_KILL_PROXY;
        cfg.supportedFactory = FACTORY;
        cfg.votingImplementation = THIN_VOTING_IMPL;
        cfg.agentImplementation = THIN_AGENT_IMPL;
        cfg.callsScriptExecutor = THIN_CALLS_SCRIPT;

        k.b = new GaugeBounty(cfg);
        VotiumAdapter va = new VotiumAdapter(CRVUSD, DAO, VOTIUM);
        VoteMarketAdapter vma = new VoteMarketAdapter(CRVUSD, DAO, CRM, VM_DESTINATION);
        // Plan §6: the fork fixture passes the ACTUAL validator pin and
        // asserts its code identity BEFORE construction (read-only live
        // verification; a mismatch fails the suite, never a substitute).
        _assertValidatorPinAtFork();
        k.core_ = new CurveGaugeListerV2(
            THIN_AGENT, // bind-time config owner IS the configured Agent (§2.1)
            CRVUSD,
            CONTROLLER,
            FEEDIST,
            CurveGaugeListerV2.AdmissionConfig(METAREGISTRY, 8),
            CurveGaugeListerV2.PlatformConfig(address(va), address(vma), 5000),
            address(k.b),
            TRUSTED_VALIDATOR
        );
        k.va = address(va);
        k.vma = address(vma);
        fvm.startPrank(DAO);
        va.setLister(address(k.core_));
        vma.setLister(address(k.core_));
        // Fork-only controller seating (frozen disclosure: NOT production
        // GaugeAdder authorization).
        IControllerVenue(CONTROLLER).commit_transfer_ownership(address(k.core_));
        IControllerVenue(CONTROLLER).apply_transfer_ownership();
        fvm.stopPrank();
        assertEq(IControllerVenue(CONTROLLER).admin(), address(k.core_), "fork: controller seated to V2");
        assertEq(k.b.lister(), address(0), "bounty starts unbound");
        // The Agent performs the one-time reciprocal bind.
        fvm.prank(THIN_AGENT);
        k.b.bindLister(address(k.core_));
        assertEq(k.b.lister(), address(k.core_), "fork: reciprocal bind");
        // Unpause listings: the config owner here is the (disclosed) Agent,
        // matching the frozen offline kit's owner-first-Agent wiring.
        fvm.prank(THIN_AGENT);
        k.core_.setPaused(false);
        return k;
    }

    /// @dev List the primary candidate on a kit's V2 (paid path, real fee via
    /// the frozen holder-prank funding) after the primary provenance re-check.
    function _listPrimary(Kit memory k) internal returns (address gauge) {
        _fundPayerOnce(payer_());
        fvm.prank(payer_());
        IErc20Venue(CRVUSD).approve(address(k.core_), FEE);
        fvm.prank(payer_());
        k.core_.listGauge(POOL_PRIMARY, GAUGE_PRIMARY, GAUGE_INDEX, HANDLER_ID);
        assertTrue(k.core_.listingId(GAUGE_PRIMARY) != bytes32(0), "fork: primary listed");
        return GAUGE_PRIMARY;
    }

    /// @dev List the re-proved second candidate on the same V2 core.
    function _listSecond(Kit memory k) internal returns (address gauge) {
        _assertSecondCandidateProvenance();
        _fundPayerOnce(payer_());
        fvm.prank(payer_());
        IErc20Venue(CRVUSD).approve(address(k.core_), FEE);
        fvm.prank(payer_());
        k.core_.listGauge(POOL_SECOND, GAUGE_SECOND, GAUGE_INDEX, HANDLER_ID);
        assertTrue(k.core_.listingId(GAUGE_SECOND) != bytes32(0), "fork: second listed");
        return GAUGE_SECOND;
    }

    // --------------- beneficiary-bound ballot helpers (rework §7/F01) -----
    //
    // The bounty NEVER creates ballots. A disclosed real veCRV holder (the
    // largest pinned voter, positive power re-asserted before use) acts as
    // the ACTUAL CREATOR/sponsor through the real newVote API; the
    // beneficiary named inside the canonical script submits. Creator !=
    // beneficiary is the sanctioned sponsorship shape; the creator identity
    // is fixture provenance only, never admitted by the product.

    /// @dev Disclosed sponsor creator (real proposal rights at the pin).
    function forkBallotCreator() internal pure returns (address) {
        return 0x52f541764E6e90eeBc5c21Ff570De0e2D63766B6;
    }

    /// @dev Precompute the exact canonical report id for a future submission
    /// by `beneficiary` with (gauge, nonce, evidence).
    function _forkReportId(Kit memory k, address gauge, address beneficiary, uint256 nonce, bytes32 eh)
        internal
        view
        returns (bytes32)
    {
        return BountyScripts.reportId(
            address(k.b), block.chainid, k.b.lister(), gauge, k.core_.listingId(gauge), beneficiary, nonce, eh
        );
    }

    /// @dev Create the REAL beneficiary-bound ballot through the deployed
    /// Voting app (waits out the per-creator 12h interval deterministically).
    function _createForkBallot(Kit memory k, address gauge, address beneficiary, uint256 nonce, bytes32 eh)
        internal
        returns (bytes32 reportId, uint256 proposalId)
    {
        address creator = forkBallotCreator();
        assertTrue(IErc20Venue(THIN_VE_CRV).balanceOf(creator) > 0, "fork: creator has real veCRV voting power");
        reportId = _forkReportId(k, gauge, beneficiary, nonce, eh);
        bytes memory script =
            BountyScripts.buildKillScript(THIN_AGENT, address(k.b), THIN_KILL_PROXY, gauge, reportId, beneficiary);
        uint256 last = IVotingCreateFacts(THIN_VOTING_APP).lastCreateVoteTimes(creator);
        if (last != 0 && block.timestamp < last + COOLDOWN) fvm.warp(last + COOLDOWN);
        fvm.prank(creator);
        proposalId = IVotingCreate(THIN_VOTING_APP).newVote(script, "", false, false);
    }

    /// @dev Full admission: real creator binds the canonical script, then
    /// the BENEFICIARY submits with the exact stake.
    function _submitForkBallot(Kit memory k, address gauge, address beneficiary, uint256 nonce, bytes32 eh)
        internal
        returns (bytes32 reportId, uint256 proposalId)
    {
        (reportId, proposalId) = _createForkBallot(k, gauge, beneficiary, nonce, eh);
        fvm.prank(beneficiary);
        bytes32 id = k.b.submit(gauge, proposalId, eh, nonce);
        require(id == reportId, "fork: submitted id equals the precomputed id");
    }

    /// @dev Fund + approve a reporter's exact stake via the disclosed
    /// crvUSD holder prank (normal transfers only).
    function _fundReporter(Kit memory k, address who, uint256 times) internal {
        uint256 need = STAKE * times;
        uint256 holderBefore = IErc20Venue(CRVUSD).balanceOf(CRVUSD_HOLDER);
        uint256 before = IErc20Venue(CRVUSD).balanceOf(who);
        fvm.prank(CRVUSD_HOLDER);
        IErc20Venue(CRVUSD).transfer(who, need);
        assertEq(IErc20Venue(CRVUSD).balanceOf(CRVUSD_HOLDER), holderBefore - need, "fork: exact stake debit");
        assertEq(IErc20Venue(CRVUSD).balanceOf(who), before + need, "fork: stake credit");
        fvm.prank(who);
        IErc20Venue(CRVUSD).approve(address(k.b), need);
    }

    /// @dev Local reporter identity (funded via the disclosed holder path).
    function reporter_() internal pure returns (address) {
        return address(uint160(uint256(keccak256(bytes("bountythin-fork-reporter")))));
    }

    function payer_() internal pure returns (address) {
        return address(uint160(uint256(keccak256(bytes("bountythin-fork-payer")))));
    }
}
