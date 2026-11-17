// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ForkDuplicateBallotScenarios} from "../../test/fork/bounty/ForkDuplicateBallot.t.sol";

/// @dev Concrete fork runner for the V02-W1 duplicate-canonical-ballot
/// acceptance witness (plans/BOUNTY-V02-PLAN.md §2 item 3 / §4 fork identity).
/// Instantiated only under FOUNDRY_PROFILE=fork; kept outside the recursive
/// default test root like every other fork runner.
contract DuplicateBallotForkTest is ForkDuplicateBallotScenarios {}
