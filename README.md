# Curve Gauge Lister

A fee-gated system for registering Curve gauges for emissions without a
per-gauge approval vote, plus a bounty that pays independent watchers for
flagging bad gauges. The DAO owns everything; the deployer keeps no keys and
receives no funds.

## The gap this fills

Deploying a gauge contract for your own pool is already permissionless on
Curve. What is gated is the next step: registering that gauge with the
GaugeController, without which the gauge can never earn CRV emissions.
Registration is only available to seated wrappers, which today approve
requests on a weekly review cycle, and a registered gauge must then wait for
a veCRV vote to earn anything. Best case that is two weeks from launch — one
to be added, one until the next vote can weight it — and in practice vote
timing and the big voters' cycles push it to three or four. New protocols
therefore launch with a gauge that exists but cannot earn, and nobody is
paid to notice when a newly listed pool turns out dishonest or dead.

## What it does

- **Trusted-factory paid registration (V2).** Anyone may pay 10,000 crvUSD to register a registry-authenticated Curve pool/gauge only when the constructor-pinned GaugeValidator at `0x888888c34a46d0b2A34e9204e5273208E670e784` returns true from `validateGauge(gauge)`. Registry checks run first; factory-policy validation runs before any fee transfer or controller addition, and rejection or a failed/malformed read reverts the listing. The validator checks the gauge against its named factory's configured reciprocal proof; its owner or appointed managers can change those policies. The DAO's `listGaugeNoEscrow` lane is exempt, so otherwise valid non-factory gauges can still be DAO-listed. This guarantee is V2-only; frozen V1 is unchanged. Successful paid registration starts at raw weight zero and grants no emissions without veCRV votes.
- **The fee funds the gauge's own vote campaign.** The fee stays in escrow
  and releases 2,500 crvUSD per week for four weeks into Votium and
  VoteMarket — the platforms where gauges buy emissions votes — split as
  configured. New listings arrive already paying the voters.
- **Kill confiscation.** If the DAO kills the gauge (its `is_killed()` flag
  is the only signal the contract reads), all unspent escrow is confiscated
  to the crvUSD FeeDistributor for veCRV holders.
- **Reporter bounty.** A watcher who files the winning kill proposal — a
  Curve ownership ballot whose payload names them as beneficiary — and
  registers it with a 1,000 crvUSD stake receives half the confiscated
  remainder. Honest losing reports are fully refunded; the stake is
  forfeited only when the DAO explicitly rules a report frivolous.
- **DAO-owned lister.** Every lister admin function belongs to the CurveDAO Aragon org.
  There are no withdrawals, rescues or sweeps; escrow can only reach the
  bribe venues, the FeeDistributor, or a recognized reporter. The DAO may
  also register gauges for free (`listGaugeNoEscrow`), creating no escrow
  and no bounty.

## Status

Not yet deployed. The full suite passes 198 offline tests and 22 pinned mainnet-fork simulations. The base system (190/20 at `74e536f`) went through three conformance rounds, a lean code audit and two independent rounds of blind adversarial security review with no outstanding Critical or High findings; the trusted-factory amendment carries its own conformance review and is not a fresh whole-system audit. The two retained accepted-risk disclosures are in `docs/BOUNTY-OPERATIONS.md`. Deployment still requires pin and validator-policy re-verification, GaugeAdder seating, ownership/binding and operational checks described in `docs/CURVE-PROPOSAL.md` and `docs/DEPLOYMENT-PINS.md`.

## Layout

- `contracts/CurveGaugeLister.sol` — fee-gated registration, V1 confiscation
- `contracts/CurveGaugeListerV2.sol` — trusted-factory paid admission and settlement with the bounty split hook
- `contracts/GaugeBounty.sol` — reporter-bound kill ballots and stakes
- `contracts/adapters/` — Votium and VoteMarket funding adapters
- `contracts/libraries/` — safe token handling, FeeDistributor accounting, canonical ballot scripts
- `test/`, `fork/` — offline suite (198) and pinned mainnet-fork suite (22)
- `docs/` — proposal, operations and disclosures, ABI, deployment pins, venue integration intel

## Running the gates

```
forge fmt --check && forge build --offline
forge test --offline                                  # 198 tests
MAINNET_RPC_URL=https://eth-mainnet.public.blastapi.io scripts/test-fork.sh   # 22 tests
```

forge/anvil 1.7.1, Solidity 0.8.30 (`evm_version = paris`, optimizer 200
runs), no external dependencies.
