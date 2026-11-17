// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title ITrustedGaugeValidator
/// @notice Call-site-local ABI declaration for the single top-level predicate
/// of the constructor-pinned trusted gauge validator
/// (plans/TRUSTEDFACTORY-PLAN.md §2/§3.2). The product never imports,
/// vendors or deploys the external validator registry/module source: this
/// file declares ONLY the one function V2 reads, so the admission helper can
/// encode the exact selector (`validateGauge(address)` = 0xe92cd3d3).
/// @dev The proposal predicate `validateProposalGauges(uint256)`
/// (0x2da285c4), the policy read `policyForFactory(address)` (0x967d5935)
/// and `proposalModule()` (0xf8dc587d) are deliberately NOT declared here:
/// they are not admission authority (plan §2).
interface ITrustedGaugeValidator {
    /// @notice Canonical true only when the candidate gauge authenticates
    /// against the policy configured for the factory the gauge itself names
    /// (reciprocal factory/module proof; plan §2.1). Faults in the
    /// validator's own dependency reads are collapsed to false by the real
    /// validator and stay rejections.
    /// @param gauge The candidate GAUGE address — never a pool, LP token,
    /// factory, caller or inferred deployer (plan §2.1).
    function validateGauge(address gauge) external view returns (bool);
}
