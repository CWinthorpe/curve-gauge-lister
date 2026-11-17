// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BountyFixture} from "../BountyFixture.sol";
import {GaugeBounty} from "../../../contracts/GaugeBounty.sol";
import {CurveGaugeListerV2} from "../../../contracts/CurveGaugeListerV2.sol";
import {IGaugeBounty} from "../../../contracts/interfaces/IGaugeBounty.sol";
import {ReportView, Phase, StakeState} from "../../../contracts/bounty/BountyTypes.sol";
import {FeeDistributorAccounting} from "../../../contracts/libraries/FeeDistributorAccounting.sol";
import {VotiumAdapter} from "../../../contracts/adapters/VotiumAdapter.sol";
import {VoteMarketAdapter} from "../../../contracts/adapters/VoteMarketAdapter.sol";
import {MockCampaignRemoteManager} from "../../../contracts/mocks/MockCampaignRemoteManager.sol";
import {IIncentivePlatform} from "../../../contracts/interfaces/IIncentivePlatform.sol";
import {V2ListerCaller} from "../../v2/V2Adapters.t.sol";
import {GovernanceGauge} from "../mocks/MockBountyGovernance.sol";
import {MockIncentivePlatform} from "../../../contracts/mocks/MockIncentivePlatform.sol";
import {MockListingController} from "../../../contracts/mocks/MockListingController.sol";

/// @dev Local vm.deal handle for funding the adapter ETH float (same
/// cheatcode dispatcher; mirrors the preserved parity suite's VmDeal).
interface S02DealVm {
    function deal(address who, uint256 amount) external;
}

/// @notice Thin attack replays (plans/BOUNTY-THIN-PLAN.md §7.2 S01–S06):
/// the six requested end-to-end threats run against the REAL product with
/// real mocks and real adapters — binding race, misbound adapter,
/// slash-vs-kill ordering, queue fairness, double report and §3.3 refund
/// exhaustiveness under hostile non-token dependencies. S01/S02 replay the
/// named V2-audit threats carried from the banked suite against the thin
/// ABI. Assertions must fail at the intended protection, never at missing
/// approval/authority/fixture funding.
contract ThinSafetyTest is BountyFixture {
    struct Live {
        CurveGaugeListerV2 core_;
        GaugeBounty b;
        address gauge;
        bytes32 id;
        uint256 voteId;
    }

    uint256 internal _seq = 1;

    /// @dev Real-adapter campaign economics constants (mirrors the preserved
    /// V2 parity suite's pinned values).
    address internal constant S02_VM_L2 = 0x8c2c5A295450DDFf4CB360cA73FCCC12243D14D9;
    uint256 internal constant S02_GWEI = 1 gwei;
    uint256 internal constant S02_REQUIRED_ETH = 2_000_000 * 1 gwei;

    /// @dev Local vm.deal handle for funding the adapter ETH float.
    S02DealVm internal constant s02vm = S02DealVm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    // Rework Phase numbering (plans/BOUNTY-REWORK-PLAN.md §6): Queued and
    // the whole queue are gone; these mirror BountyTypes.Phase exactly.
    uint8 internal constant _PH_PROPOSED = 1;
    uint8 internal constant _PH_RECOGNIZED = 3;
    uint8 internal constant _PH_REWARDED = 4;
    uint8 internal constant _PH_REJECTED = 5;
    uint8 internal constant _PH_EXPIRED = 6;
    uint8 internal constant _PH_NOAWARD = 7;

    function setUp() public {
        setupBountyWorld();
    }

    // ---------------------------------------------------------------- glue

    function _approveStake(GaugeBounty b, address who, uint256 times) internal {
        crvUSD.mint(who, STAKE * times);
        approveCrvUsd(who, address(b), STAKE * times);
    }

    /// @dev Fresh funded pair with one report admitted through the REAL
    /// beneficiary-bound ballot path (immediately Proposed).
    function _proposed() internal returns (Live memory L) {
        (L.core_, L.b) = deployBoundPair();
        L.gauge = _list(L.core_);
        bytes32 eh = keccak256(abi.encode("safety-evidence", L.gauge, _seq));
        _seq += 1;
        (L.id, L.voteId) = submitBeneficiaryBallot(L.b, address(L.core_), L.gauge, reporter, _seq, eh);
        ReportView memory rv = L.b.getReport(L.id);
        // proposalId may legitimately be 0 (the very first ballot): the
        // stored nonzero reporter, not the id, distinguishes existence.
        require(uint8(rv.phase) == _PH_PROPOSED && rv.reporter != address(0), "safety: admitted");
    }

    function _list(CurveGaugeListerV2 c) internal returns (address gauge) {
        (, gauge,) = listBountyEligible(c);
    }

    address internal _whale = address(uint160(0x9E7AC001));

    function _tallyPass(Live memory L) internal {
        if (_whaleFunded == 0) {
            giveVePower(_whale, 50_000_000e18);
            _whaleFunded = 1;
        }
        vm.prank(_whale);
        voting.vote(L.voteId, true);
    }

    uint8 internal _whaleFunded;

    /// @dev Full canonical path: real ballots, real script through the real
    /// Agent/proxy/gauge flow, ending in Recognized with the flag true.
    function _canonicalKill(Live memory L) internal {
        _tallyPass(L);
        vm.warp(L.b.getReport(L.id).voteEnd);
        vm.prank(stranger);
        voting.executeVote(L.voteId);
        require(uint8(L.b.getReport(L.id).phase) == _PH_RECOGNIZED, "safety: recognized");
        require(GovernanceGauge(L.gauge).is_killed(), "safety: killed via route");
    }

    /// @dev Hostile non-token dependencies: malformed Voting reads, reverting
    /// flag reads, a paused lister, a blocked checker and an unusable FD.
    /// The healthy crvUSD path is what must remain sufficient for refunds.
    function _hostileDeps(Live memory L) internal {
        voting.setGetVoteFault(1); // getVote reverts outright
        GovernanceGauge(L.gauge).setFlagFault(1); // flag reads revert
        escrow.setCheckerBlock(true); // lock maintenance reverts
        fd.setCanCheckpoint(false); // FD refuses accounting
    }

    /// @dev bountyreworkfix C3(c): install genuinely broken lister/owner
    /// observations on THIS row's freshly deployed V2 (per-row deployments
    /// keep the fault local). `unavailable=true` replaces the runtime with
    /// an invalid opcode so every lister call (getListing, listingId, owner)
    /// REVERTS outright; `unavailable=false` replaces it with a runtime that
    /// returns a malformed word for every call — the shape checks fail and
    /// identity reads return garbage, i.e. the observations are INVALID.
    /// Paused-but-readable is not an outage and no longer stands in for one
    /// on the F3/F4 dependency-independence rows (review/BOUNTY-REWORK-CONF.md
    /// C3(c)). A labelled fixture fault, never a product path.
    function _breakLister(CurveGaugeListerV2 lister, bool unavailable) internal {
        if (unavailable) {
            vmx.etch(address(lister), hex"fe");
        } else {
            vmx.etch(address(lister), type(ListerGarbageRuntime).runtimeCode);
        }
    }

    /// @dev Everything markFrivolous may change, and only that: the flat
    /// view minus the bond disposition, plus the full V2 listing.
    /// @dev Tally+execute one specific ballot (winner/loser race cells).
    function _tallyPassLive(GaugeBounty b, bytes32 id, uint256 proposalId) internal {
        if (_whaleFunded == 0) {
            giveVePower(_whale, 50_000_000e18);
            _whaleFunded = 1;
        }
        vm.prank(_whale);
        voting.vote(proposalId, true);
        vm.warp(b.getReport(id).voteEnd);
        vm.prank(stranger);
        voting.executeVote(proposalId);
    }

    function _fingerprint(Live memory L) internal view returns (bytes32) {
        ReportView memory rv = L.b.getReport(L.id);
        rv.stakeState = uint8(StakeState.None);
        return keccak256(abi.encode(rv, L.core_.getListing(L.gauge)));
    }

    // ------------------------------------------------------------------ S01

    function test_Thin_AttackBindingRace() public {
        // (a) Outsiders race the write-once bounty bind: refused at the
        // intended authority, moving no custody and leaving no lister.
        GaugeBounty fb = new GaugeBounty(defaultBountyConfig());
        (CurveGaugeListerV2 rival,) = deployBoundPair(); // reciprocated elsewhere

        vm.prank(stranger);
        vm.expectRevert(IGaugeBounty.NotAgent.selector);
        fb.bindLister(address(rival));
        vm.prank(daoOwner);
        vm.expectRevert(IGaugeBounty.NotAgent.selector);
        fb.bindLister(address(rival));
        vm.prank(address(agent));
        vm.expectRevert(IGaugeBounty.BadConfiguration.selector);
        fb.bindLister(address(0)); // codeless target
        vm.prank(address(agent));
        vm.expectRevert(IGaugeBounty.BadConfiguration.selector);
        fb.bindLister(address(rival)); // not reciprocal for fb
        assertEq(fb.lister(), address(0), "no outsider/rival bind lands");
        assertEq(crvUSD.balanceOf(address(fb)), 0, "no custody during the race");
        assertEq(address(fb).balance, 0, "no ETH");

        // (b) The intended DAO-side sequence still binds afterwards, once.
        MockIncentivePlatform v1 = new MockIncentivePlatform(address(crvUSD));
        MockIncentivePlatform v2m = new MockIncentivePlatform(address(crvUSD));
        MockListingController ctl = new MockListingController(controllerDao, int128(2));
        CurveGaugeListerV2 mine = new CurveGaugeListerV2(
            address(agent), // bind-time config owner must be the Agent
            address(crvUSD),
            address(ctl),
            address(fd),
            CurveGaugeListerV2.AdmissionConfig(address(registry), 8),
            CurveGaugeListerV2.PlatformConfig(address(v1), address(v2m), 5000),
            address(fb),
            address(tfValidator)
        );
        vm.prank(controllerDao);
        ctl.setLister(address(mine));
        v1.setLister(address(mine));
        v2m.setLister(address(mine));
        vm.prank(address(agent));
        fb.bindLister(address(mine));
        assertEq(fb.lister(), address(mine), "authoritative bind lands");
        vm.prank(address(agent));
        vm.expectRevert(IGaugeBounty.AlreadyBound.selector);
        fb.bindLister(address(rival));

        // (c) The real adapter's lister control cannot be front-run either;
        // no ingress, no ETH, no forged-deposit payout.
        MockIncentivePlatform votiumMock = new MockIncentivePlatform(address(crvUSD));
        address adapterManager = actor("adapterManager");
        VotiumAdapter votiumAdapter = new VotiumAdapter(address(crvUSD), adapterManager, address(votiumMock));
        vm.prank(stranger);
        (bool ok,) = address(votiumAdapter).call(abi.encodeWithSignature("setLister(address)", address(stranger)));
        assertFalse(ok, "no outsider rebind");
        assertEq(crvUSD.balanceOf(address(votiumAdapter)), 0, "adapter float untouched");
        assertEq(address(votiumAdapter).balance, 0, "adapter no ETH");
        vm.prank(stranger);
        (bool okD,) = address(votiumAdapter)
            .call(abi.encodeWithSignature("deposit(address,uint256,uint256)", address(0), uint256(1), uint256(0)));
        okD; // outcome irrelevant: a forged direct deposit pays nothing outward
        assertEq(crvUSD.balanceOf(address(votiumAdapter)), 0, "no ingress from stranger deposits");
        assertEq(votiumAdapter.owner(), adapterManager, "owner control intact");
    }

    // ------------------------------------------------------------------ S02

    struct S02W {
        CurveGaugeListerV2 core_;
        VotiumAdapter ad;
        VoteMarketAdapter vma;
        VotiumAdapter evil;
        VoteMarketAdapter evilVm;
        MockCampaignRemoteManager crm;
        MockIncentivePlatform votiumVenue;
        address adapterManager;
        address rival;
    }

    function test_Thin_AttackMisboundAdapter() public {
        // S02 (thin §7.2:297, §6 T06): the REAL owner successfully misbinds
        // — both platform legs are swapped to fresh adapters that their
        // actual owner bound to a RIVAL lister — then valid FUNDED paid
        // admission must refuse before any pull, and BOTH scheduled-epoch
        // campaign attempts against a funded VoteMarket ETH float replay
        // with exact campaign/bridge-value/ETH/token/allowance no-loss
        // oracles. The preserved V2 parity test
        // (test/v2/V2Adapters.t.sol::test_V2_AuditH01_VoteMarketCaptureCannotSpendEthFloat)
        // keeps the owner-bound-success credit; folding the already-
        // established controls into THIS thin integration identity is what
        // §7.2 S02 owed.
        S02W memory w = _s02DeployAndMisbind();
        _s02AdmissionRefusal(w);
        _s02FloatCapture(w);
        _s02AdmissionControl(w);
    }

    function _s02DeployAndMisbind() private returns (S02W memory w) {
        w.adapterManager = actor("adapterManager2");
        address[] memory platforms = new address[](1);
        platforms[0] = S02_VM_L2;
        w.crm = new MockCampaignRemoteManager(S02_GWEI, platforms);
        w.votiumVenue = new MockIncentivePlatform(address(crvUSD));
        w.ad = new VotiumAdapter(address(crvUSD), w.adapterManager, address(w.votiumVenue));
        w.vma = new VoteMarketAdapter(address(crvUSD), w.adapterManager, address(w.crm), S02_VM_L2);

        // A rival lister to which the evil adapters are genuinely owner-bound.
        CurveGaugeListerV2 rival;
        (rival,) = deployBoundPair();
        w.rival = address(rival);

        // Healthy start: fresh core with the real, correctly owner-bound pair.
        (w.core_,) = _s02PairWithRealAdapters(w.ad, w.vma);

        // (a) The real owner successfully misbinds BOTH legs: the adapter
        // manager owner-bound the fresh evil adapters to the RIVAL core and
        // the V2 config owner installs them as this core's platform config.
        w.evil = new VotiumAdapter(address(crvUSD), w.adapterManager, address(w.votiumVenue));
        w.evilVm = new VoteMarketAdapter(address(crvUSD), w.adapterManager, address(w.crm), S02_VM_L2);
        vm.prank(w.adapterManager);
        w.evil.setLister(w.rival);
        vm.prank(w.adapterManager);
        w.evilVm.setLister(w.rival);
        assertEq(w.evilVm.lister(), w.rival, "evil VM is owner-bound to the WRONG lister");
        vm.prank(daoOwner);
        w.core_.setPlatformConfig(CurveGaugeListerV2.PlatformConfig(address(w.evil), address(w.evilVm), 5000));
        CurveGaugeListerV2.PlatformConfig memory installed = w.core_.getPlatformConfig();
        assertEq(installed.votium, address(w.evil), "misbind landed (votium leg)");
        assertEq(installed.voteMarket, address(w.evilVm), "misbind landed (vote market leg)");
    }

    function _s02AdmissionRefusal(S02W memory w) private {
        // (b) Valid funded paid admission refuses at the intended gate: the
        // payer is funded and approved at the moment of the attempt, so the
        // ONLY possible failure is the misbinding check.
        (uint256 payerBal, uint256 escrowBefore) = _s02AttemptRefused(w);
        assertEq(crvUSD.balanceOf(payer), payerBal, "fee never pulled");
        assertEq(crvUSD.allowance(payer, address(w.core_)), FEE, "allowance untouched by refusal");
        assertEq(crvUSD.balanceOf(address(w.core_)), escrowBefore, "escrow untouched");
        assertEq(crvUSD.balanceOf(address(w.evilVm)), 0, "misbound VM holds no token");
        assertEq(crvUSD.balanceOf(address(w.vma)), 0, "retired VM holds no token");
    }

    /// @dev Funds payer+gauge and attempts admission against the misbound
    /// config; returns the pre-attempt custody readings (also asserted).
    function _s02AttemptRefused(S02W memory w) private returns (uint256 payerBal, uint256 escrowBefore) {
        (address pX, address gX,) = deployGovernanceGauge();
        crvUSD.mint(payer, FEE);
        approveCrvUsd(payer, address(w.core_), FEE);
        payerBal = crvUSD.balanceOf(payer);
        escrowBefore = crvUSD.balanceOf(address(w.core_));
        vm.prank(payer);
        vm.expectRevert(abi.encodeWithSelector(CurveGaugeListerV2.PlatformNotReady.selector, address(w.evil)));
        w.core_.listGauge(pX, gX, 0, lastSlot);
        assertEq(w.core_.listingId(gX), bytes32(0), "no listing materialized");
    }

    function _s02FloatCapture(S02W memory w) private {
        // (c) BOTH scheduled-epoch ETH-float capture attempts replay with
        // exact no-loss oracles against the funded VoteMarket adapter.
        s02vm.deal(address(w.evilVm), 4 * S02_REQUIRED_ETH);
        uint256 floatBefore = address(w.evilVm).balance;
        assertTrue(floatBefore > 0, "funded VoteMarket ETH float");
        uint256 campaigns = w.crm.campaignCount();
        uint256 ethPaid = w.crm.ethPaid();
        uint256 crmEth = address(w.crm).balance;
        uint256 deposits = w.evilVm.depositCount();
        V2ListerCaller attacker = new V2ListerCaller();
        attacker.setToken(address(crvUSD));
        crvUSD.mint(address(attacker), 2 * QUARTER);
        uint256 attackerTok = crvUSD.balanceOf(address(attacker));
        (address pX, address gX,) = deployGovernanceGauge();
        pX;
        uint256 e1 = block.timestamp + WEEK;
        uint256 e2 = block.timestamp + 2 * WEEK;

        // An outsider cannot even redirect the spending authority.
        vm.expectRevert(VoteMarketAdapter.NotOwner.selector);
        vm.prank(stranger);
        w.evilVm.setLister(address(stranger));
        assertEq(w.evilVm.lister(), w.rival, "capture attempt cannot rebind");

        // Attempt 1: scheduled epoch e1 through the lister-caller actor.
        vm.expectRevert(VoteMarketAdapter.NotLister.selector);
        attacker.deposit(IIncentivePlatform(address(w.evilVm)), gX, e1, QUARTER);
        // Attempt 2: scheduled epoch e2, direct outsider call.
        vm.expectRevert(VoteMarketAdapter.NotLister.selector);
        vm.prank(stranger);
        w.evilVm.deposit(gX, e2, QUARTER);

        // Exact campaign / bridge-value / ETH / token / allowance oracles.
        assertEq(w.crm.campaignCount(), campaigns, "no campaign created");
        assertEq(w.crm.ethPaid(), ethPaid, "no bridge value paid");
        assertEq(address(w.crm).balance, crmEth, "messenger received no ETH");
        assertEq(address(w.evilVm).balance, floatBefore, "ETH float intact");
        assertEq(w.evilVm.depositCount(), deposits, "no adapter deposit record");
        assertEq(crvUSD.balanceOf(address(attacker)), attackerTok, "no attacker token loss");
        assertEq(crvUSD.allowance(address(attacker), address(w.evilVm)), 0, "no attacker approval residue");
        assertEq(crvUSD.allowance(address(w.evilVm), address(w.crm)), 0, "no venue approval residue");
    }

    function _s02AdmissionControl(S02W memory w) private {
        // (d) Discriminating control: the refusals above were the misbinding,
        // not a broken fixture — owner-bound correct adapters admit the same
        // funded listing through the SAME core.
        VotiumAdapter goodVa = new VotiumAdapter(address(crvUSD), w.adapterManager, address(w.votiumVenue));
        VoteMarketAdapter goodVm = new VoteMarketAdapter(address(crvUSD), w.adapterManager, address(w.crm), S02_VM_L2);
        vm.prank(w.adapterManager);
        goodVa.setLister(address(w.core_));
        vm.prank(w.adapterManager);
        goodVm.setLister(address(w.core_));
        vm.prank(daoOwner);
        w.core_.setPlatformConfig(CurveGaugeListerV2.PlatformConfig(address(goodVa), address(goodVm), 5000));
        (address pY, address gY,) = deployGovernanceGauge();
        crvUSD.mint(payer, FEE);
        approveCrvUsd(payer, address(w.core_), FEE);
        uint256 payerBefore = crvUSD.balanceOf(payer);
        uint256 escrowBefore = crvUSD.balanceOf(address(w.core_));
        vm.prank(payer);
        w.core_.listGauge(pY, gY, 0, lastSlot);
        assertEq(payerBefore - crvUSD.balanceOf(payer), FEE, "control admission pulls exactly the fee");
        assertEq(crvUSD.balanceOf(address(w.core_)) - escrowBefore, FEE, "control fee sits in real escrow");
        assertEq(uint256(w.core_.getListing(gY).status), 1, "control listing is Active");
    }

    function _s02PairWithRealAdapters(VotiumAdapter ad, VoteMarketAdapter vma)
        internal
        returns (CurveGaugeListerV2 core_, GaugeBounty b)
    {
        b = new GaugeBounty(defaultBountyConfig());
        bounty = b;
        MockListingController ctl = new MockListingController(controllerDao, int128(2));
        core_ = new CurveGaugeListerV2(
            address(agent), // initial owner == configured Agent (thin §2.1)
            address(crvUSD),
            address(ctl),
            address(fd),
            CurveGaugeListerV2.AdmissionConfig(address(registry), 8),
            CurveGaugeListerV2.PlatformConfig(address(ad), address(vma), 5000),
            address(b),
            address(tfValidator)
        );
        vm.prank(controllerDao);
        ctl.setLister(address(core_));
        vm.prank(actor("adapterManager2"));
        ad.setLister(address(core_));
        vm.prank(actor("adapterManager2"));
        vma.setLister(address(core_));
        vm.prank(address(agent));
        b.bindLister(address(core_));
        vm.prank(address(agent));
        core_.transferOwnership(daoOwner);
        vm.prank(daoOwner);
        core_.acceptOwnership();
        vm.prank(daoOwner);
        core_.setPaused(false);
    }

    // ------------------------------------------------------------------ S03

    function test_Thin_AttackSlashVersusKill() public {
        // Twin A: canonical kill, then the owner marks the still-unpaid
        // bond. The half reward survives; only the bond destination varies.
        Live memory A = _proposed();
        _canonicalKill(A);
        bytes32 fpBefore = _fingerprint(A);
        (uint256 heldA0, uint256 credA0, uint256 daoA0) = A.b.accounting();
        assertEq(heldA0, STAKE, "recognized bond held");
        assertEq(credA0, 0, "no credit yet");

        // Foreign authorities refuse at the intended check.
        vm.prank(stranger);
        vm.expectRevert(IGaugeBounty.NotDao.selector);
        A.b.markFrivolous(A.id);
        vm.prank(treasury);
        vm.expectRevert(IGaugeBounty.NotDao.selector);
        A.b.markFrivolous(A.id);

        // The sole frivolousness authority marks once: forfeit-only.
        vm.prank(daoOwner);
        assertTrue(A.b.markFrivolous(A.id), "unpaid refundable bond can forfeit");
        assertEq(_fingerprint(A), fpBefore, "mark changed nothing but the bond");
        assertEq(uint8(A.b.getReport(A.id).phase), _PH_RECOGNIZED, "phase untouched");
        (uint256 heldA1,, uint256 daoA1) = A.b.accounting();
        assertEq(heldA1, heldA0 - STAKE, "held exchange");
        assertEq(daoA1, daoA0 + STAKE, "fixed FD liability only");
        vm.prank(daoOwner);
        assertFalse(A.b.markFrivolous(A.id), "mark is once");

        // Allocation proceeds unvetoed: the half reward is credited despite
        // the stake mark and claims together with a zero bond leg.
        crvUSD.mint(address(A.b), FEE / 2);
        vm.prank(stranger);
        assertEq(A.core_.confiscate(A.gauge), FEE, "mark never vetoes the split");
        (, uint256 credA1,) = A.b.accounting();
        assertEq(credA1, FEE / 2, "half credited");
        uint256 repBal = crvUSD.balanceOf(reporter);
        (uint256 stakeA, uint256 rewardA) = A.b.claim(A.id);
        assertEq(stakeA, 0, "forfeited bond pays no stake");
        assertEq(rewardA, FEE / 2, "reward survives forfeit");
        assertEq(crvUSD.balanceOf(reporter) - repBal, FEE / 2, "exactly the half");

        // Twin B: identical everything except no mark: claim pays both legs.
        Live memory B = _proposed();
        _canonicalKill(B);
        crvUSD.mint(address(B.b), FEE / 2);
        vm.prank(stranger);
        assertEq(B.core_.confiscate(B.gauge), FEE, "twin split");
        uint256 repBalB = crvUSD.balanceOf(reporter);
        (uint256 stakeB, uint256 rewardB) = B.b.claim(B.id);
        assertEq(stakeB, STAKE, "unmarked twin keeps its bond");
        assertEq(rewardB, FEE / 2, "identical reward half");
        assertEq(crvUSD.balanceOf(reporter) - repBalB, STAKE + FEE / 2, "both legs");

        // Paid-then-mark: no late clawback, the mark is inert.
        vm.prank(daoOwner);
        assertFalse(B.b.markFrivolous(B.id), "paid stake cannot forfeit");
        (uint256 heldB1, uint256 credB1, uint256 daoB1) = B.b.accounting();
        assertEq(heldB1, 0, "ledger drained");
        assertEq(credB1, 0, "credit drained");
        assertEq(daoB1, 0, "no liability appears post-payment");

        // Ordering across the ballot: mark BEFORE the kill attempt, then the
        // canonical execution still recognizes (the mark never touches
        // arm/vote/execution eligibility).
        Live memory C = _proposed();
        vm.prank(daoOwner);
        assertTrue(C.b.markFrivolous(C.id), "pre-ballot forfeit of bonded stake");
        _canonicalKill(C);
        assertEq(uint8(C.b.getReport(C.id).phase), _PH_RECOGNIZED, "eligibility survives the mark");
        (uint256 stakeC,) = C.b.claim(C.id);
        assertEq(stakeC, 0, "already forfeited");

        // Interleaving is impossible: the three callback calls arrive ONLY
        // inside the one executed script. Direct attempts are refused and
        // an out-of-band recognize consumes the arm to NoAward.
        Live memory D = _proposed();
        address dReporter = D.b.getReport(D.id).reporter;
        vm.prank(stranger);
        vm.expectRevert(IGaugeBounty.NotAgent.selector);
        D.b.creditBallot(D.id, dReporter);
        vm.prank(stranger);
        vm.expectRevert(IGaugeBounty.NotAgent.selector);
        D.b.recognizeKill(D.id);
        vm.prank(address(agent));
        D.b.creditBallot(D.id, dReporter); // same-block arm consumed by nothing
        vm.warp(block.timestamp + 1);
        vm.prank(address(agent));
        D.b.recognizeKill(D.id); // arm is no longer same-block
        assertEq(uint8(D.b.getReport(D.id).phase), _PH_NOAWARD, "stale arm closes without award");
        (uint256 stakeD,) = D.b.claim(D.id);
        assertEq(stakeD, STAKE, "the attempt cost the case, not the bond");
    }

    // ------------------------------------------------------------------ S04

    function test_Rework_IndependentReporterBallots() public {
        _fairnessIndependentAdmission();
        _fairnessMismatchRejection();
        _fairnessNoChargeOnRefusal();
    }

    /// @dev Independent admission: the upstream per-CREATOR proposal-rights
    /// cooldown belongs to the actual creator only. While one creator sits
    /// in its interval, any other beneficiary/creator pair is admitted
    /// immediately; the bounty never reads or enforces a shared interval,
    /// and there is no service keeper, scan bound or one-creation-per-call
    /// cap to arbitrate.
    function _fairnessIndependentAdmission() private {
        (CurveGaugeListerV2 core_, GaugeBounty b) = deployBoundPair();
        address g1 = _list(core_);
        address g2 = _list(core_);
        // reporter creates their own first ballot.
        _seq += 1;
        bytes32 eh1 = keccak256(abi.encode("fairness-evidence", g1, reporter, _seq));
        (bytes32 id1, uint256 pid1) = createBeneficiaryBallot(b, address(core_), g1, reporter, reporter, _seq, eh1);
        _approveStake(b, reporter, 1);
        vm.prank(reporter);
        b.submit(g1, pid1, eh1, _seq);
        assertEq(uint8(b.getReport(id1).phase), _PH_PROPOSED, "first admitted");

        // The SAME creator is now cooling down upstream (12h per creator):
        // the second creation attempt must wait for the interval...
        bytes32 eh2 = keccak256(abi.encode("fairness-evidence", g2, reporter, _seq + 1));
        (bytes32 id2, uint256 pid2) = createBeneficiaryBallot(b, address(core_), g2, reporter, reporter, _seq + 1, eh2);
        _approveStake(b, reporter, 1);
        vm.prank(reporter);
        b.submit(g2, pid2, eh2, _seq + 1);
        assertEq(uint8(b.getReport(id2).phase), _PH_PROPOSED, "second admitted after the creator-side wait");

        // ...while a different beneficiary with a different creator was
        // admitted in the meantime with no shared wait at all.
        address g3 = _list(core_);
        (bytes32 id3,) =
            submitBeneficiaryBallotBy(b, address(core_), g3, stranger, secondReporter, 333, keccak256("indep"));
        assertEq(uint8(b.getReport(id3).phase), _PH_PROPOSED, "independent admission, no shared mutex");
    }

    /// @dev Mismatch rejection: no caller may adopt another beneficiary's
    /// ballot or replay a bound one — every shape is a pre-custody refusal.
    function _fairnessMismatchRejection() private {
        (CurveGaugeListerV2 core_, GaugeBounty b) = deployBoundPair();
        address g1 = _list(core_);
        (bytes32 idA, uint256 pidA) =
            submitBeneficiaryBallot(b, address(core_), g1, reporter, 411, keccak256("own-ballot"));
        assertEq(uint8(b.getReport(idA).phase), _PH_PROPOSED, "A admitted");

        // B cannot submit A's ballot (B's domain hash differs from the
        // stored script: BadVote, before any pull).
        _approveStake(b, secondReporter, 1);
        vm.prank(secondReporter);
        vm.expectRevert(IGaugeBounty.DuplicateProposal.selector);
        b.submit(g1, pidA, keccak256("copy-of-active"), 412);

        // Neither can anyone re-cite the bound proposal under a fresh
        // domain, including the original reporter.
        vm.prank(reporter);
        vm.expectRevert(IGaugeBounty.DuplicateProposal.selector);
        b.submit(g1, pidA, keccak256("fresh-copy"), 413);

        // Exact replay of the accepted domain is DuplicateReport forever.
        vm.prank(reporter);
        vm.expectRevert(IGaugeBounty.DuplicateReport.selector);
        b.submit(g1, pidA, keccak256("own-ballot"), 411);
    }

    /// @dev Refusals charge nothing: balance and liabilities are untouched
    /// across every rejected attempt above-style.
    function _fairnessNoChargeOnRefusal() private {
        (CurveGaugeListerV2 core_, GaugeBounty b) = deployBoundPair();
        address g1 = _list(core_);
        (bytes32 idA, uint256 pidA) =
            submitBeneficiaryBallot(b, address(core_), g1, reporter, 511, keccak256("charged"));
        idA;
        _approveStake(b, secondReporter, 2);
        uint256 funded = crvUSD.balanceOf(secondReporter);
        (uint256 held0,,) = b.accounting();
        vm.prank(secondReporter);
        vm.expectRevert(IGaugeBounty.DuplicateProposal.selector);
        b.submit(g1, pidA, keccak256("copy"), 512);
        assertEq(crvUSD.balanceOf(secondReporter), funded, "refused duplicate charged nothing");
        (uint256 held1,,) = b.accounting();
        assertEq(held1, held0, "no liability from a refused attempt");
    }

    // ------------------------------------------------------------------ S05

    function test_Rework_ConcurrentReportsSingleAward() public {
        // Full lifecycle with an aggressive second reporter everywhere.
        // Concurrent distinct beneficiary-bound reports are ADMITTED (the
        // retired active-slot refused them); exactly one of them ever wins
        // the listing's single award.
        Live memory L = _proposed();
        address r2 = secondReporter;

        // (a) Second reporter on the same gauge: admitted with its OWN
        // ballot and exact second bond; copied-ballot submissions still
        // refuse before any pull.
        uint256 r1Bal = crvUSD.balanceOf(reporter);
        _approveStake(L.b, r2, 3);
        uint256 r2Bal = crvUSD.balanceOf(r2);
        (bytes32 idB2, uint256 pidB2) = submitBeneficiaryBallot(
            L.b, address(L.core_), L.gauge, r2, 812, keccak256(abi.encode("concurrent", L.gauge))
        );
        assertEq(crvUSD.balanceOf(r2), r2Bal, "concurrent second bond is exact");
        vm.prank(r2);
        vm.expectRevert(IGaugeBounty.DuplicateProposal.selector);
        L.b.submit(L.gauge, pidB2, keccak256(abi.encode("copy", 1)), 813);
        vm.prank(reporter);
        vm.expectRevert(IGaugeBounty.DuplicateProposal.selector);
        L.b.submit(L.gauge, L.voteId, keccak256(abi.encode("copy", 2)), _seq);
        assertEq(crvUSD.balanceOf(r2), r2Bal, "no charge on refused submit");
        assertEq(crvUSD.balanceOf(reporter), r1Bal, "one charge total per reporter");

        // (b) Recognize (A first), then B's own ballot executes: the
        // different recorded winner closes B locally; callback/credit
        // replays before claiming stay inert.
        // Cast both ballots before advancing the shared clock. The second
        // ballot is then executed at the same vote boundary after A latches
        // the listing winner.
        if (_whaleFunded == 0) {
            giveVePower(_whale, 50_000_000e18);
            _whaleFunded = 1;
        }
        vm.prank(_whale);
        voting.vote(pidB2, true);
        _canonicalKill(L);
        assertEq(uint8(L.b.getReport(idB2).phase), _PH_PROPOSED, "B pending until its own turn");
        unkillGaugeViaRoute(L.gauge); // R remains positive: latch is the gate
        vm.prank(stranger);
        voting.executeVote(pidB2);
        assertEq(uint8(L.b.getReport(idB2).phase), _PH_NOAWARD, "B cannot displace the latched winner");
        vm.prank(address(agent));
        L.b.recognizeKill(L.id); // replay: recognized is never erased
        assertEq(uint8(L.b.getReport(L.id).phase), _PH_RECOGNIZED, "replay inert");
        crvUSD.mint(address(L.b), FEE / 2);
        vm.prank(stranger);
        assertEq(L.core_.confiscate(L.gauge), FEE, "settle once");
        (, uint256 credits1,) = L.b.accounting();
        assertEq(credits1, FEE / 2, "credited once");
        vm.prank(stranger);
        vm.expectRevert(IGaugeBounty.NotLister.selector);
        L.b.creditReward(L.id, FEE / 2);
        vm.prank(stranger);
        assertEq(L.core_.confiscate(L.gauge), 0, "second seizure adds nothing");
        (, uint256 credits2,) = L.b.accounting();
        assertEq(credits2, FEE / 2, "no double credit");

        // (c) The refund-after-terminal submit path, B's loser refund and
        // A's single combined claim.
        vm.prank(r2);
        vm.expectRevert(IGaugeBounty.IneligibleGauge.selector);
        L.b.submit(L.gauge, 0, keccak256(abi.encode("after", 1)), 814);
        assertEq(crvUSD.balanceOf(r2), r2Bal, "terminal listing cannot reopen");
        (uint256 stakeB2, uint256 rewB2) = L.b.claim(idB2);
        assertEq(stakeB2, STAKE, "loser bond refunds, no invented reward");
        assertEq(rewB2, 0, "loser earns nothing");
        (uint256 stakeP, uint256 rewardP) = L.b.claim(L.id);
        assertEq(stakeP + rewardP, STAKE + FEE / 2, "one bond + one half");
        (uint256 stake2, uint256 reward2) = L.b.claim(L.id);
        assertEq(stake2 + reward2, 0, "repeat claim pays nothing");
        (uint256 held3,,) = L.b.accounting();
        assertEq(held3, 0, "liabilities drained exactly once");

        // (d) Unkill between recognition and seizure cannot produce a
        // spurious second allocation, and the later honest seizure pays the
        // single entitlement.
        Live memory M = _proposed();
        _canonicalKill(M);
        unkillGaugeViaRoute(M.gauge);
        vm.prank(stranger);
        uint256 seized = M.core_.confiscate(M.gauge);
        (, uint256 creditsM,) = M.b.accounting();
        assertEq(creditsM, 0, "false flag forbids seizure and credit");
        seized;
        killGaugeViaRoute(M.gauge);
        vm.prank(stranger);
        assertEq(M.core_.confiscate(M.gauge), FEE, "honest re-kill settles");
        (, uint256 creditsM2,) = M.b.accounting();
        assertEq(creditsM2, FEE / 2, "exactly one half, never two");

        // (e) Self-report/collusion shape: payer == reporter is accepted;
        // identity equality is never an eligibility criterion.
        Live memory S = _proposed();
        S.b.lister();
        address colluder = actor("payerReporter");
        (address pc, address gc,) = deployGovernanceGauge();
        crvUSD.mint(colluder, FEE + STAKE);
        approveCrvUsd(colluder, address(S.core_), FEE);
        vm.prank(colluder);
        S.core_.listGauge(pc, gc, 0, lastSlot);
        _approveStake(S.b, colluder, 1);
        (bytes32 idS, uint256 pidS) =
            submitBeneficiaryBallot(S.b, address(S.core_), gc, colluder, 815, keccak256("self-report"));
        assertEq(uint8(S.b.getReport(idS).phase), _PH_PROPOSED, "self-report accepted");
        Live memory SL = Live({core_: S.core_, b: S.b, gauge: gc, id: idS, voteId: pidS});
        _canonicalKill(SL);
        crvUSD.mint(address(SL.b), FEE / 2);
        vm.prank(stranger);
        SL.core_.confiscate(gc);
        uint256 cBal = crvUSD.balanceOf(colluder);
        (uint256 sP, uint256 rP) = SL.b.claim(idS);
        assertEq(sP + rP, STAKE + FEE / 2, "colluder paid their own single entitlement");
        assertEq(crvUSD.balanceOf(colluder) - cBal, sP + rP, "to the stored reporter only");
    }

    // ------------------------------------------------------------------ S06

    /// @dev Restore the SHARED mocks to honest between rows: fault state
    /// left by one row must not silently contaminate the next.
    function _resetDeps() internal {
        voting.setNewVoteFault(0);
        voting.setGetVoteFault(0);
        escrow.setCheckerBlock(false);
        fd.setCanCheckpoint(true);
        fd.setCheckpointRevert(false);
        fd.setLastTokenTime(block.timestamp - 86_401); // honest cursor, clear of the checkpoint interval
    }

    function test_Thin_AttackRefundExhaustiveness() public {
        // Every §3.3 ending returns the full 1,000 through the healthy token
        // path with hostile non-token dependencies, and only the explicit
        // owner forfeit ever removes a bond. One cell per row.
        _row1RecognizedThenHostile();
        _row2ExhaustedNoAward();
        _row3RejectedBallot();
        _row4NonWinningLocalRefund();
        _row5UnexecutedTimeout();
        _row6EmergencyBeforeAttribution();
        _row7CallbackNoAward();
        _row8ReplacementAndLateExecution();
        _row9RefundWhileFdStale();
        _row10FailedPaymentRollsBackAndRetries();
        _onlyForfeitRemovesBond();
    }

    function _claimBondOnce(Live memory L, string memory row) internal {
        address rep = L.b.getReport(L.id).reporter;
        uint256 before = crvUSD.balanceOf(rep);
        (uint256 stake, uint256 reward) = L.b.claim(L.id);
        assertEq(stake, STAKE, row);
        assertEq(reward, 0, row);
        assertEq(crvUSD.balanceOf(rep) - before, STAKE, row);
        (uint256 s2, uint256 r2) = L.b.claim(L.id);
        assertEq(s2 + r2, 0, "no repeat payout");
    }

    function _row1RecognizedThenHostile() internal {
        _resetDeps();
        Live memory L = _proposed();
        _canonicalKill(L);
        _hostileDeps(L);
        vm.prank(daoOwner);
        L.core_.setPaused(true);
        // Bond is refundable at recognition without any external read.
        _claimBondOnce(L, "row1 recognized refund");
    }

    function _row2ExhaustedNoAward() internal {
        _resetDeps();
        Live memory L = _proposed();
        // Ballot voted while still OPEN, then the escrow is exhausted.
        _tallyPass(L);
        uint256 guard = 0;
        while (L.core_.getListing(L.gauge).remaining != 0 && guard++ < 60) {
            vm.warp(block.timestamp + 4 * WEEK);
            vm.prank(stranger);
            L.core_.checkpoint(L.gauge);
        }
        assertTrue(guard < 60, "drained");
        uint256 when = L.b.getReport(L.id).voteEnd;
        if (block.timestamp < when) {
            vm.warp(when);
        }
        vm.prank(stranger);
        voting.executeVote(L.voteId);
        // Whether the kill observed an award or an exhausted listing, the
        // ending is terminal and the full bond returns; no reward is invented.
        uint8 ph = uint8(L.b.getReport(L.id).phase);
        assertTrue(ph == _PH_NOAWARD || ph == _PH_RECOGNIZED || ph == _PH_REWARDED, "closed");
        if (ph == _PH_RECOGNIZED) {
            vm.prank(stranger);
            L.b.resolve(L.id); // observed zero allocation closes the entitlement
        }
        _hostileDeps(L);
        (uint256 stake,) = L.b.claim(L.id);
        assertEq(stake, STAKE, "row2 full bond");
        assertEq(L.b.getReport(L.id).rewardCredit, 0, "no reward invented");
    }

    function _row3RejectedBallot() internal {
        _resetDeps();
        Live memory L = _proposed();
        if (_whaleFunded == 0) {
            giveVePower(_whale, 50_000_000e18);
            _whaleFunded = 1;
        }
        vm.prank(_whale);
        voting.vote(L.voteId, false); // genuine losing ballot
        vm.warp(L.b.getReport(L.id).voteEnd);
        vm.prank(stranger);
        assertTrue(L.b.resolve(L.id), "rejected closes");
        assertEq(uint8(L.b.getReport(L.id).phase), _PH_REJECTED, "Rejected");
        _hostileDeps(L);
        vm.prank(stranger);
        assertFalse(L.b.resolve(L.id), "terminal resolve is a no-op");
        _claimBondOnce(L, "row3 losing ballot refunds");
    }

    function _row4NonWinningLocalRefund() internal {
        // Replaces the retired never-created row (plan §7 S06): a NONWINNING
        // concurrent report refunds immediately and locally — no dependency
        // reads, no need to execute its own ballot or wait for any deadline.
        _resetDeps();
        Live memory L = _proposed();
        (bytes32 id2,) = submitBeneficiaryBallot(
            L.b, address(L.core_), L.gauge, secondReporter, _seq + 7, keccak256(abi.encode("loser", L.gauge))
        );
        _canonicalKill(L); // A wins the listing
        // bountyreworkfix C3(c): not merely paused-but-readable — the whole
        // lister/owner observation surface is INVALID (every call returns a
        // malformed word: getListing fails the shape check, listingId and
        // owner read garbage) on top of the hostile Voting/flag/FD set. B's
        // claim must still pay purely locally.
        _hostileDeps(L);
        vm.prank(daoOwner);
        L.core_.setPaused(true);
        _breakLister(L.core_, false);
        uint256 before = crvUSD.balanceOf(secondReporter);
        (uint256 stake,) = L.b.claim(id2);
        assertEq(stake, STAKE, "row4 local nonwinning refund pays");
        assertEq(crvUSD.balanceOf(secondReporter) - before, STAKE, "exact bond, fixed recipient");
        assertEq(uint8(L.b.getReport(id2).phase), _PH_NOAWARD, "closed by the recorded winner");
    }

    function _row5UnexecutedTimeout() internal {
        _resetDeps();
        Live memory L = _proposed();
        _tallyPass(L); // passed but never executed
        vm.warp(L.b.getReport(L.id).executeBy + 1);
        // bountyreworkfix C3(c): the lister AND owner observations are truly
        // UNAVAILABLE here (the lister runtime reverts every read, including
        // getListing/listingId/owner), not paused-but-readable. The local
        // expiry refund must not need them.
        _hostileDeps(L);
        vm.prank(daoOwner);
        L.core_.setPaused(true);
        _breakLister(L.core_, true);
        _claimBondOnce(L, "row5 executeBy+1 local expiry pays");
        assertEq(uint8(L.b.getReport(L.id).phase), _PH_EXPIRED, "no resurrection");
    }

    function _row6EmergencyBeforeAttribution() internal {
        _resetDeps();
        Live memory L = _proposed();
        // A bare emergency kill lands before any attribution attempt.
        vm.prank(emergencySafe);
        killProxy.set_killed(L.gauge);
        require(GovernanceGauge(L.gauge).is_killed(), "emergency killed");
        // The real script then runs: prepare observes the flag ALREADY true
        // (pre-kill expectation fails) -> the case closes without award.
        _tallyPass(L);
        vm.warp(L.b.getReport(L.id).voteEnd);
        vm.prank(stranger);
        voting.executeVote(L.voteId);
        assertEq(uint8(L.b.getReport(L.id).phase), _PH_NOAWARD, "unrelated kill gives no award");
        _hostileDeps(L);
        _claimBondOnce(L, "row6 emergency-before closes with full bond");
    }

    function _row7CallbackNoAward() internal {
        _resetDeps();
        Live memory L = _proposed();
        // Bound-record mismatch: the recorded script is tampered, so the
        // callback's observation refuses to arm/recognize and closes the
        // case without award; the bond stays fully refundable. (The stale
        // arm and consumed-attempt variants are the G07/G04 cells.)
        // Bounded read failure on the flag observation: prepare's
        // all-true-chain cannot complete, the callback closes the case
        // without award, yet the middle entry still delivers the kill.
        GovernanceGauge(L.gauge).setFlagFault(2); // malformed 31-byte is_killed return
        _tallyPass(L);
        vm.warp(L.b.getReport(L.id).voteEnd);
        vm.prank(stranger);
        voting.executeVote(L.voteId);
        assertEq(uint8(L.b.getReport(L.id).phase), _PH_NOAWARD, "failed bounded read -> NoAward");
        GovernanceGauge(L.gauge).setFlagFault(0);
        assertTrue(GovernanceGauge(L.gauge).is_killed(), "the kill itself landed (middle call unaffected)");
        assertEq(L.b.getReport(L.id).rewardCredit, 0, "no award invented");
        _hostileDeps(L);
        _claimBondOnce(L, "row7 callback no-award refunds");
    }

    function _row8ReplacementAndLateExecution() internal {
        // FORWARD-ONLY timestamps: the old report never executes, locally
        // expires and refunds. The old ballot executing LATE may kill but
        // cannot earn, resurrect its case or recreate liability; its
        // protective middle kill remains the disclosed residual timing
        // exposure that can pre-empt another unrecognized reporter.
        // bountyreworkfix C3(a): the replacement report is created a week
        // later (still forward-only) so at the preemption instant its OWN
        // execution window is strictly open — the NoAward can then only be
        // attributed to the stale ballot's late protective kill, not to the
        // replacement being late too.
        _resetDeps();
        Live memory L = _proposed();
        _tallyPass(L); // the old YES ballot is cast while it is still open
        vm.warp(block.timestamp + 3 days); // forward-only spacing for the replacement
        _approveStake(L.b, secondReporter, 1);
        (bytes32 id2, uint256 pid2) = submitBeneficiaryBallot(
            L.b, address(L.core_), L.gauge, secondReporter, _seq + 9, keccak256(abi.encode("replace", L.gauge))
        );
        assertEq(uint8(L.b.getReport(id2).phase), _PH_PROPOSED, "concurrent second report admitted");
        // Vote B while its ballot is open; defer its execution until after the
        // old report has expired and its late callback has run.
        if (_whaleFunded == 0) {
            giveVePower(_whale, 50_000_000e18);
            _whaleFunded = 1;
        }
        vm.prank(_whale);
        voting.vote(pid2, true);
        ReportView memory rvB = L.b.getReport(id2);
        vm.warp(L.b.getReport(L.id).executeBy + 1);
        // Isolation preconditions of the preemption witness: the OLD case is
        // past its own window while the NEW case is strictly INSIDE its own
        // window and its ballot is executable.
        assertTrue(block.timestamp > L.b.getReport(L.id).executeBy, "old case is past its own executeBy");
        assertTrue(block.timestamp >= rvB.voteEnd, "replacement is past its ballot end");
        assertTrue(block.timestamp < rvB.executeBy, "replacement is inside its OWN execution window");
        assertTrue(voting.canExecute(pid2), "replacement ballot is closed and executable");
        _claimBondOnce(L, "row8 old reporter keeps the fixed refund");
        // Late upstream execution of the OLD ballot (real script path; the
        // ballot was voted before its own close, execution is unlimited).
        vm.prank(stranger);
        voting.executeVote(L.voteId);
        ReportView memory old2 = L.b.getReport(L.id);
        assertEq(uint8(old2.phase), _PH_EXPIRED, "old stays Expired");
        assertEq(old2.rewardCredit, 0, "late execution earns nothing");
        assertTrue(GovernanceGauge(L.gauge).is_killed(), "the late protective kill stands");
        (bytes32 latchedBefore,,) = L.b.rewardTerms(L.gauge);
        assertEq(latchedBefore, bytes32(0), "old callbacks cannot latch a winner");
        // The old callbacks cannot touch the new report either; the still
        // true flag from the late protective kill makes B's execution land
        // as NoAward without creating a second liability. B is timely, so
        // this NoAward is the preemption, not an expiry.
        vm.prank(stranger);
        voting.executeVote(pid2);
        assertEq(uint8(L.b.getReport(id2).phase), _PH_NOAWARD, "late kill may pre-empt, never pay");
        (uint256 stake2,) = L.b.claim(id2);
        assertEq(stake2, STAKE, "the pre-empted reporter is still fully refunded");
        (uint256 held,,) = L.b.accounting();
        assertEq(held, 0, "no recreated liability");
        (bytes32 latchedAfter,,) = L.b.rewardTerms(L.gauge);
        assertEq(latchedAfter, bytes32(0), "no winner latch survives the preempted exchange");
    }

    function _row9RefundWhileFdStale() internal {
        _resetDeps();
        Live memory L = _proposed();
        _canonicalKill(L);
        fd.setLastTokenTime(block.timestamp - 41 * WEEK); // far beyond the horizon
        fd.setCheckpointRevert(true);
        // The recognized bond does NOT wait for FD settlement.
        _claimBondOnce(L, "row9 refund survives a stale/committed FD");
        fd.setCheckpointRevert(false);
        fd.setCanCheckpoint(true);
        fd.setLastTokenTime(block.timestamp - 86_401); // safe AND past the 1-day checkpoint interval
        // A valid recognized reward still needs safe funding: settle late.
        crvUSD.mint(address(L.b), FEE / 2);
        vm.prank(stranger);
        L.core_.confiscate(L.gauge);
        uint256 before = crvUSD.balanceOf(reporter);
        (, uint256 reward) = L.b.claim(L.id);
        assertEq(reward, FEE / 2, "delayed reward pays when funded");
        assertEq(crvUSD.balanceOf(reporter) - before, FEE / 2, "reward exact");
    }

    function _row10FailedPaymentRollsBackAndRetries() internal {
        _resetDeps();
        // A credited case whose payout would fail must revert WHOLESALE and
        // keep credit/state intact for a later funded retry.
        Live memory M = _proposed();
        _canonicalKill(M);
        vm.prank(stranger);
        M.core_.confiscate(M.gauge); // credits FEE/2; bounty holds only STAKE
        (uint256 heldM,,) = M.b.accounting();
        assertEq(heldM, STAKE, "only the bond is held");

        // The token refuses to move: the whole claim reverts and NOTHING
        // changes (debits, phase, ledger), then the same claim succeeds.
        uint256 repBefore = crvUSD.balanceOf(reporter);
        (uint256 h0, uint256 c0, uint256 d0) = M.b.accounting();
        crvUSD.setTransferBehavior(0, true, false); // transfers return false
        vm.expectRevert();
        M.b.claim(M.id);
        crvUSD.setTransferBehavior(0, false, false);
        (uint256 h1, uint256 c1, uint256 d1) = M.b.accounting();
        bytesEq(abi.encode(h1, c1, d1), abi.encode(h0, c0, d0), "ledger untouched by failed payment");
        assertEq(uint8(M.b.getReport(M.id).phase), _PH_REWARDED, "phase untouched by the revert");
        assertEq(crvUSD.balanceOf(reporter), repBefore, "reporter untouched");

        // The same claim on the healthy token pays both legs, exactly once.
        (uint256 sf, uint256 rf) = M.b.claim(M.id);
        assertEq(sf + rf, STAKE + FEE / 2, "retry pays after the fault clears");
        assertEq(crvUSD.balanceOf(reporter) - repBefore, STAKE + FEE / 2, "exact money moved once");
    }

    function _onlyForfeitRemovesBond() internal {
        _resetDeps();
        // The single exception: an explicit owner mark is the ONLY accepted
        // report ending that removes the bond; every hostile dependency,
        // replay, refuse and timeout above left it recoverable.
        Live memory L = _proposed();
        _hostileDeps(L);
        vm.prank(daoOwner);
        assertTrue(L.b.markFrivolous(L.id), "forfeit works even under the outage");
        (uint256 stake,) = L.b.claim(L.id);
        assertEq(stake, 0, "forfeited bond is not claimable");
        (,, uint256 dao) = L.b.accounting();
        assertEq(dao, STAKE, "fixed FD liability is the sole destination");
        // And the liability is real: flushDao moves exactly it to the FD.
        fd.setCanCheckpoint(true); // the row's own outage is over for the flush
        _spaceFd(); // past the FD's checkpoint interval (a settlement may
        // have refreshed the cursor earlier in this shared-mock test)
        crvUSD.mint(address(L.b), STAKE);
        uint256 fdBefore = crvUSD.balanceOf(address(fd));
        vm.prank(stranger);
        assertEq(L.b.flushDao(STAKE), STAKE, "flush pays the forfeited stake");
        (,, uint256 dao2) = L.b.accounting();
        assertEq(dao2, 0, "liability settled");
        assertEq(crvUSD.balanceOf(address(fd)) - fdBefore, STAKE, "FD received exactly the stake");
    }

    function _spaceFd() internal {
        if (block.timestamp <= fd.last_token_time() + 86_400) {
            fd.setLastTokenTime(block.timestamp - 86_401);
        }
    }
}

/// @dev bountyreworkfix C3(c) fixture runtime: answers EVERY call with one
/// malformed 32-byte word. Etched over a row's own freshly deployed V2 it
/// makes the lister/getListing/listingId and owner observations genuinely
/// INVALID data (wrong shape for getListing, garbage identities otherwise),
/// which "paused" never does. Test-local fault model, not a product path.
contract ListerGarbageRuntime {
    fallback(bytes calldata) external returns (bytes memory) {
        return abi.encode(uint256(0xBADB0DE));
    }
}
