# CX-CTL — Approved controller caller/role graph: PRE-ACTIVATION GATE witness plan

Original r2 carrier: candidate-bound, owner-held and producible on demand. Authority:
row CX-CTL of the verified r2 review (rank 2). STATUS: **PRODUCTION
SELECTION IS OPEN — nothing here selects or fabricates it. Every cell below
is a PRE-ACTIVATION GATE: paid admission must remain disabled until the
graph is selected, approved, and its witnesses are recorded.**

## Named target and consumed behaviours (fixed, approved-content shape)

Immutable `controller` = GaugeController
`0x2F50D538606Fa9EDD2B11E2446BEb18C9D5846bB` (docs/DEPLOYMENT-PINS.md
constructor table row 3 and §Production controller composition). The
product consumes exactly three behaviours
(`contracts/interfaces/IListingController.sol`): `add_gauge(address,int128,uint256)`
(caller-authorized immediate permanent registry addition),
`gauge_types(address)` (stored type when present INCLUDING valid type
zero; revert when absent), `n_gauge_types()` (exclusive type bound). The
weight surface stays an observation-only dependency outside this subset
(S20 law).

## Preserved obligations of ANY approved composition (not inferred)

* Immediate canonical typed membership at admission, including type zero
  (`_seatMembership`: add then same-transaction `gauge_types` postcheck;
  mismatch → `MembershipFailed`, whole-call rollback).
* Failure rollback of fee/record/registration/events on any rejection.
* Authorized add: execution authority belongs to the upstream
  GaugeAdder/admin integration, never to the public lister caller.
* The DAO's existing routes and the seated-wrapper route remain
  available on their existing terms (docs/CURVE-PROPOSAL.md §Simple
  Summary; this is an additional admission route, not a retirement).

## What does NOT authorize a deployment

* The fork's impersonated two-step raw-admin transfer
  (`_seat`/`test_Fork_ControllerSeatingAndUnseatedRollback`) simulates the
  composition only — it is not a GaugeAdder seating receipt
  (docs/DEPLOYMENT-PINS.md lines 20, 53-56; docs/OPERATIONS.md step 3).
* The pinned controller's EMPTY-data absence revert observed at the fork
  does NOT establish an unconditional empty-revert acceptance rule
  (R05/Q1 law): offline the supported controller uses `GaugeNotAdded`;
  neither encoding proves the production composition's failure encoding —
  cell W6 below measures it.
* Code presence at construction is wiring validation, not authority.

## Witness plan — exact cells to be produced for the selected graph

| Cell | Witness | Produces | Status |
| --- | --- | --- | --- |
| W1 | Selection record | One recorded current fixed block (chain id/number/hash/timestamp) + full runtime bytes & keccak + verified source for the controller and any proxy implementation, per docs/DEPLOYMENT-PINS.md §Re-verification procedure; `cast` receipts incl. `admin`, `n_gauge_types`, a positive `gauge_types` readback of an existing gauge | PRE-ACTIVATION GATE — OPEN |
| W2 | add_gauge authorization proof | One selected actual caller/target/grant/authority table; pre-grant negative and post-grant positive FUNDED SIMULATIONS on the exact candidate/composition, with caller/target/calldata reachability and full rollback attributed; actual on-chain grant tx/block/calldata and role readback are separately required before production unpause (see phase supplement) | PRE-ACTIVATION GATE — OPEN |
| W3 | DAO-route retention | Selected-composition simulation of the DAO's existing addition routes on their existing terms after the proposed W2 grants (named governance action + observed effect); actual grant/role readback before activation | PRE-ACTIVATION GATE — OPEN |
| W4 | Seated-wrapper route retention | Same phase-labelled proof for the seated-wrapper route, with exact retained caller/authority/selector and observed effect | PRE-ACTIVATION GATE — OPEN |
| W5 | Typed-membership certificate | One authorized paid admission SIMULATION at the selected composition recording immediate canonical `gauge_types` membership including a valid type-zero case, exact `add_gauge(gauge, type, 0)` call, raw `NewGauge` decode and gauge-count advance (independent index, not shared with a non-zero-type row); first paid broadcast is post-authorization evidence, not a prerequisite paid success while paused | PRE-ACTIVATION GATE — OPEN |
| W6 | Absence-failure encoding | Measured revert data shape of `gauge_types` for an absent gauge AT THE SELECTED PRODUCTION TARGET (empty vs custom), recorded, not assumed; the product keeps the bare-catch rule (success → `ControllerRegistryOccupied`; caught failure → continue; the add+postcheck stay the health proof) | PRE-ACTIVATION GATE — OPEN |
| W7 | Authorized bind/enablement owners | Named actual owners for atomic deploy/bind, completed handoffs, binding and immutable/config readbacks, actual grants, and explicit final unpause approval; approve W1–W6 selected-composition evidence and W8 before unpause, as well as the independent FD/venue/operations gates; mutable state is rechecked at enablement | PRE-ACTIVATION GATE — OPEN |
| W8 | Unseated negative against selected production composition | Funded pre-grant SIMULATION, with the local instance explicitly unpaused, proving the actual lister-to-target `add_gauge` call reaches the real authorization failure and complete rollback; revert bytes alone or pause rejection cannot substitute | PRE-ACTIVATION GATE — OPEN |

Once W1–W8 are approved for a selected graph, THIS table becomes the
admission-proof record ("replace ambiguous call-graph descriptions with
that graph and its witness"), and the public §Production controller
composition section in docs/DEPLOYMENT-PINS.md then states the selected
caller/role graph directly. Until then the public docs stay as written:
they name what is NOT certified and point here as the owner-held gate
file.

## Offline counterpart (behaviour, not authority)

The offline lane witnesses (`test_PaidListingUsesZeroWeightAndMembershipOnly`
cells (a)-(d), TF identity 4 poison cells) exercise core behaviour against
disclosed fixtures with exact named errors (CX-NEG strengthens the
occupied cell). They are NOT production approvals; the pinned-fork funded
pre-seating rollback is the witnessed composition at the regression pin
(`test_Fork_ControllerSeatingAndUnseatedRollback`, cited in
docs/DEPLOYMENT-PINS.md §Production controller composition).

## r3gate status and phase supplement — PAO-CTL

Current product: `d88d633c64fde7b3f37e29d846f744747186a688`.
Authority: `review/r3gate/RULING.md` §§2–3, C02 (DEFER production
composition/certificate; no speculative builder implementation).

SATISFIED-TRACKING / ACTIVATION-OPEN. The r2 carrier already satisfied the
present obligation to register this gate and its witnesses. No graph, role
grant, retained-route proof or deployment has been approved by that status.
This authority supplement is selectively published under r3gate; complete
execution/deployment evidence remains owner-held. Historical r2 receipts
retain their original phase and scope.

The immutable target named above is the intended controller pin, not a solved
production role graph. Before activation, the deployment operator must supply
one graph naming every caller, target, selector, grant and grant authority;
the governance release authority must approve it and both retained routes.
An intermediary, new implementation or different immutable target is itself
new review scope. If no graph meets the current law, activation stays HOLD;
the table is not permission to weaken membership, occupancy or governance.

W2/W5/W8 preparation is explicitly simulation against the selected composition
and current fixed state. For the negative, only the disposable simulated
instance is unpaused and all earlier admission prerequisites are valid; bind
the actual `add_gauge` frame and real authorization failure, plus unchanged
fee/record/liability/membership/approvals/receipts/events. The existing
regression negative (`test/fork/ForkAdmission.t.sol:42-57`) checks revert
bytes and rollback but has no counterpart of the positive's exact call
expectation at :79. That reachability attribution remains owed for the
selected-composition proof; it is not inferred from empty revert bytes.

After simulation/role/route approval, record actual authorized deployment,
binding, ownership and grants, and re-read state before the owner authorizes
production unpause. Only then can the first real paid trial occur. That first
unpause IS activation of the permissionless lane, not an on-chain restricted
trial mode; its authority must explicitly accept the simulation/broadcast
phase boundary and all separate deployment gates. Label the later funded
broadcast and its observed effects honestly. No successful paid broadcast is
required while paused, and no unauthorized unpause is licensed to acquire
evidence. Real venue/destination acceptance remains independently required.

Future design rounds carry PAO-CTL without re-counting the same open selection
as a simplification. Missing or contradictory graph evidence at activation,
loss of either retained route, noncanonical membership, or a claim that a
simulation is a real grant is a substantive gate failure under r3gate.
