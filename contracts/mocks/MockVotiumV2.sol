// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IVotiumV2} from "../interfaces/IVotiumV2.sol";
import {SafeToken} from "../libraries/SafeToken.sol";

/// @title MockVotiumV2
/// @notice Test-only stand-in for the Votium v2 deposit ingress (mainnet
/// `0x63942E31...2D1e`), implementing IVotiumV2 exactly. Pulls real ERC20
/// tokens from the caller per gauge and models the verified venue's deposit
/// preconditions (fetched Votium.sol): round acceptance
/// `activeRound()..activeRound()+6` (`:342-343`), the overflow-bounded reward
/// cap `maxPerVote < type(uint256).max/(100000000*10**18)` (`!highMax`,
/// `:344`), a token allowlist, and for non-empty exclusion lists the venue
/// limit `maxExclusions` (`!excluded`) plus strictly increasing address order
/// (`_checkExclusions`, `:658-665`). Accumulates totals per (round, gauge,
/// token) and emits deposit events. Receipt proof is the recorded incentive:
/// Votium has no return value on deposit functions.
/// @dev Custody here is GROSS funding, not the venue's net incentive
/// accounting: the real `_takeDeposit` (`:640-648`) pulls the gross amount as
/// a platform-fee transfer to `feeAddress` PLUS a net-reward transfer to
/// itself (fee = gross * platformFee / 10000, fee > 0 required). This fixture
/// abstracts that fee split — every recorded amount is gross funding
/// debited from the depositor, and must not be read as post-fee voter
/// incentives. Also not the real product: no Merkle distribution, fee sweep,
/// karma weighting or round finalisation is emulated. Test-only knobs (round
/// advance, token allowlist, venue maxExclusions) are fixtures, not product
/// menus.
contract MockVotiumV2 is IVotiumV2 {
    /// @notice Exclusive upper bound on a valid per-vote cap, mirroring the
    /// real venue's `maxMaxPerVote` (Votium.sol:28,344).
    uint256 public constant MAX_MAX_PER_VOTE = type(uint256).max / (100000000 * 10 ** 18);
    /// @notice Future-round horizon accepted by the real deposit ingress
    /// (Votium.sol:343, `activeRound() + 6`).
    uint256 public constant ROUND_HORIZON = 6;

    struct Incentive {
        uint256 index;
        address token;
        uint256 amount;
        uint256 round;
        address gauge;
        uint256 maxPerVote;
        address[] excluded;
        address depositor;
    }

    /// @notice Round accepted by deposits; advanced by tests, like Votium
    /// opening rounds.
    uint256 private _activeRound = 1;
    /// @dev Venue-configured exclusion limit; the real `maxExclusions` is
    /// owner-set and starts at 0 (Votium.sol:31), so exclusions are rejected
    /// until the venue (here: the test) opens a limit.
    uint256 private _maxExclusions;
    mapping(address => bool) private _allowedTokens;
    Incentive[] private _incentives;
    mapping(uint256 => mapping(address => mapping(address => uint256))) private _totals;

    event TokenAllowed(address indexed token);
    event RoundSet(uint256 round);
    event MaxExclusionsSet(uint256 maxExclusions);
    event DepositIncentive(
        address indexed token,
        address indexed gauge,
        uint256 indexed round,
        uint256 amount,
        uint256 maxPerVote,
        address depositor,
        address[] excluded
    );

    error InvalidRound();
    error LengthMismatch();
    error EmptyBatch();
    error UnsupportedToken();
    error ZeroAmount();
    error RewardCapTooHigh();
    error TooManyExclusions();
    error UnsortedExclusions();

    /// @notice Seed the token allowlist (the real product gates unapproved
    /// reward tokens).
    constructor(address[] memory allowedTokens_) {
        for (uint256 i = 0; i < allowedTokens_.length; ++i) {
            _allowedTokens[allowedTokens_[i]] = true;
            emit TokenAllowed(allowedTokens_[i]);
        }
    }

    function activeRound() external view returns (uint256) {
        return _activeRound;
    }

    /// @notice Test fixture: open/advance the accepted round.
    function setActiveRound(uint256 round_) external {
        _activeRound = round_;
        emit RoundSet(round_);
    }

    /// @notice Test fixture: allow another reward token.
    function allowToken(address token_) external {
        _allowedTokens[token_] = true;
        emit TokenAllowed(token_);
    }

    /// @inheritdoc IVotiumV2
    function maxExclusions() external view returns (uint256) {
        return _maxExclusions;
    }

    /// @notice Test fixture: configure the venue exclusion limit, as the real
    /// owner does via `setMaxExclusions` (Votium.sol:833).
    function setMaxExclusions(uint256 maxExclusions_) external {
        _maxExclusions = maxExclusions_;
        emit MaxExclusionsSet(maxExclusions_);
    }

    /// @inheritdoc IVotiumV2
    function depositUnevenSplitGauges(
        address _token,
        uint256 _round,
        address[] calldata _gauges,
        uint256[] calldata _amounts,
        uint256 _maxPerVote,
        address[] calldata _excluded
    ) external {
        // Ingress checks follow the verified venue's order (Votium.sol:341-346).
        if (_gauges.length != _amounts.length) revert LengthMismatch();
        if (_round < _activeRound || _round > _activeRound + ROUND_HORIZON) revert InvalidRound();
        if (_maxPerVote >= MAX_MAX_PER_VOTE) revert RewardCapTooHigh();
        if (_excluded.length > 0) {
            _checkExclusions(_excluded);
        }
        if (_gauges.length == 0) revert EmptyBatch();
        if (!_allowedTokens[_token]) revert UnsupportedToken();

        for (uint256 i = 0; i < _gauges.length; ++i) {
            uint256 amount = _amounts[i];
            if (amount == 0) revert ZeroAmount();
            // GROSS funding custody: the real venue would split this pull into
            // a platform-fee transfer plus a net-reward transfer (see
            // contract @dev); the recorded amount here is the gross debit.
            SafeToken.safeTransferFrom(_token, msg.sender, address(this), amount);
            _totals[_round][_gauges[i]][_token] += amount;
            uint256 index = _incentives.length;
            _incentives.push(
                Incentive({
                    index: index,
                    token: _token,
                    amount: amount,
                    round: _round,
                    gauge: _gauges[i],
                    maxPerVote: _maxPerVote,
                    excluded: _excluded,
                    depositor: msg.sender
                })
            );
            emit DepositIncentive(_token, _gauges[i], _round, amount, _maxPerVote, msg.sender, _excluded);
        }
    }

    /// @dev Mirrors Votium.sol `_checkExclusions` (:658-665): count within the
    /// venue limit (`!excluded`), addresses strictly increasing (`!sorted`,
    /// which also rejects duplicates and a zero entry).
    function _checkExclusions(address[] calldata _excluded) private view {
        if (_excluded.length > _maxExclusions) revert TooManyExclusions();
        uint160 addressHeight;
        for (uint256 i = 0; i < _excluded.length; ++i) {
            uint160 height = uint160(_excluded[i]);
            if (height <= addressHeight) revert UnsortedExclusions();
            addressHeight = height;
        }
    }

    /// @notice Recorded incentive entries, in call order.
    function incentiveCount() external view returns (uint256) {
        return _incentives.length;
    }

    function incentiveAt(uint256 index) external view returns (Incentive memory) {
        return _incentives[index];
    }

    /// @notice Cumulative accepted funding per (round, gauge, token).
    function deposited(uint256 round_, address gauge, address token_) external view returns (uint256) {
        return _totals[round_][gauge][token_];
    }
}
