// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ForkTrustedFactoryScenarios} from "../test/fork/ForkTrustedFactory.t.sol";

/// @dev Concrete fork runner for the two trusted-factory trust identities
/// (plans/TRUSTEDFACTORY-PLAN.md §5.1: SS-ng and distinct-LP legacy REAL
/// paid admissions at the unchanged pin). Instantiated only under
/// FOUNDRY_PROFILE=fork; kept outside the recursive default test root like
/// every other fork runner.
contract TrustedFactoryForkTest is ForkTrustedFactoryScenarios {}
