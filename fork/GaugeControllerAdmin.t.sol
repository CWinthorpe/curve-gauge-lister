// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ForkGaugeControllerAdminSpec} from "../test/fork/ForkGaugeControllerAdmin.t.sol";

/// @dev Concrete fork runner, plans/FORK-PLAN.md §1.1 pattern. Lives outside
/// the default source root; instantiated only under FOUNDRY_PROFILE=fork.
contract GaugeControllerAdminForkTest is ForkGaugeControllerAdminSpec {}
