# Curve Gauge Lister

Fee-gated registration of Curve gauges, with four-epoch vote-incentive escrow and all-unspent-escrow confiscation to the pinned crvUSD FeeDistributor when the gauge's own `is_killed()` flag is true. The DAO handles gauge review and kills through its existing authorized processes. There are no reporter rewards or reporting stakes.

## Product

- Anyone, including the owner, may use `listGauge` to pay exactly 10,000 crvUSD. Registry authentication and structural checks run first. The immutable, explicitly supplied GaugeValidator at `0x888888c34a46d0b2A34e9204e5273208E670e784` must then return canonical true from `validateGauge(gauge)`, before adapter readiness, listing/escrow effects, fee transfer or controller addition. False, failed and malformed reads reject the listing.
- A successful paid listing is added atomically at raw weight zero. Registration grants no emissions; veCRV voting still determines emissions.
- Four tranches of 2,500 crvUSD mature at the four following Thursday-aligned weekly boundaries. Anyone may checkpoint them. Each listing keeps its original venue addresses and split. Late settlement funds execution-time Votium rounds or VoteMarket ingress, not historical votes; a successful L1 VoteMarket receipt is not proof of destination delivery.
- If an Active listing's gauge flag is true, `confiscate` or `checkpoint` sends its entire unreleased balance to `0xD16d5eC345Dd86Fb63C6a9C43c517210F1027914`. Mandatory exact-transfer and same-transaction FeeDistributor accounting must succeed or everything reverts with escrow retained. Controller weight is never a kill signal.
- The owner-only `listGaugeNoEscrow` path retains registry/structural/controller checks but does not query the trusted validator or require paid-adapter readiness. It creates no fee or escrow and works while paused.
- The core starts paused on chain 1. Deployment must complete owner-authenticated one-time adapter bindings, DAO ownership and actual upstream controller authorization before enabling paid listings. Pause blocks only new paid admission. No owner withdrawal, payer refund, arbitrary execution, recipient replacement or escrow migration exists.

The validator pointer is immutable, but its owner or appointed managers can change upstream factory/module policies. Admission is not an audit of a pool's safety. Later checker failure or revocation does not block existing escrow settlement. Gauge kill authority belongs to the actual gauge implementation and its administrators; paying a listing fee neither grants nor transfers it.

## Status and evidence

Not deployed. The no-bounty release plan and gates, the exact ABI/layout manifest, the exact test-identity witness inventory and the dependency and acceptance receipts are held by the project owner as a single release evidence package bound to the exact candidate commit, and are producible on demand; an authority ruling is not implementation acceptance or mainnet authorization. Consult candidate-bound execution receipts for actual passing counts, not historical totals.

A bounded set of authority rulings is selectively published in-tree — `review/r3gate/` (the admission ruling, the bound census `BINDING.json`, the fork-clause resolution and that leg's verification) plus the `review/simplify2/` pre-activation obligation carriers, and this documentation package's receipts under `review/r3docs/`. These records carry admission decisions, obligation registrations and evidence boundaries; they are a partial view of, not a substitute for, the complete owner-held candidate evidence package (normative plan, ABI/layout manifest, witness inventory, dependency and acceptance receipts), which remains owner-controlled and producible on demand. A published path is not approval, and selective publication removes no owner control: the pre-activation obligations carried in those documents remain ACTIVATION-OPEN until the named approvals are actually given.

The earlier V2/reporting implementation and proposal are preserved at Git commit `e18bee54c08832dd7fd6d0a11932290155bf9178`. Historical reviews describe their original candidates and are not a fresh audit of this release; the source comparison and baseline evidence belong to those records and are held with the release evidence package. Current operational limits include FeeDistributor checkpoint contention, immutable venue availability and irrecoverable VoteMarket campaign residuals; see `docs/OPERATIONS.md`.

## Layout

- `contracts/CurveGaugeLister.sol` — paid trusted admission, DAO-free admission, four-epoch escrow and all-FeeDistributor confiscation.
- `contracts/adapters/` — Votium and VoteMarket funded ingress.
- `contracts/interfaces/`, `contracts/libraries/SafeToken.sol` — narrow dependency interfaces and safe token operations.
- `contracts/mocks/`, `test/` — test fixtures and offline tests, including retained adapter-hardening regressions.
- `fork/` — concrete pinned mainnet-fork runners; abstract scenarios remain under `test/fork/`.
- `docs/CURVE-PROPOSAL.md`, `docs/ABI.md`, `docs/OPERATIONS.md`, `docs/DEPLOYMENT-PINS.md` — current product and deployment reference.

Release authority, exact manifests and the complete candidate-bound release evidence package are not shipped in the tree; they are held by the project owner and producible on demand. The tree selectively carries only the bounded r3gate authority rulings, the pre-activation obligation carriers and this documentation package's receipts listed under Status and evidence; their presence there is neither the full package nor an approval of it.

## Running checks

```sh
forge fmt --check
forge build --offline --sizes
forge test --offline
FOUNDRY_PROFILE=fork forge build --offline --sizes
MAINNET_RPC_URL=https://eth-mainnet.public.blastapi.io scripts/test-fork.sh
```

The acceptance gates (held with the release evidence package) additionally require exact ABI/inventory/layout comparisons against the owner-held manifest, an RPC-unreachable offline control, cold/warm fork runs, fail-closed fork preflight, named falsifiers and independent runtime-byte ceiling checks. The in-tree compiled-ABI allowlist test checks artifact signature keys plus one no-fallback probe only; deployed-byte/immutables equality is its own release gate and is not attested by that test. Use a fresh build output for artifact-reading tests. The fork endpoint can change; the pinned block cannot silently change.

Build policy: Solidity 0.8.30, optimizer 200 runs, no external Solidity dependencies; default EVM Paris, fork EVM Cancun on chain 1. Baseline evidence used Forge 1.7.1. Reverify compiler/tool versions for the release.
