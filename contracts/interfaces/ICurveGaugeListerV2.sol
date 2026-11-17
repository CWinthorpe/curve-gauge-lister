// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title ICurveGaugeListerV2
/// @notice V2 hook-facing listing/config/token/binding read subset
/// (plans/BOUNTY-PLAN.md §1.5), using exactly the tuples of §1.2. Declares
/// ONLY: `getListing`, `listingId`, `crvUSD`, `feeDistributor`, `bounty` and
/// the existing `owner` view (thin plan §2.1: current config-owner
/// authentication). No interface aliases that accidentally add getters.
interface ICurveGaugeListerV2 {
    /// @notice Exact §1.2 tuple order/encoding. `Status` retains the V1
    /// order/encoding Unlisted=0, Active=1, Exhausted=2, Confiscated=3,
    /// DaoExempt=4 (`uint8` in the ABI).
    struct AdmissionConfig {
        address registry;
        uint8 maxCoins;
    }

    struct PlatformConfig {
        address votium;
        address voteMarket;
        uint16 votiumBps;
    }

    /// @notice The original 15 fields in original order followed by the three
    /// bounty allocation fields. `confiscated` remains GROSS. Do not decode
    /// V2 with V1's tuple.
    struct ListingV2 {
        address pool;
        address lpToken;
        address payer;
        address admissionRegistry;
        int128 gaugeType;
        uint256 listingEpoch;
        uint8 status;
        uint8 epochsReleased;
        uint256 deposited;
        uint256 remaining;
        uint256 released;
        uint256 confiscated;
        address votium;
        address voteMarket;
        uint16 votiumBps;
        uint256 reporterReward;
        uint256 fdConfiscated;
        bytes32 rewardReportId;
    }

    /// @notice Full record; unknown returns the all-zero Unlisted record.
    /// Terminal listing views are local only.
    function getListing(address gauge) external view returns (ListingV2 memory);

    /// @notice Permanent listing identity for any listed gauge; unknown
    /// returns zero.
    function listingId(address gauge) external view returns (bytes32);

    function crvUSD() external view returns (address);

    function feeDistributor() external view returns (address);

    /// @notice Solidity immutable reverse pointer to the bound bounty.
    function bounty() external view returns (address);

    /// @notice Existing V2 config owner (thin plan §2.1: the sole
    /// frivolousness authority; two-step transfer moves it).
    function owner() external view returns (address);
}
