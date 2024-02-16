// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Ownable} from "../utils//Ownable.sol";

/*
Time lock saves the progress of every step of proposal execution, if any hack is done time lock re-verify the proposal stages
*/

contract TimeLock is Ownable {
    event NewGoverence(address indexed newGoverence, uint256 totalProposalsCount);
    event SheduleTransaction(uint256 indexed proposalId, uint256 timeStamp);
    event CancelTransaction(uint256 indexed proposalId, uint256 timeStamp);
    event ExecuteTransaction(uint256 indexed proposalId, uint256 timeStamp);
    event QueuedTransaction(uint256 indexed proposalId, uint256 timeStamp);

    address public immutable TOKEN_FACTORY; // call to this address
    address public s_goverenceContract;

    enum State {
        Default,
        Sheduled,
        Queued,
        Canceled,
        Executed
    }

    uint256 private s_lastProposalId;
    mapping(uint256 proposalId => State) public s_transactions;

    modifier isGoverence() {
        _checkGoverence(msg.sender);
        _;
    }

    // owner is deployer, he change / update the goverence contract address
    constructor(address _tokenFactory, address _goverenceContract) Ownable(msg.sender) {
        TOKEN_FACTORY = _tokenFactory;
        s_goverenceContract = _goverenceContract;
    }

    function _checkGoverence(address _account) private view {
        require(_account == s_goverenceContract, "Time lock : Invalid goverence call");
    }

    function setNewGovereneContract(address _newGoverenceContract) external onlyOwner {
        require(_newGoverenceContract != address(0), "Time lock : Invalid zero address");
        // if goverence is not ready, admin sets his address as goverence
        s_goverenceContract = _newGoverenceContract;
        // if new goverence remove all previous proposal, due to new proposal also have same id we get
        _revokeAll();
        emit NewGoverence(_newGoverenceContract, s_lastProposalId);
    }

    function _revokeAll() private {
        for (uint256 i = 0; i < s_lastProposalId; ) {
            s_transactions[i] = State.Default;
            unchecked {
                i = i + 1;
            }
        }
    }

    // if we modify the goverence contract change the admin.
    // changing of goverence contract not affect any execution.
    // before changing goverence contract execute or cancel all the pending proposals.

    function sheduleTransaction(uint256 _proposalId) public isGoverence {
        // when the pending proposal is become active, then we shedule the transaction
        // to avoid collaiding we use _proposalId
        require(s_transactions[_proposalId] == State.Default, "Time lock : State is not in dafault");
        s_transactions[_proposalId] = State.Sheduled;
        s_lastProposalId = _proposalId;
        emit SheduleTransaction(_proposalId, block.timestamp);
    }

    function queueTransaction(uint256 _proposalId) public isGoverence {
        // if the proposal completed its voting, when the proposal is queued we will queue the transaction
        require(s_transactions[_proposalId] == State.Sheduled, "Time lock : Transaction is not sheduled");
        s_transactions[_proposalId] = State.Queued;
        emit QueuedTransaction(_proposalId, block.timestamp);
    }

    function cancelTransaction(uint256 _proposalId) public isGoverence {
        // if a proposal is canceled then we cancel the transaction
        require(s_transactions[_proposalId] != State.Executed, "Time lock : Transaction is already executed");
        require(s_transactions[_proposalId] != State.Canceled, "Time lock : Transaction is already executed");

        s_transactions[_proposalId] = State.Canceled;
        emit CancelTransaction(_proposalId, block.timestamp);
    }

    function executeTransaction(uint256 _proposalId, bytes memory _data) public isGoverence returns (bytes memory) {
        // if the proposal is executed, then we will execute the transaction
        require(s_transactions[_proposalId] == State.Queued, "Time lock : Transaction is not queued");
        s_transactions[_proposalId] = State.Executed;

        (bool success, bytes memory returnData) = TOKEN_FACTORY.call(_data);
        require(success, "Time lock : Transaction execution reverted.");
        emit ExecuteTransaction(_proposalId, block.timestamp);

        return returnData;
    }

    function emergencyExecute(bytes memory _params) external onlyOwner returns (bytes memory) {
        /* here we execuet the function directly. Here there is no need to propose a proposal */
        (bool success, bytes memory returnData) = TOKEN_FACTORY.call(_params);
        require(success, "Time lock : Transaction execution reverted.");

        return returnData;
    }
}
