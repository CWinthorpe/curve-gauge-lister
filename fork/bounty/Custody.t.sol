// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ForkThinCustodySpec} from "../../test/fork/bounty/ForkThinCustody.t.sol";

/// @dev Concrete fork runner for the thin custody/DAO-forfeit suite (plans/
/// BOUNTY-THIN-PLAN.md §7.3 F05-F08). Instantiated only under
/// FOUNDRY_PROFILE=fork.
contract ThinCustodyForkTest is ForkThinCustodySpec {}
