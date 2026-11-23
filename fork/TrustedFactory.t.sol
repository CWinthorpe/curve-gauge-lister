// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ForkTrustedFactoryScenarios} from "../test/fork/ForkTrustedFactory.t.sol";

/// @dev Concrete fork runner for the two trusted-factory trust identities
/// (plans/V1ALIGN-PLAN.md §4; V1ALIGN-WITNESSES.md §2 fork rows: SS-ng and
/// distinct-LP legacy REAL paid admissions at the unchanged pin, on the
/// no-bounty amended V1 core with the actual pinned validator).
/// Instantiated only under FOUNDRY_PROFILE=fork; kept outside the recursive
/// default test root like every other fork runner.
contract TrustedFactoryForkTest is ForkTrustedFactoryScenarios {}
