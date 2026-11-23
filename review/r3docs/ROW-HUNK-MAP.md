# r3docs — admitted row → hunk map (git diff 62c8326..a9de6ff, -U0 inventory)

Authority: `review/r3gate/RULING.md` + `BINDING.json`; work order
`plans/R3GATE-WORK-ORDER.md`. Only ADOPT rows are implemented: C03 (P0
public wording + final-candidate index refresh), C05, C07, C13, C15. All
hunks below are COMMENTS/PROSE ONLY; the token-level freeze evidence is in
BYTECODE-PROOF.md and artifacts/compare-final.txt. DEFERRED (C01/C02/C04)
and REJECTED (C06/C08-C12/C14/C16) proposals were not touched — no
receipt-representation change (C06), no gas-tuple refactor (C08), no
inlining of the predicate (C09) or maintenance helper (C12), no kill-read
reordering (C10), no parser replacement (C11), no zero-address line
deletion (C14), no interface relocation (C16), no census/inventory change
(C04), no FD/controller rewrite (C01/C02).

| File | Hunk (new-side) | Row | Change |
| --- | --- | --- | --- |
| README.md | @@ -19,0 +20,2 (Status and evidence) | C03 | New paragraph: the selectively published in-tree authority rulings (review/r3gate/, review/simplify2/ carriers, review/r3docs/ receipts) are a partial view, not the owner-held package; public path is not approval; ACTIVATION-OPEN obligations unchanged. |
| README.md | @@ -31 +33 (Layout tail) | C03 | Same section's closing sentence now distinguishes selective publication from the complete owner-held release evidence package. |
| contracts/adapters/VoteMarketAdapter.sol | @@ -15,8 +15,9 (header @notice) | C05 | "One deposit creates exactly one gauge-bound campaign" → one funded gauge-bound L1 REQUEST SUBMISSION toward the CampaignRemoteManager; not itself a created campaign. |
| contracts/adapters/VoteMarketAdapter.sol | @@ -28 +29,3 (header @dev) | C05 | Custody claim now: exact adapter-side pull credit + return to pre-deposit balance; explicitly not a separately measured recipient credit. |
| contracts/adapters/VoteMarketAdapter.sol | @@ -221,3 +224,6 (deposit baseline comment) | C05 | Balance-baseline observation wording; removed "reached the CampaignRemoteManager" recipient-credit overclaim; retains shared-predicate/CX-ADAPTER attribution. |
| contracts/adapters/VotiumAdapter.sol | @@ -35,2 +35,6 (header @dev) | C05 | Same observation boundary; no promise that every gross unit became a net venue reward (venue fee/net split evidenced in fork suite). |
| contracts/adapters/VotiumAdapter.sol | @@ -161,3 +165,7 (deposit baseline comment) | C05 | Balance-baseline observation; not recipient-credit measurement; not a gross-equals-net promise. |
| contracts/interfaces/ICampaignRemoteManager.sol | @@ -30 +30,4 (createCampaign @notice) | C05 | "Fund and register an L2 campaign" → submit funded ingress toward L2; registration/acceptance/funding are destination-side facts, not established by call success. |
| contracts/libraries/SafeToken.sol | @@ -5,3 +5,7 (contract @notice) | C13 | Diagnostic contract corrected: empty/canonical-true accepted; false or nonempty wrong-length → SafeTokenBadReturn; length-32 noncanonical Boolean can revert inside abi.decode first; failed low-level calls WRAPPED in SafeTokenCallFailed (no byte bubbling). |
| contracts/libraries/SafeToken.sol | @@ -17 +21,2 (CallFailed @dev) | C13 | Wrapped-failure statement. |
| contracts/libraries/SafeToken.sol | @@ -20 +25,4 (BadReturn @dev) | C13 | False/wrong-length vs decoder-revert boundary. |
| docs/ABI.md | @@ -45,0 +46,2 (Views) | C15 | releasable = status/flag-conditioned gross matured-unpaid projection, not a funded execution quote; remaining = Active unreleased liability; totalEscrow = aggregate paid Active liability, not surplus/executability; epochsElapsed = capped age, not funded count. |
| docs/ABI.md | @@ -66,0 +69,2 (Events tail para) | C15 | PlatformDeposit/QuarterReleased amounts are gross escrow expenditure; Votium net+fee=gross at pinned venue; no fixed-fee/net/vote promises; VoteMarket deposit = funded L1 ingress. |
| docs/ABI.md | @@ -80,0 +85,9 (Shared errors) | C13 | Shared-token-error explanation at the existing section only. |
| docs/CURVE-PROPOSAL.md | @@ -5 +5 (Simple Summary) | C15 | Fee/tranche sentence qualified: gross escrow expenditure; pinned-Votium net+fee=gross observation; no fixed future fee/net reward/vote count promised. |
| docs/CURVE-PROPOSAL.md | @@ -7 +7 (Simple Summary) | C15 | Forfeiture qualified: still-Active listing, flag OBSERVED true, exact transfer + mandatory safe same-transaction FD accounting; revert retains escrow; cleared-unobserved kill not reconstructed; successful confiscation terminal. |
| docs/CURVE-PROPOSAL.md | @@ -12 +12 (How it works 2) | C15 | Funding amounts gross, not net venue rewards. |
| docs/CURVE-PROPOSAL.md | @@ -22 +22 (Motivation) | C15 | Forfeiture claim carries the same Active/observed/accounting conditions and gross scope; no completion-time or net-reward promise. |
| docs/OPERATIONS.md | @@ -37,0 +38,2 (Admission and ordinary settlement) | C15 | Gross-expenditure disclosure paragraph incl. PlatformDeposit/QuarterReleased naming and venue boundaries; existing approval/exact-amount/trust/delivery restrictions untouched. |
| docs/OPERATIONS.md | @@ -71,0 +74,13 (Adapter arithmetic) | C05 | Custody/attestation observation boundary: core = exact source debit + nonzero adapter attestation; adapters = exact pull credit + baseline return; destination facts from pinned ingress + independent venue evidence; FD path is the two-sided check; receipt meaning stays at IIncentivePlatform.deposit. |
| test/fork/ForkFixture.sol | @@ -1019,10 +1019,15 (_assertApprovalTrace @dev) | C07 | Token/owner/spender-scoped MULTISET over the observed log batch: exact exhaustion/multiplicity, permutations accepted, arrays are expected members not a temporal oracle; scope filter (CRVUSD emitter, three-topic Approval shape, pair, 32-byte data) named; helper/assertions/expected values unchanged. |
| test/fork/ForkFixture.sol | @@ -1119 +1124,2 and @@ -1121,16 +1127,20 (_assertVotiumLegEvents @dev) | C07 | Same multiset framing; "lifecycle as a complete trace" corrected to multiset members; repeated deposits not independently lifecycle-ordered by this matcher; gross-fee member and all values/transfers/allowances preserved exactly. |
| test/fork/ForkVoteMarket.t.sol | @@ -107,4 +107,9 (_assertCustodyChain comment) | C07 | Multiset framing for the two bounded pairs; expected-member lists keep their values; no new assertions, helpers or renames. |

Commit custody: P1 (C05/C07/C13) = `340db1d40882f4a3a8432e9bc0e5505023faf99d`;
P2+P0 (C15/C03 docs) = `a9de6ffc99343801575b72a2be78ea83bd73508c`; receipts +
final-binding addendum land in the third r3docs commit. `git diff --check`
clean; `git status` clean at the bound candidate apart from this receipt
package.
