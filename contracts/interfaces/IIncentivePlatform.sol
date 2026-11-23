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
    /// gauge-bound platform deposit/ingress; return a nonzero adapter-domain
    /// L1-ingress correlation identifier. Provenance (S09; one common
    /// contract per CX-RECEIPT): the receipt is nonzero and opaque, attested
    /// by the adapter (emitter) that minted it on this chain — chain 1 here —
    /// via its deposit event and its record getters WHERE THAT ADAPTER
    /// IMPLEMENTS THEM (Votium's proof is event-only with a repeatable
    /// full-tuple value; VoteMarket keeps keyed/chronological records and
    /// rejects repeated (gauge, scheduledEpoch) pairs). It correlates the
    /// recorded ingress call within the adapter's own domain; it is NOT a
    /// globally unique identifier (a Votium deposit of the same tuple in the
    /// same round repeats the value) and NOT a destination delivery token —
    /// it carries no venue-external meaning and proves nothing about
    /// acceptance beyond that same-chain adapter call.
    /// @dev scheduledEpoch is the original weekly escrow maturity, not an
    /// assertion that a late deposit buys votes retroactively. No arbitrary
    /// recipient/calldata.
    function deposit(address gauge, uint256 scheduledEpoch, uint256 amount) external returns (bytes32 receipt);
}
