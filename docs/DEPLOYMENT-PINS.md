# Deployment pins — no-bounty CurveGaugeLister

Prospective Ethereum-mainnet configuration. These are intended pins and historical verification anchors, not a claim of current deployment readiness. Reverify all addresses, code/source identities, roles and mutable policies at a newly recorded fixed block and again before opening paid admission. Keep the test fork pin separate and unchanged.

## Intended constructor dependencies

| Role | Address / value |
| --- | --- |
| Lister owner / CurveDAO Aragon org | `0x40907540d8a6C65c637785e8f8B742ae6b0b9968` |
| crvUSD | `0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E` |
| GaugeController canonical registry/regression reference (NOT an approved production `controller_` value — see Production controller composition) | `0x2F50D538606Fa9EDD2B11E2446BEb18C9D5846bB` |
| crvUSD FeeDistributor | `0xD16d5eC345Dd86Fb63C6a9C43c517210F1027914` |
| MetaRegistry | `0xF98B45FA17DE75FB1aD0e7aFD971b0ca00e379fC` |
| Admission structural maxCoins | `8` |
| trustedGaugeValidator_ | `0x888888c34a46d0b2A34e9204e5273208E670e784` |
| Votium v2 local deposit ingress | `0x63942E31E98f1833A234077f47880A66136a2D1e` |
| VoteMarket local CampaignRemoteManager | `0x53ad4cd1f1e52dd02aa9fc4a8250a1b74f351ca2` |
| VoteMarket remote destination, chain42161 | `0x8c2c5a295450ddff4cb360ca73fccc12243d14d9` |

The controller row identifies the canonical raw GaugeController used as the registry/regression reference and as the real controller in the historical fork simulation. It is NOT an approved direct `controller_` constructor value for this unchanged core, and it is not proof of production calling authority. The production `controller_` endpoint is UNSELECTED: only a separately selected and separately approved authority-preserving GaugeAdder/wrapper/executor composition is eligible (see Production controller composition). Under the named raw controller's semantics, retaining its existing admin prevents either lister lane from adding, while transferring raw admin to the lister strands callable controller administration and both incumbent-admin-only ownership-transfer steps — lister-owner transfer cannot repair that. Do not silently replace a pin, and do not insert a guessed intermediary address. The fork-only impersonated admin transfer is a regression simulation, not a deployment instruction. GaugeAdder selection/seating/integration remains a separate rollout gate.

The lister owner controls pause, prospective configurations and two-step ownership, not discretionary token withdrawal. It is an Aragon governance executor, not described here as a deployer multisig. Actual gauge kill roles are separate, implementation-specific upstream authorities; they are not new constructor dependencies or lister privileges.

## Constructor and binding order

- `CurveGaugeLister(owner_,crvUSD_,controller_,feeDistributor_,admission_,platforms_,trustedGaugeValidator_)`: six original parameters plus the validator as SEVENTH. Admission is `(registry,maxCoins)`; platforms are `(freshVotiumAdapter,freshVoteMarketAdapter,approvedVotiumBps)`. The split is an explicit DAO-approved deployment choice, not implied by the test fixture's example. Supply the validator pin exactly; no default or setter exists. Chain1 is checked first; owner/code/token/FD/config validation follows; the core starts paused.
- `VotiumAdapter(crvUSD_,owner_,votium_)`: the token and local ingress need code. The manager is explicitly assigned, never an unexamined deployer default.
- `VoteMarketAdapter(crvUSD_,owner_,campaignRemoteManager_,votemarket_)`: local token/CRM need code; verify the nonzero remote on Arbitrum, not by an L1 code lookup.
- Use an authorized atomic deploy-and-bind batch. Each adapter's actual owner calls `setLister` once after the core exists. Read back both bindings and all pins/config; complete any two-step ownership handoff. Keep admission paused until controller, venue, FD and operational gates are complete. A misbound adapter must be replaced before accepting fees, not rebound later.

## Production controller composition (S03 — historical raw-target regression only)

The core consumes exactly three behaviours from its immutable `controller` in
both admission lanes: `add_gauge` (immediate permanent, caller-authorized
registry addition), `gauge_types` (returns the stored type when present —
including a valid type zero — and reverts when the gauge is absent) and
`n_gauge_types` (exclusive upper bound for type validation). The raw address
`0x2F50D538606Fa9EDD2B11E2446BEb18C9D5846bB` remains the canonical registry
and historical regression reference, NOT an approved direct `controller_`
constructor value for this unchanged core. The actual production endpoint is
UNSELECTED.

Under the bound saved controller source, `add_gauge`, `add_type`,
`change_type_weight`, `change_gauge_weight`, `commit_transfer_ownership` and
`apply_transfer_ownership` all gate on the incumbent controller admin, and
the core calls `add_gauge` as itself. Therefore, with that raw controller:

- Retaining its existing admin means neither lister admission lane can add.
- Transferring raw admin to the unchanged lister can make additions work but
  strands callable controller administration and both incumbent-admin-only
  ownership-transfer steps: the lister's own owner functions only configure
  this lister or transfer this lister's ownership, and a proposed successor
  cannot execute the incumbent-admin-only apply step. DAO ownership of the
  lister does not solve the caller mismatch, and lister-owner transfer cannot
  repair it. The DAO-free lane has the same inner-caller constraint.

The unchanged lister MUST NOT become raw controller admin, even temporarily.
The fork's `_seat` helper and its impersonated two-step admin transfer are a
disposable regression simulation ONLY and are INVALID AS A PRODUCTION
INTEGRATION TEMPLATE. The fixture's historical S03 “production composition”
label is explicitly superseded as an authority claim: it covers the raw-target
regression only. The pre-seating outsider rejection, funded addition,
type-zero readback, gauge-count advance, exact `add_gauge(gauge, 0, 0)`
observation and rollback in `test/fork/ForkAdmission.t.sol`
`test_Fork_ControllerSeatingAndUnseatedRollback` (reinforced by the
membership/count/type-zero assertions of the two fork trust identities)
remain valid, useful regression evidence; they prove no retained governance,
no handback and no production authority. No test, assertion or fixture
comment is modified or reinterpreted by this section.

For this unchanged core and the named raw controller, the only class eligible
for activation is a separately selected and separately approved
authority-preserving GaugeAdder/wrapper/executor composition; nothing in this
document certifies that any contract called GaugeAdder already implements a
compatible route, and no concrete intermediary, address or grant is approved
here. The core must be CONSTRUCTED against the reviewed compatible endpoint;
an already raw-pinned instance cannot be repaired by changing defaults or
seating an unrelated intermediary — its pointer is immutable. That endpoint
must implement the exact three `IListingController` operations, forward the
actual gauge/type/weight synchronously (paid: zero; DAO-free: owner-supplied
weight), provide canonical count/type/absence reads including a valid stored
type zero and revert-on-absence, and preserve same-transaction addition with
immediate canonical typed readback and whole-call rollback. The last caller
into the named raw `add_gauge` must satisfy its real incumbent-admin gate. A
name, a whitelist elsewhere or a narrow shim is not that proof; a three-method
intermediary that itself holds raw admin without callable administration and
handback recreates the prohibited composition. Queued proposals, a shadow
registry or a facade returning invented membership do not qualify. Discovery
of a real deployment or liability triggers the existing stop condition, not
migration authority.

PAO-CTL's tightened W1–W8 are the activation cells for the selected graph:
selected-current source/runtime/role bindings for the canonical controller
and every selected endpoint/executor/proxy; the full
caller/target/selector/grant/grant-authority chain to the final raw-admin
caller; paid AND DAO-free positive additions with the correct weight; an
unmasked, attributed authorization negative that actually reaches the
authorization check; preserved existing DAO addition routes and the already
seated wrapper's route on their existing terms; reachable `add_type`,
`change_type_weight`, `change_gauge_weight`, `commit_transfer_ownership` and
`apply_transfer_ownership` through actual authorized callable routes —
impersonating the lister as an EOA is not such a route. Selected-composition
simulation is approved before production enablement; actual authorized
grants, bindings and ownership readbacks precede unpause; the first real paid
broadcast is post-authorization evidence. Unpause opens the permissionless
lane; it is not a restricted trial. These are deployment-evidence obligations,
not additions to the regression census, and no destructive live governance
transaction is demanded merely to produce a certificate. Independent FD,
venue and operations gates still apply. If no compatible graph is selected
and approved, the deployment stays paused under HOLD, and production DAO-free
integration likewise may not be claimed. No core admin forwarding, generic
execution, extra ownership method, controller setter, new shim or fixture
rewrite is admitted: the blocker is a selected composition, not wording.

The same package carries the confiscation-accounting bound obligation for
the selected FeeDistributor allocator (one obligation binding the floored
inclusive coverage limit, the separate ordinary-caller eligibility rule, the
two-sided exact custody, the mandatory checkpoint and both postchecks to the
approved allocator source/runtime re-reads recorded below) and the
invariant→clause→implementation→evidence index linking every current
obligation to its approved clause and independent witness.

## Fixed regression-fork anchor

Chain1; block `26401019`; hash `0x55810b079923a14fb97ad548f5024f65530dbc4fb2357a38f41e13b3d27cb6d3`; timestamp `1794512471`.

`scripts/test-fork.sh` verifies the exact header over RPC before invoking Forge. Its endpoint override is MAINNET_RPC_URL, not a block override. The historical PublicNode endpoint can lack old-state access; an archive error is a failure, not empty code or a negative predicate. Blast's public mainnet endpoint was used for archived state in the preceding evidence. Recheck availability; do not silently repin or replace live contracts with fixture code.

Fork code/hash/role assertions and holder/DAO impersonations are in `../test/fork/ForkFixture.sol` and `../test/fork/ForkTrustedFactory.t.sol`. These are simulations, not broadcast receipts, production seating or destination-delivery certificates.

## Trusted validator lineage and mutable policy

The prior source-verification record, preserved at `e18bee54c08832dd7fd6d0a11932290155bf9178`, binds these historical facts:

| Item | Historical observation |
| --- | --- |
| Validator predicate | `validateGauge(address)`, selector `0xe92cd3d3`; argument is the GAUGE |
| Validator runtime | 3,402 bytes; Keccak256 `0x2d684822a3f2bf6f99f902474289219041443a9d9cc94cbc28505050185016cd` |
| Validator owner | `0x40907540d8a6C65c637785e8f8B742ae6b0b9968` |
| One checked enabled manager | `0xc0DE00005F21Fa7846BA0EA2E3F2FC4F048a72C9` |
| Gauge-validation module | `0x999902533033Cc63c8128C501e307477932B742E` |
| Module runtime | 1,336 bytes; Keccak256 `0xfc5562e86bbf44b97a41e6e1e1f578a396c0fd4a5aaac85805ef62630fca36ff` |
| SS-ng regular gauge factory | `0x6A8cbed756804B16E05E741eDaBd5cB544AE21bf`, module above, method1 |
| Legacy crypto factory | `0xF18056Bbd320E96A48e3Fbf8bC061322531aac99`, same module, method2 |
| SS-ng fork candidate gauge | `0x9f96B45A2ea3Fea791513aa3A7921d474105B23e` |
| Legacy candidate gauge | `0xfB389aCa09ddC676fC9D5aC3cfD2Cd133bf44E19` |
| Distinct legacy LP / minter pool | `0x1AEa495539B514A5538878D3D3695c7AEDdC61F1` / `0x03470B57B05089EE40c651dAC9E0387F1f3cb46f` |

The prior record reports full runtime reproduction from `wavey0x/curve-gauge-validator` commit `c1246600ef8aeea452ab0c849bf9135647ee8c4f`, Solidity `0.8.28+commit.7893614a`, optimizer200, Cancun, remapping `forge-std/=lib/forge-std/src/`. Source: https://github.com/wavey0x/curve-gauge-validator/blob/c1246600ef8aeea452ab0c849bf9135647ee8c4f/src/GaugeValidator.sol and adjacent GaugeValidationModuleV1.sol. This is a dependency-source anchor, not this repository's compiler policy. Do not infer Curve-organization authorship or an AutoWrapper precedent from the address; the earlier `curvefi/automation` attribution was not corroborated.

The pointer is immutable in the lister, but upstream owner/managers may change policies. The one manager above is not an exhaustive role inventory. Review ManagerSet/FactoryPolicySet history and current relevant manager keys. Verify each intended factory's module/method and actual reciprocal gauge predicate; a factory name or nonzero mapping alone does not pass. For the distinct-LP legacy route, a successful zero direct lookup permits the minter route; a failed direct read does not.

Never substitute `validateProposalGauges(uint256)` (`0x2da285c4`), a proposal module, a pool, LP, factory or transaction deployer for the per-gauge predicate. The core's code check alone proves none of this. DAO-free listing does not query the checker; policy changes do not add a settlement gate to existing escrow.

## Re-verification procedure

Select one endpoint and explicit block. Record chain ID, block number/hash/timestamp before reading code and state; use that same block for every observation. The following read-only example preserves the regression anchor; deployment must use its separately selected current block.

```sh
RPC=https://eth-mainnet.public.blastapi.io
BLOCK=26401019
cast chain-id --rpc-url "$RPC"
cast block "$BLOCK" --json --rpc-url "$RPC"
cast code 0x888888c34a46d0b2A34e9204e5273208E670e784 --block "$BLOCK" --rpc-url "$RPC"
cast call 0x888888c34a46d0b2A34e9204e5273208E670e784 'owner()(address)' --block "$BLOCK" --rpc-url "$RPC"
cast call 0x888888c34a46d0b2A34e9204e5273208E670e784 'policyForFactory(address)(address,uint8)' 0x6A8cbed756804B16E05E741eDaBd5cB544AE21bf --block "$BLOCK" --rpc-url "$RPC"
cast call 0x888888c34a46d0b2A34e9204e5273208E670e784 'validateGauge(address)(bool)' 0x9f96B45A2ea3Fea791513aa3A7921d474105B23e --block "$BLOCK" --rpc-url "$RPC"
cast call 0x888888c34a46d0b2A34e9204e5273208E670e784 'validateGauge(address)(bool)' 0xfB389aCa09ddC676fC9D5aC3cfD2Cd133bf44E19 --block "$BLOCK" --rpc-url "$RPC"
cast call 0xD16d5eC345Dd86Fb63C6a9C43c517210F1027914 'token()(address)' --block "$BLOCK" --rpc-url "$RPC"
cast call 0xD16d5eC345Dd86Fb63C6a9C43c517210F1027914 'is_killed()(bool)' --block "$BLOCK" --rpc-url "$RPC"
```

Additionally record/hash full runtime bytes and verified sources for each dependency and any proxy implementation; confirm crvUSD decimals18, controller/registry ABI and authority, validator owner/managers/policy/module, actual gauge/LP/pool/coins and real kill authorization. Full runtime hashes, not size or proxy shape alone, establish code identity. Validate literal addresses before lookup, never silently correct a malformed pin.

For the FD, record admin, can_checkpoint_token, last_token_time, token_last_balance, actual crvUSD balance and bounded-loop/cooldown source. Require public checkpoint availability for the ordinary lister, nonzero/nonfuture cursor, `now<=floor(t/604800)*604800+20*604800` and strict public eligibility `now>t+86400`. Shared-cursor contention can indefinitely delay settlement. Stale zero-delta refresh and direct retry are governed by `OPERATIONS.md`; positive stale unaccounted money is not safely repaired by a claimed best-effort refresh.

## Deployment gates still open

Current pin/source/role and validator-policy verification; an approved authority-preserving controller composition for the selected production endpoint (the direct raw-admin seat is prohibited; selected-composition simulation approved before enablement, actual authorized grants/bindings/ownership readbacks before unpause); Votium crvUSD acceptance and execution-round behavior; remote VoteMarket whitelist/MINIMUM_PERIODS and destination delivery; funded real venue probes; authorized deployment/binding/ownership receipts; committed ETH float; assigned operational roles; safe FD window and a funded trial listing. No authority or fork receipt silently closes these gates. Emergency kills should proceed through their real authority independently of settlement; a failing combined kill-and-confiscate batch would also roll back the kill.
