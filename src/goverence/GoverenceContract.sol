// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {ITimeLock} from "../interfaces/ITimeLock.sol";
import {IGoverenceToken} from "../interfaces/IGoverenceToken.sol";
import {GoverenceStorage} from "./GoverenceStorage.sol";

/*
=> Owner is the deployer, he can only verify the proposal and execute/cancel them and call emergency execution.
new admin also updated
=> This is contract is deployed by the deployer
=> at a time only one proposal is accepted
*/

contract GoverenceContract is GoverenceStorage, Ownable, ReentrancyGuard {
    ITimeLock private immutable i_timelock;
    IGoverenceToken private immutable i_goverenceToken;

    constructor(address _timelock, address _goverenceToken) Ownable(msg.sender) {
        i_timelock = ITimeLock(_timelock);
        i_goverenceToken = IGoverenceToken(_goverenceToken);
    }

    // all proposals are done on tokenFactory only and no ethers are required to call
    function propose(
        string memory _proposalDescription, // better to use ipfs url
        bytes memory _params,
        uint256 _votingPeriod
    ) external nonReentrant {
        address m_propodsedBy = msg.sender;
        require(hasProposalPower(m_propodsedBy), "Goverence contract : You do not have any proposal power to propose");
        require(
            _votingPeriod >= MIN_VOTING_PERIOD && _votingPeriod <= MAX_VOTING_PERIOD,
            "Goverence contract : voting period should be in range"
        );

        uint256 m_proposalId = s_proposalCount;
        // proposal id starts from #0
        // params is in length of 4+(32*no.of parameters), 4 length = function selector
        s_proposals[m_proposalId] =
            Proposal(m_propodsedBy, address(0), block.timestamp, 0, 0, _votingPeriod, 0, 0, false, false, _params);
        s_proposalState[m_proposalId] = State.Pending;
        s_proposalCount++;

        emit ProposalCreated(m_proposalId, _proposalDescription, _params, _votingPeriod, m_propodsedBy);
    }

    function verifyPendingProposal(uint256 _proposalId, bool _accept) external nonReentrant onlyOwner {
        // between the proposal proposed time and voting start time the pending proposal is verified
        // if time if gone then the proposal is automatically canceled
        require(s_proposalState[_proposalId] == State.Pending, "Goverence contract : Proposal was not in pending list");

        Proposal memory m_proposal = s_proposals[_proposalId];
        uint256 m_timeStamp = block.timestamp;

        if (_accept) {
            // if the proposal was not checked within MIN_PENDING_TIME the proposla is expired and canceled
            s_proposalState[_proposalId] = State.Active;
            s_proposals[_proposalId].votingStartTimeStamp = m_timeStamp;
            s_proposals[_proposalId].votingEndTimeStamp = m_timeStamp + m_proposal.votingPeriod;
            i_goverenceToken.pause();
            // dont use fallback, it may call pause function using bytes data
            i_timelock.sheduleTransaction(_proposalId);
            s_isAnyVoting = true;

            emit ProposalVerified(_proposalId, m_timeStamp, s_proposals[_proposalId].votingEndTimeStamp);
        } else {
            _revokeProposal(_proposalId);
        }
    }

    function _revokeProposal(uint256 _proposalId) private {
        require(s_proposalState[_proposalId] != State.Canceled, "Goverence contract : Proposal is already canceled");
        require(s_proposalState[_proposalId] != State.Executed, "Goverence contract : Proposal is already executed");

        s_proposalState[_proposalId] = State.Canceled;
        s_proposals[_proposalId].canceled = true;
        s_isAnyVoting = false;
        i_goverenceToken.unpause();
        i_timelock.cancelTransaction(_proposalId);

        emit ProposalCanceled(_proposalId, "Goverence contract : canceled due to reason");
    }

    function cancelProposal(uint256 _proposalId) external nonReentrant onlyOwner {
        // if canceled reason is displayed in offline, owner can cancel proposal at any time before executed
        require(_proposalId < s_proposalCount, "Goverence contract : Invalid proposal id");
        _revokeProposal(_proposalId);
    }

    function castVote(uint256 _proposalId, bool _forVote) external nonReentrant {
        require(_proposalId < s_proposalCount, "Goverence contract : Invalid proposal id");
        require(s_proposalState[_proposalId] == State.Active, "Goverence contract : Proposal was not in active");

        if (block.timestamp > s_proposals[_proposalId].votingEndTimeStamp) {
            s_proposalState[_proposalId] = State.Succeeded;
            // the succeeded proposals are queued to verify the proposal
        }
        require(s_proposalState[_proposalId] == State.Active, "Goverence contract : Proposal was not in active");

        address m_voter = msg.sender;

        require(m_voter != address(0), "Goverence contract : Invalid zero address");
        require(hasVotingPower(m_voter), "Goverence contract : You do not have any voting power");
        require(!s_hasVoteDelegated[m_voter][_proposalId], "Goverence contract : you have already delegated your vote");

        uint256 m_votes = i_goverenceToken.balanceOf(m_voter);
        _castVote(_proposalId, m_voter, _forVote, m_votes);

        emit VoteCast(_proposalId, m_voter, _forVote, m_votes);
    }

    function _castVote(uint256 _proposalId, address _voter, bool _forVote, uint256 _votes) private {
        Receipt storage m_receipt = s_votingReceipt[_proposalId][_voter];
        require(!m_receipt.hasVoted, "Goverence contract : You have already voted for this proposal");

        if (_forVote) {
            m_receipt.support = true; // redundant the data(memory)
            s_votingResults[_proposalId].forVotesCount += _votes;
        } else {
            m_receipt.support = false;
            s_votingResults[_proposalId].againstVotesCount += _votes;
        }

        m_receipt.hasVoted = true;
        m_receipt.votes = _votes;
        s_votingResults[_proposalId].votersCount++;
    }

    function delegeteVotes(uint256 _proposalId, address[] memory _delegates, uint256[] memory _votePowers)
        external
        nonReentrant
    {
        address m_owner = msg.sender;
        // vote power is divided into 100 %
        // if we allow delegate votes at pending time, hacker may delegate votes and transfer tokens to other account
        require(m_owner != address(0), "Goverence contract : Invalid zero address");
        require(
            _delegates.length == _votePowers.length && _delegates.length > 0,
            "Goverence contract : Invalid length of array"
        );
        require(s_proposalState[_proposalId] == State.Active, "Goverence contract : Proposal was not in active");

        if (block.timestamp > s_proposals[_proposalId].votingEndTimeStamp) {
            s_proposalState[_proposalId] = State.Succeeded;
            // the succeeded proposals are queued to verify the proposal
        }
        require(s_proposalState[_proposalId] == State.Active, "Goverence contract : Proposal was not in active");

        require(!_checkDuplicates(_delegates), "Goverence contract : Duplicates are not allowed");
        require(s_votingReceipt[_proposalId][m_owner].hasVoted, "Goverence contract : You have already voted");
        require(!s_hasVoteDelegated[m_owner][_proposalId], "Goverence contract : you have already delegated your vote");

        uint256 m_votePower = i_goverenceToken.balanceOf(m_owner);
        require(
            hasDelegatePower(m_votePower, _delegates.length),
            "Goverence contract : You do not have enough delegate power"
        );

        s_hasVoteDelegated[m_owner][_proposalId] = true;

        Delegate storage m_delegate = s_votesDelegated[m_owner][_proposalId];
        m_delegate.totalAccounts = _delegates.length;
        m_delegate.totalVotes = m_votePower;

        for (uint256 i = 0; i < _delegates.length; i++) {
            require(
                _delegates[i] != address(0) && _votePowers[i] >= MIN_VOTING_THREASHOLD,
                "Goverence contract : Invalid input data"
            );
            m_delegate.delegateVotePower[_delegates[i]] = _votePowers[i];
        }
    }

    function _checkDuplicates(address[] memory _accounts) private pure returns (bool) {
        for (uint256 i = 0; i < _accounts.length; i++) {
            for (uint256 j = i + 1; j < _accounts.length; j++) {
                if (_accounts[i] == _accounts[j]) {
                    // Duplicate address found
                    return true;
                }
            }
        }
        // No duplicate addresses found
        return false;
    }

    function hasDelegatePower(uint256 _balance, uint256 _votersCount) public pure returns (bool) {
        return _votersCount * MIN_VOTING_THREASHOLD >= _balance;
    }

    function castVoteByDelegate(uint256 _proposalId, address _onBehalf, bool _forVote) external nonReentrant {
        require(
            !s_hasVoteDelegated[_onBehalf][_proposalId], "Goverence contract : Onbehalf account has not delegated votes"
        );
        require(s_proposalState[_proposalId] == State.Active, "Goverence contract : Proposal was not in active");

        if (block.timestamp > s_proposals[_proposalId].votingEndTimeStamp) {
            s_proposalState[_proposalId] = State.Succeeded;
            // the succeeded proposals are queued to verify the proposal
        }
        require(s_proposalState[_proposalId] == State.Active, "Goverence contract : Proposal was not in active");

        address m_voter = msg.sender;
        uint256 m_votes = s_votesDelegated[_onBehalf][_proposalId].delegateVotePower[m_voter];
        // no need to check for address(0) and vote power
        require(m_votes >= MIN_VOTING_THREASHOLD, "Goverence contract : Invalid delgate account");

        _castVote(_proposalId, m_voter, _forVote, m_votes);

        emit VoteCastByDelegate(_proposalId, _onBehalf, m_voter, _forVote, m_votes);
    }

    function queueProposal(uint256 _proposalId) external nonReentrant {
        // any one can queue the proposal, but not by address(0)
        require(msg.sender != address(0), "Goverence contract : Invaldi zero address");
        require(s_proposalState[_proposalId] != State.Canceled, "Goverence contract : proposal is canceled");
        require(s_proposalState[_proposalId] != State.Executed, "Goverence contract : proposal is executed");
        uint256 m_timeStamp = block.timestamp;

        if (m_timeStamp > s_proposals[_proposalId].votingEndTimeStamp) {
            s_proposalState[_proposalId] = State.Succeeded;
            // the succeeded proposals are queued to verify the proposal
        }
        require(s_proposalState[_proposalId] == State.Succeeded, "Goverence contract : Voting period is not completed");

        s_proposalState[_proposalId] = State.Queued;
        s_proposals[_proposalId].queuedBy = msg.sender;
        s_proposals[_proposalId].queuedTimeStamp = m_timeStamp;
        i_timelock.queueTransaction(_proposalId);
        i_goverenceToken.unpause(); // after proposal queued tokens are unfrezed
        s_isAnyVoting = false;

        emit ProposalQueued(_proposalId, m_timeStamp);
    }

    function executeProposal(uint256 _proposalId) external nonReentrant onlyOwner {
        // here we verify the queued proposals and there votings and decide to execute or revoke the proposal
        if (_verifyQueuedProposal(_proposalId)) {
            s_proposalState[_proposalId] = State.Executed;
            s_proposals[_proposalId].executedTimeStamp = block.timestamp;
            s_proposals[_proposalId].executed = true;
            /* execution logic is written here */
            i_timelock.executeTransaction(_proposalId, s_proposals[_proposalId].params);

            emit ProposalExecuted(
                _proposalId,
                block.timestamp,
                s_proposals[_proposalId].params,
                true,
                s_votingResults[_proposalId].forVotesCount,
                s_votingResults[_proposalId].againstVotesCount
            );
        } else {
            _revokeProposal(_proposalId);
        }
    }

    function _verifyQueuedProposal(uint256 _proposalId) private view returns (bool) {
        require(s_proposalState[_proposalId] == State.Queued, "Goverence contract : Proposal not in queue");

        uint256 m_totalSupply = i_goverenceToken.totalSupply();
        VotingDetails memory m_results = s_votingResults[_proposalId];

        // minimun 40 % of vote power is used to execute the proposal
        bool m_stage1 = m_results.forVotesCount >= ((m_totalSupply * 40) / 100);
        // win with difference of 0.01 percentage
        bool m_stage2 = m_results.forVotesCount > (m_results.againstVotesCount + (m_results.againstVotesCount / 100));
        // minimun 40 % of pepole should have to participate
        bool m_stage3 = m_results.votersCount >= ((i_goverenceToken.s_ownersCount() * 40) / 100);
        // return (s_votingResults.forVotesCount > s_votingResults.againstVotesCount) && votersCount
        return m_stage1 && m_stage2 && m_stage3;
    }

    function hasProposalPower(address _account) public view returns (bool) {
        require(_account != address(0), "Goverence contract : Invalid zero address");
        // minimum the account should have to trade 1000$ value to make a proposal
        uint256 m_proposalPower = i_goverenceToken.balanceOf(_account);
        return m_proposalPower > MIN_PROPOSAL_THREASHOLD;
    }

    function hasVotingPower(address _account) public view returns (bool) {
        require(_account != address(0), "Goverence contract : Invalid zero address");
        // minimum the account should have to trade 10$ value to make a vote
        uint256 m_votingPower = i_goverenceToken.balanceOf(_account);
        return m_votingPower > MIN_VOTING_THREASHOLD;
    }

    function getVotesDelegated(address _from, address _to, uint256 _proposalId) external view returns (uint256) {
        require(_from != address(0) && _to != address(0), "Goverence contract : Invalid zero address");
        require(_proposalId < s_proposalCount, "Goverence contract : Invalid proposal id");
        return s_votesDelegated[_from][_proposalId].delegateVotePower[_to];
    }

    function getVoterReceipt(uint256 _proposalId, address _voter) external view returns (Receipt memory) {
        require(_voter != address(0), "Goverence contract : Invalid zero address");
        require(_proposalId < s_proposalCount, "Goverence contract : Invalid proposal id");
        return s_votingReceipt[_proposalId][_voter];
    }

    function getVotingResults(uint256 _proposalId) external view returns (VotingDetails memory) {
        require(_proposalId < s_proposalCount, "Goverence contract : Invalid proposal id");
        return s_votingResults[_proposalId];
    }

    function getProposal(uint256 _proposalId) external view returns (Proposal memory) {
        require(_proposalId < s_proposalCount, "Goverence contract : Invalid proposal id");
        return s_proposals[_proposalId];
    }
}
