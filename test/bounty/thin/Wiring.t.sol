// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BountyFixture} from "../BountyFixture.sol";
import {Vm} from "../../TestBase.sol";
import {GaugeBounty} from "../../../contracts/GaugeBounty.sol";
import {CurveGaugeListerV2} from "../../../contracts/CurveGaugeListerV2.sol";
import {CurveGaugeLister} from "../../../contracts/CurveGaugeLister.sol";
import {AlwaysTrueTrustedValidator} from "../../mocks/TrustedFactoryMocks.sol";
import {IGaugeBounty} from "../../../contracts/interfaces/IGaugeBounty.sol";
import {FeeDistributorAccounting} from "../../../contracts/libraries/FeeDistributorAccounting.sol";
import {ReportView, BountyConfig, StakeState} from "../../../contracts/bounty/BountyTypes.sol";
import {MockERC20} from "../../../contracts/mocks/MockERC20.sol";
import {MockPool} from "../../../contracts/mocks/MockPool.sol";
import {MockFeeDistributor} from "../../../contracts/mocks/MockFeeDistributor.sol";
import {MockListingController} from "../../../contracts/mocks/MockListingController.sol";
import {MockIncentivePlatform} from "../../../contracts/mocks/MockIncentivePlatform.sol";
import {MockOwnershipVoting} from "../mocks/MockOwnershipVoting.sol";
import {MockVotingEscrow} from "../mocks/MockVotingEscrow.sol";
import {ReentrantToken} from "../mocks/BountyFaultActors.sol";
import {
    MockWalletChecker,
    MockSupportedFactory,
    GovernanceGauge,
    MockKillProxy
} from "../mocks/MockBountyGovernance.sol";

/// @dev Non-lister contract exposing the binding getter NAMES with foreign
/// identities: isolates the individual reciprocal pins of `bindLister`
/// (real deployed code, never a cheatcode bypass).
contract ThinListerImposter {
    address public crvUSD;
    address public feeDistributor;
    address public bounty;
    address public owner;

    constructor(address t_, address f_, address b_, address o_) {
        crvUSD = t_;
        feeDistributor = f_;
        bounty = b_;
        owner = o_;
    }
}

/// @notice Thin wiring and admission-gate suite (plans/BOUNTY-THIN-PLAN.md
/// §7.2 rows W01–W07), replacing the retired BountyWiring banked identities.
/// No commit/reveal, manual gauge authorization, policy witness, retirement,
/// treasury recovery or court scaffolding survives: every assertion inspects
/// real constructor pins, the real write-once binding, real custody and the
/// real local report/queue/liability views.
contract ThinWiringTest is BountyFixture {
    /// @dev A real V2 plus the exact adapter/controller identities behind it.
    struct Kit {
        CurveGaugeListerV2 core_;
        MockListingController ctl;
        MockIncentivePlatform votium;
        MockIncentivePlatform market;
    }

    uint256 internal _seq = 1;

    function setUp() public {
        setupBountyWorld();
    }

    // ---------------------------------------------------------------- glue

    function _fundStakeTo(GaugeBounty b, address who) internal {
        crvUSD.mint(who, STAKE);
        approveCrvUsd(who, address(b), STAKE);
    }

    /// @dev Real V2 with an explicit initial config owner, fresh seated
    /// controller/platforms and a fully funded+approved payer, left PAUSED.
    /// `seatVotium`/`seatMarket` stage unseated or misbound adapters.
    function _kit(address owner_, address bounty_, bool seatVotium, bool seatMarket) internal returns (Kit memory k) {
        k.ctl = new MockListingController(controllerDao, int128(2));
        k.votium = new MockIncentivePlatform(address(crvUSD));
        k.market = new MockIncentivePlatform(address(crvUSD));
        k.core_ = new CurveGaugeListerV2(
            owner_,
            address(crvUSD),
            address(k.ctl),
            address(fd),
            CurveGaugeListerV2.AdmissionConfig(address(registry), 8),
            CurveGaugeListerV2.PlatformConfig(address(k.votium), address(k.market), 5000),
            bounty_,
            address(tfValidator)
        );
        vm.prank(controllerDao);
        k.ctl.setLister(address(k.core_));
        if (seatVotium) k.votium.setLister(address(k.core_));
        if (seatMarket) k.market.setLister(address(k.core_));
        crvUSD.mint(payer, 40 * FEE);
        approveCrvUsd(payer, address(k.core_), type(uint256).max);
        controller = k.ctl;
    }

    /// @dev Real V2 whose INITIAL config owner IS the configured Ownership
    /// Agent (§2.1 binding check), fully seated, still paused.
    function _agentKit(address bounty_) internal returns (Kit memory) {
        return _kit(address(agent), bounty_, true, true);
    }

    /// @dev Paid admission of an already registry-wired gauge: freshly
    /// funded and approved, so a refusal can never be an approval artifact.
    function _paidList(CurveGaugeListerV2 core_, address pool, address gauge) internal {
        crvUSD.mint(payer, FEE);
        approveCrvUsd(payer, address(core_), FEE);
        vm.prank(payer);
        core_.listGauge(pool, gauge, 0, lastSlot);
    }

    /// @dev Registry-wired governance gauge against a DELIBERATELY FOREIGN
    /// supported factory: its self-reported `factory()` is the spoof.
    function _deployGaugeWithFactory(address lpToken) internal returns (address pool, address gauge) {
        MockSupportedFactory alien = new MockSupportedFactory(address(killProxy));
        gauge = address(new GovernanceGauge(lpToken, address(alien)));
        uint256 slot = _nextSlot++ % 10;
        lastSlot = slot;
        pool = address(new MockPool());
        registry.setPool(pool, slot, lpToken, _coins(address(new MockERC20(18)), address(new MockERC20(18))), 2);
        registry.setGauge(pool, slot, 0, gauge, int128(0));
    }

    /// @dev Real veCRV whale tally + timely execution through the actual
    /// Voting -> CallsScript -> Agent -> proxy -> gauge route.
    function _tallyYesAndExecute(GaugeBounty b, bytes32 id, uint256 voteId) internal {
        address whale = address(uint160(0xA11CE700 + _seq++));
        giveVePower(whale, 5_000_000e18);
        vm.prank(whale);
        voting.vote(voteId, true);
        vm.warp(b.getReport(id).voteEnd);
        vm.prank(stranger);
        voting.executeVote(voteId);
    }

    function _spaceFdCursor() internal {
        if (block.timestamp <= fd.last_token_time() + 86_400) {
            fd.setLastTokenTime(block.timestamp - 86_401);
        }
    }

    function _submitOn(GaugeBounty b, CurveGaugeListerV2 core_, address who) internal returns (bytes32 id, address g) {
        (, g,) = listBountyEligible(core_);
        _seq += 1;
        bytes32 eh = keccak256(abi.encode("wiring-evidence", who, g, _seq));
        (id,) = submitBeneficiaryBallot(b, address(core_), g, who, _seq, eh);
    }

    // ------------------------------------------------------------------ W01

    function test_Thin_ConstructorAndConfigPins() public {
        // ---- (a) Chain pin: only mainnet chain id 1 constructs.
        vm.chainId(5);
        vm.expectRevert(IGaugeBounty.WrongChain.selector);
        new GaugeBounty(defaultBountyConfig());
        vm.chainId(1);
        new GaugeBounty(defaultBountyConfig()); // positive control, same frame

        // ---- (b) Every code-bearing dependency pin.
        address eoa = actor("eoaDependency");
        for (uint256 field = 0; field < 9; ++field) {
            BountyConfig memory fieldCfg = defaultBountyConfig();
            if (field == 0) fieldCfg.crvUSD = eoa;
            if (field == 1) fieldCfg.feeDistributor = eoa;
            if (field == 2) fieldCfg.ownershipVoting = eoa;
            if (field == 3) fieldCfg.ownershipAgent = eoa;
            if (field == 4) fieldCfg.killProxy = eoa;
            if (field == 5) fieldCfg.supportedFactory = eoa;
            if (field == 6) fieldCfg.votingImplementation = eoa;
            if (field == 7) fieldCfg.agentImplementation = eoa;
            if (field == 8) fieldCfg.callsScriptExecutor = eoa;
            vm.expectRevert(IGaugeBounty.BadConfiguration.selector);
            new GaugeBounty(fieldCfg);
        }

        // ---- (c) Token decimals pin (crvUSD only; the CRV alias/checker/
        // escrow pins retired with the standing lock and checker §2).
        BountyConfig memory c = defaultBountyConfig();
        c.crvUSD = address(new MockERC20(17));
        vm.expectRevert(IGaugeBounty.BadConfiguration.selector);
        new GaugeBounty(c);

        // ---- (f) Implementation, executor and route-role pins.
        MockERC20 otherCrv = new MockERC20(18);
        MockOwnershipVoting votingImplDrift =
            new MockOwnershipVoting(address(escrow), votingDao, address(new MockWalletChecker()));
        vm.prank(votingDao);
        votingImplDrift.setEVMScriptExecutor(0x00000001, address(callsScript));
        c = defaultBountyConfig();
        c.ownershipVoting = address(votingImplDrift);
        vm.expectRevert(IGaugeBounty.BadConfiguration.selector); // voting.implementation() drift
        new GaugeBounty(c);

        c = defaultBountyConfig();
        c.agentImplementation = address(new MockWalletChecker());
        vm.expectRevert(IGaugeBounty.BadConfiguration.selector); // agent.implementation() drift
        new GaugeBounty(c);

        c = defaultBountyConfig();
        c.callsScriptExecutor = address(new MockWalletChecker());
        vm.expectRevert(IGaugeBounty.BadConfiguration.selector); // type-0x01 executor drift
        new GaugeBounty(c);

        MockKillProxy proxyAlienDao = new MockKillProxy(actor("otherAgent"), emergencySafe);
        c = defaultBountyConfig();
        c.killProxy = address(proxyAlienDao);
        vm.expectRevert(IGaugeBounty.BadConfiguration.selector); // killProxy.dao() != agent
        new GaugeBounty(c);

        MockKillProxy proxyEoaEmergency = new MockKillProxy(address(agent), actor("eoaEmergency"));
        c = defaultBountyConfig();
        c.killProxy = address(proxyEoaEmergency);
        vm.expectRevert(IGaugeBounty.BadConfiguration.selector); // emergency role has no code
        new GaugeBounty(c);

        MockSupportedFactory factoryAlienAdmin = new MockSupportedFactory(actor("otherAdmin"));
        c = defaultBountyConfig();
        c.supportedFactory = address(factoryAlienAdmin);
        vm.expectRevert(IGaugeBounty.BadConfiguration.selector); // factory.admin() != proxy
        new GaugeBounty(c);

        // ---- (g) FD pins use the accepted shared-library selectors.
        MockFeeDistributor fdWrongToken = new MockFeeDistributor(address(otherCrv), fdAdmin, T0);
        c = defaultBountyConfig();
        c.feeDistributor = address(fdWrongToken);
        vm.expectRevert(FeeDistributorAccounting.DistributorUnusable.selector);
        new GaugeBounty(c);
        MockFeeDistributor fdKilled = new MockFeeDistributor(address(crvUSD), fdAdmin, T0);
        fdKilled.setKilled(true);
        c = defaultBountyConfig();
        c.feeDistributor = address(fdKilled);
        vm.expectRevert(FeeDistributorAccounting.DistributorUnusable.selector);
        new GaugeBounty(c);

        // ---- (h) Pinned Voting duration/ratio drift. The retired
        // minBalance/minTime floors are NOT constructor pins anymore: they
        // gate the actual creator's upstream proposal rights, and no
        // creator/attestation mechanism is admitted (§3.2).
        for (uint256 drift = 1; drift <= 3; ++drift) {
            MockOwnershipVoting v = new MockOwnershipVoting(address(escrow), votingDao, votingImplementation);
            vm.prank(votingDao);
            v.setEVMScriptExecutor(0x00000001, address(callsScript));
            vm.prank(votingDao);
            if (drift == 1) v.setVoteTime(VOTE_TIME + 1);
            if (drift == 2) v.setSupportRequired(SUPPORT_REQUIRED + 1);
            if (drift == 3) v.setMinAcceptQuorum(MIN_ACCEPT_QUORUM - 1);
            c = defaultBountyConfig();
            c.ownershipVoting = address(v);
            vm.expectRevert(IGaugeBounty.BadConfiguration.selector);
            new GaugeBounty(c);
        }

        // ---- (i) All 9 config fields round-trip exactly through config().
        BountyConfig memory want = defaultBountyConfig();
        GaugeBounty good = new GaugeBounty(want);
        BountyConfig memory got = good.config();
        assertEq(got.crvUSD, want.crvUSD, "pin 1 crvUSD");
        assertEq(got.feeDistributor, want.feeDistributor, "pin 2 feeDistributor");
        assertEq(got.ownershipVoting, want.ownershipVoting, "pin 3 ownershipVoting");
        assertEq(got.ownershipAgent, want.ownershipAgent, "pin 4 ownershipAgent");
        assertEq(got.killProxy, want.killProxy, "pin 5 killProxy");
        assertEq(got.supportedFactory, want.supportedFactory, "pin 6 supportedFactory");
        assertEq(got.votingImplementation, want.votingImplementation, "pin 7 votingImplementation");
        assertEq(got.agentImplementation, want.agentImplementation, "pin 8 agentImplementation");
        assertEq(got.callsScriptExecutor, want.callsScriptExecutor, "pin 9 callsScriptExecutor");
        assertEq(keccak256(abi.encode(got)), keccak256(abi.encode(want)), "exact 9-field tuple order");

        // ---- (j) Config is constructor-only: real mutations cannot move it.
        (CurveGaugeListerV2 core_, GaugeBounty b) = deployBoundPair();
        bytes32 cfgBefore = keccak256(abi.encode(b.config()));
        (, address gauge,) = listBountyEligible(core_);
        (bytes32 id,) = submitBeneficiaryBallot(b, address(core_), gauge, reporter, 601, keccak256("w01-mutation"));
        require(b.getReport(id).reporter == reporter, "case accepted");
        vm.prank(daoOwner);
        assertTrue(b.markFrivolous(id), "stake forfeited");
        (uint256 heldNow,, uint256 daoNow) = b.accounting();
        assertEq(heldNow, 0, "bond moved to the FD liability");
        assertEq(daoNow, STAKE, "queue mutated");
        assertEq(keccak256(abi.encode(b.config())), cfgBefore, "config immutable across mutations");

        // ---- (k) No mutable duplicate authority: no setter, initializer,
        // owner, gauge-authorization surface, sweep or generic executor, and
        // neither fallback nor receive. Probed from every privileged role.
        bytes[] memory forbidden = new bytes[](16);
        forbidden[0] = abi.encodeWithSignature("setConfig(address)", address(1));
        forbidden[1] = abi.encodeWithSignature("updateConfig(address)", address(1));
        forbidden[2] = abi.encodeWithSignature("authorizeGauge(address,bytes32)", address(1), bytes32(uint256(1)));
        forbidden[3] = abi.encodeWithSignature("setOwner(address)", stranger);
        forbidden[4] = abi.encodeWithSignature("setOwner(address,address)", stranger, stranger);
        forbidden[5] = abi.encodeWithSignature("transferOwnership(address)", stranger);
        forbidden[6] = abi.encodeWithSignature("sweep(address)", stranger);
        forbidden[7] = abi.encodeWithSignature("sweepToken(address,uint256)", address(crvUSD), uint256(1));
        forbidden[8] = abi.encodeWithSignature("withdraw()");
        forbidden[9] = abi.encodeWithSignature("withdrawAll()");
        forbidden[10] = abi.encodeWithSignature("execute(address,uint256,bytes)", address(crvUSD), uint256(0), hex"");
        forbidden[11] = abi.encodeWithSignature("setDao(address)", stranger);
        forbidden[12] = abi.encodeWithSignature("setTreasury(address)", stranger);
        forbidden[13] = abi.encodeWithSignature("initialize(address)", stranger);
        forbidden[14] = abi.encodeWithSignature("upgrade(address)", stranger);
        forbidden[15] = abi.encodeWithSignature("setLister(address)", stranger);
        address[4] memory authorities = [address(agent), treasury, daoOwner, stranger];
        uint256 crvUsdBefore = crvUSD.balanceOf(address(b));
        uint256 crvBefore = crv.balanceOf(address(b));
        for (uint256 a = 0; a < authorities.length; ++a) {
            for (uint256 p = 0; p < forbidden.length; ++p) {
                _expectAbsentSelector(forbidden[p]);
                vm.prank(authorities[a]);
                (bool ok,) = address(b).call(forbidden[p]);
                assertFalse(ok, "no mutable duplicate authority");
            }
        }
        (bool fbOk,) = address(b).call(hex"deadbeef01");
        assertFalse(fbOk, "no fallback");
        vmx.deal(address(this), 1 ether);
        (bool ethOk,) = address(b).call{value: 1 wei}("");
        assertFalse(ethOk, "no receive");
        assertEq(crvUSD.balanceOf(address(b)), crvUsdBefore, "custody unmoved by probes");
        assertEq(crv.balanceOf(address(b)), crvBefore, "CRV unmoved by probes");
    }

    // ------------------------------------------------------------------ W02

    function test_Thin_ReciprocalBinding() public {
        GaugeBounty b = deployBounty();
        Kit memory honest = _agentKit(address(b));

        // ---- (a) Only the configured Ownership Agent may bind at all.
        address[5] memory outsiders = [stranger, treasury, daoOwner, reporter, address(callsScript)];
        for (uint256 i = 0; i < outsiders.length; ++i) {
            vm.prank(outsiders[i]);
            vm.expectRevert(IGaugeBounty.NotAgent.selector);
            b.bindLister(address(honest.core_));
            assertEq(b.lister(), address(0), "no write before authentication");
        }

        // ---- (b) Every wrong target is rejected BEFORE any state is written.
        vm.prank(address(agent));
        vm.expectRevert(IGaugeBounty.BadConfiguration.selector);
        b.bindLister(address(0));
        assertEq(b.lister(), address(0), "zero target wrote nothing");

        vm.prank(address(agent));
        vm.expectRevert(IGaugeBounty.BadConfiguration.selector);
        b.bindLister(actor("eoaLister"));
        assertEq(b.lister(), address(0), "no-code target wrote nothing");

        ThinListerImposter wrongToken =
            new ThinListerImposter(actor("foreignCrvUsd"), address(fd), address(b), address(agent));
        vm.prank(address(agent));
        vm.expectRevert(IGaugeBounty.BadConfiguration.selector);
        b.bindLister(address(wrongToken));
        assertEq(b.lister(), address(0), "foreign token wrote nothing");

        MockFeeDistributor foreignFd = new MockFeeDistributor(address(crv), fdAdmin, T0);
        ThinListerImposter wrongFd =
            new ThinListerImposter(address(crvUSD), address(foreignFd), address(b), address(agent));
        vm.prank(address(agent));
        vm.expectRevert(IGaugeBounty.BadConfiguration.selector);
        b.bindLister(address(wrongFd));
        assertEq(b.lister(), address(0), "foreign FD wrote nothing");

        GaugeBounty other = new GaugeBounty(defaultBountyConfig());
        ThinListerImposter notReciprocal =
            new ThinListerImposter(address(crvUSD), address(fd), address(other), address(agent));
        vm.prank(address(agent));
        vm.expectRevert(IGaugeBounty.BadConfiguration.selector);
        b.bindLister(address(notReciprocal));
        assertEq(b.lister(), address(0), "non-reciprocal target wrote nothing");

        // A REAL V2 whose owner is not the configured Agent: its own owner
        // cannot win the first-caller binding race either.
        Kit memory daoOwned = _kit(daoOwner, address(b), true, true);
        assertEq(daoOwned.core_.owner(), daoOwner, "dao-owned control");
        vm.prank(address(agent));
        vm.expectRevert(IGaugeBounty.BadConfiguration.selector);
        b.bindLister(address(daoOwned.core_));
        assertEq(b.lister(), address(0), "non-agent-owned V2 wrote nothing");
        vm.prank(daoOwner);
        vm.expectRevert(IGaugeBounty.NotAgent.selector);
        b.bindLister(address(daoOwned.core_));
        assertEq(b.lister(), address(0), "and still not bindable by that V2's owner");

        // ---- (c) The correct bind happens exactly once, through the Agent.
        vm.recordLogs();
        vm.prank(address(agent));
        b.bindLister(address(honest.core_));
        Vm.Log[] memory bindLogs = vm.getRecordedLogs();
        assertEq(countEvents(bindLogs, address(b), sig("ListerBound(address)")), 1, "ListerBound emitted once");
        assertEq(b.lister(), address(honest.core_), "lister() readback exact");
        assertEq(honest.core_.bounty(), address(b), "reciprocal pointer exact");

        // ---- (d) Write-once forever, even for the Agent and even replaying
        // the same address. No second ListerBound is possible.
        vm.recordLogs();
        vm.prank(address(agent));
        vm.expectRevert(IGaugeBounty.AlreadyBound.selector);
        b.bindLister(address(honest.core_));
        vm.prank(address(agent));
        vm.expectRevert(IGaugeBounty.AlreadyBound.selector);
        b.bindLister(address(other));
        vm.prank(address(agent));
        vm.expectRevert(IGaugeBounty.AlreadyBound.selector);
        b.bindLister(address(0));
        Vm.Log[] memory rebindingLogs = vm.getRecordedLogs();
        assertEq(countEvents(rebindingLogs, address(b), sig("ListerBound(address)")), 0, "no second ListerBound");
        assertEq(b.lister(), address(honest.core_), "binding immutable after the first write");
    }

    // ------------------------------------------------------------------ W03

    function test_Thin_PaidReadinessBeforeEffects() public {
        // ---- Cell 1: honest core whose bounty is UNBOUND.
        GaugeBounty bA = deployBounty(); // stays unbound forever
        Kit memory a = _kit(daoOwner, address(bA), true, true);
        vm.prank(daoOwner);
        a.core_.setPaused(false);
        (address poolA, address gaugeA,) = deployGovernanceGauge();
        _expectPaidRefused(a, poolA, gaugeA, abi.encodeWithSelector(CurveGaugeListerV2.BountyNotReady.selector));

        // ---- Cell 2: WRONG-BOUND bounty (its lister() names another core).
        // Both cores must be constructed while the bounty is still unbound.
        GaugeBounty bB = deployBounty();
        Kit memory misbound = _kit(daoOwner, address(bB), true, true);
        Kit memory holder = _agentKit(address(bB));
        vm.prank(address(agent));
        bB.bindLister(address(holder.core_));
        require(bB.lister() == address(holder.core_), "cell-2 bounty bound elsewhere");
        vm.prank(daoOwner);
        misbound.core_.setPaused(false);
        (address poolB, address gaugeB,) = deployGovernanceGauge();
        _expectPaidRefused(misbound, poolB, gaugeB, abi.encodeWithSelector(CurveGaugeListerV2.BountyNotReady.selector));
        // Positive control: the reciprocally bound core admits the same shape.
        vm.prank(address(agent));
        holder.core_.setPaused(false);
        (address poolOK, address gaugeOK,) = deployGovernanceGauge();
        _paidList(holder.core_, poolOK, gaugeOK);
        assertEq(uint256(holder.core_.getListing(gaugeOK).status), 1, "bound core admits");
        assertEq(holder.core_.totalEscrow(), FEE, "bound core takes the fee once");

        // ---- Cell 3: UNSEATED adapter -> PlatformNotReady strictly before fee.
        GaugeBounty bC = deployBounty();
        Kit memory c = _kit(address(agent), address(bC), false, true); // votium never seated
        vm.prank(address(agent));
        bC.bindLister(address(c.core_)); // bounty readiness IS satisfied
        require(bC.lister() == address(c.core_) && c.votium.lister() == address(0), "cell-3 unseated votium");
        vm.prank(address(agent));
        c.core_.setPaused(false);
        (address poolC, address gaugeC,) = deployGovernanceGauge();
        _expectPaidRefused(
            c, poolC, gaugeC, abi.encodeWithSelector(CurveGaugeListerV2.PlatformNotReady.selector, address(c.votium))
        );

        // ---- Cell 4: MISBOUND adapters (platforms seated for a different core).
        Kit memory otherCore = _kit(daoOwner, address(deployBounty()), true, true);
        GaugeBounty bD = deployBounty();
        MockListingController ctlD = new MockListingController(controllerDao, int128(2));
        MockIncentivePlatform misVotium = new MockIncentivePlatform(address(crvUSD));
        MockIncentivePlatform misMarket = new MockIncentivePlatform(address(crvUSD));
        misVotium.setLister(address(otherCore.core_)); // wrong seating on purpose
        misMarket.setLister(address(otherCore.core_));
        CurveGaugeListerV2 coreD = new CurveGaugeListerV2(
            address(agent),
            address(crvUSD),
            address(ctlD),
            address(fd),
            CurveGaugeListerV2.AdmissionConfig(address(registry), 8),
            CurveGaugeListerV2.PlatformConfig(address(misVotium), address(misMarket), 5000),
            address(bD),
            address(tfValidator)
        );
        Kit memory d = Kit({core_: coreD, ctl: ctlD, votium: misVotium, market: misMarket});
        vm.prank(controllerDao);
        ctlD.setLister(address(coreD));
        vm.prank(address(agent));
        bD.bindLister(address(coreD)); // bounty side is correct
        require(bD.lister() == address(coreD), "cell-4 bounty reciprocally bound");
        vm.prank(address(agent));
        coreD.setPaused(false);
        (address poolD, address gaugeD,) = deployGovernanceGauge();
        _expectPaidRefused(
            d, poolD, gaugeD, abi.encodeWithSelector(CurveGaugeListerV2.PlatformNotReady.selector, address(misVotium))
        );

        // ---- Cell 5: the DAO-free path is bounty-readiness independent and
        // keeps working while PAUSED with unseated platforms irrelevant.
        GaugeBounty bE = deployBounty(); // never bound
        Kit memory e = _kit(daoOwner, address(bE), true, true);
        assertTrue(e.core_.paused(), "fresh V2 starts paused");
        assertEq(bE.lister(), address(0), "cell-5 bounty unbound");
        (address poolE, address gaugeE,) = deployPlainGauge();
        uint256 slotE = lastSlot;
        uint256 payerBefore = crvUSD.balanceOf(payer);
        uint256 coreBefore = crvUSD.balanceOf(address(e.core_));
        vm.prank(daoOwner);
        e.core_.listGaugeNoEscrow(poolE, gaugeE, 0, slotE, 0);
        assertEq(uint256(e.core_.getListing(gaugeE).status), 4, "free path while paused+unbound");
        assertEq(e.core_.getListing(gaugeE).payer, address(0), "free path stores no payer");
        assertEq(crvUSD.balanceOf(address(e.core_)), coreBefore, "free path never touches escrow");
        assertEq(crvUSD.balanceOf(payer), payerBefore, "free path pulls no fee");
        assertEq(e.core_.totalEscrow(), 0, "free path creates no liability");
        assertEq(e.ctl.gauge_types(gaugeE), int128(0), "free path still registers membership");
        vm.prank(stranger);
        vm.expectRevert(CurveGaugeListerV2.NotOwner.selector);
        e.core_.listGaugeNoEscrow(poolE, address(0x9999), 0, slotE, 0);

        // Paid admission on the SAME core stays gated by bounty readiness
        // even once unpaused.
        vm.prank(daoOwner);
        e.core_.setPaused(false);
        (address poolF, address gaugeF,) = deployGovernanceGauge();
        _expectPaidRefused(e, poolF, gaugeF, abi.encodeWithSelector(CurveGaugeListerV2.BountyNotReady.selector));
    }

    /// @dev Trace-before-effects oracle: the refusal must land at the gate,
    /// with zero fee, custody, liability, controller or event side effects.
    function _expectPaidRefused(Kit memory k, address pool, address gauge, bytes memory expected) internal {
        uint256 payerBefore = crvUSD.balanceOf(payer);
        uint256 addsBefore = k.ctl.addCalls();
        uint256 escrowBefore = k.core_.totalEscrow();
        vm.recordLogs();
        vm.prank(payer);
        vm.expectRevert(expected);
        k.core_.listGauge(pool, gauge, 0, lastSlot);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(crvUSD.balanceOf(payer), payerBefore, "fee not attempted");
        assertEq(crvUSD.balanceOf(address(k.core_)), 0, "no custody");
        assertEq(k.core_.totalEscrow(), escrowBefore, "no escrow liability");
        assertEq(k.ctl.addCalls(), addsBefore, "no controller.add_gauge");
        assertEq(uint256(k.core_.getListing(gauge).status), 0, "no listing record");
        assertEq(
            countEvents(
                logs, address(k.core_), sig("GaugeListed(address,address,address,int128,uint256,uint256,bool)")
            ),
            0,
            "no admission event"
        );
    }

    // ------------------------------------------------------------------ W04

    function test_Thin_EligibleAuthenticatedRoute() public {
        (CurveGaugeListerV2 core_, GaugeBounty b) = deployBoundPair();

        // Every rejection lands at the eligibility gate itself: each cell
        // funds and approves the reporter immediately before attempting, so
        // a failure can never be a missing-funding artifact.

        // ---- Rejection: never listed on the bound V2 at all.
        _rejectIneligible(b, actor("neverListedGauge"), "w04-unknown", "unknown gauge");

        // ---- Rejection: V1-style gauge listed only on the OLD lister.
        _rejectV1OnlyListing(b, core_);

        // ---- Rejection: DAO-free listing (DaoExempt => payer == 0).
        _rejectFreeListing(b, core_);

        // ---- Rejection: remote/unverified route (no factory() at all).
        _rejectUnverifiedRoute(b, core_);

        // ---- Rejection: spoofed route (factory() names a FOREIGN factory).
        _rejectSpoofedRoute(b, core_);

        // ---- Rejection: terminal listing (four funded quarters, exhausted).
        _rejectTerminalListing(b, core_);

        // ---- Rejection: pre-killed gauge (route honest, flag already true).
        _rejectPreKilled(b, core_);

        // ---- Acceptance: the paid, authenticated supported
        // factory -> proxy -> Agent route qualifies.
        _acceptAuthenticatedRoute(b, core_);
    }

    /// @dev Positive route cell: real registry-authenticated paid listing on
    /// the honest factory -> proxy -> Agent route, and a successful bond.
    function _acceptAuthenticatedRoute(GaugeBounty b, CurveGaugeListerV2 core_) private {
        (, address good,) = listBountyEligible(core_);
        assertEq(core_.getListing(good).payer, payer, "paid listing has a payer");
        assertEq(GovernanceGauge(good).factory(), address(factory), "supported factory");
        assertEq(MockSupportedFactory(address(factory)).admin(), address(killProxy), "proxy admin");
        assertEq(MockKillProxy(address(killProxy)).dao(), address(agent), "agent dao route");
        assertFalse(GovernanceGauge(good).is_killed(), "live gauge");
        assertTrue(core_.getListing(good).remaining > 0, "positive remainder");
        (bytes32 slotBefore,,) = b.rewardTerms(good);
        assertEq(slotBefore, bytes32(0), "no latch pre-submit");
        uint256 bal0 = crvUSD.balanceOf(address(b));
        uint256 rep0 = crvUSD.balanceOf(reporter);
        bytes32 eh = keccak256("w04-accepted");
        (bytes32 id,) = submitBeneficiaryBallot(b, address(core_), good, reporter, 604, eh);
        assertEq(crvUSD.balanceOf(address(b)) - bal0, STAKE, "exact bond pulled once");
        assertEq(crvUSD.balanceOf(reporter), rep0, "reporter funded exactly for one bond");
        ReportView memory rv = b.getReport(id);
        assertEq(rv.reporter, reporter, "stored reporter");
        assertEq(rv.gauge, good, "stored gauge");
        assertEq(rv.evidenceHash, eh, "stored evidence");
        assertEq(rv.listingId, core_.listingId(good), "stored permanent listing id");
        assertEq(uint256(rv.phase), 1, "admitted immediately: no queue state exists");
        // Unlike the retired active-slot view, a PENDING submission never
        // appears as an entitlement candidate (§4): no latch, all-zero read.
        (bytes32 slotId, address slotRep, bool slotEligible) = b.rewardTerms(good);
        assertEq(slotId, bytes32(0), "pending report is not a winner candidate");
        assertEq(slotRep, address(0), "no phantom slot reporter");
        assertFalse(slotEligible, "not eligible before recognition");
        (uint256 heldL,,) = b.accounting();
        assertEq(heldL, STAKE, "liability is the real bond");
    }

    /// @dev Cell: gauge listed only on the frozen V1 core is unknown to V2.
    function _rejectV1OnlyListing(GaugeBounty b, CurveGaugeListerV2 core_) private {
        (address v1Pool, address v1Gauge,) = deployGovernanceGauge();
        uint256 v1Slot = lastSlot;
        MockListingController v1Ctl = new MockListingController(controllerDao, int128(2));
        MockIncentivePlatform v1Votium = new MockIncentivePlatform(address(crvUSD));
        MockIncentivePlatform v1Market = new MockIncentivePlatform(address(crvUSD));
        CurveGaugeLister v1 = new CurveGaugeLister(
            daoOwner,
            address(crvUSD),
            address(v1Ctl),
            address(fd),
            CurveGaugeLister.AdmissionConfig(address(registry), 8),
            CurveGaugeLister.PlatformConfig(address(v1Votium), address(v1Market), 5000),
            address(new AlwaysTrueTrustedValidator())
        );
        vm.prank(controllerDao);
        v1Ctl.setLister(address(v1));
        v1Votium.setLister(address(v1));
        v1Market.setLister(address(v1));
        // Owner unpause after binding (V1ALIGN §1.3) so the retained
        // V1-only-listing cell keeps exercising the paid path.
        vm.prank(daoOwner);
        v1.setPaused(false);
        crvUSD.mint(payer, FEE);
        approveCrvUsd(payer, address(v1), FEE);
        vm.prank(payer);
        v1.listGauge(v1Pool, v1Gauge, 0, v1Slot);
        assertEq(uint256(v1.getListing(v1Gauge).status), 1, "V1-listed Active");
        assertEq(uint256(core_.getListing(v1Gauge).status), 0, "unknown to the bound V2");
        _rejectIneligible(b, v1Gauge, "w04-v1", "V1-only listing");
    }

    /// @dev Cell: a DAO-free (DaoExempt) listing has no payer and cannot pay
    /// a bounty reporter.
    function _rejectFreeListing(GaugeBounty b, CurveGaugeListerV2 core_) private {
        (address freePool, address freeGauge,) = deployPlainGauge();
        vm.prank(daoOwner);
        core_.listGaugeNoEscrow(freePool, freeGauge, 0, lastSlot, 0);
        require(core_.getListing(freeGauge).payer == address(0), "free listing has no payer");
        _rejectIneligible(b, freeGauge, "w04-free", "free listing");
    }

    /// @dev Cell: a paid Active listing of a gauge that cannot evidence the
    /// supported factory at all (MockGauge has no factory()).
    function _rejectUnverifiedRoute(GaugeBounty b, CurveGaugeListerV2 core_) private {
        (address plainPool, address plainGauge,) = deployPlainGauge();
        _paidList(core_, plainPool, plainGauge);
        require(core_.getListing(plainGauge).status == 1, "plain gauge is paid-Active");
        _rejectIneligible(b, plainGauge, "w04-nofactory", "unverified route");
    }

    /// @dev Cell: a well-formed governance gauge whose factory() names a
    /// FOREIGN factory is still rejected: a self-report is never authority.
    function _rejectSpoofedRoute(GaugeBounty b, CurveGaugeListerV2 core_) private {
        (address spoofPool, address spoofGauge) = _deployGaugeWithFactory(address(new MockERC20(18)));
        _paidList(core_, spoofPool, spoofGauge);
        require(core_.getListing(spoofGauge).status == 1, "spoof listing is paid-Active");
        assertTrue(GovernanceGauge(spoofGauge).factory() != address(factory), "route is foreign");
        _rejectIneligible(b, spoofGauge, "w04-spoof", "spoofed route");
    }

    /// @dev Cell: four funded quarters later the listing is terminal.
    function _rejectTerminalListing(GaugeBounty b, CurveGaugeListerV2 core_) private {
        (, address exhausted,) = listBountyEligible(core_);
        uint256 exStart = core_.getListing(exhausted).listingEpoch;
        for (uint256 q = 1; q <= 4; ++q) {
            vm.warp(exStart + q * WEEK);
            core_.checkpoint(exhausted);
        }
        require(core_.getListing(exhausted).status == 2, "Exhausted");
        require(core_.getListing(exhausted).remaining == 0, "zero remainder");
        _rejectIneligible(b, exhausted, "w04-terminal", "terminal listing");
    }

    /// @dev Cell: an independently killed gauge never earns a bounty case.
    function _rejectPreKilled(GaugeBounty b, CurveGaugeListerV2 core_) private {
        (address kPool, address kGauge,) = deployGovernanceGauge();
        _paidList(core_, kPool, kGauge);
        killGaugeViaRoute(kGauge);
        require(GovernanceGauge(kGauge).is_killed(), "pre-killed");
        require(core_.getListing(kGauge).status == 1, "still Active before seizure");
        _rejectIneligible(b, kGauge, "w04-prekill", "pre-killed gauge");
    }

    /// @dev Common rejection oracle: the reporter is funded and approved at
    /// the moment of the attempt, so the ONLY possible failure is the gate.
    function _rejectIneligible(GaugeBounty b, address gauge, string memory evidence, string memory label) private {
        _fundStakeTo(b, reporter); // funding/approval is never the blocker
        uint256 bal0 = crvUSD.balanceOf(address(b));
        uint256 rep0 = crvUSD.balanceOf(reporter);
        vm.prank(reporter);
        vm.expectRevert(IGaugeBounty.IneligibleGauge.selector);
        b.submit(gauge, 1, keccak256(bytes(evidence)), 699);
        _expectNoPull(b, bal0, rep0, label);
    }

    function _expectNoPull(GaugeBounty b, uint256 bal0, uint256 rep0, string memory label) internal view {
        assertEq(crvUSD.balanceOf(address(b)), bal0, label);
        assertEq(crvUSD.balanceOf(reporter), rep0, "no pull on rejection");
        (uint256 heldR, uint256 crR, uint256 daoR) = b.accounting();
        assertEq(heldR, 0, "no liability on rejection");
        assertEq(crR, 0, "no credits on rejection");
        assertEq(daoR, 0, "no FD liability on rejection");
    }

    /// @dev Pre-create the w04 acceptance ballot; the submit site stays a
    /// plain reporter prank.
    function _w04Pid(GaugeBounty b, address good, address who, bytes32 eh) private returns (uint256 pid) {
        bytes32 rid;
        (rid, pid) = createBeneficiaryBallot(b, address(b.lister()), good, who, who, 604, eh);
        require(rid != bytes32(0), "w04 ballot built");
    }

    // ------------------------------------------------------------------ W05

    function test_Thin_AllowedAndRemovedEntrypoints() public {
        (CurveGaugeListerV2 core_, GaugeBounty b) = deployBoundPair();
        (, address gauge,) = listBountyEligible(core_);
        (bytes32 id,) = submitBeneficiaryBallot(b, address(core_), gauge, reporter, 605, keccak256("w05-case"));
        require(b.getReport(id).reporter == reporter, "case exists");
        address storedReporter = b.getReport(id).reporter;

        // ---- Surviving mutators reject the wrong authority exactly.
        address[4] memory notAgent = [stranger, treasury, daoOwner, reporter];
        for (uint256 i = 0; i < notAgent.length; ++i) {
            vm.prank(notAgent[i]);
            vm.expectRevert(IGaugeBounty.NotAgent.selector);
            b.bindLister(address(0));
            vm.prank(notAgent[i]);
            vm.expectRevert(IGaugeBounty.NotAgent.selector);
            b.creditBallot(id, storedReporter);
            vm.prank(notAgent[i]);
            vm.expectRevert(IGaugeBounty.NotAgent.selector);
            b.recognizeKill(id);
        }
        // The standing-lock treasury authority is GONE entirely: there is no
        // NotTreasury gate to hit because no callable funding endpoint
        // exists — probed below via the removed surface.
        address[4] memory notDao = [stranger, treasury, reporter, address(agent)];
        for (uint256 i = 0; i < notDao.length; ++i) {
            vm.prank(notDao[i]);
            vm.expectRevert(IGaugeBounty.NotDao.selector);
            b.markFrivolous(id);
        }
        address[5] memory notLister = [stranger, treasury, daoOwner, reporter, address(agent)];
        for (uint256 i = 0; i < notLister.length; ++i) {
            vm.prank(notLister[i]);
            vm.expectRevert(IGaugeBounty.NotLister.selector);
            b.creditReward(id, 1e18);
        }
        // Positive authority controls: the pinned roles really do pass their
        // own authentication gates (the guard checks are LATER).
        vm.prank(address(agent));
        b.creditBallot(id, storedReporter); // pre-window arm attempt is allowed in
        vm.prank(daoOwner);
        assertTrue(b.markFrivolous(id), "current V2 config owner is the DAO authority");

        // ---- The fenced self-calls are removed: they reject EVERYBODY as
        // unknown selectors (low-level probes, never a fallback).
        address[6] memory everyone = [address(agent), treasury, daoOwner, stranger, actor("eoaCaller"), address(core_)];
        for (uint256 i = 0; i < everyone.length; ++i) {
            vm.prank(everyone[i]);
            (bool msOk,) = address(b).call(abi.encodeWithSignature("maintainStandingLock()"));
            assertFalse(msOk, "maintainStandingLock no longer callable");
            vm.prank(everyone[i]);
            (bool cpOk,) = address(b).call(abi.encodeWithSignature("createPendingVote(bytes32)", id));
            assertFalse(cpOk, "createPendingVote no longer callable");
        }

        // ---- Complete §2.1 manifest: 19 distinct selectors, exact order.
        _expectExactCallableSurface();

        // ---- Removed payloads: no generated getter, no court, no commit or
        // reveal, no retirement/recovery, no sweep or generic executor. Every
        // probe is a LOW-LEVEL call, so a fallback could not hide behind a
        // missing selector, and it is probed from every privileged role.
        _expectRemovedSurface(b, address(core_), gauge, id);

        // Positive control: the surviving permissionless entrypoints still
        // work in the same frame, so the rejections above are the ABI surface
        // and not a broken fixture. The retired queue/service endpoints are
        // probed as ABSENT (the removed matrix below), not called.
        (bool resOk,) = address(b).call(abi.encodeCall(GaugeBounty.resolve, (id)));
        assertTrue(resOk, "resolve survives");
        (bool stakeOk,) = address(b).call(abi.encodeCall(GaugeBounty.claim, (id)));
        assertTrue(stakeOk, "claim survives");

        // ---- Correct-authority reentrancy witnesses (finding 4; §2.1:75
        // reworked): every surviving mutator is attacked RE-ENTRANTLY
        // through a real token callback of the bounty's own stake asset,
        // from its CORRECT authority and with satisfied preconditions, so
        // each refusal is attributable to the shared mutex (Reentrancy).
        // The two fenced self-calls left with the queue machinery.
        _w05ReentryControls();
    }

    /// @dev §2.1:75 (reworked): every surviving mutator carries the shared
    /// reentrancy guard; the two self-call helpers left with the queue.
    /// W05 WITNESSES every row with a valid caller, never an outsider-auth
    /// artifact.
    function _w05ReentryControls() private {
        W05World memory w = _w05BuildWorld();
        w.id1 = _w05WindowSubmit(w);
        _w05WindowClaim(w);
    }

    struct W05World {
        ReentrantToken tk;
        GaugeBounty bF;
        CurveGaugeListerV2 coreF;
        ThinReentryAttacker atk;
        bytes32 id0;
        bytes32 id1;
        address gauge0;
        address gauge1;
    }

    function _w05BuildWorld() private returns (W05World memory w) {
        w.tk = new ReentrantToken(18);
        MockFeeDistributor fdF = new MockFeeDistributor(address(w.tk), fdAdmin, block.timestamp);
        MockIncentivePlatform platV = new MockIncentivePlatform(address(w.tk));
        MockIncentivePlatform platM = new MockIncentivePlatform(address(w.tk));
        MockListingController ctlF = new MockListingController(controllerDao, int128(2));
        BountyConfig memory cfg = defaultBountyConfig();
        cfg.crvUSD = address(w.tk);
        cfg.feeDistributor = address(fdF);
        w.bF = new GaugeBounty(cfg);
        w.coreF = new CurveGaugeListerV2(
            address(agent), // bind-time config owner IS the Agent (§2.1)
            address(w.tk),
            address(ctlF),
            address(fdF),
            CurveGaugeListerV2.AdmissionConfig(address(registry), 8),
            CurveGaugeListerV2.PlatformConfig(address(platV), address(platM), 5000),
            address(w.bF),
            address(tfValidator)
        );
        vm.prank(controllerDao);
        ctlF.setLister(address(w.coreF));
        platV.setLister(address(w.coreF));
        platM.setLister(address(w.coreF));
        vm.prank(address(agent));
        w.bF.bindLister(address(w.coreF));
        vm.prank(address(agent));
        w.coreF.transferOwnership(daoOwner);
        vm.prank(daoOwner);
        w.coreF.acceptOwnership();
        vm.prank(daoOwner);
        w.coreF.setPaused(false);

        // Funded preconditions: reporter stake, payer fee. There is no
        // project capital path anymore (§2): nothing funds a lock.
        (address pool0, address g0,) = deployGovernanceGauge();
        uint256 slot0 = lastSlot;
        (address pool1, address g1,) = deployGovernanceGauge();
        uint256 slot1 = lastSlot;
        w.gauge0 = g0;
        w.gauge1 = g1;
        w.tk.mint(reporter, 4 * STAKE);
        w.tk.mint(payer, 2 * FEE);
        vm.prank(reporter);
        w.tk.approve(address(w.bF), 4 * STAKE);
        vm.prank(payer);
        w.tk.approve(address(w.coreF), 2 * FEE);
        vm.prank(payer);
        w.coreF.listGauge(pool0, g0, 0, slot0);
        vm.prank(payer);
        w.coreF.listGauge(pool1, g1, 0, slot1);

        // Seed case (its real id parameterizes the matrix) — NOT the attack
        // window; admitted through the real beneficiary-bound path.
        (w.id0,) = submitBeneficiaryBallot(w.bF, address(w.coreF), g0, reporter, 705, keccak256("w05-seed"));
        require(w.bF.getReport(w.id0).reporter == reporter, "w05: seed case admitted");

        // The attack matrix: every surviving mutator, each from its correct
        // authority (or permissionless where none is required), with real
        // ids/amounts so no row can die on authentication, funding or
        // approval.
        w.atk = new ThinReentryAttacker();
        w.atk.setTarget(address(w.bF));
        w.atk.arm(reporter, abi.encodeCall(GaugeBounty.submit, (g1, uint256(0), keccak256("w05-reentry"), uint256(0))));
        w.atk.arm(stranger, abi.encodeCall(GaugeBounty.resolve, (w.id0)));
        w.atk.arm(stranger, abi.encodeCall(GaugeBounty.claim, (w.id0)));
        w.atk.arm(daoOwner, abi.encodeCall(GaugeBounty.markFrivolous, (w.id0)));
        w.atk.arm(stranger, abi.encodeCall(GaugeBounty.flushDao, (1)));
        w.atk.arm(address(agent), abi.encodeCall(GaugeBounty.bindLister, (address(w.coreF))));
        w.atk.arm(address(agent), abi.encodeCall(GaugeBounty.creditBallot, (w.id0, reporter)));
        w.atk.arm(address(agent), abi.encodeCall(GaugeBounty.recognizeKill, (w.id0)));
        w.atk.arm(address(w.coreF), abi.encodeCall(GaugeBounty.creditReward, (w.id0, 1e18)));
    }

    /// @dev Window 1: reentrant attack during the bond pull of a live
    /// submit. The outer lock is held (_lockState == 2), so EVERY row must
    /// die at the shared mutex.
    function _w05WindowSubmit(W05World memory w) private returns (bytes32) {
        bytes32 eh1 = keccak256("w05-window");
        (bytes32 preId1, uint256 pid1) =
            createBeneficiaryBallot(w.bF, address(w.coreF), w.gauge1, reporter, reporter, 706, eh1);
        preId1;
        w.tk.armAttack(address(w.atk), abi.encodeWithSignature("run()"), true, true);
        vm.prank(reporter);
        bytes32 id1 = w.bF.submit(w.gauge1, pid1, eh1, 706);
        w.tk.disarm();
        assertEq(w.atk.runs(), 1, "w05: the matrix really fired inside the token callback");
        _w05ExpectMatrixRefusals(w);
        // The outer submit itself completed: the accepted report exists.
        assertEq(uint256(w.bF.getReport(id1).phase), 1, "outer submit completed under the attack");
        (uint256 heldW,, uint256 daoW) = w.bF.accounting();
        assertEq(heldW, 2 * STAKE, "matrix changed no liability");
        assertEq(daoW, 0, "matrix forfeited nothing");
        assertEq(uint8(w.bF.getReport(w.id0).stakeState), uint8(StakeState.Bonded), "no reentrant slash");
        return id1;
    }

    /// @dev Window 2: the same matrix re-fires during claim's payout (the
    /// transfer direction) while the outer claim holds the lock. Bond
    /// recovery is the outer call's alone.
    function _w05WindowClaim(W05World memory w) private {
        // The window case is taken to its own local terminal endpoint: the
        // original-clock expiry at executeBy + 1 (no dependency is needed).
        ReportView memory rv1 = w.bF.getReport(w.id1);
        require(uint256(rv1.phase) == 1, "w05: window case live");
        vm.warp(rv1.executeBy + 1);
        uint256 repBefore = w.tk.balanceOf(reporter);
        w.tk.armAttack(address(w.atk), abi.encodeWithSignature("run()"), true, true);
        (uint256 stakeC,) = w.bF.claim(w.id1);
        w.tk.disarm();
        assertEq(stakeC, STAKE, "outer claim pays exactly once under the attack");
        assertEq(w.atk.runs(), 2, "w05: the matrix really fired inside the payout callback");
        _w05ExpectMatrixRefusals(w);
        (uint256 heldP,,) = w.bF.accounting();
        assertEq(heldP, STAKE, "only the seed bond remains held");
        assertEq(w.tk.balanceOf(reporter) - repBefore, STAKE, "reporter paid exactly once across both windows");
    }

    /// @dev Every row refused, and refused by the shared mutex
    /// (Reentrancy) — never by outsider authentication, funding or
    /// approval. The retired fence rows left with the self-call machinery.
    function _w05ExpectMatrixRefusals(W05World memory w) private view {
        bytes4 cause = IGaugeBounty.Reentrancy.selector;
        for (uint256 i = 0; i < 9; ++i) {
            (bool completed, bytes memory ret) = w.atk.rowResult(i);
            assertFalse(completed, "reentrant mutator completed its effects");
            assertEq(_sel(ret), cause, "not the shared mutex");
        }
    }

    /// @dev The first four bytes of a low-level call's returned data.
    function _sel(bytes memory ret) private pure returns (bytes4) {
        if (ret.length < 4) return bytes4(0);
        bytes4 s;
        assembly {
            s := mload(add(ret, 0x20))
        }
        return s;
    }

    /// @dev The complete deleted-surface inventory probed by low-level call
    /// from every privileged identity: no fallback and no receive may answer.
    function _expectRemovedSurface(GaugeBounty b, address core_, address gauge, bytes32 id) private {
        bytes[] memory removed = new bytes[](33);
        removed[0] = abi.encodeWithSignature("commit(address,bytes32)", gauge, bytes32(uint256(1)));
        removed[1] = abi.encodeWithSignature(
            "submit(bytes32,bytes32,bytes32)", bytes32(uint256(1)), bytes32(uint256(2)), bytes32(uint256(3))
        );
        removed[2] = abi.encodeWithSignature("expire(bytes32)", id);
        removed[3] = abi.encodeWithSignature("finalize(bytes32)", id);
        removed[4] = abi.encodeWithSignature(
            "registerFrivolousVote(bytes32,uint256,bytes32)", id, uint256(1), bytes32(uint256(3))
        );
        removed[5] = abi.encodeWithSignature("declareFrivolous(bytes32,bytes32)", id, bytes32(uint256(4)));
        removed[6] = abi.encodeWithSignature("authorizeGauge(address,bytes32)", gauge, bytes32(uint256(5)));
        removed[7] = abi.encodeWithSignature("retire()");
        removed[8] = abi.encodeWithSignature("recoverStandingCRV()");
        removed[9] = abi.encodeWithSignature("recoverCRV()");
        removed[10] = abi.encodeWithSignature("lockPrincipal()");
        removed[11] = abi.encodeWithSignature("queueAt(uint256)", uint256(0));
        removed[12] = abi.encodeWithSignature("activeReport(address)", gauge);
        removed[13] = abi.encodeWithSignature("killScript(bytes32)", id);
        // Rework-deleted callables (§6): each removed selector probed raw.
        removed[26] = abi.encodeWithSignature("fundStandingLock(uint256)", uint256(1e18));
        removed[27] = abi.encodeWithSignature("maintainStandingLock()");
        removed[28] = abi.encodeWithSignature("createPendingVote(bytes32)", id);
        removed[29] = abi.encodeWithSignature("servicePending(uint256)", uint256(1));
        removed[30] = abi.encodeWithSignature("queueState()");
        removed[31] = abi.encodeWithSignature("submit(address,bytes32)", gauge, bytes32(uint256(1)));
        removed[32] = abi.encodeWithSignature("prepareKill(bytes32)", id);
        removed[14] = abi.encodeWithSignature("frivolousScript(bytes32,bytes32)", id, bytes32(uint256(6)));
        removed[15] = abi.encodeWithSignature("nextNonce(address)", reporter);
        removed[16] = abi.encodeWithSignature(
            "commitmentFor(address,address,uint256,bytes32,bytes32)",
            reporter,
            gauge,
            uint256(0),
            bytes32(uint256(7)),
            bytes32(uint256(8))
        );
        removed[17] = abi.encodeWithSignature("sweep(address)", stranger);
        removed[18] = abi.encodeWithSignature("execute(address,uint256,bytes)", address(crvUSD), uint256(0), hex"");
        removed[19] = abi.encodeWithSignature("reveal(bytes32,bytes32)", bytes32(uint256(9)), bytes32(uint256(10)));
        removed[20] = abi.encodeWithSignature("getGaugePolicy(address)", gauge);
        removed[21] = abi.encodeWithSignature("court(bytes32)", id);
        removed[22] = abi.encodeWithSignature("slashedStake(bytes32)", id);
        removed[23] = abi.encodeWithSignature("recoverCRV()");
        removed[24] = abi.encodeWithSignature("claimStake(bytes32)", id);
        removed[25] = abi.encodeWithSignature("claimReward(bytes32)", id);

        address[5] memory probes = [address(agent), treasury, daoOwner, address(core_), stranger];
        uint256 crvAtBounty = crv.balanceOf(address(b));
        uint256 usdAtBounty = crvUSD.balanceOf(address(b));
        for (uint256 p = 0; p < removed.length; ++p) {
            for (uint256 c = 0; c < probes.length; ++c) {
                _expectAbsentSelector(removed[p]);
                vm.prank(probes[c]);
                (bool ok,) = address(b).call(removed[p]);
                assertFalse(ok, "removed payload still live");
            }
        }
        (bool junkOk,) = address(b).call(hex"00000000");
        assertFalse(junkOk, "no fallback");
        (bool shortOk,) = address(b).call(hex"1234");
        assertFalse(shortOk, "no short-calldata fallback");
        vmx.deal(address(this), 1 ether);
        (bool ethOk,) = address(b).call{value: 1 wei}("");
        assertFalse(ethOk, "no receive");
        assertEq(crv.balanceOf(address(b)), crvAtBounty, "probes moved no CRV");
        assertEq(crvUSD.balanceOf(address(b)), usdAtBounty, "probes moved no crvUSD");
    }

    // ------------------------------------------------------------------ W06

    /// @dev Deliberately odd donated amounts: never round liabilities.
    uint256 internal constant DONATED_USD = 500e18;
    uint256 internal constant DONATED_CRV = 1234e18;

    function test_Thin_DonationsAreNotCredits() public {
        (CurveGaugeListerV2 core_, GaugeBounty b) = deployBoundPair();
        (uint256 zh0, uint256 zh1, uint256 zh2) = b.accounting();
        bytes32 zeroHash = keccak256(abi.encode(zh0, zh1, zh2));

        _donateSurplus(b);
        (uint256 dh0, uint256 dh1, uint256 dh2) = b.accounting();
        assertEq(keccak256(abi.encode(dh0, dh1, dh2)), zeroHash, "donations never change a bucket");
        // The bounty holds NO principal at all: an unsolicited CRV push is
        // inert unaccounted surplus with no lock, checker or capital exit.
        assertEq(crv.balanceOf(address(b)), DONATED_CRV, "surplus sits unaccounted at the contract");

        _donateToFeeDistributor(b, zeroHash);
        _expectNoCapitalExit(b);

        // ---- Donated balance is not flushable: flushDao is bounded by the
        // REAL daoLiability, never by the token balance.
        vm.prank(stranger);
        vm.expectRevert(IGaugeBounty.BadAmount.selector);
        b.flushDao(DONATED_USD);
        vm.prank(stranger);
        vm.expectRevert(IGaugeBounty.BadAmount.selector);
        b.flushDao(1);
        assertEq(crvUSD.balanceOf(address(b)), DONATED_USD, "unflushable surplus still held");
        // There is no project CRV path whatsoever: the bounty never pulls,
        // approves or locks CRV, and the config carries no CRV/escrow/
        // checker/treasury identity (§6 tuple equality is checked above).

        _expectClaimsPayExactlyLiabilities(b, core_);
        _expectFlushCappedAtLiability(b, core_);
    }

    /// @dev Unsolicited crvUSD and CRV pushed into the bounty by a stranger.
    function _donateSurplus(GaugeBounty b) private {
        crvUSD.mint(stranger, DONATED_USD);
        vm.prank(stranger);
        crvUSD.transfer(address(b), DONATED_USD);
        crv.mint(stranger, DONATED_CRV);
        vm.prank(stranger);
        crv.transfer(address(b), DONATED_CRV);
    }

    /// @dev An FD-income-shaped permissionless transfer into the pinned FD is
    /// real FD income and must never touch a bounty bucket.
    function _donateToFeeDistributor(GaugeBounty b, bytes32 zeroHash) private {
        uint256 fdIncomeBefore = crvUSD.balanceOf(address(fd));
        crvUSD.mint(stranger, 999e18);
        vm.prank(stranger);
        crvUSD.transfer(address(fd), 999e18);
        (uint256 fh0, uint256 fh1, uint256 fh2) = b.accounting();
        assertEq(keccak256(abi.encode(fh0, fh1, fh2)), zeroHash, "FD income never becomes bounty credit");
        assertEq(crvUSD.balanceOf(address(fd)) - fdIncomeBefore, 999e18, "FD received the income only");
    }

    /// @dev No recovery/sweep/withdraw endpoint exists for the CRV surplus.
    function _expectNoCapitalExit(GaugeBounty b) private {
        bytes[] memory exits = new bytes[](8);
        exits[0] = abi.encodeWithSignature("recoverStandingCRV()");
        exits[1] = abi.encodeWithSignature("recoverCRV()");
        exits[2] = abi.encodeWithSignature("recover()");
        exits[3] = abi.encodeWithSignature("withdraw()");
        exits[4] = abi.encodeWithSignature("withdrawAll()");
        exits[5] = abi.encodeWithSignature("withdraw(uint256)", DONATED_CRV);
        exits[6] = abi.encodeWithSignature("sweep(address)", treasury);
        exits[7] = abi.encodeWithSignature("emergencyWithdraw()");
        uint256 treasuryCrvBefore = crv.balanceOf(treasury);
        uint256 escrowCrvBefore = crv.balanceOf(address(escrow));
        for (uint256 i = 0; i < exits.length; ++i) {
            for (uint256 r = 0; r < 3; ++r) {
                address caller = r == 0 ? address(agent) : (r == 1 ? treasury : daoOwner);
                _expectAbsentSelector(exits[i]);
                vm.prank(caller);
                (bool ok,) = address(b).call(exits[i]);
                assertFalse(ok, "surplus is not sweepable");
            }
        }
        assertEq(crv.balanceOf(address(b)), DONATED_CRV, "CRV surplus intact");
        assertEq(crv.balanceOf(treasury), treasuryCrvBefore, "nothing reached the treasury");
        assertEq(crv.balanceOf(address(escrow)), escrowCrvBefore, "lock untouched");
    }

    /// @dev A canonically recognized case pays exactly its own bond plus its
    /// funded half of the remainder, never one unit of the donated surplus.
    function _expectClaimsPayExactlyLiabilities(GaugeBounty b, CurveGaugeListerV2 core_) private {
        (, address gauge,) = listBountyEligible(core_);
        (bytes32 id, uint256 pid) =
            submitBeneficiaryBallot(b, address(core_), gauge, reporter, 606, keccak256("w06-recognized"));
        ReportView memory rv = b.getReport(id);
        require(uint256(rv.phase) == 1, "admitted");
        _tallyYesAndExecute(b, id, pid);
        require(uint256(b.getReport(id).phase) == 3, "recognized");
        (uint256 heldN, uint256 creditsN, uint256 daoN) = b.accounting();
        assertEq(heldN, STAKE, "bond is held (Refundable still counts)");
        assertEq(uint8(b.getReport(id).stakeState), uint8(StakeState.Refundable), "one real bond liability");
        assertEq(creditsN, 0, "no credit funded yet");
        assertEq(daoN, 0, "donation is not a reserved liability");

        uint256 rem = core_.getListing(gauge).remaining;
        _spaceFdCursor();
        uint256 fdBefore = crvUSD.balanceOf(address(fd));
        vm.prank(stranger);
        core_.confiscate(gauge);
        assertEq(b.getReport(id).rewardCredit, rem / 2, "credit is exactly half the remainder");
        (, uint256 creditsF,) = b.accounting();
        assertEq(creditsF, rem / 2, "only the funded half is a credit");
        assertEq(crvUSD.balanceOf(address(fd)) - fdBefore, rem - rem / 2, "FD got exactly F");
        _claimsOf(b, id, rem);
    }

    /// @dev Combined claim pays the bond then the credit, never the surplus.
    function _claimsOf(GaugeBounty b, bytes32 id, uint256 rem) private {
        uint256 repBefore = crvUSD.balanceOf(reporter);
        uint256 bountyBefore = crvUSD.balanceOf(address(b));
        // Available bond and funded reward pay TOGETHER in one claim.
        (uint256 stW, uint256 rwW) = b.claim(id);
        assertEq(stW, STAKE, "stake pays exactly the bond");
        assertEq(rwW, rem / 2, "reward pays exactly the credit, same call");
        (uint256 stW2, uint256 rwW2) = b.claim(id);
        assertEq(stW2, 0, "stake already paid");
        assertEq(rwW2, 0, "reward already paid");
        assertEq(crvUSD.balanceOf(reporter) - repBefore, STAKE + rem / 2, "no donation leaked to the reporter");
        assertEq(bountyBefore - crvUSD.balanceOf(address(b)), STAKE + rem / 2, "only liabilities were paid");
        assertEq(crvUSD.balanceOf(address(b)), DONATED_USD, "donated surplus stays put");
        (uint256 stW3, uint256 rwW3) = b.claim(id);
        assertEq(stW3, 0, "repeat stake pays nothing");
        assertEq(rwW3, 0, "repeat reward pays nothing");
    }

    /// @dev Even a RESERVED liability cannot be inflated by the surplus: the
    /// flush ceiling is exactly daoLiability.
    function _expectFlushCappedAtLiability(GaugeBounty b, CurveGaugeListerV2 core_) private {
        (, address g2,) = listBountyEligible(core_);
        (bytes32 id2,) = submitBeneficiaryBallot(b, address(core_), g2, secondReporter, 607, keccak256("w06-forfeit"));
        vm.prank(daoOwner);
        assertTrue(b.markFrivolous(id2), "forfeit reserves the real liability");
        (,, uint256 daoW) = b.accounting();
        assertEq(daoW, STAKE, "liability is exactly one bond");
        vm.prank(stranger);
        vm.expectRevert(IGaugeBounty.BadAmount.selector);
        b.flushDao(STAKE + 1); // one unit past the reserved liability
        // The token balance is liability + donated surplus: a flush sized to
        // the BALANCE (not the liability) is refused outright.
        vm.prank(stranger);
        vm.expectRevert(IGaugeBounty.BadAmount.selector);
        b.flushDao(STAKE + DONATED_USD);

        // ---- There is NO principal and no funding endpoint to top up:
        // any unsolicited CRV movement (even from the treasury role address)
        // leaves the liability ledger, the CRV surplus and all crvUSD
        // custody exactly as they were.
        uint256 bountySurplusBefore = crv.balanceOf(address(b));
        require(bountySurplusBefore == DONATED_CRV, "surplus still present");
        crv.mint(treasury, 1e18);
        uint256 treasuryBefore = crv.balanceOf(treasury);
        vm.prank(treasury);
        crv.transfer(address(b), 1e18); // pure push: no pull path exists
        assertEq(treasuryBefore - crv.balanceOf(treasury), 1e18, "treasury debited its own push");
        assertEq(crv.balanceOf(address(b)), bountySurplusBefore + 1e18, "pushed CRV is inert surplus");
        // crvUSD custody is exactly the untouchable surplus PLUS the one
        // reserved forfeited bond: the push moved no crvUSD at all.
        assertEq(crvUSD.balanceOf(address(b)), DONATED_USD + STAKE, "surplus + reserved liability only");
        (,, uint256 daoW2) = b.accounting();
        assertEq(daoW2, STAKE, "the reserved liability is still unpaid");
    }

    // ------------------------------------------------------------------ W07

    function test_Thin_LocalViewsAndUnknownIds() public {
        (CurveGaugeListerV2 core_, GaugeBounty b) = deployBoundPair();

        // ---- Unknown report: the COMPLETE all-zero tuple.
        _expectAllZeroReport(b);
        _expectZeroOnlyViews(b);

        // ---- No protocol queue exists: two admissions coexist and every
        // local read is per-report. The winner latch is the ONLY
        // hook-visible permanent record and pending reports never appear.
        (bytes32 idSeed,) = _submitOn(b, core_, reporter);
        require(uint256(b.getReport(idSeed).phase) == 1, "seed admitted");
        (bytes32 idQ,) = _submitOn(b, core_, secondReporter);
        require(uint256(b.getReport(idQ).phase) == 1, "second report coexists");

        // Local expiry on the ORIGINAL clock: Expired + refundable, pure
        // local close with zero external reads.
        vm.warp(b.getReport(idQ).executeBy + 1);
        assertTrue(b.resolve(idQ), "expired locally");
        assertEq(uint256(b.getReport(idQ).phase), 6, "Expired");
        assertEq(uint8(b.getReport(idQ).stakeState), uint8(StakeState.Refundable), "refundable");

        _expectLocalViewsUnderFaults(b, core_);
    }

    /// @dev Every field of the flat report view (identity, ballot binding,
    /// clocks, phase, bond disposition and credit — all ten §6 components)
    /// must be exactly zero for an id that never existed.
    function _expectAllZeroReport(GaugeBounty b) private {
        ReportView memory z = b.getReport(keccak256("never-seen"));
        assertEq(z.reporter, address(0), "unknown reporter");
        assertEq(z.gauge, address(0), "unknown gauge");
        assertEq(z.listingId, bytes32(0), "unknown listing");
        assertEq(z.evidenceHash, bytes32(0), "unknown evidence");
        assertEq(z.proposalId, 0, "unknown proposalId");
        assertEq(z.voteEnd, 0, "unknown voteEnd");
        assertEq(z.executeBy, 0, "unknown executeBy");
        assertEq(uint256(z.phase), 0, "unknown phase");
        assertEq(z.stakeState, 0, "unknown stakeState");
        assertEq(z.rewardCredit, 0, "unknown rewardCredit");
        ReportView memory zeroView;
        assertEq(keccak256(abi.encode(z)), keccak256(abi.encode(zeroView)), "every unknown field is zero");
        vm.expectRevert(IGaugeBounty.UnknownReport.selector);
        b.resolve(keccak256("never-seen"));
    }

    /// @dev Empty-world view shapes: unknown id is the complete zero tuple
    /// and the hook read is exactly zero (§4: no latch, all-zero tuple even
    /// when proposals exist).
    function _expectZeroOnlyViews(GaugeBounty b) private view {
        (bytes32 unknownId, address unknownRep, bool unknownEligible) = b.rewardTerms(actor("neverListedGauge"));
        assertEq(unknownId, bytes32(0), "unknown hook id");
        assertEq(unknownRep, address(0), "unknown hook reporter");
        assertFalse(unknownEligible, "unknown hook ineligible");
    }

    /// @dev Every local view must return byte-identical values with the gauge
    /// flag read and the Voting getVote read both forcibly broken.
    function _expectLocalViewsUnderFaults(GaugeBounty b, CurveGaugeListerV2 core_) private {
        (bytes32 idF, address faultGauge) = _submitOn(b, core_, reporter);
        require(idF != bytes32(0), "fault case accepted");
        bytes32 reportShape = keccak256(abi.encode(b.getReport(idF)));
        bytes32 acctShape = _acctShape(b);
        (bytes32 hookShape) = _viewShapes(b, faultGauge);

        GovernanceGauge(faultGauge).setFlagFault(1); // gauge is_killed reverts
        voting.setGetVoteFault(1); // getVote reverts
        assertEq(keccak256(abi.encode(b.getReport(idF))), reportShape, "getReport is dependency-free");
        assertEq(_acctShape(b), acctShape, "accounting is local");
        (bytes32 hookShape2) = _viewShapes(b, faultGauge);
        assertEq(hookShape2, hookShape, "rewardTerms is local");
        _expectConfigAndBindingLocal(b, core_);
        GovernanceGauge(faultGauge).setFlagFault(0);
        voting.setGetVoteFault(0);
    }

    function _acctShape(GaugeBounty b) private view returns (bytes32) {
        (uint256 h, uint256 c, uint256 d) = b.accounting();
        return keccak256(abi.encode(h, c, d));
    }

    /// @dev The complete surviving callable surface: EXACTLY the 14 functions
    /// of plans/BOUNTY-REWORK-PLAN.md §6 / plans/bountyrework/abi-manifest.json.
    /// A deleted-payload probe only proves absence when its selector belongs
    /// to none of these, so every probe is collision-checked first. Any
    /// drift in this list fails the manifest equality check below.
    function _realSelectors() private pure returns (bytes4[14] memory s) {
        s[0] = GaugeBounty.config.selector;
        s[1] = GaugeBounty.lister.selector;
        s[2] = GaugeBounty.bindLister.selector;
        s[3] = GaugeBounty.submit.selector;
        s[4] = GaugeBounty.creditBallot.selector;
        s[5] = GaugeBounty.recognizeKill.selector;
        s[6] = GaugeBounty.rewardTerms.selector;
        s[7] = GaugeBounty.creditReward.selector;
        s[8] = GaugeBounty.resolve.selector;
        s[9] = GaugeBounty.claim.selector;
        s[10] = GaugeBounty.markFrivolous.selector;
        s[11] = GaugeBounty.flushDao.selector;
        s[12] = GaugeBounty.getReport.selector;
        s[13] = GaugeBounty.accounting.selector;
        return s;
    }

    /// @dev Selector equality against the §6 manifest (computed from the
    /// ABI declarations of GaugeBounty itself, so a renamed/added/removed
    /// endpoint fails here, not silently).
    function _expectExactCallableSurface() internal pure {
        bytes4[14] memory m = _realSelectors();
        bytes4[14] memory expect;
        expect[0] = bytes4(0x79502c55); // config()
        expect[1] = bytes4(0x2cdc1c74); // lister()
        expect[2] = bytes4(0x9389f319); // bindLister(address)
        expect[3] = bytes4(0x12980769); // submit(address,uint256,bytes32,uint256)
        expect[4] = bytes4(0xbe1acbef); // creditBallot(bytes32,address)
        expect[5] = bytes4(0xe1e58a40); // recognizeKill(bytes32)
        expect[6] = bytes4(0xc249734c); // rewardTerms(address)
        expect[7] = bytes4(0xb8491252); // creditReward(bytes32,uint256)
        expect[8] = bytes4(0x5c23bdf5); // resolve(bytes32)
        expect[9] = bytes4(0xbd66528a); // claim(bytes32)
        expect[10] = bytes4(0x948bfa9d); // markFrivolous(bytes32)
        expect[11] = bytes4(0x23cc88b8); // flushDao(uint256)
        expect[12] = bytes4(0x171c4f11); // getReport(bytes32)
        expect[13] = bytes4(0x9624e83e); // accounting()
        for (uint256 i = 0; i < m.length; ++i) {
            assertEq(m[i], expect[i], "rework plan section-6 manifest selector mismatch");
        }
    }

    /// @dev A removed payload is only evidence if its 4-byte selector belongs
    /// to no surviving function of the product.
    function _expectAbsentSelector(bytes memory payload) private pure {
        bytes4 sel = bytes4(payload);
        bytes4[14] memory real = _realSelectors();
        for (uint256 i = 0; i < real.length; ++i) {
            assertTrue(sel != real[i], "deleted payload collides with a live selector");
        }
    }

    /// @dev Canonical encoding of the multi-value local hook view.
    function _viewShapes(GaugeBounty b, address gauge) private view returns (bytes32) {
        (bytes32 slotId, address slotReporter, bool eligible) = b.rewardTerms(gauge);
        return keccak256(abi.encode(slotId, slotReporter, eligible));
    }

    /// @dev config(), lister() and the unknown-id report are all local reads.
    function _expectConfigAndBindingLocal(GaugeBounty b, CurveGaugeListerV2 core_) private view {
        ReportView memory zeroView;
        assertEq(
            keccak256(abi.encode(b.getReport(keccak256("still-unknown")))),
            keccak256(abi.encode(zeroView)),
            "unknown stays zero under faults"
        );
        assertEq(b.lister(), address(core_), "lister() local under dependency faults");
        assertEq(keccak256(abi.encode(b.config())), keccak256(abi.encode(defaultBountyConfig())), "config() local");
    }
}

/// @dev Test-only reentrancy matrix actor (never a product hook, never an
/// address the product trusts): invoked from the bounty's own stake token's
/// callback, it re-enters each armed mutator payload from its correct
/// authority using the standard prank-before-call technique and records the
/// real per-row outcome so the suite can attribute each refusal precisely.
interface IThinReentryVm {
    function prank(address newCaller) external;
}

contract ThinReentryAttacker {
    IThinReentryVm private constant VM = IThinReentryVm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    struct Row {
        address authority;
        bytes payload;
        bool completed;
        bytes ret;
    }

    Row[] private _rows;
    address private _target;
    uint256 private _runs;

    function setTarget(address t) external {
        _target = t;
    }

    function arm(address authority, bytes calldata payload) external {
        _rows.push(Row({authority: authority, payload: payload, completed: false, ret: ""}));
    }

    function runs() external view returns (uint256) {
        return _runs;
    }

    function rowCount() external view returns (uint256) {
        return _rows.length;
    }

    function rowResult(uint256 i) external view returns (bool, bytes memory) {
        return (_rows[i].completed, _rows[i].ret);
    }

    /// @dev Fired from the token callback while the outer operation holds
    /// the shared guard: every row must revert, and its revert data is the
    /// witness of WHICH protection refused it.
    function run() external {
        _runs += 1;
        for (uint256 i = 0; i < _rows.length; ++i) {
            VM.prank(_rows[i].authority);
            (bool ok, bytes memory ret) = _target.call(_rows[i].payload);
            _rows[i].completed = ok;
            _rows[i].ret = ret;
        }
    }
}
