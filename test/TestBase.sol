// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @dev Minimal local Foundry cheatcode declarations (executor-owned; no
/// forge-std import, no network dependency). Only the subset this suite uses.
interface Vm {
    struct Log {
        bytes32[] topics;
        bytes data;
        address emitter;
    }

    function warp(uint256 newTimestamp) external;
    function prank(address newCaller) external;
    function startPrank(address newCaller) external;
    function stopPrank() external;
    function expectRevert() external;
    function expectRevert(bytes4 revertData) external;
    function expectRevert(bytes calldata revertData) external;
    function expectEmit(bool checkTopic1, bool checkTopic2, bool checkTopic3, bool checkData) external;
    function expectEmit(bool checkTopic1, bool checkTopic2, bool checkTopic3, bool checkData, address emitter) external;
    function recordLogs() external;
    function getRecordedLogs() external view returns (Log[] memory logs);

    // exec4 additions (review2 findings 2, 4): the chain-id fixture for the
    // source-chain campaign test and the compiled-ABI allowlist comparison.
    // Same cheatcode dispatcher, still no forge-std dependency.
    function chainId(uint256 newChainId) external;

    // exec6 additions (review4 finding 1): the authoritative function
    // inventory is the FRESH COMPILED ARTIFACT's complete methodIdentifiers
    // signature keys, read straight from the artifact JSON this very forge
    // build writes under out/ (probed registered and exact on this Forge
    // 1.7.1 build).
    function readFile(string memory path) external returns (string memory data);
    function keyExistsJson(string memory json, string memory key) external returns (bool);
    function parseJsonKeys(string memory json, string memory key) external returns (string[] memory keys);
}

/// @notice Minimal local test base: cheatcode handle and assertions. Every
/// assertion reverts with a descriptive label, surfaced by `forge test -vvv`.
abstract contract TestBase {
    /// @dev Cheatcode dispatcher (prank/warp/expect*).
    Vm internal constant vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    /// @dev Deterministic local actor: pure keccak of a label, no cheatcode.
    function actor(string memory name) internal pure returns (address) {
        return address(uint160(uint256(keccak256(bytes(name)))));
    }

    event GaugeListed(
        address indexed gauge,
        address indexed pool,
        address indexed payer,
        int128 gaugeType,
        uint256 listingEpoch,
        uint256 fee,
        bool daoExempt
    );
    event PlatformDeposit(
        address indexed gauge,
        address indexed platform,
        uint256 indexed scheduledEpoch,
        uint256 executionEpoch,
        uint256 amount,
        bytes32 receipt
    );
    event QuarterReleased(address indexed gauge, uint256 indexed scheduledEpoch, uint256 amount, uint256 remaining);
    event EscrowConfiscated(address indexed gauge, address indexed feeDistributor, uint256 amount, uint256 receiptWeek);
    event FeeCheckpointResult(bool success);
    event PauseSet(bool paused);
    event AdmissionConfigSet(address registry, uint8 maxCoins);
    event PlatformConfigSet(address votium, address voteMarket, uint16 votiumBps);
    event OwnershipTransferStarted(address indexed owner, address indexed pendingOwner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    function assertEq(uint256 a, uint256 b, string memory label) internal pure {
        require(a == b, label);
    }

    function assertEq(address a, address b, string memory label) internal pure {
        require(a == b, label);
    }

    function assertEq(bytes32 a, bytes32 b, string memory label) internal pure {
        require(a == b, label);
    }

    function assertEq(int128 a, int128 b, string memory label) internal pure {
        require(a == b, label);
    }

    function assertTrue(bool condition, string memory label) internal pure {
        require(condition, label);
    }

    function assertFalse(bool condition, string memory label) internal pure {
        require(!condition, label);
    }

    /// @dev True if `logs` contains a log from `emitter` with `sig` topic0.
    function hasEventFrom(Vm.Log[] memory logs, address emitter, bytes32 sig) internal pure returns (bool) {
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].emitter == emitter && logs[i].topics.length > 0 && logs[i].topics[0] == sig) return true;
        }
        return false;
    }

    /// @dev Count logs from `emitter` with `sig` topic0.
    function countEvents(Vm.Log[] memory logs, address emitter, bytes32 sig) internal pure returns (uint256 n) {
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].emitter == emitter && logs[i].topics.length > 0 && logs[i].topics[0] == sig) n += 1;
        }
    }
}
