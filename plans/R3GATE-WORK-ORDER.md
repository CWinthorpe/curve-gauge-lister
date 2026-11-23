# r3gate — bounded builder work order

Authority: `review/r3gate/RULING.md`, against product `d88d633c64fde7b3f37e29d846f744747186a688`.
Status: RELEASED FOR THE ADMITTED DOCUMENTATION BRANCH ONLY; NOT DEPLOYMENT APPROVAL.

The fleet/verifier is not a work queue. Only ADOPT rows C03/C05/C07/C13/C15 are released here. C01/C02/C04 are deferred; C06/C08/C09/C10/C11/C12/C14/C16 are rejected for this engagement. No code cleanup may ride along with a comment correction. The authority leg itself edits only plans/review; the product-facing edits below belong to the subsequent builder, not r3gate.

## P0 — C03 authority repair and final binding

The authority leg delivers the corrected `review/simplify2/AUTH-EVIDENCE-INDEX.md`, the FD/controller status supplements and `review/r3gate/FORK-CLAUSE-RESOLUTION.md`. Do not recreate those artifacts. Current admission order is V1ALIGN-PLAN §2.1, specifically the paid-lane paragraph, not §1.3 or §2.2. Legacy fork clauses resolve through the explicit current resolution, not a missing checkout file or an unqualified old inventory/cooldown policy.

Builder remainder:

- In `README.md` Status/evidence and Layout wording only, distinguish these selectively published authority rulings from the complete owner-held candidate evidence package. Do not publish bulk manifests/receipts, remove owner control, or imply that a public path alone is approval.
- At the final shipped candidate, append the actual candidate, source/build/manifest/census receipt digests and owner approval status to the SAME current evidence index. Preserve previous candidate records as history. Approval absent means OPEN, never fill it from a successful test.
- Carry the structural future-engagement paragraph verbatim into the confirmation brief. Keep PAO-FD/CTL/AUTH tracking satisfaction distinct from activation closure; do not perform deployment certification in this documentation package.

P0 acceptance: every current admission/fork citation resolves; no existing historical source/receipt is rewritten as a new pass; owner-held full-package access remains available; final binding distinguishes facts produced by the builder from pending approval.

## P1 — C05, C07 and C13 claim-boundary corrections

Only the named comments/NatSpec and directly corresponding public prose may change.

C05 — custody and ingress:

- `contracts/adapters/VoteMarketAdapter.sol`: header at :13-35 and balance-baseline comment at :220-225. Replace “one deposit creates exactly one ... campaign” with one funded gauge-bound L1 request submission. Describe the observed exact adapter pull credit and return to its prior token balance, not a separately measured recipient credit.
- `contracts/adapters/VotiumAdapter.sol`: custody comments at :33-36 and :160-165. State the same observation boundary without promising every gross unit became net venue reward.
- `contracts/interfaces/ICampaignRemoteManager.sol`: `createCampaign` notice at :30-42. Submission is toward L2; L1 success is not L2 registration/acceptance/funding.
- `docs/OPERATIONS.md`: a short custody/attestation boundary at the existing venue/delivery sections. Core checks exact source debit plus nonzero adapter attestation; adapters check exact pull credit and net return to baseline; the pinned ingress plus independent venue evidence supplies destination facts. Contrast the FD path's actual two-sided debit/credit checks. Preserve all existing approval, exact-amount, trust and delivery restrictions. Keep common receipt meaning at `IIncentivePlatform.deposit`; do not create another receipt specification or edit its implementation/interface.

C07 — multiset evidence:

- `test/fork/ForkFixture.sol`: comments at :1019-1030 and :1116-1138.
- `test/fork/ForkVoteMarket.t.sol`: comments at :106-113.
- Describe a token/owner/spender-scoped multiset with exact exhaustion and multiplicity over the observed log batch. Permutations are accepted; repeated deposits are not independently lifecycle-ordered by this matcher. Values listed in arrays are expected members, not a temporal oracle.
- Retain `_assertApprovalTrace`, variable names, assertion strings, bitmap/nested search, every expected value and multiplicity, CRVUSD emitter/topic/data-length filtering, the Votium `gross-fee` member, independent transfer checks and final allowances EXACTLY. The current evidence index adopts the precise evidence name. No helper rename, cursor, new ordered assertion or new test is released. A sequencing gate needs separately observed pin behavior and authority.

C13 — token-return diagnostics:

- `contracts/libraries/SafeToken.sol`: notice and error comments at :5-9,17-21 only.
- `docs/ABI.md`: shared-token-error explanation at the existing Shared errors section only.
- Successful empty data or canonical true is accepted. False or nonempty wrong length reaches `SafeTokenBadReturn`; a length-32 noncanonical Boolean can revert during `abi.decode` before that custom error. Failed low-level calls use `SafeTokenCallFailed`, not a promise to bubble dependency revert bytes. Preserve the entire `_call` body, accepted set, diagnostics, code-presence check and zero-first/exact/clear approval behavior. Do not decode a uint word or normalize errors.

P1 acceptance: each new sentence matches the actual observation/branch; no executable token, literal (including diagnostic strings), declaration, import, path, function identity or assertion changes. NatSpec metadata/source hashes may change; disclose them, never claim byte-identical compiler metadata from a comment-only diff.

## P2 — C15 payer-facing monetary disclosure

Files: `docs/CURVE-PROPOSAL.md`, `docs/OPERATIONS.md`, `docs/ABI.md`, only the corresponding economic summaries/field explanations. Reuse existing sections rather than adding a parallel monetary model.

- Qualify forfeiture where claimed (proposal Simple Summary and Motivation): the listing must still be Active, the current flag must be observed true, and exact transfer plus safe same-transaction FD accounting must succeed; otherwise escrow is retained on revert. A cleared unobserved kill is not reconstructed; successful confiscation stays terminal.
- Fee/tranche/release amounts and `PlatformDeposit`/`QuarterReleased` amounts are GROSS escrow expenditure. Votium's independently observed net reward plus current platform fee equals gross at the pinned venue; no fixed future fee, universal net reward or guaranteed votes are promised. VoteMarket is funded L1 ingress, not L2 delivery.
- `releasable` is the current status/flag-conditioned gross matured-unpaid projection, not a funded execution/readiness quote. `remaining` is the Active unreleased liability; `totalEscrow` is the aggregate paid Active liability, not surplus or a guarantee of venue/FD executability. `epochsElapsed` is capped age, not funded count. Preserve every current field meaning and failure behavior.
- Keep fee=10,000 crvUSD, four quarters of 2,500, Thursday schedule, frozen split/endpoints, all-FD destination, no-refund/no-migration policy and independent venue/FD limitations. Do not introduce a new status, quote, recovery right or operator kill policy.

P2 acceptance: a payer can distinguish gross funding, venue net rewards, maturity, executability and conditional forfeiture at the initial claim; later limitations remain intact. No promise of a completion time or fee-free net rewards is added.

## Change allowlist and package discipline

Product-facing allowlist (comments/prose only):

- `README.md` — P0 evidence-publication boundary only.
- `contracts/adapters/VoteMarketAdapter.sol` — P1 comments named above.
- `contracts/adapters/VotiumAdapter.sol` — P1 comments named above.
- `contracts/interfaces/ICampaignRemoteManager.sol` — P1 notice only.
- `contracts/libraries/SafeToken.sol` — P1 notice/error comments only.
- `test/fork/ForkFixture.sol` — P1 multiset comments only.
- `test/fork/ForkVoteMarket.t.sol` — P1 multiset comments only.
- `docs/OPERATIONS.md`, `docs/ABI.md`, `docs/CURVE-PROPOSAL.md` — P1/P2 named prose only.

Owner-held new builder/confirmation receipts belong under a new `review/r3gate-implementation/` directory; update the current index by an explicitly identified final-binding addendum. Do not overwrite simplify2 raw logs, generators, manifests, witness inventory or historical approvals. No broad evidence publication is implied by this authority leg's narrow commit/push exception.

Make one P1 comment/boundary commit and one P2 payer-doc/P0-publication commit, each with a row-cited diff. Do not invent extra edits to reach a commit count. A purely overlapping prose change can be placed once with both row citations. No executable-core file edit, import relocation, helper removal/rename, test split/reorder, source formatting sweep, dependency/configuration change, pin change or product amendment is admitted.

## Census and behavior lock

`review/r3gate/BINDING.json` contains exact approved file:contract:signature sets: default 77, fork 13. Compare discovered AND executed sets, including paths and contracts, not just counts. Preserve the legacy `test/bountyfix02/AdapterConfig.t.sol:AdapterConfigR2Test` identities. Additions, removals, renames, duplicates, skips, concrete inherited-suite duplication or changes to the inventory are STOP conditions under this order. The older general ability to approve additional regressions is not such approval here.

Every test/helper executable token and every assertion remains identical to d88d633. Every product executable token, declaration, ABI, storage member/stride, error/event, call order and monetary expression remains identical. Preserve independent literal expectations; do not derive witness constants or formulas from production. VC-02 still proves offset-1 guard sensitivity only; no claim of later-cell execution follows from its aborted red. Neither this work order nor confirmation may enlarge that historical receipt.

## Gates

G0 — Base and scope (each package): bind the exact authority child of d88d633 and record working status; stop on unrelated product changes. Compare all unauthorized files byte-for-byte to d88d633. In allowed Solidity files use a string-aware lexer/token comparison that excludes comments and whitespace but retains string literals and token boundaries; a naive regex that strips comment-looking text inside a string is insufficient. There must be ZERO executable/declaration/import/test-literal token delta. Review the prose diff against P0–P2 and the sealed law.

G1 — Mechanical (each package): `git diff --check`, `forge fmt --check`, fresh `forge build --offline --sizes` and `FOUNDRY_PROFILE=fork forge build --offline --sizes`. Retain native outputs/exits and warnings; preserve Solidity 0.8.30, optimizer200, no viaIR, default Paris/fork Cancun-chain1. Build in an isolated exact candidate with fresh outputs; no toolchain/dependency edits or waiver.

G2 — Artifact/census (final package): compare full fresh ABI, methodIdentifiers and recursive storage layouts under BOTH profiles to the approved manifest and same-profile d88d633 baseline. No selector-count substitute. Record source/runtime hashes anew; comment metadata is not expected byte-identical. For the three product deployables, compare executable runtime bytecode separately from a validated Solidity metadata trailer, with the parsing method and raw bytes retained. Test contracts can embed creation-code metadata, so outer-trailer stripping alone is not a test-byte equivalence proof; their executable source tokens and assertions are frozen by G0. Require each product deployed runtime <=24,576 decoded bytes, and retain the constructor/initcode check. Discovered native full-signature inventories must equal BINDING.json, exactly 77/13. The ABI allowlist test must read this fresh default `out/`, never a stale artifact from another tree.

G3 — Offline (final package): run the complete default suite with MAINNET_RPC_URL unset and again with `MAINNET_RPC_URL=http://127.0.0.1:1`; record native PASS identities equal to discovered identities, zero failures/skips in both runs. These are two executions of the same identities, not an increased census. No new mutation battery is required for a proven comment-only change; carry existing accepted sensitivities with their original scope.

G4 — Pinned fork (final package, once): all 13 identities through `scripts/test-fork.sh`, no filters, unchanged chain1/block26401019/hash0x55810b079923a14fb97ad548f5024f65530dbc4fb2357a38f41e13b3d27cb6d3/timestamp1794512471. Record cache mode honestly; this bounded comment-only confirmation does not claim a new cold/warm qualification. Historical cold/warm/preflight evidence stays historical. No repin, mocks, etch/store, skipped live positives, changed expectations or transport-green. BLOCKED: RPC is a HOLD for this required final gate, not grounds to fabricate results. Capture the native exit and actual PASS set.

G5 — One independent confirmation pass: inspect only P0–P2 delivery, the admitted row mapping, G0–G4 receipts and current obligation statuses. Verify exact candidate/source/hash custody and compare the prose to actual code/observations. It may reproduce existing gates or produce the final G4 receipt on the exact shipped candidate; the builder and confirmer need not duplicate the same final fork run merely to create two receipts. No new simplification hunt, arbitrary sensitivity expansion or confirmation-by-count. If the allowed edits and all gates pass, state LEAN CONVERGED — ACTIVATION OBLIGATIONS OPEN. If a gate fails, name that bounded failure; no automatic full blind round.

No builder completion marker or green gate authorizes deployment. The FD/controller certificates, final owner evidence approval and all other deployment gates remain outside this order.
