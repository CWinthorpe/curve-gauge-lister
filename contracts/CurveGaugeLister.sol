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
import {CurveWeek} from "./libraries/CurveWeek.sol";

/// @title CurveGaugeLister
/// @notice Fee-gated gauge lister with four-epoch bribe escrow and gauge-flag
/// confiscation to the fixed crvUSD FeeDistributor. Chain-1 only; starts
/// paused; paid admission requires the constructor-pinned trusted gauge
/// validator to return canonical true for the exact gauge.
/// @dev The candidate-bound release evidence package — normative plan, ABI
/// manifest, witness inventory and gate receipts, including the dependency
/// proofs — is held by the project owner and producible on demand; "plan §"
/// markers in this file name sections of that owner-held specification.
/// Neither a historical comment nor a generated interface reference is an
/// independent release authority.
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
    uint256 public constant WEEK = CurveWeek.WEEK;
    /// @notice Exact paid admission fee in crvUSD base units: the fixed
    /// tranche identity (CX-CONSTANTS) — exactly `QUARTER * EPOCHS`, so the
    /// fee cannot silently drift from the drip schedule. Value, getter,
    /// layout and every reserve transition are unchanged; the literal
    /// economics (10,000e18 total, 2,500e18 per tranche, four tranches) keep
    /// their independent witnesses in the offline suite.
    uint256 public constant FEE = QUARTER * EPOCHS;
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

    /// @dev Named boundary of the FeeDistributor accounting proof (plan §6,
    /// auditfix001 §3): the real deployed allocator (`CurveFeeDistribution.vy`
    /// `_checkpoint_token`) apportions the accumulated fee-token delta across
    /// at most 20 whole-week iterations starting at the cursor's week floor,
    /// so a cursor older than 20 weeks would have its omitted tail discarded
    /// (verified against the selected allocator's source and, at release,
    /// re-read at its runtime per docs/DEPLOYMENT-PINS.md). This constant is
    /// that COVERAGE horizon: `block.timestamp <= epochStart(t) +
    /// FD_ACCOUNTING_HORIZON_WEEKS * WEEK`. It is private confiscation logic,
    /// not a public constant or getter, and it is distinct from the
    /// allocator's separate PUBLIC-ELIGIBILITY cooldown (`can_checkpoint_token`
    /// and strictly `now > t + 86400` for a non-admin caller such as this
    /// contract) — neither requirement implies the other.
    uint256 private constant FD_ACCOUNTING_HORIZON_WEEKS = 20;

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
        // review1 finding 9 (rationale per S21): under a mixed split the two
        // legs of one quarter arrive at the shared address as two same-key
        // (gauge, scheduledEpoch) calls; the concrete rejecting case is
        // VoteMarket's duplicate-key guard (its witness rejects the second
        // key before funding), so a frozen mixed listing under one shared
        // endpoint could never fully release. The rule forbids aliasing the
        // two PRODUCT venue roles onto one endpoint; it is not a universal
        // adapter rule — Votium's live-round witness separately expects
        // multiple same-gauge entries in one round, which is not permission
        // to merge the venue roles. When both shares are positive the
        // endpoints must differ. 0/10000 single-share configs keep the zero
        // address allowed for the never-called side. Call predicates come
        // from the one computed split (S11): an interior basis-point leg is
        // positive exactly when its share amount is nonzero.
        (uint256 votiumAmount, uint256 voteMarketAmount) = _quarterSplit(cfg.votiumBps);
        if (votiumAmount > 0 && voteMarketAmount > 0 && cfg.votium == cfg.voteMarket) {
            revert BadPlatformConfig();
        }
        // A zero-share destination may be the zero address and is never called.
        if (votiumAmount > 0) _validatePlatformTarget(cfg.votium, token);
        if (voteMarketAmount > 0) _validatePlatformTarget(cfg.voteMarket, token);
    }

    function _validatePlatformTarget(address platform, address token) private view {
        if (platform == address(0) || platform == address(this) || platform == token) {
            revert BadPlatformConfig();
        }
        if (platform.code.length == 0) revert BadPlatformConfig();
        if (IIncentivePlatform(platform).rewardToken() != token) revert BadPlatformConfig();
    }

    /// @dev auditfix001 §2 (binding, named as binding per S06): refuse paid
    /// admission against unbound or incorrectly bound adapters. Every
    /// positive-share endpoint of the exact memory configuration about to be
    /// snapshotted into the listing must already be irrevocably BOUND to THIS
    /// lister (the adapter's write-once `setLister` result — see the venue
    /// guarantee lifetime matrix in docs/OPERATIONS.md). A zero-share endpoint
    /// is never read or called. Constructor/`setPlatformConfig` validation
    /// stays code/token/split-only: construction works before binding and
    /// staging unbound future endpoints remains permitted; the binding check
    /// is enforced on every paid admission, including after configuration
    /// changes. Public guards and diagnostics are unchanged.
    function _requireAdaptersBound(PlatformConfig memory cfg) private view {
        (uint256 votiumAmount, uint256 voteMarketAmount) = _quarterSplit(cfg.votiumBps);
        if (votiumAmount > 0) _requireAdapterBound(cfg.votium);
        if (voteMarketAmount > 0) _requireAdapterBound(cfg.voteMarket);
    }

    /// @dev A decoded different bound lister — including zero — reverts
    /// PlatformNotReady (binding diagnostic; name retained). A missing,
    /// reverting or malformed `lister()` getter propagates as a hard failure;
    /// it is never caught to continue.
    function _requireAdapterBound(address platform) private view {
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
        // adapter binding.
        _requireAdaptersBound(plat);

        StoredListing storage rec = _writeAdmittedRecord(gauge, pool, lpToken, derivedType, cfg);
        // Paid-lane-specific assignments stay here (CX-ADMIT): the actual
        // payer, Active status, and the frozen platform snapshot.
        rec.payer = msg.sender;
        rec.status = Status.Active;
        rec.votium = plat.votium;
        rec.voteMarket = plat.voteMarket;
        rec.votiumBps = plat.votiumBps;
        totalEscrow += FEE;

        uint256 balBefore = IERC20Minimal(crvUSD).balanceOf(address(this));
        SafeToken.safeTransferFrom(crvUSD, msg.sender, address(this), FEE);
        if (IERC20Minimal(crvUSD).balanceOf(address(this)) != balBefore + FEE) revert FeeDeltaMismatch();

        _seatMembership(gauge, derivedType, INITIAL_WEIGHT);

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

        StoredListing storage rec = _writeAdmittedRecord(gauge, pool, lpToken, derivedType, cfg);
        // DAO-lane-specific assignment stays here (CX-ADMIT): DaoExempt
        // status. The zero payer and the zero monetary/platform snapshot are
        // the fresh record's defaults — this lane stamps no fee, escrow or
        // venue endpoints.
        rec.status = Status.DaoExempt;

        _seatMembership(gauge, derivedType, initialWeight);

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

        uint256 due = _maturedUnpaid(rec.listingEpoch, rec.epochsReleased);

        for (uint256 i = 0; i < due; ++i) {
            // Step 4 (A2.3): the kill-observation unit is the QUARTER, not
            // the leg (CX-QUARTER). Iteration zero reuses the authoritative
            // initial flag observation made above (only local epoch
            // arithmetic ran in between — the initial read covers tranche
            // one because nothing observable happened since); every later
            // tranche rereads immediately before its outbound calls because
            // a kill may have landed after the earlier tranche funded.
            // Within one quarter the two positive-share legs commit as a
            // unit: `_settleMaturedQuarter`/`_routeQuarter` perform no
            // flag read between the legs, so a flag change observed at all
            // is observed at the NEXT quarter boundary. True observed after
            // an earlier quarter in the transaction confiscates the
            // remainder and stops the loop; a read failure rolls back the
            // entire checkpoint. Neither one read per call nor per-leg
            // reads are equivalent.
            if (i != 0 && _gaugeKilled(gauge)) {
                confiscatedNow = _confiscate(gauge);
                break;
            }
            _settleMaturedQuarter(gauge, rec);
            releasedNow += QUARTER;
        }
    }

    /// @dev One complete quarter transition in the plan §5 effect/routing/
    /// event/status order: bump the funded counter and reserve, route the
    /// matured tranche's split using the record's frozen snapshot, emit the
    /// quarter release with the post-effect Active-only remainder, then move
    /// to Exhausted at four funded quarters. The quarter's two venue legs
    /// commit as one unit — the kill flag is observed per quarter, never
    /// per leg (CX-QUARTER). Called only from the `checkpoint` loop, which
    /// owns the quarter-boundary observation points; the whole call keeps
    /// all-due atomicity under the outer lock.
    function _settleMaturedQuarter(address gauge, StoredListing storage rec) private {
        uint256 scheduledEpoch = rec.listingEpoch + (uint256(rec.epochsReleased) + 1) * WEEK;

        // Step 5: checks-effects-interactions for this quarter.
        rec.epochsReleased += 1;
        totalEscrow -= QUARTER;

        _routeQuarter(gauge, rec, scheduledEpoch);

        emit QuarterReleased(gauge, scheduledEpoch, QUARTER, _remaining(rec));

        if (rec.epochsReleased == EPOCHS) {
            // Step 6: four funded quarters terminal; remaining is exactly 0.
            rec.status = Status.Exhausted;
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
    /// checkpoint. For the approved ordinary public-caller configuration,
    /// canonical zero-delta housekeeping is the direct `checkpoint_token()`
    /// maintenance on the FeeDistributor itself (its own caller/cooldown
    /// rules apply); this wrapper is retained convenience, not settlement
    /// evidence.
    /// @dev Transfers no escrow and claims for no voter. Catch a checkpoint
    /// revert, emit its failure indication, return false; success returns true.
    /// A standalone true means only that the upstream call returned — the
    /// evidence for successful escrow accounting is `EscrowConfiscated`,
    /// committed by `_confiscate` exclusively after exact-custody and the
    /// mandatory in-transaction accounting postchecks succeed. No pause gate.
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
    /// @dev Single documented materialization point of the public tuple (S14):
    /// every derived monetary display cell comes from the shared funded-amount
    /// helper below. Field order, provenance (the record's own stored fields),
    /// Active-only `remaining`, zero Unlisted/DAO monetary fields, terminal
    /// amounts and the explicit aggregate liability `totalEscrow` are all
    /// preserved. Custody can include donations: neither balance nor a
    /// matured-due figure may be substituted for these amounts.
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
            result.released = _releasedAmount(rec.epochsReleased);
            result.remaining = _remaining(rec);
            if (rec.status == Status.Confiscated) result.confiscated = FEE - result.released;
        }
        result.votium = rec.votium;
        result.voteMarket = rec.voteMarket;
        result.votiumBps = rec.votiumBps;
        return result;
    }

    /// @dev Single-source gross amount already funded for a record's funded
    /// quarter count (S14): shared by the Active-only remainder and the
    /// public display above. A matured-due count is a different quantity
    /// (see `_maturedUnpaid`) and never substitutes for it.
    function _releasedAmount(uint8 epochsReleased) private pure returns (uint256) {
        return QUARTER * uint256(epochsReleased);
    }

    function _remaining(StoredListing storage rec) private view returns (uint256) {
        return rec.status == Status.Active ? FEE - _releasedAmount(rec.epochsReleased) : 0;
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
    /// @dev The due count is the shared capped elapsed-minus-funded computation,
    /// not `getListing.remaining`: elapsed weeks never include future
    /// maturities, while `remaining` is the Active-only monetary balance.
    function releasable(address gauge) external view returns (uint256) {
        StoredListing storage rec = _listings[gauge];
        if (rec.status != Status.Active) return 0;
        if (_gaugeKilled(gauge)) return 0;
        return QUARTER * _maturedUnpaid(rec.listingEpoch, rec.epochsReleased);
    }

    /// @notice Floor a Unix timestamp to its Thursday-aligned Curve week.
    /// @dev Delegates to the single production floor convention
    /// (`CurveWeek.floorWeek`); public ABI shape unchanged.
    function epochStart(uint256 timestamp) public pure returns (uint256) {
        return CurveWeek.floorWeek(timestamp);
    }

    /// @notice Inspect immutable dependencies via generated getters for
    /// crvUSD/controller/feeDistributor; the following helpers keep the plan's
    /// read-surface intent explicit.

    // ---------------------------------------------------------------------
    // Internal routines
    // ---------------------------------------------------------------------

    function _cappedElapsed(uint256 listingEpoch) private view returns (uint256) {
        // Precondition (chain-1 record invariant): `listingEpoch` is stored
        // only from `epochStart(block.timestamp)` when a paid record is
        // admitted, so it is never later than the block timestamp of any
        // later settlement read, and elapsed counts are computed only from
        // admitted paid records — never from caller-supplied or future
        // anchors. Equality already yields zero, so no separate floor or
        // early-return is needed; the subtraction cannot underflow under
        // this documented precondition. The cap is retained.
        uint256 elapsed = (block.timestamp - listingEpoch) / WEEK;
        return elapsed > EPOCHS ? EPOCHS : elapsed;
    }

    /// @dev Single source of the matured-unpaid quarter count: capped
    /// elapsed weeks minus successfully funded quarters, never below zero.
    /// Shared by `checkpoint`'s loop bound and `releasable`'s gross quote so
    /// the external quote and all-due execution stay in agreement while
    /// keeping their distinct purposes (due count vs monetary remaining).
    function _maturedUnpaid(uint256 listingEpoch, uint8 epochsReleased) private view returns (uint256) {
        uint256 elapsed = _cappedElapsed(listingEpoch);
        return elapsed > uint256(epochsReleased) ? elapsed - uint256(epochsReleased) : 0;
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

    /// @dev Shared admitted-record assignments for both listing lanes
    /// (CX-ADMIT): exactly the five identical writes (pool, authenticated LP
    /// token, provenance registry, derived type, floored listing epoch) of a
    /// freshly admitted record. The admission gates are NOT merged here: the
    /// owner/pause checks stay in the respective entry points, structural
    /// checks run inside `_admit` before the paid lane's trust read, and all
    /// lane-specific fields stay at the call sites.
    function _writeAdmittedRecord(
        address gauge,
        address pool,
        address lpToken,
        int128 derivedType,
        AdmissionConfig memory cfg
    ) private returns (StoredListing storage rec) {
        rec = _listings[gauge];
        rec.pool = pool;
        rec.lpToken = lpToken;
        rec.admissionRegistry = cfg.registry;
        rec.gaugeType = derivedType;
        rec.listingEpoch = epochStart(block.timestamp);
    }

    /// @dev Shared immediate typed-membership work for both listing lanes
    /// (CX-ADMIT): the caller-authorized `add_gauge` with this lane's
    /// initial weight (paid: `INITIAL_WEIGHT` zero; DAO: owner-supplied),
    /// then the SAME-transaction membership postcheck that is the health
    /// proof. Weight values stay lane-specific per plan law; the postcheck
    /// is identical, and a failed or mismatched membership reverts the whole
    /// call — no lane gate is hoisted ahead of `_admit` here.
    function _seatMembership(address gauge, int128 derivedType, uint256 initialWeight) private {
        IListingController(controller).add_gauge(gauge, derivedType, initialWeight);
        if (IListingController(controller).gauge_types(gauge) != derivedType) revert MembershipFailed();
    }

    /// @dev One computed split of one gross QUARTER (S11): Votium takes the
    /// basis-point floor, VoteMarket the remainder. The same amounts are the
    /// single source of truth for which destinations are read or called —
    /// zero share means never read, never called — at prospective
    /// configuration validation, admission binding-readiness and frozen-record
    /// routing. The current constants make every interior basis-point leg
    /// positive, so amount-derived predicates match the historical bps
    /// predicates; split-bound validation stays first at both validation sites.
    function _quarterSplit(uint16 votiumBps) private pure returns (uint256 votiumAmount, uint256 voteMarketAmount) {
        votiumAmount = (QUARTER * uint256(votiumBps)) / BPS;
        voteMarketAmount = QUARTER - votiumAmount; // remainder to VoteMarket
    }

    /// @dev Route one matured quarter's gross split using this gauge's immutable
    /// snapshot (plan §7). Every failure reverts the entire checkpoint.
    function _routeQuarter(address gauge, StoredListing storage rec, uint256 scheduledEpoch) private {
        (uint256 votiumAmount, uint256 voteMarketAmount) = _quarterSplit(rec.votiumBps);
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
        // Directional exact-delta check (CX-ADAPTER): direction first via
        // the shared outbound-delta predicate, then the exact debit amount,
        // so an opposite-direction observation surfaces through the named
        // error instead of an arithmetic Panic.
        if (!_exactOutboundDelta(balBefore, balAfter, amount)) revert PlatformDeltaMismatch(platform);
        SafeToken.forceApprove(crvUSD, platform, 0);
        emit PlatformDeposit(gauge, platform, scheduledEpoch, epochStart(block.timestamp), amount, receipt);
    }

    /// @dev Shared direction-first outbound-delta predicate for the two
    /// core debit checks (CX-ADAPTER, used by `_fundPlatform` and
    /// `_confiscate`): an observation moving the balance UP fails before any
    /// subtraction, and only an exact `-amount` delta passes. It is
    /// deliberately NOT equated to the inbound-credit comparison (which
    /// stays in addition form at the FeeDistributor boundary) nor to a
    /// baseline-equality check; each custody boundary keeps its own exact,
    /// named comparison and its own error.
    function _exactOutboundDelta(uint256 before_, uint256 after_, uint256 amount) private pure returns (bool) {
        if (after_ > before_) return false;
        return before_ - after_ == amount;
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
        // future, and within the named coverage horizon
        // `FD_ACCOUNTING_HORIZON_WEEKS`, measured from the cursor's week
        // floor — equivalently now <= H = epochStart(t) +
        // FD_ACCOUNTING_HORIZON_WEEKS * WEEK (the first partial week
        // consumes one of the allocator's bounded loop iterations; `now == H`
        // is permitted, `H + 1` is rejected). The subtraction cannot
        // underflow in this short-circuit order. The bound mirrors the
        // selected allocator's source loop (docs/DEPLOYMENT-PINS.md
        // re-verification records the runtime bytes; the fixture model is
        // contracts/mocks/MockFeeDistributor.sol `_doCheckpointToken`). The
        // caller rule stays separate: as an ordinary non-admin caller the
        // lister additionally needs the allocator's public-checkpoint
        // eligibility (strict cooldown), which is availability, not coverage.
        // This bound is private confiscation logic, not a public constant or
        // getter.
        uint256 t = IFeeDistributor(fd).last_token_time();
        if (t == 0) revert DistributorUnusable();
        if (t > block.timestamp) revert DistributorUnusable();
        if (block.timestamp - epochStart(t) > FD_ACCOUNTING_HORIZON_WEEKS * WEEK) revert DistributorUnusable();

        // Step 3: effects before token interaction. The exact confiscatable
        // remainder is derived from the funded-quarter count directly,
        // independent of the status filter used by the public display
        // (CX-AMOUNT): both callers gate on Active before entering `_confiscate`,
        // so this equals the Active-only `_remaining` observation here while
        // the custody amount no longer routes through the display's status
        // predicate. Status/liability order is unchanged, the terminal no-op
        // guards stay at the call sites, and the public Active-only
        // `remaining` display is untouched.
        amount = FEE - _releasedAmount(rec.epochsReleased);
        uint256 receiptWeek = epochStart(block.timestamp);
        rec.status = Status.Confiscated;
        totalEscrow -= amount;

        // Step 4: exact direct transfer with two-sided delta verification.
        // The debit side uses the shared direction-first predicate (an
        // opposite-direction observation must surface through the named
        // error, never an arithmetic Panic); the credit side stays in
        // addition form — the two boundaries are deliberately not equated
        // (CX-ADAPTER).
        uint256 listerBefore = IERC20Minimal(crvUSD).balanceOf(address(this));
        uint256 fdBefore = IERC20Minimal(crvUSD).balanceOf(fd);
        SafeToken.safeTransfer(crvUSD, fd, amount);
        uint256 listerAfter = IERC20Minimal(crvUSD).balanceOf(address(this));
        if (!_exactOutboundDelta(listerBefore, listerAfter, amount)) {
            revert ConfiscationDeltaMismatch();
        }
        uint256 fdAfter = IERC20Minimal(crvUSD).balanceOf(fd);
        if (fdAfter != fdBefore + amount) revert ConfiscationDeltaMismatch();

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
        // `EscrowConfiscated` is the completion signal for escrow
        // accounting (CX-MAINT): it commits only after exact custody and
        // both mandatory postchecks. The accompanying
        // `FeeCheckpointResult(true)` is retained compatibility telemetry on
        // the confiscation path — the same event name carries the separate,
        // weaker best-effort maintenance meaning when the standalone
        // `checkpointFees()` wrapper emits it (see `_tryCheckpointToken`).
        emit EscrowConfiscated(gauge, fd, amount, receiptWeek);
        emit FeeCheckpointResult(true);
    }

    /// @dev Best-effort `checkpoint_token()` for the STANDALONE
    /// `checkpointFees()` maintenance path only (auditfix001 §3:
    /// `_confiscate` performs mandatory accounting itself and no longer calls
    /// this helper). Canonical ordinary zero-delta maintenance is the direct
    /// FeeDistributor `checkpoint_token()` call; this wrapper is retained
    /// convenience. Catch a revert WITHOUT reverting anything else; emit its
    /// outcome. A standalone FeeCheckpointResult(true) means the upstream
    /// call returned, NOT that arbitrary stale pre-existing fees were fully
    /// allocated and NOT escrow-accounting success (that evidence is
    /// `EscrowConfiscated` from `_confiscate`).
    function _tryCheckpointToken() private returns (bool ok) {
        try IFeeDistributor(feeDistributor).checkpoint_token() {
            emit FeeCheckpointResult(true);
            ok = true;
        } catch {
            emit FeeCheckpointResult(false);
        }
    }
}
