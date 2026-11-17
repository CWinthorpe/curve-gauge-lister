// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ForkVoteMarketSpec} from "../test/fork/ForkVoteMarket.t.sol";

/// @dev Concrete fork runner, plans/FORK-PLAN.md §1.1. Lives outside BOTH
/// default source roots; instantiated only under FOUNDRY_PROFILE=fork.
contract VoteMarketForkTest is ForkVoteMarketSpec {}
