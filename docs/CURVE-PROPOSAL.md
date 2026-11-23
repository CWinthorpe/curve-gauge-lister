# Proposal: Fee-Gated Automatic Gauge Registration

## Simple Summary

Add a paid route for registry-authenticated Curve gauges to register with the GaugeController after trusted-factory validation, without a separate per-gauge approval vote. The fee is 10,000 crvUSD and funds four weekly tranches of vote incentives for that gauge. All amounts here are gross escrow expenditure: at the independently observed pinned Votium venue, net reward plus the current platform fee equals gross, and no fixed future fee, net reward or vote count is promised. Registration starts at raw weight zero and does not award emissions; veCRV voters retain that choice.

The DAO handles monitoring, review and kills through its existing authorized processes. When a still-Active listing's gauge's own `is_killed()` flag is observed true, its entire still-unreleased escrow is confiscated to the pinned crvUSD FeeDistributor for distribution under its normal rules — conditional on the exact transfer and the mandatory safe same-transaction FeeDistributor accounting succeeding; if that cannot complete, the transaction reverts and the escrow stays retained. A kill cleared before observation is not reconstructed, and a successful confiscation stays terminal. There is no payment to a reporter, payer or deployer. This is an additional admission route, not a retirement of existing governance or seated-wrapper routes.

## How it works

1. **Paid listing.** `CurveGaugeLister.listGauge` authenticates the pool/gauge/LP relationship and structural eligibility through the configured registry. It then calls `validateGauge(gauge)` on the constructor-pinned validator `0x888888c34a46d0b2A34e9204e5273208E670e784`. Only a successful, exact 32-byte canonical true result passes. A named factory alone is insufficient: the external validator applies its configured reciprocal factory/module proof, including supported distinct-LP legacy routes. Failure rejects before fee transfer or controller addition. The owner has no paid-lane exception.
2. **Escrow and incentives.** Exactly 10,000 crvUSD is held in the lister, with 2,500 crvUSD maturing at each of the four following Thursday weekly boundaries. Anyone may checkpoint. Each listing snapshots its Votium/VoteMarket endpoints and split; later owner configuration cannot redirect it. Every funded quarter requires exact custody movement and receipts. Funding amounts are gross escrow expenditure, not net venue rewards: the independently observed net reward plus the current platform fee equals gross at the pinned Votium venue. A late tranche uses current venue timing, not retroactive votes. VoteMarket funding is asynchronous L1-to-L2 ingress.
3. **Kill and confiscation.** Gauge kills remain external DAO/gauge-administrator actions; this lister cannot kill a gauge. Its only settlement oracle is the current gauge `is_killed()` flag, never controller weight or a report. Anyone may settle a killed Active listing. Its whole unspent remainder goes directly to crvUSD FeeDistributor `0xD16d5eC345Dd86Fb63C6a9C43c517210F1027914`, conditional on mandatory safe accounting in the same transaction. If that cannot complete, the transaction reverts and the escrow remains reserved. No early-kill refund or alternative recipient exists.
4. **DAO lane and administration.** The owner-only `listGaugeNoEscrow` lane charges no fee, creates no escrow, and does not query the trusted validator. It retains registry/structural/controller checks, so otherwise valid non-factory gauges remain eligible through DAO action. Pausing affects only new paid listings. Ownership is two-step; the intended owner is the CurveDAO Aragon org. No withdrawal, rescue, sweep, arbitrary execution or escrow-migration authority is added.

A live listing completes after four successfully funded quarters. Previously funded venue amounts are expenditure, not recoverable escrow.

## Motivation

Separate registration eligibility from emissions preference. The paid route replaces the per-gauge approval step only for candidates satisfying the defined admission checks; it does not replace veCRV voting or promise liquidity, votes, yield or a launch-to-emissions timetable.

Each successful paid listing pre-funds its initial vote-incentive budget. A later authorized kill forfeits the remaining budget to the FeeDistributor rather than returning it to the payer — that forfeiture is conditional: the listing must still be Active, the current `is_killed()` flag must be observed true, and the exact transfer plus mandatory safe same-transaction FeeDistributor accounting must succeed, otherwise the transaction reverts and the escrow is retained. Forfeited amounts are gross escrow expenditure; no net venue reward or completion time is promised. Protective governance remains a DAO responsibility, without a separate reporting or reward protocol.

## Specification and rollout conditions

- The shipping contracts are the amended `CurveGaugeLister`, `VotiumAdapter` and `VoteMarketAdapter`, deployed from an exact reviewed release commit, not a moving branch name.
- Core constructor order is `(owner_, crvUSD_, controller_, feeDistributor_, admission_, platforms_, trustedGaugeValidator_)`. The validator is the seventh argument, explicitly supplied, immutable and without a setter/default. Chain 1 is mandatory; the core starts paused.
- Intended lister owner: CurveDAO Aragon org `0x40907540d8a6C65c637785e8f8B742ae6b0b9968`. Fee token: crvUSD `0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E`. Confiscation destination and validator are the pins above. Constructor code checks do not authenticate a supplied address; deployment must verify all pins and mutable upstream policy.
- Fixed economics: fee 10,000 crvUSD, four tranches of 2,500 crvUSD, paid initial controller weight zero, and 100% of unreleased escrow to the FeeDistributor on observed flag-true confiscation.
- Complete owner-authenticated, write-once adapter binding and actual upstream permission for the lister's `add_gauge` call before opening admission. The fork suite's impersonated controller-admin transfer is not a production GaugeAdder integration or an authorization receipt.
- Reverify current validator policy, registry associations, venue token acceptance/timing, destination VoteMarket requirements, bridge delivery and ETH float. Prove FeeDistributor public-checkpoint availability and safe accounting. Existing routes remain available on their existing terms.

## Limits and disclosures

- The immutable validator address has mutable upstream owner/manager-controlled policies. It authenticates the configured proof, not pool safety, economic quality or an independent deployment trace. Revocation/fault stops new paid admission, not settlement of already-admitted escrow.
- Kill authority is gauge-specific. Admission does not grant it to the payer or lister and does not verify every gauge's governance route. The DAO must verify and use the real authorized route. A kill cleared before the lister observes it leaves no historical kill proof here.
- FeeDistributor settlement requires a fresh bounded-allocation cursor and successful atomic accounting. Its public checkpoint cooldown is strict and shared; third parties can repeatedly delay settlement. Funds remain in escrow on failure, with no guaranteed completion time or recipient substitution. A standalone checkpoint is not a repair for already omitted stale allocations.
- Either venue's failure rolls back the whole checkpoint. An immutable broken venue can strand ordinary releases indefinitely; new defaults do not repair old snapshots. A legitimate gauge kill can use the separate venue-free confiscation path, still subject to FeeDistributor accounting.
- VoteMarket L1 ingress does not establish destination campaign delivery. Unused destination rewards have no ordinary project-controlled recovery API and may equal the whole campaign funding. They do not return to listing escrow or necessarily reach Curve's FeeDistributor. See the operations reference.

## Review boundary and references

Not deployed. The v1align authority review defines the no-bounty source amendment and the release gates; implementation acceptance must bind the actual release commit and fresh test/ABI/size receipts. Earlier reviews and test totals apply to their original candidates only. The previous product/proposal is preserved at `e18bee54c08832dd7fd6d0a11932290155bf9178` for the public audit trail.

- Repository: https://github.com/CWinthorpe/curve-gauge-lister
- Authority, gates and the exact ABI manifest: the candidate-bound release evidence package (normative plan, ABI/layout manifest, witness inventory, dependency and acceptance receipts), held by the project owner and producible on demand
- Interface reference: `ABI.md`
- Operations and limits: `OPERATIONS.md`
- Deployment pins and re-verification: `DEPLOYMENT-PINS.md`
