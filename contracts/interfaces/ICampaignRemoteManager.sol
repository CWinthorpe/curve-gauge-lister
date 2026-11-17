// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title ICampaignRemoteManager
/// @notice Minimal local declaration of the VoteMarket v2 (Stake DAO) L1
/// CampaignRemoteManager (`0x53ad4cd1f1e52dd02aa9fc4a8250a1b74f351ca2`,
/// Sourcify exact match, see docs/INTEL-YB-HELPERS.md). Field names, order and
/// types — including the `uint8` numberOfPeriods — are pinned to the verified
/// deployed ABI. Not a full CampaignRemoteManager interface.
interface ICampaignRemoteManager {
    /// @notice Campaign creation payload forwarded to the destination-chain
    /// VoteMarket via the LaPoste messenger. Delivery is asynchronous: an L1
    /// successful return does not itself prove an L2 campaign is live.
    struct CampaignCreationParams {
        uint256 chainId;
        address gauge;
        address manager;
        address rewardToken;
        uint8 numberOfPeriods;
        uint256 maxRewardPerVote;
        uint256 totalRewardAmount;
        address[] addresses;
        address hook;
        bool isWhitelist;
    }

    /// @notice Fund and register an L2 campaign. On the verified manager
    /// (C1:1749-1781) the ingress guards are `block.chainid == 1` and a
    /// whitelisted `votemarket` platform; the manager then pulls
    /// `params.totalRewardAmount` of `params.rewardToken` from the caller and
    /// forwards the supplied destination chain and ALL `msg.value` to
    /// `LaPoste.sendMessage` for the cross-chain message. The manager holds no
    /// gas-price state and validates no value equality: pricing the message
    /// (`additionalGasLimit * gasPrice` in this product) is the CALLER's
    /// budgeting policy, and the messenger's acceptance of that payment is a
    /// deployment-time check. Returns nothing: the campaign id surfaces on
    /// L2, so the durable L1 proof of funding is the recorded call itself.
    function createCampaign(
        CampaignCreationParams calldata params,
        uint256 destinationChainId,
        uint256 additionalGasLimit,
        address votemarket
    ) external payable;
}
