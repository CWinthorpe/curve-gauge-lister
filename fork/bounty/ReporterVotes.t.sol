// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ReporterVotesForkSpec} from "../../test/fork/bounty/ForkReporterVotes.t.sol";

/// @dev Concrete fork runner for the migrated rework beneficiary-binding /
/// independent-ballot suite (plans/BOUNTY-REWORK-PLAN.md §7: F01/F02).
/// Instantiated only under FOUNDRY_PROFILE=fork.
contract ReporterVotesForkTest is ReporterVotesForkSpec {}
