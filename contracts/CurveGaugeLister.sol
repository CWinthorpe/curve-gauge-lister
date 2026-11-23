// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC20Minimal} from "./interfaces/IERC20Minimal.sol";
import {IListingController} from "./interfaces/IListingController.sol";
import {ICurveRegistry} from "./interfaces/ICurveRegistry.sol";
import {ICurveGauge} from "./interfaces/ICurveGauge.sol";
import {IFeeDistributor} from "./interfaces/IFeeDistributor.sol";
import {IIncentivePlatform} from "./interfaces/IIncentivePlatform.sol";
import {ITrustedGaugeValidator} from "./interfaces/ITrustedGaugeValidator.sol";
import {SafeToken} from "./libraries/SafeToken.sol";

/// @title CurveGaugeLister
/// @notice Fee-gated gauge lister with four-epoch bribe escrow and gauge-flag
/// confiscation to the fixed crvUSD FeeDistributor. Chain-1 only; starts
/// paused; paid admission requires the constructor-pinned trusted gauge
/// validator to return canonical true for the exact gauge.
/// plans/V1ALIGN-PLAN.md is the release authority for this amended source.
contract CurveGaugeLister {
    // ---------------------------------------------------------------------
    // Types (plan §3.1)
    // ---------------------------------------------------------------------

    enum Status {
        Unlisted,
        Active,
        Exhausted,
        Confiscated,
        DaoExempt
    }

    struct AdmissionConfig {
        address registry;
        uint8 maxCoins;
    }

    struct PlatformConfig {
        address votium;
        address voteMarket;
        uint16 votiumBps;
    }

    /// @dev Mapping key is gauge, not pool. `payer = msg.sender` for paid
    /// admission, `address(0)` for free admission. `listingEpoch` is the floored
    /// timestamp, not a week number. `epochsReleased` counts successfully funded
    /// quarters, not elapsed wall time; elapsed epochs are derived separately.
    struct Listing {
        address pool;
        address lpToken;
        address payer;
        address admissionRegistry;
        int128 gaugeType;
        uint256 listingEpoch;
        Status status;
        uint8 epochsReleased;
        uint256 deposited;
        uint256 remaining;
        uint256 released;
        uint256 confiscated;
        address votium;
        address voteMarket;
        uint16 votiumBps;
    }

    // ---------------------------------------------------------------------
    // Constants (plan §3.1 item 7)
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
    /// A new unvoted gauge is live while its explicit killed flag is false;
    /// controller weight is an emissions fact, never a kill signal.
    uint256 public constant INITIAL_WEIGHT = 0;

    /// @dev Conventional native-ETH sentinel accepted as a structural coin.
    address private constant NATIVE_SENTINEL = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /// @dev MetaRegistry ABI bounds (plan §4 step 3).
    uint256 private constant MAX_HANDLER_ID = 10;
    uint256 private constant MAX_GAUGE_INDEX = 10;

    // ---------------------------------------------------------------------
    // Storage (plan §3.1 logical layout)
    // ---------------------------------------------------------------------

    /// @notice Immutable fee token; never configurable after construction.
    address public immutable crvUSD;
    /// @notice Immutable controller abstraction (GaugeAdder adapter boundary).
    address public immutable controller;
    /// @notice Immutable confiscation destination.
    address public immutable feeDistributor;
    /// @notice Immutable pinned trusted gauge validator (plans/V1ALIGN-PLAN.md
    /// §2.1): the ONLY top-level read for paid admission is
    /// `validateGauge(gauge)` on this address. No setter, no default, no
    /// per-listing override, no configuration-tuple extension. Code presence
    /// at construction is a wiring guard, NOT proof of correct ABI, ownership,
    /// policy or authenticity; operators must supply the verified pin
    /// explicitly and reverify it.
    address public immutable trustedGaugeValidator;

    address public owner;
    address public pendingOwner;
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
    }

    mapping(address => StoredListing) private _listings;

    /// @notice Reserved liability: sum of `remaining` over all paid listings.
    uint256 public totalEscrow;

    /// @dev Private reentrancy-lock word, initialized unlocked.
    uint256 private _lockState = 1;

    // ---------------------------------------------------------------------
    // Events (plan §3.1)
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
    event EscrowConfiscated(address indexed gauge, address indexed feeDistributor, uint256 amount, uint256 receiptWeek);
    event FeeCheckpointResult(bool success);
    event PauseSet(bool paused);
    event AdmissionConfigSet(address registry, uint8 maxCoins);
    event PlatformConfigSet(address votium, address voteMarket, uint16 votiumBps);
    event OwnershipTransferStarted(address indexed owner, address indexed pendingOwner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    // ---------------------------------------------------------------------
    // Errors (names are executor-local per plan §3.1; semantics are not)
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
    error DistributorUnusable();
    error ConfiscationDeltaMismatch();
    /// @notice Construction outside chain 1 (plans/V1ALIGN-PLAN.md §2.1): the
    /// first constructor check; venue semantics are mainnet-keyed.
    error WrongChain();
    /// @notice Trusted-factory admission (plans/V1ALIGN-PLAN.md §2.1): the
    /// pinned validator's call SUCCEEDED with exactly 32 bytes containing
    /// canonical zero for this gauge. Includes underlying factory/module faults
    /// that the real validator itself collapses to false. Selector 0x6c706dca.
    error UntrustedGauge(address gauge);
    /// @notice Trusted-factory read fault (§2.1): the top-level call failed,
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
    // Construction (plan §3.1, §4 config validation, §7 platform validation)
    // ---------------------------------------------------------------------

    /// @notice Set the DAO owner and immutable settlement dependencies plus
    /// the pinned trusted gauge validator (plans/V1ALIGN-PLAN.md §2.1);
    /// validate all configuration before enabling paid admission. The core
    /// starts paused: owner-authenticated adapter bindings, controller
    /// authorization and deployment checks must complete before unpausing.
    /// @dev Require chain 1 FIRST (`WrongChain`); nonzero owner; code at
    /// token/controller/distributor/validator (`NoCode` covers zero and EOA
    /// inputs); token decimals exactly 18; `feeDistributor.token() == crvUSD_`;
    /// distributor not killed; valid admission and platform configs per plan
    /// sections 4 and 7. No address may be supplied by a lister. No fee
    /// transfer or platform approval occurs in construction. No
    /// `validateGauge` call is made at construction: there is no candidate
    /// gauge yet, and the validator code check is wiring validation only,
    /// never pin authentication.
    constructor(
        address owner_,
        address crvUSD_,
        address controller_,
        address feeDistributor_,
        AdmissionConfig memory admission_,
        PlatformConfig memory platforms_,
        address trustedGaugeValidator_
    ) {
        if (block.chainid != 1) revert WrongChain();
        if (owner_ == address(0)) revert ZeroOwner();
        if (crvUSD_.code.length == 0) revert NoCode(crvUSD_);
        if (controller_.code.length == 0) revert NoCode(controller_);
        if (feeDistributor_.code.length == 0) revert NoCode(feeDistributor_);
        if (trustedGaugeValidator_.code.length == 0) revert NoCode(trustedGaugeValidator_);
        if (IERC20Minimal(crvUSD_).decimals() != 18) revert BadAdmissionConfig();

        if (IFeeDistributor(feeDistributor_).token() != crvUSD_) revert DistributorUnusable();
        if (IFeeDistributor(feeDistributor_).is_killed()) revert DistributorUnusable();

        crvUSD = crvUSD_;
        controller = controller_;
        feeDistributor = feeDistributor_;
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
        // review1 finding 9: a mixed split onto one shared endpoint is unusable
        // (that adapter rejects the second same-gauge/same-epoch deposit, so a
        // frozen listing under it could never release). When both shares are
        // positive the endpoints must differ. 0/10000 single-share configs keep
        // the zero address allowed for the never-called side.
        if (uint256(cfg.votiumBps) > 0 && uint256(cfg.votiumBps) < BPS && cfg.votium == cfg.voteMarket) {
            revert BadPlatformConfig();
        }
        // A zero-share destination may be the zero address and is never called.
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

    /// @dev auditfix001 §2: refuse paid admission against unbound or
    /// incorrectly bound adapters. Every positive-share endpoint of the exact
    /// memory configuration about to be snapshotted into the listing must
    /// already be irrevocably bound to THIS lister. A zero-share endpoint is
    /// never read or called. Constructor/`setPlatformConfig` validation stays
    /// code/token/split-only: construction works before binding and staging
    /// unbound future endpoints remains permitted; readiness is enforced on
    /// every paid admission, including after configuration changes.
    function _requirePlatformsReady(PlatformConfig memory cfg) private view {
        if (cfg.votiumBps > 0) _requirePlatformReady(cfg.votium);
        if (cfg.votiumBps < BPS) _requirePlatformReady(cfg.voteMarket);
    }

    /// @dev A decoded different bound lister — including zero — reverts
    /// PlatformNotReady. A missing, reverting or malformed `lister()` getter
    /// propagates as a hard failure; it is never caught to continue.
    function _requirePlatformReady(address platform) private view {
        if (IIncentivePlatform(platform).lister() != address(this)) revert PlatformNotReady(platform);
    }

    /// @dev Trusted-factory admission (plans/V1ALIGN-PLAN.md §2.1): the single
    /// top-level read of the constructor-pinned validator for THIS candidate
    /// gauge. Only a successful staticcall returning exactly 32 bytes
    /// containing integer 1 accepts. Canonical zero is `UntrustedGauge`; a
    /// failed staticcall, a response length other than exactly 32, or a word
    /// above 1 is normalized to `TrustedGaugeCheckFailed` without bubbling
    /// checker error data. Malformed bool cannot escape via an unintended ABI
    /// decoder: the decode happens as uint256 AFTER the length guard. There is
    /// no fallback acceptance, cached true, soft warning, try/catch
    /// continuation, caller-based exception or owner bypass. This is checked
    /// for EACH new paid admission only — never at checkpoint/confiscate and
    /// never retroactively.
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
    // Business entry points (plan §4, §5, §6, §7)
    // ---------------------------------------------------------------------

    /// @notice Admit a registry-authenticated pool/gauge, require the
    /// constructor-pinned trusted gauge validator to accept this exact gauge,
    /// pull the exact fee, and call
    /// `controller.add_gauge(gauge, derivedType, INITIAL_WEIGHT)` immediately
    /// and atomically.
    /// @dev Anyone, including owner, may use this paid path; require not
    /// paused. Registry/structural admission runs FIRST; the trusted-factory
    /// read follows `_admit` and precedes platform readiness, any
    /// StoredListing/totalEscrow write, the fee transfer and controller
    /// addition, so trust never precedes registry authentication and never
    /// follows a custody or listing effect. On ANY failure revert fee,
    /// registry addition, local listing and events together. Do not read
    /// weight or require it to be nonzero. Do not call a bribe platform or
    /// FeeDistributor here. There is no owner exemption on this path.
    function listGauge(address pool, address gauge, uint256 gaugeIndex, uint256 handlerId) external lock {
        if (paused) revert ListingsPaused();
        AdmissionConfig memory cfg = _admissionConfig;
        PlatformConfig memory plat = _platformConfig;
        (address lpToken, int128 derivedType) = _admit(pool, gauge, gaugeIndex, handlerId, cfg);

        // V1ALIGN §2.1 ordering: exactly here, after `_admit` returns and
        // before readiness, listing write, `totalEscrow` accounting, fee
        // transfer or `controller.add_gauge`.
        _requireTrustedGauge(gauge);

        // auditfix001 §2: paid admission refuses unbound or misbound
        // adapters BEFORE any StoredListing/totalEscrow write, fee pull or
        // controller addition, on the same memory configuration snapshotted
        // into the listing below. `listGaugeNoEscrow` stays independent of
        // platform readiness.
        _requirePlatformsReady(plat);

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
    /// @dev Allowed while paused. Call `add_gauge` immediately with the supplied
    /// initial weight. Store `DaoExempt` and zero deposited/remaining/released/
    /// confiscated/epochsReleased and zero platform snapshots. Never require a
    /// token balance/allowance or call a platform for this path. Verify
    /// membership after addition; zero weight is valid for this path.
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
    /// @dev For Active state, read actual `gauge.is_killed()` before epoch
    /// arithmetic or platform calls. True confiscates; otherwise fund all
    /// currently matured, unpaid quarters in chronological order (maximum four).
    /// Works while paused. Unknown gauge reverts; all terminal states return
    /// `(0,0)` without external calls. Details in plan sections 5–7.
    function checkpoint(address gauge) external lock returns (uint256 releasedNow, uint256 confiscatedNow) {
        StoredListing storage rec = _listings[gauge];
        Status st = rec.status;
        if (st == Status.Unlisted) revert UnknownGauge(gauge);
        if (st != Status.Active) return (0, 0);

        // Step 1 of plan §5 (A2.3): authoritative gauge-flag read first. Never
        // infer kill from controller weight, a caller-supplied flag or a local
        // kill-intent mapping. A read/ABI failure reverts and preserves escrow;
        // there is no controller read on the settlement path.
        if (_gaugeKilled(gauge)) {
            confiscatedNow = _confiscate(gauge);
            return (0, confiscatedNow);
        }

        uint256 elapsed = _cappedElapsed(rec.listingEpoch);
        uint256 due = elapsed > uint256(rec.epochsReleased) ? elapsed - uint256(rec.epochsReleased) : 0;

        for (uint256 i = 0; i < due; ++i) {
            // Step 4 (A2.3): iteration zero reuses the authoritative initial
            // flag observation made above (only local epoch arithmetic ran in
            // between); every later tranche rereads immediately before its
            // outbound calls. True observed after an earlier quarter in the
            // transaction confiscates the remainder and stops the loop; a
            // read failure rolls back the entire checkpoint.
            if (i != 0 && _gaugeKilled(gauge)) {
                confiscatedNow = _confiscate(gauge);
                break;
            }
            uint256 scheduledEpoch = rec.listingEpoch + (uint256(rec.epochsReleased) + 1) * WEEK;

            // Step 5: checks-effects-interactions for this quarter.
            rec.epochsReleased += 1;
            totalEscrow -= QUARTER;
            releasedNow += QUARTER;

            _routeQuarter(gauge, rec, scheduledEpoch);

            emit QuarterReleased(gauge, scheduledEpoch, QUARTER, _remaining(rec));

            if (rec.epochsReleased == EPOCHS) {
                // Step 6: four funded quarters terminal; remaining is exactly 0.
                rec.status = Status.Exhausted;
            }
        }
    }

    /// @notice Anyone may execute gauge-flag confiscation between epochs, even
    /// in the listing epoch.
    /// @dev Same authoritative gauge-flag check and internal confiscation
    /// routine as `checkpoint`, but never releases bribes. Active/flag-false
    /// returns 0; terminal states return 0; unknown gauge reverts. It is not a
    /// DAO kill command.
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
    /// checkpoint.
    /// @dev Transfers no escrow and claims for no voter. Catch a checkpoint
    /// revert, emit its failure indication, return false; success returns true.
    /// No pause gate.
    function checkpointFees() external lock returns (bool checkpointed) {
        return _tryCheckpointToken();
    }

    // ---------------------------------------------------------------------
    // Owner entry points (plan §3.1)
    // ---------------------------------------------------------------------

    /// @notice Pause/unpause ONLY `listGauge`; keep DAO-free listing, releases
    /// and confiscation available. Emit even for a deliberate repeated setting.
    function setPaused(bool paused_) external onlyOwner lock {
        paused = paused_;
        emit PauseSet(paused_);
    }

    /// @notice Validate/store trusted registry and structural max-coins bound
    /// for new admissions; do not re-admit, kill, or rewrite existing gauges.
    function setAdmissionConfig(AdmissionConfig calldata config) external onlyOwner lock {
        _validateAdmission(config);
        _admissionConfig = config;
        emit AdmissionConfigSet(config.registry, config.maxCoins);
    }

    /// @notice Validate/store future-listing Votium/VoteMarket addresses and
    /// split; no transfer, arbitrary calldata execution, or existing-listing
    /// mutation.
    function setPlatformConfig(PlatformConfig calldata config) external onlyOwner lock {
        _validatePlatforms(config, crvUSD);
        _platformConfig = config;
        emit PlatformConfigSet(config.votium, config.voteMarket, config.votiumBps);
    }

    /// @notice Propose a nonzero new DAO owner; set/replace pendingOwner, not
    /// owner.
    function transferOwnership(address newOwner) external onlyOwner lock {
        if (newOwner == address(0)) revert ZeroOwner();
        pendingOwner = newOwner;
        emit OwnershipTransferStarted(owner, newOwner);
    }

    /// @notice Only pendingOwner may accept; update owner and clear pendingOwner.
    /// @dev No renounce-ownership method.
    function acceptOwnership() external lock {
        if (msg.sender != pendingOwner) revert NotPendingOwner();
        address previous = owner;
        owner = msg.sender;
        pendingOwner = address(0);
        emit OwnershipTransferred(previous, msg.sender);
    }

    // ---------------------------------------------------------------------
    // Read surface (plan §3.1)
    // ---------------------------------------------------------------------

    /// @notice Return the complete record; unknown returns the all-zero Unlisted
    /// record.
    function getListing(address gauge) external view returns (Listing memory) {
        Listing memory result;
        StoredListing storage rec = _listings[gauge];
        result.pool = rec.pool;
        result.lpToken = rec.lpToken;
        result.payer = rec.payer;
        result.admissionRegistry = rec.admissionRegistry;
        result.gaugeType = rec.gaugeType;
        result.listingEpoch = rec.listingEpoch;
        result.status = rec.status;
        result.epochsReleased = rec.epochsReleased;
        if (rec.status != Status.Unlisted && rec.status != Status.DaoExempt) {
            result.deposited = FEE;
            result.released = QUARTER * uint256(rec.epochsReleased);
            result.remaining = _remaining(rec);
            if (rec.status == Status.Confiscated) result.confiscated = FEE - result.released;
        }
        result.votium = rec.votium;
        result.voteMarket = rec.voteMarket;
        result.votiumBps = rec.votiumBps;
        return result;
    }

    function _remaining(StoredListing storage rec) private view returns (uint256) {
        return rec.status == Status.Active ? FEE - QUARTER * uint256(rec.epochsReleased) : 0;
    }

    /// @notice Return current future-admission configuration.
    function getAdmissionConfig() external view returns (AdmissionConfig memory) {
        return _admissionConfig;
    }

    /// @notice Return future-listing defaults, not a historical gauge's snapshot.
    function getPlatformConfig() external view returns (PlatformConfig memory) {
        return _platformConfig;
    }

    /// @notice For a paid record return capped elapsed epochs per plan §5;
    /// return 0 for Unlisted or DaoExempt. Does not claim that a matured tranche
    /// was funded.
    function epochsElapsed(address gauge) external view returns (uint256) {
        StoredListing storage rec = _listings[gauge];
        Status st = rec.status;
        if (st == Status.Unlisted || st == Status.DaoExempt) return 0;
        return _cappedElapsed(rec.listingEpoch);
    }

    /// @notice Return gross matured-but-unpaid amount only for Active/flag-false
    /// gauges; otherwise 0. Gauge read failures propagate, not treated as kills.
    function releasable(address gauge) external view returns (uint256) {
        StoredListing storage rec = _listings[gauge];
        if (rec.status != Status.Active) return 0;
        if (_gaugeKilled(gauge)) return 0;
        uint256 elapsed = _cappedElapsed(rec.listingEpoch);
        if (elapsed <= uint256(rec.epochsReleased)) return 0;
        return QUARTER * (elapsed - uint256(rec.epochsReleased));
    }

    /// @notice Floor a Unix timestamp to its Thursday-aligned Curve week.
    /// @dev Unix epoch zero is a Thursday, so plain flooring aligns to Thursday
    /// 00:00 UTC with no extra offset. The multiplication cannot overflow:
    /// `(timestamp / WEEK) * WEEK <= timestamp` for every uint256 input.
    function epochStart(uint256 timestamp) public pure returns (uint256) {
        unchecked {
            return (timestamp / WEEK) * WEEK;
        }
    }

    /// @notice Inspect immutable dependencies via generated getters for
    /// crvUSD/controller/feeDistributor; the following helpers keep the plan's
    /// read-surface intent explicit.

    // ---------------------------------------------------------------------
    // Internal routines
    // ---------------------------------------------------------------------

    function _cappedElapsed(uint256 listingEpoch) private view returns (uint256) {
        uint256 nowTime = block.timestamp;
        // listingEpoch is week-aligned, so flooring `now` before the
        // subtraction is unnecessary: elapsed weeks are identical whether
        // computed from the raw timestamp or its week floor. block.timestamp
        // is monotonic within the listing record's lifetime; guard only
        // against pathological pre-listing reads.
        if (nowTime <= listingEpoch) return 0;
        uint256 elapsed = (nowTime - listingEpoch) / WEEK;
        return elapsed > EPOCHS ? EPOCHS : elapsed;
    }

    /// @dev A2.3 kill oracle: killed-for-confiscation := `is_killed() == true`,
    /// ONLY. Shared by every settlement read point (checkpoint initial,
    /// per-tranche reread, confiscate, releasable). A read/ABI failure bubbles
    /// up and reverts; it is neither a kill nor permission to release.
    function _gaugeKilled(address gauge) private view returns (bool) {
        return ICurveGauge(gauge).is_killed();
    }

    /// @dev Shared admission checks for both listing paths (plan §4 steps 1–6).
    function _admit(address pool, address gauge, uint256 gaugeIndex, uint256 handlerId, AdmissionConfig memory cfg)
        private
        view
        returns (address lpToken, int128 derivedType)
    {
        // Step 1: nonzero pool/gauge with code. (Pause/owner gates are in the
        // respective entry points.)
        if (pool == address(0) || gauge == address(0)) revert ZeroTarget();
        if (pool.code.length == 0) revert NoCode(pool);
        if (gauge.code.length == 0) revert NoCode(gauge);

        // Step 2: permanent local uniqueness by gauge, forever.
        if (_listings[gauge].status != Status.Unlisted) revert AlreadyListed(gauge);
        // A successful gauge_types result means already registered elsewhere.
        // The expected absent-gauge revert permits continuing; the subsequent
        // add_gauge and membership postcondition are the health proof.
        try IListingController(controller).gauge_types(gauge) returns (int128) {
            revert ControllerRegistryOccupied(gauge);
        } catch {}

        // Step 3: MetaRegistry ABI bounds and trusted-registry provenance.
        if (handlerId >= MAX_HANDLER_ID || gaugeIndex >= MAX_GAUGE_INDEX) revert IndexOutOfRange();
        if (!ICurveRegistry(cfg.registry).is_registered(pool, handlerId)) revert PoolNotRegistered();
        lpToken = ICurveRegistry(cfg.registry).get_lp_token(pool, handlerId);

        // Step 4: gauge provenance and LP identity.
        if (ICurveRegistry(cfg.registry).get_gauge(pool, gaugeIndex, handlerId) != gauge) revert GaugeMismatch();
        if (lpToken == address(0) || lpToken.code.length == 0) revert BadLpToken();
        if (ICurveGauge(gauge).lp_token() != lpToken) revert BadLpToken();

        // Step 5: admission-time liveness and handler-derived type.
        if (ICurveGauge(gauge).is_killed()) revert GaugeKilledAtAdmission();
        derivedType = ICurveRegistry(cfg.registry).get_gauge_type(pool, gaugeIndex, handlerId);
        if (derivedType < 0 || derivedType >= IListingController(controller).n_gauge_types()) {
            revert BadGaugeType();
        }

        // Step 6: structural coin checks on the used slots only.
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
        // LP token cannot use the native sentinel: enforced by its code check.
    }

    /// @dev Route one matured quarter's gross split using this gauge's immutable
    /// snapshot (plan §7). Every failure reverts the entire checkpoint.
    function _routeQuarter(address gauge, StoredListing storage rec, uint256 scheduledEpoch) private {
        uint256 votiumAmount = (QUARTER * uint256(rec.votiumBps)) / BPS;
        uint256 voteMarketAmount = QUARTER - votiumAmount; // remainder to VoteMarket
        // Zero-amount destinations are skipped altogether (never called).
        if (votiumAmount > 0) _fundPlatform(gauge, rec.votium, scheduledEpoch, votiumAmount);
        if (voteMarketAmount > 0) _fundPlatform(gauge, rec.voteMarket, scheduledEpoch, voteMarketAmount);
    }

    /// @dev force-approve only that amount, deposit, require nonzero receipt and
    /// exact lister balance decrease, clear allowance to zero, then emit
    /// PlatformDeposit.
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

    /// @dev Plan §6 + auditfix001 §3 confiscation routine, shared by
    /// checkpoint/confiscate. The caller path has just observed Active plus
    /// `gauge.is_killed() == true`. POLICY: revert the entire confiscation if
    /// safe accounting cannot complete in this transaction — retaining escrow
    /// is preferable to committing an unrecoverable allocation omission; a
    /// later best-effort retry cannot restore an already consumed delta.
    function _confiscate(address gauge) private returns (uint256 amount) {
        StoredListing storage rec = _listings[gauge];
        address fd = feeDistributor;
        // Step 1: fixed FeeDistributor must remain a usable destination.
        if (fd.code.length == 0) revert DistributorUnusable();
        if (IFeeDistributor(fd).token() != crvUSD) revert DistributorUnusable();
        if (IFeeDistributor(fd).is_killed()) revert DistributorUnusable();

        // Step 2 (auditfix001 §3): the real allocation cursor must be FRESH,
        // read BEFORE any terminal effect or transfer: nonzero, not in the
        // future, and within the distributor's bounded 20-week accounting
        // horizon measured from the cursor's week floor — equivalently
        // now <= H = epochStart(t) + 20*WEEK (the first partial week
        // consumes one of the 20 loop iterations; `now == H` is permitted,
        // `H + 1` is rejected). The subtraction cannot underflow in this
        // short-circuit order. This bound is private confiscation logic, not
        // a public constant or getter.
        uint256 t = IFeeDistributor(fd).last_token_time();
        if (t == 0) revert DistributorUnusable();
        if (t > block.timestamp) revert DistributorUnusable();
        if (block.timestamp - epochStart(t) > 20 * WEEK) revert DistributorUnusable();

        // Step 3: effects before token interaction.
        amount = _remaining(rec);
        uint256 receiptWeek = epochStart(block.timestamp);
        rec.status = Status.Confiscated;
        totalEscrow -= amount;

        // Step 4: exact direct transfer with two-sided delta verification.
        uint256 listerBefore = IERC20Minimal(crvUSD).balanceOf(address(this));
        uint256 fdBefore = IERC20Minimal(crvUSD).balanceOf(fd);
        SafeToken.safeTransfer(crvUSD, fd, amount);
        if (IERC20Minimal(crvUSD).balanceOf(address(this)) != listerBefore - amount) {
            revert ConfiscationDeltaMismatch();
        }
        if (IERC20Minimal(crvUSD).balanceOf(fd) != fdBefore + amount) revert ConfiscationDeltaMismatch();

        // Step 5 (auditfix001 §3): mandatory atomic accounting in the SAME
        // transaction: call checkpoint_token directly, WITHOUT a swallowed
        // revert and with no pre-transfer checkpoint, then require the cursor
        // at now and the accounted balance equal to the distributor's actual
        // custody; otherwise DistributorUnusable. Read/decode failures also
        // revert. No false result is ever committed by confiscation.
        IFeeDistributor(fd).checkpoint_token();
        if (IFeeDistributor(fd).last_token_time() != block.timestamp) revert DistributorUnusable();
        if (IFeeDistributor(fd).token_last_balance() != IERC20Minimal(crvUSD).balanceOf(fd)) {
            revert DistributorUnusable();
        }

        // Step 6: custody and accounting-success events, in this order.
        emit EscrowConfiscated(gauge, fd, amount, receiptWeek);
        emit FeeCheckpointResult(true);
    }

    /// @dev Best-effort `checkpoint_token()` for the STANDALONE
    /// `checkpointFees()` maintenance path only (auditfix001 §3:
    /// `_confiscate` performs mandatory accounting itself and no longer calls
    /// this helper): catch a revert WITHOUT reverting anything else; emit its
    /// outcome. A standalone FeeCheckpointResult(true) means the upstream
    /// call returned, NOT that arbitrary stale pre-existing fees were fully
    /// allocated.
    function _tryCheckpointToken() private returns (bool ok) {
        try IFeeDistributor(feeDistributor).checkpoint_token() {
            emit FeeCheckpointResult(true);
            ok = true;
        } catch {
            emit FeeCheckpointResult(false);
        }
    }
}
