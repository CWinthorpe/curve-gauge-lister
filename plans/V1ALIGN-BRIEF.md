# AUTHORITY LEG BRIEF — curve-gauge-lister / v1align (V1↔V2 gap review: bring V1 to production parity minus the bounty system)

Authority leg, clinical register. Operator order (intent verbatim): proposal
feedback says remove the bounty system and let the DAO handle kills on its
own; the V1 contract never had the bounty, but may be stale versus V2.
Review the differences and rule what must be brought into V1 to get it up
to date with V2 — EXCLUDING the bounty system — while fully maintaining the
DAO confiscation path (is_killed()-only oracle, all unspent escrow to the
pinned crvUSD FeeDistributor under the mandatory safe-accounting law).

Repo: /home/winny/curve-gauge-lister, main. Candidate HEAD.

## Your work
1. SYSTEMATIC DIFF V1 (contracts/CurveGaugeLister.sol + shared libraries/
   interfaces/adapters as composed) vs V2 (CurveGaugeListerV2.sol + bounty
   hooks): enumerate every divergence — constructor surface, admission
   checks, settlement/confiscation paths, adapter binding, guards, events,
   errors, storage, sizes. Classify each: BOUNTY-COUPLED (stays out of V1),
   PRODUCTION-PARITY-MISSING (must port), or HISTORICAL-NEUTRAL. Known
   candidates to adjudicate, not assume: (a) V2's trusted-factory paid
   admission gate (GaugeValidator 0x8888..., validateGauge, UntrustedGauge/
   TrustedGaugeCheckFailed, chain-1+code guards, eighth-constructor pattern)
   — operator's newest product guarantee on the 10K paid lane, presumably
   ports; (b) chain-1 constructor guard V1 lacks; (c) auditfix001 items V1
   already has — verify byte-level, do not assume; (d) anything V2 drifted
   in settlement, epoch math, or events.
2. RULE the shape: amend CurveGaugeLister in place (frozen-by-discipline
   only; never deployed — acceptable if you re-verify) vs new file — your
   call, state reasoning. Decide fate of V2 + GaugeBounty + bounty tests:
   recommend removal from the shipping tree vs quarantine, keeping the
   audit trail coherent for a public repo (proposal feedback is public too).
3. Update the plan surface: target ABI/manifest, constructor signature,
   witness matrix (all surviving V1 identities kept; new trust-gate
   identities ported from V2's TrustedFactory suite with bounty dependencies
   stripped; falsifier rows named), census re-derivation (state expected
   counts honestly, do not target a number), gates incl. fork suite, size
   under both profiles with the 24,576 ceiling check.
4. DOC-DELTAS: the public proposal (docs/CURVE-PROPOSAL.md), README, ABI,
   operations and pins must describe the no-bounty product truthfully —
   kill economics become all-FD confiscation only; bounty sections deleted,
   not hedged. Draft the exact replacement text in a deltas file; executors
   apply verbatim.
5. Release the qwen work order (numbered packages, one commit each) or hold
   with the precise blocker if the diff surfaces something needing operator
   decision.

You write plans/+review/ only; no product edits. Commit `v1align: <summary>`
+ push. Print `DONE v1align` as your final line.
