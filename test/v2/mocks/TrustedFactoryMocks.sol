// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {MockListingController} from "../../../contracts/mocks/MockListingController.sol";

/// @dev Call shape the validator/module fixtures read off a candidate gauge:
/// the registry-authenticated gauge's own LP association and its self-asserted
/// factory. `factory()` is the gauge's CLAIM, never the product's authority:
/// the fixtures authenticate it only via the reciprocal proofs below
/// (plans/TRUSTEDFACTORY-PLAN.md §2.1).
interface IFactoryGaugeLike {
    function lp_token() external view returns (address);
    function factory() external view returns (address);
}

/// @dev The module-side reciprocal proof entry point, mirroring the pinned
/// validator's module surface `validateGauge(address,address,uint8)`
/// (0x641e688f, plan §2) — a LOCAL FIXTURE MODEL, not the deployed module.
interface IModuleLike {
    function validateGauge(address gauge, address factory, uint8 method) external view returns (bool);
}

/// @title AlwaysTrueTrustedValidator
/// @notice Disclosed HEALTHY CHECKER STAND-IN for the retained baseline
/// fixtures (plans/TRUSTEDFACTORY-PLAN.md §6): a code-bearing validator whose
/// `validateGauge` returns canonical true unconditionally. Supplying it to the
/// migrated constructor sites proves parameterization and keeps every old
/// downstream obligation reachable on its original path. It is NOT evidence
/// that a live non-factory gauge passes trust verification, and dedicated new
/// tests claiming actual trust verification must not use it.
contract AlwaysTrueTrustedValidator {
    function validateGauge(address) external pure returns (bool) {
        return true;
    }
}

/// @title NoSelectorValidator
/// @notice Code-bearing validator WITHOUT `validateGauge` and without any
/// fallback: the top-level read fails at dispatch ("missing function" case).
contract NoSelectorValidator {
    function unrelated() external pure returns (uint256) {
        return 1;
    }
}

/// @title TrustedFactoryModel
/// @notice FIXTURE model of a Curve factory exposing the reciprocal lookups
/// the pinned module authenticates against (plan §2.1): `get_gauge(token)`,
/// `gauge_for_vault(vault)` and `is_valid_gauge(gauge)`, each with per-key
/// revert injection so fault-vs-zero distinctions are executable. Fixture
/// setters are unrestricted test setup, not production authority.
contract TrustedFactoryModel {
    error FactoryLookupFailed();

    mapping(address => address) private _gauges;
    mapping(address => address) private _vaultGauges;
    mapping(address => bool) private _valid;
    mapping(address => bool) private _revertGetGauge;

    function setGauge(address token, address gauge) external {
        _gauges[token] = gauge;
    }

    function setVaultGauge(address vault, address gauge) external {
        _vaultGauges[vault] = gauge;
    }

    function setValidGauge(address gauge, bool valid) external {
        _valid[gauge] = valid;
    }

    /// @notice Fault injection: make the DIRECT lookup on `token` revert
    /// (rather than return zero), so the no-fallback rule is executable.
    function setGetGaugeRevert(address token, bool enabled) external {
        _revertGetGauge[token] = enabled;
    }

    function get_gauge(address token) external view returns (address) {
        if (_revertGetGauge[token]) revert FactoryLookupFailed();
        return _gauges[token];
    }

    function gauge_for_vault(address vault) external view returns (address) {
        return _vaultGauges[vault];
    }

    function is_valid_gauge(address gauge) external view returns (bool) {
        return _valid[gauge];
    }
}

/// @title GaugeValidationModuleModel
/// @notice FIXTURE model of GaugeValidationModuleV1's four reciprocal proofs
/// (plan §2.1): (1) DIRECT_LP, (2) DIRECT_OR_POOL_LP with the strict
/// successful-zero-only minter fallback, (3) VAULT, (4) FACTORY_IS_VALID_GAUGE.
/// A failed/malformed first lookup NEVER permits fallback. `fault` injects a
/// module-level revert, which the validator model collapses to false exactly
/// like the real validator's internal fault handling.
contract GaugeValidationModuleModel {
    error ModuleFault();

    bool public fault;

    function setFault(bool enabled) external {
        fault = enabled;
    }

    function validateGauge(address gauge, address factory, uint8 method) external view returns (bool) {
        if (fault) revert ModuleFault();
        address lp = IFactoryGaugeLike(gauge).lp_token();
        if (method == 1) {
            // DIRECT_LP: the factory's reverse association must equal the
            // candidate. A lookup fault propagates to the validator catch.
            return TrustedFactoryModel(factory).get_gauge(lp) == gauge;
        }
        if (method == 2) {
            // DIRECT_OR_POOL_LP: a successful NONZERO first response must
            // equal the candidate; ONLY a successful ZERO response permits
            // lp.minter() -> pool -> get_gauge(pool).
            (bool ok, bytes memory data) = factory.staticcall(abi.encodeCall(TrustedFactoryModel.get_gauge, (lp)));
            if (!ok || data.length != 32) {
                return false; // failed/malformed first read: no fallback
            }
            uint256 direct = abi.decode(data, (uint256));
            if (direct != 0) {
                return direct == uint256(uint160(gauge));
            }
            (bool okM, bytes memory dataM) = lp.staticcall(abi.encodeWithSignature("minter()"));
            if (!okM || dataM.length != 32) {
                return false;
            }
            uint256 pool = abi.decode(dataM, (uint256));
            (bool okP, bytes memory dataP) =
                factory.staticcall(abi.encodeCall(TrustedFactoryModel.get_gauge, (address(uint160(pool)))));
            if (!okP || dataP.length != 32) {
                return false;
            }
            return abi.decode(dataP, (uint256)) == uint256(uint160(gauge));
        }
        if (method == 3) {
            // VAULT: gauge_for_vault(gauge.lp_token()) == gauge.
            return TrustedFactoryModel(factory).gauge_for_vault(lp) == gauge;
        }
        if (method == 4) {
            // FACTORY_IS_VALID_GAUGE: canonical true from the factory.
            return TrustedFactoryModel(factory).is_valid_gauge(gauge);
        }
        return false;
    }
}

/// @title ConfigurableTrustedValidator
/// @notice FIXTURE model of the pinned GaugeValidator core (plan §2.1: gauge
/// code -> gauge.factory() -> nonzero factory policy -> module reciprocal
/// proof). Internal dependency faults collapse to false; the top-level fault
/// menu below is used ONLY to exercise the product's read-fault normalization
/// (plan §3.3/§5.1 CheckerReadFaultsFailClosed) and is disclosed as fault
/// injection, never as a happy path. NOT the deployed validator: live factory
/// semantics are certified by the fork identities.
contract ConfigurableTrustedValidator {
    error CheckerFault();
    error UnexpectedArgument();

    enum TopFault {
        None,
        Revert,
        Empty,
        OneByte,
        ThirtyOneByte,
        TrueWithTail, // 64 bytes: canonical true word plus tail
        Word2, // noncanonical bool word
        MaxUint // word = 2**256 - 1
    }

    struct Policy {
        address module;
        uint8 method;
    }

    mapping(address => Policy) private _policies;
    TopFault private _fault;
    bool private _rejectAll;
    bool private _gateArmed;
    address private _gateArg;

    /// @notice Unrestricted fixture wiring: the policy configured for a
    /// factory the candidate gauges claim.
    function setPolicy(address factory, address module, uint8 method) external {
        _policies[factory] = Policy(module, method);
    }

    function setTopFault(TopFault fault_) external {
        _fault = fault_;
    }

    /// @notice Canonical-false mode (external dependency "returns false"
    /// case, including underlying faults the real validator collapses).
    function setRejectAll(bool enabled) external {
        _rejectAll = enabled;
    }

    /// @notice Argument gate: when armed, validateGauge accepts EXACTLY
    /// `onlyArg` and reverts on every other argument, so the witness can pin
    /// the single argument the product passes (plan §5.1 exact-target cells).
    function setArgumentGate(bool enabled, address onlyArg) external {
        _gateArmed = enabled;
        _gateArg = onlyArg;
    }

    function validateGauge(address gauge) external view returns (bool) {
        TopFault fault = _fault;
        if (fault == TopFault.Revert) revert CheckerFault();
        if (fault == TopFault.Empty) {
            assembly {
                return(0, 0)
            }
        }
        if (fault == TopFault.OneByte) {
            assembly {
                mstore(0, 1)
                return(0, 1)
            }
        }
        if (fault == TopFault.ThirtyOneByte) {
            assembly {
                mstore(0, 1)
                return(1, 31)
            }
        }
        if (fault == TopFault.TrueWithTail) {
            assembly {
                mstore(0, 1)
                mstore(32, 0xB00B)
                return(0, 64)
            }
        }
        if (fault == TopFault.Word2) {
            assembly {
                mstore(0, 2)
                return(0, 32)
            }
        }
        if (fault == TopFault.MaxUint) {
            assembly {
                mstore(0, not(0))
                return(0, 32)
            }
        }
        if (_gateArmed && gauge != _gateArg) revert UnexpectedArgument();
        if (_rejectAll) {
            return false;
        }
        if (gauge.code.length == 0) {
            return false; // zero/absent candidate has no factory to authenticate
        }
        address claimedFactory;
        try IFactoryGaugeLike(gauge).factory() returns (address f) {
            claimedFactory = f;
        } catch {
            return false; // unusable factory claim collapses to false
        }
        if (claimedFactory == address(0)) {
            return false; // zero factory: rejected
        }
        Policy memory p = _policies[claimedFactory];
        if (p.module == address(0) || p.method == 0 || p.method > 4) {
            return false; // no configured policy
        }
        try IModuleLike(p.module).validateGauge(gauge, claimedFactory, p.method) returns (bool verdict) {
            return verdict;
        } catch {
            return false; // underlying proof fault collapses to false, like the real validator
        }
    }
}

/// @title FactoryClaimGauge
/// @notice Gauge fixture that self-asserts a factory (the plan §2.1 claim the
/// validator must authenticate, never trust). `factoryReadReverts` models the
/// legacy gauge with no usable `factory()`.
contract FactoryClaimGauge {
    error FactoryReadFault();

    address public lp_token;
    bool public is_killed;
    address private _factory;
    bool private _factoryReadReverts;

    constructor(address lp_, address factory_) {
        lp_token = lp_;
        _factory = factory_;
    }

    function factory() external view returns (address) {
        if (_factoryReadReverts) revert FactoryReadFault();
        return _factory;
    }

    function setKilled(bool killed) external {
        is_killed = killed;
    }

    function setFactory(address factory_) external {
        _factory = factory_;
    }

    function setFactoryReadReverts(bool enabled) external {
        _factoryReadReverts = enabled;
    }
}

/// @title LegacyLpToken
/// @notice Distinct-LP fixture: its OWN token contract, separate from the
/// pool, carrying `minter() -> pool` for the method-2 fallback route
/// (plan §2.1/§4.1). Keeps the two-crypto legacy shape from relabeling the
/// LP as the pool.
contract LegacyLpToken {
    address public minter;

    constructor(address minter_) {
        minter = minter_;
    }

    function setMinter(address minter_) external {
        minter = minter_;
    }
}

/// @title PoisonAddController
/// @notice Test-local controller whose `add_gauge` reverts with a DISTINCT
/// sentinel while every other routine (membership, weights, reads) stays
/// honest — the independent effect-path poison for the plan §5.1 snapshot
/// contract's ordering cells.
contract PoisonAddController is MockListingController {
    error PoisonedAdd();

    bool private _poisonAdd;

    constructor(address dao_, int128 gaugeTypeCount_) MockListingController(dao_, gaugeTypeCount_) {}

    function setPoisonAdd(bool enabled) external {
        _poisonAdd = enabled;
    }

    function add_gauge(address gauge, int128 gaugeType, uint256 weight) public override {
        if (_poisonAdd) revert PoisonedAdd();
        super.add_gauge(gauge, gaugeType, weight);
    }
}
