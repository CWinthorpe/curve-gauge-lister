// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BountyTestBase} from "./BountyTestBase.sol";
import {BountyConfig} from "../../contracts/bounty/BountyTypes.sol";
import {BountyScripts} from "../../contracts/libraries/BountyScripts.sol";
import {CurveGaugeListerV2} from "../../contracts/CurveGaugeListerV2.sol";
import {IERC20Minimal} from "../../contracts/interfaces/IERC20Minimal.sol";
import {MockERC20} from "../../contracts/mocks/MockERC20.sol";
import {MockPool} from "../../contracts/mocks/MockPool.sol";
import {MockGauge} from "../../contracts/mocks/MockGauge.sol";
import {MockCurveRegistry} from "../../contracts/mocks/MockCurveRegistry.sol";
import {MockListingController} from "../../contracts/mocks/MockListingController.sol";
import {MockFeeDistributor} from "../../contracts/mocks/MockFeeDistributor.sol";
import {MockIncentivePlatform} from "../../contracts/mocks/MockIncentivePlatform.sol";
import {MockOwnershipVoting} from "./mocks/MockOwnershipVoting.sol";
import {MockVotingEscrow} from "./mocks/MockVotingEscrow.sol";
import {
    MockWalletChecker,
    MockSupportedFactory,
    GovernanceGauge,
    MockKillProxy,
    MockOwnershipAgent,
    MockCallsScript
} from "./mocks/MockBountyGovernance.sol";
import {MockBountyHook} from "./mocks/MockBountyHook.sol";
import {AlwaysTrueTrustedValidator} from "../mocks/TrustedFactoryMocks.sol";
import {GaugeBounty} from "../../contracts/GaugeBounty.sol";
import {SilentRecipient} from "./mocks/BountyFaultActors.sol";

/// @notice Shared offline world for the bounty and V2 suites
/// (plans/BOUNTY-PLAN.md §5.1): real deployed mocks injected through normal
/// constructors, wired to exactly the role identities the GaugeBounty/V2
/// constructors demand. Suites call `setupBountyWorld()` from their own
/// `setUp()`; production deployments (V2, GaugeBounty) attach in later
/// packages via the deploy helpers here.
abstract contract BountyFixture is BountyTestBase {
    // ------------------------------- roles --------------------------------
    address internal daoOwner; // lister owner (CurveDAO multisig analogue)
    address internal controllerDao;
    address internal fdAdmin;
    address internal payer;
    address internal reporter;
    address internal secondReporter;
    address internal treasury; // projectTreasury (EOA-shaped: nonzero only)
    address internal emergencySafe;
    address internal stranger;
    address internal votingDao; // mock-Voting admin for parameter changes

    // ------------------------------ systems -------------------------------
    MockERC20 internal crvUSD;
    MockERC20 internal crv;
    MockFeeDistributor internal fd;
    MockCurveRegistry internal registry;
    MockListingController internal controller;
    MockIncentivePlatform internal votium;
    MockIncentivePlatform internal voteMarket;

    MockWalletChecker internal checker;
    MockVotingEscrow internal escrow;
    MockOwnershipVoting internal voting;
    address internal votingImplementation;
    address internal agentImplementation;
    MockOwnershipAgent internal agent;
    MockCallsScript internal callsScript;
    MockKillProxy internal killProxy;
    MockSupportedFactory internal factory;

    MockBountyHook internal hook; // strict stand-in until real bounty exists
    CurveGaugeListerV2 internal v2; // default core for the parity suites
    GaugeBounty internal bounty; // the real bounty once deployed

    /// @dev Disclosed HEALTHY CHECKER STAND-IN (plans/TRUSTEDFACTORY-PLAN.md
    /// §6): supplies the eighth constructor argument to the retained baseline
    /// fixtures so their original downstream obligations stay reachable. It
    /// proves constructor parameterization only — never that a live
    /// non-factory gauge passes trust verification. Dedicated new trust tests
    /// use their own fixtures instead.
    AlwaysTrueTrustedValidator internal tfValidator;

    /// @dev Per-suite pool/gauge counter keeps registry keys unique.
    uint256 internal _nextSlot = 1;
    /// @dev Handler slot used by the most recent deployGovernanceGauge /
    /// deployPlainGauge call (registries key by (pool, handlerId)).
    uint256 internal lastSlot;

    function setupBountyWorld() internal {
        // V2/GaugeBounty constructors require mainnet chain id 1; forge's
        // offline default is 31337. Suites that need other chain ids (e.g.
        // the VoteMarket source-chain case) may switch it AFTER deployment.
        vm.chainId(1);
        daoOwner = actor("daoMultisig");
        controllerDao = actor("controllerDao");
        fdAdmin = actor("fdAdmin");
        payer = actor("feePayer");
        reporter = actor("reporter");
        secondReporter = actor("secondReporter");
        treasury = actor("projectTreasury");
        emergencySafe = address(new SilentRecipient()); // code required by the constructor role checks
        stranger = actor("stranger");
        votingDao = actor("votingDao");

        vm.warp(T0);

        crvUSD = new MockERC20(18);
        crv = new MockERC20(18);
        fd = new MockFeeDistributor(address(crvUSD), fdAdmin, T0);
        registry = new MockCurveRegistry();
        controller = new MockListingController(controllerDao, int128(2));
        votium = new MockIncentivePlatform(address(crvUSD));
        voteMarket = new MockIncentivePlatform(address(crvUSD));

        checker = new MockWalletChecker();
        escrow = new MockVotingEscrow(address(crv), address(checker));
        votingImplementation = address(new MockOwnershipAgent(address(this), address(this)));
        agentImplementation = address(new MockOwnershipAgent(address(this), address(this)));
        voting = new MockOwnershipVoting(address(escrow), votingDao, votingImplementation);
        callsScript = new MockCallsScript(address(voting));
        agent = new MockOwnershipAgent(agentImplementation, address(callsScript));
        killProxy = new MockKillProxy(address(agent), emergencySafe);
        factory = new MockSupportedFactory(address(killProxy));

        vm.prank(votingDao);
        voting.setEVMScriptExecutor(0x00000001, address(callsScript));

        hook = new MockBountyHook(address(crvUSD), address(fd));
        tfValidator = new AlwaysTrueTrustedValidator();
    }

    // --------------------------- V2 deployment ----------------------------

    /// @notice Deploy a V2 core against explicit dependency addresses; NO
    /// seating, NO hook binding and NO unpause (tests exercise the wiring
    /// order deliberately). Defaults mirror the frozen baseline constructor.
    /// The eighth argument receives the disclosed healthy checker stand-in.
    function deployV2Core(address controller_, address votium_, address voteMarket_, address bounty_)
        internal
        returns (CurveGaugeListerV2 core_)
    {
        return deployV2CoreWithValidator(controller_, votium_, voteMarket_, bounty_, address(tfValidator));
    }

    /// @notice Same deployment with an EXPLICIT validator pin (dedicated trust
    /// witnesses and constructor-negative cells supply their own checker).
    function deployV2CoreWithValidator(
        address controller_,
        address votium_,
        address voteMarket_,
        address bounty_,
        address validator_
    ) internal returns (CurveGaugeListerV2 core_) {
        core_ = new CurveGaugeListerV2(
            daoOwner,
            address(crvUSD),
            controller_,
            address(fd),
            CurveGaugeListerV2.AdmissionConfig(address(registry), 8),
            CurveGaugeListerV2.PlatformConfig(votium_, voteMarket_, 5000),
            bounty_,
            validator_
        );
    }

    /// @notice Full honest wiring for a fresh core: seat the controller
    /// (via its DAO), bind both platform mocks, bind the hook as the Agent
    /// would, then unpause. Mirrors §1.2 "finish all wiring and verify
    /// readback before unpausing".
    function bindAndUnpause(
        CurveGaugeListerV2 core_,
        MockListingController ctl,
        address votium_,
        address voteMarket_,
        MockBountyHook bountyHook_
    ) internal {
        vm.prank(controllerDao);
        ctl.setLister(address(core_));
        MockIncentivePlatform(votium_).setLister(address(core_));
        MockIncentivePlatform(voteMarket_).setLister(address(core_));
        bountyHook_.bindLister(address(core_));
        vm.prank(daoOwner);
        core_.setPaused(false);
        vm.startPrank(payer);
        crvUSD.approve(address(core_), type(uint256).max);
        vm.stopPrank();
    }

    /// @notice Deploy + bind + unpause the default V2 world against fresh
    /// platform mocks and a fresh hook on the default controller pair.
    function deployDefaultV2() internal returns (CurveGaugeListerV2 core_) {
        MockIncentivePlatform freshVotium = new MockIncentivePlatform(address(crvUSD));
        MockIncentivePlatform freshVoteMarket = new MockIncentivePlatform(address(crvUSD));
        MockListingController freshController = new MockListingController(controllerDao, int128(2));
        MockBountyHook freshHook = new MockBountyHook(address(crvUSD), address(fd));
        core_ =
            deployV2Core(address(freshController), address(freshVotium), address(freshVoteMarket), address(freshHook));
        bindAndUnpause(core_, freshController, address(freshVotium), address(freshVoteMarket), freshHook);
        // expose the freshly-bound trio for convenience in parity suites
        controller = freshController;
        votium = freshVotium;
        voteMarket = freshVoteMarket;
        hook = freshHook;
        v2 = core_;
    }

    // --------------------------- bounty deployment ------------------------

    /// @notice Deploy the real GaugeBounty against the honest fixture world.
    function deployBounty() internal returns (GaugeBounty b) {
        b = new GaugeBounty(defaultBountyConfig());
        bounty = b;
    }

    /// @notice Full honest wiring of the NEW pair: deploy bounty, deploy V2
    /// against it (fresh controller/platforms), let the actual Agent bind,
    /// verify reciprocity, then unpause (§1.2 deploy order and checks).
    /// @notice Thin deployment order (plans/BOUNTY-THIN-PLAN.md §2.1):
    /// bounty, then PAUSED V2 whose initial config owner IS the configured
    /// Ownership Agent, bind through that Agent, move config authority to
    /// the DAO via the real two-step transfer, then unpause. An outsider
    /// cannot win a first-caller binding race.
    function deployBoundPair() internal returns (CurveGaugeListerV2 core_, GaugeBounty b) {
        b = new GaugeBounty(defaultBountyConfig());
        bounty = b;
        MockIncentivePlatform freshVotium = new MockIncentivePlatform(address(crvUSD));
        MockIncentivePlatform freshVoteMarket = new MockIncentivePlatform(address(crvUSD));
        MockListingController freshController = new MockListingController(controllerDao, int128(2));
        core_ = new CurveGaugeListerV2(
            address(agent), // initial owner: the configured Ownership Agent
            address(crvUSD),
            address(freshController),
            address(fd),
            CurveGaugeListerV2.AdmissionConfig(address(registry), 8),
            CurveGaugeListerV2.PlatformConfig(address(freshVotium), address(freshVoteMarket), 5000),
            address(b),
            address(tfValidator)
        );
        vm.prank(controllerDao);
        freshController.setLister(address(core_));
        freshVotium.setLister(address(core_));
        freshVoteMarket.setLister(address(core_));
        vm.prank(address(agent));
        b.bindLister(address(core_));
        assertEq(b.lister(), address(core_), "reciprocal binding verified");
        assertEq(core_.bounty(), address(b), "reverse pointer verified");
        // Hand the (now-bound) config authority to the DAO, then unpause.
        vm.prank(address(agent));
        core_.transferOwnership(daoOwner);
        vm.prank(daoOwner);
        core_.acceptOwnership();
        vm.prank(daoOwner);
        core_.setPaused(false);
        v2 = core_;
        controller = freshController;
        votium = freshVotium;
        voteMarket = freshVoteMarket;
    }

    /// @dev Kill through the honest governance route (factory admin == the
    /// AMM owner proxy, which hardcodes the gauge boolean to true).
    function killGaugeViaRoute(address gauge) internal {
        vm.prank(address(killProxy));
        GovernanceGauge(gauge).set_killed(true);
    }

    /// @dev Authorized unkill (factory admin route; AMM execute in production).
    function unkillGaugeViaRoute(address gauge) internal {
        vm.prank(address(killProxy));
        GovernanceGauge(gauge).set_killed(false);
    }

    // --------------------------- submission helpers -------------------------

    /// @notice List a paid, authorized, live governance-route gauge on the
    /// bound V2 core: deploy, authorize, fund+approve payer, list. Returns
    /// (pool, gauge, slot).
    function listBountyEligible(CurveGaugeListerV2 core_) internal returns (address pool, address gauge, uint256 slot) {
        (pool, gauge,) = deployGovernanceGauge();
        slot = lastSlot;
        crvUSD.mint(payer, FEE);
        approveCrvUsd(payer, address(core_), FEE);
        vm.prank(payer);
        core_.listGauge(pool, gauge, 0, slot);
    }

    /// @dev Fund + approve the exact stake for a reporter (default bounty).
    function fundStake(address who) internal {
        fundStake(bounty, who);
    }

    /// @dev Fund + approve the exact stake for a reporter against a given
    /// bounty instance.
    function fundStake(GaugeBounty b_, address who) internal {
        crvUSD.mint(who, STAKE);
        approveCrvUsd(who, address(b_), STAKE);
    }

    // --------------------------- config builders --------------------------

    /// @notice Complete honest configuration for GaugeBounty construction.
    function defaultBountyConfig() internal view returns (BountyConfig memory cfg) {
        cfg.crvUSD = address(crvUSD);
        cfg.feeDistributor = address(fd);
        cfg.ownershipVoting = address(voting);
        cfg.ownershipAgent = address(agent);
        cfg.killProxy = address(killProxy);
        cfg.supportedFactory = address(factory);
        cfg.votingImplementation = votingImplementation;
        cfg.agentImplementation = agentImplementation;
        cfg.callsScriptExecutor = address(callsScript);
    }

    // ------------------------- registry fixtures --------------------------

    function _coins(address a, address b) internal pure returns (address[8] memory c) {
        c[0] = a;
        c[1] = b;
    }

    /// @dev Deploy a registry-authenticated pool/LP with a governance-route
    /// gauge (factory route fully wired). Returns (pool, gauge, lp).
    function deployGovernanceGauge() internal returns (address pool, address gauge, address lp) {
        uint256 slot = _nextSlot++ % 10; // MetaRegistry handler bound is 0..9; pools are unique contracts
        lastSlot = slot;
        lp = address(new MockERC20(18));
        pool = address(new MockPool());
        gauge = address(new GovernanceGauge(lp, address(factory)));
        registry.setPool(pool, slot, lp, _coins(address(new MockERC20(18)), address(new MockERC20(18))), 2);
        registry.setGauge(pool, slot, 0, gauge, int128(0));
    }

    /// @dev Deploy a plain (non-governance-route) gauge as the admission
    /// control: MockGauge self-reports NO factory, exercising the
    /// `factory()`-is-not-authentication rule.
    function deployPlainGauge() internal returns (address pool, address gauge, address lp) {
        uint256 slot = _nextSlot++ % 10;
        lastSlot = slot;
        lp = address(new MockERC20(18));
        pool = address(new MockPool());
        gauge = address(new MockGauge(lp));
        registry.setPool(pool, slot, lp, _coins(address(new MockERC20(18)), address(new MockERC20(18))), 2);
        registry.setGauge(pool, slot, 0, gauge, int128(0));
        return (pool, gauge, lp);
    }

    // ----------------------------- funding --------------------------------

    function approveCrvUsd(address from, address spender, uint256 amount) internal {
        vm.prank(from);
        crvUSD.approve(spender, amount);
    }

    function approveCrv(address from, address spender, uint256 amount) internal {
        vm.prank(from);
        crv.approve(spender, amount);
    }

    // --------------------- ve power for mock Voting -----------------------

    /// @notice Give `who` a real, decayed veCRV lock through the model's own
    /// funding path (mint, approve, create_lock at the full horizon).
    function fundCrv(address to, uint256 amount) internal {
        crv.mint(to, amount);
    }

    function giveVePower(address who, uint256 rawCrv) internal {
        fundCrv(who, rawCrv);
        approveCrv(who, address(escrow), rawCrv);
        vm.prank(who);
        escrow.create_lock(rawCrv, ((block.timestamp + MAX_TIME) / WEEK) * WEEK);
    }

    /// @dev Ensure `who` can exercise upstream proposal rights in the mock
    /// Voting model (creator side only; the bounty never reads any checker).
    function ensureVePower(address who) internal {
        if (escrow.balanceOf(who) < MIN_BALANCE) {
            (bool lockedOk, bytes memory raw) =
                address(escrow).staticcall(abi.encodeWithSignature("locked(address)", who));
            if (lockedOk && raw.length >= 64) {
                (int128 amount,) = abi.decode(raw, (int128, uint256));
                if (amount > 0) {
                    fundCrv(who, MIN_BALANCE);
                    approveCrv(who, address(escrow), MIN_BALANCE);
                    vm.prank(who);
                    escrow.increase_amount(MIN_BALANCE);
                    return;
                }
            }
            giveVePower(who, MIN_BALANCE + 100e18);
        }
    }

    // --------------------- beneficiary-bound ballot helpers ----------------

    /// @notice Precompute the EXACT canonical report identity a submission by
    /// `who` with (gauge, nonce, evidence) will produce — before any ballot
    /// exists. Uses the live listing id, the deployed domain and the caller
    /// as the beneficiary.
    function computeReportId(GaugeBounty b_, address core_, address gauge, address who, uint256 nonce, bytes32 eh)
        internal
        view
        returns (bytes32)
    {
        bytes32 lid = CurveGaugeListerV2(core_).listingId(gauge);
        return BountyScripts.reportId(address(b_), block.chainid, core_, gauge, lid, who, nonce, eh);
    }

    /// @notice The exact canonical three-action script for a future report:
    /// creditBallot(reportId, beneficiary), proxy kill, recognizeKill.
    function canonicalKillScript(GaugeBounty b_, address gauge, bytes32 reportIdKey, address beneficiary)
        internal
        view
        returns (bytes memory)
    {
        return BountyScripts.buildKillScript(
            address(agent), address(b_), address(killProxy), gauge, reportIdKey, beneficiary
        );
    }

    /// @notice Create a beneficiary-bound Ownership ballot: the canonical
    /// script S(reportId, beneficiary, gauge) naming the exact future
    /// submitter, created on-chain by `creator` — which may be a sponsor
    /// distinct from the beneficiary (actual-creator equality is NOT the
    /// admitted policy). Waits out the creator's upstream per-creator
    /// cooldown deterministically (the creator-side interval stays real).
    /// Returns (reportId, actual proposalId).
    function createBeneficiaryBallot(
        GaugeBounty b_,
        address core_,
        address gauge,
        address beneficiary,
        address creator,
        uint256 nonce,
        bytes32 eh
    ) internal returns (bytes32 reportId, uint256 proposalId) {
        reportId = computeReportId(b_, core_, gauge, beneficiary, nonce, eh);
        bytes memory script = canonicalKillScript(b_, gauge, reportId, beneficiary);
        ensureVePower(creator);
        uint256 last = voting.lastCreateVoteTimes(creator);
        if (last != 0 && block.timestamp < last + COOLDOWN) vm.warp(last + COOLDOWN);
        vm.prank(creator);
        proposalId = voting.newVote(script, "", false, false);
    }

    /// @notice One-call admit: fund the exact stake, create the beneficiary-
    /// bound ballot (self-created unless a sponsor is given), submit it as
    /// the beneficiary. Returns (reportId, proposalId).
    function submitBeneficiaryBallot(
        GaugeBounty b_,
        address core_,
        address gauge,
        address beneficiary,
        uint256 nonce,
        bytes32 eh
    ) internal returns (bytes32 reportId, uint256 proposalId) {
        return submitBeneficiaryBallotBy(b_, core_, gauge, beneficiary, beneficiary, nonce, eh);
    }

    function submitBeneficiaryBallotBy(
        GaugeBounty b_,
        address core_,
        address gauge,
        address beneficiary,
        address creator,
        uint256 nonce,
        bytes32 eh
    ) internal returns (bytes32 reportId, uint256 proposalId) {
        (reportId, proposalId) = createBeneficiaryBallot(b_, core_, gauge, beneficiary, creator, nonce, eh);
        fundStake(b_, beneficiary);
        vm.prank(beneficiary);
        bytes32 id = b_.submit(gauge, proposalId, eh, nonce);
        assertEq(id, reportId, "submitted id equals the precomputed canonical id");
    }
}
