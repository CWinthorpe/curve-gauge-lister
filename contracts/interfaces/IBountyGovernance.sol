// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title IBountyGovernance
/// @notice Narrow Agent/proxy/factory/gauge provenance interfaces for the
/// bounty's verified Stableswap-NG factory/proxy route
/// (plans/BOUNTY-PLAN.md §1.5, retained by plans/BOUNTY-REWORK-PLAN.md §2).
/// Declaration-only; no runtime. The retired IWalletChecker dependency is
/// gone: the bounty holds no veCRV principal and gates no proposal rights.
interface IAgent {
    function implementation() external view returns (address);

    /// @notice Governance script execution endpoint; the canonical scripts
    /// call ONLY this with ETH value zero.
    function execute(address target, uint256 value, bytes calldata data) external;
}

interface IKillProxy {
    function dao() external view returns (address);

    function emergency_dao() external view returns (address);

    /// @notice Proxy-level kill: `set_killed(address)`, NOT the gauge's
    /// `set_killed(bool)`. Hardcodes the gauge boolean to true.
    function set_killed(address gauge) external;
}

interface ISupportedFactory {
    function admin() external view returns (address);
}

interface ISupportedGauge {
    /// @notice Self-report alone is never authentication; the constructor-bound
    /// supported factory is the comparison target.
    function factory() external view returns (address);

    function is_killed() external view returns (bool);
}
