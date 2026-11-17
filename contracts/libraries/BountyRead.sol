// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IOwnershipVoting} from "../interfaces/IOwnershipVoting.sol";
import {ICurveGaugeListerV2 as IFeeDistributorToken} from "../interfaces/ICurveGaugeListerV2.sol";
import {IERC20Minimal} from "../interfaces/IERC20Minimal.sol";

/// @title BountyRead
/// @notice Internal capped staticcall and strict decoding for no-award
/// callbacks (plans/BOUNTY-PLAN.md §3.2): bounded staticcalls copy at most
/// 8192 return bytes and forward at most 200000 gas per dependency read;
/// complete tuple offsets/lengths/boolean ranges are validated before
/// decoding. Return-data bombs and malformed ABI must fail closed (caller
/// treats the read as a no-award failure) without aborting an adequately
/// gas-funded ordinary kill. No public/external functions; no storage.
library BountyRead {
    uint256 internal constant MAX_RETURN_BYTES = 8192;
    uint256 internal constant MAX_GAS_PER_READ = 200000;

    /// @notice Decision fields from the strictly validated ten-field getVote envelope.
    struct VoteRecord {
        bool open;
        bool executed;
        uint256 startDate;
        uint256 snapshotBlock;
        uint256 supportRequired;
        uint256 minAcceptQuorum;

        uint256 votingPower;
        bytes32 scriptHash;
    }

    /// @dev Capped staticcall. Returns ok=false (never reverts, never
    /// propagates) on any call failure or oversized return; the raw return is
    /// copied only when within the bound. `gasleft()` never exceeds the cap;
    /// an under-gassed outer transaction can still fail before this point —
    /// this library promises nothing beyond bounded per-read forwarding.
    function cappedStaticCall(address target, bytes memory callData) internal view returns (bool ok, bytes memory ret) {
        if (target.code.length == 0) {
            return (false, "");
        }
        uint256 forward = gasleft() < MAX_GAS_PER_READ ? gasleft() : MAX_GAS_PER_READ;
        assembly {
            // Do not copy return data before validating its bounded length.
            // The one copy below publishes only a successful, bounded result.
            let size := mload(0x40)
            let success := staticcall(forward, target, add(callData, 0x20), mload(callData), 0, 0)
            let rlen := returndatasize()
            if and(success, lt(rlen, 8193)) {
                mstore(size, rlen)
                returndatacopy(add(size, 0x20), 0, rlen)
                // Publish the allocation.
                mstore(0x40, add(add(size, 0x20), and(add(rlen, 31), not(31))))
                ok := 1
                ret := size
            }
        }
    }

    /// @dev Strict single-word uint256 decode.
    function decodeUint256(bytes memory ret) internal pure returns (bool ok, uint256 value) {
        if (ret.length != 32) {
            return (false, 0);
        }
        return (true, abi.decode(ret, (uint256)));
    }

    /// @dev Capped no-argument bool read (is_killed style): backed by the
    /// single strict word-read primitive (no return-data allocation; the
    /// same 200,000-gas forward bound and exact-32-byte length rule).
    function readBool(address target, bytes4 selector) internal view returns (bool ok, bool value) {
        return boolWord(target, selector, bytes32(0), false);
    }

    /// @dev Capped single-word uint256 read (selector + optional one-word
    /// argument) backed by the same strict word-read primitive; exact
    /// 32-byte return requirement, <=200,000 forwarded gas.
    function readUint(address target, bytes4 selector, bytes32 arg, bool hasArg)
        internal
        view
        returns (bool ok, uint256 value)
    {
        return _wordRead(target, selector, arg, hasArg);
    }

    /// @dev Capped, strictly-decoded `canExecute(uint256)->bool` read on the
    /// pinned Voting app (thin plan §3.1: a closed, unexecuted ballot whose
    /// canExecute is false is a validated rejection). ok=false means the
    /// observation is unavailable and the caller must defer.
    function canExecutable(address voting, uint256 voteId) internal view returns (bool ok, bool value) {
        return boolWord(voting, IOwnershipVoting.canExecute.selector, bytes32(voteId), true);
    }

    /// @dev ONE bounded getListing observation for all decision consumers
    /// (thin plan §3.1/§4.2): validates the static 18-word shape and reads
    /// only the decision words — payer(2), status(6), deposited(8),
    /// remaining(9), confiscated(11), reporterReward(15), rewardReportId(17).
    /// fetched=false means the dependency is unreadable (callers defer or
    /// fail closed per their own rules); decoded=false is a malformed shape.
    /// paidActivePositive is positively observed Active+paid+exact-fee-shape
    /// with positive remainder; free/terminal/exhausted read false.
    function listingFacts(address lister, address gauge)
        internal
        view
        returns (
            bool fetched,
            bool decoded,
            bool paidActivePositive,
            uint256 status,
            uint256 rewardReportId,
            uint256 reporterReward,
            uint256 confiscated
        )
    {
        bytes memory ret;
        (fetched, ret) = cappedCall1(lister, IFeeDistributorToken.getListing.selector, uint256(uint160(gauge)));
        if (!fetched) {
            return (false, false, false, 0, 0, 0, 0);
        }
        if (ret.length != 18 * 32) {
            return (true, false, false, 0, 0, 0, 0);
        }
        uint256 payerWord;
        uint256 depositedWord;
        uint256 remainingWord;
        assembly {
            let pb := add(ret, 0x20)
            payerWord := mload(add(pb, 0x40))
            status := mload(add(pb, 0xC0))
            depositedWord := mload(add(pb, 0x100))
            remainingWord := mload(add(pb, 0x120))
            confiscated := mload(add(pb, 0x160))
            reporterReward := mload(add(pb, 0x1E0))
            rewardReportId := mload(add(pb, 0x220))
        }
        decoded = true;
        paidActivePositive = status == 1 && payerWord != 0 && depositedWord == 10_000e18 && remainingWord != 0;
    }

    /// @dev Capped staticcall with an optional 32-byte argument, ONE shared
    /// body (builds the calldata in scratch memory; bounds the forward gas
    /// and the captured return exactly like cappedStaticCall).
    function cappedCall1(address target, bytes4 selector, uint256 arg)
        internal
        view
        returns (bool ok, bytes memory ret)
    {
        assembly {
            let m := mload(0x40)
            mstore(m, and(selector, 0xffffffff00000000000000000000000000000000000000000000000000000000))
            mstore(add(m, 4), arg)
            let s := staticcall(200000, target, m, 36, 0, 0)
            let n := returndatasize()
            if and(s, iszero(gt(n, 8192))) {
                let buf := mload(0x40)
                mstore(buf, n)
                let d := add(buf, 32)
                returndatacopy(d, 0, n)
                // round the allocation up to the word boundary
                let words := div(add(n, 31), 32)
                mstore(0x40, add(d, mul(words, 32)))
                ok := 1
                ret := buf
            }
        }
    }

    /// @dev Capped encoded-call getVote read with strict full-tuple decoding.
    function readVote(address target, uint256 voteId) internal view returns (bool ok, VoteRecord memory rec) {
        (bool callOk, bytes memory ret) = cappedCall1(target, IOwnershipVoting.getVote.selector, voteId);
        if (!callOk) return (false, rec);
        return decodeGetVote(ret);
    }

    // ------------------------------------------------------------------
    // Compact primitive reads (internal-only; X08b §2.3): ONE strict
    // word-read primitive backs every single-word dependency check. All
    // forward <= MAX_GAS_PER_READ and read <= 32 bytes with exact length
    // validation before any value is used.
    // ------------------------------------------------------------------

    /// @dev staticcall(target, selector || optionalArg) -> exactly one word.
    /// got=false on any call failure, wrong length or oversized return; the
    /// value is meaningful only when got=true.
    function _wordRead(address target, bytes4 selector, bytes32 arg, bool hasArg)
        private
        view
        returns (bool got, uint256 word)
    {
        assembly {
            let m := mload(0x40)
            mstore(m, and(selector, 0xffffffff00000000000000000000000000000000000000000000000000000000))
            let size := 4
            if hasArg {
                mstore(add(m, 4), arg)
                size := 36
            }
            let s := staticcall(200000, target, m, size, m, 32)
            if and(s, eq(returndatasize(), 32)) {
                got := 1
                word := mload(m)
            }
        }
    }

    /// @dev staticcall(target, selector || optionalArg) -> exactly one word,
    /// compared equal to expected.
    function eqWord(address target, bytes4 selector, bytes32 arg, bool hasArg, uint256 expected)
        internal
        view
        returns (bool)
    {
        (bool got, uint256 w) = _wordRead(target, selector, arg, hasArg);
        return got && w == expected;
    }

    /// @dev staticcall(target, selector || optionalArg) -> exactly one word
    /// equal to 0 or 1, returned as bool.
    function boolWord(address target, bytes4 selector, bytes32 arg, bool hasArg)
        internal
        view
        returns (bool ok, bool value)
    {
        (bool got, uint256 w) = _wordRead(target, selector, arg, hasArg);
        if (!got || w > 1) return (false, false);
        return (true, w == 1);
    }

    /// @dev Address-returning read (eqWord against a second address form).
    function eqAddress(address target, bytes4 selector, bytes32 arg, bool hasArg, address expected)
        internal
        view
        returns (bool)
    {
        return eqWord(target, selector, arg, hasArg, uint256(uint160(expected)));
    }

    /// @dev decimals() == 18 check.
    function decimals18(address token) internal view returns (bool) {
        return eqWord(token, IERC20Minimal.decimals.selector, bytes32(0), false, 18);
    }

    /// @dev Nonempty code check.
    function hasCode(address target) internal view returns (bool) {
        return target.code.length != 0;
    }

    /// @dev getEVMScriptExecutor(CALLS_SCRIPT_TYPE bytes) == expected.
    function executorBound(address voting, bytes4 scriptType, address expected) internal view returns (bool) {
        (bool ok, bytes memory ret) = cappedStaticCall(
            voting, abi.encodeWithSelector(IOwnershipVoting.getEVMScriptExecutor.selector, abi.encodePacked(scriptType))
        );
        if (!ok) return false;
        (bool dec, uint256 v) = decodeUint256(ret);
        return dec && v == uint256(uint160(expected));
    }

    /// @dev Strict decode of the complete getVote tuple: nine static heads
    /// plus the dynamic script tail. Validates total length, the dynamic
    /// offset EQUALS 320 before dereferencing it, script length bounds and
    /// both boolean ranges BEFORE decoding; nothing here can revert.
    function decodeGetVote(bytes memory ret) internal pure returns (bool ok, VoteRecord memory vote) {
        if (ret.length < 352) {
            return (false, vote);
        }
        uint256 dynOff;
        uint256 scriptLen;
        assembly {
            let pb := add(ret, 0x20)
            dynOff := mload(add(pb, 288))
            // ONLY after confirming the canonical offset: read the tail.
            if eq(dynOff, 320) {
                scriptLen := mload(add(pb, 320))
            }
        }
        if (dynOff != 320 || scriptLen > 8192) {
            return (false, vote);
        }
        uint256 padded = ((scriptLen + 31) / 32) * 32;
        if (ret.length != 352 + padded) {
            return (false, vote);
        }
        if (_head(ret, 0) > 1 || _head(ret, 1) > 1) {
            return (false, vote);
        }
        // Hash the script IN PLACE from the validated return buffer: no
        // per-call bytes copy exists anywhere (the 8192 length bound was
        // checked above, so reads stay inside `ret`).
        bytes32 scriptHash;
        assembly {
            let src := add(add(ret, 0x20), 352) // pb + 320 + 32
            scriptHash := keccak256(src, scriptLen)
        }
        vote.open = _head(ret, 0) == 1;
        vote.executed = _head(ret, 1) == 1;
        vote.startDate = _head(ret, 2);
        vote.snapshotBlock = _head(ret, 3);
        vote.supportRequired = _head(ret, 4);
        vote.minAcceptQuorum = _head(ret, 5);

        vote.votingPower = _head(ret, 8);
        vote.scriptHash = scriptHash;
        return (true, vote);
    }

    /// @dev One word of the decoded payload (payload begins after the
    /// length word of `ret`).
    function _head(bytes memory ret, uint256 i) private pure returns (uint256 w) {
        assembly {
            w := mload(add(add(ret, 0x20), mul(i, 0x20)))
        }
    }
}
