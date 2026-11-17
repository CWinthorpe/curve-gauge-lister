// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ForkKillSpec} from "../test/fork/ForkKill.t.sol";

/// @dev Concrete fork runner, plans/FORK-PLAN.md §1.1. Lives outside BOTH
/// default source roots; instantiated only under FOUNDRY_PROFILE=fork.
contract KillForkTest is ForkKillSpec {}
