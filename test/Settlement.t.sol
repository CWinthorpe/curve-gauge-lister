// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {TestBase, Vm} from "./TestBase.sol";
import {CurveGaugeLister} from "../contracts/CurveGaugeLister.sol";
import {IERC20Minimal} from "../contracts/interfaces/IERC20Minimal.sol";
import {ICurveGauge} from "../contracts/interfaces/ICurveGauge.sol";
import {MockERC20} from "../contracts/mocks/MockERC20.sol";
import {MockPool} from "../contracts/mocks/MockPool.sol";
import {MockGauge} from "../contracts/mocks/MockGauge.sol";
import {MockCurveRegistry} from "../contracts/mocks/MockCurveRegistry.sol";
import {MockListingController} from "../contracts/mocks/MockListingController.sol";
import {MockFeeDistributor} from "../contracts/mocks/MockFeeDistributor.sol";
import {MockIncentivePlatform} from "../contracts/mocks/MockIncentivePlatform.sol";
import {AlwaysTrueTrustedValidator} from "./mocks/TrustedFactoryMocks.sol";

/// @notice Test-only MockIncentivePlatform subclass used as the CONTRACT OWNER
/// of a dedicated lister for the review1 finding-4 reentrancy fixture: it adds
/// only helpers to execute the same owner-gated calls outside settlement, so
/// the inside-settlement failures are demonstrably non-vacuous. The plan-
/// prescribed base mock API is untouched.
contract ContractOwnerAdapter is MockIncentivePlatform {
    bool public lastCallOk;

    constructor(address token_) MockIncentivePlatform(token_) {}

    /// @notice Execute an arbitrary call as this contract (the test lister's
    /// owner) outside any deposit.
    function fireCallback(address target, bytes calldata data) external returns (bool ok) {
        (ok,) = target.call(data);
        lastCallOk = ok;
    }

    /// @notice Let this contract, as a token holder, set its own approval.
    function approveToken(address token_, address spender, uint256 amount) external {
        IERC20Minimal(token_).approve(spender, amount);
    }
}

/// @notice Test-only fixture that executes the settlement-relevant state
/// change from inside a platform deposit callback. `killNow` flips the gauge's
/// admin-side killed flag (the A2 kill oracle — the mock setter is
/// unrestricted and models the authorized gauge-admin `set_killed(True)` path,
/// never a weight change). `zeroWeightNow` performs the retired weight-only
/// operation through the real controller DAO fixture identity, as an explicit
/// negative probe: it must never affect custody. Never a product dependency.
contract DaoKillCallback is TestBase {
    MockListingController private _ctl;
    address private _dao;

    function arm(address ctl_, address dao_) external {
        _ctl = MockListingController(ctl_);
        _dao = dao_;
    }

    function killNow(address gauge) external {
        MockGauge(gauge).setKilled(true);
    }

    function zeroWeightNow(address gauge) external {
        vm.prank(_dao);
        _ctl.change_gauge_weight(gauge, 0);
    }
}

/// @notice Test-only ABI-fault gauge fixture for exec7 (E7.2): behaves like a
/// healthy MockGauge until armed, then `is_killed()` returns a NONCANONICAL
/// 32-byte word (0x2a…, neither 0 nor 1) — malformed boolean returndata that
/// cannot decode. The product must treat it as a hard failure: neither a kill
/// nor permission to release.
contract GarbageFlagGauge is ICurveGauge {
    address private immutable _lpToken;
    bool private _killed;
    bool private _garbage;

    constructor(address lpToken_) {
        require(lpToken_ != address(0), "zero lp");
        _lpToken = lpToken_;
    }

    function lp_token() external view returns (address) {
        return _lpToken;
    }

    function is_killed() external view returns (bool) {
        if (_garbage) {
            assembly {
                mstore(0, 0x2a)
                return(0, 32)
            }
        }
        return _killed;
    }

    function setKilled(bool killed) external {
        _killed = killed;
    }

    /// @notice Arm/disable the malformed-return fault (never changes the
    /// stored flag or LP identity).
    function setGarbage(bool enabled) external {
        _garbage = enabled;
    }
}

/// @notice Epochs, adapters, FeeDistributor mechanics and adversarial flows
/// (plan §9 R2, R3 rows plus reentrancy, token-safety and conservation fuzz).
contract SettlementTest is TestBase {
    uint256 internal constant FEE = 10_000e18;
    uint256 internal constant QUARTER = 2_500e18;
    uint256 internal constant WEEK = 604800;
    uint256 internal constant T0 = 1794441600; // Thu 2026-11-12 00:00 UTC

    MockERC20 internal token;
    MockCurveRegistry internal registry;
    MockListingController internal controller;
    MockFeeDistributor internal fd;
    MockIncentivePlatform internal votium;
    MockIncentivePlatform internal voteMarket;
    CurveGaugeLister internal lister;

    address internal daoOwner;
    address internal controllerDao;
    address internal fdAdmin;
    address internal payer;
    address internal stranger;

    function setUp() public {
        daoOwner = actor("daoMultisig");
        controllerDao = actor("controllerDao");
        fdAdmin = actor("fdAdmin");
        payer = actor("payer");
        stranger = actor("stranger");

        token = new MockERC20(18);
        registry = new MockCurveRegistry();
        controller = new MockListingController(controllerDao, int128(2));
        vm.warp(T0);
        fd = new MockFeeDistributor(address(token), fdAdmin, T0);
        votium = new MockIncentivePlatform(address(token));
        voteMarket = new MockIncentivePlatform(address(token));

        // Explicit chain 1 before ordinary deployment: the amended
        // constructor checks WrongChain FIRST (V1ALIGN §2.1).
        vm.chainId(1);
        lister = new CurveGaugeLister(
            daoOwner,
            address(token),
            address(controller),
            address(fd),
            CurveGaugeLister.AdmissionConfig(address(registry), 8),
            CurveGaugeLister.PlatformConfig(address(votium), address(voteMarket), 5000),
            address(new AlwaysTrueTrustedValidator())
        );

        vm.prank(controllerDao);
        controller.setLister(address(lister));
        votium.setLister(address(lister));
        voteMarket.setLister(address(lister));

        // V1ALIGN §1.3: the fresh core starts paused. Observe that shipped
        // state, then the owner unpauses after binding so every retained
        // downstream obligation runs on its original path.
        assertTrue(lister.paused(), "core starts paused");
        vm.prank(daoOwner);
        lister.setPaused(false);

        token.mint(payer, 40 * FEE);
        vm.startPrank(payer);
        token.approve(address(lister), type(uint256).max);
        vm.stopPrank();
    }

    // ---------------------------------------------------------------
    // fixtures
    // ---------------------------------------------------------------

    function _coins(address a, address b) internal pure returns (address[8] memory c) {
        c[0] = a;
        c[1] = b;
    }

    function deployAuthenticatedPool(uint256 handlerId, uint256 gaugeIndex)
        internal
        returns (address pool, address gauge, address lp)
    {
        lp = address(new MockERC20(18));
        pool = address(new MockPool());
        gauge = address(new MockGauge(lp));
        registry.setPool(pool, handlerId, lp, _coins(address(new MockERC20(18)), address(new MockERC20(18))), 2);
        registry.setGauge(pool, handlerId, gaugeIndex, gauge, 0);
    }

    /// @dev Paid listing of a fresh authenticated gauge at the current time.
    function listFresh(uint256 handlerId, uint256 gaugeIndex) internal returns (address pool, address gauge) {
        (pool, gauge,) = deployAuthenticatedPool(handlerId, gaugeIndex);
        vm.prank(payer);
        lister.listGauge(pool, gauge, gaugeIndex, handlerId);
    }

    /// @dev Kill the gauge for settlement via its admin-side flag (A2): flip
    /// MockGauge's independent killed switch. Controller weight is never read
    /// or touched on the kill path.
    function killGauge(address gauge) internal {
        MockGauge(gauge).setKilled(true);
    }

    // ---------------------------------------------------------------
    // R2 — epochs, drip, catch-up, platforms
    // ---------------------------------------------------------------

    function test_ThursdayBoundaryAndOneSecondEdges() public {
        // (a) listing exactly AT the Thursday boundary belongs to the NEW
        // epoch: full week wait.
        (address poolA, address gaugeA,) = deployAuthenticatedPool(0, 0);
        vm.warp(T0);
        listPaidAt(poolA, gaugeA, 0, 0);
        assertEq(lister.getListing(gaugeA).listingEpoch, T0, "L at boundary");
        vm.warp(T0 + WEEK - 1);
        (uint256 r, uint256 c) = lister.checkpoint(gaugeA);
        assertEq(r + c, 0, "maturity-1 pays nothing");
        vm.warp(T0 + WEEK);
        (r, c) = lister.checkpoint(gaugeA);
        assertEq(r, QUARTER, "maturity funds");
        assertEq(c, 0, "no confiscation");
        vm.warp(T0 + WEEK + 1);
        (r, c) = lister.checkpoint(gaugeA);
        assertEq(r + c, 0, "maturity+1 already paid");

        // (b) listing one second BEFORE the boundary is in the previous epoch
        // and can release one second later.
        _tMinusOneListingEdges();

        // (c) review1 finding 7: fresh listing one second AFTER the boundary
        // floors into the NEW epoch: full week wait, same edges as (a).
        _tPlusOneFreshListingEdges();
    }

    function _tMinusOneListingEdges() internal {
        (address poolB, address gaugeB,) = deployAuthenticatedPool(1, 0);
        vm.warp(T0 - 1);
        listPaidAt(poolB, gaugeB, 0, 1);
        assertEq(lister.getListing(gaugeB).listingEpoch, T0 - WEEK, "L floored to prior Thursday");
        (uint256 rB, uint256 cB) = lister.checkpoint(gaugeB);
        assertEq(rB + cB, 0, "T-1 listing: nothing at maturity-1");
        assertEq(lister.getListing(gaugeB).remaining, FEE, "T-1 listing: escrow intact at maturity-1");
        (uint256 aB0, uint256 eB0, bytes32 rB0) = votium.getDeposit(gaugeB, T0);
        assertEq(aB0 + eB0 + uint256(rB0), 0, "T-1 listing: no votium receipts at maturity-1");
        (uint256 aB1, uint256 eB1, bytes32 rB1) = voteMarket.getDeposit(gaugeB, T0);
        assertEq(aB1 + eB1 + uint256(rB1), 0, "T-1 listing: no voteMarket receipts at maturity-1");
        vm.warp(T0);
        (rB, cB) = lister.checkpoint(gaugeB);
        assertEq(rB, QUARTER, "released one second after listing at boundary");
        assertEq(cB, 0, "no confiscation");
        assertEq(lister.getListing(gaugeB).epochsReleased, 1, "T-1 listing: exactly one quarter at maturity");
        vm.warp(T0 + 1);
        (rB, cB) = lister.checkpoint(gaugeB);
        assertEq(rB + cB, 0, "T-1 listing: no duplicate at maturity+1");
    }

    function _tPlusOneFreshListingEdges() internal {
        (address poolC2, address gaugeC2,) = deployAuthenticatedPool(2, 0);
        vm.warp(T0 + 1);
        listPaidAt(poolC2, gaugeC2, 0, 2);
        assertEq(lister.getListing(gaugeC2).listingEpoch, T0, "T+1 listing floors to the new epoch");
        vm.warp(T0 + WEEK - 1);
        (uint256 rC, uint256 cC) = lister.checkpoint(gaugeC2);
        assertEq(rC + cC, 0, "T+1 listing: nothing at maturity-1");
        assertEq(lister.getListing(gaugeC2).remaining, FEE, "T+1 listing: escrow intact at maturity-1");
        assertEq(lister.epochsElapsed(gaugeC2), 0, "T+1 listing: zero elapsed at maturity-1");
        vm.warp(T0 + WEEK);
        (rC, cC) = lister.checkpoint(gaugeC2);
        assertEq(rC, QUARTER, "T+1 listing: one quarter at maturity");
        assertEq(cC, 0, "T+1 listing: no confiscation");
        assertEq(lister.getListing(gaugeC2).epochsReleased, 1, "T+1 listing: single counter bump at maturity");
        (uint256 amtC2V, uint256 execC2V, bytes32 recC2V) = votium.getDeposit(gaugeC2, T0 + WEEK);
        assertEq(amtC2V, QUARTER / 2, "T+1 listing: votium receipt face at maturity");
        assertEq(execC2V, T0 + WEEK, "T+1 listing: execution epoch at maturity");
        assertTrue(recC2V != bytes32(0), "T+1 listing: votium receipt funded");
        vm.warp(T0 + WEEK + 1);
        (rC, cC) = lister.checkpoint(gaugeC2);
        assertEq(rC + cC, 0, "T+1 listing: no duplicate release at maturity+1");
        assertEq(lister.getListing(gaugeC2).epochsReleased, 1, "T+1 listing: counter still one");
    }

    function listPaidAt(address pool, address gauge, uint256 gaugeIndex, uint256 handlerId) internal {
        vm.prank(payer);
        lister.listGauge(pool, gauge, gaugeIndex, handlerId);
    }

    function test_FourEpochQuarterRelease() public {
        (, address gauge) = listFresh(0, 0);
        for (uint256 k = 1; k <= 4; ++k) {
            vm.warp(T0 + k * WEEK);
            if (k == 1) {
                vm.expectEmit(true, true, true, true);
                emit QuarterReleased(gauge, T0 + WEEK, QUARTER, FEE - QUARTER);
            }
            (uint256 r, uint256 c) = lister.checkpoint(gauge);
            assertEq(r, QUARTER, "one quarter per maturity");
            assertEq(c, 0, "no confiscation");
            CurveGaugeLister.Listing memory rec = lister.getListing(gauge);
            assertEq(rec.released, k * QUARTER, "cumulative released");
            assertEq(rec.remaining, FEE - k * QUARTER, "cumulative remaining");
            assertEq(uint256(rec.epochsReleased), k, "counter");
            assertEq(lister.totalEscrow(), FEE - k * QUARTER, "totalEscrow decays");
            assertEq(token.balanceOf(address(votium)), (k * QUARTER) / 2, "votium cumulative");
            assertEq(token.balanceOf(address(voteMarket)), (k * QUARTER) / 2, "voteMarket cumulative");
            if (k < 4) {
                assertEq(uint8(rec.status), uint8(CurveGaugeLister.Status.Active), "active");
            } else {
                assertEq(uint8(rec.status), uint8(CurveGaugeLister.Status.Exhausted), "exhausted");
                assertEq(rec.remaining, 0, "zero remaining at exhaustion");
            }

            // Identical-timestamp repeat (absorbed from the retired standalone
            // repeat test): zero return and no counter/receipt change.
            (uint256 rRep, uint256 cRep) = lister.checkpoint(gauge);
            assertEq(rRep + cRep, 0, "same-timestamp repeat is idle");
            assertEq(uint256(lister.getListing(gauge).epochsReleased), k, "repeat leaves the counter unchanged");
            assertEq(lister.totalEscrow(), FEE - k * QUARTER, "repeat moves no liability");
        }
        assertEq(lister.getListing(gauge).released, FEE, "2500/5000/7500/10000 vector complete");
        assertEq(votium.depositCount() + voteMarket.depositCount(), 8, "no duplicate receipts on repeats");
    }

    function test_MissedEpochCatchUpIsBoundedAndPreservesMaturityLabels() public {
        (, address gauge) = listFresh(0, 0);

        // Late call in the third week funds quarters 1..3 only.
        vm.warp(T0 + 3 * WEEK);
        (uint256 r, uint256 c) = lister.checkpoint(gauge);
        assertEq(r, 3 * QUARTER, "catch-up funds due quarters");
        assertEq(c, 0, "no confiscation");
        assertEq(lister.getListing(gauge).epochsReleased, 3, "counter");

        // Original maturities preserved in receipts while execution is now.
        for (uint256 k = 1; k <= 3; ++k) {
            (uint256 amt, uint256 exec, bytes32 receipt) = votium.getDeposit(gauge, T0 + k * WEEK);
            assertEq(amt, QUARTER / 2, "votium scheduled amount");
            assertEq(exec, T0 + 3 * WEEK, "execution epoch is the late call");
            assertTrue(exec != T0 + k * WEEK || k == 3, "scheduled differs from execution when late");
            assertTrue(receipt != bytes32(0), "receipt preserved");
            (uint256 amtM,, bytes32 receiptM) = voteMarket.getDeposit(gauge, T0 + k * WEEK);
            assertEq(amtM, QUARTER / 2, "voteMarket scheduled amount");
            assertTrue(receiptM != bytes32(0), "receipt preserved 2");
        }

        // Late call in the fifth week funds the fourth quarter only; no fifth
        // quarter exists.
        vm.warp(T0 + 5 * WEEK);
        (r, c) = lister.checkpoint(gauge);
        assertEq(r, QUARTER, "only the last quarter remains");
        assertEq(uint8(lister.getListing(gauge).status), uint8(CurveGaugeLister.Status.Exhausted), "exhausted");
        assertEq(votium.depositCount(), 4, "bounded at four");
        assertEq(voteMarket.depositCount(), 4, "bounded at four 2");
        (uint256 amt5,, bytes32 rec5) = votium.getDeposit(gauge, T0 + 5 * WEEK);
        assertEq(amt5 + uint256(rec5), 0, "no fifth quarter");
        assertEq(lister.getListing(gauge).released, FEE, "full release");
    }

    function test_PlatformSplitsAndZeroShareRouting() public {
        // Gauge A: default 5000/5000. Gauge B: 0-share votium (live address,
        // must never be called). Gauge C: 10000 to votium (voteMarket zero
        // address allowed). Gauge D: intermediate 3333.
        (, address gaugeA) = listFresh(0, 0);

        vm.prank(daoOwner);
        lister.setPlatformConfig(CurveGaugeLister.PlatformConfig(address(votium), address(voteMarket), 0));
        (, address gaugeB) = listFresh(1, 0);

        vm.prank(daoOwner);
        lister.setPlatformConfig(CurveGaugeLister.PlatformConfig(address(votium), address(0), 10000));
        (, address gaugeC) = listFresh(2, 0);

        vm.prank(daoOwner);
        lister.setPlatformConfig(CurveGaugeLister.PlatformConfig(address(votium), address(voteMarket), 3333));
        (, address gaugeD) = listFresh(3, 0);

        uint256 maturity = T0 + WEEK;
        vm.warp(maturity);

        (uint256 rA,) = lister.checkpoint(gaugeA);
        (uint256 rC,) = lister.checkpoint(gaugeC);
        assertEq(rA, QUARTER, "A funds");
        assertEq(rC, QUARTER, "C funds");
        assertEq(votium.depositCount(), 2, "A and C on votium");
        assertEq(voteMarket.depositCount(), 1, "only A on voteMarket");

        // Zero-share target is provably never called: break it, then settle B.
        votium.setFailureMode(1);
        (uint256 rB,) = lister.checkpoint(gaugeB);
        assertEq(rB, QUARTER, "B settles with votium broken (never called)");
        votium.setFailureMode(0);

        (uint256 rD,) = lister.checkpoint(gaugeD);
        assertEq(rD, QUARTER, "D funds");

        // Exact floors and complements, gross totals per quarter.
        uint256 vExp = (QUARTER * 3333) / 10_000;
        checkDeposit(votium, gaugeD, maturity, vExp);
        checkDeposit(voteMarket, gaugeD, maturity, QUARTER - vExp);
        checkDeposit(votium, gaugeC, maturity, QUARTER);
        checkEmptyDeposit(votium, gaugeB, maturity);
        checkDeposit(voteMarket, gaugeB, maturity, QUARTER);
        checkDeposit(votium, gaugeA, maturity, QUARTER / 2);
        checkDeposit(voteMarket, gaugeA, maturity, QUARTER / 2);

        assertEq(token.balanceOf(address(votium)), QUARTER / 2 + QUARTER + vExp, "votium total");
        assertEq(token.balanceOf(address(voteMarket)), QUARTER / 2 + QUARTER + (QUARTER - vExp), "voteMarket total");
        assertEq(lister.totalEscrow(), 4 * FEE - 4 * QUARTER, "escrow");
    }

    function checkDeposit(MockIncentivePlatform p, address g, uint256 sched, uint256 expAmt) internal view {
        (uint256 amt, uint256 exec, bytes32 receipt) = p.getDeposit(g, sched);
        assertEq(amt, expAmt, "deposit gross");
        assertEq(exec, sched, "on-time execution");
        assertTrue(receipt != bytes32(0), "receipt nonzero");
    }

    function checkEmptyDeposit(MockIncentivePlatform p, address g, uint256 sched) internal view {
        (uint256 amt,, bytes32 receipt) = p.getDeposit(g, sched);
        assertEq(amt + uint256(receipt), 0, "zero-share target never deposited");
    }

    function test_ReceiptMustBeFundedAndAllowanceCleared() public {
        (, address gauge) = listFresh(0, 0);
        uint256 maturity = T0 + WEEK;
        vm.warp(maturity);

        (uint256 r,) = lister.checkpoint(gauge);
        assertEq(r, QUARTER, "normal release");
        (uint256 amtV, uint256 execV, bytes32 receiptV) = votium.getDeposit(gauge, maturity);
        assertEq(amtV, QUARTER / 2, "recorded gross");
        assertEq(execV, maturity, "execution epoch");
        assertTrue(receiptV != bytes32(0), "nonzero receipt");
        assertEq(token.balanceOf(address(votium)), amtV, "receipt backed by balance");
        assertEq(token.balanceOf(address(voteMarket)), amtV, "receipt backed by balance 2");
        assertEq(token.allowance(address(lister), address(votium)), 0, "votium allowance cleared");
        assertEq(token.allowance(address(lister), address(voteMarket)), 0, "voteMarket allowance cleared");

        // Mode 2: receipt without pulling -> whole quarter rolls back.
        votium.setFailureMode(2);
        vm.warp(maturity + WEEK);
        vm.expectRevert();
        lister.checkpoint(gauge);
        assertFaultRollback(gauge, 1);
        // Mode 3: underpull by one unit.
        votium.setFailureMode(3);
        vm.expectRevert();
        lister.checkpoint(gauge);
        assertFaultRollback(gauge, 1);
        // Mode 4: pull then zero receipt.
        votium.setFailureMode(4);
        vm.expectRevert();
        lister.checkpoint(gauge);
        assertFaultRollback(gauge, 1);
        // Unknown modes revert at the setter.
        vm.expectRevert();
        votium.setFailureMode(5);

        votium.setFailureMode(0);
        (uint256 r2,) = lister.checkpoint(gauge);
        assertEq(r2, QUARTER, "retry after faults funds only quarter 2");
        assertEq(votium.depositCount(), 2, "exactly two funded votium deposits");
        assertEq(voteMarket.depositCount(), 2, "exactly two funded voteMarket deposits");
        assertEq(lister.getListing(gauge).epochsReleased, 2, "counter");
    }

    function assertFaultRollback(address gauge, uint256 paidSoFar) internal view {
        CurveGaugeLister.Listing memory rec = lister.getListing(gauge);
        assertEq(uint256(rec.epochsReleased), paidSoFar, "no counter bump on fault");
        assertEq(rec.released, paidSoFar * QUARTER, "no released bump on fault");
        assertEq(rec.remaining, FEE - paidSoFar * QUARTER, "no remaining drain on fault");
        assertEq(lister.totalEscrow(), FEE - paidSoFar * QUARTER, "no escrow change on fault");
        assertEq(token.balanceOf(address(votium)), paidSoFar * QUARTER / 2, "no platform gain on fault");
        assertEq(votium.depositCount(), paidSoFar, "no receipt on fault");
    }

    function test_SecondPlatformFailureRollsBackWholeCheckpoint() public {
        (, address gauge) = listFresh(0, 0);
        // review1 finding 5: VoteMarket starts NORMAL and its own deposit
        // callback flips it to failure mode (1) after its first successful
        // deposit. Two quarters are due at once: quarter one fully funds both
        // platforms, then quarter two's VoteMarket deposit fails, so the
        // ENTIRE call reverts including the completed earlier quarter in the
        // same transaction.
        voteMarket.setReentry(address(voteMarket), abi.encodeCall(MockIncentivePlatform.setFailureMode, (uint8(1))));
        vm.warp(T0 + 2 * WEEK);
        vm.expectRevert();
        lister.checkpoint(gauge);

        assertEq(votium.depositCount(), 0, "first platform receipt rolled back");
        assertEq(voteMarket.depositCount(), 0, "second platform receipts rolled back");
        assertEq(token.balanceOf(address(votium)), 0, "first platform balance rolled back");
        assertEq(token.balanceOf(address(voteMarket)), 0, "second platform balance zero");
        assertEq(token.balanceOf(address(lister)), FEE, "escrow untouched");
        assertEq(lister.totalEscrow(), FEE, "accounting untouched");
        CurveGaugeLister.Listing memory rec = lister.getListing(gauge);
        assertEq(uint256(rec.epochsReleased), 0, "no counter bump");
        assertEq(rec.released, 0, "no released bump");
        assertEq(rec.remaining, FEE, "no remaining drain");
        assertEq(rec.confiscated, 0, "no confiscation");
        assertEq(rec.deposited, FEE, "deposited intact");
        assertEq(uint8(rec.status), uint8(CurveGaugeLister.Status.Active), "still Active");
        assertEq(token.allowance(address(lister), address(votium)), 0, "votium approval rolled back to zero");
        assertEq(token.allowance(address(lister), address(voteMarket)), 0, "voteMarket approval rolled back to zero");
        // The callback's mode flip rolled back with the failed call: no
        // residual failure mode persists (proved by the clean retry below).

        // Successful retry (callback cleared) funds exactly once each.
        voteMarket.setReentry(address(0), "");
        (uint256 r,) = lister.checkpoint(gauge);
        assertEq(r, 2 * QUARTER, "both due quarters fund");
        assertEq(votium.depositCount(), 2, "no double funding on retry");
        assertEq(voteMarket.depositCount(), 2, "no double funding on retry 2");
        assertEq(token.balanceOf(address(votium)), QUARTER, "retry fully funds the earlier quarter");
        assertEq(token.balanceOf(address(voteMarket)), QUARTER, "retry fully funds the earlier quarter 2");
        assertEq(lister.totalEscrow(), FEE - 2 * QUARTER, "escrow after retry");
    }

    // Isolated stack for the mid-catch-up scenarios (storage-backed for
    // stack depth). exec7: the kill flavor now lives in the standalone
    // test_KilledFlagTrueAtMaturityStopsMidCatchUp below (A2: only the gauge
    // flag confiscates); the retired weight-zero flavor is inverted inside
    // test_WeightZeroWithoutKilledFlagDoesNotConfiscate.
    MockListingController internal ctlB_;
    MockFeeDistributor internal fdLive_;
    MockIncentivePlatform internal pv_;
    MockIncentivePlatform internal pm_;
    CurveGaugeLister internal lb_;
    address internal poolK_;
    address internal gaugeK_;

    /// @dev exec7 (E7.2): at least two quarters due in ONE checkpoint; the
    /// FIRST quarter's final positive-share endpoint (VoteMarket in the normal
    /// mixed split) flips the gauge flag true mid-call. Quarter one stands,
    /// the loop stops, the exact remainder goes to the FeeDistributor, and
    /// raw controller weight stays explicitly nonzero throughout.
    function test_KilledFlagTrueAtMaturityStopsMidCatchUp() public {
        ctlB_ = new MockListingController(controllerDao, int128(2));
        fdLive_ = new MockFeeDistributor(address(token), fdAdmin, T0);
        pv_ = new MockIncentivePlatform(address(token));
        pm_ = new MockIncentivePlatform(address(token));
        vm.chainId(1);
        lb_ = new CurveGaugeLister(
            daoOwner,
            address(token),
            address(ctlB_),
            address(fdLive_),
            CurveGaugeLister.AdmissionConfig(address(registry), 8),
            CurveGaugeLister.PlatformConfig(address(pv_), address(pm_), 5000),
            address(new AlwaysTrueTrustedValidator())
        );
        vm.prank(controllerDao);
        ctlB_.setLister(address(lb_));
        pv_.setLister(address(lb_));
        pm_.setLister(address(lb_));
        // Owner unpause after binding (V1ALIGN §1.3 fixture wiring).
        vm.prank(daoOwner);
        lb_.setPaused(false);
        vm.startPrank(payer);
        token.approve(address(lb_), type(uint256).max);
        vm.stopPrank();
        (poolK_, gaugeK_,) = deployAuthenticatedPool(3, 0);
        vm.prank(payer);
        lb_.listGauge(poolK_, gaugeK_, 0, 3);
        uint256 tK = lb_.getListing(gaugeK_).listingEpoch;
        // Explicitly nonzero scheduled weight (admin setup, not a paid seed):
        // the kill must land with raw weight still nonzero.
        vm.prank(controllerDao);
        ctlB_.change_gauge_weight(gaugeK_, 777);
        assertEq(ctlB_.get_gauge_weight(gaugeK_), 777, "precondition: nonzero weight");
        assertFalse(MockGauge(gaugeK_).is_killed(), "precondition: flag false");

        DaoKillCallback killer = new DaoKillCallback();
        killer.arm(address(ctlB_), controllerDao);
        pm_.setReentry(address(killer), abi.encodeCall(DaoKillCallback.killNow, (gaugeK_)));
        vm.warp(tK + 2 * WEEK);
        vm.recordLogs();
        (uint256 releasedNow, uint256 confiscatedNow) = lb_.checkpoint(gaugeK_);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        // Assert callback success BEFORE clearing it: clearing resets the
        // observation (E7.1.4).
        assertTrue(pm_.reentrySucceeded(), "flag flip executed from the quarter-one callback");
        pm_.setReentry(address(0), "");
        assertEq(releasedNow, QUARTER, "quarter one funds before the mid-catch-up flag");
        assertEq(confiscatedNow, FEE - QUARTER, "quarter two remainder confiscated");
        assertEq(ctlB_.get_gauge_weight(gaugeK_), 777, "raw weight unchanged and nonzero through the kill");
        assertEq(ctlB_.addCalls(), 1, "kill callback is not an addition path");
        _assertMidCatchUpReceipts(tK);
        _assertMidCatchUpLedger(logs);
    }

    /// @dev Receipt leg of test_KilledFlagTrueAtMaturityStopsMidCatchUp
    /// (storage-backed fixtures keep the stack shallow).
    function _assertMidCatchUpReceipts(uint256 tK) internal view {
        // Quarter one receipts survive on BOTH endpoints with the ORIGINAL
        // scheduled epoch and the actual (late) execution epoch.
        (uint256 amtV1, uint256 execV1, bytes32 recV1) = pv_.getDeposit(gaugeK_, tK + WEEK);
        assertEq(amtV1, QUARTER / 2, "quarter one votium receipt face");
        assertEq(execV1, tK + 2 * WEEK, "quarter one execution epoch is the catch-up call");
        assertTrue(recV1 != bytes32(0), "quarter one votium receipt funded");
        (uint256 amtM1, uint256 execM1, bytes32 recM1) = pm_.getDeposit(gaugeK_, tK + WEEK);
        assertEq(amtM1, QUARTER / 2, "quarter one voteMarket receipt face");
        assertEq(execM1, tK + 2 * WEEK, "quarter one voteMarket execution epoch");
        assertTrue(recM1 != bytes32(0), "quarter one voteMarket receipt funded");

        // Quarter two (scheduled tK + 2*WEEK) never called a platform.
        (uint256 amtV2, uint256 execV2, bytes32 recV2) = pv_.getDeposit(gaugeK_, tK + 2 * WEEK);
        assertEq(amtV2 + execV2 + uint256(recV2), 0, "quarter two never called votium");
        (uint256 amtM2,, bytes32 recM2) = pm_.getDeposit(gaugeK_, tK + 2 * WEEK);
        assertEq(amtM2 + uint256(recM2), 0, "quarter two never called voteMarket");
        assertEq(pv_.depositCount(), 1, "only quarter one on votium");
        assertEq(pm_.depositCount(), 1, "only quarter one on voteMarket");
    }

    /// @dev Ledger/custody/events leg of
    /// test_KilledFlagTrueAtMaturityStopsMidCatchUp.
    function _assertMidCatchUpLedger(Vm.Log[] memory logs) internal view {
        CurveGaugeLister.Listing memory rec = lb_.getListing(gaugeK_);
        assertEq(uint8(rec.status), uint8(CurveGaugeLister.Status.Confiscated), "terminal after mid-catch-up flag");
        assertEq(uint256(rec.epochsReleased), 1, "counter stopped at quarter one");
        assertEq(rec.released, QUARTER, "only quarter one released");
        assertEq(rec.confiscated, FEE - QUARTER, "remainder confiscated");
        assertEq(rec.remaining, 0, "no remaining after confiscation");
        assertEq(lb_.totalEscrow(), 0, "liability cleared");
        assertEq(token.balanceOf(address(fdLive_)), FEE - QUARTER, "FD got exactly the mid-catch-up remainder");
        assertEq(token.balanceOf(address(lb_)), 0, "isolated lister emptied");
        assertEq(token.balanceOf(address(pv_)) + token.balanceOf(address(pm_)), QUARTER, "quarter one fully funded");
        assertTrue(
            hasEventFrom(logs, address(lb_), keccak256("EscrowConfiscated(address,address,uint256,uint256)")),
            "confiscation event"
        );
        assertTrue(
            hasEventFrom(logs, address(lb_), keccak256("QuarterReleased(address,uint256,uint256,uint256)")),
            "quarter-one release event"
        );
        assertEq(
            countEvents(logs, address(lb_), keccak256("QuarterReleased(address,uint256,uint256,uint256)")),
            1,
            "exactly one quarter released"
        );
        assertEq(token.allowance(address(lb_), address(pv_)), 0, "votium allowance zero");
        assertEq(token.allowance(address(lb_), address(pm_)), 0, "voteMarket allowance zero");
    }

    function countEventsFrom(Vm.Log[] memory logs, address emitter) internal pure returns (uint256 n) {
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].emitter == emitter) n += 1;
        }
    }

    // ---------------------------------------------------------------
    // R3 — kill oracle, confiscation, FeeDistributor mechanics
    // ---------------------------------------------------------------

    /// @dev exec7 (E7.2), rebuilt per review6 finding 3: the flag alone
    /// confiscates across the full entrypoint x timing matrix on SEPARATE
    /// Active fixtures with explicitly nonzero raw weight — {checkpoint,
    /// confiscate} x {listing epoch (no dues), matured UNPAID dues}. Each
    /// cell asserts its dues BEFORE the flag is set, then exact remaining
    /// seizure, zero platform calls/receipts, released 0, terminal
    /// Confiscated, cleared liability and unchanged weight. The true/zero
    /// control proves zero weight neither blocks nor duplicates seizure;
    /// the paid-partial cell seizes only its unreleased remainder. Cells
    /// live in per-fixture helpers to keep the stack shallow (the same
    /// convention as the mid-catch-up fixtures above).
    function test_KillViaGaugeFlagOnlyConfiscates() public {
        // (a) checkpoint x listing epoch (no dues), weight nonzero.
        _flagTrueCheckpointListingEpoch(31337, 0);
        // (b) checkpoint x matured-UNPAID dues, weight nonzero.
        _flagTrueCheckpointMaturedUnpaid(7, 1);
        // (c) confiscate x listing epoch (no dues), weight nonzero.
        _flagTrueConfiscateListingEpoch(1234, 2);
        // (d) confiscate x matured-UNPAID dues, weight nonzero.
        _flagTrueConfiscateMaturedUnpaid(88, 3);
        // (e) confiscate after partial payment: only the unpaid remainder.
        _flagTrueConfiscateAfterPartialPayment(55, 4);
        // (f) true/zero control: also confiscates exactly once.
        _flagTrueZeroWeightControl(5);
    }

    /// @dev Cell (a): checkpoint in the listing epoch (no dues) with
    /// explicitly nonzero raw weight; the whole fee is seized immediately.
    function _flagTrueCheckpointListingEpoch(uint256 weight, uint256 handlerId) internal {
        (, address gauge) = listFresh(handlerId, 0);
        vm.prank(controllerDao);
        controller.change_gauge_weight(gauge, weight);
        assertEq(controller.get_gauge_weight(gauge), weight, "A raw weight explicitly nonzero");
        assertEq(lister.epochsElapsed(gauge), 0, "A listing epoch: no dues");
        killGauge(gauge);
        assertTrue(MockGauge(gauge).is_killed(), "A flag true");
        // auditfix001 §3: advance WITHIN the listing epoch (still zero dues)
        // to a genuinely eligible accounting time for the seizure.
        uint256 listingEpochA = lister.getListing(gauge).listingEpoch;
        vm.warp(listingEpochA + 86401);
        assertEq(lister.epochsElapsed(gauge), 0, "A still zero dues at the seizure");

        uint256 fdBefore = token.balanceOf(address(fd));
        vm.recordLogs();
        (uint256 released, uint256 confiscated) = lister.checkpoint(gauge);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(released, 0, "A listing epoch: nothing released");
        assertEq(confiscated, FEE, "A listing epoch: whole fee seized");
        assertEq(token.balanceOf(address(fd)), fdBefore + FEE, "A immediate exact remaining transfer to FD");
        assertEq(votium.depositCount() + voteMarket.depositCount(), 0, "A zero platform calls/receipts");
        CurveGaugeLister.Listing memory rec = lister.getListing(gauge);
        assertEq(uint8(rec.status), uint8(CurveGaugeLister.Status.Confiscated), "A terminal Confiscated");
        assertEq(rec.remaining, 0, "A liability cleared");
        assertEq(controller.get_gauge_weight(gauge), weight, "A weight unchanged by confiscation");
        assertTrue(
            hasEventFrom(logs, address(lister), keccak256("EscrowConfiscated(address,address,uint256,uint256)")),
            "A confiscation event"
        );
        // Second call after terminal: exactly zero.
        assertEq(lister.confiscate(gauge), 0, "A confiscates exactly once");
        (uint256 rTerm, uint256 cTerm) = lister.checkpoint(gauge);
        assertEq(rTerm + cTerm, 0, "A no-op after terminal");
    }

    /// @dev Cell (b): checkpoint with two genuinely matured UNPAID quarters
    /// at kill time — the flag is set only AFTER asserting the outstanding
    /// dues, so the seizure happens with real dues and funds nothing.
    function _flagTrueCheckpointMaturedUnpaid(uint256 weight, uint256 handlerId) internal {
        (, address gauge) = listFresh(handlerId, 0);
        vm.prank(controllerDao);
        controller.change_gauge_weight(gauge, weight);
        assertEq(controller.get_gauge_weight(gauge), weight, "B raw weight explicitly nonzero");
        uint256 listingEpoch = lister.getListing(gauge).listingEpoch;
        vm.warp(listingEpoch + 2 * WEEK);
        assertEq(lister.epochsElapsed(gauge), 2, "B two quarters matured unpaid before the flip");
        assertEq(lister.releasable(gauge), 2 * QUARTER, "B dues genuinely outstanding");
        killGauge(gauge);
        assertTrue(MockGauge(gauge).is_killed(), "B flag true");

        uint256 fdBefore = token.balanceOf(address(fd));
        (uint256 released, uint256 confiscated) = lister.checkpoint(gauge);
        assertEq(released, 0, "B matured-unpaid: nothing released");
        assertEq(confiscated, FEE, "B matured-unpaid: whole fee seized");
        assertEq(token.balanceOf(address(fd)), fdBefore + FEE, "B immediate exact remaining transfer to FD");
        assertEq(votium.depositCount() + voteMarket.depositCount(), 0, "B zero platform calls/receipts");
        CurveGaugeLister.Listing memory rec = lister.getListing(gauge);
        assertEq(uint8(rec.status), uint8(CurveGaugeLister.Status.Confiscated), "B terminal Confiscated");
        assertEq(rec.remaining, 0, "B liability cleared");
        assertEq(uint256(rec.epochsReleased), 0, "B counter untouched");
        assertEq(controller.get_gauge_weight(gauge), weight, "B weight unchanged by confiscation");
        assertEq(lister.confiscate(gauge), 0, "B confiscates exactly once");
    }

    /// @dev Cell (c): permissionless confiscate in the listing epoch (no
    /// dues) with explicitly nonzero raw weight.
    function _flagTrueConfiscateListingEpoch(uint256 weight, uint256 handlerId) internal {
        (, address gauge) = listFresh(handlerId, 0);
        vm.prank(controllerDao);
        controller.change_gauge_weight(gauge, weight);
        assertEq(controller.get_gauge_weight(gauge), weight, "C raw weight explicitly nonzero");
        assertEq(lister.epochsElapsed(gauge), 0, "C listing epoch: no dues");
        killGauge(gauge);
        assertTrue(MockGauge(gauge).is_killed(), "C flag true");
        // auditfix001 §3: advance WITHIN the listing epoch to an eligible
        // accounting time (kill coverage stays listing-epoch, dues stay 0).
        vm.warp(lister.getListing(gauge).listingEpoch + 86401);
        assertEq(lister.epochsElapsed(gauge), 0, "C still zero dues at the seizure");

        uint256 fdBefore = token.balanceOf(address(fd));
        vm.prank(stranger);
        assertEq(lister.confiscate(gauge), FEE, "C listing epoch: whole fee seized");
        assertEq(token.balanceOf(address(fd)), fdBefore + FEE, "C immediate exact remaining transfer to FD");
        assertEq(votium.depositCount() + voteMarket.depositCount(), 0, "C zero platform calls/receipts");
        CurveGaugeLister.Listing memory rec = lister.getListing(gauge);
        assertEq(uint8(rec.status), uint8(CurveGaugeLister.Status.Confiscated), "C terminal Confiscated");
        assertEq(rec.remaining, 0, "C liability cleared");
        assertEq(controller.get_gauge_weight(gauge), weight, "C weight unchanged by confiscation");
        vm.prank(stranger);
        assertEq(lister.confiscate(gauge), 0, "C confiscates exactly once");
    }

    /// @dev Cell (d): permissionless confiscate with two genuinely matured
    /// UNPAID quarters at kill time — a separate Active record from cell
    /// (b), seizing the full escrow without funding any quarter.
    function _flagTrueConfiscateMaturedUnpaid(uint256 weight, uint256 handlerId) internal {
        (, address gauge) = listFresh(handlerId, 0);
        vm.prank(controllerDao);
        controller.change_gauge_weight(gauge, weight);
        assertEq(controller.get_gauge_weight(gauge), weight, "D raw weight explicitly nonzero");
        uint256 listingEpoch = lister.getListing(gauge).listingEpoch;
        vm.warp(listingEpoch + 2 * WEEK);
        assertEq(lister.epochsElapsed(gauge), 2, "D two quarters matured unpaid before the flip");
        assertEq(lister.releasable(gauge), 2 * QUARTER, "D dues genuinely outstanding");
        killGauge(gauge);
        assertTrue(MockGauge(gauge).is_killed(), "D flag true");

        uint256 fdBefore = token.balanceOf(address(fd));
        vm.prank(stranger);
        assertEq(lister.confiscate(gauge), FEE, "D matured-unpaid: whole remaining escrow seized");
        assertEq(token.balanceOf(address(fd)), fdBefore + FEE, "D immediate exact remaining transfer to FD");
        assertEq(votium.depositCount() + voteMarket.depositCount(), 0, "D zero platform calls/receipts");
        CurveGaugeLister.Listing memory rec = lister.getListing(gauge);
        assertEq(uint8(rec.status), uint8(CurveGaugeLister.Status.Confiscated), "D terminal Confiscated");
        assertEq(rec.remaining, 0, "D liability cleared");
        assertEq(uint256(rec.epochsReleased), 0, "D counter untouched");
        assertEq(controller.get_gauge_weight(gauge), weight, "D weight unchanged by confiscation");
        vm.prank(stranger);
        assertEq(lister.confiscate(gauge), 0, "D confiscates exactly once");
    }

    /// @dev Cell (e): two quarters are funded BEFORE the flag is set, then
    /// confiscation takes exactly the unreleased remainder.
    function _flagTrueConfiscateAfterPartialPayment(uint256 weight, uint256 handlerId) internal {
        (, address gauge) = listFresh(handlerId, 0);
        vm.prank(controllerDao);
        controller.change_gauge_weight(gauge, weight);
        assertEq(controller.get_gauge_weight(gauge), weight, "E raw weight explicitly nonzero");
        uint256 listingEpoch = lister.getListing(gauge).listingEpoch;
        vm.warp(listingEpoch + 2 * WEEK);
        (uint256 paid,) = lister.checkpoint(gauge);
        assertEq(paid, 2 * QUARTER, "E two quarters paid pre-kill");
        assertEq(votium.depositCount(), 2, "E pre-kill funding only");
        killGauge(gauge);

        uint256 fdBefore = token.balanceOf(address(fd));
        vm.prank(stranger);
        assertEq(lister.confiscate(gauge), FEE - 2 * QUARTER, "E exact unreleased remainder");
        assertEq(token.balanceOf(address(fd)), fdBefore + FEE - 2 * QUARTER, "E FD totals");
        assertEq(votium.depositCount(), 2, "E no further platform calls after the kill");
        assertEq(voteMarket.depositCount(), 2, "E no further voteMarket calls after the kill");
        CurveGaugeLister.Listing memory rec = lister.getListing(gauge);
        assertEq(uint8(rec.status), uint8(CurveGaugeLister.Status.Confiscated), "E terminal");
        assertEq(rec.remaining, 0, "E liability cleared");
    }

    /// @dev Cell (f): true/zero control — flag true AND raw weight zero also
    /// confiscates exactly once; weight contributes nothing either way.
    function _flagTrueZeroWeightControl(uint256 handlerId) internal {
        (, address gauge) = listFresh(handlerId, 0);
        assertEq(controller.get_gauge_weight(gauge), 0, "F fresh weight zero");
        killGauge(gauge);
        assertTrue(MockGauge(gauge).is_killed(), "F flag true");
        // auditfix001 §3: in-epoch advance to an eligible accounting time.
        vm.warp(lister.getListing(gauge).listingEpoch + 86401);

        uint256 fdBefore = token.balanceOf(address(fd));
        vm.prank(stranger);
        assertEq(lister.confiscate(gauge), FEE, "F true/zero confiscates");
        assertEq(lister.confiscate(gauge), 0, "F exactly once");
        assertEq(token.balanceOf(address(fd)), fdBefore + FEE, "F FD totals");
        assertEq(lister.totalEscrow(), 0, "F all liabilities cleared");
    }

    /// @dev exec7 (E7.2): flag false is live at ANY weight — fresh zero, an
    /// explicit admin nonzero-to-zero change, and a weight-only flip during a
    /// quarter's callback. Nothing is ever seized and later quarters still fund.
    function test_WeightZeroWithoutKilledFlagDoesNotConfiscate() public {
        // (a) fresh weight zero, flag false.
        (, address gauge) = listFresh(0, 0);
        assertEq(controller.get_gauge_weight(gauge), 0, "fresh weight zero");
        assertFalse(MockGauge(gauge).is_killed(), "flag false");
        vm.prank(stranger);
        assertEq(lister.confiscate(gauge), 0, "confiscate returns 0");
        (uint256 r0, uint256 c0) = lister.checkpoint(gauge); // listing epoch, no dues
        assertEq(r0 + c0, 0, "no-due checkpoint preserves funds");
        assertEq(lister.getListing(gauge).remaining, FEE, "escrow intact");

        // (b) explicit admin nonzero-to-zero change with the flag still false.
        vm.prank(controllerDao);
        controller.change_gauge_weight(gauge, 999);
        vm.prank(controllerDao);
        controller.change_gauge_weight(gauge, 0); // nonzero -> zero
        assertFalse(MockGauge(gauge).is_killed(), "flag still false");
        vm.prank(stranger);
        assertEq(lister.confiscate(gauge), 0, "admin zero alone: confiscate 0");
        assertEq(lister.releasable(gauge), 0, "nothing matured yet");

        // (c) matured releasable/checkpoint return and fund the proper
        // quarters at zero weight; FD gets zero.
        vm.warp(T0 + 2 * WEEK);
        assertEq(lister.releasable(gauge), 2 * QUARTER, "matured gross at zero weight");
        (uint256 r2, uint256 c2) = lister.checkpoint(gauge);
        assertEq(r2, 2 * QUARTER, "quarters fund at zero weight");
        assertEq(c2, 0, "no confiscation");
        assertEq(token.balanceOf(address(fd)), 0, "FD gets zero");
        assertEq(lister.getListing(gauge).epochsReleased, 2, "counter advanced");

        // (d) change weight alone DURING the quarter-one callback of a fresh
        // gauge: later due quarters still fund (the retired oracle is gone).
        // review6 finding 2: the mid-call drop must be genuinely nonzero ->
        // zero — gaugeD's scheduled bias is established and asserted at the
        // exact nonzero Elixir evidence weight (DEFECT-001/A2.2) BEFORE the
        // catch-up, so the callback provably writes zero over a nonzero
        // value, never zero over zero.
        (, address gaugeD) = listFresh(1, 0); // listed at T0 + 2*WEEK
        uint256 listingEpochD = lister.getListing(gaugeD).listingEpoch;
        vm.prank(controllerDao);
        controller.change_gauge_weight(gaugeD, 36_978_154_478_253_142_761_600);
        assertEq(
            controller.get_gauge_weight(gaugeD),
            36_978_154_478_253_142_761_600,
            "D precondition: nonzero scheduled bias before catch-up"
        );
        assertFalse(MockGauge(gaugeD).is_killed(), "D precondition: flag false before catch-up");
        DaoKillCallback weightFlipper = new DaoKillCallback();
        weightFlipper.arm(address(controller), controllerDao);
        voteMarket.setReentry(address(weightFlipper), abi.encodeCall(DaoKillCallback.zeroWeightNow, (gaugeD)));
        vm.warp(listingEpochD + 4 * WEEK); // all four quarters due in one call
        (uint256 rD, uint256 cD) = lister.checkpoint(gaugeD);
        // Assert callback success BEFORE clearing it: clearing resets the
        // observation.
        assertTrue(voteMarket.reentrySucceeded(), "weight-only callback executed mid-quarter");
        voteMarket.setReentry(address(0), "");
        assertEq(rD, 4 * QUARTER, "all four due quarters still fund after a mid-call weight drop");
        assertEq(cD, 0, "no confiscation from a mid-call weight change");
        assertEq(controller.get_gauge_weight(gaugeD), 0, "weight really went nonzero -> zero mid-call");
        assertFalse(MockGauge(gaugeD).is_killed(), "flag stayed false through the drop");
        assertEq(uint8(lister.getListing(gaugeD).status), uint8(CurveGaugeLister.Status.Exhausted), "D exhausted");
        assertEq(token.balanceOf(address(fd)), 0, "FD untouched by weight-only flips");
        // The first and every later due funded receipt survives on both
        // platforms, labeled with its ORIGINAL scheduled epoch and the late
        // catch-up call as the execution epoch.
        for (uint256 k = 1; k <= 4; ++k) {
            uint256 scheduled = listingEpochD + k * WEEK;
            (uint256 amtV, uint256 execV, bytes32 recV) = votium.getDeposit(gaugeD, scheduled);
            assertEq(amtV, QUARTER / 2, "D funded votium receipt face survives");
            assertEq(execV, listingEpochD + 4 * WEEK, "D votium execution epoch is the catch-up call");
            assertTrue(recV != bytes32(0), "D funded votium receipt survives");
            (uint256 amtM, uint256 execM, bytes32 recM) = voteMarket.getDeposit(gaugeD, scheduled);
            assertEq(amtM, QUARTER / 2, "D funded voteMarket receipt face survives");
            assertEq(execM, listingEpochD + 4 * WEEK, "D voteMarket execution epoch is the catch-up call");
            assertTrue(recM != bytes32(0), "D funded voteMarket receipt survives");
        }
        assertEq(votium.depositCount() + voteMarket.depositCount(), 4 + 8, "all quarters funded on both gauges");
    }

    /// @dev exec7 (E7.2): after admission the settlement path performs NO
    /// controller read. With controller reads reverting: flag false settles
    /// normally; flag true confiscates through each entrypoint on separate
    /// Active records, with releasable zero before settlement. The failure
    /// stays enabled during the calls.
    function test_SettlementNeverReadsControllerWeight() public {
        // All records are admitted FIRST (admission legitimately reads the
        // controller); the reads break only afterwards.
        (, address gaugeA) = listFresh(0, 0);
        (, address gaugeB) = listFresh(1, 0); // checkpoint entrypoint
        (, address gaugeC) = listFresh(2, 0); // confiscate entrypoint
        vm.prank(controllerDao);
        controller.change_gauge_weight(gaugeA, 55); // nonzero to prove no reread either way

        // Flag false: releases work with the controller fully broken.
        vm.warp(T0 + WEEK);
        controller.setReadsRevert(true);
        vm.prank(stranger);
        assertEq(lister.confiscate(gaugeA), 0, "flag false: confiscate 0 with controller down");
        assertEq(lister.releasable(gaugeA), QUARTER, "releasable works with controller down");
        (uint256 rA,) = lister.checkpoint(gaugeA);
        assertEq(rA, QUARTER, "checkpoint releases with controller down");
        assertEq(token.balanceOf(address(votium)) + token.balanceOf(address(voteMarket)), QUARTER, "funded");

        // Flag true: one fresh Active record per settlement entrypoint.
        killGauge(gaugeB);
        killGauge(gaugeC);
        assertEq(lister.releasable(gaugeB), 0, "releasable zero on true flag before settlement");
        assertEq(lister.releasable(gaugeC), 0, "releasable zero on true flag before settlement 2");
        (, uint256 cB) = lister.checkpoint(gaugeB);
        assertEq(cB, FEE, "checkpoint confiscates with controller down");
        // auditfix001 §3: the first seizure reset the SHARED distributor
        // cursor; give the consecutive second seizure its strict cooldown.
        vm.warp(block.timestamp + 86401);
        vm.prank(stranger);
        assertEq(lister.confiscate(gaugeC), FEE, "confiscate confiscates with controller down");
        assertEq(token.balanceOf(address(fd)), 2 * FEE, "FD holds both");
        // The failure really stayed enabled through every settlement call.
        vm.expectRevert(MockListingController.ReadFailed.selector);
        controller.gauge_types(gaugeB);

        // Controller health returns only for the teardown read.
        controller.setReadsRevert(false);
        assertEq(controller.gauge_types(gaugeB), int128(0), "controller restored after the scenario");
    }

    /// @dev exec7 (E7.2): healthy admission followed by a reverting gauge
    /// getter — `checkpoint`, `confiscate` and `releasable` all revert before
    /// maturity AND with dues, whether controller weight is 0 or nonzero; the
    /// exact injected error is observed, nothing moves, and a restored getter
    /// allows exactly one correct retry. A malformed boolean return is equally
    /// unsettleable. (This inverts the old product's claim that a gauge flag
    /// could not affect settlement: Settlement.t.sol pre-exec7 lines 724–729
    /// asserted a true flag still released.)
    function test_GaugeFlagReadFailureCannotSettle() public {
        // --- (a) reverting getter, controller weight ZERO (fresh paid listing).
        (, address gauge) = listFresh(0, 0);
        assertEq(controller.get_gauge_weight(gauge), 0, "fresh paid weight is zero");

        // Before maturity (no dues): all three entry points revert.
        MockGauge(gauge).setKilledReadRevert(true);
        vm.prank(stranger);
        vm.expectRevert(MockGauge.KilledReadFailed.selector);
        lister.confiscate(gauge);
        vm.expectRevert(MockGauge.KilledReadFailed.selector);
        lister.checkpoint(gauge);
        vm.expectRevert(MockGauge.KilledReadFailed.selector);
        lister.releasable(gauge);

        // With dues (two quarters matured): still revert, nothing moves.
        vm.warp(T0 + 2 * WEEK);
        vm.recordLogs();
        vm.expectRevert(MockGauge.KilledReadFailed.selector);
        lister.checkpoint(gauge);
        vm.expectRevert(MockGauge.KilledReadFailed.selector);
        lister.confiscate(gauge);
        vm.expectRevert(MockGauge.KilledReadFailed.selector);
        lister.releasable(gauge);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(countEventsFrom(logs, address(lister)), 0, "no lister events under read failure");
        CurveGaugeLister.Listing memory rec = lister.getListing(gauge);
        assertEq(uint256(rec.epochsReleased), 0, "no counter bump under read failure");
        assertEq(rec.remaining, FEE, "no remaining drain under read failure");
        assertEq(rec.confiscated, 0, "no confiscation under read failure");
        assertEq(lister.totalEscrow(), FEE, "liability preserved under read failure");
        assertEq(token.balanceOf(address(lister)), FEE, "custody preserved under read failure");
        assertEq(votium.depositCount() + voteMarket.depositCount(), 0, "no receipts under read failure");
        assertEq(token.allowance(address(lister), address(votium)), 0, "no votium allowance");
        assertEq(token.allowance(address(lister), address(voteMarket)), 0, "no voteMarket allowance");

        // Restore a valid getter: exactly one correct retry settles the dues.
        MockGauge(gauge).setKilledReadRevert(false);
        (uint256 r, uint256 c) = lister.checkpoint(gauge);
        assertEq(r, 2 * QUARTER, "single correct retry funds both due quarters");
        assertEq(c, 0, "no confiscation on the retry");
        assertEq(votium.depositCount(), 2, "no duplicate funding on the retry");

        // (b) test-local ABI-fault fixture: malformed boolean returndata
        // after healthy admission also cannot release or confiscate. Its
        // times also derive from its own recorded listing epoch (forward
        // warps only).
        address lp = address(new MockERC20(18));
        address pool = address(new MockPool());
        GarbageFlagGauge garbageGauge = new GarbageFlagGauge(lp);
        registry.setPool(pool, 2, lp, _coins(address(new MockERC20(18)), address(new MockERC20(18))), 2);
        registry.setGauge(pool, 2, 0, address(garbageGauge), 0);
        vm.prank(payer);
        lister.listGauge(pool, address(garbageGauge), 0, 2);
        uint256 listingEpochG = lister.getListing(address(garbageGauge)).listingEpoch;
        vm.warp(listingEpochG + WEEK); // this listing's first actual maturity
        garbageGauge.setGarbage(true);
        // Staticcall-level decode failure bubbles as an empty-revert from the
        // product's ABI decode of the malformed return.
        vm.expectRevert();
        lister.checkpoint(address(garbageGauge));
        vm.expectRevert();
        lister.confiscate(address(garbageGauge));
        vm.expectRevert();
        lister.releasable(address(garbageGauge));
        assertEq(lister.getListing(address(garbageGauge)).epochsReleased, 0, "garbage read released nothing");
        assertEq(token.balanceOf(address(lister)), 2 * FEE - 2 * QUARTER, "garbage read moved nothing");
        // Disarming the fault restores ordinary settlement.
        garbageGauge.setGarbage(false);
        (uint256 rG,) = lister.checkpoint(address(garbageGauge));
        assertEq(rG, QUARTER, "healthy retry funds after the malformed-data fault");
    }

    /// @dev exec7 (E7.2): the FIRST quarter provisionally funds, its final
    /// endpoint arms the gauge-read fault, and the next tranche's flag reread
    /// reverts the WHOLE checkpoint — prior receipts/balances/counters,
    /// allowances and the callback's fault write all roll back (distinguished
    /// from the successful mid-call kill in test_KilledFlagTrueAtMaturity-
    /// StopsMidCatchUp). A cleared callback then retries without duplicates.
    function test_GaugeFlagReadFailureMidCatchUpRollsBack() public {
        (, address gauge) = listFresh(0, 0);
        // Arm VoteMarket (each quarter's final positive-share endpoint) to
        // flip the GAUGE read fault on during quarter one's deposit.
        voteMarket.setReentry(address(gauge), abi.encodeCall(MockGauge.setKilledReadRevert, (true)));
        vm.warp(T0 + 2 * WEEK); // two quarters due in one checkpoint
        vm.expectRevert(MockGauge.KilledReadFailed.selector);
        lister.checkpoint(gauge);

        // The entire checkpoint rolled back, including the callback's fault
        // write on the gauge (it happened inside the reverted transaction).
        assertEq(votium.depositCount(), 0, "prior-quarter votium receipt rolled back");
        assertEq(voteMarket.depositCount(), 0, "prior-quarter voteMarket receipt rolled back");
        assertEq(token.balanceOf(address(votium)), 0, "prior-quarter votium balance rolled back");
        assertEq(token.balanceOf(address(voteMarket)), 0, "prior-quarter voteMarket balance rolled back");
        assertEq(token.balanceOf(address(lister)), FEE, "escrow untouched by the rollback");
        assertEq(lister.totalEscrow(), FEE, "liability untouched by the rollback");
        CurveGaugeLister.Listing memory rec = lister.getListing(gauge);
        assertEq(uint256(rec.epochsReleased), 0, "counter rolled back");
        assertEq(rec.released, 0, "released rolled back");
        assertEq(rec.remaining, FEE, "remaining rolled back");
        assertEq(uint8(rec.status), uint8(CurveGaugeLister.Status.Active), "still Active");
        assertEq(token.allowance(address(lister), address(votium)), 0, "votium allowance rolled back to zero");
        assertEq(token.allowance(address(lister), address(voteMarket)), 0, "voteMarket allowance rolled back to zero");
        assertFalse(MockGauge(gauge).is_killed(), "stored flag state preserved");
        // The callback's success-flag write happened INSIDE the reverted
        // transaction, so it rolled back with everything else — the revert
        // reason (KilledReadFailed) is itself the evidence the callback ran
        // and armed the fault before quarter two's reread.
        assertFalse(voteMarket.reentrySucceeded(), "callback success flag rolled back with the checkpoint");

        // The gauge read is genuinely healthy again only because the write
        // rolled back; the reentry ARM itself persists (set before the call),
        // so a naive retry would re-fault. Clear it and retry: exactly the two
        // due quarters fund, with no duplicate funding.
        voteMarket.setReentry(address(0), "");
        (uint256 r, uint256 c) = lister.checkpoint(gauge);
        assertEq(r, 2 * QUARTER, "retry funds both due quarters");
        assertEq(c, 0, "no confiscation on the retry");
        assertEq(votium.depositCount(), 2, "no duplicate votium funding");
        assertEq(voteMarket.depositCount(), 2, "no duplicate voteMarket funding");
        assertEq(lister.getListing(gauge).epochsReleased, 2, "counter advanced exactly once per quarter");
    }

    /// @dev exec7 (E7.2): releasable keys off the gauge flag ONLY. Exact
    /// matured-but-unpaid amounts at flag false for zero and nonzero weights
    /// and after a partial release; zero at flag true for either weight; gauge
    /// read failures propagate while controller failures do not; unknown
    /// records return zero without any dependency read (terminal records are
    /// covered by test_TerminalStatesSkipKillOracleReads).
    function test_ReleasableUsesGaugeFlagOnly() public {
        // (a) zero weight, flag false: exact amounts, decaying with payments.
        (, address gaugeZ) = listFresh(0, 0);
        assertEq(controller.get_gauge_weight(gaugeZ), 0, "zero weight");
        assertEq(lister.releasable(gaugeZ), 0, "nothing due in the listing epoch");
        vm.warp(T0 + WEEK);
        assertEq(lister.releasable(gaugeZ), QUARTER, "one quarter at zero weight");
        vm.warp(T0 + 3 * WEEK);
        assertEq(lister.releasable(gaugeZ), 3 * QUARTER, "three quarters at zero weight");
        lister.checkpoint(gaugeZ); // pay all three
        assertEq(lister.releasable(gaugeZ), 0, "zero after full catch-up release");
        vm.warp(T0 + 4 * WEEK);

        // (b) nonzero weight, flag false: identical amounts (forward-only
        // timeline: gaugeN is listed at T0+4W after (a)'s three-quarter
        // catch-up; gaugeZ stays active with one quarter outstanding).
        (, address gaugeN) = listFresh(1, 0);
        vm.prank(controllerDao);
        controller.change_gauge_weight(gaugeN, 500);
        vm.warp(T0 + 5 * WEEK);
        assertEq(lister.releasable(gaugeN), QUARTER, "same amount at nonzero weight");
        lister.checkpoint(gaugeN); // quarter one paid
        vm.warp(T0 + 6 * WEEK);
        assertEq(lister.releasable(gaugeN), QUARTER, "exact after partial release");
        assertEq(lister.getListing(gaugeN).epochsReleased, 1, "partial release precondition");

        // (c) flag true returns 0 at either weight.
        killGauge(gaugeN);
        assertEq(controller.get_gauge_weight(gaugeN), 500, "nonzero weight still");
        assertEq(lister.releasable(gaugeN), 0, "true/nonzero returns 0");
        (, address gaugeZ2) = listFresh(2, 0); // listed at T0+6W
        vm.warp(T0 + 7 * WEEK); // one quarter due: only the flag can zero it
        assertEq(lister.releasable(gaugeZ2), QUARTER, "flag false would release here");
        killGauge(gaugeZ2);
        assertEq(controller.get_gauge_weight(gaugeZ2), 0, "zero weight");
        assertEq(lister.releasable(gaugeZ2), 0, "true/zero returns 0");
        MockGauge(gaugeZ2).setKilled(false);

        // (d) gauge read failure propagates.
        MockGauge(gaugeZ2).setKilledReadRevert(true);
        vm.expectRevert(MockGauge.KilledReadFailed.selector);
        lister.releasable(gaugeZ2);
        MockGauge(gaugeZ2).setKilledReadRevert(false);

        // (e) controller failure does NOT propagate (no controller read).
        controller.setReadsRevert(true);
        assertEq(lister.releasable(gaugeZ2), QUARTER, "controller failure does not affect releasable");
        controller.setReadsRevert(false);

        // (f) unknown record returns 0 without any read. (The terminal-state
        // releasable matrix belongs to test_TerminalStatesSkipKillOracleReads.)
        assertEq(lister.releasable(actor("neverListed")), 0, "unknown: zero without reads");
    }

    /// @dev exec7 (E7.2): Exhausted, Confiscated and DaoExempt remain no-ops
    /// for checkpoint/confiscate/releasable when BOTH dependency getters
    /// revert; no events, transfers or new receipts appear; a confiscated
    /// record cannot be reopened by unkill/weight restoration; unknown
    /// settlement calls retain UnknownGauge.
    function test_TerminalStatesSkipKillOracleReads() public {
        (, address gaugeX) = listFresh(0, 0); // -> Exhausted
        (, address gaugeK) = listFresh(1, 0); // -> Confiscated
        (address poolD, address gaugeD,) = deployAuthenticatedPool(2, 0); // DaoExempt
        vm.warp(T0 + 4 * WEEK);
        lister.checkpoint(gaugeX);
        killGauge(gaugeK);
        vm.prank(stranger);
        lister.confiscate(gaugeK);
        vm.prank(daoOwner);
        lister.listGaugeNoEscrow(poolD, gaugeD, 0, 2, 0);
        assertEq(uint8(lister.getListing(gaugeX).status), uint8(CurveGaugeLister.Status.Exhausted), "X exhausted");
        assertEq(uint8(lister.getListing(gaugeK).status), uint8(CurveGaugeLister.Status.Confiscated), "K confiscated");
        assertEq(uint8(lister.getListing(gaugeD).status), uint8(CurveGaugeLister.Status.DaoExempt), "D exempt");

        // Unkill/weight restoration cannot reopen the confiscated record.
        MockGauge(gaugeK).setKilled(false);
        vm.prank(controllerDao);
        controller.change_gauge_weight(gaugeK, 123);

        // BOTH dependency getters revert for the whole scenario.
        controller.setReadsRevert(true);
        MockGauge(gaugeX).setKilledReadRevert(true);
        MockGauge(gaugeK).setKilledReadRevert(true);
        MockGauge(gaugeD).setKilledReadRevert(true);
        address[3] memory terminal = [gaugeX, gaugeK, gaugeD];
        uint256 fdBefore = token.balanceOf(address(fd));
        for (uint256 i = 0; i < terminal.length; ++i) {
            vm.recordLogs();
            (uint256 r, uint256 c) = lister.checkpoint(terminal[i]);
            assertEq(r + c, 0, "terminal checkpoint no-op with both getters reverting");
            uint256 seized = lister.confiscate(terminal[i]);
            assertEq(seized, 0, "terminal confiscate no-op with both getters reverting");
            assertEq(lister.releasable(terminal[i]), 0, "terminal releasable zero with both getters reverting");
            Vm.Log[] memory logs = vm.getRecordedLogs();
            assertEq(countEventsFrom(logs, address(lister)), 0, "no lister events on a terminal no-op");
        }
        assertEq(token.balanceOf(address(fd)), fdBefore, "no transfers");
        assertEq(votium.depositCount() + voteMarket.depositCount(), 8, "no new receipts");
        assertEq(token.balanceOf(address(votium)), 2 * QUARTER, "no new platform custody");

        // Unknown settlement calls retain UnknownGauge.
        address ghost = actor("neverListed");
        vm.expectRevert(abi.encodeWithSelector(CurveGaugeLister.UnknownGauge.selector, ghost));
        lister.checkpoint(ghost);
        vm.expectRevert(abi.encodeWithSelector(CurveGaugeLister.UnknownGauge.selector, ghost));
        lister.confiscate(ghost);

        controller.setReadsRevert(false);
        MockGauge(gaugeX).setKilledReadRevert(false);
        MockGauge(gaugeK).setKilledReadRevert(false);
        MockGauge(gaugeD).setKilledReadRevert(false);
    }

    function test_ObservedConfiscationStaysTerminalAfterFlagCleared() public {
        // (a) a successful confiscation cannot be reopened by an unkill or by
        // weight restoration.
        (, address gaugeA) = listFresh(0, 0);
        killGauge(gaugeA);
        // auditfix001 §3: in-listing-epoch advance to an eligible accounting
        // time (the kill itself stays a listing-epoch kill).
        vm.warp(lister.getListing(gaugeA).listingEpoch + 86401);
        vm.prank(stranger);
        assertEq(lister.confiscate(gaugeA), FEE, "A confiscated");

        MockGauge(gaugeA).setKilled(false); // authorized unkill after observation
        vm.prank(controllerDao);
        controller.change_gauge_weight(gaugeA, 999); // votes/admin overwrite weight too
        (uint256 r, uint256 c) = lister.checkpoint(gaugeA);
        assertEq(r + c, 0, "terminal despite cleared flag and restored weight");
        assertEq(lister.confiscate(gaugeA), 0, "no re-confiscation");
        assertEq(token.balanceOf(address(fd)), FEE, "FD balance frozen at seizure");
        assertEq(
            uint8(lister.getListing(gaugeA).status), uint8(CurveGaugeLister.Status.Confiscated), "stays Confiscated"
        );

        // (b) a kill flag that is cleared BEFORE observation cannot be
        // historically inferred: current-state detection is the mandate.
        (, address gaugeB) = listFresh(1, 0);
        vm.warp(T0 + WEEK);
        killGauge(gaugeB);
        MockGauge(gaugeB).setKilled(false); // unkill before any settlement read
        (r, c) = lister.checkpoint(gaugeB);
        assertEq(r, QUARTER, "cleared-before-observation releases");
        assertEq(c, 0, "no historical-kill claim");
        assertEq(token.balanceOf(address(fd)), FEE, "only A was confiscated");
    }

    function test_ConfiscationTransfersOnlyKilledGaugeBalance() public {
        (, address gaugeA) = listFresh(0, 0);
        (, address gaugeB) = listFresh(1, 0);
        assertEq(lister.totalEscrow(), 2 * FEE, "two fees");

        address donor = actor("donor");
        token.mint(donor, 777e18);
        vm.prank(donor);
        token.transfer(address(lister), 777e18); // unsolicited donation
        assertEq(token.balanceOf(address(lister)), 2 * FEE + 777e18, "donation held");

        killGauge(gaugeA);
        // auditfix001 §3: in-listing-epoch advance to an eligible accounting
        // time for the seizure.
        vm.warp(lister.getListing(gaugeA).listingEpoch + 86401);
        vm.prank(stranger);
        assertEq(lister.confiscate(gaugeA), FEE, "only A's remaining");
        assertEq(token.balanceOf(address(fd)), FEE, "FD receives only A");
        assertEq(token.balanceOf(address(lister)), FEE + 777e18, "B and donation stay");
        assertEq(lister.totalEscrow(), FEE, "B liability intact");
        CurveGaugeLister.Listing memory recB = lister.getListing(gaugeB);
        assertEq(recB.remaining, FEE, "B untouched");
        assertEq(uint8(recB.status), uint8(CurveGaugeLister.Status.Active), "B still Active");
        assertEq(token.allowance(address(lister), address(fd)), 0, "FD approval always zero");
    }

    /// @dev auditfix001 §3/§6: confiscation REVERTS until safe accounting can
    /// complete in the transaction. At t (the construction-floored cursor)
    /// and exactly +86400, and under an injected checkpoint failure at an
    /// otherwise eligible time, BOTH killed-gauge settlement entrypoints
    /// revert with the complete state intact. Standalone checkpointFees()
    /// still returns/emits false in cooldown or under the injected revert
    /// and transfers nothing. At +86401 the DIRECT confiscation retry (never
    /// checkpointFees first) commits exactly once with full accounting and
    /// success events; the injected fault gets its own cleared-fault
    /// direct-retry control on a fresh listing. A two-listing cell proves a
    /// successful seizure resets the SHARED cursor so the next
    /// same-timestamp seizure reverts until its own strict cooldown passes,
    /// with no partial commit of the second gauge.
    function test_CheckpointCooldownRevertsConfiscationUntilAccountingEligible() public {
        (, address gauge) = listFresh(0, 0);
        killGauge(gauge);
        assertEq(fd.last_token_time(), T0, "cursor floored at construction");

        // (a) At t and exactly +86400: both entrypoints revert, state intact.
        _expectSeizureRevertStateIntact(gauge, MockFeeDistributor.CannotCheckpoint.selector, "at t");
        vm.warp(T0 + 86400);
        _expectSeizureRevertStateIntact(gauge, MockFeeDistributor.CannotCheckpoint.selector, "at t+86400");

        // Standalone checkpointFees still reports false in cooldown and
        // transfers nothing (custody stays in the core).
        vm.prank(stranger);
        assertFalse(lister.checkpointFees(), "checkpointFees false during cooldown");
        assertEq(token.balanceOf(address(lister)), FEE, "checkpointFees transferred nothing");
        assertEq(fd.checkpointCalls(), 0, "no accounting pass yet");

        // (b) At +86401 retry CONFISCATION directly: it commits exactly once,
        // with full accounting and success events.
        vm.warp(T0 + 86401);
        vm.recordLogs();
        uint256 seized = lister.confiscate(gauge);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(seized, FEE, "direct retry seizes the whole fee");
        assertTrue(
            hasEventFrom(logs, address(lister), keccak256("EscrowConfiscated(address,address,uint256,uint256)")),
            "custody event"
        );
        assertTrue(hasFCResult(logs, true), "accounting success indicated");
        assertFalse(hasFCResult(logs, false), "no false result committed by confiscation");
        assertEq(fd.last_token_time(), T0 + 86401, "cursor accounted to now");
        assertEq(fd.token_last_balance(), FEE, "entire fee accounted");
        assertEq(fd.tokens_per_week(T0), FEE, "single covered bucket credited");
        assertEq(token.balanceOf(address(fd)), FEE, "FD holds the fee");
        assertEq(token.balanceOf(address(lister)), 0, "core emptied");
        assertEq(fd.checkpointCalls(), 1, "exactly one accounting pass");
        CurveGaugeLister.Listing memory rec = lister.getListing(gauge);
        assertEq(uint8(rec.status), uint8(CurveGaugeLister.Status.Confiscated), "terminal");
        assertEq(rec.confiscated, FEE, "terminal confiscation ledger");
        assertEq(lister.confiscate(gauge), 0, "cannot pay again");

        // (c) Injected checkpoint failure at an otherwise eligible time on a
        // fresh listing: reverts with everything intact; clearing the fault
        // and retrying DIRECTLY commits exactly once.
        vm.warp(T0 + 3 * 86400);
        assertTrue(block.timestamp > fd.last_token_time() + 86400, "public path eligible without the fault");
        (, address gauge2) = listFresh(1, 0);
        killGauge(gauge2);
        fd.setCheckpointRevert(true);
        _expectSeizureRevertStateIntact(gauge2, MockFeeDistributor.CheckpointFailed.selector, "injected failure");
        vm.prank(stranger);
        assertFalse(lister.checkpointFees(), "checkpointFees false under injected revert");
        assertEq(token.balanceOf(address(lister)), FEE, "no transfer under the fault");
        assertEq(fd.checkpointCalls(), 1, "no accounting pass under the fault");
        fd.setCheckpointRevert(false);
        vm.prank(stranger);
        assertEq(lister.confiscate(gauge2), FEE, "fault cleared: direct retry commits");
        assertEq(fd.token_last_balance(), 2 * FEE, "second fee fully accounted");
        assertEq(fd.checkpointCalls(), 2, "second accounting pass");
        assertEq(lister.totalEscrow(), 0, "both records terminal");

        // (d) Two-listing cell: one successful seizure resets the SHARED
        // distributor cursor, so the next seizure at the same timestamp
        // reverts; after the strict cooldown it succeeds. No partial commit.
        vm.warp(T0 + 5 * 86400);
        (, address gaugeX) = listFresh(2, 0);
        (, address gaugeY) = listFresh(3, 0);
        killGauge(gaugeX);
        killGauge(gaugeY);
        vm.prank(stranger);
        assertEq(lister.confiscate(gaugeX), FEE, "first seizure commits");
        assertEq(fd.last_token_time(), block.timestamp, "shared cursor reset by the first seizure");
        _expectSeizureRevertStateIntact(gaugeY, MockFeeDistributor.CannotCheckpoint.selector, "same-timestamp second");
        vm.warp(block.timestamp + 86401);
        vm.prank(stranger);
        assertEq(lister.confiscate(gaugeY), FEE, "second seizure after its strict cooldown");
        assertEq(fd.token_last_balance(), 4 * FEE, "all four fees accounted");
        assertEq(token.balanceOf(address(fd)), 4 * FEE, "FD custody total");
        assertEq(lister.totalEscrow(), 0, "no liability remains");
    }

    /// @dev Both killed-gauge settlement entrypoints revert with `want` and
    /// the COMPLETE pre-state intact: Listing record, totalEscrow, both
    /// custody balances, cursor, accounted balance, weekly buckets and the
    /// successful checkpoint count.
    function _expectSeizureRevertStateIntact(address gauge, bytes4 want, string memory label) internal {
        bytes32 recHash = keccak256(abi.encode(lister.getListing(gauge)));
        uint256 escrow = lister.totalEscrow();
        uint256 listerBal = token.balanceOf(address(lister));
        uint256 fdBal = token.balanceOf(address(fd));
        uint256 cursor = fd.last_token_time();
        uint256 accounted = fd.token_last_balance();
        uint256 calls = fd.checkpointCalls();
        uint256 bucket0 = fd.tokens_per_week(T0);
        uint256 bucket1 = fd.tokens_per_week(T0 + WEEK);

        vm.prank(stranger);
        vm.expectRevert(want);
        lister.confiscate(gauge);
        vm.expectRevert(want);
        lister.checkpoint(gauge);

        assertEq(keccak256(abi.encode(lister.getListing(gauge))), recHash, string.concat(label, ": listing unchanged"));
        assertEq(lister.totalEscrow(), escrow, string.concat(label, ": escrow intact"));
        assertEq(token.balanceOf(address(lister)), listerBal, string.concat(label, ": core custody intact"));
        assertEq(token.balanceOf(address(fd)), fdBal, string.concat(label, ": FD custody intact"));
        assertEq(fd.last_token_time(), cursor, string.concat(label, ": cursor unchanged"));
        assertEq(fd.token_last_balance(), accounted, string.concat(label, ": accounted balance unchanged"));
        assertEq(fd.checkpointCalls(), calls, string.concat(label, ": no accounting pass"));
        assertEq(fd.tokens_per_week(T0), bucket0, string.concat(label, ": bucket T0 unchanged"));
        assertEq(fd.tokens_per_week(T0 + WEEK), bucket1, string.concat(label, ": bucket T0+W unchanged"));
    }

    function hasFCResult(Vm.Log[] memory logs, bool wanted) internal pure returns (bool) {
        bytes32 sig = keccak256("FeeCheckpointResult(bool)");
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].emitter != address(0) && logs[i].topics.length > 0 && logs[i].topics[0] == sig) {
                if (logs[i].data.length == 32) {
                    if (abi.decode(logs[i].data, (bool)) == wanted) return true;
                }
            }
        }
        return false;
    }

    function test_KilledFeeDistributorRevertsWithoutAlternativeRecipient() public {
        (, address gauge) = listFresh(0, 0);
        killGauge(gauge);
        fd.setKilled(true);

        vm.prank(stranger);
        vm.expectRevert();
        lister.confiscate(gauge);
        vm.expectRevert();
        lister.checkpoint(gauge);
        assertEq(uint8(lister.getListing(gauge).status), uint8(CurveGaugeLister.Status.Active), "no state change");
        assertEq(lister.getListing(gauge).remaining, FEE, "no transfer success");
        assertEq(token.balanceOf(address(fd)), 0, "no tokens to a killed destination");
        assertEq(lister.totalEscrow(), FEE, "liability intact");

        // Restoring a healthy fixture with the gauge flag still true works.
        fd.setKilled(false);
        assertTrue(MockGauge(gauge).is_killed(), "flag still true");
        // auditfix001 §3: advance within the listing epoch to an eligible
        // accounting time before the successful retry.
        vm.warp(lister.getListing(gauge).listingEpoch + 86401);
        vm.prank(stranger);
        assertEq(lister.confiscate(gauge), FEE, "retry succeeds");
        assertEq(token.balanceOf(address(fd)), FEE, "FD holds it now");
    }

    // ---------------------------------------------------------------
    // Adversarial / safety
    // ---------------------------------------------------------------

    function test_AdapterCannotReenterListingReleaseOrConfiscation() public {
        (, address gauge1) = listFresh(0, 0);
        (, address gauge2) = listFresh(1, 0);

        // (a) reentrant release attempt during a funded deposit.
        votium.setReentry(address(lister), abi.encodeCall(CurveGaugeLister.checkpoint, (gauge1)));
        vm.warp(T0 + WEEK);
        (uint256 r,) = lister.checkpoint(gauge1);
        assertEq(r, QUARTER, "one legitimate quarter only");
        assertFalse(votium.reentrySucceeded(), "reentrant release blocked by guard");
        assertEq(lister.getListing(gauge1).epochsReleased, 1, "no extra counter bump");
        assertEq(votium.depositCount(), 1, "exactly one votium deposit");
        assertEq(voteMarket.depositCount(), 1, "exactly one voteMarket deposit");
        votium.setReentry(address(0), "");

        // (b) reentrant confiscation attempt.
        voteMarket.setReentry(address(lister), abi.encodeCall(CurveGaugeLister.confiscate, (gauge2)));
        vm.warp(T0 + WEEK);
        (r,) = lister.checkpoint(gauge2);
        assertEq(r, QUARTER, "quarter funds once");
        assertFalse(voteMarket.reentrySucceeded(), "reentrant confiscation blocked");
        assertEq(
            uint8(lister.getListing(gauge2).status),
            uint8(CurveGaugeLister.Status.Active),
            "no terminal flip via reentry"
        );
        voteMarket.setReentry(address(0), "");

        // (c) review1 finding 4: the non-vacuous contract-owner fixture. This
        // lister's owner IS the settlement adapter contract. Each owner call
        // below is first demonstrated to SUCCEED through the adapter outside
        // settlement (correctly authenticated metadata, funded payer for the
        // paid path), then shown to FAIL when injected inside a funded
        // deposit — the guard, not authorization or argument shape, blocks it.
        // (Malformed/unprivileged owner-call reentry duplicates were cut by
        // the lean audit: the valid funded contract-owner callbacks below
        // remain.)
        _buildAdapterOwnerFixture();
        _ownerCallsSucceedOutsideSettlement();
        _ownerCallsBlockedInsideSettlement();
    }

    // Contract-owner fixture state (stack-depth relief for the (d) scenario).
    MockERC20 internal tokenB;
    MockListingController internal controllerB;
    MockFeeDistributor internal fdB;
    MockIncentivePlatform internal marketB;
    ContractOwnerAdapter internal ownerAdapter;
    CurveGaugeLister internal listerB;
    address internal ownerPoolFree;
    address internal ownerGaugeFree;
    address internal ownerPoolPaid;
    address internal ownerGaugePaid;
    uint256 internal ownerAdapterBalPaid;
    address internal ownerPoolLive;
    address internal ownerGaugeLive;

    function _buildAdapterOwnerFixture() internal {
        tokenB = new MockERC20(18);
        controllerB = new MockListingController(controllerDao, int128(2));
        fdB = new MockFeeDistributor(address(tokenB), fdAdmin, T0);
        marketB = new MockIncentivePlatform(address(tokenB));
        ownerAdapter = new ContractOwnerAdapter(address(tokenB));
        vm.chainId(1);
        listerB = new CurveGaugeLister(
            address(ownerAdapter),
            address(tokenB),
            address(controllerB),
            address(fdB),
            CurveGaugeLister.AdmissionConfig(address(registry), 8),
            CurveGaugeLister.PlatformConfig(address(ownerAdapter), address(marketB), 5000),
            address(new AlwaysTrueTrustedValidator())
        );
        vm.prank(controllerDao);
        controllerB.setLister(address(listerB));
        ownerAdapter.setLister(address(listerB));
        marketB.setLister(address(listerB));
        // Owner unpause after binding (V1ALIGN §1.3): the owner here IS the
        // contract adapter; the retained callback-path assertions below stay
        // intact.
        vm.prank(address(ownerAdapter));
        listerB.setPaused(false);
        tokenB.mint(payer, 10 * FEE);
        vm.startPrank(payer);
        tokenB.approve(address(listerB), type(uint256).max);
        vm.stopPrank();
        // The adapter, as owner AND as a funded payer for its own paid-path
        // attempts, carries its own tokens and approval.
        tokenB.mint(address(ownerAdapter), 2 * FEE);
        ownerAdapter.approveToken(address(tokenB), address(listerB), type(uint256).max);
    }

    function _ownerCallsSucceedOutsideSettlement() internal {
        assertTrue(
            ownerAdapter.fireCallback(address(listerB), abi.encodeCall(CurveGaugeLister.setPaused, (true))),
            "contract owner pauses outside settlement"
        );
        assertTrue(listerB.paused(), "pause applied outside settlement");
        assertTrue(
            ownerAdapter.fireCallback(address(listerB), abi.encodeCall(CurveGaugeLister.setPaused, (false))),
            "contract owner unpauses outside settlement"
        );
        assertFalse(listerB.paused(), "unpause applied outside settlement");

        (ownerPoolFree, ownerGaugeFree,) = deployAuthenticatedPool(3, 0);
        assertTrue(
            ownerAdapter.fireCallback(
                address(listerB),
                abi.encodeCall(CurveGaugeLister.listGaugeNoEscrow, (ownerPoolFree, ownerGaugeFree, 0, 3, 2))
            ),
            "contract owner free-lists outside settlement with authenticated metadata"
        );
        assertEq(
            uint8(listerB.getListing(ownerGaugeFree).status),
            uint8(CurveGaugeLister.Status.DaoExempt),
            "free record created outside"
        );

        (ownerPoolPaid, ownerGaugePaid,) = deployAuthenticatedPool(4, 0);
        ownerAdapterBalPaid = tokenB.balanceOf(address(ownerAdapter));
        assertTrue(
            ownerAdapter.fireCallback(
                address(listerB), abi.encodeCall(CurveGaugeLister.listGauge, (ownerPoolPaid, ownerGaugePaid, 0, 4))
            ),
            "funded paid listing succeeds outside settlement"
        );
        assertEq(
            uint8(listerB.getListing(ownerGaugePaid).status),
            uint8(CurveGaugeLister.Status.Active),
            "paid record created outside"
        );
        assertEq(tokenB.balanceOf(address(ownerAdapter)), ownerAdapterBalPaid - FEE, "adapter paid its own fee outside");

        // The gauge that will settle while owner callbacks are injected.
        (ownerPoolLive, ownerGaugeLive,) = deployAuthenticatedPool(5, 0);
        vm.prank(payer);
        listerB.listGauge(ownerPoolLive, ownerGaugeLive, 0, 5);
    }

    function _ownerCallsBlockedInsideSettlement() internal {
        uint256 tLive = listerB.getListing(ownerGaugeLive).listingEpoch;

        ownerAdapter.setReentry(address(listerB), abi.encodeCall(CurveGaugeLister.setPaused, (true)));
        vm.warp(tLive + WEEK);
        (uint256 rOwn,) = listerB.checkpoint(ownerGaugeLive);
        assertEq(rOwn, QUARTER, "quarter one funds while owner callback fails internally");
        assertFalse(ownerAdapter.reentrySucceeded(), "owner setPaused blocked inside settlement");
        assertFalse(listerB.paused(), "pause untouched by blocked owner callback");
        ownerAdapter.setReentry(address(0), "");

        (address poolFree2, address gaugeFree2,) = deployAuthenticatedPool(6, 0);
        ownerAdapter.setReentry(
            address(listerB), abi.encodeCall(CurveGaugeLister.listGaugeNoEscrow, (poolFree2, gaugeFree2, 0, 6, 2))
        );
        vm.warp(tLive + 2 * WEEK);
        (rOwn,) = listerB.checkpoint(ownerGaugeLive);
        assertEq(rOwn, QUARTER, "quarter two funds");
        assertFalse(ownerAdapter.reentrySucceeded(), "owner free-listing blocked inside settlement");
        assertEq(
            uint8(listerB.getListing(gaugeFree2).status),
            uint8(CurveGaugeLister.Status.Unlisted),
            "no reentrant free record"
        );
        assertEq(controllerB.addCalls(), 3, "blocked free listing added nothing (2 outside + live)");
        ownerAdapter.setReentry(address(0), "");

        (address poolPaid2, address gaugePaid2,) = deployAuthenticatedPool(7, 0);
        uint256 adapterBalIn = tokenB.balanceOf(address(ownerAdapter));
        uint256 listerBBalIn = tokenB.balanceOf(address(listerB));
        ownerAdapter.setReentry(
            address(listerB), abi.encodeCall(CurveGaugeLister.listGauge, (poolPaid2, gaugePaid2, 0, 7))
        );
        vm.warp(tLive + 3 * WEEK);
        (rOwn,) = listerB.checkpoint(ownerGaugeLive);
        assertEq(rOwn, QUARTER, "quarter three funds");
        assertFalse(ownerAdapter.reentrySucceeded(), "funded owner paid-listing blocked inside settlement");
        assertEq(
            uint8(listerB.getListing(gaugePaid2).status),
            uint8(CurveGaugeLister.Status.Unlisted),
            "no reentrant paid record"
        );
        // Only the legitimate quarter-three flow moved tokens: the adapter
        // gained exactly its deposit share and the lister lost exactly one
        // quarter. The blocked paid listing added no FEE movement.
        assertEq(
            tokenB.balanceOf(address(ownerAdapter)),
            adapterBalIn + QUARTER / 2,
            "blocked paid listing moved no fee (adapter only its deposit share)"
        );
        assertEq(
            tokenB.balanceOf(address(listerB)),
            listerBBalIn - QUARTER,
            "no fee entered under the guard (only the quarter released)"
        );
        ownerAdapter.setReentry(address(0), "");

        // Control: with no callback the settlement path itself is healthy.
        vm.warp(tLive + 4 * WEEK);
        (rOwn,) = listerB.checkpoint(ownerGaugeLive);
        assertEq(rOwn, QUARTER, "final quarter funds");
        assertEq(
            uint8(listerB.getListing(ownerGaugeLive).status), uint8(CurveGaugeLister.Status.Exhausted), "exhausted"
        );
        // Exact custody accounting of the whole fixture: listerB holds only
        // the never-settled outside listing's FEE; the adapter holds its
        // undeployed 2 FEE minus the FEE it paid to list, plus four half
        // quarters; marketB holds the complementary half quarters.
        assertEq(tokenB.balanceOf(address(listerB)), FEE, "listerB keeps only the outside paid listing escrow");
        assertEq(tokenB.balanceOf(address(ownerAdapter)), (3 * FEE) / 2, "adapter custody exact");
        assertEq(tokenB.balanceOf(address(marketB)), FEE / 2, "marketB custody exact");
    }

    function test_TokenFalseReturnEmptyReturnAndTransferTax() public {
        // (a) false-return transfer is rejected atomically.
        token.setTransferBehavior(0, true, false);
        (address poolA, address gaugeA,) = deployAuthenticatedPool(0, 0);
        uint256 payerBefore = token.balanceOf(payer);
        listPaidRevert(poolA, gaugeA, 0);
        assertEq(token.balanceOf(payer), payerBefore, "false-return: fee not taken");
        assertEq(
            uint8(lister.getListing(gaugeA).status), uint8(CurveGaugeLister.Status.Unlisted), "false-return: no record"
        );
        token.setTransferBehavior(0, false, false);

        // (b) fee-on-transfer receipt is rejected (delta != FEE), atomically.
        token.setTransferBehavior(100, false, false); // burns 1% on every move
        (address poolB, address gaugeB,) = deployAuthenticatedPool(1, 0);
        payerBefore = token.balanceOf(payer);
        listPaidRevert(poolB, gaugeB, 1);
        assertEq(token.balanceOf(payer), payerBefore, "taxed receipt rolled back");
        assertEq(token.balanceOf(address(lister)), 0, "lister holds nothing from taxed receipt");
        assertEq(
            uint8(lister.getListing(gaugeB).status), uint8(CurveGaugeLister.Status.Unlisted), "taxed receipt no record"
        );
        assertEq(lister.totalEscrow(), 0, "taxed receipt no escrow");
        token.setTransferBehavior(0, false, false);

        // (c) empty-return transfers are supported (accepted with real deltas).
        token.setTransferBehavior(0, false, true);
        (address poolC, address gaugeC,) = deployAuthenticatedPool(2, 0);
        listPaidAt(poolC, gaugeC, 0, 2);
        assertEq(uint8(lister.getListing(gaugeC).status), uint8(CurveGaugeLister.Status.Active), "empty-return listed");
        assertEq(token.balanceOf(address(lister)), FEE, "empty-return fee held");
        token.setTransferBehavior(0, false, false);

        // (d) taxed OUTBOUND confiscation delta is rejected; terminal state
        // and transfer only persist together.
        (, address gaugeD) = listFresh(3, 0);
        killGauge(gaugeD);
        token.setTransferBehavior(50, false, false); // 0.5% tax on outbound
        vm.prank(stranger);
        vm.expectRevert();
        lister.confiscate(gaugeD);
        assertEq(
            uint8(lister.getListing(gaugeD).status), uint8(CurveGaugeLister.Status.Active), "no partial accounting"
        );
        assertEq(lister.getListing(gaugeD).remaining, FEE, "remaining preserved");
        assertEq(lister.totalEscrow(), 2 * FEE, "escrow preserved (C and D)");
        assertEq(token.balanceOf(address(fd)), 0, "no confiscation success");
        token.setTransferBehavior(0, false, false);
        // auditfix001 §3: advance within the listing epoch to an eligible
        // accounting time; the original maturities and kill coverage are
        // unchanged (the kill happened in the listing epoch, dues stay 0).
        vm.warp(lister.getListing(gaugeD).listingEpoch + 86401);
        vm.prank(stranger);
        assertEq(lister.confiscate(gaugeD), FEE, "clean retry confiscates");
        assertEq(token.balanceOf(address(fd)), FEE, "FD custody after retry");

        // (e) false-return on the PLATFORM SETTLEMENT pull (release, not just
        // confiscation): the mock's SafeToken pull rejects false returns, so
        // the whole checkpoint must revert with nothing recorded.
        (, address gaugeE) = listFresh(4, 0);
        token.setTransferBehavior(0, true, false);
        uint256 maturityE = lister.getListing(gaugeE).listingEpoch + WEEK;
        vm.warp(maturityE);
        uint256 listerBeforeE = token.balanceOf(address(lister));
        vm.expectRevert();
        lister.checkpoint(gaugeE);
        CurveGaugeLister.Listing memory recE = lister.getListing(gaugeE);
        assertEq(uint256(recE.epochsReleased), 0, "false-return release: no counter");
        assertEq(recE.released, 0, "false-return release: no released");
        assertEq(recE.remaining, FEE, "false-return release: remaining intact");
        assertEq(uint8(recE.status), uint8(CurveGaugeLister.Status.Active), "false-return release: still Active");
        assertEq(votium.depositCount(), 0, "false-return release: no votium receipts");
        assertEq(voteMarket.depositCount(), 0, "false-return release: no voteMarket receipts");
        assertEq(token.balanceOf(address(votium)), 0, "false-return release: votium unfunded");
        assertEq(token.balanceOf(address(voteMarket)), 0, "false-return release: voteMarket unfunded");
        assertEq(token.balanceOf(address(lister)), listerBeforeE, "false-return release: escrow intact");
        assertEq(token.allowance(address(lister), address(votium)), 0, "false-return release: no lingering approval");
        assertEq(token.allowance(address(lister), address(voteMarket)), 0, "false-return release: no approval 2");
        token.setTransferBehavior(0, false, false);
        (uint256 rE,) = lister.checkpoint(gaugeE);
        assertEq(rE, QUARTER, "false-return: clean retry funds");
        assertEq(token.balanceOf(address(votium)), QUARTER / 2, "false-return retry: votium exact funding");
        assertEq(token.balanceOf(address(voteMarket)), QUARTER / 2, "false-return retry: voteMarket exact funding");
        (uint256 amtE,,) = votium.getDeposit(gaugeE, maturityE);
        assertEq(token.balanceOf(address(votium)), amtE, "retry receipt face backed by custody");

        // (f) empty-return transfers are supported on the RELEASE path too
        // (normal mode): settlement succeeds with exact funding recorded.
        (, address gaugeF) = listFresh(5, 0);
        uint256 votiumBeforeF = token.balanceOf(address(votium));
        uint256 vmBeforeF = token.balanceOf(address(voteMarket));
        uint256 maturityF = lister.getListing(gaugeF).listingEpoch + WEEK;
        token.setTransferBehavior(0, false, true);
        vm.warp(maturityF);
        (uint256 rF,) = lister.checkpoint(gaugeF);
        assertEq(rF, QUARTER, "empty-return release funds");
        assertEq(
            token.balanceOf(address(votium)),
            votiumBeforeF + QUARTER / 2,
            "empty-return: votium custody equals prior plus this receipt"
        );
        assertEq(
            token.balanceOf(address(voteMarket)),
            vmBeforeF + QUARTER / 2,
            "empty-return: voteMarket custody equals its recorded receipts"
        );
        (uint256 amtFV, uint256 execFV, bytes32 recFV) = votium.getDeposit(gaugeF, maturityF);
        assertEq(amtFV, QUARTER / 2, "empty-return votium face");
        assertEq(execFV, maturityF, "empty-return votium execution epoch");
        assertTrue(recFV != bytes32(0), "empty-return votium receipt");
        (uint256 amtFM, uint256 execFM, bytes32 recFM) = voteMarket.getDeposit(gaugeF, maturityF);
        assertEq(amtFM, QUARTER / 2, "empty-return voteMarket face");
        assertEq(execFM, maturityF, "empty-return voteMarket execution epoch");
        assertTrue(recFM != bytes32(0), "empty-return voteMarket receipt");
        token.setTransferBehavior(0, false, false);

        // (g) taxed OUTBOUND transfer on platform funding: the mock must reject
        // a pull whose delivery falls short of the recorded receipt face, so
        // the checkpoint rolls back completely (no full-face unfunded receipt).
        (, address gaugeG) = listFresh(6, 0);
        uint256 listerBeforeG = token.balanceOf(address(lister));
        uint256 custBeforeG = token.balanceOf(address(votium)) + token.balanceOf(address(voteMarket));
        uint256 cntBeforeG = votium.depositCount() + voteMarket.depositCount();
        uint256 maturityG = lister.getListing(gaugeG).listingEpoch + WEEK;
        token.setTransferBehavior(100, false, false); // burns 1% on every move
        vm.warp(maturityG);
        vm.expectRevert();
        lister.checkpoint(gaugeG);
        CurveGaugeLister.Listing memory recG = lister.getListing(gaugeG);
        assertEq(uint256(recG.epochsReleased), 0, "taxed release: no counter");
        assertEq(recG.released, 0, "taxed release: no released");
        assertEq(recG.remaining, FEE, "taxed release: remaining intact");
        assertEq(uint8(recG.status), uint8(CurveGaugeLister.Status.Active), "taxed release: still Active");
        assertEq(token.balanceOf(address(lister)), listerBeforeG, "taxed release: escrow intact");
        assertEq(
            token.balanceOf(address(votium)) + token.balanceOf(address(voteMarket)),
            custBeforeG,
            "taxed release: no underfunded custody accepted"
        );
        assertEq(votium.depositCount() + voteMarket.depositCount(), cntBeforeG, "taxed release: no receipts");
        assertEq(lister.totalEscrow(), token.balanceOf(address(lister)), "taxed release: liability matches custody");
        token.setTransferBehavior(0, false, false);
        (uint256 rG,) = lister.checkpoint(gaugeG);
        assertEq(rG, QUARTER, "taxed release: clean retry funds");
        assertEq(
            token.balanceOf(address(votium)) + token.balanceOf(address(voteMarket)),
            custBeforeG + QUARTER,
            "taxed release: retry fully funds"
        );

        // (h) review1 finding 1 tail / review2 finding 3: FALSE-RETURN
        // confiscation. The matrix must cover outbound confiscation, not only
        // release. A killed gauge with one previously funded quarter must
        // roll back completely when the confiscation transfer returns false:
        // no terminal state, exact remaining liability kept, prior platform
        // funding untouched, and a clean retry afterwards.
        (, address gaugeH) = listFresh(7, 0);
        uint256 maturityH = lister.getListing(gaugeH).listingEpoch + WEEK;
        vm.warp(maturityH);
        (uint256 rH,) = lister.checkpoint(gaugeH);
        assertEq(rH, QUARTER, "false-return confiscation: one quarter funded first");
        killGauge(gaugeH);
        uint256 fdBeforeH = token.balanceOf(address(fd));
        uint256 platformBeforeH = token.balanceOf(address(votium)) + token.balanceOf(address(voteMarket));
        uint256 escrowBeforeH = lister.totalEscrow();
        uint256 releasedH = lister.getListing(gaugeH).released;
        token.setTransferBehavior(0, true, false); // false-return outbound
        vm.prank(stranger);
        vm.expectRevert();
        lister.confiscate(gaugeH);
        CurveGaugeLister.Listing memory recH = lister.getListing(gaugeH);
        assertEq(
            uint8(recH.status), uint8(CurveGaugeLister.Status.Active), "false-return confiscation: no terminal state"
        );
        assertEq(recH.remaining, FEE - QUARTER, "false-return confiscation: liability intact");
        assertEq(recH.confiscated, 0, "false-return confiscation: no partial accounting");
        assertEq(uint256(recH.epochsReleased), 1, "false-return confiscation: paid quarter untouched");
        assertEq(recH.released, releasedH, "false-return confiscation: release ledger untouched");
        assertEq(token.balanceOf(address(fd)), fdBeforeH, "false-return confiscation: FD unfunded");
        assertEq(
            token.balanceOf(address(votium)) + token.balanceOf(address(voteMarket)),
            platformBeforeH,
            "false-return confiscation: prior platform funding untouched"
        );
        assertEq(lister.totalEscrow(), escrowBeforeH, "false-return confiscation: escrow intact");
        assertEq(token.balanceOf(address(lister)), escrowBeforeH, "false-return confiscation: custody intact");
        token.setTransferBehavior(0, false, false);
        vm.prank(stranger);
        assertEq(lister.confiscate(gaugeH), FEE - QUARTER, "false-return confiscation: clean retry seizes remainder");
        recH = lister.getListing(gaugeH);
        assertEq(
            uint8(recH.status), uint8(CurveGaugeLister.Status.Confiscated), "terminal only on the successful transfer"
        );
        assertEq(recH.remaining, 0, "liability moved exactly");
        assertEq(recH.confiscated, FEE - QUARTER, "confiscation ledger exact");
        assertEq(token.balanceOf(address(fd)), fdBeforeH + (FEE - QUARTER), "FD got exactly the remainder");
        assertEq(lister.totalEscrow(), escrowBeforeH - (FEE - QUARTER), "escrow credit released exactly");
        assertEq(
            token.balanceOf(address(votium)) + token.balanceOf(address(voteMarket)),
            platformBeforeH,
            "prior platform funding still untouched after retry"
        );

        // (i) review1 finding 1 tail / review2 finding 3: EMPTY-RETURN
        // confiscation executed WITH the empty-return behavior active (the
        // committed suite previously reset it before every confiscation).
        // Same posture as (h): one funded quarter, then a kill; the empty-
        // return outbound transfer is accepted with the exact delta.
        (, address gaugeI) = listFresh(8, 0);
        uint256 maturityI = lister.getListing(gaugeI).listingEpoch + WEEK;
        vm.warp(maturityI);
        (uint256 rI,) = lister.checkpoint(gaugeI);
        assertEq(rI, QUARTER, "empty-return confiscation: one quarter funded first");
        killGauge(gaugeI);
        uint256 fdBeforeI = token.balanceOf(address(fd));
        uint256 platformBeforeI = token.balanceOf(address(votium)) + token.balanceOf(address(voteMarket));
        uint256 escrowBeforeI = lister.totalEscrow();
        uint256 listerBalBeforeI = token.balanceOf(address(lister));
        token.setTransferBehavior(0, false, true); // empty-return OUTBOUND during confiscation
        vm.prank(stranger);
        assertEq(lister.confiscate(gaugeI), FEE - QUARTER, "empty-return confiscation pays exactly the remainder");
        token.setTransferBehavior(0, false, false);
        CurveGaugeLister.Listing memory recI = lister.getListing(gaugeI);
        assertEq(
            uint8(recI.status),
            uint8(CurveGaugeLister.Status.Confiscated),
            "empty-return: terminal state set on success"
        );
        assertEq(recI.remaining, 0, "empty-return: remaining liability moved exactly");
        assertEq(recI.confiscated, FEE - QUARTER, "empty-return: confiscation ledger exact");
        assertEq(recI.released, QUARTER, "empty-return: paid quarter unchanged");
        assertEq(uint256(recI.epochsReleased), 1, "empty-return: quarter counter unchanged");
        assertEq(token.balanceOf(address(fd)), fdBeforeI + (FEE - QUARTER), "empty-return: FD custody exact");
        assertEq(listerBalBeforeI - token.balanceOf(address(lister)), FEE - QUARTER, "empty-return: escrow debit exact");
        assertEq(lister.totalEscrow(), escrowBeforeI - (FEE - QUARTER), "empty-return: escrow credit exact");
        assertEq(
            token.balanceOf(address(votium)) + token.balanceOf(address(voteMarket)),
            platformBeforeI,
            "empty-return: prior platform funding untouched"
        );
    }

    function listPaidRevert(address pool, address gauge, uint256 handlerId) internal {
        vm.prank(payer);
        vm.expectRevert();
        lister.listGauge(pool, gauge, 0, handlerId);
    }

    // ---------------------------------------------------------------
    // auditfix001 §6 — offline accounting and rollback regressions
    // ---------------------------------------------------------------

    /// @dev auditfix001 §6 item 1 / V-M01: the audit's 40-week-stale
    /// distributor scenario. A week-aligned cursor with zero unaccounted FD
    /// balance and a 10,000-token paid escrow under an actual kill flag
    /// reverts DistributorUnusable on BOTH settlement entrypoints BEFORE any
    /// transfer, with everything conserved (a second live escrow stays in the
    /// conservation assertions). A separate raw-model control without core
    /// protection proves direct funding after the gap allocates only FEE/2
    /// and a later successful checkpoint cannot repair it — the mock has not
    /// been made falsely forgiving. A zero-delta checkpointFees refresh then
    /// advances the cursor losslessly; immediate and exactly +86400 retries
    /// revert; at +86401 the DIRECT confiscation accounts the entire FEE
    /// (aligned recovery within one bucket) and becomes terminal.
    function test_AuditM01_StaleFortyWeekDistributorRevertsAndSafeRetryAllocatesAll() public {
        (, address donorGauge) = listFresh(1, 0); // second live escrow
        (, address gauge) = listFresh(0, 0);
        killGauge(gauge);
        vm.warp(T0 + 40 * WEEK);
        assertEq(fd.last_token_time(), T0, "week-aligned cursor from construction");
        assertEq(fd.token_last_balance(), token.balanceOf(address(fd)), "zero unaccounted FD balance");
        assertTrue(block.timestamp - lister.epochStart(fd.last_token_time()) > 20 * WEEK, "beyond the 20-week horizon");

        // Both entrypoints revert DistributorUnusable BEFORE the transfer.
        _expectSeizureRevertStateIntact(gauge, CurveGaugeLister.DistributorUnusable.selector, "40-week stale");
        assertEq(token.balanceOf(address(lister)), 2 * FEE, "core still holds both fees");
        assertEq(lister.getListing(donorGauge).remaining, FEE, "donor escrow conserved");
        assertEq(token.allowance(address(lister), address(votium)), 0, "no votium allowance");
        assertEq(token.allowance(address(lister), address(voteMarket)), 0, "no voteMarket allowance");

        // Raw-model control, no core protection: funding the raw FD after the
        // 40-week gap allocates only 20 of 40 weeks (FEE/2) and consumes the
        // full delta — the tail is discarded forever.
        MockFeeDistributor rawFd = new MockFeeDistributor(address(token), fdAdmin, T0);
        token.mint(address(rawFd), FEE);
        vm.prank(fdAdmin);
        rawFd.checkpoint_token();
        assertEq(_sumBuckets(rawFd, T0, 20), FEE / 2, "raw model allocates only half");
        assertEq(_sumBuckets(rawFd, T0 + 20 * WEEK, 20), 0, "tail weeks get nothing");
        assertEq(rawFd.token_last_balance(), FEE, "raw full delta consumed");

        // Separate ZERO-DELTA refresh: custody stays in the core, no fee is
        // allocated, the cursor advances to now.
        vm.prank(stranger);
        assertTrue(lister.checkpointFees(), "zero-delta refresh succeeds");
        assertEq(fd.last_token_time(), T0 + 40 * WEEK, "cursor advanced to now");
        assertEq(fd.token_last_balance(), 0, "no fee allocated by the refresh");
        assertEq(token.balanceOf(address(lister)), 2 * FEE, "custody stays in core");

        // Immediate and exactly +86400 retries revert (strict cooldown).
        vm.prank(stranger);
        vm.expectRevert(MockFeeDistributor.CannotCheckpoint.selector);
        lister.confiscate(gauge);
        vm.warp(T0 + 40 * WEEK + 86400);
        vm.expectRevert(MockFeeDistributor.CannotCheckpoint.selector);
        lister.confiscate(gauge);
        assertEq(uint8(lister.getListing(gauge).status), uint8(CurveGaugeLister.Status.Active), "still Active");
        assertEq(token.balanceOf(address(fd)), 0, "still no FD custody");

        // The raw model's later successful checkpoint cannot repair its loss.
        vm.prank(fdAdmin);
        rawFd.checkpoint_token();
        assertEq(_sumBuckets(rawFd, T0, 20), FEE / 2, "raw retry adds none of the omitted half");

        // At +86401 the direct confiscation accounts the ENTIRE fee — this
        // aligned recovery case stays within one bucket.
        vm.warp(T0 + 40 * WEEK + 86401);
        vm.prank(stranger);
        uint256 seized = lister.confiscate(gauge);
        assertEq(seized, FEE, "entire fee seized");
        assertEq(fd.tokens_per_week(T0 + 40 * WEEK), FEE, "single-bucket full allocation");
        assertEq(fd.last_token_time(), block.timestamp, "cursor accounted to now");
        assertEq(fd.token_last_balance(), FEE, "full custody accounted");
        assertEq(token.balanceOf(address(fd)), FEE, "FD holds the fee");
        CurveGaugeLister.Listing memory rec = lister.getListing(gauge);
        assertEq(uint8(rec.status), uint8(CurveGaugeLister.Status.Confiscated), "terminal");
        assertEq(rec.confiscated, FEE, "terminal ledger");
        assertEq(lister.totalEscrow(), FEE, "donor liability remains");
        assertEq(lister.getListing(donorGauge).remaining, FEE, "donor escrow still conserved");
        assertEq(lister.confiscate(gauge), 0, "cannot pay again");
    }

    function _sumBuckets(MockFeeDistributor fdx, uint256 start, uint256 weeksCount) internal view returns (uint256 s) {
        for (uint256 i = 0; i < weeksCount; ++i) {
            s += fdx.tokens_per_week(start + i * WEEK);
        }
    }

    // Storage-backed horizon-fixture fields (stack-depth relief only).
    MockFeeDistributor internal hFd_;
    MockIncentivePlatform internal hV_;
    MockIncentivePlatform internal hM_;
    MockListingController internal hC_;
    CurveGaugeLister internal hL_;
    address internal hGauge_;

    /// @dev auditfix001 §6 item 2: the accounting horizon includes the
    /// partial first week. For cursor offsets 0, 1 and WEEK-1 from a positive
    /// week boundary, H-1 and H account successfully (bucket increments equal
    /// the exact upstream integer allocation formula) while H+1 reverts
    /// before the transfer — including the near-end-of-week cursor where
    /// now - t < 20*WEEK is nevertheless unsafe, because the horizon is
    /// keyed to epochStart(t), not t.
    function test_AuditM01_AccountingHorizonIncludesPartialWeekEdges() public {
        uint256[3] memory offsets = [uint256(0), uint256(1), WEEK - 1];
        uint256[3] memory bases = [T0 + 10 * WEEK, T0 + 40 * WEEK, T0 + 70 * WEEK];
        for (uint256 oi = 0; oi < 3; ++oi) {
            uint256 cursor = bases[oi] + offsets[oi];
            uint256 h = (cursor / WEEK) * WEEK + 20 * WEEK;
            // H-1 and H account successfully.
            _horizonProbe(cursor, h - 1, true);
            _horizonProbe(cursor, h, true);
            // H+1 reverts before the transfer. For the near-end-of-week
            // cursor the naive span check now - t < 20*WEEK would ACCEPT
            // H+1 (19W+2 < 20W); the horizon keyed to epochStart(t) is what
            // rejects it.
            if (oi == 2) {
                assertTrue(h + 1 - cursor < 20 * WEEK, "near-end span is below 20 weeks");
            }
            _horizonProbe(cursor, h + 1, false);
        }
    }

    /// @dev One independent fixture per (cursor, when) probe: fresh FD with
    /// the raw cursor override, fresh bound platforms/controller/core, paid
    /// listing, genuine kill flag, then permissionless confiscation at
    /// `when`.
    function _horizonProbe(uint256 cursor, uint256 when, bool expectOk) internal {
        hFd_ = new MockFeeDistributor(address(token), fdAdmin, T0);
        hFd_.setLastTokenTime(cursor);
        hV_ = new MockIncentivePlatform(address(token));
        hM_ = new MockIncentivePlatform(address(token));
        hC_ = new MockListingController(controllerDao, int128(2));
        vm.chainId(1);
        hL_ = new CurveGaugeLister(
            daoOwner,
            address(token),
            address(hC_),
            address(hFd_),
            CurveGaugeLister.AdmissionConfig(address(registry), 8),
            CurveGaugeLister.PlatformConfig(address(hV_), address(hM_), 5000),
            address(new AlwaysTrueTrustedValidator())
        );
        vm.prank(controllerDao);
        hC_.setLister(address(hL_));
        hV_.setLister(address(hL_));
        hM_.setLister(address(hL_));
        // Owner unpause after binding (V1ALIGN §1.3 fixture wiring).
        vm.prank(daoOwner);
        hL_.setPaused(false);
        vm.startPrank(payer);
        token.approve(address(hL_), FEE);
        vm.stopPrank();
        (address pool, address gauge,) = deployAuthenticatedPool(0, 0);
        hGauge_ = gauge;
        vm.prank(payer);
        hL_.listGauge(pool, gauge, 0, 0);
        MockGauge(gauge).setKilled(true);

        vm.warp(when);
        if (!expectOk) {
            uint256 fdBal = token.balanceOf(address(hFd_));
            vm.prank(stranger);
            vm.expectRevert(CurveGaugeLister.DistributorUnusable.selector);
            hL_.confiscate(gauge);
            assertEq(uint8(hL_.getListing(gauge).status), uint8(CurveGaugeLister.Status.Active), "H+1: not terminal");
            assertEq(token.balanceOf(address(hFd_)), fdBal, "H+1: reverted before transfer");
            assertEq(hFd_.last_token_time(), cursor, "H+1: cursor untouched");
            assertEq(hFd_.token_last_balance(), 0, "H+1: nothing accounted");
            return;
        }
        vm.prank(stranger);
        uint256 seized = hL_.confiscate(gauge);
        assertEq(seized, FEE, "H-1/H: full fee seized");
        assertEq(hFd_.last_token_time(), when, "cursor accounted to now");
        assertEq(hFd_.token_last_balance(), FEE, "full custody accounted");
        assertEq(token.balanceOf(address(hFd_)), FEE, "FD custody");
        assertEq(uint8(hL_.getListing(gauge).status), uint8(CurveGaugeLister.Status.Confiscated), "terminal");
        _assertUpstreamAllocation(hFd_, cursor, when, FEE);
    }

    /// @dev The exact deployed `_checkpoint_token` integer allocation: each
    /// week bucket receives total * (bucketEnd - cursor)/sinceLast with the
    /// same-timestamp special case, at most 20 iterations, tail discarded.
    function _assertUpstreamAllocation(MockFeeDistributor fdx, uint256 t, uint256 nowTime, uint256 total)
        internal
        view
    {
        uint256 sinceLast = nowTime - t;
        uint256 cur = t;
        uint256 week = (t / WEEK) * WEEK;
        for (uint256 i = 0; i < 20; ++i) {
            uint256 nextWeek = week + WEEK;
            uint256 share;
            if (nowTime < nextWeek) {
                share = (sinceLast == 0 && nowTime == t) ? total : (total * (nowTime - cur)) / sinceLast;
            } else {
                share = (sinceLast == 0 && nextWeek == t) ? total : (total * (nextWeek - cur)) / sinceLast;
            }
            assertEq(fdx.tokens_per_week(week), share, "upstream integer allocation exact");
            if (nowTime < nextWeek) break;
            cur = nextWeek;
            week = nextWeek;
        }
    }

    /// @dev auditfix001 §6 item 3: zero/future cursor, cursor-getter
    /// revert/short return, disabled public checkpointing, a normally
    /// returning no-op checkpoint and a cursor-only checkpoint all revert
    /// with escrow preserved — the cursor-only false success is caught by the
    /// accounted-balance postcheck. Restoring normal behavior allows exactly
    /// one successful retry. All admission/kill/token/cooldown prerequisites
    /// are arranged so each intended guard is the one reached.
    function test_AuditM01_InvalidCursorAndIncompleteCheckpointRevert() public {
        (, address gauge) = listFresh(0, 0);
        killGauge(gauge);
        vm.warp(T0 + 2 * WEEK); // cooldown-eligible against the T0 cursor
        assertTrue(block.timestamp > fd.last_token_time() + 86400, "public path otherwise eligible");
        assertTrue(block.timestamp - lister.epochStart(fd.last_token_time()) <= 20 * WEEK, "otherwise fresh");

        // Zero cursor.
        fd.setLastTokenTime(0);
        _expectSeizureRevertStateIntact(gauge, CurveGaugeLister.DistributorUnusable.selector, "zero cursor");
        fd.setLastTokenTime(T0);

        // Future cursor.
        fd.setLastTokenTime(block.timestamp + WEEK);
        _expectSeizureRevertStateIntact(gauge, CurveGaugeLister.DistributorUnusable.selector, "future cursor");
        fd.setLastTokenTime(T0);

        // Cursor getter revert propagates. (The shared snapshot helper reads
        // the cursor, so this cell asserts preservation inline.)
        fd.setCursorReadMode(1);
        {
            uint256 listerBalR = token.balanceOf(address(lister));
            uint256 fdBalR = token.balanceOf(address(fd));
            vm.prank(stranger);
            vm.expectRevert(MockFeeDistributor.CursorReadFailed.selector);
            lister.confiscate(gauge);
            vm.expectRevert(MockFeeDistributor.CursorReadFailed.selector);
            lister.checkpoint(gauge);
            assertEq(token.balanceOf(address(lister)), listerBalR, "getter revert: core custody intact");
            assertEq(token.balanceOf(address(fd)), fdBalR, "getter revert: FD custody intact");
            assertEq(
                uint8(lister.getListing(gauge).status), uint8(CurveGaugeLister.Status.Active), "getter revert: Active"
            );
            assertEq(fd.checkpointCalls(), 0, "getter revert: no accounting pass");
        }
        fd.setCursorReadMode(0);

        // Cursor getter short return: ABI-decode failure reverts; same
        // complete preservation. (Restore the mode before reading the real
        // cursor back.)
        fd.setCursorReadMode(2);
        uint256 listerBal = token.balanceOf(address(lister));
        uint256 fdBal = token.balanceOf(address(fd));
        vm.prank(stranger);
        vm.expectRevert();
        lister.confiscate(gauge);
        fd.setCursorReadMode(0);
        assertEq(token.balanceOf(address(lister)), listerBal, "short cursor: core custody intact");
        assertEq(token.balanceOf(address(fd)), fdBal, "short cursor: FD custody intact");
        assertEq(uint8(lister.getListing(gauge).status), uint8(CurveGaugeLister.Status.Active), "short cursor: Active");
        assertEq(fd.last_token_time(), T0, "short cursor: real cursor untouched");
        fd.setCursorReadMode(0);

        // Disabled public checkpointing: the inner call reverts and the whole
        // confiscation follows.
        fd.setCanCheckpoint(false);
        _expectSeizureRevertStateIntact(gauge, MockFeeDistributor.CannotCheckpoint.selector, "public path disabled");
        fd.setCanCheckpoint(true);

        // Normally returning no-op checkpoint: postcheck catches the
        // un-advanced cursor.
        fd.setCheckpointMode(1);
        _expectSeizureRevertStateIntact(gauge, CurveGaugeLister.DistributorUnusable.selector, "no-op checkpoint");
        fd.setCheckpointMode(0);

        // Cursor-only checkpoint: the cursor postcheck passes, the
        // accounted-balance postcheck catches the false success.
        fd.setCheckpointMode(2);
        _expectSeizureRevertStateIntact(gauge, CurveGaugeLister.DistributorUnusable.selector, "cursor-only checkpoint");
        fd.setCheckpointMode(0);

        // Restored normal behavior: exactly one successful retry.
        vm.prank(stranger);
        assertEq(lister.confiscate(gauge), FEE, "restored fixture seizes");
        assertEq(fd.last_token_time(), block.timestamp, "cursor accounted to now");
        assertEq(fd.token_last_balance(), FEE, "full accounting");
        assertEq(uint8(lister.getListing(gauge).status), uint8(CurveGaugeLister.Status.Confiscated), "terminal");
        assertEq(lister.confiscate(gauge), 0, "exactly once");
    }

    // Storage-backed auditfix001 §6 item-4 fixture (stack-depth relief).
    MockListingController internal ctlM_;
    MockFeeDistributor internal fdM_;
    MockIncentivePlatform internal pvM_;
    MockIncentivePlatform internal pmM_;
    CurveGaugeLister internal listerM_;
    address internal poolM_;
    address internal gaugeM_;

    /// @dev auditfix001 §6 item 4: a complete first quarter funds inside a
    /// catch-up checkpoint, then the flag flips true before a later quarter
    /// while FD accounting is injected to fail. The WHOLE enclosing
    /// checkpoint rolls back: earlier receipts, token movements, ledger,
    /// allowances and the callback's own kill write. (The existing healthy
    /// test_KilledFlagTrueAtMaturityStopsMidCatchUp still proves a successful
    /// seizure commits the earlier quarter and confiscates only the
    /// remainder.)
    function test_AuditM01_MidCatchUpAccountingFailureRollsBackEarlierQuarter() public {
        ctlM_ = new MockListingController(controllerDao, int128(2));
        fdM_ = new MockFeeDistributor(address(token), fdAdmin, T0);
        pvM_ = new MockIncentivePlatform(address(token));
        pmM_ = new MockIncentivePlatform(address(token));
        vm.chainId(1);
        listerM_ = new CurveGaugeLister(
            daoOwner,
            address(token),
            address(ctlM_),
            address(fdM_),
            CurveGaugeLister.AdmissionConfig(address(registry), 8),
            CurveGaugeLister.PlatformConfig(address(pvM_), address(pmM_), 5000),
            address(new AlwaysTrueTrustedValidator())
        );
        vm.prank(controllerDao);
        ctlM_.setLister(address(listerM_));
        pvM_.setLister(address(listerM_));
        pmM_.setLister(address(listerM_));
        // Owner unpause after binding (V1ALIGN §1.3 fixture wiring).
        vm.prank(daoOwner);
        listerM_.setPaused(false);
        vm.startPrank(payer);
        token.approve(address(listerM_), type(uint256).max);
        vm.stopPrank();
        (poolM_, gaugeM_,) = deployAuthenticatedPool(4, 0);
        vm.prank(payer);
        listerM_.listGauge(poolM_, gaugeM_, 0, 4);
        uint256 tK = listerM_.getListing(gaugeM_).listingEpoch;

        // The kill fires from quarter one's final-endpoint callback; FD
        // accounting is injected to fail when the seizure runs.
        DaoKillCallback killer = new DaoKillCallback();
        killer.arm(address(ctlM_), controllerDao);
        pmM_.setReentry(address(killer), abi.encodeCall(DaoKillCallback.killNow, (gaugeM_)));
        fdM_.setCheckpointRevert(true);

        vm.warp(tK + 2 * WEEK); // two quarters due in one checkpoint
        vm.expectRevert(MockFeeDistributor.CheckpointFailed.selector);
        listerM_.checkpoint(gaugeM_);

        // The WHOLE checkpoint rolled back, quarter one included.
        assertEq(pvM_.depositCount(), 0, "earlier votium receipt rolled back");
        assertEq(pmM_.depositCount(), 0, "earlier voteMarket receipt rolled back");
        assertEq(token.balanceOf(address(pvM_)) + token.balanceOf(address(pmM_)), 0, "platform custody rolled back");
        assertEq(token.balanceOf(address(listerM_)), FEE, "escrow untouched");
        assertEq(listerM_.totalEscrow(), FEE, "liability untouched");
        assertEq(token.balanceOf(address(fdM_)), 0, "no FD custody survived");
        assertEq(fdM_.last_token_time(), T0, "FD cursor untouched");
        assertEq(fdM_.token_last_balance(), 0, "FD accounting untouched");
        assertEq(fdM_.checkpointCalls(), 0, "no accounting pass survived");
        CurveGaugeLister.Listing memory rec = listerM_.getListing(gaugeM_);
        assertEq(uint8(rec.status), uint8(CurveGaugeLister.Status.Active), "still Active");
        assertEq(uint256(rec.epochsReleased), 0, "counter rolled back");
        assertEq(rec.released, 0, "released rolled back");
        assertEq(rec.remaining, FEE, "remaining rolled back");
        assertEq(token.allowance(address(listerM_), address(pvM_)), 0, "votium allowance rolled back");
        assertEq(token.allowance(address(listerM_), address(pmM_)), 0, "voteMarket allowance rolled back");
        assertFalse(MockGauge(gaugeM_).is_killed(), "callback kill write rolled back with the checkpoint");
        assertFalse(pmM_.reentrySucceeded(), "callback success flag rolled back");

        // Clearing the fault and the callback retries cleanly: both due
        // quarters fund (the flag write did not survive the revert).
        fdM_.setCheckpointRevert(false);
        pmM_.setReentry(address(0), "");
        (uint256 rM,) = listerM_.checkpoint(gaugeM_);
        assertEq(rM, 2 * QUARTER, "retry funds both due quarters");
        assertEq(pvM_.depositCount(), 2, "no duplicate funding");
        assertEq(token.balanceOf(address(fdM_)), 0, "release path touches no FD");
    }

    // ---------------------------------------------------------------
    // Kill at each release count (deterministic replacement for the retired
    // five-valued kill fuzz and the random mirrored-ledger driver)
    // ---------------------------------------------------------------

    /// @dev Deterministic replacement for the retired five-valued kill fuzz:
    /// every release count 0..4 is exercised exactly once on its own seeded
    /// listing. For each count: fund exactly that many quarters sequentially,
    /// kill via the gauge flag, then assert the exact returned seizure, the
    /// FD balance delta, prior funded amounts, the public accounting and the
    /// terminal status locally — no global mirror ledger.
    function test_KillAtEachReleaseCount() public {
        for (uint256 n = 0; n <= 4; ++n) {
            // Baselines before this iteration's gauge: platform custody and
            // receipt counts accumulate across the loop's independent gauges.
            uint256 platformBefore = token.balanceOf(address(votium)) + token.balanceOf(address(voteMarket));
            uint256 receiptsBefore = votium.depositCount() + voteMarket.depositCount();
            (, address gauge) = listFresh(0, 0);
            uint256 listingEpoch = lister.getListing(gauge).listingEpoch;
            for (uint256 k = 1; k <= n; ++k) {
                vm.warp(listingEpoch + k * WEEK);
                (uint256 r,) = lister.checkpoint(gauge);
                assertEq(r, QUARTER, "sequential funding");
            }
            uint256 platformTotal = token.balanceOf(address(votium)) + token.balanceOf(address(voteMarket));
            assertEq(platformTotal - platformBefore, n * QUARTER, "platforms hold prior quarters");
            assertEq(votium.depositCount() + voteMarket.depositCount() - receiptsBefore, 2 * n, "prior receipts exact");

            killGauge(gauge);
            if (n == 0) {
                // auditfix001 §3: advance WITHIN the listing epoch to an
                // eligible accounting time (kill coverage stays in-epoch,
                // elapsed stays 0).
                vm.warp(listingEpoch + 86401);
                assertEq(lister.epochsElapsed(gauge), 0, "count 0: still no dues at the seizure");
            }
            uint256 fdBefore = token.balanceOf(address(fd));
            uint256 escrowBefore = lister.totalEscrow();
            uint256 seized = lister.confiscate(gauge);
            assertEq(seized, FEE - n * QUARTER, "seize FEE minus released");
            assertEq(token.balanceOf(address(fd)), fdBefore + seized, "FD got exactly the unreleased");
            assertEq(
                token.balanceOf(address(votium)) + token.balanceOf(address(voteMarket)),
                platformTotal,
                "never touches previous platform money"
            );
            assertEq(lister.totalEscrow(), escrowBefore - seized, "liability cleared by the seizure");
            CurveGaugeLister.Listing memory rec = lister.getListing(gauge);
            assertEq(uint256(rec.epochsReleased), n, "counter unchanged by kill");
            assertEq(rec.released, n * QUARTER, "released unchanged by kill");
            assertEq(rec.remaining, 0, "remaining zero");
            assertEq(rec.confiscated, seized, "confiscated accounting exact");
            if (n < 4) {
                assertEq(uint8(rec.status), uint8(CurveGaugeLister.Status.Confiscated), "confiscated");
            } else {
                assertEq(seized, 0, "count 4 yields no-op");
                assertEq(uint8(rec.status), uint8(CurveGaugeLister.Status.Exhausted), "exhausted stays");
            }
        }
    }
}
