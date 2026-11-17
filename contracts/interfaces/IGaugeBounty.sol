// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ReportView, BountyConfig} from "../bounty/BountyTypes.sol";

/// @title IGaugeBounty
/// @notice GaugeBounty's complete public surface (plans/BOUNTY-REWORK-PLAN.md
/// §6): exactly 14 callable functions — no other generated getter, overload,
/// receive, fallback or payable. No standing lock, FIFO queue, shared
/// creation or service entrypoint exists. All state is private except
/// through this table. Sole ABI type authority together with BountyTypes.
interface IGaugeBounty {
    // ------------------------------------------------------------------ events

    event ListerBound(address indexed lister);
    event ReportSubmitted(
        bytes32 indexed reportId,
        address indexed reporter,
        address indexed gauge,
        uint256 proposalId,
        uint256 reportNonce,
        bytes32 evidenceHash,
        uint256 voteEnd,
        uint256 executeBy
    );
    event ReportStateChanged(bytes32 indexed reportId, uint8 phase);
    event StakeForfeited(bytes32 indexed reportId);
    event RewardCredited(bytes32 indexed reportId, uint256 amount);
    event Claimed(bytes32 indexed reportId, address indexed reporter, uint256 stakeAmount, uint256 rewardAmount);
    event DaoFlushed(uint256 amount, uint256 receiptWeek);

    // ------------------------------------------------------------------ errors

    error WrongChain();
    error BadConfiguration();
    error NotAgent();
    error NotDao();
    error NotLister();
    error Reentrancy();
    error AlreadyBound();
    error UnknownReport();
    error IneligibleGauge();
    error BadEvidence();
    error BadPhase();
    error BadVote();
    error BadAmount();
    error TokenDeltaMismatch();
    error DuplicateReport();
    error DuplicateProposal();

    // --------------------------------------------------------------- functions

    /// @notice Complete immutable configuration tuple, exact 9-address order.
    function config() external view returns (BountyConfig memory);

    /// @notice The authenticated write-once V2 binding.
    function lister() external view returns (address);

    /// @notice Configured Ownership Agent only; bind a code-bearing
    /// reciprocal V2 once.
    function bindLister(address lister_) external;

    /// @notice Paid admission of an EXISTING beneficiary-bound ballot:
    /// reporter is msg.sender (no beneficiary/creator/app argument), stake
    /// is exactly 1000e18 crvUSD, and the ballot's canonical script must
    /// equal S(reportId, msg.sender, gauge) exactly. reportNonce is a
    /// caller-chosen identifier that lets the script be precomputed before
    /// the ballot exists; it is not a commit/reveal salt or shared counter.
    function submit(address gauge, uint256 proposalId, bytes32 evidenceHash, uint256 reportNonce)
        external
        returns (bytes32 reportId);

    /// @notice Configured Ownership Agent only; the canonical pre-kill arm
    /// callback. Requires the supplied reporter to equal the stored report
    /// reporter and the full observation chain; a failed or mismatching
    /// attempt closes only its own unfinished offer with NoAward and never
    /// reverts the protective kill. Never moves tokens or FD.
    function creditBallot(bytes32 reportId, address reporter) external;

    /// @notice Configured Ownership Agent only; consumes the same-block arm
    /// and recognizes the executed canonical kill (current flag true).
    /// First qualifying flag-true recognition writes the permanent
    /// listing-level winner latch; a different recorded winner closes this
    /// attempt as NoAward. Never erases Recognized/Rewarded.
    function recognizeKill(bytes32 reportId) external;

    /// @notice Local only; supply the existing V2 split hook with the
    /// latched entitlement. With no latch returns the all-zero tuple even
    /// when proposals exist; after funding/closure the permanent
    /// id/reporter may still be returned with eligible false.
    function rewardTerms(address gauge) external view returns (bytes32 reportId, address reporter, bool eligible);

    /// @notice Bound V2 only; verify the latched winner, its terminal
    /// allocation and the exact reporter half once.
    function creditReward(bytes32 reportId, uint256 amount) external;

    /// @notice Anyone; run local loser/expiry cleanup first, then close an
    /// observed failed/ineligible case. Never slashes. Terminal endings are
    /// local no-ops; live offers are never cancellable.
    function resolve(bytes32 reportId) external returns (bool changed);

    /// @notice Anyone; pay available bond/reward to the stored reporter,
    /// including the same local cleanup resolve performs first.
    function claim(bytes32 reportId) external returns (uint256 stakeAmount, uint256 rewardAmount);

    /// @notice Current V2 config owner only; irrevocably assign an unpaid
    /// 1,000 stake to the pinned FD. The sole accepted-report exception.
    function markFrivolous(bytes32 reportId) external returns (bool applied);

    /// @notice Anyone; safely transfer/account only reserved forfeited
    /// stakes to the fixed FD.
    function flushDao(uint256 amount) external returns (uint256 flushed);

    /// @notice Local only; expose identity, ballot binding, clocks, bond
    /// disposition and current reward credit. Unknown ids read all zeros.
    function getReport(bytes32 reportId) external view returns (ReportView memory);

    /// @notice Local only; the three CURRENT custody liabilities, not
    /// historical counters.
    function accounting() external view returns (uint256 heldStakes, uint256 rewardCredits, uint256 daoLiability);
}
