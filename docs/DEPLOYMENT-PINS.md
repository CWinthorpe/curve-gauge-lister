# Deployment pins — no-bounty CurveGaugeLister

Prospective Ethereum-mainnet configuration. These are intended pins and historical verification anchors, not a claim of current deployment readiness. Reverify all addresses, code/source identities, roles and mutable policies at a newly recorded fixed block and again before opening paid admission. Keep the test fork pin separate and unchanged.

## Intended constructor dependencies

| Role | Address / value |
| --- | --- |
| Lister owner / CurveDAO Aragon org | `0x40907540d8a6C65c637785e8f8B742ae6b0b9968` |
| crvUSD | `0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E` |
| GaugeController canonical registry/regression reference (NOT an approved production `controller_` value — see Production controller composition) | `0x2F50D538606Fa9EDD2B11E2446BEb18C9D5846bB` |
| Production `controller_` / separate DAO-controlled router | Address UNSELECTED; required composition specified below; never substitute the raw controller or an invented address |
| crvUSD FeeDistributor | `0xD16d5eC345Dd86Fb63C6a9C43c517210F1027914` |
| MetaRegistry | `0xF98B45FA17DE75FB1aD0e7aFD971b0ca00e379fC` |
| Admission structural maxCoins | `8` |
| trustedGaugeValidator_ | `0x888888c34a46d0b2A34e9204e5273208E670e784` |
| Votium v2 local deposit ingress | `0x63942E31E98f1833A234077f47880A66136a2D1e` |
| VoteMarket local CampaignRemoteManager | `0x53ad4cd1f1e52dd02aa9fc4a8250a1b74f351ca2` |
| VoteMarket remote destination, chain42161 | `0x8c2c5a295450ddff4cb360ca73fccc12243d14d9` |

The controller row identifies the canonical raw GaugeController C, not an approved direct `controller_` value for this unchanged core. The selected composition specification is a separate DAO-controlled router R: construct the fresh lister L against R, install R as C's raw admin through the incumbent DAO's two-step governance action, and admit L as R's authorized adder. The DAO retains exclusive router control, independent registration, full raw administration, revocation and handback. R's implementation/address, independent review and actual grants remain OPEN; no existing GaugeAdder election is assumed. Retaining C's current admin prevents direct L→C additions, while seating L as raw admin strands administration and both transfer steps. Do not silently replace a pin. The impersonated raw-admin fork transfer remains regression-only, not a deployment instruction.

The lister owner controls pause, prospective configurations and two-step ownership, not discretionary token withdrawal. It is an Aragon governance executor, not described here as a deployer multisig. Actual gauge kill roles are separate, implementation-specific upstream authorities; they are not new constructor dependencies or lister privileges.

## Constructor and binding order

- `CurveGaugeLister(owner_,crvUSD_,controller_,feeDistributor_,admission_,platforms_,trustedGaugeValidator_)`: six original parameters plus the validator as SEVENTH. Admission is `(registry,maxCoins)`; platforms are `(freshVotiumAdapter,freshVoteMarketAdapter,approvedVotiumBps)`. The split is an explicit DAO-approved deployment choice, not implied by the test fixture's example. Supply the validator pin exactly; no default or setter exists. Chain1 is checked first; owner/code/token/FD/config validation follows; the core starts paused.
- `VotiumAdapter(crvUSD_,owner_,votium_)`: the token and local ingress need code. The manager is explicitly assigned, never an unexamined deployer default.
- `VoteMarketAdapter(crvUSD_,owner_,campaignRemoteManager_,votemarket_)`: local token/CRM need code; verify the nonzero remote on Arbitrum, not by an L1 code lookup.
- Use an authorized atomic deploy-and-bind batch. Each adapter's actual owner calls `setLister` once after the core exists. Read back both bindings and all pins/config; complete any two-step ownership handoff. Keep admission paused until controller, venue, FD and operational gates are complete. A misbound adapter must be replaced before accepting fees, not rebound later.

## Production controller composition — separate DAO-controlled router

The composition specification is selected; router implementation/address, review, governance approval and activation remain OPEN. Define C as raw GaugeController `0x2F50D538606Fa9EDD2B11E2446BEb18C9D5846bB`, D as DAO executor `0x40907540d8a6C65c637785e8f8B742ae6b0b9968`, R as the separate router and L as the fresh lister. R/L are labels, not deployment pins.

### Verified live baseline

At chain 1 block `26490527`, hash `0x2d08e56a768c84718784469563bf0f89e1824e8bec675eae5c3570470fb53727`, timestamp `1795589567` (2026-11-25 06:52:47 UTC), C returned `admin()==D`, `future_admin()==D`, `n_gauge_types()==13` and `n_gauges()==1056`. `gauges(0)` returned `0x7ca5b0a2910B33e9759DC7dDB0413949071D7575`, whose `gauge_types` returned valid type zero; `gauge_types(0x0000000000000000000000000000000000000000)` reverted with empty data. The future-admin value is not proof of a new pending transfer; apply does not clear that slot. This observation pin does not replace the regression-fork anchor below or future pre-activation re-reads.

[Blockscout's source response](https://eth.blockscout.com/api/v2/smart-contracts/0x2F50D538606Fa9EDD2B11E2446BEb18C9D5846bB) binds Vyper source SHA-256 `515270588d23b15b1aa0f3cd1f6bc17ddfbe0a972b6c65122f31313e29f1af94`: `add_gauge` at lines 289–324 gates on `assert msg.sender == self.admin` at line 297; both ownership steps at lines 128–148 require the incumbent admin; `add_type`, `change_type_weight` and `change_gauge_weight` are admin-only at lines 428, 444 and 480. Storage declarations at lines 68–109 and the complete source/ABI expose no native disciple/wrapper-election, epoch or budget authorization mechanism. Weight-accounting weeks are not wrapper-election epochs.

The service's deployed runtime matched pinned `eth_getCode` byte-for-byte: 12,013 bytes, Keccak-256 `0x655bec9519bc4e87c56bb2c54767c5ae6407f8be1b29140f5110c29d9607d42d`. The service reports partial verification (`is_partially_verified=true`, `is_fully_verified=false`, compiler `0.2.4+commit.7949850`); no fresh local Vyper reproduction or full creation verification is claimed. [Current Curve documentation](https://docs.curve.finance/protocol/gauge/whitelisting-gauge/) describes a per-gauge 7-day on-chain vote and 2,500 veCRV to create it; that is a documentation observation, not a new Voting-parameter read. The exact reads/source capture are owner-held and producible on demand.

### Required installation and continuing authority

- R has fixed canonical target C and exclusive DAO governance authority D, without independent deployer/manager control. Only D and adders explicitly admitted by D may register; initial delegated admission names exact L. D alone grants/revokes that capability. No lister, payer or other adder obtains administration, grant, upgrade or arbitrary-execution rights.
- L is freshly constructed with immutable `controller_=R`, owner D and its existing paused start. R implements `add_gauge(address,int128,uint256)`, `gauge_types(address)` and `n_gauge_types()` with synchronous canonical addition/read-through and whole-call rollback. Preserve actual gauge/type/weight: paid zero; DAO-free owner-supplied weight. Both calls originate at R from L; do not impose zero on all L calls or infer the outer caller. Preserve valid type zero, exclusive type-count bound and revert-on-absence; no shadow registry, queued addition or invented membership qualifies.
- D retains independent D→R→C addition without L's fee/validator/registry/structural/pause restrictions, plus DAO-only callable routes for raw `add_type`, `change_type_weight`, `change_gauge_weight`, `commit_transfer_ownership` and `apply_transfer_ownership`. Preserve raw default-argument overloads through matching router overloads or explicitly equivalent approved proposal payloads. No generic arbitrary-target executor is required in R. The lister gets no admin-forwarder, generic execution, new ownership method or controller setter.
- The incumbent D executes `C.commit_transfer_ownership(R)` then `C.apply_transfer_ownership()`, BOTH as D; pending R cannot perform the apply step. The governance package binds exact R/L deployment/configuration, D's exclusive control, L's adder grant and adapter bindings. “One-time” means policy installation, not necessarily one transaction. Post-installation `C.admin()==R`, NEVER L. D retains ultimate control through R, not a continuing direct raw-admin caller role.
- Preserve the DAO proposal process by updating its target/payload route to D→R→C. Old D→C admin calldata will fail after seating R. Inventory queued/in-flight proposals and execute before transition or explicitly reissue/migrate under DAO approval. No already-seated wrapper is assumed; independently evidenced external routes must be accounted for explicitly. Handback/replacement is D directing incumbent R through BOTH raw ownership steps. Handback to D restores direct DAO administration and disables R's raw-add route; it does not redirect immutable L or migrate escrow.
- Revoking L disables both lister admission lanes while retaining direct DAO registration/administration. Core pause alone disables only paid admission. Neither revocation, pause nor handback removes existing permanent registrations, affects existing escrow settlement, supplies kill authority or creates a refund. The lister MUST NEVER be raw admin, even temporarily; a raw-pinned instance cannot be repaired by changing defaults.

### Activation evidence — PAO-CTL W1–W8

These cells verify the concrete composition above, not an election under a nonexistent native wrapper mechanism. All remain OPEN. The deployment operator supplies selected-implementation evidence; governance approves the installation, retained powers and enablement alongside independent release authorities.

| Cell | Required evidence for C/D/R/L |
| --- | --- |
| W1 | Current fixed chain/block/hash/time; source/full runtime and roles for C, R and any actual governance/proxy components; fixed C target, D-only router control, exact L candidate/immutables and all authorized adders. Implementation/address selection and independent router review are required, not inferred from this specification. |
| W2 | Exact caller/target/selector/grant/grant-authority graph; ordered incumbent-D commit/apply installation, L grant, and funded paid positive simulation through L→R→C. Verify C's final admin is R, never L. Actual authorized install/grant transactions and readbacks are separately owed before unpause. |
| W3 | DAO-free L admission with supplied weight AND independent DAO registration without L restrictions; actual authorized governance/proposal payload route, queued-proposal disposition, every raw type/weight admin operation and both handback steps remain reachable. No EOA impersonation of L/R substitutes for a callable route. |
| W4 | D-only grant/revoke; rejection of outsider/adder administration and unauthorized addition; after L revocation both L lanes fail while independent DAO additions/admin remain usable. Core pause is not router revocation. No fictional seated-wrapper certificate is required; account for any separately evidenced existing external route. |
| W5 | Paid immediate canonical typed membership including valid type zero, exact raw gauge/type/zero-weight call, raw NewGauge and gauge-count advance; DAO-free supplied-weight/readback in W3. Independently observe C rather than accept router-local claims. |
| W6 | Selected R's absence-revert encoding and canonical count/type/absence read-through, including zero type. Preserve the core's existing bare-catch occupancy rule; absence bytes alone prove no authorization. |
| W7 | Approve W1–W6/W8 simulations and independent FD/venue/operations gates; actual authorized deploy/bind/handoff/install/grant readbacks, current mutable roles and proposal continuity, then explicit owner unpause approval and state verification. |
| W8 | Disposable, explicitly unpaused, otherwise-valid funded pre-grant/revoked negative reaches R's real adder authorization frame; unauthorized R→C authority failure is separately attributed where applicable. Bind full fee/record/liability/membership/approval/receipt/event rollback. Pause/validator/binding failures or revert bytes alone do not prove authorization reachability. |

Selected-composition simulations and separate router review precede production installation/enablement approval. Actual authorized grants, deployment/bindings, ownership and role readbacks precede unpause. The first real paid broadcast is post-authorization evidence; unpause opens the permissionless lane, not a restricted trial. No destructive live governance action is demanded merely to obtain a certificate. No viable reviewed installation or any missing mandatory cell means HOLD, with no claim of production DAO-free integration either. This documentation specifies the separate dependency but authorizes no router implementation or broadcast.

The fork `_seat` helper's impersonated raw-admin transfer and historical S03 “production composition” label remain a raw-target REGRESSION ONLY, INVALID AS A PRODUCTION INTEGRATION TEMPLATE. Existing paid/absence/type-zero/count/rollback observations remain useful for their actual scope and prove no router, retained governance or handback. Tests, fixtures and native regression identities are unchanged; W1–W8 are separate deployment evidence, not additions to that census. Discovery of an actual deployed raw-pinned core or existing liability triggers the existing stop condition, not migration authority.

The same owner-held package retains the independent FeeDistributor allocator/eligibility/accounting obligation and the invariant-to-clause-to-implementation-to-evidence index. This correction changes no FD/venue certificate, economic term, escrow mechanism or release approval.

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

Current pin/source/role and validator-policy verification; separately reviewed R implementation/address and DAO-approved installation of the concrete controller composition above, including proposal-payload continuity, revocation and handback (L as raw admin remains prohibited); approved selected-composition simulations and actual authorized deployment/grant/binding/ownership readbacks before unpause; Votium crvUSD acceptance and execution-round behavior; remote VoteMarket whitelist/MINIMUM_PERIODS and destination delivery; funded real venue probes; committed ETH float; assigned operational roles; safe FD window and the post-authorization funded trial. No authority document, attestation commit or historical fork receipt closes these gates. Emergency kills remain independent authorized actions; a failing combined kill-and-confiscate batch would roll back the kill.
