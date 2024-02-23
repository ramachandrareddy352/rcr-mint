// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.18;

interface ITimeLock {
    enum State {
        Default,
        Sheduled,
        Queued,
        Canceled,
        Executed
    }

    function sheduleTransaction(uint256 _proposalId) external;
    function s_transactions(uint256 _proposalId) external view returns (State);
    function queueTransaction(uint256 _proposalId) external;
    function cancelTransaction(uint256 _proposalId) external;
    function executeTransaction(uint256 _proposalId, bytes memory _data) external returns (bytes memory);
}
