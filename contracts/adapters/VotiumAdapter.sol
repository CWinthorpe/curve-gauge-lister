// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IIncentivePlatform} from "../interfaces/IIncentivePlatform.sol";
import {IERC20Minimal} from "../interfaces/IERC20Minimal.sol";
import {IVotiumV2} from "../interfaces/IVotiumV2.sol";
import {SafeToken} from "../libraries/SafeToken.sol";
import {AdapterOwnable} from "../libraries/AdapterOwnable.sol";
import {AdapterCustody} from "../libraries/AdapterCustody.sol";

/// @title VotiumAdapter
/// @notice Real-platform adapter funding Votium v2 from the CurveGaugeLister
/// escrow (plan §7, docs/INTEL-YB-HELPERS.md §3.2). One deposit routes one
/// gauge-bound tranche into the currently active Votium round:
/// pull EXACTLY `amount` of the immutable crvUSD from the bound lister,
/// bounded-approve the Votium deposit address for EXACTLY `amount`, call
/// `depositUnevenSplitGauges(crvUSD, activeRound(), [gauge], [amount],
/// maxPerVote, excluded)` with single-element arrays (per-gauge binding, not
/// the YB helper's shared-weights model), clear the approval to zero, and
/// return a deterministic nonzero receipt.
/// @dev Deliberate deviations from the MIT YB DepositHelperVotium (INTEL §4):
/// no owner `execute()` / `withdrawEther` surface, no unlimited standing
/// approval (approve exact, clear after), per-gauge deposit binding, and
/// manager-settable per-deposit `maxPerVote`/`excluded` instead of a shared
/// weights array. Configuration setters validate the verified venue's
/// ingress preconditions at set time (cap bound, current exclusion limit
/// and strictly increasing order). Later venue-policy changes can
/// invalidate stored exclusions and block deposits until the manager
/// repairs the list.
/// Defaults mirror the YB helper's effective behaviour:
/// `maxPerVote = 0` (unbounded) and an empty exclusion list — the fee
/// boomerang property is accepted and no voter blacklist is introduced.
/// The deposit address is constructor-bound so no owner action can ever
/// redirect token approvals; there is no token withdrawal path, so the
/// adapter verifies within every deposit the exact pull credit and that its
/// own crvUSD balance returned to the pre-deposit baseline. Those are
/// adapter-side balance observations, not a separately measured recipient
/// credit, and no promise that every gross unit became a net venue reward
/// (the pinned venue's fee/net split is evidenced independently in the fork
/// suite).
contract VotiumAdapter is IIncentivePlatform, AdapterOwnable {
    /// @notice Immutable fee/reward token; the only token this adapter moves.
    address public immutable crvUSD;
    /// @notice Votium v2 deposit ingress (`0x63942E31...2D1e` on mainnet).
    address public immutable votium;
    // `owner`/`pendingOwner`, their getters, the ownership events, NotOwner,
    // onlyOwner and the two-step transitions are inherited from
    // AdapterOwnable (S22) unchanged in call surface, error encodings,
    // storage order, events and slots.

    /// @notice Per-vote reward cap passed through to Votium (0 = unbounded).
    uint256 public maxPerVote;
    /// @dev Voter addresses excluded from this adapter's incentives.
    address[] private _excluded;
    /// @notice Upper bound on the configured exclusion list; bounds calldata
    /// size passed to the platform call. NOT venue compatibility: the venue's
    /// own `maxExclusions()` is additionally enforced by `setExcluded`.
    uint256 public constant MAX_EXCLUDED = 50;
    /// @notice Exclusive upper bound on a valid per-vote cap, mirroring the
    /// real venue's overflow guard `maxMaxPerVote` (Votium.sol:28; deposit
    /// ingress `require(_maxPerVote < maxMaxPerVote, "!highMax")` at :344).
    /// Any cap >= this value is rejected here before it can poison a deposit.
    uint256 public constant MAX_MAX_PER_VOTE = type(uint256).max / (100000000 * 10 ** 18);

    address private _lister;

    event ListerSet(address indexed lister);
    event MaxPerVoteSet(uint256 maxPerVote);
    event ExcludedSet(address[] excluded);
    event VotiumDeposit(
        address indexed gauge, uint256 indexed scheduledEpoch, uint256 indexed round, uint256 amount, bytes32 receipt
    );

    error NotLister();
    error ListerAlreadySet();
    error BadLister();
    error BadDeposit();
    error BadExclusion();
    error BadMaxPerVote();
    error BadVenueExclusions();
    error PullDeltaMismatch();
    error PlatformUnderpull();
    error BadReceipt();

    /// @notice Bind token, manager and the Votium deposit ingress. The token
    /// and the local ingress are immutable and must have deployed code; the
    /// owner must be nonzero and is transferred in two steps (it is not an
    /// immutable). Code presence does not authenticate token/venue identity,
    /// proxy behavior or continuing availability.
    constructor(address crvUSD_, address owner_, address votium_) {
        require(crvUSD_ != address(0) && owner_ != address(0) && votium_ != address(0), "zero arg");
        require(crvUSD_.code.length > 0 && votium_.code.length > 0, "no code");
        crvUSD = crvUSD_;
        owner = owner_;
        votium = votium_;
    }

    /// @inheritdoc IIncentivePlatform
    function rewardToken() external view returns (address) {
        return crvUSD;
    }

    /// @notice Configured voter-exclusion list (default empty).
    function excluded() external view returns (address[] memory) {
        return _excluded;
    }

    /// @notice One-time, owner-authenticated lister binding (auditfix001
    /// §1): deposits are accepted only from this address, preventing
    /// outsider receipt spam. Target must be a contract. Only a still-unbound
    /// adapter can be bound: even the owner cannot replace a successful
    /// binding, including after either ownership transfer. There is no reset,
    /// rebind, recovery or bypass path.
    function setLister(address lister_) external onlyOwner {
        if (_lister != address(0)) revert ListerAlreadySet();
        if (lister_ == address(0) || lister_.code.length == 0) revert BadLister();
        _lister = lister_;
        emit ListerSet(lister_);
    }

    /// @notice Bound lister; zero means unbound (auditfix001 §1).
    function lister() external view returns (address) {
        return _lister;
    }

    /// @inheritdoc IIncentivePlatform
    function deposit(address gauge, uint256 scheduledEpoch, uint256 amount) external returns (bytes32 receipt) {
        // Shared stateless binding/shape predicates (CX-ADAPTER); the
        // adapter keeps its own errors and this error order.
        if (!AdapterCustody.isBoundCaller(_lister, msg.sender)) revert NotLister();
        if (!AdapterCustody.validDepositShape(gauge, amount)) revert BadDeposit();

        // Round is the platform's live active round at call time; a late
        // scheduledEpoch buys participation in THIS round, never retroactive
        // votes for the original escrow maturity. The venue accepting
        // multiple same-gauge entries in one round (live-round witness) is
        // Votium's own batch behaviour; it is NOT permission for the product
        // to alias its two venue roles onto one endpoint (the core's
        // distinct-positive-endpoint rule stays; see S21 in CurveGaugeLister
        // `_validatePlatforms`).
        uint256 round = IVotiumV2(votium).activeRound();

        uint256 balBefore = IERC20Minimal(crvUSD).balanceOf(address(this));
        SafeToken.safeTransferFrom(crvUSD, msg.sender, address(this), amount);
        if (!AdapterCustody.exactPullCredit(balBefore, IERC20Minimal(crvUSD).balanceOf(address(this)), amount)) {
            revert PullDeltaMismatch();
        }

        address[] memory gauges = new address[](1);
        gauges[0] = gauge;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;

        // Bounded approval, deposit, then zero: no enduring allowance is ever
        // left behind. (Current law with NO exception: INTEL §4's historical
        // "except where platform ABI requires standing approvals" clause was
        // NOT adopted — both adapters use exact bounded approvals cleared
        // after every venue call.) A failed platform call reverts the whole
        // deposit, approvals included.
        SafeToken.forceApprove(crvUSD, votium, amount);
        IVotiumV2(votium).depositUnevenSplitGauges(crvUSD, round, gauges, amounts, maxPerVote, _excluded);
        SafeToken.forceApprove(crvUSD, votium, 0);

        // No withdrawal surface exists in this adapter, so custody must be
        // complete inside the deposit itself: with the exact pull credit
        // checked above, this observes the adapter's own crvUSD balance
        // returning to its pre-deposit baseline — the adapter retains
        // nothing. It is a balance-baseline observation, not a separately
        // measured recipient credit and not a gross-equals-net venue
        // promise (shared baseline predicate, own error and position,
        // CX-ADAPTER).
        if (!AdapterCustody.custodyClearedToBaseline(balBefore, IERC20Minimal(crvUSD).balanceOf(address(this)))) {
            revert PlatformUnderpull();
        }

        // Deterministic in (gauge, scheduledEpoch, amount, round); a zero
        // receipt is unreachable by construction but guarded explicitly.
        receipt = keccak256(abi.encode(gauge, scheduledEpoch, amount, round));
        // S09 (common contract per CX-RECEIPT): this hash is an opaque
        // adapter-domain L1-ingress correlation identifier. `round`
        // provenance is the live activeRound() read at THIS chain-1 ingress
        // call; the value attests the recorded deposit only, never
        // destination delivery or venue-side acceptance beyond that call.
        // This venue's proof is EVENT-ONLY — there is deliberately no
        // deposit record or record getter here — and the full-tuple value is
        // REPEATABLE: the same (gauge, scheduledEpoch, amount, round) mints
        // the same receipt again (Votium permits repeated same-gauge entries;
        // no global uniqueness is claimed).
        if (receipt == bytes32(0)) revert BadReceipt();
        emit VotiumDeposit(gauge, scheduledEpoch, round, amount, receipt);
    }

    /// @notice Manager-only: per-vote reward cap for future deposits
    /// (0 = unbounded, the YB-helper default).
    /// @dev Rejects caps the real venue rejects: Votium.sol:344 requires
    /// `maxPerVote < type(uint256).max / (100000000 * 10**18)` ("!highMax")
    /// to prevent overflow at round end, so an out-of-bound cap configured
    /// here would block every Votium-bearing checkpoint until corrected.
    function setMaxPerVote(uint256 maxPerVote_) external onlyOwner {
        if (maxPerVote_ >= MAX_MAX_PER_VOTE) revert BadMaxPerVote();
        maxPerVote = maxPerVote_;
        emit MaxPerVoteSet(maxPerVote_);
    }

    /// @notice Manager-only: voter-exclusion list for future deposits.
    /// @dev Mirrors the real venue's ingress preconditions (Votium.sol
    /// :344-346, :658-665): entries nonzero, strictly increasing in numeric
    /// address order (the venue's `!sorted` require — duplicates are
    /// rejected by the same strict inequality), list length within both the
    /// local calldata bound MAX_EXCLUDED and the venue's own
    /// `maxExclusions()` (the `!excluded` bound; read live from the pinned
    /// deposit ingress, not assumed from the local cap). Default remains
    /// empty (no voter blacklist by default); the empty list needs no venue
    /// check, matching the venue's `if(_excluded.length > 0)` gating.
    function setExcluded(address[] calldata excluded_) external onlyOwner {
        if (excluded_.length > MAX_EXCLUDED) revert BadExclusion();
        uint160 height;
        for (uint256 i = 0; i < excluded_.length; ++i) {
            address e = excluded_[i];
            if (e == address(0)) revert BadExclusion();
            uint160 next = uint160(e);
            if (next <= height) revert BadExclusion();
            height = next;
        }
        if (excluded_.length > 0 && excluded_.length > IVotiumV2(votium).maxExclusions()) {
            revert BadVenueExclusions();
        }
        // Whole-list replacement via the compiler's ordered calldata→storage
        // copy (CX-EXCLUDED): semantically identical to the previous
        // delete-then-push loop (length set, all elements assigned, order
        // preserved), and it runs ONLY after every validation above, so a
        // rejected list still never reaches storage. The venue's own
        // maxExclusions() read keeps its position immediately before the
        // write, skipped for the empty list. The UNSIGNED strict-increase
        // rule (zero, duplicates) stays this venue's own policy — the
        // VoteMarket adapter's arbitrary distinct-caller-order rule is NOT
        // normalized to it (or vice versa) by this cut.
        _excluded = excluded_;
        emit ExcludedSet(excluded_);
    }
    // transferOwnership/acceptOwnership inherited from AdapterOwnable (S22).
}
