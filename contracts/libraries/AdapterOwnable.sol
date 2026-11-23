// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title AdapterOwnable
/// @notice The two venue adapters' identical two-step ownership transition,
/// shared (S22): nonzero proposal, pending-owner acceptance with clear, the
/// existing events and the existing string-revert encodings, and unchanged
/// storage layout — `owner` and `pendingOwner` remain the first two slots of
/// each adapter exactly as before, so inherited public getters keep their
/// ABI shape and slot positions.
/// @dev Deliberately NOT the core's ownership code: `CurveGaugeLister` keeps
/// its custom errors, its lock and its independent boundary. No uniform-error
/// or layout change is made anywhere by this abstraction.
abstract contract AdapterOwnable {
    /// @notice Manager allowed to tune per-deposit configuration.
    address public owner;
    /// @notice Two-step ownership candidate; no renounce path exists.
    address public pendingOwner;

    event OwnershipTransferStarted(address indexed owner, address indexed pendingOwner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    error NotOwner();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    /// @notice Manager proposes a nonzero new owner; acceptance is required.
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "zero owner");
        pendingOwner = newOwner;
        emit OwnershipTransferStarted(owner, newOwner);
    }

    /// @notice Only pendingOwner may accept; no renounce path exists.
    function acceptOwnership() external {
        require(msg.sender == pendingOwner, "not pending owner");
        address previous = owner;
        owner = msg.sender;
        pendingOwner = address(0);
        emit OwnershipTransferred(previous, msg.sender);
    }
}
