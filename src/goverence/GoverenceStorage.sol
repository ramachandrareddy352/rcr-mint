// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.18;

/*
=> Transfer if paused during the voting period only, not in pending and queue periods
*/
contract GoverenceStorage {
    event ProposalCreated(
        uint256 indexed proposalId, string description, bytes calldatas, uint256 votingPeriod, address proposedBy
    );
    event ProposalVerified(uint256 indexed proposalId, uint256 votingStartTime, uint256 votingEndTime);
    event VoteCast(uint256 indexed proposalId, address indexed voter, bool support, uint256 votes);
    event VoteCastByDelegate(
        uint256 indexed proposalId, address indexed onBehalf, address indexed voter, bool support, uint256 votes
    );
    event ProposalCanceled(uint256 indexed proposalId, string resaon);
    event ProposalQueued(uint256 indexed proposalId, uint256 queuedAt);
    event ProposalExecuted(
        uint256 indexed proposalId,
        uint256 executedAt,
        bytes calldatas,
        bool executed,
        uint256 forVotes,
        uint256 againstVotes
    );

    uint256 public constant MIN_PENDING_TIME = 2 days;
    uint256 public constant MIN_VOTING_PERIOD = 5 days;
    uint256 public constant MAX_VOTING_PERIOD = 15 days;
    uint256 public constant MIN_PROPOSAL_THREASHOLD = 1000 * 1e18; // 1000 $ ot make a proposal
    uint256 public constant MIN_VOTING_THREASHOLD = 10 * 1e18; // min 10$ to vote

    uint256 public s_proposalCount; // The total number of proposals, tracks by unique number
    bool public s_isAnyVoting; // if any one of the proposal is voting , then it is true

    enum State {
        DefaultState, // state always shows zero
        Pending, // proposal is proposed and admin is not verifed yet
        Active, // during this state the voting is done
        Canceled, // proposal is canceled
        Succeeded, // if succeed the voting time is completed
        Queued, // after completing the voting , any one of the holder queue the proposal to admin
        Executed // proposal is executed

    }

    struct Proposal {
        address proposedBy; // proposed by
        address queuedBy; // after completing voting, proposal was queued and finally admin verifies and execute the proposal
        uint256 proposedTimeStamp; // timestamp at which the proposal is proposed
        uint256 queuedTimeStamp; // timestamp at which the proposal is queued
        uint256 executedTimeStamp; // timestamp at which the proposal is executed
        uint256 votingPeriod; // the no.of days that the voting is going
        uint256 votingStartTimeStamp; // time at which admin accept the proposal and start to vote
        uint256 votingEndTimeStamp; // time at which the voting is ends for a proposal
        bool canceled; // Flag marking whether the proposal has been canceled
        bool executed; // Flag marking whether the proposal has been executed
        bytes params;
    }

    struct VotingDetails {
        uint256 votersCount;
        uint256 forVotesCount; // Current number of votes in favor of this proposal (incresed by power)
        uint256 againstVotesCount; // Current number of votes in opposition to this proposal
        uint256 totalVoteSupply;
    }

    // Ballot receipt record for a voter
    struct Receipt {
        bool hasVoted; // Whether or not a vote has been cast
        bool support; // Whether or not the voter supports the proposal
        uint256 votes; // The number of votes the voter had, which were cast
    }

    struct Delegate {
        uint256 totalAccounts;
        mapping(address account => uint256 votes) delegateVotePower;
        // here votePercent is not no.of votes
        uint256 totalVotes;
    }
    // after voting starts then only delegate of vote is possible

    mapping(address owner => mapping(uint256 proposalId => Delegate)) public s_votesDelegated;
    mapping(address owner => mapping(uint256 proposalId => bool)) public s_hasVoteDelegated;
    mapping(uint256 proposalId => mapping(address voter => Receipt)) internal s_votingReceipt;
    mapping(uint256 proposalId => VotingDetails) internal s_votingResults;
    mapping(uint256 proposalId => State) public s_proposalState; // Stage tracking of every proposal
    mapping(uint256 proposalId => Proposal) internal s_proposals;
}
