// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC20Minimal} from "./interfaces/IERC20Minimal.sol";
import {IFeeDistributor} from "./interfaces/IFeeDistributor.sol";
import {IGaugeBounty} from "./interfaces/IGaugeBounty.sol";
import {ICurveGaugeListerV2} from "./interfaces/ICurveGaugeListerV2.sol";
import {IOwnershipVoting} from "./interfaces/IOwnershipVoting.sol";
import {IAgent, IKillProxy, ISupportedFactory, ISupportedGauge} from "./interfaces/IBountyGovernance.sol";
import {SafeToken} from "./libraries/SafeToken.sol";
import {FeeDistributorAccounting} from "./libraries/FeeDistributorAccounting.sol";
import {BountyScripts} from "./libraries/BountyScripts.sol";
import {BountyRead} from "./libraries/BountyRead.sol";
import {ICurveGauge} from "./interfaces/ICurveGauge.sol";
import {ReportView, BountyConfig, Phase, StakeState} from "./bounty/BountyTypes.sol";

/// @title GaugeBounty
/// @notice Prospective reporter-bonded kill bounty (plans/BOUNTY-REWORK-PLAN.md
/// §§2–6). Admission binds a PRE-CREATED beneficiary-bound Ownership ballot:
/// `submit` requires the exact canonical script S(reportId, msg.sender, gauge)
/// stored in the cited proposal, so the submitter IS the encoded beneficiary
/// (sponsorship is permitted; the actual creator may differ — that is not
/// authenticated and no creator mechanism exists). No standing lock, no
/// project capital, no FIFO queue, no shared creation, no single active-slot
/// admission: any number of distinct beneficiary-bound reports may coexist
/// per listing and FIRST QUALIFYING RECOGNITION wins a permanent
/// listing-level latch. Holds only the three money liabilities, the
/// permanent report/proposal bindings, the winner latch, the same-block arm
/// and ordinary reentrancy protection on every mutator. Deployment order:
/// bounty first, V2 second, then the immutable Ownership Agent calls
/// `bindLister(V2)`. No receive/fallback, no payable function, no owner, no
/// arbitrary execution, no token sweep, no vote-casting/boost/weight
/// endpoint, no periodic-maintenance entrypoint and no cancellation.
contract GaugeBounty {
    // ---------------------------------------------------------------------
    // Pinned governance mechanics (research facts, rework plan §3.2)
    // ---------------------------------------------------------------------

    uint256 private constant STAKE = 1000e18;
    uint256 private constant VOTE_TIME = 604800;
    uint256 private constant SUPPORT_REQUIRED = 510000000000000000;
    uint256 private constant MIN_ACCEPT_QUORUM = 300000000000000000;
    /// @dev 7-day execution grace after the real 7-day ballot (§3.2 step 3):
    /// the unresolved local clock is ALWAYS startDate + 14 days, never
    /// submit + anything, and never extendable.
    uint256 private constant EXECUTION_GRACE = 604800;

    // ---------------------------------------------------------------------
    // Configuration and binding (§6)
    // ---------------------------------------------------------------------

    address private _lister; // write-once authenticated binding

    // ---------------------------------------------------------------------
    // Report state (§4): permanent reports, permanent proposal bindings,
    // permanent listing-level winner latch. No per-listing collection,
    // queue or total report loop; existence is a nonzero stored reporter.
    // ---------------------------------------------------------------------

    struct Report {
        Phase phase; // packed private lifecycle; public ReportView is unchanged
        StakeState stakeState;
        address reporter; // existence := reporter != address(0); immutable
        address gauge;
        bytes32 listingId; // permanent listing identity at admission
        bytes32 evidenceHash;
        uint256 proposalId; // immutable ballot binding (zero is a legal id)
        uint256 voteEnd; // actual ballot startDate + VOTE_TIME (never reset)
        uint256 executeBy; // voteEnd + EXECUTION_GRACE
        uint256 rewardCredit; // currently funded, unpaid reporter half
        uint256 armedBlock; // private same-block arm; no getter
    }

    mapping(bytes32 => Report) private _reports;
    mapping(uint256 => bytes32) private _boundProposal; // proposalId => reportId, forever
    mapping(bytes32 => bytes32) private _winnerLatch; // listingId => recognized reportId, forever

    // The three CURRENT custody liabilities (thin §4.3). Historical counters
    // are maintained by independent test ledgers, never by the product.
    uint256 private _heldStakes; // Bonded + Refundable, never Refunded/Forfeited
    uint256 private _rewardCredits; // actually funded, unpaid rewards
    uint256 private _daoLiability; // unpaid forfeited stakes reserved for the FD

    // ---------------------------------------------------------------------
    // Guards: ordinary reentrancy protection on EVERY mutator. Operation
    // fences existed only for the deleted self-calls and are gone.
    // ---------------------------------------------------------------------

    /// @dev Reentrancy-lock word, initialized unlocked.
    uint256 private _lockState = 1;

    // ---------------------------------------------------------------------
    // Constructor-only configuration tail (§6). Five dependency code hashes
    // are read by the compatibility checks. Written exactly once in the
    // constructor after the validations; there is no setter, initializer,
    // reinitializer, owner, upgrade or alternative write path. Immutable
    // config changes require a new deployment, never a setter.
    // ---------------------------------------------------------------------

    BountyConfig private _cfg;
    bytes32 private _depVotingApp;
    bytes32 private _depAgent;
    bytes32 private _depProxy;
    bytes32 private _depFactory;
    bytes32 private _depExecutor;

    // ---------------------------------------------------------------------
    // Events (§6): seven, with the existing signatures/indexing; the retired
    // StandingLockFunded/KillVoteCreated are gone and ReportSubmitted now
    // carries the ballot binding and the original vote clocks.
    // ---------------------------------------------------------------------

    event ListerBound(address indexed lister);
    event ReportSubmitted(
        bytes32 indexed reportId,
        address indexed reporter,
        address indexed gauge,
        uint256 proposalId,
        uint256 reportNonce,
        bytes32 evidenceHash,
        uint256 voteEnd,
        uint256 executeBy
    );
    event ReportStateChanged(bytes32 indexed reportId, uint8 phase);
    event RewardCredited(bytes32 indexed reportId, uint256 amount);
    event StakeForfeited(bytes32 indexed reportId);
    event Claimed(bytes32 indexed reportId, address indexed reporter, uint256 stakeAmount, uint256 rewardAmount);
    event DaoFlushed(uint256 amount, uint256 receiptWeek);

    /// @dev The complete §6 custom-error set: sixteen product errors.
    /// `DistributorUnusable` and `ConfiscationDeltaMismatch` come from the
    /// shared FD library with the accepted selectors; SafeToken errors stay
    /// reachable. Beneficiary mismatch is BadVote, not a creator observation.
    error WrongChain();
    error BadConfiguration();
    error NotAgent();
    error NotDao();
    error NotLister();
    error Reentrancy();
    error AlreadyBound();
    error UnknownReport();
    error IneligibleGauge();
    error BadEvidence();
    error BadPhase();
    error BadVote();
    error BadAmount();
    error TokenDeltaMismatch();
    error DuplicateReport();
    error DuplicateProposal();

    modifier lock() {
        _lockEnter();
        _;
        _lockExit();
    }

    function _lockEnter() private {
        if (_lockState != 1) revert Reentrancy();
        _lockState = 2;
    }

    function _lockExit() private {
        _lockState = 1;
    }

    modifier onlyAgent() {
        if (msg.sender != _cfg.ownershipAgent) revert NotAgent();
        _;
    }

    // ---------------------------------------------------------------------
    // Construction (§6)
    // ---------------------------------------------------------------------

    /// @notice All nine configuration addresses are fixed for the deployment;
    /// every identity/pin check below runs at construction. Config changes
    /// require a new deployment, not an owner knob. No CRV pull, escrow,
    /// treasury or wallet-checker identity is accepted or probed (§2).
    constructor(BountyConfig memory config_) {
        if (block.chainid != 1) revert WrongChain();

        address[9] memory mustHaveCode = [
            config_.crvUSD,
            config_.feeDistributor,
            config_.ownershipVoting,
            config_.ownershipAgent,
            config_.killProxy,
            config_.supportedFactory,
            config_.votingImplementation,
            config_.agentImplementation,
            config_.callsScriptExecutor
        ];
        for (uint256 i = 0; i < mustHaveCode.length; ++i) {
            if (mustHaveCode[i].code.length == 0) revert BadConfiguration();
        }

        if (!BountyRead.decimals18(config_.crvUSD)) revert BadConfiguration();

        // FD identity via the accepted failure selectors.
        if (!BountyRead.eqAddress(
                config_.feeDistributor, IFeeDistributor.token.selector, bytes32(0), false, config_.crvUSD
            )) {
            revert FeeDistributorAccounting.DistributorUnusable();
        }
        (bool fdReadOk, bool fdKilled) =
            BountyRead.boolWord(config_.feeDistributor, IFeeDistributor.is_killed.selector, bytes32(0), false);
        if (!fdReadOk || fdKilled) revert FeeDistributorAccounting.DistributorUnusable();

        // App/Agent/executor/route identity chain (no escrow/checker legs).
        if (!BountyRead.eqAddress(
                config_.ownershipVoting,
                IOwnershipVoting.implementation.selector,
                bytes32(0),
                false,
                config_.votingImplementation
            )) {
            revert BadConfiguration();
        }
        if (!BountyRead.executorBound(
                config_.ownershipVoting, BountyScripts.CALLS_SCRIPT_TYPE, config_.callsScriptExecutor
            )) {
            revert BadConfiguration();
        }
        if (!BountyRead.eqAddress(
                config_.ownershipAgent, IAgent.implementation.selector, bytes32(0), false, config_.agentImplementation
            )) {
            revert BadConfiguration();
        }
        if (!BountyRead.eqAddress(
                config_.killProxy, IKillProxy.dao.selector, bytes32(0), false, config_.ownershipAgent
            )) {
            revert BadConfiguration();
        }
        (bool emOk, uint256 emAddr) =
            BountyRead.readUint(config_.killProxy, IKillProxy.emergency_dao.selector, bytes32(0), false);
        if (!emOk || !BountyRead.hasCode(address(uint160(emAddr)))) revert BadConfiguration();
        if (!BountyRead.eqAddress(
                config_.supportedFactory, ISupportedFactory.admin.selector, bytes32(0), false, config_.killProxy
            )) {
            revert BadConfiguration();
        }

        // Pinned Voting duration/support/quorum (§3.2 step 2). The retired
        // minBalance/minTime gates controlled the actual creator's upstream
        // proposal rights, not beneficiary eligibility or bounty admission.
        if (!BountyRead.eqWord(
                config_.ownershipVoting, IOwnershipVoting.voteTime.selector, bytes32(0), false, VOTE_TIME
            )) {
            revert BadConfiguration();
        }
        if (!BountyRead.eqWord(
                config_.ownershipVoting,
                IOwnershipVoting.supportRequiredPct.selector,
                bytes32(0),
                false,
                SUPPORT_REQUIRED
            )) {
            revert BadConfiguration();
        }
        if (!BountyRead.eqWord(
                config_.ownershipVoting,
                IOwnershipVoting.minAcceptQuorumPct.selector,
                bytes32(0),
                false,
                MIN_ACCEPT_QUORUM
            )) {
            revert BadConfiguration();
        }

        _cfg = config_;
        _depVotingApp = config_.ownershipVoting.codehash;
        _depAgent = config_.ownershipAgent.codehash;
        _depProxy = config_.killProxy.codehash;
        _depFactory = config_.supportedFactory.codehash;
        _depExecutor = config_.callsScriptExecutor.codehash;
    }

    // ---------------------------------------------------------------------
    // Configuration and binding entrypoints
    // ---------------------------------------------------------------------

    function config() external view returns (BountyConfig memory cfg) {
        cfg = _cfg; // exact 9-address tuple, single storage-to-memory copy
    }

    function lister() external view returns (address) {
        return _lister;
    }

    /// @notice One-time authenticated storage written by the actual Ownership
    /// Agent (not a Solidity-immutable constructor address). Requires unset,
    /// code, chain/token/FD match and V2.bounty == this (§1.2 wiring).
    function bindLister(address lister_) external onlyAgent lock {
        if (_lister != address(0)) revert AlreadyBound();
        if (lister_.code.length == 0) revert BadConfiguration();
        if (block.chainid != 1) revert WrongChain();
        if (!BountyRead.eqAddress(lister_, ICurveGaugeListerV2.crvUSD.selector, bytes32(0), false, _cfg.crvUSD)) {
            revert BadConfiguration();
        }
        if (!BountyRead.eqAddress(
                lister_, ICurveGaugeListerV2.feeDistributor.selector, bytes32(0), false, _cfg.feeDistributor
            )) {
            revert BadConfiguration();
        }
        if (!BountyRead.eqAddress(lister_, ICurveGaugeListerV2.bounty.selector, bytes32(0), false, address(this))) {
            revert BadConfiguration();
        }
        // Initially the V2 config owner must BE the configured Ownership
        // Agent's counterpart wiring authority: an outsider cannot win a
        // first-caller binding race.
        if (!BountyRead.eqAddress(lister_, ICurveGaugeListerV2.owner.selector, bytes32(0), false, _cfg.ownershipAgent))
        {
            revert BadConfiguration();
        }
        _lister = lister_;
        emit ListerBound(lister_);
    }

    // ---------------------------------------------------------------------
    // Internal token helpers
    // ---------------------------------------------------------------------

    /// @dev Exact token pull with two-sided delta checks and a cleared
    /// allowance postcondition (§3.2 step 6, frozen SafeToken policy).
    /// Empty/false/malformed token behavior all revert the whole admission.
    function _pullToken(address token, address from, uint256 amount) private {
        uint256 fromBefore = _bal(token, from);
        uint256 toBefore = _bal(token, address(this));
        SafeToken.safeTransferFrom(token, from, address(this), amount);
        if (_bal(token, from) != fromBefore - amount) revert TokenDeltaMismatch();
        if (_bal(token, address(this)) != toBefore + amount) revert TokenDeltaMismatch();
        // External pullers (reporters) may hold larger approvals; only the
        // exact debit is enforced. Contract-issued approvals (V2->bounty) are
        // cleared and checked at their own sites per thin plan §4.1.
    }

    // ---------------------------------------------------------------------
    // Dependency identity verification (§3.2 step 2)
    // ---------------------------------------------------------------------

    /// @dev Rechecks the constructor-bound Voting/Agent implementation
    /// pointers, code identities, CallsScript executor and the three pinned
    /// Voting parameters. Returns false on any drift; callers defer or yield
    /// unapplied/no-award outcomes rather than obstructing the kill.
    function _checkVotingCompat() private view returns (bool) {
        if (block.chainid != 1) return false;
        if (_cfg.ownershipVoting.codehash != _depVotingApp) return false;
        if (_cfg.ownershipAgent.codehash != _depAgent) return false;
        if (_cfg.callsScriptExecutor.codehash != _depExecutor) return false;
        if (!BountyRead.eqAddress(
                _cfg.ownershipVoting,
                IOwnershipVoting.implementation.selector,
                bytes32(0),
                false,
                _cfg.votingImplementation
            )) {
            return false;
        }
        if (!BountyRead.eqAddress(
                _cfg.ownershipAgent, IAgent.implementation.selector, bytes32(0), false, _cfg.agentImplementation
            )) {
            return false;
        }
        if (!BountyRead.executorBound(_cfg.ownershipVoting, BountyScripts.CALLS_SCRIPT_TYPE, _cfg.callsScriptExecutor))
        {
            return false;
        }
        if (!BountyRead.eqWord(_cfg.ownershipVoting, IOwnershipVoting.voteTime.selector, bytes32(0), false, VOTE_TIME))
        {
            return false;
        }
        if (!BountyRead.eqWord(
                _cfg.ownershipVoting, IOwnershipVoting.supportRequiredPct.selector, bytes32(0), false, SUPPORT_REQUIRED
            )) {
            return false;
        }
        return BountyRead.eqWord(
            _cfg.ownershipVoting, IOwnershipVoting.minAcceptQuorumPct.selector, bytes32(0), false, MIN_ACCEPT_QUORUM
        );
    }

    /// @dev Gauge-side route identity checks (proxy/factory code and roles).
    function _checkRouteCompat() private view returns (bool) {
        if (_cfg.killProxy.codehash != _depProxy) return false;
        if (_cfg.supportedFactory.codehash != _depFactory) return false;
        if (!BountyRead.eqAddress(_cfg.killProxy, IKillProxy.dao.selector, bytes32(0), false, _cfg.ownershipAgent)) {
            return false;
        }
        return BountyRead.eqAddress(
            _cfg.supportedFactory, ISupportedFactory.admin.selector, bytes32(0), false, _cfg.killProxy
        );
    }

    function _requireGovernanceCompatible() private view {
        if (!_checkVotingCompat() || !_checkRouteCompat()) revert BadConfiguration();
    }

    /// @dev ONE shared balanceOf read body (value-typed args): every delta
    /// check reads through it instead of inlining a fresh external-call
    /// decoder per site.
    function _bal(address token, address who) private view returns (uint256) {
        return IERC20Minimal(token).balanceOf(who);
    }

    /// @dev Token payment with two-sided delta checks to a FIXED recipient.
    function _payToken(address token, address to, uint256 amount) private {
        uint256 fromBefore = _bal(token, address(this));
        uint256 toBefore = _bal(token, to);
        SafeToken.safeTransfer(token, to, amount);
        if (_bal(token, address(this)) != fromBefore - amount) revert TokenDeltaMismatch();
        if (_bal(token, to) != toBefore + amount) revert TokenDeltaMismatch();
    }

    /// @dev Single shared bounded getListing observation for every decision
    /// consumer.
    function _facts(address gauge)
        private
        view
        returns (
            bool fetched,
            bool decoded,
            bool paidActivePositive,
            uint256 status,
            uint256 rewardReportId,
            uint256 reporterReward,
            uint256 confiscated
        )
    {
        return BountyRead.listingFacts(_lister, gauge);
    }

    /// @dev Capped, strictly-decoded getVote observation; never reverts.
    function _observeVote(uint256 voteId) private view returns (bool ok, BountyRead.VoteRecord memory rec) {
        return BountyRead.readVote(_cfg.ownershipVoting, voteId);
    }

    /// @dev The complete canonical kill script reconstructed from STORED
    /// reportId/reporter/gauge (§3.3): never from supplied callback data.
    function _killScriptOf(Report storage r, bytes32 reportId) private view returns (bytes memory) {
        return BountyScripts.buildKillScript(
            _cfg.ownershipAgent, address(this), _cfg.killProxy, r.gauge, reportId, r.reporter
        );
    }

    // ---------------------------------------------------------------------
    // Views
    // ---------------------------------------------------------------------

    /// @notice Unknown report ids return the all-zero tuple; a legitimate
    /// zero proposal id is disambiguated by the nonzero stored reporter.
    function getReport(bytes32 reportId) external view returns (ReportView memory rv) {
        Report storage r = _reports[reportId];
        if (r.reporter == address(0)) {
            return rv;
        }
        return ReportView({
            reporter: r.reporter,
            gauge: r.gauge,
            listingId: r.listingId,
            evidenceHash: r.evidenceHash,
            proposalId: r.proposalId,
            voteEnd: r.voteEnd,
            executeBy: r.executeBy,
            phase: uint8(r.phase),
            stakeState: uint8(r.stakeState),
            rewardCredit: r.rewardCredit
        });
    }

    /// @notice Local-only hook read; no upstream/lister/token calls (§4).
    /// With no latch, the all-zero tuple — even when proposals exist. With a
    /// latch, the permanent winner id/reporter are ALWAYS returned (also
    /// after funding or closure) while eligible holds only for Recognized
    /// with zero current reward credit. Pending submissions never appear as
    /// an entitlement candidate and payment never clears the winner.
    function rewardTerms(address gauge) external view returns (bytes32 reportId_, address reporter_, bool eligible) {
        if (_lister == address(0)) {
            return (bytes32(0), address(0), false);
        }
        bytes32 lid = keccak256(abi.encode(uint256(1), _lister, gauge)); // local derivation, no read
        reportId_ = _winnerLatch[lid];
        if (reportId_ == bytes32(0)) {
            return (bytes32(0), address(0), false);
        }
        Report storage r = _reports[reportId_];
        reporter_ = r.reporter;
        // Recognized already incorporates successful attribution; a consumed
        // allocation (Rewarded) or any credit is no longer an entitlement.
        eligible = r.reporter != address(0) && r.phase == Phase.Recognized && r.rewardCredit == 0;
    }

    function accounting() external view returns (uint256 heldStakes, uint256 rewardCredits, uint256 daoLiability) {
        return (_heldStakes, _rewardCredits, _daoLiability);
    }

    // ---------------------------------------------------------------------
    // Direct admission of a beneficiary-bound ballot (§3.1/§3.2)
    // ---------------------------------------------------------------------

    /// @notice One public paid submission: exact 1000e18 crvUSD from the
    /// reporter, an EXISTING ballot whose canonical script names the
    /// submitter, evidence identifier and caller-chosen report nonce. There
    /// is no beneficiary/creator/app argument: the fixed reporter IS
    /// msg.sender and the only app is config.ownershipVoting. Every §3.2
    /// step runs before any stake is retained; a rejected submission
    /// registers nothing — no new report/bond survives any failed path.
    function submit(address gauge, uint256 proposalId, bytes32 evidenceHash, uint256 reportNonce)
        external
        lock
        returns (bytes32 reportId)
    {
        // Step 1: chain, bound reciprocal V2, evidence, live eligible
        // listing, permanent listing id and the never-latched condition.
        if (block.chainid != 1) revert WrongChain();
        if (_lister == address(0)) revert BadConfiguration();
        if (_lister.code.length == 0) revert BadConfiguration();
        if (!BountyRead.eqAddress(_lister, ICurveGaugeListerV2.bounty.selector, bytes32(0), false, address(this))) {
            revert BadConfiguration();
        }
        if (evidenceHash == bytes32(0)) revert BadEvidence();
        _requireEligible(gauge);
        bytes32 lid = ICurveGaugeListerV2(_lister).listingId(gauge);
        // An already-latched winner (even if the gauge was later un-killed)
        // makes the listing permanently inadmissible for new reports.
        if (lid == bytes32(0) || _winnerLatch[lid] != bytes32(0)) revert IneligibleGauge();

        // Step 2: current implementation/role/route compatibility and the
        // three surviving pins. minBalance/minTime gates are deleted: they
        // control the actual creator's upstream proposal rights, not
        // beneficiary eligibility or bounty admission.
        _requireGovernanceCompatible();

        // Step 3: existence + complete record, fail closed; the ORIGINAL
        // vote clock is bound, never reset to submit time.
        (bytes32 scriptHash, uint256 voteEnd, uint256 executeBy) = _admitBallot(proposalId);

        // Step 4: the reporter IS the caller; permanent-identity duplicates
        // fail forever, including after any refund/forfeiture. No creator
        // lookup or equality test exists.
        address reporter = msg.sender;
        reportId = BountyScripts.reportId(
            address(this), block.chainid, _lister, gauge, lid, reporter, reportNonce, evidenceHash
        );
        if (reportId == bytes32(0)) revert BadEvidence(); // preserve the map's empty sentinel
        if (_reports[reportId].reporter != address(0)) revert DuplicateReport();
        if (_boundProposal[proposalId] != bytes32(0)) revert DuplicateProposal();

        // Step 5: beneficiary-in-hash equality REPLACES creator equality.
        // The stored script must equal S(reportId, reporter, gauge) byte for
        // byte — wrong explicit beneficiary, wrong gauge, wrong domain/
        // callback, other Agent/proxy/bounty, missing/reordered/extra
        // actions, selector substitution and trailing bytes are ALL BadVote.
        if (
            scriptHash
                != keccak256(
                    BountyScripts.buildKillScript(
                        _cfg.ownershipAgent, address(this), _cfg.killProxy, gauge, reportId, reporter
                    )
                )
        ) revert BadVote();

        // Step 6: exact two-sided pull, then all permanent effects, in ONE
        // reverting transaction. Larger external allowance is legal.
        _pullToken(_cfg.crvUSD, reporter, STAKE);

        Report storage r = _reports[reportId];
        r.reporter = reporter;
        r.gauge = gauge;
        r.listingId = lid;
        r.evidenceHash = evidenceHash;
        r.proposalId = proposalId;
        r.voteEnd = voteEnd;
        r.executeBy = executeBy;
        r.phase = Phase.Proposed;
        r.stakeState = StakeState.Bonded;
        _heldStakes += STAKE;
        _boundProposal[proposalId] = reportId;

        emit ReportSubmitted(reportId, reporter, gauge, proposalId, reportNonce, evidenceHash, voteEnd, executeBy);
        emit ReportStateChanged(reportId, uint8(Phase.Proposed));
    }

    /// @dev §3.2 step 3 in one narrow frame: strictly decoded existence,
    /// unexecuted, positive power, pinned snapshot ratios, sane timing words
    /// and guarded original-clock binding. Every failure reverts BadVote
    /// before any stake is retained; the caller binds the returned script
    /// hash against the reconstructed canonical script.
    function _admitBallot(uint256 proposalId)
        private
        view
        returns (bytes32 scriptHash, uint256 voteEnd, uint256 executeBy)
    {
        (bool lenOk, uint256 len) =
            BountyRead.readUint(_cfg.ownershipVoting, IOwnershipVoting.votesLength.selector, bytes32(0), false);
        if (!lenOk) revert BadVote();
        if (proposalId >= len) revert BadVote(); // monotonic ids; zero is legal
        (bool dec, BountyRead.VoteRecord memory rec) = _observeVote(proposalId);
        if (!dec) revert BadVote();
        if (rec.executed) revert BadVote();
        if (rec.votingPower == 0) revert BadVote();
        if (rec.supportRequired != SUPPORT_REQUIRED) revert BadVote();
        if (rec.minAcceptQuorum != MIN_ACCEPT_QUORUM) revert BadVote();
        if (rec.startDate == 0 || rec.startDate > block.timestamp) revert BadVote();
        if (rec.snapshotBlock >= block.number) revert BadVote();
        // Guarded arithmetic binds the ORIGINAL clock; a future/max-date
        // word fails closed.
        if (rec.startDate > type(uint256).max - VOTE_TIME) revert BadVote();
        voteEnd = rec.startDate + VOTE_TIME;
        if (voteEnd > type(uint256).max - EXECUTION_GRACE) revert BadVote();
        executeBy = voteEnd + EXECUTION_GRACE;
        if (block.timestamp > executeBy) revert BadVote();
        scriptHash = rec.scriptHash;
    }

    /// @dev Submission-time eligibility (§3.2 step 1): positively observed
    /// Active+paid+exact-fee-shape+positive-remainder listing via the bound
    /// V2's bounded read, live not-killed flag and the verified supported
    /// route. Reads propagate as reverts (fail closed) on this public path.
    function _requireEligible(address gauge) private view {
        (bool fetched, bool decoded, bool paidActivePositive,,,,) = _facts(gauge);
        if (!fetched || !decoded || !paidActivePositive) revert IneligibleGauge();
        if (gauge.code.length == 0) revert IneligibleGauge();
        // Live supported route (V2's registry-authenticated listing is
        // already fixed; factory()/admin()/dao() are re-checked every time,
        // a self-reported factory() alone is never sufficient).
        if (!BountyRead.eqAddress(gauge, ISupportedGauge.factory.selector, bytes32(0), false, _cfg.supportedFactory)) {
            revert IneligibleGauge();
        }
        if (!BountyRead.eqAddress(
                _cfg.supportedFactory, ISupportedFactory.admin.selector, bytes32(0), false, _cfg.killProxy
            )) {
            revert BadConfiguration();
        }
        if (!BountyRead.eqAddress(_cfg.killProxy, IKillProxy.dao.selector, bytes32(0), false, _cfg.ownershipAgent)) {
            revert BadConfiguration();
        }
        if (ICurveGauge(gauge).is_killed()) revert IneligibleGauge();
    }

    // ---------------------------------------------------------------------
    // Recognition race (§3.3/§4): two Agent-only, no-token/no-FD,
    // bounded-observation one-shot callbacks. Credit requires a false
    // current kill flag; recognize consumes a same-block arm BEFORE reads
    // and requires a true current flag. Failed/mismatching/stale/unarmed/
    // consumed attempts close ONLY their own unfinished offer (NoAward) and
    // never revert or obstruct the middle protective kill.
    // ---------------------------------------------------------------------

    /// @notice Agent-only pre-kill arm callback: creditBallot(reportId,
    /// reporter). After authentication, the supplied reporter must equal the
    /// already-stored nonzero reporter; reporter is NEVER written from
    /// callback data and the canonical script is always reconstructed from
    /// stored values. This is the pre-kill arm only — not reward credit,
    /// beneficiary assignment, winner registration or token settlement.
    function creditBallot(bytes32 reportId, address reporter) external onlyAgent lock {
        Report storage r = _reports[reportId];
        if (r.reporter == address(0)) return; // unknown callback: inert
        if (r.reporter != reporter) {
            _closeIfOpen(reportId, r); // wrong-beneficiary attempt spends its own offer
            return;
        }
        if (!_armable(r) || !_observationPasses(reportId, r, false)) {
            _closeIfOpen(reportId, r);
            return;
        }
        r.phase = Phase.Armed;
        r.armedBlock = block.number;
    }

    /// @notice Agent-only recognition: consumes and clears the same-block
    /// arm BEFORE reads; requires the timely executed canonical script,
    /// unchanged identities, a still-live matching listing, no different
    /// recognized winner and the CURRENT kill flag true. First qualifying
    /// flag-true recognition writes the previously empty permanent winner
    /// latch; Recognized/Rewarded are never rewritten and no token or FD
    /// movement occurs.
    function recognizeKill(bytes32 reportId) external onlyAgent lock {
        Report storage r = _reports[reportId];
        if (r.reporter == address(0)) return; // unknown callback: inert
        // An already recognized (or rewarded) entitlement is never erased.
        if (r.phase == Phase.Recognized || r.phase == Phase.Rewarded) return;
        bool armed = r.phase == Phase.Armed && r.armedBlock == block.number;
        r.armedBlock = 0; // consume/clear the arm before any read
        if (!armed || !_observationPasses(reportId, r, true)) {
            _closeIfOpen(reportId, r);
            return;
        }
        bytes32 latched = _winnerLatch[r.listingId];
        if (latched != bytes32(0) && latched != reportId) {
            // A different winner already stands: the loser closes locally.
            _close(reportId, r, Phase.NoAward);
            return;
        }
        if (latched == bytes32(0)) {
            _winnerLatch[r.listingId] = reportId; // FIRST QUALIFYING recognition stands, forever
        }
        r.phase = Phase.Recognized;
        if (r.stakeState == StakeState.Bonded) {
            r.stakeState = StakeState.Refundable; // bond claimable unless forfeited
        }
        emit ReportStateChanged(reportId, uint8(Phase.Recognized));
    }

    function _armable(Report storage r) private view returns (bool) {
        return r.phase == Phase.Proposed && r.armedBlock == 0;
    }

    /// @dev Closes only a case with an outstanding offer; terminal and
    /// recognized states are never erased and unchanged repeats are inert.
    function _closeIfOpen(bytes32 reportId, Report storage r) private {
        if (r.phase == Phase.Proposed || r.phase == Phase.Armed) {
            _close(reportId, r, Phase.NoAward);
        }
    }

    /// @dev Shared observation chain (§3.3): timeliness inside the inclusive
    /// [voteEnd, executeBy] window, no different recognized winner, matching
    /// still-live listing identity, governance/route compatibility, complete
    /// bound executed+closed vote+exact canonical script (reconstructed from
    /// stored values), and the CURRENT kill flag equal to expectKilled.
    /// Pure reads; no state writes; failures return false.
    function _observationPasses(bytes32 reportId, Report storage r, bool expectKilled) private view returns (bool) {
        if (block.timestamp < r.voteEnd || block.timestamp > r.executeBy) return false;
        bytes32 latched = _winnerLatch[r.listingId];
        if (latched != bytes32(0) && latched != reportId) return false;
        if (!_listingSnapshotMatches(r)) return false;
        if (!_checkRouteCompat()) return false;
        (bool ok, BountyRead.VoteRecord memory rec) = _observeVote(r.proposalId);
        if (!ok || !_matchingKillRecord(reportId, r, rec)) return false;
        (bool fok, bool killed) = BountyRead.readBool(r.gauge, ICurveGauge.is_killed.selector);
        if (!fok) return false;
        return killed == expectKilled;
    }

    /// @dev The executed-and-closed half: Real Voting sets executed BEFORE
    /// running the script, so both callbacks observe it; `executed &&
    /// !open` is required and canExecute is deliberately NOT consulted here
    /// (it is false after execution).
    function _matchingKillRecord(bytes32 reportId, Report storage r, BountyRead.VoteRecord memory rec)
        private
        view
        returns (bool)
    {
        if (!rec.executed || rec.open) return false;
        return _matchingCreatedRecord(reportId, r, rec);
    }

    /// @dev The compatibility half of the matching: the canonical script
    /// reconstructed from THIS case's stored values, its bound original
    /// creation time and the pinned governance settings, without the
    /// executed/open requirement. Used by resolve's validated rejection so
    /// an untrusted false after implementation drift cannot close a case.
    function _matchingCreatedRecord(bytes32 reportId, Report storage r, BountyRead.VoteRecord memory rec)
        private
        view
        returns (bool)
    {
        // The bound record must be the ACTUAL creation of this case:
        // guarded equality on the LOCALLY bound end — the untrusted
        // startDate is never added; a future/max/other mismatching start
        // cannot equal the stored actual creation time.
        if (r.voteEnd < VOTE_TIME) return false;
        if (rec.startDate != r.voteEnd - VOTE_TIME) return false;
        if (rec.supportRequired != SUPPORT_REQUIRED) return false;
        if (rec.minAcceptQuorum != MIN_ACCEPT_QUORUM) return false;
        if (!_checkVotingCompat()) return false;
        return rec.scriptHash == keccak256(_killScriptOf(r, reportId));
    }

    /// @dev Local-only binding: the permanent listing identity for this gauge
    /// must still be the case's listing, via the bound V2's bounded read,
    /// with a positively observed live (Active+paid+fee-shape+remainder)
    /// listing. A failed/malformed read fails closed to no-award.
    function _listingSnapshotMatches(Report storage r) private view returns (bool) {
        (bool idOk, uint256 lid) = BountyRead.readUint(
            _lister, ICurveGaugeListerV2.listingId.selector, bytes32(uint256(uint160(r.gauge))), true
        );
        if (!idOk || lid != uint256(r.listingId)) return false;
        (bool fetched, bool dec, bool alive,,,,) = _facts(r.gauge);
        return fetched && dec && alive;
    }

    // ---------------------------------------------------------------------
    // Resolve: local cleanup FIRST (different winner, then expiry), then
    // bounded observations (§4). Never slashes.
    // ---------------------------------------------------------------------

    /// @notice Permissionless closure of an observed failed/ineligible case
    /// or a locally expired/outraced case. Local cleanup runs without any
    /// external read; otherwise observations are bounded and unavailable
    /// data merely defers (with the local expiry fallback). A resolve NEVER
    /// slashes: only `markFrivolous` by the current V2 owner can forfeit a
    /// bond. Rewarded/Rejected/Expired/NoAward endings are local no-ops;
    /// live offers are never cancellable.
    function resolve(bytes32 reportId) external lock returns (bool changed) {
        Report storage r = _reports[reportId];
        if (r.reporter == address(0)) revert UnknownReport();
        if (r.phase == Phase.Proposed || r.phase == Phase.Armed) {
            // Local cleanup BEFORE external observations, in this order:
            // a different recorded winner, then the local expiry clock.
            bytes32 latched = _winnerLatch[r.listingId];
            if (latched != bytes32(0) && latched != reportId) {
                _close(reportId, r, Phase.NoAward);
                return true;
            }
            if (block.timestamp > r.executeBy) {
                _close(reportId, r, Phase.Expired);
                return true;
            }
            // Validated rejection: closed, unexecuted, compatible canonical
            // ballot whose canExecute is false. False alone, without the
            // matching record/open/executed checks, is insufficient.
            (bool ok, BountyRead.VoteRecord memory rec) = _observeVote(r.proposalId);
            if (ok && !rec.open && !rec.executed) {
                (bool cek, bool canEx) = BountyRead.canExecutable(_cfg.ownershipVoting, r.proposalId);
                if (cek && !canEx && _matchingCreatedRecord(reportId, r, rec)) {
                    _close(reportId, r, Phase.Rejected);
                    return true;
                }
            }
            if (_listingDefinitelyDead(r)) {
                _close(reportId, r, Phase.NoAward);
                return true;
            }
            return false; // open/passed-unexecuted timely ballot: stay Proposed, no slash
        }
        if (r.phase == Phase.Recognized) {
            // An observed irrecoverably terminal / no-matching-allocation
            // listing closes the entitlement; time elapsed or an unavailable
            // FD is never evidence. Unreadable data defers.
            (bool fetched, bool dec,, uint256 status, uint256 rewardReportId,,) = _facts(r.gauge);
            dec;
            if (!fetched || !dec) return false;
            if (status == 2 || (status == 3 && rewardReportId != uint256(reportId))) {
                _close(reportId, r, Phase.NoAward); // the latch stays consumed forever
                return true;
            }
            return false;
        }
        return false; // Rewarded/Rejected/Expired/NoAward: terminal no-ops
    }

    /// @dev Positively observed prekill/exhaustion/terminal ineligibility.
    /// Any unreadable observation defers (false) — expiry is the local
    /// fallback, never a dependency-dependent hang.
    function _listingDefinitelyDead(Report storage r) private view returns (bool) {
        (bool facOk, uint256 fac) = BountyRead.readUint(r.gauge, ISupportedGauge.factory.selector, bytes32(0), false);
        if (!facOk) return false;
        if (fac != uint256(uint160(_cfg.supportedFactory))) return true;
        (bool fetched, bool dec, bool paidActivePositive,,,,) = _facts(r.gauge);
        if (!fetched || !dec) return false;
        if (!paidActivePositive) return true; // exhausted/terminal/ineligible
        (bool bok, bool killed) = BountyRead.readBool(r.gauge, ICurveGauge.is_killed.selector);
        if (!bok) return false;
        return killed; // positively observed prekill
    }

    /// @dev THE single terminal-closure routine: the bond becomes
    /// immediately Refundable unless already Forfeited/Refunded, and the
    /// durable phase transition emits once. The permanent proposal binding
    /// and the winner latch are NEVER cleared here (or by claim, credit,
    /// expiry, unkill or a later report).
    function _close(bytes32 reportId, Report storage r, Phase finalPhase) private {
        r.phase = finalPhase;
        r.armedBlock = 0;
        if (r.stakeState == StakeState.Bonded) {
            r.stakeState = StakeState.Refundable;
        }
        emit ReportStateChanged(reportId, uint8(finalPhase));
    }

    // ---------------------------------------------------------------------
    // Sole frivolousness transition (§5)
    // ---------------------------------------------------------------------

    /// @notice Current V2 config owner only. The ONLY effect is forfeiting an
    /// unpaid bond: from Bonded or Refundable it irrevocably assigns exactly
    /// the fixed 1,000 stake to the pinned-FD liability. Phase, proposal,
    /// clocks, winner latch, arm, credit, reward entitlement and the V2
    /// listing are untouched, so a forfeited reporter can still win and
    /// receive its contractual half. Already-refunded or already-forfeited
    /// bonds return false without mutation; unknown reports revert. There is
    /// no clawback and no guaranteed adjudication interval.
    function markFrivolous(bytes32 reportId) external lock returns (bool applied) {
        if (_lister == address(0)) revert NotDao();
        Report storage r = _reports[reportId];
        if (r.reporter == address(0)) revert UnknownReport();
        if (ICurveGaugeListerV2(_lister).owner() != msg.sender) revert NotDao();
        if (r.stakeState != StakeState.Bonded && r.stakeState != StakeState.Refundable) {
            return false; // None cannot exist for a live case; Refunded/Forfeited are inert
        }
        r.stakeState = StakeState.Forfeited;
        _heldStakes -= STAKE;
        _daoLiability += STAKE;
        emit StakeForfeited(reportId);
        return true;
    }

    // ---------------------------------------------------------------------
    // Fixed-recipient claims and FD liability flush (§5)
    // ---------------------------------------------------------------------

    /// @notice Anyone; performs the same LOCAL cleanup resolve runs first
    /// (different-winner NoAward, then local Expired), then pays the
    /// available bond and funded reward together to the STORED reporter
    /// (pull, never a redirect). A timely refund can beat forfeiture and
    /// needs no dependency reads; empty or repeated claims return (0,0)
    /// without any token call. Debit happens before the transfer and both
    /// balance deltas are enforced, so a token failure rolls the entire
    /// claim back with the liabilities intact.
    function claim(bytes32 reportId) external lock returns (uint256 stakeAmount, uint256 rewardAmount) {
        Report storage r = _reports[reportId];
        if (r.reporter == address(0)) revert UnknownReport();
        // LOCAL cleanup only — never resolve()'s external-observation
        // branch, so no Voting, gauge, lister, owner or FD is required
        // after a dependency outage.
        if (r.phase == Phase.Proposed || r.phase == Phase.Armed) {
            bytes32 latched = _winnerLatch[r.listingId];
            if (latched != bytes32(0) && latched != reportId) {
                _close(reportId, r, Phase.NoAward);
            } else if (block.timestamp > r.executeBy) {
                _close(reportId, r, Phase.Expired);
            }
        }
        if (r.stakeState == StakeState.Refundable) {
            stakeAmount = STAKE;
        }
        rewardAmount = r.rewardCredit;
        if (stakeAmount == 0 && rewardAmount == 0) {
            return (0, 0);
        }
        uint256 total = stakeAmount + rewardAmount;
        // Debit before interactions; every later failure rolls it back.
        if (stakeAmount > 0) {
            r.stakeState = StakeState.Refunded;
            _heldStakes -= STAKE;
        }
        if (rewardAmount > 0) {
            r.rewardCredit = 0;
            _rewardCredits -= rewardAmount;
        }
        address who = r.reporter;
        _payToken(_cfg.crvUSD, who, total);
        emit Claimed(reportId, who, stakeAmount, rewardAmount);
    }

    /// @notice Anyone; flushes only explicitly reserved forfeited liabilities.
    /// Never excess balance, unslashed stakes or unallocated escrow. Failure
    /// retains the liability (revert); refunds do not wait for flush.
    function flushDao(uint256 amount) external lock returns (uint256 flushed) {
        if (amount == 0 || amount > _daoLiability) revert BadAmount();
        FeeDistributorAccounting.preflight(_cfg.feeDistributor, _cfg.crvUSD);
        _daoLiability -= amount;
        FeeDistributorAccounting.depositAndAccount(_cfg.feeDistributor, _cfg.crvUSD, amount);
        flushed = amount;
        emit DaoFlushed(amount, BountyScripts.weekFloor(block.timestamp));
    }

    // ---------------------------------------------------------------------
    // Bound-V2 settlement hook (§5)
    // ---------------------------------------------------------------------

    /// @notice Bound V2 only. Requires the latched winner, its matching
    /// local recognized/unslashed/unallocated case and V2's just-written
    /// Confiscated listing with this report ID and exact B; sets the
    /// allocation, reserves B, pulls exactly B with both custody deltas
    /// checked; zero allowance afterward. The latch is never cleared —
    /// there is no second allocation for this listing, ever. No reporter
    /// external call.
    function creditReward(bytes32 reportId, uint256 amount) external lock {
        if (msg.sender != _lister) revert NotLister();
        Report storage r = _reports[reportId];
        if (r.reporter == address(0)) revert UnknownReport();
        if (r.phase != Phase.Recognized) revert BadPhase(); // one lifetime allocation
        if (amount == 0) revert BadAmount();
        // Independently verify the latched winner for this case's listing.
        if (_winnerLatch[r.listingId] != reportId) revert BadConfiguration();
        // And V2's actual terminal allocation (never merely an `eligible`
        // boolean): listing identity, report, the exact reporter half and
        // the half/gross allocation identity B = floor(R/2).
        bytes32 lid = ICurveGaugeListerV2(_lister).listingId(r.gauge);
        (
            bool fetched,
            bool decoded,,
            uint256 status,
            uint256 rewardReportId,
            uint256 reporterReward,
            uint256 confiscated
        ) = _facts(r.gauge);
        if (!fetched || !decoded) revert BadConfiguration();
        if (
            status != 3 || rewardReportId != uint256(reportId) || reporterReward != amount || lid != r.listingId
                || confiscated / 2 != amount
        ) {
            revert BadConfiguration();
        }
        // reporterReward == amount == floor(confiscated / 2) already implies
        // reporterReward <= confiscated; no additional subtraction guard is needed.
        // Transition BEFORE pulling; any failure rolls this back with both
        // funding legs (thin §2.2).
        r.phase = Phase.Rewarded;
        r.rewardCredit = amount;
        _rewardCredits += amount;
        _pullToken(_cfg.crvUSD, _lister, amount);
        emit ReportStateChanged(reportId, uint8(Phase.Rewarded));
        emit RewardCredited(reportId, amount);
    }
}
