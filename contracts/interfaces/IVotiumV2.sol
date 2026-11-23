// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title IVotiumV2
/// @notice Minimal local declaration of the deployed Votium v2 deposit ingress
/// (mainnet `0x63942E31E98f1833A234077f47880A66136a2D1e`, Sourcify exact match,
/// see docs/INTEL-YB-HELPERS.md). Mirrors only the surface the VotiumAdapter
/// calls; parameter names/types/ordering are pinned to the verified deployed
/// ABI. Not a full Votium interface. Fork-side venue mirror:
/// test/fork/ForkFixture.sol `IVotiumVenue` (S26) — the three declarations
/// here must agree with its members; the venue-state extras there are
/// observation-only.
interface IVotiumV2 {
    /// @notice Current accepted deposit round; read at deposit time.
    function activeRound() external view returns (uint256);

    /// @notice Venue-configured upper bound on the number of excluded voter
    /// addresses per incentive (real `uint256 public maxExclusions`,
    /// Votium.sol:31, enforced at `:658-665` with the `!excluded` require;
    /// owner-set via `setMaxExclusions` at `:833`). Read by the adapter when
    /// the manager configures an exclusion list, so a locally valid list can
    /// never be pinned as venue-compatible without checking the venue limit.
    function maxExclusions() external view returns (uint256);

    /// @notice Per-gauge uneven deposit into one round. transferFroms each
    /// `_amounts[i]` of `_token` from the caller for `_gauges[i]`.
    function depositUnevenSplitGauges(
        address _token,
        uint256 _round,
        address[] calldata _gauges,
        uint256[] calldata _amounts,
        uint256 _maxPerVote,
        address[] calldata _excluded
    ) external;
}
