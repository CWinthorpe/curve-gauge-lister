// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title ICanonicalController
/// @notice Narrow local declaration of the fixed upstream GaugeController ABI
/// this router actually uses (plans/ROUTERPLAN-SPEC.md §1/§4). Declared
/// locally: the product has ZERO import statements and no external Solidity
/// dependency. `add_gauge(address,int128,uint256)`, `gauge_types(address)`
/// and `n_gauge_types()` agree with the product dependency subset in
/// contracts/interfaces/IListingController.sol; the admin entries mirror the
/// real controller's two-step ownership mechanics that R mediates.
interface ICanonicalController {
    function admin() external view returns (address);
    function future_admin() external view returns (address);
    function commit_transfer_ownership(address successor) external;
    function apply_transfer_ownership() external;
    function add_gauge(address gauge, int128 gaugeType, uint256 weight) external;
    function gauge_types(address gauge) external view returns (int128);
    function n_gauge_types() external view returns (int128);
}

/// @title GaugeControllerAdmin
/// @notice Fixed-authority Curve DAO controller router (role R): an immutable
/// pinned canonical GaugeController C and an immutable Curve DAO executor D.
/// Only D grants/revokes adders, invokes generic controller execution, and
/// initiates or completes the two-step C-administration handback. After a
/// successful handback apply the router is permanently retired for every
/// mutation; canonical reads survive. R is never a funds holder: every call
/// to C is an ordinary zero-value CALL, nothing is payable, and there is no
/// receive/fallback, deposit, withdrawal, rescue or approval surface.
/// @dev Normative specification: plans/ROUTERPLAN-SPEC.md (field/function/
/// event/error binding) with the machine-readable manifest
/// plans/ROUTERPLAN-ABI.json and the governance sequencing
/// plans/ROUTERPLAN-DEPLOYMENT.md. The candidate-bound conformance evidence
/// package is owner-held and producible on demand; this header is a
/// reference, not an independent authority.
contract GaugeControllerAdmin {
    // ------------------------------------------------------------------
    // Storage and construction (SPEC §2)
    // ------------------------------------------------------------------

    /// @notice Immutable pinned canonical controller C. Embedded in the
    /// runtime code as an immutable; no storage slot; never changes.
    address public immutable controller;
    /// @notice Immutable explicit DAO executor D supplied at construction.
    /// Never derived from msg.sender/tx.origin; never changes.
    address public immutable dao;

    /// @notice Delegated adder flags. Slot 0; key location
    /// keccak256(abi.encode(key,uint256(0))). Only D writes them; a flag is
    /// history, not a promise of present capability after retirement.
    mapping(address => bool) public isAdder;
    /// @notice Local fresh-commit nomination required for apply (the raw
    /// controller's future_admin is stale after seating). Slot 1, offset 0.
    address public pendingControllerAdmin;
    /// @notice Permanent lifecycle latch: becomes true only on a successful
    /// handback apply and is never cleared. Slot 1, offset 20.
    bool public retired;
    /// @notice Single mutual-exclusion word shared by ALL mutators. Slot 2:
    /// 1=idle, 2=entered.
    uint256 private _lock = 1;

    // ------------------------------------------------------------------
    // Errors (SPEC §5; exact names/types; upstream reverts bubble unwrapped)
    // ------------------------------------------------------------------

    error InvalidController(address controller);
    error NoCode(address target);
    error InvalidDao(address dao);
    error NotDao(address caller);
    error NotAdder(address caller);
    error Retired();
    error ReentrantCall();
    error NotControllerAdmin(address actual);
    error InvalidAdder(address adder);
    error InvalidSuccessor(address successor);
    error NoPendingTransfer();
    error PendingAdminMismatch(address expected, address actual);
    error ControllerAdminMismatch(address expected, address actual);
    error InvalidOwnershipCalldata();

    // ------------------------------------------------------------------
    // Events (SPEC §5)
    // ------------------------------------------------------------------

    event AdderSet(address indexed adder, bool enabled);
    event GaugeAdded(address indexed caller, address indexed gauge, int128 gaugeType, uint256 weight);
    /// @notice Generic-execute audit record. Hashes of the full input and
    /// returned byte arrays; NOT a governance approval, fee receipt or
    /// emissions event. The raw controller emits its own events.
    event Executed(bytes4 indexed selector, bytes32 calldataHash, bytes32 returndataHash);
    event ControllerTransferCommitted(address indexed successor);
    event ControllerTransferApplied(address indexed successor);

    // ------------------------------------------------------------------
    // Modifiers (SPEC §4: authority first, then retirement, then lock)
    // ------------------------------------------------------------------

    modifier onlyDao() {
        if (msg.sender != dao) revert NotDao(msg.sender);
        _;
    }

    /// @dev add_gauge entry gate: D itself or an address with a live grant.
    /// Read-through functions are deliberately NOT gated.
    modifier onlyDaoOrAdder() {
        if (msg.sender != dao && !isAdder[msg.sender]) revert NotAdder(msg.sender);
        _;
    }

    modifier activeLock() {
        if (retired) revert Retired();
        if (_lock != 1) revert ReentrantCall();
        _lock = 2;
        _;
        _lock = 1;
    }

    /// @notice Pin the immutable controller C and DAO D. Parameters are
    /// explicitly supplied, never derived; deployment precedes installation
    /// — no requirement that C.admin()==R here. No auto-grants, no token
    /// calls, no authority transfer.
    constructor(address controller_, address dao_) {
        if (controller_ == address(0) || controller_ == address(this)) revert InvalidController(controller_);
        if (controller_.code.length == 0) revert NoCode(controller_);
        if (dao_ == address(0) || dao_ == address(this) || dao_ == controller_) revert InvalidDao(dao_);
        controller = controller_;
        dao = dao_;
    }

    // ------------------------------------------------------------------
    // Delegated adder administration (SPEC §3)
    // ------------------------------------------------------------------

    /// @notice D-only grant/revoke of the raw-add capability. Usable before
    /// seating but after deployment. Writes the flag and emits AdderSet even
    /// when the value is unchanged; 0/R/C/D are rejected before any effect.
    function grant(address adder, bool enabled) external onlyDao activeLock {
        if (adder == address(0) || adder == address(this) || adder == controller || adder == dao) {
            revert InvalidAdder(adder);
        }
        isAdder[adder] = enabled;
        emit AdderSet(adder, enabled);
    }

    // ------------------------------------------------------------------
    // Lister-facing add path (SPEC §3/§5)
    // ------------------------------------------------------------------

    /// @notice The only adder-gated entry: D or a granted adder may drive the
    /// synchronous controller addition. No type/weight clamp, fee, validator,
    /// pool, pause, gauge-code or registry policy is added by R: arguments
    /// reach C exactly as supplied (a grant is the full raw-add capability,
    /// including any controller-valid initial weight). R never fabricates
    /// the event: GaugeAdded is emitted only after C returns successfully.
    function add_gauge(address gauge, int128 gaugeType, uint256 weight) external onlyDaoOrAdder activeLock {
        _requireIncumbent();
        ICanonicalController(controller).add_gauge(gauge, gaugeType, weight);
        emit GaugeAdded(msg.sender, gauge, gaugeType, weight);
    }

    // ------------------------------------------------------------------
    // Canonical read-through (SPEC §3; public, lock-free, retire-proof)
    // ------------------------------------------------------------------

    /// @notice Typed STATICCALL read-through to C. Preserves a valid stored
    /// zero and the exact upstream revert bytes for absence; a malformed
    /// upstream return reverts and never fabricates membership.
    function gauge_types(address gauge) external view returns (int128) {
        return ICanonicalController(controller).gauge_types(gauge);
    }

    /// @notice Typed read-through of C's canonical exclusive type bound. No
    /// local cache or shadow registry.
    function n_gauge_types() external view returns (int128) {
        return ICanonicalController(controller).n_gauge_types();
    }

    // ------------------------------------------------------------------
    // Generic controller execution (SPEC §3/§4)
    // ------------------------------------------------------------------

    /// @notice D-only arbitrary execution against the IMMUTABLE pinned C
    /// only: the ABI carries just `bytes` — no target, no value — and the
    /// sole CALL destination is C, never R. Ownership selectors are mediated
    /// into the SAME commit/apply state machine as the typed methods (no
    /// raw ownership escape); canonical encodings only. All other payloads
    /// reach C unchanged and keep C's exact return or failure bytes; an
    /// input shorter than four bytes uses selector=0 for Executed. Executed
    /// fires only on success.
    function execute(bytes calldata data) external onlyDao activeLock returns (bytes memory result) {
        bytes4 selector = data.length >= 4 ? bytes4(data[:4]) : bytes4(0);
        if (selector == ICanonicalController.commit_transfer_ownership.selector) {
            if (data.length != 36) revert InvalidOwnershipCalldata();
            uint256 word = abi.decode(data[4:], (uint256));
            if (word > type(uint160).max) revert InvalidOwnershipCalldata();
            _commit(address(uint160(word)));
            result = "";
        } else if (selector == ICanonicalController.apply_transfer_ownership.selector) {
            if (data.length != 4) revert InvalidOwnershipCalldata();
            _apply();
            result = "";
        } else {
            _requireIncumbent();
            bool ok;
            (ok, result) = controller.call(data);
            if (!ok) {
                // Bubble C's failure bytes exactly, including an empty revert.
                assembly ("memory-safe") {
                    revert(add(result, 32), mload(result))
                }
            }
        }
        emit Executed(selector, keccak256(data), keccak256(result));
    }

    // ------------------------------------------------------------------
    // Typed two-step handback (SPEC §4)
    // ------------------------------------------------------------------

    /// @notice D-only nomination of the next C administrator. Transfers
    /// C-administration, never ownership of R (there is none to transfer).
    function commit_transfer_ownership(address successor) external onlyDao activeLock {
        _commit(successor);
    }

    /// @notice D-only completion of the nominated handback. The INCUMBENT R
    /// calls C.apply (not the pending successor); success permanently retires
    /// R for all mutations.
    function apply_transfer_ownership() external onlyDao activeLock {
        _apply();
    }

    // ------------------------------------------------------------------
    // Internal shared routines (SPEC §4; no second lock, no self-call)
    // ------------------------------------------------------------------

    /// @dev Controller authority is a hard precondition for every mutating
    /// lane; failure here is R's guard firing, never a reached raw call.
    function _requireIncumbent() private view {
        address actual = ICanonicalController(controller).admin();
        if (actual != address(this)) revert NotControllerAdmin(actual);
    }

    /// @dev Shared commit for typed and mediated execute paths. Any failure
    /// rolls back BOTH local and C effects (same transaction).
    function _commit(address successor) private {
        _requireIncumbent();
        if (successor == address(0) || successor == address(this) || successor == controller) {
            revert InvalidSuccessor(successor);
        }
        pendingControllerAdmin = successor;
        ICanonicalController(controller).commit_transfer_ownership(successor);
        address actual = ICanonicalController(controller).future_admin();
        if (actual != successor) revert PendingAdminMismatch(successor, actual);
        emit ControllerTransferCommitted(successor);
    }

    /// @dev Shared apply for typed and mediated execute paths. The local
    /// fresh nomination is required: C.future_admin is stale after seating
    /// and is NOT proof of a fresh commit. Retirement is latched BEFORE the
    /// external apply so a reentrant view of the finalizing state sees
    /// Retired; any revert rolls retirement, nomination, controller state
    /// and logs back together.
    function _apply() private {
        _requireIncumbent();
        address successor = pendingControllerAdmin;
        if (successor == address(0)) revert NoPendingTransfer();
        address future = ICanonicalController(controller).future_admin();
        if (future != successor) revert PendingAdminMismatch(successor, future);
        pendingControllerAdmin = address(0);
        retired = true;
        ICanonicalController(controller).apply_transfer_ownership();
        address actual = ICanonicalController(controller).admin();
        if (actual != successor) revert ControllerAdminMismatch(successor, actual);
        emit ControllerTransferApplied(successor);
    }
}
