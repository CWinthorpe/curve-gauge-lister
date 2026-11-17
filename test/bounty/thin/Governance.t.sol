// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BountyFixture} from "../BountyFixture.sol";
import {Vm} from "../../TestBase.sol";
import {GaugeBounty} from "../../../contracts/GaugeBounty.sol";
import {CurveGaugeListerV2} from "../../../contracts/CurveGaugeListerV2.sol";
import {IGaugeBounty} from "../../../contracts/interfaces/IGaugeBounty.sol";
import {IAgent, IKillProxy} from "../../../contracts/interfaces/IBountyGovernance.sol";
import {IOwnershipVoting} from "../../../contracts/interfaces/IOwnershipVoting.sol";
import {ReportView, StakeState} from "../../../contracts/bounty/BountyTypes.sol";
import {GovernanceGauge} from "../mocks/MockBountyGovernance.sol";
import {MockOwnershipVoting} from "../mocks/MockOwnershipVoting.sol";
import {BountyRead} from "../../../contracts/libraries/BountyRead.sol";

/// @notice Thin canonical-kill recognition suite (plans/BOUNTY-THIN-PLAN.md
/// §7.2 rows G01-G09): one computed canonical hash, honest model execution
/// through Voting -> CallsScript -> Agent -> proxy/gauge, one-shot callbacks
/// with no token or FD movement, bounded malformed-read tolerance and the
/// expiry semantics of the 7+7 timers. The banked middle-call rollback
/// regression is retained (G04).
contract ThinGovernanceTest is BountyFixture {
    struct Live {
        CurveGaugeListerV2 core_;
        GaugeBounty b;
        address gauge;
        bytes32 id;
        uint256 voteId;
    }

    address internal _mega;

    function setUp() public {
        setupBountyWorld();
    }

    // ---------------------------------------------------------------- glue

    function _proposed() internal returns (Live memory L) {
        (L.core_, L.b) = deployBoundPair();
        return _proposedOn(L);
    }

    function _proposedOn(Live memory L) internal returns (Live memory) {
        (, L.gauge,) = listBountyEligible(L.core_);
        _nonce += 1;
        bytes32 eh = keccak256(abi.encode("gov-evidence", L.gauge, block.number, block.timestamp, _nonce));
        (L.id, L.voteId) = submitBeneficiaryBallot(L.b, address(L.core_), L.gauge, reporter, _nonce, eh);
        require(uint256(L.b.getReport(L.id).phase) == 1, "gov: admitted");
        return L;
    }

    uint256 internal _nonce;

    function _fund(GaugeBounty b, address who) internal {
        crvUSD.mint(who, STAKE);
        approveCrvUsd(who, address(b), STAKE);
    }

    function _spaceFdCursor() internal {
        if (block.timestamp <= fd.last_token_time() + 86_400) {
            fd.setLastTokenTime(block.timestamp - 86_401);
        }
    }

    /// @dev ONE dominant YES voter for the whole test (per-case whales would
    /// dilute the strict support/quorum ratios against accumulated supply).
    function _tallyPass(Live memory L) internal {
        if (_mega == address(0)) {
            _mega = address(uint160(0x6FA1CE01));
            giveVePower(_mega, 5_000_000e18);
        }
        vm.prank(_mega);
        voting.vote(L.voteId, true);
    }

    function _execute(Live memory L, uint256 when) internal {
        vm.warp(when);
        vm.prank(stranger);
        voting.executeVote(L.voteId);
    }

    /// @dev Independent canonical builder: 0x00000001 then three
    /// Agent(20)||uint32(len)||calldata entries, ordinary ABI encoding.
    function _canonical(GaugeBounty b, address agentAddr, address killProxyAddr, address gauge, bytes32 id)
        internal
        view
        returns (bytes memory)
    {
        bytes memory d1 = abi.encodeCall(
            IAgent.execute, (address(b), 0, abi.encodeCall(IGaugeBounty.creditBallot, (id, b.getReport(id).reporter)))
        );
        bytes memory d2 =
            abi.encodeCall(IAgent.execute, (killProxyAddr, 0, abi.encodeCall(IKillProxy.set_killed, (gauge))));
        bytes memory d3 =
            abi.encodeCall(IAgent.execute, (address(b), 0, abi.encodeCall(IGaugeBounty.recognizeKill, (id))));
        // (creditBallot carries the explicit beneficiary word; the reporter
        // argument is fetched from stored state, never supplied.)
        return bytes.concat(
            bytes4(0x00000001),
            bytes20(agentAddr),
            bytes4(uint32(d1.length)),
            d1,
            bytes20(agentAddr),
            bytes4(uint32(d2.length)),
            d2,
            bytes20(agentAddr),
            bytes4(uint32(d3.length)),
            d3
        );
    }

    // ------------------------------------------------------------------ G01

    function test_Thin_CanonicalHashBinding() public {
        Live memory L = _proposed();
        bytes memory honest = _canonical(L.b, address(agent), address(killProxy), L.gauge, L.id);

        // Positive control: the honest script is byte-identical to what the
        // bound vote recorded, and execution recognizes.
        assertEq(keccak256(voting.scriptOf(L.voteId)), keccak256(honest), "recorded script is canonical");
        _tallyPass(L);
        _execute(L, L.b.getReport(L.id).voteEnd);
        assertEq(uint256(L.b.getReport(L.id).phase), 3, "canonical execution recognized");

        // Nine mutation classes; each builds its own fresh case and tampers
        // exactly one element of that case's canonical script. Hash equality
        // binds the whole sequence — no byte-word proof scaffold involved.
        _mutateOne("report", 0);
        _mutateOne("gauge", 1);
        _mutateOne("app", 2);
        _mutateOne("target", 3);
        _mutateOne("order", 4);
        _mutateOne("value", 5);
        _mutateOne("length", 6);
        _mutateOne("domain", 7);
        _mutateOne("trailing", 8);
    }

    function _mutateOne(string memory cls, uint8 kind) private {
        Live memory L = _proposed();
        bytes memory honest = _canonical(L.b, address(agent), address(killProxy), L.gauge, L.id);
        bytes memory tampered = honest;
        if (kind == 0) {
            // Wrong report identity inside the creditBallot/recognizeKill args.
            tampered = _swapWord(honest, bytes32(uint256(L.id)), bytes32(uint256(L.id) ^ 0xBAD));
        } else if (kind == 1) {
            // Wrong gauge in the set_killed argument.
            tampered = _swapWord(honest, bytes32(uint256(uint160(L.gauge))), bytes32(uint256(0x6A650001)));
        } else if (kind == 2) {
            // Wrong executed contract (bounty) inside entry 1's execute args.
            tampered = _swapWord(honest, bytes32(uint256(uint160(address(L.b)))), bytes32(uint256(0xA0000001)));
        } else if (kind == 3) {
            // Wrong executed target (proxy) inside entry 2's execute args.
            tampered = _swapWord(honest, bytes32(uint256(uint160(address(killProxy)))), bytes32(uint256(0x7A200001)));
        } else if (kind == 4) {
            tampered = _orderSwap(honest); // recognize before the kill lands
        } else if (kind == 5) {
            tampered = _flipByte(honest, 4 + 24 + 4 + 32 + 16); // nonzero ETH value word
        } else if (kind == 6) {
            tampered = _flipByte(honest, 4 + 20 + 3); // uint32 framing length
        } else if (kind == 7) {
            tampered = _flipByte(honest, 3); // script type prefix (domain)
        } else {
            tampered = bytes.concat(honest, bytes1(0x00)); // trailing byte
        }
        voting.setScriptFor(L.voteId, tampered);
        _tallyPass(L);
        // Advance to a GENUINELY executable ballot: closed window, passed
        // tally, unexecuted (thin §7.2 G01 / §8.4 — the negatives must reach
        // script execution, never pass at the ballot-open guard).
        vm.warp(L.b.getReport(L.id).voteEnd);
        assertTrue(voting.canExecute(L.voteId), "tampered ballot is closed and executable");
        (bool execOk, bytes memory ret) =
            address(voting).call(abi.encodeCall(MockOwnershipVoting.executeVote, (L.voteId)));
        if (!execOk) {
            // Malformed framing may legitimately revert the whole ballot —
            // but never through the open guard: that would be a vacuous pass.
            assertTrue(
                keccak256(ret) != keccak256(abi.encodeWithSignature("Error(string)", "still open")),
                "negative never rests on the still-open guard"
            );
        }
        // The REAL result of executeVote: the ballot's executed flag exists
        // iff the call completed (atomic script failure rolls it back).
        (, bool ballotExecuted,,,,,,,,) = voting.getVote(L.voteId);
        assertEq(ballotExecuted, execOk, "executeVote result and ballot state agree");
        ReportView memory rv = L.b.getReport(L.id);
        cls;
        // Intended non-attribution for every mutation class: a completed
        // tampered run closes WITHOUT award; a reverted run leaves the case
        // untouched. Never armed, recognized or rewarded.
        if (execOk) {
            assertTrue(uint256(rv.phase) == 1 || uint256(rv.phase) == 7, "tampered run never attributes");
        } else {
            assertEq(uint256(rv.phase), 1, "reverted tampered run leaves the case untouched");
        }
        assertEq(rv.rewardCredit, 0, "no credit without the exact canonical hash");
        (,, bool eligible) = L.b.rewardTerms(L.gauge);
        assertFalse(eligible, "tampered script earns no entitlement");
        // The bond really comes back: take the case to its local terminal
        // endpoint and recover the full 1,000 — never "still held while open".
        if (uint256(rv.phase) == 1) {
            vm.warp(rv.executeBy + 1);
        }
        (uint256 stake0, uint256 reward0) = L.b.claim(L.id);
        assertEq(stake0, STAKE, "tamper never costs the reporter the bond");
        assertEq(reward0, 0, "no reward from a tampered script");
    }

    /// @dev bountyconf3 finding 2(a): the hash-sensitivity half of the
    /// G01 obligation. The tampered script below is a strict SUPERSET of the
    /// canonical one: the same three actions, same targets, same arguments,
    /// same order, plus ONE extra well-framed Agent leg that can change
    /// nothing (a view-only `getReport(id)` read of the case's own report).
    /// It therefore parses, executes to completion, really drives the proxy
    /// kill and is observed with the kill flag TRUE — every guard in the
    /// shared `_observationPasses` chain except the canonical whole-script
    /// comparison (`rec.scriptHash == keccak256(_killScriptOf(...))`) is
    /// satisfied. Removing that comparison ALONE (product-only scratch
    /// mutation `return true`) makes this committed case FAIL: the
    /// non-canonical script arms, recognizes and earns the entitlement. The
    /// committed product refuses it.
    function test_Thin_HashGuardSoleDefense_FailsWhenBypassed() public {
        Live memory L = _proposed();
        bytes memory honest = _canonical(L.b, address(agent), address(killProxy), L.gauge, L.id);
        assertEq(honest.length, 696, "canonical script: prefix + 252 + 220 + 220 framed entries");
        // Extra inert leg: the same Agent route, a view read of the very
        // report the script is about. No token, no FD, no state transition.
        bytes memory idle =
            abi.encodeCall(IAgent.execute, (address(L.b), 0, abi.encodeCall(IGaugeBounty.getReport, (L.id))));
        assertEq(idle.length, 196, "inert leg reuses the canonical execute payload");
        bytes memory tampered = bytes.concat(honest, bytes20(address(agent)), bytes4(uint32(idle.length)), idle);
        assertEq(tampered.length, honest.length + 220, "inert leg appends exactly one framed entry");
        assertTrue(keccak256(tampered) != keccak256(honest), "bound script is not the canonical script");
        // The canonical prefix survives: the refusal must come from the
        // whole-script comparison, never from a framing/domain failure.
        assertEq(_scriptType(tampered), uint256(0x00000001), "hash-guard case keeps the domain");
        _runAndAssertRefused(L, tampered, "canonical hash guard alone refuses the non-canonical script");
    }

    /// @dev bountyconf3 finding 2(b): the order cell must exercise
    /// SEQUENCE, not domain selection. This is the same ballot the G01 order
    /// class tampers, isolated so a scratch guard relaxation can be credited
    /// to it exactly: `_orderSwap` keeps the `0x00000001` CallsScript domain
    /// prefix verbatim and swaps two COMPLETE 220-byte action blocks, so the
    /// script parses, all three Agent legs execute and the kill really lands.
    /// The refused award comes from the ordered-observation law alone —
    /// `recognizeKill` requires the CURRENT flag to be true, which it is not
    /// yet when the recognition leg precedes the kill leg. Falsifier (scratch,
    /// product-only): with the canonical hash comparison bypassed alone this
    /// cell stays GREEN (the flag ordering law still refuses it); additionally
    /// relaxing `killed == expectKilled` to `true` turns THIS cell red on the
    /// named assertion below.
    function test_Thin_OrderCellExercisesSequenceNotDomain() public {
        Live memory L = _proposed();
        bytes memory honest = _canonical(L.b, address(agent), address(killProxy), L.gauge, L.id);
        bytes memory tampered = _orderSwap(honest);
        // Well-framed, same length, domain prefix intact, and the ACTIONS
        // are permuted: only the order differs from canonical.
        assertEq(tampered.length, 696, "reorder preserves the framed length");
        assertEq(_scriptType(tampered), uint256(0x00000001), "reorder keeps the CallsScript domain");
        assertEq(_scriptType(honest), uint256(0x00000001), "canonical domain control");
        assertTrue(keccak256(tampered) != keccak256(honest), "reordered script differs from canonical");
        assertEq(keccak256(_orderSwap(honest)), keccak256(tampered), "reorder is deterministic");
        uint256[3] memory lens = [uint256(228), uint256(196), uint256(196)];
        for (uint256 i = 0; i < 3; ++i) {
            (address tgt, uint32 len) = _entryFrame(tampered, i);
            assertEq(
                uint256(uint160(tgt)), uint256(uint160(address(agent))), "every entry still targets the bound Agent"
            );
            assertEq(uint256(len), lens[i], "every entry keeps its declared payload length");
        }
        assertEq(_selectorAt(tampered, 0), _selectorAt(honest, 0), "position 1 is still creditBallot");
        assertEq(_selectorAt(tampered, 1), _selectorAt(honest, 2), "position 2 is the LATER recognizeKill leg");
        assertEq(_selectorAt(tampered, 2), _selectorAt(honest, 1), "position 3 is the LATER proxy-kill leg");
        _runAndAssertRefused(L, tampered, "out-of-order recognition is refused by the sequence law");
    }

    /// @dev Shared tail for both sole-defense cells: bind the tampered
    /// script, close and pass the ballot, run it for real and require (a)
    /// genuine execution to completion, (b) the kill-proxy observation the
    /// product reads to be TRUE, so the named guard alone is what refuses
    /// attribution, and (c) the full non-attribution/refund oracle.
    function _runAndAssertRefused(Live memory L, bytes memory tampered, string memory refusal) private {
        voting.setScriptFor(L.voteId, tampered);
        _tallyPass(L);
        vm.warp(L.b.getReport(L.id).voteEnd);
        assertTrue(voting.canExecute(L.voteId), "sole-defense ballot is closed and executable");
        (bool execOk, bytes memory ret) =
            address(voting).call(abi.encodeCall(MockOwnershipVoting.executeVote, (L.voteId)));
        // A well-framed tamper must RUN: refusing it through the executor
        // domain or the parser would make the cell test framing instead.
        assertTrue(execOk, string(abi.encodePacked("tampered script must run, not fail framing: ", _why(ret))));
        (, bool ballotExecuted,,,,,,,,) = voting.getVote(L.voteId);
        assertTrue(ballotExecuted, "tampered script really completed the ballot");
        // Every entry succeeded, so the shared flag observation the product
        // checks at recognize time was satisfied with killed == TRUE.
        assertTrue(GovernanceGauge(L.gauge).is_killed(), "the canonical kill leg landed: flag observation is TRUE");
        ReportView memory rv = L.b.getReport(L.id);
        assertEq(uint256(rv.phase), 7, refusal);
        assertEq(rv.rewardCredit, 0, "no credit while the guard holds");
        (,, bool eligible) = L.b.rewardTerms(L.gauge);
        assertFalse(eligible, "no entitlement while the guard holds");
        (uint256 stake0, uint256 reward0) = L.b.claim(L.id);
        assertEq(stake0, STAKE, "the refusal still refunds the bond");
        assertEq(reward0, 0, "no reward from a refused script");
    }

    /// @dev Short, bounded rendering of a failed call's revert data for the
    /// two labels above (an assertion failure must name the mechanism).
    function _why(bytes memory ret) private pure returns (string memory) {
        if (ret.length == 0) {
            return "empty";
        }
        bytes32 w;
        assembly {
            w := mload(add(ret, 0x20))
        }
        return string(abi.encodePacked("0x", _hex16(w)));
    }

    function _hex16(bytes32 v) private pure returns (string memory) {
        bytes16 d = bytes16("0123456789abcdef");
        bytes memory out = new bytes(64);
        for (uint256 i = 0; i < 32; ++i) {
            uint8 b = uint8(v[i]);
            out[2 * i] = d[b >> 4];
            out[2 * i + 1] = d[b & 0x0F];
        }
        return string(out);
    }

    /// @dev Ordinary memory copy of one complete block of a script.
    function _slice(bytes memory s, uint256 start, uint256 n) private pure returns (bytes memory out) {
        require(start + n <= s.length, "gov: slice out of bounds");
        out = new bytes(n);
        for (uint256 i = 0; i < n; ++i) {
            out[i] = s[start + i];
        }
    }

    /// @dev The four-byte CallsScript type prefix of a memory script, as the
    /// numeric big-endian value (0x00000001 for the canonical domain).
    function _scriptType(bytes memory s) private pure returns (uint256 t) {
        require(s.length >= 4, "gov: script shorter than the domain prefix");
        assembly {
            t := and(shr(224, mload(add(s, 0x20))), 0xffffffff)
        }
    }

    /// @dev Entry `n`'s (0-based) target and declared calldata length.
    function _entryFrame(bytes memory s, uint256 n) private pure returns (address target, uint32 len) {
        uint256[3] memory e = [uint256(252), uint256(220), uint256(220)];
        require(s.length == 4 + 252 + 220 + 220, "gov: canonical three-entry script");
        uint256 at = 4;
        for (uint256 i = 0; i < n; ++i) {
            at += e[i];
        }
        assembly {
            let w := mload(add(add(s, 0x20), at))
            target := shr(96, w) // big-endian bytes 0..19 of the entry
            len := and(shr(64, w), 0xffffffff) // big-endian bytes 20..23
        }
    }

    /// @dev The inner selector of entry `n`: Agent.execute calldata is
    /// 4-byte selector + 3 head words + length word, then the packed
    /// inner call, whose first four bytes are the action selector.
    function _selectorAt(bytes memory s, uint256 n) private pure returns (uint256 sel) {
        (, uint32 len) = _entryFrame(s, n);
        require(len == 228 || len == 196, "gov: canonical entry payload");
        uint256[3] memory e = [uint256(252), uint256(220), uint256(220)];
        uint256 at = 4;
        for (uint256 i = 0; i < n; ++i) {
            at += e[i];
        }
        at += 24 + 4 + 96 + 32;
        assembly {
            sel := and(shr(224, mload(add(add(s, 0x20), at))), 0xffffffff)
        }
    }

    /// @dev Genuine well-framed reorder: the `0x00000001` domain prefix is
    /// copied VERBATIM (bountyconf3 finding 2(b): the previous loop wrote
    /// into a zero-filled buffer and only filled from byte 4, so the script
    /// carried the `0x00000000` prefix and was refused by executor-domain
    /// selection — `ScriptExecutorMissing` — instead of testing sequence),
    /// and the two COMPLETE 220-byte action blocks are swapped:
    ///   creditBallot | set_killed | recognizeKill
    /// -> creditBallot | recognizeKill | set_killed
    /// Every entry keeps its own target, uint32 length and payload bytes, so
    /// the CallsScript parser accepts it and all three Agent legs run.
    function _orderSwap(bytes memory honest) private pure returns (bytes memory) {
        uint256 e1 = 252; // creditBallot entry: 20 + 4 + 228
        uint256 e = 220; // kill/recognize entries: 20 + 4 + 196
        require(honest.length == 4 + e1 + 2 * e, "gov: canonical three-entry script");
        return bytes.concat(_slice(honest, 0, 4 + e1), _slice(honest, 4 + e1 + e, e), _slice(honest, 4 + e1, e));
    }

    function _swapWord(bytes memory src, bytes32 needle, bytes32 repl) private pure returns (bytes memory) {
        bytes memory out = new bytes(src.length);
        for (uint256 i = 0; i < src.length; ++i) {
            out[i] = src[i];
        }
        for (uint256 i = 0; i + 32 <= src.length; ++i) {
            bytes32 w;
            assembly {
                w := mload(add(add(src, 0x20), i))
            }
            if (w == needle) {
                for (uint256 j = 0; j < 32; ++j) {
                    out[i + j] = repl[j];
                }
            }
        }
        return out;
    }

    function _flipByte(bytes memory src, uint256 at) private pure returns (bytes memory) {
        bytes memory out = new bytes(src.length);
        for (uint256 i = 0; i < src.length; ++i) {
            out[i] = src[i];
        }
        out[at] = bytes1(uint8(out[at]) ^ 0x01);
        return out;
    }

    // bountyfix01 V-L01 (test_Thin_AuditBallotMetadataIdentifiesReportAndGauge)
    // is RETIRED (plans/BOUNTY-REWORK-PLAN.md §2/§7): the product no longer
    // calls newVote or constructs its 161-byte description. Canonical-script
    // and beneficiary authentication remain in G01/G02 and the rework suite.

    // ------------------------------------------------------------------ G02

    function test_Thin_TallyIsNotExecution() public {
        Live memory L = _proposed();
        // Open guard: execution before the ballot end reverts outright.
        vm.prank(stranger);
        vm.expectRevert(bytes("still open"));
        voting.executeVote(L.voteId);

        // A tiny YES clears neither the 51% support nor the 30% quorum.
        address mite = address(uint160(0x6FA1CE99));
        giveVePower(mite, 100e18); // >0 power, far below the 51%/30% ratios
        vm.prank(mite);
        voting.vote(L.voteId, true);
        vm.warp(L.b.getReport(L.id).voteEnd);
        assertFalse(voting.canExecute(L.voteId), "strict ratios refuse");
        vm.prank(stranger);
        vm.expectRevert(MockOwnershipVoting.TallyFailed.selector);
        voting.executeVote(L.voteId);
        assertEq(uint256(L.b.getReport(L.id).phase), 1, "still Proposed after failed tally");

        // Passed-but-unexecuted on a FRESH case: the ballot is closed and
        // executable, yet the case earns nothing until execution.
        Live memory M = _proposed();
        _tallyPass(M); // votes while open
        vm.warp(M.b.getReport(M.id).voteEnd);
        assertTrue(voting.canExecute(M.voteId), "tally passed");
        assertFalse(M.b.resolve(M.id), "passed-unexecuted is not failure-by-default");
        assertEq(uint256(M.b.getReport(M.id).phase), 1, "Remains Proposed: no reward, no slash");
        assertEq(M.b.getReport(M.id).stakeState, uint8(StakeState.Bonded), "bond still held, never slashed");

        // Execution (not the tally) is what binds: run the real script.
        _execute(M, M.b.getReport(M.id).voteEnd);
        assertEq(uint256(M.b.getReport(M.id).phase), 3, "executed canonical recognized");
    }

    // ------------------------------------------------------------------ G03

    function test_Thin_ExecutedFalseToTrueRecognition() public {
        Live memory L = _proposed();
        // Callback authority is exactly the configured Agent.
        vm.prank(stranger);
        vm.expectRevert(IGaugeBounty.NotAgent.selector);
        L.b.creditBallot(L.id, reporter);
        vm.prank(daoOwner);
        vm.expectRevert(IGaugeBounty.NotAgent.selector);
        L.b.recognizeKill(L.id);

        // Pre-kill: the gauge really is false before the script runs.
        assertFalse(GovernanceGauge(L.gauge).is_killed(), "false before");
        uint256 fdBefore = crvUSD.balanceOf(address(fd));
        uint256 bountyBefore = crvUSD.balanceOf(address(L.b));
        (int128 lockAmt,) = escrow.locked(address(L.b));
        lockAmt;

        _tallyPass(L);
        _execute(L, L.b.getReport(L.id).voteEnd); // real CallsScript/Agent/proxy path

        // Post-kill: true, recognized, bond refundable, rewardTerms live.
        assertTrue(GovernanceGauge(L.gauge).is_killed(), "true after");
        assertEq(uint256(L.b.getReport(L.id).phase), 3, "Recognized");
        assertEq(uint8(L.b.getReport(L.id).stakeState), uint8(StakeState.Refundable), "bond refundable");
        (bytes32 slotId, address slotRep, bool eligible) = L.b.rewardTerms(L.gauge);
        assertEq(slotId, L.id, "slot names this case");
        assertEq(slotRep, reporter, "fixed reporter");
        assertTrue(eligible, "unallocated entitlement");
        assertEq(crvUSD.balanceOf(address(fd)), fdBefore, "no FD movement in callbacks");
        assertEq(crvUSD.balanceOf(address(L.b)), bountyBefore, "no token movement in callbacks");
    }

    // ------------------------------------------------------------------ G04

    function test_Thin_MiddleCallRollback() public {
        // Banked regression retained (thin §5 X07): if the actual proxy call
        // fails, the ENTIRE executeVote rolls back — including both
        // attribution observations (the arm from prepare and the recognition
        // state), the executed flag and the kill itself.
        Live memory L = _proposed();
        _tallyPass(L);
        // Break the middle entry only: the proxy demands dao()==agent; move
        // the factory admin so GovernanceGauge.set_killed rejects the proxy.
        address fakeAdmin = actor("fakeAdmin");
        factory.setAdmin(fakeAdmin);
        vm.warp(L.b.getReport(L.id).voteEnd);
        vm.prank(stranger);
        vm.expectRevert(); // EntryFailed bubbles through CallsScript/Agent/Voting
        voting.executeVote(L.voteId);
        factory.setAdmin(address(killProxy)); // restore the honest route

        assertFalse(GovernanceGauge(L.gauge).is_killed(), "kill rolled back");
        (, bool executed,,,,,,,,) = voting.getVote(L.voteId);
        assertFalse(executed, "executed flag rolled back with the transaction");
        ReportView memory rv = L.b.getReport(L.id);
        assertEq(uint256(rv.phase), 1, "attribution observations rolled back to Proposed");
        assertEq(rv.stakeState, uint8(StakeState.Bonded), "bond still held (live offer outstanding)");
    }

    // ------------------------------------------------------------------ G05

    function test_Thin_EmergencyBeforePrepare() public {
        Live memory L = _proposed();
        // FD unavailable for the whole emergency window.
        fd.setLastTokenTime(block.timestamp - 40 * WEEK);
        // Independent emergency kill, no bounty involvement at all.
        vm.prank(emergencySafe);
        killProxy.set_killed(L.gauge);
        assertTrue(GovernanceGauge(L.gauge).is_killed(), "emergency landed");

        // The pending case's later canonical execution sees CURRENT true at
        // prepare: no award (a pending report cannot take half of an
        // independent emergency kill).
        _tallyPass(L);
        _execute(L, L.b.getReport(L.id).voteEnd);
        assertEq(uint256(L.b.getReport(L.id).phase), 7, "pre-true flag: NoAward");
        (uint256 stake0,) = L.b.claim(L.id);
        assertEq(stake0, STAKE, "bond refundable anyway");

        // Later all-FD seizure remains possible once the FD is healthy:
        // current true flag controls, buckets route entirely to the FD.
        fd.setLastTokenTime(block.timestamp);
        _spaceFdCursor();
        uint256 rem = L.core_.getListing(L.gauge).remaining;
        uint256 fdBefore = crvUSD.balanceOf(address(fd));
        vm.prank(stranger);
        uint256 gross = L.core_.confiscate(L.gauge);
        assertEq(gross, rem, "full remainder seized");
        assertEq(L.core_.getListing(L.gauge).reporterReward, 0, "no reporter leg");
        assertEq(crvUSD.balanceOf(address(fd)) - fdBefore, rem, "FD took everything");
    }

    // ------------------------------------------------------------------ G06

    function test_Thin_BoundedReadFaultsDoNotBlockKill() public {
        // Gauge flag classes: revert, short return, oversized return bomb,
        // and gas-burning read — each on a FRESH case.
        _readFaultCell(1, 0, "flag revert");
        _readFaultCell(2, 0, "flag short");
        _readFaultCell(3, 0, "flag bomb");
        _readFaultCell(4, 0, "flag gas");
        // Voting record classes: revert, malformed, huge offset, oversized
        // tail, invalid boolean — the nine specified malformed-read classes
        // of §7.2 G06 (four flag faults plus five record faults).
        _readFaultCell(0, 1, "getVote revert");
        _readFaultCell(0, 2, "getVote malformed");
        _readFaultCell(0, 4, "getVote huge offset");
        _readFaultCell(0, 5, "getVote oversized tail");
        _readFaultCell(0, 6, "getVote invalid bool");
        // The forged-executed-flag cell is a WELL-FORMED control, not one of
        // the malformed classes: it keeps the successful non-obstruction
        // witness and is asserted with its own honest oracle, so a
        // recognition regression can never satisfy the malformed cells.
        _wellFormedFlagsControl();
    }

    /// @dev One specified malformed-read cell: the middle kill must land and
    /// the case must close WITHOUT award — no entitlement, no credit and the
    /// bond refundable through the real claim (thin §3.1:105, §7.2 G06).
    function _readFaultCell(uint8 flagFault, uint8 voteFault, string memory label) private {
        Live memory L = _proposed();
        _tallyPass(L);
        if (flagFault != 0) {
            GovernanceGauge(L.gauge).setFlagFault(flagFault);
        }
        if (voteFault != 0) {
            voting.setGetVoteFault(voteFault);
        }
        vm.warp(L.b.getReport(L.id).voteEnd);
        assertTrue(voting.canExecute(L.voteId), "faulted ballot is genuinely executable");
        vm.prank(stranger);
        voting.executeVote(L.voteId); // must NOT revert: adequate gas, middle kill lands
        if (flagFault != 0) {
            GovernanceGauge(L.gauge).setFlagFault(0); // read the truth after the fault
        }
        if (voteFault != 0) {
            voting.setGetVoteFault(0);
        }
        assertTrue(GovernanceGauge(L.gauge).is_killed(), "outage never obstructs the kill");
        ReportView memory rv = L.b.getReport(L.id);
        // Required oracle for the specified fault classes: NoAward, never
        // Recognized/Rewarded/Armed, with zero credit and no entitlement.
        assertEq(uint256(rv.phase), 7, label);
        assertEq(rv.rewardCredit, 0, "no credit from a faulted observation");
        (,, bool eligible) = L.b.rewardTerms(L.gauge);
        assertFalse(eligible, "no entitlement after the faulted callback");
        (uint256 stake0, uint256 reward0) = L.b.claim(L.id);
        assertEq(stake0, STAKE, "refundable bond after the faulted callback");
        assertEq(reward0, 0, "no reward from a faulted callback");
    }

    /// @dev Separate well-formed control: an honest recorded ballot whose
    /// getVote merely FORGES executed=true over otherwise-valid data is the
    /// well-formed recognition class — distinguished from the malformed
    /// cells above (finding 3). It proves the faulted cells' NoAward is the
    /// read fault closing the case, not a world that never recognizes.
    function _wellFormedFlagsControl() private {
        Live memory L = _proposed();
        _tallyPass(L);
        voting.setGetVoteFault(3); // forged executed flag over the honest shape
        vm.warp(L.b.getReport(L.id).voteEnd);
        assertTrue(voting.canExecute(L.voteId), "control ballot is genuinely executable");
        uint256 fdBefore = crvUSD.balanceOf(address(fd));
        uint256 bountyBefore = crvUSD.balanceOf(address(L.b));
        vm.prank(stranger);
        voting.executeVote(L.voteId);
        voting.setGetVoteFault(0);
        assertTrue(GovernanceGauge(L.gauge).is_killed(), "control kill lands");
        ReportView memory rv = L.b.getReport(L.id);
        assertEq(uint256(rv.phase), 3, "well-formed observations do recognize");
        assertEq(uint8(rv.stakeState), uint8(StakeState.Refundable), "recognition makes the bond refundable");
        assertEq(rv.rewardCredit, 0, "recognition pays nothing");
        assertEq(crvUSD.balanceOf(address(fd)), fdBefore, "no FD movement in the control");
        assertEq(crvUSD.balanceOf(address(L.b)), bountyBefore, "no token movement in the control");
        (uint256 stake0, uint256 reward0) = L.b.claim(L.id);
        assertEq(stake0, STAKE, "control bond refunds");
        assertEq(reward0, 0, "control reward waits for actual allocation");
    }

    // ------------------------------------------------------------------ G07

    function test_Thin_CallbackReplayCannotRearm() public {
        Live memory L = _proposed();
        // recognize without any prepare: consumes the attempt, NoAward.
        vm.warp(L.b.getReport(L.id).voteEnd);
        vm.prank(address(agent));
        L.b.recognizeKill(L.id);
        assertEq(uint256(L.b.getReport(L.id).phase), 7, "unarmed recognize closes NoAward");

        // Replay on the consumed case cannot reopen: inert.
        vm.prank(address(agent));
        L.b.creditBallot(L.id, reporter);
        vm.prank(address(agent));
        L.b.recognizeKill(L.id);
        assertEq(uint256(L.b.getReport(L.id).phase), 7, "consumed case cannot rearm");

        // Fresh recognized case: later-block replays never erase it.
        Live memory M = _proposed();
        _tallyPass(M);
        _execute(M, M.b.getReport(M.id).voteEnd);
        assertEq(uint256(M.b.getReport(M.id).phase), 3, "recognized");
        vmx.roll(block.number + 2);
        vm.prank(address(agent));
        M.b.creditBallot(M.id, reporter); // stale replay: must not clear or downgrade
        vm.prank(address(agent));
        M.b.recognizeKill(M.id);
        assertEq(uint256(M.b.getReport(M.id).phase), 3, "recognized entitlement survives replays");
        // Fund it, then replay: Rewarded is never erased either.
        _spaceFdCursor();
        vm.prank(stranger);
        M.core_.confiscate(M.gauge);
        assertEq(uint256(M.b.getReport(M.id).phase), 4, "Rewarded");
        vm.prank(address(agent));
        M.b.recognizeKill(M.id);
        assertEq(uint256(M.b.getReport(M.id).phase), 4, "Rewarded entitlement survives replays");
        (, uint256 rew) = M.b.claim(M.id);
        assertTrue(rew > 0, "funded rights claimable after replays");

        // bountyreworkfix C2(b): isolated executed/closed sensitivity for the
        // shared observation chain. A closed, tallied but NEVER-executed
        // ballot arms nothing: the callback observes executed=false through
        // _matchingKillRecord and the case closes NoAward with the full bond
        // refundable — while the genuine canonical kill elsewhere in this
        // suite still runs and pays. Falsifier RW-GX deletes that executed
        // predicate (keeping open/timing/hash/flag guards) and fails at the
        // named assertion in _unexecutedBallotCannotArmCell.
        _unexecutedBallotCannotArmCell();
    }

    function _unexecutedBallotCannotArmCell() private {
        Live memory U = _proposed();
        _tallyPass(U); // real YES while open: the tally alone must not arm
        vm.warp(U.b.getReport(U.id).voteEnd); // closed and executable, never executed
        assertTrue(voting.canExecute(U.voteId), "cell ballot is closed and executable");
        (, bool execFlag,,,,,,,,) = voting.getVote(U.voteId);
        assertFalse(execFlag, "cell ballot is genuinely unexecuted at the callback");
        vm.prank(address(agent));
        U.b.creditBallot(U.id, reporter);
        assertEq(
            uint256(U.b.getReport(U.id).phase),
            7,
            "unexecuted ballot cannot arm: observed executed guard closes NoAward"
        );
        (uint256 stakeU, uint256 rewardU) = U.b.claim(U.id);
        assertEq(stakeU, STAKE, "unexecuted-ballot refusal still refunds the bond");
        assertEq(rewardU, 0, "no reward from an unexecuted ballot");
        (,, bool eligibleU) = U.b.rewardTerms(U.gauge);
        assertFalse(eligibleU, "no entitlement from an unexecuted ballot");
    }

    // ------------------------------------------------------------------ G08

    function test_Thin_ExecutionExpiryStillAllowsKill() public {
        // Inclusive endpoints: recognition is valid AT voteEnd and AT
        // executeBy; past executeBy the case expires locally and the bond is
        // refundable — yet late canonical execution still kills the gauge
        // and cannot earn or resurrect a reward.
        Live memory A = _proposed();
        _tallyPass(A);
        _execute(A, A.b.getReport(A.id).voteEnd); // exactly E: inclusive
        assertEq(uint256(A.b.getReport(A.id).phase), 3, "E-inclusive recognized");

        Live memory B = _proposed();
        _tallyPass(B);
        _execute(B, B.b.getReport(B.id).executeBy); // exactly K: inclusive
        assertEq(uint256(B.b.getReport(B.id).phase), 3, "K-inclusive recognized");

        Live memory C = _proposed();
        _tallyPass(C);
        uint256 K = C.b.getReport(C.id).executeBy;
        vm.warp(K + 1);
        // Local expiry first: claim's timeout cleanup closes and refunds.
        (uint256 stakeC,) = C.b.claim(C.id);
        assertEq(stakeC, STAKE, "executeBy+1 refund, dependency-free");
        assertEq(uint256(C.b.getReport(C.id).phase), 6, "Expired");
        // Late execution still lands the kill but can never earn.
        vm.prank(stranger);
        voting.executeVote(C.voteId);
        assertTrue(GovernanceGauge(C.gauge).is_killed(), "late canonical execution kills");
        assertEq(uint256(C.b.getReport(C.id).phase), 6, "expired cannot be revived");
        (uint256 s2, uint256 r2) = C.b.claim(C.id);
        assertEq(s2 + r2, 0, "no reward, no second bond");
    }

    // ------------------------------------------- bountyfix01 V-L03 witness

    /// @dev bountyfix01 V-L03: after an honest bind, a corrupt ballot-start
    /// observation (full-range max or a future date) can never establish a
    /// valid executed/rejected record and must never panic the product. The
    /// canonical model ballot executes for real: both callbacks RETURN, the
    /// middle kill lands, the genuine upstream executed flag remains set,
    /// the case closes NoAward with zero entitlement/credit, and the exact
    /// bond refunds once; restoring honest reads and replaying callbacks
    /// cannot resurrect the consumed case. The shared `resolve` rejection
    /// path and the armed `recognizeKill` path get their own cells; a fresh
    /// honest control must still Recognize.
    function test_Thin_AuditInvalidStartDateNoAwardAndRefund() public {
        _invalidStartDateExecuteCell(0);
        _invalidStartDateExecuteCell(1);
        _invalidStartDateResolveCell(0);
        _invalidStartDateResolveCell(1);
        _invalidStartDateArmedCell(0);
        _invalidStartDateArmedCell(1);
        // A fresh honest control must still Recognize.
        Live memory M = _proposed();
        _tallyPass(M);
        _execute(M, M.b.getReport(M.id).voteEnd);
        assertEq(uint256(M.b.getReport(M.id).phase), 3, "fresh honest control still recognizes");
    }

    /// @dev kind 0 = type(uint256).max, kind 1 = one second ahead of now.
    function _badStart(uint8 kind) private view returns (uint256) {
        return kind == 0 ? type(uint256).max : block.timestamp + 1;
    }

    /// @dev Real canonical execution under a corrupt start date: kill lands,
    /// NoAward, one exact bond refund, no resurrection after restore.
    function _invalidStartDateExecuteCell(uint8 kind) private {
        Live memory L = _proposed();
        // Correct-width record passes the product decoder BEFORE corruption.
        (bool dec, BountyRead.VoteRecord memory rec) = BountyRead.readVote(address(voting), L.voteId);
        assertTrue(dec, "well-formed record passes the decoder");
        assertEq(rec.startDate, L.b.getReport(L.id).voteEnd - VOTE_TIME, "honest date is the actual creation");
        _tallyPass(L);
        uint256 bad = _badStart(kind);
        voting.setStartDateObservation(true, bad);
        // The corrupt word is ABI-valid and still decodes: only its VALUE is
        // semantically impossible (BountyRead.decodeGetVote stays unchanged).
        (bool decBad,) = BountyRead.readVote(address(voting), L.voteId);
        assertTrue(decBad, "corrupt-but-well-formed date still decodes");
        vm.warp(L.b.getReport(L.id).voteEnd);
        assertTrue(voting.canExecute(L.voteId), "ballot is genuinely executable under the corrupt date");
        vm.prank(stranger);
        voting.executeVote(L.voteId); // must RETURN, not revert: the kill is not obstructed
        _assertKilledNoAwardRefund(L);
        // Restore honest reads and replay the callbacks: no resurrection.
        voting.setStartDateObservation(false, 0);
        vm.prank(address(agent));
        L.b.creditBallot(L.id, reporter);
        vm.prank(address(agent));
        L.b.recognizeKill(L.id);
        assertEq(uint256(L.b.getReport(L.id).phase), 7, "consumed NoAward cannot resurrect");
        (uint256 s2, uint256 r2) = L.b.claim(L.id);
        assertEq(s2 + r2, 0, "still paid exactly once");
    }

    /// @dev Shared oracle for a corrupt-observation execution: genuine kill,
    /// genuine executed flag, NoAward, zero credit/entitlement, ONE exact
    /// bond refund.
    function _assertKilledNoAwardRefund(Live memory L) private {
        assertTrue(GovernanceGauge(L.gauge).is_killed(), "outage never obstructs the middle kill");
        (, bool executed,,,,,,,,) = voting.getVote(L.voteId);
        assertTrue(executed, "genuine upstream executed flag remains set");
        ReportView memory rv = L.b.getReport(L.id);
        assertEq(uint256(rv.phase), 7, "callbacks close the applicable case NoAward");
        assertEq(rv.rewardCredit, 0, "no entitlement, no credit");
        (,, bool eligible) = L.b.rewardTerms(L.gauge);
        assertFalse(eligible, "no entitlement from a corrupt observation");
        (uint256 stake0, uint256 reward0) = L.b.claim(L.id);
        assertEq(stake0, STAKE, "exact bond refunded");
        assertEq(reward0, 0, "no reward invented");
    }

    /// @dev Shared `resolve` rejection path: a corrupt date cannot establish
    /// the validated rejection (false/no change); the restored honest date
    /// permits Rejected with the bond refundable.
    function _invalidStartDateResolveCell(uint8 kind) private {
        Live memory P = _proposed();
        // NO yes-vote: a genuinely closed, losing, unexecuted ballot.
        vm.warp(P.b.getReport(P.id).voteEnd + 1);
        voting.setStartDateObservation(true, _badStart(kind));
        assertFalse(P.b.resolve(P.id), "corrupt date gives false/no change");
        assertEq(uint256(P.b.getReport(P.id).phase), 1, "no closure on the corrupt observation");
        voting.setStartDateObservation(false, 0);
        assertTrue(P.b.resolve(P.id), "restored date permits the validated rejection");
        assertEq(uint256(P.b.getReport(P.id).phase), 5, "Rejected");
        (uint256 stake0, uint256 reward0) = P.b.claim(P.id);
        assertEq(stake0, STAKE, "rejected bond refunds");
        assertEq(reward0, 0, "never a reward");
    }

    /// @dev `recognizeKill`'s ARMED path under corruption. DISCLOSED FAULT
    /// INJECTION, not a separate canonical transaction: this isolated cell
    /// pranks the authorized Agent directly and arms through the mock's
    /// EXISTING labelled forged-executed read mode (GF_BAD_FLAGS) before the
    /// real same-block proxy kill; the genuine executeVote-embedded
    /// sequence is covered by the execution cell and the honest control.
    function _invalidStartDateArmedCell(uint8 kind) private {
        Live memory Q = _proposed();
        _tallyPass(Q);
        vm.warp(Q.b.getReport(Q.id).voteEnd);
        voting.setGetVoteFault(3); // labelled forged executed flag
        vm.prank(address(agent));
        Q.b.creditBallot(Q.id, reporter);
        assertEq(uint256(Q.b.getReport(Q.id).phase), 2, "armed on the well-formed forged observation");
        killGaugeViaRoute(Q.gauge); // real proxy route, same block
        assertTrue(GovernanceGauge(Q.gauge).is_killed(), "same-block middle kill lands");
        voting.setStartDateObservation(true, _badStart(kind)); // corrupt before recognition
        vm.prank(address(agent));
        Q.b.recognizeKill(Q.id); // must RETURN: the consumed arm closes NoAward
        assertEq(uint256(Q.b.getReport(Q.id).phase), 7, "corrupt recognition observation closes NoAward");
        assertEq(Q.b.getReport(Q.id).rewardCredit, 0, "no credit from the corrupt armed path");
        (uint256 stake0, uint256 reward0) = Q.b.claim(Q.id);
        assertEq(stake0, STAKE, "non-forfeited bond refunds once");
        assertEq(reward0, 0, "no reward");
        (uint256 s1, uint256 r1) = Q.b.claim(Q.id);
        assertEq(s1 + r1, 0, "single refund");
        voting.setStartDateObservation(false, 0);
        voting.setGetVoteFault(0);
    }

    // ------------------------------------------------------------------ G09

    function test_Thin_CurrentFlagAndNoMoneyCallbacks() public {
        Live memory L = _proposed();
        _tallyPass(L);
        _execute(L, L.b.getReport(L.id).voteEnd);
        assertEq(uint256(L.b.getReport(L.id).phase), 3, "recognized with true flag");

        // Authorized unkill BEFORE seizure: the CURRENT flag governs.
        vm.prank(address(killProxy));
        GovernanceGauge(L.gauge).set_killed(false);
        assertFalse(GovernanceGauge(L.gauge).is_killed(), "unkilled");
        _spaceFdCursor();
        vm.prank(stranger);
        (, uint256 conf) = L.core_.checkpoint(L.gauge);
        assertEq(conf, 0, "false flag forbids seizure; no historical latch");
        assertEq(uint256(L.b.getReport(L.id).phase), 3, "entitlement waits locally, unfired");
        // Local terms survive the upstream outage: rewardTerms/getReport are
        // pure reads even with Voting and the gauge flag broken.
        voting.setGetVoteFault(1);
        GovernanceGauge(L.gauge).setFlagFault(1);
        (bytes32 slotId,, bool eligible) = L.b.rewardTerms(L.gauge);
        assertEq(slotId, L.id, "terms remain readable under faults");
        assertTrue(eligible, "unallocated entitlement intact under faults");
        ReportView memory rv = L.b.getReport(L.id);
        assertEq(rv.stakeState, uint8(StakeState.Refundable), "bond state local");
        voting.setGetVoteFault(0);
        GovernanceGauge(L.gauge).setFlagFault(0);
        // Re-kill through the honest route and settle: recognition itself
        // never moved a token (custody equality around this whole test).
        vm.prank(address(killProxy));
        GovernanceGauge(L.gauge).set_killed(true);
        uint256 fdBefore = crvUSD.balanceOf(address(fd));
        uint256 repBefore = crvUSD.balanceOf(reporter);
        _spaceFdCursor();
        vm.prank(stranger);
        uint256 gross = L.core_.confiscate(L.gauge);
        assertTrue(gross > 0, "seizure fires once the current flag is true");
        (, uint256 reward) = L.b.claim(L.id);
        assertEq(reward, gross / 2, "half paid at settlement");
        assertEq(crvUSD.balanceOf(reporter) - repBefore, STAKE + gross / 2, "bond+half to reporter");
        assertEq(crvUSD.balanceOf(address(fd)) - fdBefore, gross - gross / 2, "F to FD at settlement only");
    }
}
