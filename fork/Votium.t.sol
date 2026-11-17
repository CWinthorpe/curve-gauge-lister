// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ForkVotiumSpec} from "../test/fork/ForkVotium.t.sol";

/// @dev Concrete fork runner, plans/FORK-PLAN.md §1.1. Lives outside BOTH
/// default source roots; instantiated only under FOUNDRY_PROFILE=fork.
contract VotiumForkTest is ForkVotiumSpec {}
