#!/usr/bin/env python3
"""P2 named trust falsifiers (V1ALIGN-WITNESSES.md, F-TF-* rows).

Each mutant: fresh disposable copy of the tree, ONE product mutation, exact
selected witness identity, required red at the named label, then restored
rerun green. Tests stay byte-identical; only
contracts/CurveGaugeLister.sol mutates, and only inside the scratch copy.
"""
import json, os, shutil, subprocess, sys

REPO = "/home/winny/curve-gauge-lister"
ROOT = "/home/winny/tmp-scratch/v1align-falsify/p2"
CONTRACT = "contracts/CurveGaugeLister.sol"

ORDER_BLOCK = (
    "\n"
    "        // V1ALIGN \u00a72.1 ordering: exactly here, after `_admit` returns and\n"
    "        // before readiness, listing write, `totalEscrow` accounting, fee\n"
    "        // transfer or `controller.add_gauge`.\n"
    "        _requireTrustedGauge(gauge);\n"
)

def sub(text, old, new, must=1):
    assert text.count(old) == must, "pattern count != %d for %r" % (must, old[:80])
    return text.replace(old, new)

# mutant id -> (test name, required first-label, list of (old,new) edits)
MUTANTS = {
    "F-TF-CHAIN": ("test_TF_ConstructorPinAndGuards", "TF_CHAIN_FIRST", [
        ("        if (block.chainid != 1) revert WrongChain();\n", "")]),
    "F-TF-CODE": ("test_TF_ConstructorPinAndGuards", "TF_PIN_NO_CODE", [
        ("        if (trustedGaugeValidator_.code.length == 0) revert NoCode(trustedGaugeValidator_);\n", "")]),
    "F-TF-PIN": ("test_TF_ConstructorPinAndGuards", "TF_PIN_EXACT", [
        ("        trustedGaugeValidator = trustedGaugeValidator_;",
         "        trustedGaugeValidator = 0x888888c34a46d0b2A34e9204e5273208E670e784; // MUTANT F-TF-PIN")]),
    "F-TF-PAUSE": ("test_TF_ConstructorPinAndGuards", "TF_PIN_EXACT", [
        ("        owner = owner_;\n        paused = true;\n", "        owner = owner_;\n")]),
    "F-TF-FALSE": ("test_TF_UntrustedPaidAdmissionBeforeEffects", "TF_FALSE_REJECTS", [
        ("        if (verdict == 0) revert UntrustedGauge(gauge);\n", "")]),
    "F-TF-FAULT": ("test_TF_CheckerReadFaultsFailClosed", "TF_READ_FAULT_REJECTS", [
        ("        if (!ok) revert TrustedGaugeCheckFailed(gauge);",
         "        if (!ok) return; // MUTANT F-TF-FAULT")]),
    "F-TF-LENGTH": ("test_TF_CheckerReadFaultsFailClosed", "TF_EXACT_RETURN_LENGTH", [
        ("        if (data.length != 32) revert TrustedGaugeCheckFailed(gauge);",
         "        if (data.length < 32) revert TrustedGaugeCheckFailed(gauge); // MUTANT F-TF-LENGTH")]),
    "F-TF-BOOL": ("test_TF_CheckerReadFaultsFailClosed", "TF_CANONICAL_BOOL", [
        ("        if (verdict > 1) revert TrustedGaugeCheckFailed(gauge);\n", "")]),
    "F-TF-ARG": ("test_TF_TrustedPaidAdmissionAndExactTarget", "TF_EXACT_GAUGE_ARGUMENT", [
        ("        _requireTrustedGauge(gauge);\n\n        // auditfix001",
         "        _requireTrustedGauge(pool); // MUTANT F-TF-ARG\n\n        // auditfix001")]),
    "F-TF-SELECTOR": ("test_TF_TrustedPaidAdmissionAndExactTarget", "TF_EXACT_GAUGE_ARGUMENT", [
        ("trustedGaugeValidator.staticcall(abi.encodeCall(ITrustedGaugeValidator.validateGauge, (gauge)));",
         "trustedGaugeValidator.staticcall(abi.encodeWithSelector(bytes4(0x2da285c4), uint256(uint160(gauge)))); // MUTANT F-TF-SELECTOR: proposal selector, not validateGauge(address)")]),
    "F-TF-AFTER-ADD": ("test_TF_UntrustedPaidAdmissionBeforeEffects", "TF_BEFORE_ADD_GAUGE", [
        (ORDER_BLOCK, ""),
        ("        if (IListingController(controller).gauge_types(gauge) != derivedType) revert MembershipFailed();\n\n        emit GaugeListed(gauge, pool, msg.sender, derivedType, rec.listingEpoch, FEE, false);",
         "        if (IListingController(controller).gauge_types(gauge) != derivedType) revert MembershipFailed();\n        _requireTrustedGauge(gauge); // MUTANT F-TF-AFTER-ADD\n\n        emit GaugeListed(gauge, pool, msg.sender, derivedType, rec.listingEpoch, FEE, false);")]),
    "F-TF-AFTER-FEE": ("test_TF_UntrustedPaidAdmissionBeforeEffects", "TF_BEFORE_TRANSFER", [
        (ORDER_BLOCK, ""),
        ("        IListingController(controller).add_gauge(gauge, derivedType, INITIAL_WEIGHT);",
         "        _requireTrustedGauge(gauge); // MUTANT F-TF-AFTER-FEE\n        IListingController(controller).add_gauge(gauge, derivedType, INITIAL_WEIGHT);")]),
    "F-TF-AFTER-READY": ("test_TF_UntrustedPaidAdmissionBeforeEffects", "TF_BEFORE_READINESS", [
        (ORDER_BLOCK, ""),
        ("        _requirePlatformsReady(plat);",
         "        _requirePlatformsReady(plat);\n        _requireTrustedGauge(gauge); // MUTANT F-TF-AFTER-READY")]),
    "F-TF-REGISTRY": ("test_TF_RegistryAuthenticationPrecedesTrust", "TF_REGISTRY_FIRST", [
        (ORDER_BLOCK, ""),
        ("        (address lpToken, int128 derivedType) = _admit(pool, gauge, gaugeIndex, handlerId, cfg);\n\n        // auditfix001",
         "        _requireTrustedGauge(gauge); // MUTANT F-TF-REGISTRY\n        (address lpToken, int128 derivedType) = _admit(pool, gauge, gaugeIndex, handlerId, cfg);\n\n        // auditfix001")]),
    "F-TF-OWNER": ("test_TF_UntrustedPaidAdmissionBeforeEffects", "TF_OWNER_PAID_NOT_EXEMPT", [
        ("        _requireTrustedGauge(gauge);\n\n        // auditfix001",
         "        if (msg.sender != owner) _requireTrustedGauge(gauge); // MUTANT F-TF-OWNER\n\n        // auditfix001")]),
    "F-TF-FREE": ("test_TF_DaoFreeLaneIsTrustIndependent", "TF_DAO_NO_CHECKER_DEPENDENCE", [
        ("        if (msg.sender != owner) revert NotOwner();\n        AdmissionConfig memory cfg = _admissionConfig;\n        (address lpToken, int128 derivedType) = _admit(pool, gauge, gaugeIndex, handlerId, cfg);",
         "        if (msg.sender != owner) revert NotOwner();\n        AdmissionConfig memory cfg = _admissionConfig;\n        (address lpToken, int128 derivedType) = _admit(pool, gauge, gaugeIndex, handlerId, cfg);\n        _requireTrustedGauge(gauge); // MUTANT F-TF-FREE")]),
    "F-TF-RETRO": ("test_TF_TrustIsAdmissionOnly", "TF_NO_RETROACTIVE_DRIP_GATE", [
        ("        if (st != Status.Active) return (0, 0);\n",
         "        if (st != Status.Active) return (0, 0);\n        _requireTrustedGauge(gauge); // MUTANT F-TF-RETRO\n")]),
    "F-TF-RECORD": ("test_TF_TrustedPaidAdmissionAndExactTarget", "TF_TRUSTED_PAID_ACTIVE", [
        ("        rec.votium = plat.votium;\n", "")]),
    "F-TF-FREE-EVENT": ("test_TF_DaoFreeLaneIsTrustIndependent", "TF_DAO_NO_FACTORY_ALLOWED", [
        ("        emit GaugeListed(gauge, pool, address(0), derivedType, rec.listingEpoch, 0, true);\n", "")]),
}

def run(cmd, cwd, log):
    r = subprocess.run(cmd, shell=True, cwd=cwd, capture_output=True, text=True)
    open(log, "w").write("$ " + cmd + "\n\n" + r.stdout + "\n--stderr--\n" + r.stderr)
    return r.returncode, r.stdout

def make_copy(tag):
    d = os.path.join(ROOT, tag)
    if os.path.exists(d):
        shutil.rmtree(d)
    shutil.copytree(
        REPO, d,
        ignore=shutil.ignore_patterns("out", "cache", "out-fork", "cache-fork", ".git"),
    )
    return d

def main():
    only = sys.argv[1:] if len(sys.argv) > 1 else list(MUTANTS)
    os.makedirs(ROOT, exist_ok=True)
    results = []
    for mid in only:
        testname, label, edits = MUTANTS[mid]
        d = make_copy("copy")
        cpath = os.path.join(d, CONTRACT)
        pristine = open(cpath).read()
        # 1. pristine green (fresh baseline for this mutant)
        rc, out = run(
            f"forge test --offline --match-contract TrustedFactoryTest --match-test '^{testname}\\(\\)$' 2>&1",
            d, os.path.join(ROOT, f"{mid}.pristine.log"))
        sel = [l for l in out.splitlines() if l.startswith("Ran ") and "1 test" in l]
        pg = ("[PASS] " + testname + "()" in out) and rc == 0 and bool(sel)
        # 2. mutant red
        mutated = pristine
        try:
            for old, new in edits:
                mutated = sub(mutated, old, new)
        except AssertionError as e:
            results.append((mid, "MUTATION-PATCH-FAIL", str(e)))
            print(mid, "MUTATION-PATCH-FAIL", e, flush=True)
            continue
        assert mutated != pristine
        open(os.path.join(ROOT, f"{mid}.patch.txt"), "w").write(
            "\n\n".join(f"OLD:\n{old}\nNEW:\n{new}" for old, new in edits) + "\n")
        open(cpath, "w").write(mutated)
        rc2, out2 = run(
            f"forge test --offline --match-contract TrustedFactoryTest --match-test '^{testname}\\(\\)$' -vv 2>&1",
            d, os.path.join(ROOT, f"{mid}.red.log"))
        red = ("[FAIL" in out2) and ("Suite result: FAILED" in out2) and (label in out2) and rc2 != 0 and ("Ran 1 test for" in out2)
        # 3. restored green
        open(cpath, "w").write(pristine)
        rc3, out3 = run(
            f"forge test --offline --match-contract TrustedFactoryTest --match-test '^{testname}\\(\\)$' 2>&1",
            d, os.path.join(ROOT, f"{mid}.restored.log"))
        rg = ("[PASS] " + testname + "()" in out3) and rc3 == 0
        status = "OK" if (pg and red and rg) else "FAIL"
        results.append((mid, status, f"pristine_green={pg} red@{label}={red} restored_green={rg}"))
        print(f"{mid}: {status} | {results[-1][2]}", flush=True)
    bad = [r for r in results if r[1] != "OK"]
    print(json.dumps([list(r) for r in results], indent=1))
    sys.exit(1 if bad else 0)

main()
