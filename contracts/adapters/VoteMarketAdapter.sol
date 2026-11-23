// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IIncentivePlatform} from "../interfaces/IIncentivePlatform.sol";
import {IERC20Minimal} from "../interfaces/IERC20Minimal.sol";
import {ICampaignRemoteManager} from "../interfaces/ICampaignRemoteManager.sol";
import {SafeToken} from "../libraries/SafeToken.sol";
import {CurveWeek} from "../libraries/CurveWeek.sol";

/// @title VoteMarketAdapter
/// @notice Real-platform adapter funding VoteMarket v2 (Stake DAO) campaigns
/// from the CurveGaugeLister escrow via the L1 CampaignRemoteManager
/// (plan §7, docs/INTEL-YB-HELPERS.md §3.3). One deposit creates exactly one
/// gauge-bound campaign: pull EXACTLY `amount` of the immutable crvUSD from
/// the bound lister, bounded-approve the CampaignRemoteManager for EXACTLY
/// `amount`, call `createCampaign{value: additionalGasLimit * gasPrice}` with
/// params bound to (block.chainid, gauge, manager = this adapter, crvUSD,
/// numberOfPeriods = 2, configured cap/amount/exclusions, hook = 0, isWhitelist
/// = false) toward destination chain 42161, clear the approval to zero, and
/// record the deposit with a receipt.
/// @dev Deliberate deviations from the AGPL-3.0 YB DepositHelperVoteMarket
/// (INTEL §4): the call is reimplemented from the verified ABI, not copied.
/// There is NO owner `execute()` / `withdrawEther` / ETH-rescue surface at
/// all: `receive()` accepts the ops ETH float from anyone, but nothing can
/// take ETH back out. Consequently the adapter verifies within each deposit
/// that the full pulled crvUSD left custody to the CampaignRemoteManager.
/// Insufficient ETH for the cross-chain gas makes the whole deposit revert,
/// which rolls back the enclosing checkpoint — a quarter is never silently
/// skipped (core requires exact funding; same semantics as the mocks).
/// Campaign delivery to L2 is ASYNCHRONOUS (LaPoste): L1 success is the
/// recorded-call proof, not a live-campaign proof. The CampaignRemoteManager
/// and votemarket endpoints are constructor-bound so no owner action can
/// redirect token approvals or bridge destinations.
contract VoteMarketAdapter is IIncentivePlatform {
    /// @notice VoteMarket v2 campaigns live on Arbitrum one (INTEL §3.3).
    uint256 public constant DESTINATION_CHAIN_ID = 42161;
    /// @notice Fixed campaign length in periods (matches the YB helper; the
    /// deployed MINIMUM_PERIODS must be confirmed pre-mainnet).
    uint8 public constant NUMBER_OF_PERIODS = 2;
    /// @notice Upper bound on the configured exclusion list; bounds calldata
    /// size and the gas-price multiplier.
    uint256 public constant MAX_EXCLUDED = 50;

    /// @notice Immutable fee/reward token; the only token this adapter moves.
    address public immutable crvUSD;
    /// @notice L1 CampaignRemoteManager (`0x53ad4cd1...1ca2` on mainnet).
    address public immutable campaignRemoteManager;
    /// @notice Destination-chain VoteMarket passed through to the manager
    /// (`0x8c2c5a29...14d9`, Arbitrum side, per verified live reads).
    address public immutable votemarket;
    /// @notice Manager allowed to tune per-deposit configuration.
    address public owner;
    /// @notice Two-step ownership candidate; no renounce path exists.
    address public pendingOwner;

    /// @notice Per-vote reward cap in campaign params
    /// (default type(uint256).max, the YB-helper live-read value).
    uint256 public maxRewardPerVote = type(uint256).max;
    /// @notice Bridge gas budget for the campaign-creation message itself.
    uint256 public campaignCreationGas = 2_000_000;
    /// @notice Incremental bridge gas budget per excluded address.
    uint256 public blacklistedAddressGas = 50_000;
    /// @notice Gas price used to price the native-ETH float requirement.
    uint256 public gasPrice = 1 gwei;

    /// @dev Voter addresses excluded from campaigns created by this adapter.
    address[] private _excluded;

    struct DepositRecord {
        address gauge;
        uint256 scheduledEpoch;
        uint256 amount;
        uint256 executionEpoch;
        bytes32 receipt;
    }

    mapping(bytes32 => uint256) private _depositIndex;
    DepositRecord[] private _depositLog;
    address private _lister;

    event ListerSet(address indexed lister);
    event MaxRewardPerVoteSet(uint256 maxRewardPerVote);
    event ExcludedSet(address[] excluded);
    event GasSettingsSet(uint256 campaignCreationGas, uint256 blacklistedAddressGas, uint256 gasPrice);
    event CampaignDeposit(
        address indexed gauge,
        uint256 indexed scheduledEpoch,
        uint256 indexed executionEpoch,
        uint256 amount,
        bytes32 receipt
    );
    event OwnershipTransferStarted(address indexed owner, address indexed pendingOwner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    error NotOwner();
    error NotLister();
    error ListerAlreadySet();
    error BadLister();
    error BadDeposit();
    error BadExclusion();
    error BadRewardCap();
    error BadGasSettings();
    error DuplicateDeposit();
    error PullDeltaMismatch();
    error PlatformUnderpull();
    error InsufficientEth();
    error BadReceipt();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    /// @notice Bind token, manager, L1 CampaignRemoteManager and destination
    /// VoteMarket. The token and the local CampaignRemoteManager are immutable
    /// and must have deployed code; the owner must be nonzero and is
    /// transferred in two steps (it is not an immutable); the remote
    /// VoteMarket is only required to be nonzero here — its code and
    /// configuration are checked operationally on its destination chain, not
    /// by an L1 code lookup. Code presence does not authenticate
    /// token/venue identity, proxy behavior or continuing availability.
    constructor(address crvUSD_, address owner_, address campaignRemoteManager_, address votemarket_) {
        require(
            crvUSD_ != address(0) && owner_ != address(0) && campaignRemoteManager_ != address(0)
                && votemarket_ != address(0),
            "zero arg"
        );
        require(crvUSD_.code.length > 0 && campaignRemoteManager_.code.length > 0, "no code");
        crvUSD = crvUSD_;
        owner = owner_;
        campaignRemoteManager = campaignRemoteManager_;
        votemarket = votemarket_;
    }

    /// @inheritdoc IIncentivePlatform
    function rewardToken() external view returns (address) {
        return crvUSD;
    }

    /// @notice Configured voter-exclusion list (default empty — no voter
    /// blacklist by default).
    function excluded() external view returns (address[] memory) {
        return _excluded;
    }

    /// @notice One-time, owner-authenticated lister binding (auditfix001
    /// §1): deposits are accepted only from this address, preventing outsider
    /// campaign spam. Target must be a contract. Only a still-unbound adapter
    /// can be bound: even the owner cannot replace a successful binding,
    /// including after either ownership transfer. There is no reset, rebind,
    /// recovery or bypass path.
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
        if (msg.sender != _lister) revert NotLister();
        if (gauge == address(0) || amount == 0) revert BadDeposit();

        bytes32 key = keccak256(abi.encode(gauge, scheduledEpoch));
        if (_depositIndex[key] != 0) revert DuplicateDeposit();

        uint256 balBefore = IERC20Minimal(crvUSD).balanceOf(address(this));
        SafeToken.safeTransferFrom(crvUSD, msg.sender, address(this), amount);
        if (IERC20Minimal(crvUSD).balanceOf(address(this)) != balBefore + amount) revert PullDeltaMismatch();

        // Native gas budget for the L1→L2 campaign message: base creation gas
        // plus the per-excluded-address allowance (YB helper pricing).
        uint256 additionalGasLimit = campaignCreationGas + blacklistedAddressGas * _excluded.length;
        uint256 value = additionalGasLimit * gasPrice;
        if (address(this).balance < value) revert InsufficientEth();

        address[] memory addresses_ = new address[](_excluded.length);
        for (uint256 i = 0; i < _excluded.length; ++i) {
            addresses_[i] = _excluded[i];
        }
        ICampaignRemoteManager.CampaignCreationParams memory params = ICampaignRemoteManager.CampaignCreationParams({
            chainId: block.chainid,
            gauge: gauge,
            manager: address(this),
            rewardToken: crvUSD,
            numberOfPeriods: NUMBER_OF_PERIODS,
            maxRewardPerVote: maxRewardPerVote,
            totalRewardAmount: amount,
            addresses: addresses_,
            hook: address(0),
            isWhitelist: false
        });

        // Bounded approval, campaign call, then zero: no enduring allowance is
        // ever left behind (INTEL §4). A failed manager call reverts the whole
        // deposit, approvals included.
        SafeToken.forceApprove(crvUSD, campaignRemoteManager, amount);
        ICampaignRemoteManager(campaignRemoteManager).createCampaign{value: value}(
            params, DESTINATION_CHAIN_ID, additionalGasLimit, votemarket
        );
        SafeToken.forceApprove(crvUSD, campaignRemoteManager, 0);

        // No token or ETH withdrawal surface exists here, so custody must be
        // complete inside the deposit itself: every pulled unit has to have
        // reached the CampaignRemoteManager in this same call.
        if (IERC20Minimal(crvUSD).balanceOf(address(this)) != balBefore) revert PlatformUnderpull();

        // Nonce-keyed so repeated top-ups of one gauge never alias, while a
        // duplicate (gauge, scheduledEpoch) is rejected before any pull.
        uint256 index = _depositLog.length;
        receipt = keccak256(abi.encode(gauge, scheduledEpoch, amount, index + 1));
        if (receipt == bytes32(0)) revert BadReceipt();

        // Execution-week label uses the single production Curve-week floor
        // convention (CurveWeek); it labels when the L1 ingress ran and is
        // not a delivery assertion.
        uint256 executionEpoch = CurveWeek.floorWeek(block.timestamp);
        _depositLog.push(
            DepositRecord({
                gauge: gauge,
                scheduledEpoch: scheduledEpoch,
                amount: amount,
                executionEpoch: executionEpoch,
                receipt: receipt
            })
        );
        _depositIndex[key] = index + 1;
        emit CampaignDeposit(gauge, scheduledEpoch, executionEpoch, amount, receipt);
    }

    /// @notice Keeper helper: native ETH still missing for ONE deposit of
    /// `amount` (0 once bound-lister traffic is possible). The required value
    /// prices the cross-chain message only and is independent of `amount`, so
    /// a zero-amount query (which the deposit itself rejects) reports no
    /// deficit; fund `ethDeficit(x)` to the adapter via plain `send`/`call`
    /// before the next scheduled settlement.
    function ethDeficit(uint256 amount) external view returns (uint256) {
        if (amount == 0) return 0;
        uint256 required = (campaignCreationGas + blacklistedAddressGas * _excluded.length) * gasPrice;
        uint256 held = address(this).balance;
        return required > held ? required - held : 0;
    }

    /// @notice Inspect the recorded funding of one (gauge, scheduledEpoch).
    /// @dev Zero receipt means "never funded" (the core requires funded
    /// receipts, so a recorded 0 receipt cannot have happened).
    function getDeposit(address gauge, uint256 scheduledEpoch)
        external
        view
        returns (uint256 amount, uint256 executionEpoch, bytes32 receipt)
    {
        uint256 index = _depositIndex[keccak256(abi.encode(gauge, scheduledEpoch))];
        if (index == 0) return (0, 0, bytes32(0));
        DepositRecord storage d = _depositLog[index - 1];
        return (d.amount, d.executionEpoch, d.receipt);
    }

    /// @notice Number of recorded campaign deposits.
    function depositCount() external view returns (uint256) {
        return _depositLog.length;
    }

    /// @notice Chronological deposit record.
    function depositAt(uint256 index) external view returns (DepositRecord memory) {
        return _depositLog[index];
    }

    /// @notice Accept the ops ETH float from anyone. There is deliberately no
    /// matching withdrawal, rescue or sweep surface: spent gas value is gone,
    /// unspent float stays put.
    receive() external payable {}

    /// @notice Manager-only: per-vote reward cap in campaign params.
    /// @dev Must stay positive: a zero cap produces an unusable campaign.
    function setMaxRewardPerVote(uint256 maxRewardPerVote_) external onlyOwner {
        if (maxRewardPerVote_ == 0) revert BadRewardCap();
        maxRewardPerVote = maxRewardPerVote_;
        emit MaxRewardPerVoteSet(maxRewardPerVote_);
    }

    /// @notice Manager-only: voter-exclusion list for future campaigns.
    /// @dev Rejects zero entries, duplicates and oversized lists; the default
    /// remains empty.
    function setExcluded(address[] calldata excluded_) external onlyOwner {
        if (excluded_.length > MAX_EXCLUDED) revert BadExclusion();
        delete _excluded;
        for (uint256 i = 0; i < excluded_.length; ++i) {
            address e = excluded_[i];
            if (e == address(0)) revert BadExclusion();
            for (uint256 j = 0; j < i; ++j) {
                if (_excluded[j] == e) revert BadExclusion();
            }
            _excluded.push(e);
        }
        emit ExcludedSet(excluded_);
    }

    /// @notice Manager-only: bridge gas settings applied to future deposits.
    /// @dev Atomic triple update so a half-applied gas setting can never price
    /// a deposit; base gas and gas price must be positive. Rejects, BEFORE any
    /// storage or event, any triple whose worst-case fifty-exclusion bridge
    /// budget would overflow: with U = type(uint256).max and N =
    /// MAX_EXCLUDED, requires `blacklistedAddressGas_ <= (U -
    /// campaignCreationGas_) / N` and then `gasPrice_ <= U /
    /// (campaignCreationGas_ + blacklistedAddressGas_ * N)`. Equality is
    /// allowed and X = 0 stays legal; every permitted exclusion count 0..N is
    /// covered irrespective of the current list length, so a later
    /// `setExcluded` cannot invalidate the invariant. Rejections use the
    /// existing BadGasSettings error, never an arithmetic Panic. This is an
    /// arithmetic-safety bound only: not a gas-price cap, affordability
    /// guarantee or bridge quote — valid but excessive pricing can still make
    /// deposits fail with InsufficientEth until the manager repairs it.
    function setGasSettings(uint256 campaignCreationGas_, uint256 blacklistedAddressGas_, uint256 gasPrice_)
        external
        onlyOwner
    {
        if (campaignCreationGas_ == 0 || gasPrice_ == 0) revert BadGasSettings();
        uint256 u = type(uint256).max;
        if (blacklistedAddressGas_ > (u - campaignCreationGas_) / MAX_EXCLUDED) revert BadGasSettings();
        uint256 worstCaseBudget = campaignCreationGas_ + blacklistedAddressGas_ * MAX_EXCLUDED;
        if (gasPrice_ > u / worstCaseBudget) revert BadGasSettings();
        campaignCreationGas = campaignCreationGas_;
        blacklistedAddressGas = blacklistedAddressGas_;
        gasPrice = gasPrice_;
        emit GasSettingsSet(campaignCreationGas_, blacklistedAddressGas_, gasPrice_);
    }

    /// @notice Manager proposes a nonzero new owner; acceptance is required.
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "zero owner");
        pendingOwner = newOwner;
        emit OwnershipTransferStarted(owner, newOwner);
    }

    /// @notice Only pendingOwner may accept; no renounce path exists.
    function acceptOwnership() external {
        require(msg.sender == pendingOwner, "not pending owner");
        address previous = owner;
        owner = msg.sender;
        pendingOwner = address(0);
        emit OwnershipTransferred(previous, msg.sender);
    }
}
