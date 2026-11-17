# Proposal: Fee-Gated Automatic Gauge Registration with a Kill-Report Bounty

## Simple Summary

Add a contract system that registers Curve gauges with the GaugeController after registry authentication and trusted-factory validation, on payment of a 10,000 crvUSD fee, removing the per-gauge approval step that sits between an eligible pool and the emissions vote. This is an additional route, not a replacement: existing seated wrappers keep adding gauges through their own processes, and any member can still win a gauge through a normal governance vote. The fee funds the new gauge's first four weeks in the emissions vote markets. If a listed gauge is later killed by the DAO, the unspent fee is confiscated: half pays the independent reporter who flagged it, the rest goes to veCRV holders through the crvUSD FeeDistributor. The DAO owns the contracts; the deployer holds no keys and receives no funds.

## How the system works

Background in two sentences. On Curve, creating a gauge contract for your own pool is already open to anyone; the gauge only earns CRV, though, once the GaugeController registers it, and registration is restricted to seated wrappers whose requests today go through a manual review cycle. veCRV holders then vote weekly on which registered gauges actually receive emissions.

The system:

1. **Listing.** Paid V2 registration costs 10,000 crvUSD and requires a registry-authenticated pool/gauge followed by a true `validateGauge(gauge)` result from constructor-pinned GaugeValidator `0x888888c34a46d0b2A34e9204e5273208E670e784`. The validator checks the candidate against its named factory's configured reciprocal proof, including supported legacy LP-to-pool paths; a factory name alone is not enough. A negative result or failed/malformed read reverts before fee transfer or `add_gauge`. The DAO's owner-only `listGaugeNoEscrow` path remains exempt from factory validation, allowing otherwise valid non-factory gauges without escrow or bounty. Frozen V1 is unchanged and does not provide this new paid guarantee. Successful paid registration occurs atomically through the DAO-seated wrapper at raw weight zero; emissions remain solely the weekly veCRV vote's choice.
2. **Fee escrow.** The 10,000 crvUSD is not paid to anyone. It remains in the contract and releases 2,500 crvUSD at each of the four following weekly epoch boundaries, split between Votium and VoteMarket, the two platforms where gauges fund votes. Each payment buys the new gauge exposure in that week's emissions vote.
3. **Kill and confiscation.** If the DAO kills the gauge (the contract reads only the gauge's own `is_killed()` flag), any caller can trigger settlement. All unspent escrow leaves the contract permanently.
4. **The bounty.** A watcher who identifies a bad gauge files a standard Curve ownership proposal to kill it, in which the proposal's own payload names the watcher as the reward beneficiary. They register that proposal with this contract and post a 1,000 crvUSD stake. The contract checks the proposal's exact payload bytes against the expected form for that report, gauge and beneficiary before admitting it.
   - Kill passes and executes: the reporter receives half of the unspent escrow; the FeeDistributor receives the other half.
   - Kill fails to pass, or another report wins first: the stake is fully refunded.
   - The DAO rules the report frivolous: the stake is forfeited to the FeeDistributor.

   A false report therefore risks a real 1,000 crvUSD, and reporting early is worth money.
5. **Ownership.** All administrative functions (pausing new listings, configuration, ownership transfer) belong to the CurveDAO Aragon org. The contracts contain no withdrawal, rescue or sweep function. Escrow funds can only reach the bribe platforms, the FeeDistributor, or a recognized reporter.

A listing that never goes bad simply spends its four weeks of vote funding and completes.

## Motivation

**The approval step, not the vote, is what we remove.** New protocols need a working gauge at launch, when liquidity either forms or does not. The review cycle in front of registration runs weekly, and a registered gauge then waits on the next weekly vote for its weight: two weeks to first emissions at best, three to four in practice given vote timing and the big voters' cycles. That gap costs the new pool and Curve's competitiveness for that liquidity. Registry-authenticated pools that pass the contract's checks skip it. Every judgment about which gauges deserve emissions stays with veCRV voters, and new gauges enter at weight zero with no emissions claim.

**Voting gets paid more, more often.** Each paid listing injects 10,000 crvUSD into Votium and VoteMarket over its gauge's first month. That money goes to the veCRV holders who vote on the new gauge. Gauge voting becomes a more consistent source of fees for voters, and protocols get a standard, automated way to fund their launch-month campaign instead of negotiating it separately.

**Continuous review of new listings.** New pools concentrate risk on Curve: dishonest admin rights, exploitable contracts, abandoned liquidity. There is currently no reward for noticing these early, so review tends to happen after the damage. The bounty assigns a price to being first: half of the killed listing's own unspent escrow. The 1,000 crvUSD stake makes junk reports expensive, and honest losing reports are refunded, so only bad-faith claims lose money.

**Protocol security with pre-funded consequences.** Today a dishonest listing that runs for weeks before a kill burns emissions and trust while nobody profits from its removal. Under this system a malicious listing locks 10,000 crvUSD upfront, and whatever was not spent on vote incentives is split between the reporter who ended it and the veCRV holders who bear the cost of bad listings. An attacker funds the reward for their own exposure.

## Specification

- Deploy the amended `CurveGaugeListerV2`, `GaugeBounty`, `VotiumAdapter` and `VoteMarketAdapter` from the current main commit of `github.com/CWinthorpe/curve-gauge-lister`. Do not deploy or seat frozen `CurveGaugeLister` (V1) as a paid lane satisfying this requirement. Constructor wiring includes:
  - owner: CurveDAO Aragon org `0x40907540d8a6C65c637785e8f8B742ae6b0b9968`
  - confiscation destination: crvUSD FeeDistributor `0xD16d5eC345Dd86Fb63C6a9C43c517210F1027914`
  - V2 `trustedGaugeValidator_`: `0x888888c34a46d0b2A34e9204e5273208E670e784`, explicitly supplied as the eighth constructor argument after `bounty_`, with chain-1 and code-presence guards; no hardcoded default or setter.
- Seat the system's wrapper in GaugeAdder through the standard wrapper process so the lister may call `add_gauge` at raw weight zero.
- Fixed parameters: listing fee 10,000 crvUSD; four weekly tranches of 2,500 crvUSD; reporter stake 1,000 crvUSD; reporter reward floor(unspent escrow / 2), remainder to the FeeDistributor; kill detection solely the gauge `is_killed()` flag.
- The DAO keeps a free registration path (`listGaugeNoEscrow`) exempt from the trusted-factory check, while retaining registry authentication, owner authorization and structural checks. Its listings create no escrow and no bounty.
- No existing route is retired. Every seated wrapper continues to register gauges on its own review terms, and gauges can still be proposed to the DAO for direct addition by vote. The paid path is strictly one more door.

## Known limits

- The validator address is immutable in V2, but the validator's owner or appointed managers can change trusted factories and validation modules. Admission uses their current policy, not an independent creation-trace proof or an audit of pool safety. Policy revocation or checker failure blocks new paid admissions; it does not add a trust condition to existing escrow settlement. The DAO-free lane remains available subject to its original checks.
- Confiscated payouts can be delayed, never redirected or lost, when the crvUSD FeeDistributor is stale or third-party calls advance its shared accounting cursor past the amount owed. Disclosed in `docs/BOUNTY-OPERATIONS.md`.
- Two governance-approved proposals can contain identical kill payloads. If an unregistered duplicate executes first, the matching pending report closes without paying its reporter half; the stake is still refunded and the escrow still reaches the FeeDistributor. Requires a real second approved ballot; disclosed and reasoned in `docs/BOUNTY-OPERATIONS.md`.

## Development and review record

The base system (`74e536f`) passed 190 offline and 20 fork tests and completed three bounded conformance rounds, a lean code audit and two independent rounds of blind adversarial security review, with no outstanding Critical or High findings. The trusted-factory amendment adds eight offline and two fork tests (198/22 total, including real SS-ng and distinct-LP legacy factory admissions) and carries its own conformance review; it is not a fresh whole-system audit. The retained accepted risks keep their original rulings.

## Reference

- Repository: https://github.com/CWinthorpe/curve-gauge-lister (pre-amendment baseline: `74e536f`)
- Operations and disclosures: `docs/BOUNTY-OPERATIONS.md`
- Interface reference: `docs/BOUNTY-ABI.md`
- Deployment pins and re-verification recipe: `docs/DEPLOYMENT-PINS.md`
