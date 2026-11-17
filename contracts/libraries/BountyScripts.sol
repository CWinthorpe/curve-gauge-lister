// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IAgent, IKillProxy} from "../interfaces/IBountyGovernance.sol";
import {IGaugeBounty} from "../interfaces/IGaugeBounty.sol";

/// @title BountyScripts
/// @notice Internal canonical CallsScript encoding and report domain hashes
/// (plans/BOUNTY-REWORK-PLAN.md §3.1/§3.3). No public/external functions; no
/// storage; nothing here is independently deployable. The product no longer
/// calls newVote or constructs ballot metadata: the retired 161-byte
/// voteMetadata/hex formatter is gone; the canonical script encoder and the
/// FD weekFloor survive.
library BountyScripts {
    /// @dev Aragon CallsScript executor type identifier. Canonical scripts
    /// begin with exactly 0x00000001.
    bytes4 internal constant CALLS_SCRIPT_TYPE = 0x00000001;

    /// @dev Curve week (pinned research fact; the FD receipt horizon).
    uint256 internal constant WEEK = 604800;

    /// @dev Exact reporter-bound domain string (rework plan §3.1);
    /// identities use abi.encode (never packed concatenation) with the
    /// actual chain id. The beneficiary is bound inside reportId AND inside
    /// the canonical script's explicit creditBallot word — a ballot naming
    /// another beneficiary can never be admitted for this reporter.
    bytes32 internal constant REPORT_DOMAIN = keccak256(bytes("CurveGaugeBounty.report.reporter.v1"));

    /// @dev Week floor used for receipt weeks and the FD accounting horizon.
    function weekFloor(uint256 timestamp) internal pure returns (uint256) {
        return (timestamp / WEEK) * WEEK;
    }

    /// @notice The permanent report identity (rework plan §3.1):
    /// keccak256(abi.encode(DOMAIN, block.chainid, bounty, lister, gauge,
    /// listingId, reporter, reportNonce, evidenceHash)). reportNonce is a
    /// caller-chosen identifier (NOT a commit/reveal salt, shared counter or
    /// deadline) enabling exact-script precomputation before the ballot
    /// exists. proposalId is deliberately NOT in the reportId preimage: no
    /// future-ID prediction, no circular hash.
    function reportId(
        address bounty,
        uint256 chainid,
        address lister,
        address gauge,
        bytes32 listingId,
        address reporter,
        uint256 reportNonce,
        bytes32 evidenceHash
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(REPORT_DOMAIN, chainid, bounty, lister, gauge, listingId, reporter, reportNonce, evidenceHash)
        );
    }

    /// @notice The canonical three-action kill script (rework plan §3.3),
    /// calling ONLY the fixed Ownership Agent's execute(address,uint256,bytes)
    /// with ETH value zero, in this exact order:
    ///  1. Agent.execute(bounty, 0, creditBallot(reportId, reporter))
    ///  2. Agent.execute(killProxy, 0, set_killed(gauge))
    ///  3. Agent.execute(bounty, 0, recognizeKill(reportId))
    /// Each entry is 20-byte Agent address || uint32 big-endian calldata
    /// length || calldata. Credit calldata is 68 bytes; Agent payload lengths
    /// are 228,196,196; the full script is 696 bytes. No additional calls, no
    /// trailing bytes, no caller-supplied script. Ordinary ABI encoding for
    /// the Agent calldata and the CallsScript target/uint32-length framing.
    function buildKillScript(
        address agent,
        address bounty,
        address killProxy,
        address gauge,
        bytes32 reportIdKey,
        address reporter
    ) internal pure returns (bytes memory) {
        return bytes.concat(
            CALLS_SCRIPT_TYPE,
            _entry(agent, bounty, abi.encodeCall(IGaugeBounty.creditBallot, (reportIdKey, reporter))),
            _entry(agent, killProxy, abi.encodeCall(IKillProxy.set_killed, (gauge))),
            _entry(agent, bounty, abi.encodeCall(IGaugeBounty.recognizeKill, (reportIdKey)))
        );
    }

    /// @dev One canonical CallsScript entry: 20-byte Agent target || uint32
    /// calldata length || Agent.execute(target, 0, data) framed by the
    /// ordinary ABI encoder. Fixed action shape: the payload arrives as a
    /// value; there is no caller-supplied value, length or extra-action list.
    function _entry(address agent, address target, bytes memory data) private pure returns (bytes memory) {
        bytes memory calldata_ = abi.encodeCall(IAgent.execute, (target, 0, data));
        return bytes.concat(bytes20(agent), bytes4(uint32(calldata_.length)), calldata_);
    }
}
