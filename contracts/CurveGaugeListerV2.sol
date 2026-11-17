// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC20Minimal} from "./interfaces/IERC20Minimal.sol";
import {IListingController} from "./interfaces/IListingController.sol";
import {ICurveRegistry} from "./interfaces/ICurveRegistry.sol";
import {ICurveGauge} from "./interfaces/ICurveGauge.sol";
import {IFeeDistributor} from "./interfaces/IFeeDistributor.sol";
import {IIncentivePlatform} from "./interfaces/IIncentivePlatform.sol";
import {SafeToken} from "./libraries/SafeToken.sol";
import {FeeDistributorAccounting} from "./libraries/FeeDistributorAccounting.sol";
import {ICurveGaugeListerV2} from "./interfaces/ICurveGaugeListerV2.sol";
import {IGaugeBounty} from "./interfaces/IGaugeBounty.sol";
import {ITrustedGaugeValidator} from "./interfaces/ITrustedGaugeValidator.sol";
import {BountyConfig, ReportView, Phase} from "./bounty/BountyTypes.sol";

/// @title CurveGaugeListerV2
/// @notice Versioned prospective lister for NEW admissions only
/// (plans/BOUNTY-PLAN.md §1): source-derived from the accepted
/// CurveGaugeLister with a single split-confiscation routine, an immutable
/// bounty binding, and paid-admission readiness. No migration, upgrade,
/// retrofit or transfer of V1 escrows; V1's all-FeeDistributor economics
/// continue unchanged. V1 is NOT amended and does not carry the paid
/// trusted-factory guarantee below. Every unaffected routine is retained from
/// the reviewed V1 source; the V1-to-V2 delta is exactly: constructor binding
/// + chain 1 + paused start; paid-admission bounty readiness; the 18-field
/// ListingV2 tuple; the versioned EscrowConfiscated event; the split
/// allocation routine; `bounty()`/`listingId()`; the four original new errors;
/// and, per plans/TRUSTEDFACTORY-PLAN.md, the constructor-pinned
/// `trustedGaugeValidator` with the paid-admission trust read that runs after
/// registry/structural admission and before readiness, listing/escrow
/// accounting, fee transfer and `controller.add_gauge` — together with the
/// two additional errors `UntrustedGauge`/`TrustedGaugeCheckFailed`. The
/// owner-only `listGaugeNoEscrow` lane performs no trust read.
contract CurveGaugeListerV2 {
    // ---------------------------------------------------------------------
    // Types (plan §1.2; shared with the hook interface)
    // ---------------------------------------------------------------------

    enum Status {
        Unlisted,
        Active,
        Exhausted,
        Confiscated,
        DaoExempt
    }

    /// @dev Storage-encoding widths mirror V1 exactly: the Status enum is the
    /// uint8 wire type of `ListingV2.status`.
    struct AdmissionConfig {
        address registry;
        uint8 maxCoins;
    }

    struct PlatformConfig {
        address votium;
        address voteMarket;
        uint16 votiumBps;
    }

    // ---------------------------------------------------------------------
    // Constants (V1 §3.1 item 7, retained verbatim)
    // ---------------------------------------------------------------------

    /// @notice Seconds in one Curve week (Thursday 00:00 UTC boundaries).
    uint256 public constant WEEK = 604800;
    /// @notice Exact paid admission fee in crvUSD base units.
    uint256 public constant FEE = 10_000e18;
    /// @notice Gross tranche released per matured epoch.
    uint256 public constant QUARTER = 2_500e18;
    /// @notice Number of drip epochs.
    uint256 public constant EPOCHS = 4;
    /// @notice Basis-point denominator for the platform split.
    uint256 public constant BPS = 10_000;
    /// @notice Raw controller weight stamped at paid admission, per A2: zero.
    uint256 public constant INITIAL_WEIGHT = 0;

    /// @dev Conventional native-ETH sentinel accepted as a structural coin.
    address private constant NATIVE_SENTINEL = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /// @dev MetaRegistry ABI bounds (plan §4 step 3).
    uint256 private constant MAX_HANDLER_ID = 10;
    uint256 private constant MAX_GAUGE_INDEX = 10;

    /// @dev Half of an odd remainder goes to the reporter reserve; rounding
    /// residue belongs to the FD (§4.1).
    uint256 private constant SPLIT_DIVISOR = 2;

    // ---------------------------------------------------------------------
    // Storage (plan §1.2, §4.2)
    // ---------------------------------------------------------------------

    /// @notice Immutable fee token; never configurable after construction.
    address public immutable crvUSD;
    /// @notice Immutable controller abstraction (GaugeAdder adapter boundary).
    address public immutable controller;
    /// @notice Immutable confiscation destination.
    address public immutable feeDistributor;
    /// @notice Immutable reverse pointer to the bound GaugeBounty (§1.2:
    /// V2's reverse pointer is a Solidity immutable; no setter).
    address public immutable bounty;
    /// @notice Immutable pinned trusted gauge validator
    /// (plans/TRUSTEDFACTORY-PLAN.md §3.1): the ONLY top-level read for paid
    /// admission is `validateGauge(gauge)` on this address. No setter, no
    /// default, no per-listing override, no configuration-tuple extension.
    /// Code presence at construction is a wiring guard, NOT proof of correct
    /// ABI, ownership, policy or authenticity; operators must supply the
    /// verified pin explicitly and reverify it.
    address public immutable trustedGaugeValidator;

    address public owner;
    address public pendingOwner;
    /// @dev V2 starts paused (§1.2); wiring must finish before unpausing.
    bool public paused;

    AdmissionConfig private _admissionConfig;
    PlatformConfig private _platformConfig;

    struct StoredListing {
        address pool;
        Status status;
        uint8 epochsReleased;
        address lpToken;
        address payer;
        address admissionRegistry;
        int128 gaugeType;
        uint256 listingEpoch;
        address votium;
        address voteMarket;
        uint16 votiumBps;
        // §1.2 appended allocation destinations: cumulative ORIGINAL split
        // amounts at the first successful seizure; zero before seizure.
        uint256 reporterReward;
        bytes32 rewardReportId;
    }

    mapping(address => StoredListing) private _listings;

    /// @notice Reserved liability: sum of `remaining` over all paid listings.
    uint256 public totalEscrow;

    /// @dev Private reentrancy-lock word, initialized unlocked.
    uint256 private _lockState = 1;

    // ---------------------------------------------------------------------
    // Events (V1 set retained EXCEPT the versioned confiscation event)
    // ---------------------------------------------------------------------

    event GaugeListed(
        address indexed gauge,
        address indexed pool,
        address indexed payer,
        int128 gaugeType,
        uint256 listingEpoch,
        uint256 fee,
        bool daoExempt
    );
    event PlatformDeposit(
        address indexed gauge,
        address indexed platform,
        uint256 indexed scheduledEpoch,
        uint256 executionEpoch,
        uint256 amount,
        bytes32 receipt
    );
    event QuarterReleased(address indexed gauge, uint256 indexed scheduledEpoch, uint256 amount, uint256 remaining);
    /// @notice V2 version of V1's EscrowConfiscated: the gross field is NOT
    /// an FD receipt; `reporterReward + fdConfiscated == gross`. Emitted only
    /// after both funding legs and FD accounting succeed.
    event EscrowConfiscated(
        address indexed gauge,
        address indexed feeDistributor,
        bytes32 indexed reportId,
        uint256 gross,
        uint256 reporterReward,
        uint256 fdConfiscated,
        uint256 receiptWeek
    );
    event FeeCheckpointResult(bool success);
    event PauseSet(bool paused);
    event AdmissionConfigSet(address registry, uint8 maxCoins);
    event PlatformConfigSet(address votium, address voteMarket, uint16 votiumBps);
    event OwnershipTransferStarted(address indexed owner, address indexed pendingOwner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    // ---------------------------------------------------------------------
    // Errors: V1 set retained verbatim; four BOUNTY-PLAN additions plus the
    // two trusted-factory additions (six total). Shared FD failures
    // use FeeDistributorAccounting.DistributorUnusable /
    // ConfiscationDeltaMismatch so the accepted selectors stay recognizable;
    // SafeToken errors remain reachable through the unchanged library.
    // ---------------------------------------------------------------------

    error ZeroOwner();
    error ZeroTarget();
    error NoCode(address target);
    error NotOwner();
    error NotPendingOwner();
    error ListingsPaused();
    error Reentrancy();
    error BadAdmissionConfig();
    error BadPlatformConfig();
    error UnknownGauge(address gauge);
    error AlreadyListed(address gauge);
    error ControllerRegistryOccupied(address gauge);
    error IndexOutOfRange();
    error PoolNotRegistered();
    error GaugeMismatch();
    error BadLpToken();
    error GaugeKilledAtAdmission();
    error BadGaugeType();
    error BadCoinCount();
    error BadCoin();
    error FeeDeltaMismatch();
    error MembershipFailed();
    error PlatformDeltaMismatch(address platform);
    error PlatformReceiptMissing(address platform);
    error PlatformNotReady(address platform);
    error WrongChain();
    error BadBounty();
    error BountyNotReady();
    error BountyDeltaMismatch();
    /// @notice Trusted-factory admission (plans/TRUSTEDFACTORY-PLAN.md §3.3):
    /// the pinned validator's call SUCCEEDED with exactly 32 bytes containing
    /// canonical zero for this gauge. Includes underlying factory/module faults
    /// that the real validator itself collapses to false. Selector 0x6c706dca.
    error UntrustedGauge(address gauge);
    /// @notice Trusted-factory read fault (§3.3): the top-level call failed,
    /// the response length is not exactly 32 bytes, or the decoded uint256
    /// word exceeds 1. Checker error data is normalized here, never bubbled
    /// as the specified error. Selector 0x7835e9b7.
    error TrustedGaugeCheckFailed(address gauge);

    modifier lock() {
        if (_lockState != 1) revert Reentrancy();
        _lockState = 2;
        _;
        _lockState = 1;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    // ---------------------------------------------------------------------
    // Construction (plan §1.2)
    // ---------------------------------------------------------------------

    /// @notice Set the DAO owner and immutable settlement dependencies plus
    /// the bounty binding and the pinned trusted gauge validator
    /// (plans/TRUSTEDFACTORY-PLAN.md §3.1); validate all configuration before
    /// enabling paid admission. V2 starts paused.
    /// @dev Retains every V1 constructor validation and additionally:
    /// chain 1; code at bounty; matching bounty config token/FD; compatible
    /// write-once lister binding (zero before binding, or this address); code
    /// at `trustedGaugeValidator_` (`NoCode` covers zero and EOA inputs). The
    /// validator code check is a minimum wiring guard only — there is no
    /// candidate gauge at construction and no constructor `validateGauge`
    /// call is made or required. Adapters and bounty binding are NOT required
    /// at construction; readiness is enforced on every paid admission. No fee
    /// transfer or platform approval occurs here.
    constructor(
        address owner_,
        address crvUSD_,
        address controller_,
        address feeDistributor_,
        AdmissionConfig memory admission_,
        PlatformConfig memory platforms_,
        address bounty_,
        address trustedGaugeValidator_
    ) {
        if (block.chainid != 1) revert WrongChain();
        if (owner_ == address(0)) revert ZeroOwner();
        if (crvUSD_.code.length == 0) revert NoCode(crvUSD_);
        if (controller_.code.length == 0) revert NoCode(controller_);
        if (feeDistributor_.code.length == 0) revert NoCode(feeDistributor_);
        if (trustedGaugeValidator_.code.length == 0) revert NoCode(trustedGaugeValidator_);
        if (IERC20Minimal(crvUSD_).decimals() != 18) revert BadAdmissionConfig();

        if (IFeeDistributor(feeDistributor_).token() != crvUSD_) revert FeeDistributorAccounting.DistributorUnusable();
        if (IFeeDistributor(feeDistributor_).is_killed()) revert FeeDistributorAccounting.DistributorUnusable();

        if (bounty_.code.length == 0) revert BadBounty();
        BountyConfig memory bcfg = IGaugeBounty(bounty_).config();
        if (bcfg.crvUSD != crvUSD_) revert BadBounty();
        if (bcfg.feeDistributor != feeDistributor_) revert BadBounty();
        address bound = IGaugeBounty(bounty_).lister();
        if (bound != address(0) && bound != address(this)) revert BadBounty();

        crvUSD = crvUSD_;
        controller = controller_;
        feeDistributor = feeDistributor_;
        bounty = bounty_;
        trustedGaugeValidator = trustedGaugeValidator_;
        owner = owner_;
        paused = true;

        _validateAdmission(admission_);
        _validatePlatforms(platforms_, crvUSD_);
        _admissionConfig = admission_;
        _platformConfig = platforms_;
    }

    function _validateAdmission(AdmissionConfig memory cfg) private view {
        if (cfg.registry == address(0) || cfg.registry.code.length == 0) revert BadAdmissionConfig();
        if (cfg.maxCoins < 2 || cfg.maxCoins > 8) revert BadAdmissionConfig();
    }

    function _validatePlatforms(PlatformConfig memory cfg, address token) private view {
        if (cfg.votiumBps > BPS) revert BadPlatformConfig();
        // review1 finding 9 retained: a mixed split onto one shared endpoint
        // is unusable; 0/10000 single-share configs keep the zero address
        // allowed for the never-called side.
        if (uint256(cfg.votiumBps) > 0 && uint256(cfg.votiumBps) < BPS && cfg.votium == cfg.voteMarket) {
            revert BadPlatformConfig();
        }
        if (uint256(cfg.votiumBps) > 0) _validatePlatformTarget(cfg.votium, token);
        if (BPS - uint256(cfg.votiumBps) > 0) _validatePlatformTarget(cfg.voteMarket, token);
    }

    function _validatePlatformTarget(address platform, address token) private view {
        if (platform == address(0) || platform == address(this) || platform == token) {
            revert BadPlatformConfig();
        }
        if (platform.code.length == 0) revert BadPlatformConfig();
        if (IIncentivePlatform(platform).rewardToken() != token) revert BadPlatformConfig();
    }

    /// @dev auditfix001 §2 retained: paid admission refuses unbound or
    /// misbound adapters BEFORE any write, pull or controller addition.
    function _requirePlatformsReady(PlatformConfig memory cfg) private view {
        if (cfg.votiumBps > 0) _requirePlatformReady(cfg.votium);
        if (cfg.votiumBps < BPS) _requirePlatformReady(cfg.voteMarket);
    }

    function _requirePlatformReady(address platform) private view {
        if (IIncentivePlatform(platform).lister() != address(this)) revert PlatformNotReady(platform);
    }

    /// @dev §1.2: on EVERY paid admission, before fee/effects/controller
    /// addition, the bounty's write-once binding must reciprocate.
    function _requireBountyReady() private view {
        if (IGaugeBounty(bounty).lister() != address(this)) revert BountyNotReady();
    }

    /// @dev Trusted-factory admission (plans/TRUSTEDFACTORY-PLAN.md §3.2/§3.3):
    /// the single top-level read of the constructor-pinned validator for THIS
    /// candidate gauge. Only a successful staticcall returning exactly 32
    /// bytes containing integer 1 accepts. Canonical zero is `UntrustedGauge`;
    /// a failed staticcall, a response length other than exactly 32, or a word
    /// above 1 is normalized to `TrustedGaugeCheckFailed` without bubbling
    /// checker error data. Malformed bool cannot escape via an unintended ABI
    /// decoder: the decode happens as uint256 AFTER the length guard. There is
    /// no fallback acceptance, cached true, soft warning, try/catch
    /// continuation, caller-based exception or owner bypass. This is checked
    /// for EACH new paid admission only — never at
    /// checkpoint/confiscate/report/claim and never retroactively.
    function _requireTrustedGauge(address gauge) private view {
        (bool ok, bytes memory data) =
            trustedGaugeValidator.staticcall(abi.encodeCall(ITrustedGaugeValidator.validateGauge, (gauge)));
        if (!ok) revert TrustedGaugeCheckFailed(gauge);
        if (data.length != 32) revert TrustedGaugeCheckFailed(gauge);
        uint256 verdict = abi.decode(data, (uint256));
        if (verdict == 0) revert UntrustedGauge(gauge);
        if (verdict > 1) revert TrustedGaugeCheckFailed(gauge);
    }

    // ---------------------------------------------------------------------
    // Business entry points
    // ---------------------------------------------------------------------

    /// @notice Admit a registry-authenticated pool/gauge, require the
    /// constructor-pinned trusted gauge validator to accept this exact gauge,
    /// pull the exact fee, and call
    /// `controller.add_gauge(gauge, derivedType, INITIAL_WEIGHT)` immediately
    /// and atomically.
    /// @dev Anyone, including owner, may use this paid path; require not
    /// paused. Registry/structural admission runs FIRST; the trusted-factory
    /// read follows `_admit` and precedes paid readiness (adapters + bounty),
    /// listing/escrow accounting, the fee transfer and controller addition,
    /// so trust never precedes registry authentication and never follows a
    /// custody or listing effect. On ANY failure revert fee, registry
    /// addition, local listing and events together. There is no owner
    /// exemption on this path.
    function listGauge(address pool, address gauge, uint256 gaugeIndex, uint256 handlerId) external lock {
        if (paused) revert ListingsPaused();
        AdmissionConfig memory cfg = _admissionConfig;
        PlatformConfig memory plat = _platformConfig;
        (address lpToken, int128 derivedType) = _admit(pool, gauge, gaugeIndex, handlerId, cfg);

        // TRUSTEDFACTORY §3.2 ordering: exactly here, after `_admit` returns
        // and before any readiness, listing write, `totalEscrow` accounting,
        // fee transfer or `controller.add_gauge`.
        _requireTrustedGauge(gauge);

        _requirePlatformsReady(plat);
        _requireBountyReady();

        StoredListing storage rec = _listings[gauge];
        rec.pool = pool;
        rec.lpToken = lpToken;
        rec.payer = msg.sender;
        rec.admissionRegistry = cfg.registry;
        rec.gaugeType = derivedType;
        rec.listingEpoch = epochStart(block.timestamp);
        rec.status = Status.Active;
        rec.votium = plat.votium;
        rec.voteMarket = plat.voteMarket;
        rec.votiumBps = plat.votiumBps;
        totalEscrow += FEE;

        uint256 balBefore = IERC20Minimal(crvUSD).balanceOf(address(this));
        SafeToken.safeTransferFrom(crvUSD, msg.sender, address(this), FEE);
        if (IERC20Minimal(crvUSD).balanceOf(address(this)) != balBefore + FEE) revert FeeDeltaMismatch();

        IListingController(controller).add_gauge(gauge, derivedType, INITIAL_WEIGHT);
        if (IListingController(controller).gauge_types(gauge) != derivedType) revert MembershipFailed();

        emit GaugeListed(gauge, pool, msg.sender, derivedType, rec.listingEpoch, FEE, false);
    }

    /// @notice DAO-owner-only addition with no fee, using the same structural
    /// admission checks and permanent duplicate protections.
    /// @dev Allowed while paused. DAO-free admission does NOT depend on bounty
    /// readiness (§1.2): no bounty/platform read gates this path. It is also
    /// entirely independent of the trusted gauge validator
    /// (plans/TRUSTEDFACTORY-PLAN.md §1): this lane performs NO trust read,
    /// including when the validator returns false, faults or has no code.
    /// Non-factory gauges remain legitimate DAO-listed candidates subject to
    /// the unchanged registry/structural requirements.
    function listGaugeNoEscrow(
        address pool,
        address gauge,
        uint256 gaugeIndex,
        uint256 handlerId,
        uint256 initialWeight
    ) external lock {
        if (msg.sender != owner) revert NotOwner();
        AdmissionConfig memory cfg = _admissionConfig;
        (address lpToken, int128 derivedType) = _admit(pool, gauge, gaugeIndex, handlerId, cfg);

        StoredListing storage rec = _listings[gauge];
        rec.pool = pool;
        rec.lpToken = lpToken;
        rec.admissionRegistry = cfg.registry;
        rec.gaugeType = derivedType;
        rec.listingEpoch = epochStart(block.timestamp);
        rec.status = Status.DaoExempt;

        IListingController(controller).add_gauge(gauge, derivedType, initialWeight);
        if (IListingController(controller).gauge_types(gauge) != derivedType) revert MembershipFailed();

        emit GaugeListed(gauge, pool, address(0), derivedType, rec.listingEpoch, 0, true);
    }

    /// @notice Anyone may settle this gauge.
    /// @dev Retained V1 semantics: authoritative gauge-flag read first; true
    /// enters the single split-confiscation routine; terminal states return
    /// (0,0) before any external dependency.
    function checkpoint(address gauge) external lock returns (uint256 releasedNow, uint256 confiscatedNow) {
        StoredListing storage rec = _listings[gauge];
        Status st = rec.status;
        if (st == Status.Unlisted) revert UnknownGauge(gauge);
        if (st != Status.Active) return (0, 0);

        if (_gaugeKilled(gauge)) {
            confiscatedNow = _confiscate(gauge);
            return (0, confiscatedNow);
        }

        uint256 elapsed = _cappedElapsed(rec.listingEpoch);
        uint256 due = elapsed > uint256(rec.epochsReleased) ? elapsed - uint256(rec.epochsReleased) : 0;

        for (uint256 i = 0; i < due; ++i) {
            if (i != 0 && _gaugeKilled(gauge)) {
                confiscatedNow = _confiscate(gauge);
                break;
            }
            uint256 scheduledEpoch = rec.listingEpoch + (uint256(rec.epochsReleased) + 1) * WEEK;

            rec.epochsReleased += 1;
            totalEscrow -= QUARTER;
            releasedNow += QUARTER;

            _routeQuarter(gauge, rec, scheduledEpoch);

            emit QuarterReleased(gauge, scheduledEpoch, QUARTER, _remaining(rec));

            if (rec.epochsReleased == EPOCHS) {
                rec.status = Status.Exhausted;
            }
        }
    }

    /// @notice Anyone may execute gauge-flag confiscation between epochs.
    /// @dev Same authoritative flag check and the SAME private allocation
    /// routine as `checkpoint`; never releases bribes.
    function confiscate(address gauge) external lock returns (uint256 amount) {
        StoredListing storage rec = _listings[gauge];
        Status st = rec.status;
        if (st == Status.Unlisted) revert UnknownGauge(gauge);
        if (st != Status.Active) return 0;
        if (_gaugeKilled(gauge)) {
            amount = _confiscate(gauge);
        }
    }

    /// @notice Permissionless best-effort retry of the FeeDistributor token
    /// checkpoint. Transfers no escrow and claims for no voter.
    function checkpointFees() external lock returns (bool checkpointed) {
        return _tryCheckpointToken();
    }

    // ---------------------------------------------------------------------
    // Owner entry points
    // ---------------------------------------------------------------------

    /// @notice Pause/unpause ONLY `listGauge`; keep DAO-free listing, releases
    /// and confiscation available.
    function setPaused(bool paused_) external onlyOwner lock {
        paused = paused_;
        emit PauseSet(paused_);
    }

    function setAdmissionConfig(AdmissionConfig calldata config) external onlyOwner lock {
        _validateAdmission(config);
        _admissionConfig = config;
        emit AdmissionConfigSet(config.registry, config.maxCoins);
    }

    function setPlatformConfig(PlatformConfig calldata config) external onlyOwner lock {
        _validatePlatforms(config, crvUSD);
        _platformConfig = config;
        emit PlatformConfigSet(config.votium, config.voteMarket, config.votiumBps);
    }

    function transferOwnership(address newOwner) external onlyOwner lock {
        if (newOwner == address(0)) revert ZeroOwner();
        pendingOwner = newOwner;
        emit OwnershipTransferStarted(owner, newOwner);
    }

    function acceptOwnership() external lock {
        if (msg.sender != pendingOwner) revert NotPendingOwner();
        address previous = owner;
        owner = msg.sender;
        pendingOwner = address(0);
        emit OwnershipTransferred(previous, msg.sender);
    }

    // ---------------------------------------------------------------------
    // Read surface (plan §1.3 plus plans/TRUSTEDFACTORY-PLAN.md §3.4:
    // exactly 32 callables, including `trustedGaugeValidator()`)
    // ---------------------------------------------------------------------

    /// @notice Return the complete ListingV2 record; unknown returns the
    /// all-zero Unlisted record. Local only (§1.3 row 17).
    function getListing(address gauge) external view returns (ICurveGaugeListerV2.ListingV2 memory result) {
        StoredListing storage rec = _listings[gauge];
        result.pool = rec.pool;
        result.lpToken = rec.lpToken;
        result.payer = rec.payer;
        result.admissionRegistry = rec.admissionRegistry;
        result.gaugeType = rec.gaugeType;
        result.listingEpoch = rec.listingEpoch;
        result.status = uint8(rec.status);
        result.epochsReleased = rec.epochsReleased;
        if (rec.status != Status.Unlisted && rec.status != Status.DaoExempt) {
            result.deposited = FEE;
            result.released = QUARTER * uint256(rec.epochsReleased);
            result.remaining = _remaining(rec);
            if (rec.status == Status.Confiscated) {
                result.confiscated = FEE - result.released;
                result.reporterReward = rec.reporterReward;
                result.fdConfiscated = result.confiscated - rec.reporterReward;
                result.rewardReportId = rec.rewardReportId;
            }
        }
        result.votium = rec.votium;
        result.voteMarket = rec.voteMarket;
        result.votiumBps = rec.votiumBps;
    }

    function _remaining(StoredListing storage rec) private view returns (uint256) {
        return rec.status == Status.Active ? FEE - QUARTER * uint256(rec.epochsReleased) : 0;
    }

    function getAdmissionConfig() external view returns (AdmissionConfig memory) {
        return _admissionConfig;
    }

    function getPlatformConfig() external view returns (PlatformConfig memory) {
        return _platformConfig;
    }

    function epochsElapsed(address gauge) external view returns (uint256) {
        StoredListing storage rec = _listings[gauge];
        Status st = rec.status;
        if (st == Status.Unlisted || st == Status.DaoExempt) return 0;
        return _cappedElapsed(rec.listingEpoch);
    }

    /// @notice Flag oracle only: gross matured-but-unpaid for Active/flag-
    /// false gauges; otherwise 0. Gauge read failures propagate.
    function releasable(address gauge) external view returns (uint256) {
        StoredListing storage rec = _listings[gauge];
        if (rec.status != Status.Active) return 0;
        if (_gaugeKilled(gauge)) return 0;
        uint256 elapsed = _cappedElapsed(rec.listingEpoch);
        if (elapsed <= uint256(rec.epochsReleased)) return 0;
        return QUARTER * (elapsed - uint256(rec.epochsReleased));
    }

    /// @notice Floor a Unix timestamp to its Thursday-aligned Curve week.
    function epochStart(uint256 timestamp) public pure returns (uint256) {
        unchecked {
            return (timestamp / WEEK) * WEEK;
        }
    }

    /// @notice Permanent listing ID (§1.2): keccak256(abi.encode(uint256(1),
    /// address(this), gauge)) for any listed gauge; unknown returns zero.
    /// `listingEpoch` is not a nonce; no relisting makes this ambiguous.
    function listingId(address gauge) external view returns (bytes32) {
        if (_listings[gauge].status == Status.Unlisted) return bytes32(0);
        return keccak256(abi.encode(uint256(1), address(this), gauge));
    }

    // ---------------------------------------------------------------------
    // Internal routines
    // ---------------------------------------------------------------------

    function _cappedElapsed(uint256 listingEpoch) private view returns (uint256) {
        uint256 nowTime = block.timestamp;
        if (nowTime <= listingEpoch) return 0;
        uint256 elapsed = (nowTime - listingEpoch) / WEEK;
        return elapsed > EPOCHS ? EPOCHS : elapsed;
    }

    /// @dev A2.3 kill oracle retained: ONLY actual gauge.is_killed(); read/ABI
    /// failure reverts settlement; never a controller read.
    function _gaugeKilled(address gauge) private view returns (bool) {
        return ICurveGauge(gauge).is_killed();
    }

    /// @dev Shared admission checks for both listing paths (V1 plan §4 steps
    /// 1–6), retained verbatim.
    function _admit(address pool, address gauge, uint256 gaugeIndex, uint256 handlerId, AdmissionConfig memory cfg)
        private
        view
        returns (address lpToken, int128 derivedType)
    {
        if (pool == address(0) || gauge == address(0)) revert ZeroTarget();
        if (pool.code.length == 0) revert NoCode(pool);
        if (gauge.code.length == 0) revert NoCode(gauge);

        if (_listings[gauge].status != Status.Unlisted) revert AlreadyListed(gauge);
        try IListingController(controller).gauge_types(gauge) returns (int128) {
            revert ControllerRegistryOccupied(gauge);
        } catch {}

        if (handlerId >= MAX_HANDLER_ID || gaugeIndex >= MAX_GAUGE_INDEX) revert IndexOutOfRange();
        if (!ICurveRegistry(cfg.registry).is_registered(pool, handlerId)) revert PoolNotRegistered();
        lpToken = ICurveRegistry(cfg.registry).get_lp_token(pool, handlerId);

        if (ICurveRegistry(cfg.registry).get_gauge(pool, gaugeIndex, handlerId) != gauge) revert GaugeMismatch();
        if (lpToken == address(0) || lpToken.code.length == 0) revert BadLpToken();
        if (ICurveGauge(gauge).lp_token() != lpToken) revert BadLpToken();

        if (ICurveGauge(gauge).is_killed()) revert GaugeKilledAtAdmission();
        derivedType = ICurveRegistry(cfg.registry).get_gauge_type(pool, gaugeIndex, handlerId);
        if (derivedType < 0 || derivedType >= IListingController(controller).n_gauge_types()) {
            revert BadGaugeType();
        }

        uint256 n = ICurveRegistry(cfg.registry).get_n_coins(pool, handlerId);
        if (n < 2 || n > uint256(cfg.maxCoins)) revert BadCoinCount();
        address[8] memory coins = ICurveRegistry(cfg.registry).get_coins(pool, handlerId);
        for (uint256 i = 0; i < n; ++i) {
            address c = coins[i];
            if (c == address(0)) revert BadCoin();
            for (uint256 j = 0; j < i; ++j) {
                if (coins[j] == c) revert BadCoin();
            }
            if (c != NATIVE_SENTINEL && c.code.length == 0) revert BadCoin();
        }
    }

    /// @dev Route one matured quarter's gross split using this gauge's
    /// immutable snapshot (V1 plan §7), retained verbatim.
    function _routeQuarter(address gauge, StoredListing storage rec, uint256 scheduledEpoch) private {
        uint256 votiumAmount = (QUARTER * uint256(rec.votiumBps)) / BPS;
        uint256 voteMarketAmount = QUARTER - votiumAmount;
        if (votiumAmount > 0) _fundPlatform(gauge, rec.votium, scheduledEpoch, votiumAmount);
        if (voteMarketAmount > 0) _fundPlatform(gauge, rec.voteMarket, scheduledEpoch, voteMarketAmount);
    }

    /// @dev V1-faithful funded platform leg: force-approve exact, deposit,
    /// require nonzero receipt and exact debit, clear allowance, emit.
    function _fundPlatform(address gauge, address platform, uint256 scheduledEpoch, uint256 amount) private {
        uint256 balBefore = IERC20Minimal(crvUSD).balanceOf(address(this));
        SafeToken.forceApprove(crvUSD, platform, amount);
        bytes32 receipt = IIncentivePlatform(platform).deposit(gauge, scheduledEpoch, amount);
        if (receipt == bytes32(0)) revert PlatformReceiptMissing(platform);
        uint256 balAfter = IERC20Minimal(crvUSD).balanceOf(address(this));
        if (balBefore - balAfter != amount) revert PlatformDeltaMismatch(platform);
        SafeToken.forceApprove(crvUSD, platform, 0);
        emit PlatformDeposit(gauge, platform, scheduledEpoch, epochStart(block.timestamp), amount, receipt);
    }

    /// @dev Plan §4.1 SINGLE split-confiscation routine, reached only after
    /// Active plus an authoritative true flag, from BOTH confiscate() and the
    /// true branch of checkpoint(). Atomic order (§4.1 steps 1–5):
    ///  1. FD preflight and bounty terms read/consistency BEFORE effects.
    ///  2. Effects: Confiscated, totalEscrow debit, gross/B/F/reportId.
    ///  3. Exact B approval + bounty creditReward + debit/allowance checks.
    ///  4. Exact F direct transfer + mandatory FD accounting.
    ///  5. Versioned event, then FeeCheckpointResult(true).
    /// A caught bounty terms/funding failure NEVER silently routes the
    /// reporter half to the FD: the whole seizure reverts and retries.
    function _confiscate(address gauge) private returns (uint256 amount) {
        StoredListing storage rec = _listings[gauge];
        address fd = feeDistributor;

        // Step 1: accepted preflight before effects or either transfer.
        FeeDistributorAccounting.preflight(fd, crvUSD);

        // Step 1 (cont.): bounty terms, then recipient/report consistency.
        (bytes32 reportId, address termsReporter, bool eligible) = IGaugeBounty(bounty).rewardTerms(gauge);
        uint256 reporterReward = 0;
        if (eligible) {
            ReportView memory rv = IGaugeBounty(bounty).getReport(reportId);
            // A normally decoded INELIGIBLE term is the all-FD branch; an
            // "eligible" claim that fails consistency is a funding-integrity
            // failure and reverts the whole seizure. The stake disposition
            // deliberately does NOT gate the reward: forfeiture only ever
            // moves the bond (thin §3.2).
            if (
                rv.gauge != gauge || rv.reporter != termsReporter || termsReporter == address(0)
                    || uint8(rv.phase) != uint8(Phase.Recognized)
                    || rv.listingId != keccak256(abi.encode(uint256(1), address(this), gauge)) || rv.rewardCredit != 0
            ) {
                revert BountyDeltaMismatch();
            }
            uint256 r = _remaining(rec);
            reporterReward = r / SPLIT_DIVISOR; // floor; residue to FD
        }

        // Step 2: effects before token interaction (no second seizure).
        amount = _remaining(rec);
        uint256 fdShare = amount - reporterReward;
        uint256 receiptWeek = epochStart(block.timestamp);
        bytes32 allocatedReportId = reporterReward > 0 ? reportId : bytes32(0);
        rec.status = Status.Confiscated;
        totalEscrow -= amount;
        rec.reporterReward = reporterReward;

        rec.rewardReportId = allocatedReportId;

        // Step 3: exact B approval, funded credit, exact debit, zeroed
        // allowance. No reporter external call; B only ever moves to bounty
        // custody.
        if (reporterReward > 0) {
            uint256 balBefore = IERC20Minimal(crvUSD).balanceOf(address(this));
            SafeToken.forceApprove(crvUSD, bounty, reporterReward);
            IGaugeBounty(bounty).creditReward(reportId, reporterReward);
            if (IERC20Minimal(crvUSD).balanceOf(address(this)) != balBefore - reporterReward) {
                revert BountyDeltaMismatch();
            }
            if (IERC20Minimal(crvUSD).allowance(address(this), bounty) != 0) revert BountyDeltaMismatch();
        }

        // Step 4: exact F direct transfer + mandatory same-transaction
        // accounting. Earlier bounty funding/effects in this transaction roll
        // back if this fails.
        FeeDistributorAccounting.depositAndAccount(fd, crvUSD, fdShare);

        // Step 5: custody and accounting-success events, in this order. The
        // event's reportId mirrors the recorded allocation (zero when B=0),
        // so a normally-decoded ineligible case never attaches a reward
        // association to the seizure — exactly like `rewardReportId`.
        emit EscrowConfiscated(gauge, fd, allocatedReportId, amount, reporterReward, fdShare, receiptWeek);
        emit FeeCheckpointResult(true);
    }

    /// @dev Standalone best-effort checkpointFees helper, retained from V1.
    function _tryCheckpointToken() private returns (bool ok) {
        try IFeeDistributor(feeDistributor).checkpoint_token() {
            emit FeeCheckpointResult(true);
            ok = true;
        } catch {
            emit FeeCheckpointResult(false);
        }
    }
}
