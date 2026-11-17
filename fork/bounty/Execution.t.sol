// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ForkThinExecutionSpec} from "../../test/fork/bounty/ForkThinExecution.t.sol";

/// @dev Concrete fork runner for the thin execution/refund suite (plans/
/// BOUNTY-THIN-PLAN.md §7.3 F03/F04). Instantiated only under
/// FOUNDRY_PROFILE=fork.
contract ThinExecutionForkTest is ForkThinExecutionSpec {}
