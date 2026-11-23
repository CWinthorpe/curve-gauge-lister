// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title ITrustedGaugeValidator
/// @notice Call-site-local ABI declaration for the single top-level predicate
/// of the constructor-pinned trusted gauge validator read by the amended V1
/// `CurveGaugeLister` (plans/V1ALIGN-PLAN.md §2.1). The product never imports,
/// vendors or deploys the external validator registry/module source: this
/// file declares ONLY the one function paid admission reads, so the admission
/// helper can encode the exact selector (`validateGauge(address)` =
/// 0xe92cd3d3).
/// @dev The proposal predicate `validateProposalGauges(uint256)`
/// (0x2da285c4), the policy read `policyForFactory(address)` (0x967d5935)
/// and `proposalModule()` (0xf8dc587d) are deliberately NOT declared here:
/// they are not admission authority (plan §2.1).
interface ITrustedGaugeValidator {
    /// @notice Canonical true only when the candidate gauge authenticates
    /// against the policy configured for the factory the gauge itself names
    /// (reciprocal factory/module proof; plan §2.1). Faults in the
    /// validator's own dependency reads are collapsed to false by the real
    /// validator and stay rejections.
    /// @dev The `bool` here is the WIRE claim only (CX-HISTORY): the product
    /// call site does not trust the decoder. `CurveGaugeLister
    /// ._requireTrustedGauge` requires a SUCCESSFUL staticcall returning
    /// EXACTLY 32 bytes whose uint256 word is canonically 1 (canonical zero
    /// → UntrustedGauge; failure, wrong length, or word > 1 →
    /// TrustedGaugeCheckFailed, with checker error data normalized, never
    /// bubbled). That exact-length/canonical-true law lives at the call
    /// site and is not weakened by this declaration's typed return.
    /// @param gauge The candidate GAUGE address — never a pool, LP token,
    /// factory, caller or inferred deployer (plan §2.1).
    function validateGauge(address gauge) external view returns (bool);
}
