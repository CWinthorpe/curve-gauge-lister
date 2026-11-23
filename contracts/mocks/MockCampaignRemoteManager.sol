// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ICampaignRemoteManager} from "../interfaces/ICampaignRemoteManager.sol";
import {SafeToken} from "../libraries/SafeToken.sol";

/// @title MockCampaignRemoteManager
/// @notice Test-only stand-in for the VoteMarket v2 (Stake DAO) L1
/// CampaignRemoteManager (`0x53ad4cd1...1ca2`), implementing
/// ICampaignRemoteManager exactly, plus a controlled-messenger policy layer.
/// REAL manager guards (fetched CampaignRemoteManager.sol): `block.chainid
/// == 1` (`InvalidChainId`, :1749) and the platform whitelist
/// (`PlatformNotWhitelisted`, :1750). It pulls `params.totalRewardAmount` of
/// `params.rewardToken` from the caller and records the full call. Like the
/// real manager, `createCampaign` returns nothing: campaign creation is
/// asynchronous (LaPoste) and the campaign id surfaces on L2, so the
/// recorded L1 call — not any returned value, and not a destination-campaign
/// fact — is what this fixture makes inspectable as ingress evidence
/// (CX-LABELS: "recorded campaign", never "live campaign").
/// @dev POLICY FIXTURE (not manager guards): the deployed manager validates
/// neither the destination chain nor `msg.value == additionalGasLimit *
/// gasPrice` — it forwards the supplied destination and ALL `msg.value` to
/// `LaPoste.sendMessage` (:1774-1781), which prices the message itself. The
/// destination 42161 pin and the value equality below are this controlled
/// messenger fixture's policy: they verify the ADAPTER's budgeting choice
/// (its YB-helper-shaped `additionalGasLimit * gasPrice` computation) and
/// reject a mispriced message in-test. They are not evidence the live LaPoste
/// messenger accepts the payment; live bridge pricing stays a deployment
/// check.
/// @dev Also not the real product: no bridge, messenger, L2 callback, token
/// factory, refund or ownership machinery is emulated. Received ETH is
/// retained as the paid-gas ledger (the real manager forwards it to the
/// messenger); there is no withdrawal surface, mirroring the adapter-side
/// INTEL §4 deviation.
contract MockCampaignRemoteManager is ICampaignRemoteManager {
    /// @notice Only Arbitrum one is accepted as a campaign destination by
    /// this fixture (adapter destination policy, not a manager guard — see
    /// the contract-level devnote).
    uint256 public constant DESTINATION_CHAIN_ID = 42161;
    /// @notice Real manager ingress guard (C1:1749): L1 creation only.
    uint256 public constant SOURCE_CHAIN_ID = 1;
    /// @notice Fixture gas price this controlled messenger bills at (the real
    /// manager holds no gasPrice state — see the contract-level devnote).
    uint256 public immutable gasPrice;

    struct Campaign {
        uint256 id;
        ICampaignRemoteManager.CampaignCreationParams params;
        uint256 destinationChainId;
        uint256 additionalGasLimit;
        address votemarket;
        address caller;
        uint256 value;
    }

    Campaign[] private _campaigns;
    uint256 private _ethPaid;

    /// @dev Platform (destination-chain VoteMarket) whitelist, as in the real
    /// manager's whitelistedPlatforms.
    mapping(address => bool) private _whitelistedPlatforms;

    event CampaignCreated(uint256 indexed id, address indexed gauge, address indexed manager, uint256 totalReward);
    event PlatformWhitelistUpdated(address indexed platform, bool whitelisted);

    error InvalidChainId();
    error InvalidDestinationChainId();
    error UnknownPlatform();
    error BadGasValue();
    error EmptyCampaign();
    error BadParams();

    /// @notice Fix the controlled-messenger gas price and seed the platform
    /// whitelist.
    constructor(uint256 gasPrice_, address[] memory platforms_) {
        gasPrice = gasPrice_;
        for (uint256 i = 0; i < platforms_.length; ++i) {
            _whitelistedPlatforms[platforms_[i]] = true;
            emit PlatformWhitelistUpdated(platforms_[i], true);
        }
    }

    function whitelistedPlatforms(address platform) external view returns (bool) {
        return _whitelistedPlatforms[platform];
    }

    /// @inheritdoc ICampaignRemoteManager
    function createCampaign(
        CampaignCreationParams calldata params,
        uint256 destinationChainId,
        uint256 additionalGasLimit,
        address votemarket
    ) external payable {
        // Real manager ingress guards (C1:1749-1750), same order.
        if (block.chainid != SOURCE_CHAIN_ID) revert InvalidChainId();
        if (!_whitelistedPlatforms[votemarket]) revert UnknownPlatform();
        // Controlled-messenger policy checks (fixture, not manager guards).
        if (destinationChainId != DESTINATION_CHAIN_ID) revert InvalidDestinationChainId();
        if (msg.value != additionalGasLimit * gasPrice) revert BadGasValue();
        if (params.totalRewardAmount == 0) revert EmptyCampaign();
        if (params.numberOfPeriods == 0) revert BadParams();
        if (params.manager == address(0) || params.rewardToken == address(0)) revert BadParams();
        if (params.chainId == 0 || params.gauge == address(0)) revert BadParams();

        SafeToken.safeTransferFrom(params.rewardToken, msg.sender, address(this), params.totalRewardAmount);

        uint256 id = _campaigns.length;
        _campaigns.push(
            Campaign({
                id: id,
                params: params,
                destinationChainId: destinationChainId,
                additionalGasLimit: additionalGasLimit,
                votemarket: votemarket,
                caller: msg.sender,
                value: msg.value
            })
        );
        _ethPaid += msg.value;
        emit CampaignCreated(id, params.gauge, params.manager, params.totalRewardAmount);
    }

    /// @notice Recorded campaign calls, in order.
    function campaignCount() external view returns (uint256) {
        return _campaigns.length;
    }

    function campaignAt(uint256 index) external view returns (Campaign memory) {
        return _campaigns[index];
    }

    /// @notice Cumulative bridge-gas ETH accepted (spent, never returned).
    function ethPaid() external view returns (uint256) {
        return _ethPaid;
    }
}
