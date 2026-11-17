// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC20Minimal} from "../../../contracts/interfaces/IERC20Minimal.sol";
import {BountyConfig, ReportView} from "../../../contracts/bounty/BountyTypes.sol";
import {SafeToken} from "../../../contracts/libraries/SafeToken.sol";

/// @title MockBountyHook
/// @notice Strict test-only bounty stand-in used to exercise the COMPLETE V2
/// flow (X02, adapted to the thin hook in T04): bound-lister caller only, a
/// matching LOCAL flat-view case (gauge/reporter/listing identity, phase
/// Recognized, zero current reward credit — the old slashed-stake veto is
/// deliberately gone), and V2's just-written Confiscated listing with this
/// report ID and exact B; it transitions to Rewarded before pulling, pulls
/// exactly B via transferFrom and checks custody deltas. Fault modes let the
/// settlement tests prove V2's all-or-nothing rollback; consistency is
/// honest by construction (a staged recognized case satisfies V2's report/
/// recipient checks, everything else fails them).
contract MockBountyHook {
    struct CaseRec {
        bool exists;
        address gauge;
        address reporter;
        uint8 phase; // mirrors the thin BountyTypes.Phase order
        uint256 rewardCredit;
    }

    struct CreditExpectation {
        bool expected;
        uint256 amount;
        address lister;
        address reporter;
    }

    /// @dev Rework lifecycle constants (BountyTypes order: None=0,
    /// Proposed=1, Armed=2, Recognized=3, Rewarded=4, Rejected=5, Expired=6,
    /// NoAward=7; the Queued phase is retired with the queue).
    uint8 private constant PHASE_RECOGNIZED = 3;
    uint8 private constant PHASE_REWARDED = 4;

    address private immutable _crvUSD;
    address private immutable _feeDistributor;
    address private _lister; // write-once, like the real binding
    mapping(bytes32 => CaseRec) private _cases; // reportId => local case
    mapping(address => bytes32) private _caseOf; // gauge => staged reportId
    mapping(bytes32 => CreditExpectation) private _credits;
    bytes32 private _lastPulledReportId;
    uint256 private _lastPulledAmount;
    uint256 private _creditCalls;
    bool private _creditRevert;
    bool private _creditNoPull;
    bool private _creditUnderPull;
    bool private _termsRevert;
    bool private _termsMalformed;

    error NotLister();
    error AlreadyBound();
    error BadLister();
    error CreditNotExpected();
    error CreditRevert();
    error CreditDeltaMismatch();

    event RewardCredited(bytes32 indexed reportId, uint256 amount);
    event ListerBound(address indexed lister);

    constructor(address crvUSD_, address feeDistributor_) {
        require(crvUSD_ != address(0) && feeDistributor_ != address(0), "zero");
        _crvUSD = crvUSD_;
        _feeDistributor = feeDistributor_;
    }

    // ------------------------- config / binding surface -------------------

    /// @notice Only the first two config fields matter to V2's constructor
    /// checks (token/FD match); the rest are inert placeholders.
    function config() external view returns (BountyConfig memory cfg) {
        cfg.crvUSD = _crvUSD;
        cfg.feeDistributor = _feeDistributor;
    }

    function crvUSD() external view returns (address) {
        return _crvUSD;
    }

    function feeDistributor() external view returns (address) {
        return _feeDistributor;
    }

    function lister() external view returns (address) {
        return _lister;
    }

    function bindLister(address lister_) external {
        if (_lister != address(0)) revert AlreadyBound();
        if (lister_ == address(0) || lister_.code.length == 0) revert BadLister();
        _lister = lister_;
        emit ListerBound(lister_);
    }

    // ------------------------------- hook reads ---------------------------

    /// @notice Exists := staged case matching this gauge. Eligible := local
    /// Recognized phase with zero current reward credit (the real contract's
    /// gate; Recognized already incorporates the old successful-attribution/
    /// unallocated conditions).
    function rewardTerms(address gauge) external view returns (bytes32, address, bool) {
        if (_termsRevert) revert CreditRevert();
        if (_termsMalformed) {
            assembly {
                return(0, 31)
            }
        }
        bytes32 id = _caseOf[gauge];
        CaseRec storage c = _cases[id];
        bool eligible = c.exists && c.gauge == gauge && c.phase == PHASE_RECOGNIZED && c.rewardCredit == 0;
        return (id, c.reporter, eligible);
    }

    /// @notice Flat local-accounting view for V2's consistency checks. The
    /// listing identity mirrors the permanent V2 formula so the honest path
    /// satisfies the real check.
    function getReport(bytes32 reportId) external view returns (ReportView memory rv) {
        CaseRec storage c = _cases[reportId];
        if (!c.exists) {
            return rv;
        }
        rv.reporter = c.reporter;
        rv.gauge = c.gauge;
        rv.listingId = keccak256(abi.encode(uint256(1), _lister, c.gauge));
        rv.evidenceHash = bytes32(uint256(0xE11));
        rv.proposalId = 1;
        rv.voteEnd = block.timestamp;
        rv.executeBy = block.timestamp + 7 days;
        rv.phase = c.phase;
        rv.stakeState = 2; // Refundable
        rv.rewardCredit = c.rewardCredit;
    }

    /// @notice Only the bound V2 may call; requires a pre-staged exact credit
    /// for this report, transitions to Rewarded, then pulls exactly amount.
    function creditReward(bytes32 reportId, uint256 amount) external {
        if (msg.sender != _lister) revert NotLister();
        _creditCalls += 1;
        if (_creditRevert) revert CreditRevert();
        CreditExpectation storage e = _credits[reportId];
        if (!e.expected || e.amount != amount || e.lister != msg.sender) revert CreditNotExpected();
        CaseRec storage c = _cases[reportId];
        if (!c.exists || c.gauge == address(0)) revert CreditNotExpected();
        if (c.phase != PHASE_RECOGNIZED || c.rewardCredit != 0) revert CreditNotExpected();
        c.phase = PHASE_REWARDED;
        c.rewardCredit = amount;

        if (_creditNoPull) {
            // Malicious stand-in: claims success without pulling anything.
            emit RewardCredited(reportId, amount);
            return;
        }
        uint256 before = IERC20Minimal(_crvUSD).balanceOf(address(this));
        uint256 pull = _creditUnderPull ? amount - 1 : amount;
        SafeToken.safeTransferFrom(_crvUSD, msg.sender, address(this), pull);
        uint256 after_ = IERC20Minimal(_crvUSD).balanceOf(address(this));
        if (!_creditUnderPull && after_ - before != amount) revert CreditDeltaMismatch();
        // Under-pull mode deliberately returns "success" one unit short: the
        // SENDER-side exact debit/allowance checks in V2 must catch it, not
        // this stand-in.
        _lastPulledReportId = reportId;
        _lastPulledAmount = amount;
        emit RewardCredited(reportId, amount);
    }

    // ------------------------------- controls -----------------------------

    /// @notice Stage a coherent recognized case for `gauge` under `reportId`.
    function stageCase(address gauge, bytes32 reportId, address reporter) external {
        _cases[reportId] =
            CaseRec({exists: true, gauge: gauge, reporter: reporter, phase: PHASE_RECOGNIZED, rewardCredit: 0});
        _caseOf[gauge] = reportId;
    }

    /// @notice Degrade a staged case (terminal phase / current credit) to
    /// drive the all-FD branches and consistency-failure branches.
    function setCaseState(bytes32 reportId, uint8 phase, uint256 rewardCredit) external {
        CaseRec storage c = _cases[reportId];
        require(c.exists, "no case");
        c.phase = phase;
        c.rewardCredit = rewardCredit;
    }

    function clearCase(address gauge, bytes32 reportId) external {
        delete _cases[reportId];
        delete _caseOf[gauge];
    }

    function setTermsFaults(bool revert_, bool malformed_) external {
        _termsRevert = revert_;
        _termsMalformed = malformed_;
    }

    /// @notice Stage the ONE credit this hook will accept; V2 must call with
    /// exactly this report/amount from exactly the bound lister.
    function expectCredit(bytes32 reportId, uint256 amount) external {
        _credits[reportId] = CreditExpectation({expected: true, amount: amount, lister: _lister, reporter: msg.sender});
    }

    function clearCredit(bytes32 reportId) external {
        delete _credits[reportId];
    }

    function setCreditFaults(bool revert_, bool noPull, bool underPull) external {
        _creditRevert = revert_;
        _creditNoPull = noPull;
        _creditUnderPull = underPull;
    }

    function creditCalls() external view returns (uint256) {
        return _creditCalls;
    }

    function lastPulled() external view returns (bytes32, uint256) {
        return (_lastPulledReportId, _lastPulledAmount);
    }

    function allocated(bytes32 reportId) external view returns (bool) {
        return _cases[reportId].exists && _cases[reportId].phase == PHASE_REWARDED;
    }
}
