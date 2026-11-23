// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title AdapterCustody
/// @notice Stateless binding and custody predicates shared by the two venue
/// adapters (CX-ADAPTER): the bound-lister comparison, the deposit-shape
/// comparison, the exact inbound-pull comparison and the custody-cleared
/// baseline comparison.
/// @dev The helpers hold no storage, no inheritance and declare no errors:
/// each adapter keeps its own `_lister` slot, its owner-only one-time
/// binding, its venue-specific call order, and its OWN named errors and
/// error order at the call sites. This is deliberately not a shared
/// inherited storage prefix for `_lister` (not this cut), not an equation of
/// the core's outbound-delta checks with these inbound/baseline comparisons,
/// and not a normalization of the two venues' distinct policies
/// (bounded/cleared approvals, evidence, no-withdrawal and the exclusion
/// rules stay per venue).
library AdapterCustody {
    /// @dev True iff `caller` equals the adapter's bound lister. The
    /// zero-means-unbound meaning stays with `_lister` and its getter.
    function isBoundCaller(address boundLister, address caller) internal pure returns (bool) {
        return caller == boundLister;
    }

    /// @dev True iff the deposit shape is well-formed: a nonzero candidate
    /// gauge and a nonzero amount. Shape check only; venue-keyed duplicate
    /// policy stays at the adapter that has one.
    function validDepositShape(address gauge, uint256 amount) internal pure returns (bool) {
        return gauge != address(0) && amount != 0;
    }

    /// @dev True iff the adapter's balance gained EXACTLY `amount` from the
    /// pull (credit in addition form). Distinct from the baseline
    /// comparison below: one proves the pull, the other proves nothing was
    /// left behind.
    function exactPullCredit(uint256 balBefore, uint256 balAfter, uint256 amount) internal pure returns (bool) {
        return balAfter == balBefore + amount;
    }

    /// @dev True iff the adapter's balance returned to its pre-pull
    /// baseline exactly — every pulled unit left custody within the same
    /// deposit call.
    function custodyClearedToBaseline(uint256 balBefore, uint256 balAfter) internal pure returns (bool) {
        return balAfter == balBefore;
    }
}
