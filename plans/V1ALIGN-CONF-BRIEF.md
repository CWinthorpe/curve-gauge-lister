# REVIEW LEG BRIEF — curve-gauge-lister / v1align-conf (bounded conformance: no-bounty V1 parity)

Bounded conformance, clinical register. Authority: plans/V1ALIGN-PLAN.md +
V1ALIGN-WITNESSES.md + V1ALIGN-WITNESS-INVENTORY.json + V1ALIGN-MANIFEST.json
+ V1ALIGN-DOC-DELTAS.md. Candidate: main @ b37e533 (orchestrator verified:
77/77 offline incl unreachable-RPC repeat, 13/13 fork on the same pin, zero
bounty references in contracts/, tree clean).

Verify cell by cell against the authority; re-run, don't re-read alone:
1. Constructor: seventh-arg validator, WrongChain FIRST, paused-at-init,
   first six args byte-named unchanged; no bounty slot, no setter/default.
   ABI/recursive layout vs V1ALIGN-MANIFEST.json under both profiles
   (full entry objects, not selector counts).
2. Confiscation law §2.2: is_killed()-only oracle, inline _confiscate
   intact, all-R-to-FD, no settlement-path reads of validator/ballot/report;
   gauge-read failure reverts; terminal-after-observed-kill.
3. §2.3 protections: adapters + shared interfaces + SafeToken byte-identical
   vs baseline hashes in the manifest; owner-only one-time setLister
   preserved; bounty-named history did not remove any composed protection
   (spot-check the deletion closure: nothing surviving imports anything
   deleted; test/bountyfix02/ retained).
4. Witness inventory truth: every RETAINED offline 69 + fork 11 identity
   executed and green by name AND compiled signature; the 8+2 trust
   identities ported with matrix cells; RETIRED rows actually gone; no
   silent drops or inherited-green fakes; fuzz counted once.
5. REPRODUCE two G6 falsifiers yourself in a disposable copy (one trust
   mutant + one confiscation/accounting mutant): pristine green, mutant red
   at the named frame, restored green. Other rows must cite real receipts.
6. Docs: README/proposal/ABI/OPERATIONS/PINS match DOC-DELTAS verbatim and
   describe the no-bounty product truthfully; no stale reporter/stake/claim
   economics anywhere in shipping paths; historical evidence untouched.
7. Sizes: independent decode of deployedBytecode incl metadata for the
   three deployables <= 24,576 both profiles; creation-size sanity.

Verdict: CONFORMS → certify NO-BOUNTY V1 ACCEPTED (deployment-pending), or
list exact gaps. Commit review/V1ALIGN-CONF.md `v1align-conf: <verdict>
<sha>` + push. Print `DONE v1align-conf` as your final line.
