#!/usr/bin/env python3
"""G6 named product-only falsifiers — FINAL set (V1ALIGN-WITNESSES.md §3).

Runs inside a clean isolated checkout of the committed package-3 candidate
(env CGL_CANDIDATE). Each mutant row: pristine green / named mutant red at
the first discriminating label / restored green, in disposable copies with
the final committed tests byte-identical (tests are never mutated). One
product mutation per row from a fresh product baseline.

Rows: 19 F-TF-* + F-NB-SPLIT, F-NB-WEIGHT, F-NB-HORIZON, F-NB-ACCOUNT
(two required identities), F-NB-POST, F-NB-BIND-VOTIUM, F-NB-BIND-VOTEMARKET.
"""
import json, os, shutil, subprocess, sys

CAND = os.environ["CGL_CANDIDATE"]
WORK = os.environ.get("CGL_FALSIFY_WORK", "/home/winny/tmp-scratch/v1align-falsify/p3")
CL = "contracts/CurveGaugeLister.sol"
VA = "contracts/adapters/VotiumAdapter.sol"
VMA = "contracts/adapters/VoteMarketAdapter.sol"

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

# id -> (file, edits, [(testname, required-label), ...])
MUTANTS = {
    "F-TF-CHAIN": (CL, [("        if (block.chainid != 1) revert WrongChain();\n", "")],
        [("test_TF_ConstructorPinAndGuards", "TF_CHAIN_FIRST")]),
    "F-TF-CODE": (CL, [("        if (trustedGaugeValidator_.code.length == 0) revert NoCode(trustedGaugeValidator_);\n", "")],
        [("test_TF_ConstructorPinAndGuards", "TF_PIN_NO_CODE")]),
    "F-TF-PIN": (CL, [("        trustedGaugeValidator = trustedGaugeValidator_;",
        "        trustedGaugeValidator = 0x888888c34a46d0b2A34e9204e5273208E670e784; // MUTANT F-TF-PIN")],
        [("test_TF_ConstructorPinAndGuards", "TF_PIN_EXACT")]),
    "F-TF-PAUSE": (CL, [("        owner = owner_;\n        paused = true;\n", "        owner = owner_;\n")],
        [("test_TF_ConstructorPinAndGuards", "TF_PIN_EXACT")]),
    "F-TF-FALSE": (CL, [("        if (verdict == 0) revert UntrustedGauge(gauge);\n", "")],
        [("test_TF_UntrustedPaidAdmissionBeforeEffects", "TF_FALSE_REJECTS")]),
    "F-TF-FAULT": (CL, [("        if (!ok) revert TrustedGaugeCheckFailed(gauge);",
        "        if (!ok) return; // MUTANT F-TF-FAULT")],
        [("test_TF_CheckerReadFaultsFailClosed", "TF_READ_FAULT_REJECTS")]),
    "F-TF-LENGTH": (CL, [("        if (data.length != 32) revert TrustedGaugeCheckFailed(gauge);",
        "        if (data.length < 32) revert TrustedGaugeCheckFailed(gauge); // MUTANT F-TF-LENGTH")],
        [("test_TF_CheckerReadFaultsFailClosed", "TF_EXACT_RETURN_LENGTH")]),
    "F-TF-BOOL": (CL, [("        if (verdict > 1) revert TrustedGaugeCheckFailed(gauge);\n", "")],
        [("test_TF_CheckerReadFaultsFailClosed", "TF_CANONICAL_BOOL")]),
    "F-TF-ARG": (CL, [("        _requireTrustedGauge(gauge);\n\n        // auditfix001",
        "        _requireTrustedGauge(pool); // MUTANT F-TF-ARG\n\n        // auditfix001")],
        [("test_TF_TrustedPaidAdmissionAndExactTarget", "TF_EXACT_GAUGE_ARGUMENT")]),
    "F-TF-SELECTOR": (CL, [("trustedGaugeValidator.staticcall(abi.encodeCall(ITrustedGaugeValidator.validateGauge, (gauge)));",
        "trustedGaugeValidator.staticcall(abi.encodeWithSelector(bytes4(0x2da285c4), uint256(uint160(gauge)))); // MUTANT F-TF-SELECTOR")],
        [("test_TF_TrustedPaidAdmissionAndExactTarget", "TF_EXACT_GAUGE_ARGUMENT")]),
    "F-TF-AFTER-ADD": (CL, [(ORDER_BLOCK, ""),
        ("        if (IListingController(controller).gauge_types(gauge) != derivedType) revert MembershipFailed();\n\n        emit GaugeListed(gauge, pool, msg.sender, derivedType, rec.listingEpoch, FEE, false);",
         "        if (IListingController(controller).gauge_types(gauge) != derivedType) revert MembershipFailed();\n        _requireTrustedGauge(gauge); // MUTANT F-TF-AFTER-ADD\n\n        emit GaugeListed(gauge, pool, msg.sender, derivedType, rec.listingEpoch, FEE, false);")],
        [("test_TF_UntrustedPaidAdmissionBeforeEffects", "TF_BEFORE_ADD_GAUGE")]),
    "F-TF-AFTER-FEE": (CL, [(ORDER_BLOCK, ""),
        ("        IListingController(controller).add_gauge(gauge, derivedType, INITIAL_WEIGHT);",
         "        _requireTrustedGauge(gauge); // MUTANT F-TF-AFTER-FEE\n        IListingController(controller).add_gauge(gauge, derivedType, INITIAL_WEIGHT);")],
        [("test_TF_UntrustedPaidAdmissionBeforeEffects", "TF_BEFORE_TRANSFER")]),
    "F-TF-AFTER-READY": (CL, [(ORDER_BLOCK, ""),
        ("        _requirePlatformsReady(plat);",
         "        _requirePlatformsReady(plat);\n        _requireTrustedGauge(gauge); // MUTANT F-TF-AFTER-READY")],
        [("test_TF_UntrustedPaidAdmissionBeforeEffects", "TF_BEFORE_READINESS")]),
    "F-TF-REGISTRY": (CL, [(ORDER_BLOCK, ""),
        ("        (address lpToken, int128 derivedType) = _admit(pool, gauge, gaugeIndex, handlerId, cfg);\n\n        // auditfix001",
         "        _requireTrustedGauge(gauge); // MUTANT F-TF-REGISTRY\n        (address lpToken, int128 derivedType) = _admit(pool, gauge, gaugeIndex, handlerId, cfg);\n\n        // auditfix001")],
        [("test_TF_RegistryAuthenticationPrecedesTrust", "TF_REGISTRY_FIRST")]),
    "F-TF-OWNER": (CL, [("        _requireTrustedGauge(gauge);\n\n        // auditfix001",
        "        if (msg.sender != owner) _requireTrustedGauge(gauge); // MUTANT F-TF-OWNER\n\n        // auditfix001")],
        [("test_TF_UntrustedPaidAdmissionBeforeEffects", "TF_OWNER_PAID_NOT_EXEMPT")]),
    "F-TF-FREE": (CL, [("        if (msg.sender != owner) revert NotOwner();\n        AdmissionConfig memory cfg = _admissionConfig;\n        (address lpToken, int128 derivedType) = _admit(pool, gauge, gaugeIndex, handlerId, cfg);",
        "        if (msg.sender != owner) revert NotOwner();\n        AdmissionConfig memory cfg = _admissionConfig;\n        (address lpToken, int128 derivedType) = _admit(pool, gauge, gaugeIndex, handlerId, cfg);\n        _requireTrustedGauge(gauge); // MUTANT F-TF-FREE")],
        [("test_TF_DaoFreeLaneIsTrustIndependent", "TF_DAO_NO_CHECKER_DEPENDENCE")]),
    "F-TF-RETRO": (CL, [("        if (st != Status.Active) return (0, 0);\n",
        "        if (st != Status.Active) return (0, 0);\n        _requireTrustedGauge(gauge); // MUTANT F-TF-RETRO\n")],
        [("test_TF_TrustIsAdmissionOnly", "TF_NO_RETROACTIVE_DRIP_GATE")]),
    "F-TF-RECORD": (CL, [("        rec.votium = plat.votium;\n", "")],
        [("test_TF_TrustedPaidAdmissionAndExactTarget", "TF_TRUSTED_PAID_ACTIVE")]),
    "F-TF-FREE-EVENT": (CL, [("        emit GaugeListed(gauge, pool, address(0), derivedType, rec.listingEpoch, 0, true);\n", "")],
        [("test_TF_DaoFreeLaneIsTrustIndependent", "TF_DAO_NO_FACTORY_ALLOWED")]),
    "F-NB-SPLIT": (CL, [("        SafeToken.safeTransfer(crvUSD, fd, amount);",
        "        SafeToken.safeTransfer(crvUSD, fd, amount / 2); // MUTANT F-NB-SPLIT")],
        [("test_KillAtEachReleaseCount", "ConfiscationDeltaMismatch")]),
    "F-NB-WEIGHT": (CL, [("        return ICurveGauge(gauge).is_killed();",
        "        return ICurveGauge(gauge).is_killed() || IListingController(controller).get_gauge_weight(gauge) == 0; // MUTANT F-NB-WEIGHT")],
        [("test_WeightZeroWithoutKilledFlagDoesNotConfiscate", "CannotCheckpoint")]),
    "F-NB-HORIZON": (CL, [("        if (block.timestamp - epochStart(t) > 20 * WEEK) revert DistributorUnusable();",
        "        if (block.timestamp - t > 20 * WEEK) revert DistributorUnusable(); // MUTANT F-NB-HORIZON")],
        [("test_AuditM01_AccountingHorizonIncludesPartialWeekEdges", "did not revert")]),
    "F-NB-ACCOUNT": (CL, [(
        "        IFeeDistributor(fd).checkpoint_token();\n"
        "        if (IFeeDistributor(fd).last_token_time() != block.timestamp) revert DistributorUnusable();\n"
        "        if (IFeeDistributor(fd).token_last_balance() != IERC20Minimal(crvUSD).balanceOf(fd)) {\n"
        "            revert DistributorUnusable();\n"
        "        }\n",
        "        try IFeeDistributor(fd).checkpoint_token() {} catch {} // MUTANT F-NB-ACCOUNT\n")],
        [("test_CheckpointCooldownRevertsConfiscationUntilAccountingEligible", "did not revert"),
         ("test_AuditM01_MidCatchUpAccountingFailureRollsBackEarlierQuarter", "did not revert")]),
    "F-NB-POST": (CL, [(
        "        if (IFeeDistributor(fd).token_last_balance() != IERC20Minimal(crvUSD).balanceOf(fd)) {\n"
        "            revert DistributorUnusable();\n"
        "        }\n", "")],
        [("test_AuditM01_InvalidCursorAndIncompleteCheckpointRevert", "did not revert")]),
    "F-NB-BIND-VOTIUM": (VA, [("    function setLister(address lister_) external onlyOwner {",
        "    function setLister(address lister_) external { // MUTANT F-NB-BIND-VOTIUM")],
        [("test_Adapter_VotiumNonListerAndBindingRejects", "did not revert")]),
    "F-NB-BIND-VOTEMARKET": (VMA, [("    function setLister(address lister_) external onlyOwner {",
        "    function setLister(address lister_) external { // MUTANT F-NB-BIND-VOTEMARKET")],
        [("test_AuditH01_VoteMarketCaptureCannotSpendEthFloat", "did not revert")]),
}

ROOT_DIR = WORK

def run(cmd, cwd, log):
    r = subprocess.run(cmd, shell=True, cwd=cwd, capture_output=True, text=True)
    open(log, "w").write("$ " + cmd + "\n\n" + r.stdout + "\n--stderr--\n" + r.stderr)
    return r.returncode, r.stdout

def make_copy(tag):
    d = os.path.join(WORK, tag)
    if os.path.exists(d):
        shutil.rmtree(d)
    shutil.copytree(CAND, d, ignore=shutil.ignore_patterns("out", "cache", "out-fork", "cache-fork", ".git", "gates-out"))
    return d

def main():
    only = sys.argv[1:] or list(MUTANTS)
    os.makedirs(WORK, exist_ok=True)
    results = []
    for mid in only:
        rel, edits, wants = MUTANTS[mid]
        d = make_copy("copy")
        files = {}
        for f in {rel}:
            files[f] = open(os.path.join(d, f)).read()
        # pristine green for every required identity
        pg_all, sel_lines = True, []
        for testname, label in wants:
            rc, out = run(f"forge test --offline --match-test '^{testname}\\(\\)$' 2>&1", d, os.path.join(ROOT_DIR, f"{mid}.{testname}.pristine.log"))
            ok = (f"[PASS] {testname}()" in out) and rc == 0 and ("Ran 1 test for" in out)
            pg_all &= ok
            sel_lines.append((testname, out.splitlines()[2] if len(out.splitlines()) > 2 else "?"))
        mutated = files[rel]
        try:
            for old, new in edits:
                mutated = sub(mutated, old, new)
        except AssertionError as e:
            results.append((mid, "MUTATION-PATCH-FAIL", str(e)))
            print(mid, "MUTATION-PATCH-FAIL", e, flush=True)
            continue
        assert mutated != files[rel]
        open(os.path.join(ROOT_DIR, f"{mid}.patch.txt"), "w").write(
            f"file: {rel}\n\n" + "\n\n".join(f"OLD:\n{o}\nNEW:\n{n}" for o, n in edits) + "\n")
        open(os.path.join(d, rel), "w").write(mutated)
        red_all = True
        for testname, label in wants:
            rc2, out2 = run(f"forge test --offline --match-test '^{testname}\\(\\)$' -vv 2>&1", d, os.path.join(ROOT_DIR, f"{mid}.{testname}.red.log"))
            red = ("[FAIL" in out2) and ("Suite result: FAILED" in out2) and (label in out2) and rc2 != 0 and ("Ran 1 test for" in out2)
            red_all &= red
        # restored green
        open(os.path.join(d, rel), "w").write(files[rel])
        rg_all = True
        for testname, label in wants:
            rc3, out3 = run(f"forge test --offline --match-test '^{testname}\\(\\)$' 2>&1", d, os.path.join(ROOT_DIR, f"{mid}.{testname}.restored.log"))
            rg_all &= (f"[PASS] {testname}()" in out3) and rc3 == 0
        status = "OK" if (pg_all and red_all and rg_all) else "FAIL"
        results.append((mid, status, f"pristine_green={pg_all} mutant_red={red_all} restored_green={rg_all}"))
        print(f"{mid}: {status} | {results[-1][2]}", flush=True)
    print(json.dumps([list(r) for r in results], indent=1))
    sys.exit(1 if any(r[1] != "OK" for r in results) else 0)

if __name__ == "__main__":
    main()
