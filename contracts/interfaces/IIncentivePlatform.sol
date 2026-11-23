// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @notice Stateless local adapter ABI, NOT the native Votium or VoteMarket ABI.
/// Production-specific adapters must satisfy plan section 7 before real custody
/// is enabled.
interface IIncentivePlatform {
    /// @notice Identify the single reward token accepted by the adapter.
    function rewardToken() external view returns (address);

    /// @notice Bound lister authorized to deposit; zero means unbound
    /// (auditfix001 §1). Paid admission requires this to equal the lister.
    function lister() external view returns (address);

    /// @notice Pull EXACTLY amount from the lister and irrevocably fund a
    /// gauge-bound platform deposit/ingress; return a nonzero durable receipt
    /// identifier. Provenance (S09): a receipt is an opaque adapter-domain
    /// value attested by the adapter (emitter) that minted it on this chain —
    /// chain 1 here — via its record getters and its own deposit event. It
    /// correlates the ingress call; it is not a destination delivery token and
    /// carries no venue-external meaning.
    /// @dev scheduledEpoch is the original weekly escrow maturity, not an
    /// assertion that a late deposit buys votes retroactively. No arbitrary
    /// recipient/calldata.
    function deposit(address gauge, uint256 scheduledEpoch, uint256 amount) external returns (bytes32 receipt);
}
