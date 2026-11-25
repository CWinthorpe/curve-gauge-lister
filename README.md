# Curve Gauge Lister

Fee-gated registration of Curve gauges, with four-epoch vote-incentive escrow and all-unspent-escrow confiscation to the pinned crvUSD FeeDistributor when the gauge's own `is_killed()` flag is true. The DAO handles gauge review and kills through its existing authorized processes. There are no reporter rewards or reporting stakes.

This is a proposed additional admission route, not a live bypass of Curve governance. [Curve's current gauge-whitelisting documentation](https://docs.curve.finance/protocol/gauge/whitelisting-gauge/) describes a per-gauge 7-day on-chain vote, requiring 2,500 veCRV to create. At Ethereum block `26490527` (2026-11-25), canonical GaugeController `0x2F50D538606Fa9EDD2B11E2446BEb18C9D5846bB` admits additions only from its admin, CurveDAO `0x40907540d8a6C65c637785e8f8B742ae6b0b9968`; it has no native disciple/wrapper election, epoch or budget authorization mechanism.

The seating ask is a one-time DAO-approved installation of a separate DAO-controlled router: the router becomes raw controller admin, the fresh lister is constructed against it and admitted as an authorized adder, and the DAO retains its independent proposal route, full controller administration, adder revocation and admin handback through the router. Existing raw-target governance payloads must be retargeted; preservation means the governance process and powers, not unchanged calldata. Only after that installation and activation may eligible paid listings register without a separate per-gauge registration vote. veCRV weight voting and gauge-specific kill authority remain unchanged. The lister must never be raw controller admin and gains no admin-forwarder. The router is implemented in this repository as `contracts/GaugeControllerAdmin.sol` (see `docs/CURVE-PROPOSAL.md` for semantics, `docs/ABI.md` for its complete compiled surface, and `docs/OPERATIONS.md`/`docs/DEPLOYMENT-PINS.md` for installation sequencing and limits); production address selection, the separate independent review, governance approval and activation remain open, and no deployment is claimed by that implementation.

## Product

- Anyone, including the owner, may use `listGauge` to pay exactly 10,000 crvUSD. Registry authentication and structural checks run first. The immutable, explicitly supplied GaugeValidator at `0x888888c34a46d0b2A34e9204e5273208E670e784` must then return canonical true from `validateGauge(gauge)`, before adapter readiness, listing/escrow effects, fee transfer or controller addition. False, failed and malformed reads reject the listing.
- A successful paid listing is added atomically at raw weight zero. Registration grants no emissions; veCRV voting still determines emissions.
- Four tranches of 2,500 crvUSD mature at the four following Thursday-aligned weekly boundaries. Anyone may checkpoint them. Each listing keeps its original venue addresses and split. Late settlement funds execution-time Votium rounds or VoteMarket ingress, not historical votes; a successful L1 VoteMarket receipt is not proof of destination delivery.
- If an Active listing's gauge flag is true, `confiscate` or `checkpoint` sends its entire unreleased balance to `0xD16d5eC345Dd86Fb63C6a9C43c517210F1027914`. Mandatory exact-transfer and same-transaction FeeDistributor accounting must succeed or everything reverts with escrow retained. Controller weight is never a kill signal.
- The owner-only `listGaugeNoEscrow` path retains registry/structural/controller checks but does not query the trusted validator or require paid-adapter readiness. It creates no fee or escrow and works while paused.
- The core starts paused on chain 1. Deployment must complete owner-authenticated one-time adapter bindings, DAO ownership and the separate router installation/authorization before enabling paid listings. The core's immutable controller endpoint is the approved router, not the raw GaugeController. Pause blocks only new paid admission; router revocation blocks both lister admission lanes, not existing escrow settlement. No owner withdrawal, payer refund, arbitrary execution, recipient replacement or escrow migration exists.

The validator pointer is immutable, but its owner or appointed managers can change upstream factory/module policies. Admission is not an audit of a pool's safety. Later checker failure or revocation does not block existing escrow settlement. Gauge kill authority belongs to the actual gauge implementation and its administrators; paying a listing fee neither grants nor transfers it.

### The router: `contracts/GaugeControllerAdmin.sol`

The supplied `GaugeControllerAdmin` is role R of the selected composition: the standalone, fixed-authority Curve DAO controller-administration router. Both authorities are constructor-pinned immutables — `controller()` is the canonical GaugeController C and `dao()` is the explicit Curve DAO executor D supplied at construction; neither is derived from the deployer, and no router-owner, target-setter, upgrade or initializer surface exists. R is what becomes the raw controller admin; the fresh unchanged lister L is constructed with `controller_ = R`, and only L, once granted, and D reach the add path.

Powers, exactly:

- Only D grants/revokes adders (`grant(address,bool)`), invokes generic controller execution (`execute(bytes)` — no target, no value, ordinary zero-value CALL to the immutable C only), and initiates or completes the two-step ownership handback. A grant is the full raw-add capability: any adder D grants, including L, may supply any controller-valid initial weight through `add_gauge`; the paid raw-weight-zero rule stays in unchanged L, not in a router clamp, and D's own `D→R` administration (add/type/weight) is independent of any grant.
- The two controller ownership selectors inside `execute(bytes)` are mediated into the same local commit/apply state machine as the typed `commit_transfer_ownership`/`apply_transfer_ownership` methods, with canonical encodings only: there is no raw ownership escape from retirement, and apply is possible only from a fresh local commit (the raw controller's `future_admin` is stale history, never proof).
- `add_gauge` requires an incumbent check at R itself (`C.admin()` must equal R) in addition to the D/adder gate — but `grant` is deliberately usable before seating, after deployment; incumbency gates the mutating lanes that reach C (`add_gauge`, non-ownership `execute`, commit and apply), not the authorization-key lane.
- Canonical reads (`gauge_types`, `n_gauge_types`, getters) are public, lock-free and remain callable after retirement; they confer no write capability.
- A successful handback apply permanently retires R for every mutation — including `grant` and generic `execute` of otherwise-public controller functions — and clears only the local nomination. Retirement is never cleared and no revival API exists; a retired router must never be reseated, because that would strand controller administration. Governance tooling must refuse to nominate a retired R.
- Funding boundary: R has no intended custody or money-handling path — nonpayable throughout, no receive/fallback, no deposit/withdrawal/rescue/sweep/approval surface, and every call to C sends zero value. Literal zero balances are not an invariant of any EVM contract: forced ETH and unsolicited ERC20 transfers can arrive and remain stranded, conferring no authority, blocking no operation and receiving no recovery service. Do not rely on R's balance being zero.

## Status and evidence

Not deployed. The no-bounty release plan and gates, the exact ABI/layout manifest, the exact test-identity witness inventory and the dependency and acceptance receipts are held by the project owner as a single release evidence package bound to the exact candidate commit, and are producible on demand; an authority ruling is not implementation acceptance or mainnet authorization. Consult candidate-bound execution receipts for actual passing counts, not historical totals.

The evidence and obligation carriers for this release — the admission ruling, the bound census manifest, the fork-clause resolution and that leg's verification, the pre-activation obligation carriers and this documentation package's receipts — are held by the project owner, are producible on demand and are not published in the source tree. These records carry admission decisions, obligation registrations and evidence boundaries; they are a partial view of, not a substitute for, the complete owner-held candidate evidence package (normative plan, ABI/layout manifest, witness inventory, dependency and acceptance receipts), which remains owner-controlled and producible on demand. Custody of a record is not approval, and producing it on demand removes no owner control: the pre-activation obligations carried in those documents remain ACTIVATION-OPEN until the named approvals are actually given.

The public source tree is product-only. There is no current selective-publication exception for authority rulings, work orders or receipt packages: these, including the controller-composition correction and pre-activation carriers, remain owner-held and producible on demand. Historical Git publication is not current in-tree custody. Neither custody, an authority attestation commit nor document publication is owner release or activation approval. Activation remains on HOLD until the separate router implementation/review/governance installation and all controller, FD, venue, binding, float and operations approvals are complete.

The earlier V2/reporting implementation and proposal are preserved at Git commit `e18bee54c08832dd7fd6d0a11932290155bf9178`. Historical reviews describe their original candidates and are not a fresh audit of this release; the source comparison and baseline evidence belong to those records and are held with the release evidence package. Current operational limits include FeeDistributor checkpoint contention, immutable venue availability and irrecoverable VoteMarket campaign residuals; see `docs/OPERATIONS.md`.

## Layout

- `contracts/CurveGaugeLister.sol` — paid trusted admission, DAO-free admission, four-epoch escrow and all-FeeDistributor confiscation.
- `contracts/GaugeControllerAdmin.sol` — the supplied fixed-authority DAO controller router (role R): immutable C/D, D-only grant/execute/typed handback, adder-gated `add_gauge`, canonical lock-free reads, mediated ownership selectors and permanent post-handback retirement. Production deployment remains separately gated.
- `contracts/adapters/` — Votium and VoteMarket funded ingress.
- `contracts/interfaces/`, `contracts/libraries/SafeToken.sol` — narrow dependency interfaces and safe token operations.
- `contracts/mocks/`, `test/` — test fixtures and offline tests, including retained adapter-hardening regressions.
- `fork/` — concrete pinned mainnet-fork runners; abstract scenarios remain under `test/fork/`.
- `docs/CURVE-PROPOSAL.md`, `docs/ABI.md`, `docs/OPERATIONS.md`, `docs/DEPLOYMENT-PINS.md` — current product and deployment reference.

Release authority, exact manifests and the complete candidate-bound release evidence package, including the pre-activation obligation carriers and documentation receipts, are not shipped in the public tree. They are held by the project owner and producible on demand. These records preserve their evidence boundaries and approval requirements; no published product document or authority attestation substitutes for owner release or activation approval.

## Running checks

```sh
forge fmt --check
rm -rf out cache
forge build --offline --sizes --extra-output storageLayout
forge test --offline
FOUNDRY_PROFILE=fork forge build --offline --sizes --extra-output storageLayout
MAINNET_RPC_URL=https://eth-mainnet.public.blastapi.io scripts/test-fork.sh
```

The acceptance gates (held with the release evidence package) additionally require exact ABI/inventory/layout comparisons against the owner-held manifest, an RPC-unreachable offline control, cold/warm fork runs, fail-closed fork preflight, named falsifiers and independent runtime-byte ceiling checks. The in-tree compiled-ABI allowlist test checks artifact signature keys plus one no-fallback probe only; deployed-byte/immutables equality is its own release gate and is not attested by that test. The compiled-ABI/storage-surface identities read the artifact's `storageLayout` section from the fresh default output under `out/`; the build commands above are the canonical gate form that emits it. Artifact-reading runs therefore start from a cleared, freshly built default output — a plain build without `--extra-output storageLayout` provides no layout input for those identities. The fork endpoint can change; the pinned block cannot silently change.

Build policy: Solidity 0.8.30, optimizer 200 runs, no external Solidity dependencies; default EVM Paris, fork EVM Cancun on chain 1. Baseline evidence used Forge 1.7.1. Reverify compiler/tool versions for the release.
