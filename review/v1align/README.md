# v1align — authority receipt index

Disposition: RELEASE IMPLEMENTATION; NOT DEPLOYMENT APPROVAL.

Reviewed product candidate: e18bee54c08832dd7fd6d0a11932290155bf9178. This authority commit changes only plans/ and review/. The source amendment, removals and exact public-document replacements are work orders, not already shipped changes.

## Ruling and deliverables

Amend never-deployed CurveGaugeLister in place; port immutable validator/paid-only trust, chain1 and paused startup. Keep the original all-FD monetary path, Listing/event/storage and shared hardening. Remove V2/GaugeBounty and exclusive dependencies/tests from the shipping tree, not an executable optional quarantine. The reviewed baseline commit preserves the public history.

- ../../plans/V1ALIGN-PLAN.md — product law, exact constructor, deletion authority, seven implementation gates and four numbered qwen packages, one commit each.
- ../../plans/V1ALIGN-MANIFEST.json — full normative target ABI/method identifiers, original recursive layout, shared source/runtime hashes and product disposition. Target, not fresh compiled implementation.
- ../../plans/V1ALIGN-WITNESSES.md — every surviving obligation, eight/two trust port rows and named behavioral/ABI falsifiers.
- ../../plans/V1ALIGN-WITNESS-INVENTORY.json — exhaustive native baseline identity dispositions and exact counterpart mapping; compiled signatures and escaped anchored regex are separate from Forge JSON's bare names.
- ../../plans/V1ALIGN-DOC-DELTAS.md — five complete verbatim public replacement files, two deleted old docs and one literal historical-intel amendment. documentation-replacements.json hashes the target payloads without applying them.
- DIFF.md, source-comparison.json, abi-delta.json — complete routine/declaration/composition classification, raw/token accounting comparisons and full compiler-ABI deltas.

## Observed evidence

- Both profile builds succeeded. build-default.txt/build-fork.txt retain native size tables and warnings. toolchain.json records actual compiler and resolved relevant config. baseline.json retains full ABI, method identifiers, layouts, decoded sizes/runtime hashes, source hashes and build/test argv/exits. No product compiler/profile change.
- test-default-unset.txt and test-default-unreachable.txt each contain198 PASS,0 fail,0 skip across15 suites, exactly matching list-default.txt.
- fork-cold.txt and fork-warm.txt each contain22 PASS,0 fail,0 skip across9 suites, exactly matching list-fork.txt. fork-status.json records isolated HOME, endpoint and exits; the unchanged wrapper verified chain/header before each test run. fork-unreachable.txt then failed closed with exit1 before any tests despite the warmed cache.
- authority-check.json re-decodes fresh compiler objects, verifies all84 collected product/test/doc/tooling file hashes unchanged, compares complete manifest derivation and exact native PASS signatures, checks all baseline product runtimes against24,576 and validates exact docs extraction. The expected no-bounty census77/13 is derived, NOT an executed target result.
- hardcoded-artifact-check.json closes the existing out/-path ambiguity in adapter ABI tests: their actual old artifact inputs match the fresh default ABI/method identifiers/runtime. Future acceptance must use a clean default out/ at the expected relative path instead.
- historical-source-check.json records six byte-identical current/historical-local sources, including V1's inline auditfix001 law and shared adapters. It does not presume the older local object is on public main history.
- fmt-check.txt is empty because forge fmt --check exited0; the exit is recorded in authority-check.json. The native compiler warnings are not suppressed or called warning-free. Review-local .gitattributes exempts only build-default.txt/build-fork.txt from Git whitespace checks, preserving their compiler-emitted caret padding and final blank lines byte-for-byte; no source, test, script or document receives that exemption.

Excluded tooling attempts are retained separately: fork-setup-attempt1.txt (wrong installed-solc directory assumption, before RPC/tests) and authority-check-attempt1.txt (bare test names versus compiled-signature parser mismatch). Neither is a product failure or waived gate.

## Reproduction and interpretation

The collectors are review tools, not shipping/deployment scripts. To reproduce, use an isolated checkout of the reviewed candidate, copy this authority's plans/ and review/v1align/ support files into that checkout without changing its product/HEAD, and use the recorded toolchain, an installed compiler and TMPDIR under suitable session scratch. Retain this committed evidence; write new run outputs in the isolated copy. Run collect_baseline.py, compare_sources.py, derive_manifest.py, collect_fork.py and check_authority.py in that order. collect_fork.py must use the actually installed compiler path for its host; the recorded path is Linux/XDG-specific. Both native build/test inventories and full execution logs are required. Baseline adapter tests expect out/ artifacts; create a fresh default out/ before those tests or preserve and perform the same full hardcoded-artifact equivalence check. Scratch compiler objects and RPC caches are deliberately not committed; their parsed receipts and hashes are. A public clone may lack historical local object74e536f; the checker labels that supplementary comparison NOT_REPRODUCED rather than pretending it reran. Current-candidate source/accounting/ABI/size and native-test checks remain mandatory and independent of that optional historical corroboration.

This review's bounded never-deployed recheck is README.md:44 ("Not yet deployed"), the operator statement, and tracked-tree inspection with no broadcast/deployments receipt or deployment script. It is not a chain-wide proof of nonexistence. Stop the source-amendment interpretation if any deployed instance/liability is discovered.

No implementation mutants, amended-core byte sizes, mainnet transactions, controller seating, ownership/binding handoffs or cross-chain delivery have been certified here. No private credentials were needed. Current pin/policy/venue checks and actual upstream authorization remain deployment gates.
