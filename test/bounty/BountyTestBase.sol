// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {TestBase} from "../TestBase.sol";

/// @dev Test-local cheatcode additions permitted by plans/BOUNTY-PLAN.md §5.1
/// (roll/expectCall/snapshot support) on the SAME cheatcode dispatcher. No
/// forge-std import; the frozen TestBase is not edited. mockCall-style
/// bypasses are deliberately absent: mocks must be real deployed contracts.
interface VmExtras {
    function roll(uint256 newHeight) external;
    function snapshot() external returns (uint256);
    function revertTo(uint256 snapshotId) external returns (bool);
    function expectCall(address caller, address callee, bytes calldata data) external;
    function expectCall(address caller, address callee, bytes calldata data, uint64 returnData, uint64 revertData)
        external;
    function etch(address target, bytes calldata newRuntime) external;
    function deal(address who, uint256 newBalance) external;
    function log_named_uint(string calldata key, uint256 val) external;
    function log_named_address(string calldata key, address val) external;
}

/// @notice Shared base for every bounty/V2 offline suite: the frozen
/// assertions plus bounty event signatures for exact log matching and the
/// pinned economic constants.
abstract contract BountyTestBase is TestBase {
    VmExtras internal constant vmx = VmExtras(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    // ------------------------- pinned constants ---------------------------
    uint256 internal constant FEE = 10_000e18;
    uint256 internal constant QUARTER = 2_500e18;
    uint256 internal constant STAKE = 1000e18;
    uint256 internal constant WEEK = 604800;
    uint256 internal constant MAX_TIME = 126144000;
    uint256 internal constant COOLDOWN = 43200;
    uint256 internal constant VOTE_TIME = 604800;
    uint256 internal constant EXECUTION_GRACE = 604800; // 7d after ballot (§9)
    uint256 internal constant MIN_BALANCE = 2500e18;
    /// @notice Thursday 2026-11-12 00:00 UTC (baseline fixture anchor).
    uint256 internal constant T0 = 1794441600;
    uint256 internal constant SUPPORT_REQUIRED = 510000000000000000;
    uint256 internal constant MIN_ACCEPT_QUORUM = 300000000000000000;

    // ------------------------- bounty events (topic0) ---------------------
    event ListerBound(address indexed lister);

    event ReportSubmitted(
        bytes32 indexed reportId,
        address indexed reporter,
        address indexed gauge,
        uint256 proposalId,
        uint256 reportNonce,
        bytes32 evidenceHash,
        uint256 voteEnd,
        uint256 executeBy
    );
    event ReportStateChanged(bytes32 indexed reportId, uint8 phase);

    event DaoFlushed(uint256 amount, uint256 receiptWeek);
    /// @notice V2's versioned confiscation event (replaces V1's shape).
    event EscrowConfiscatedV2(
        address indexed gauge,
        address indexed feeDistributor,
        bytes32 indexed reportId,
        uint256 gross,
        uint256 reporterReward,
        uint256 fdConfiscated,
        uint256 receiptWeek
    );

    // ------------------------- helpers ------------------------------------

    /// @dev Full topic0 of an event signature for raw log matching.
    function sig(string memory signature) internal pure returns (bytes32) {
        return keccak256(bytes(signature));
    }

    function assertEq(bool a, bool b, string memory label) internal pure {
        require(a == b, label);
    }

    function bytesEq(bytes memory a, bytes memory b, string memory label) internal pure {
        require(keccak256(a) == keccak256(b), label);
    }
}
