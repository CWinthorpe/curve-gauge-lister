// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ForkAdmissionSpec} from "../test/fork/ForkAdmission.t.sol";

/// @dev Concrete fork runner, plans/FORK-PLAN.md §1.1. Lives outside BOTH
/// default source roots; instantiated only under FOUNDRY_PROFILE=fork.
contract AdmissionForkTest is ForkAdmissionSpec {}
