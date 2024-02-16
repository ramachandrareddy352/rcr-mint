// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.18;

interface IGoverenceToken {
    function pause() external;
    function unpause() external;
    function s_ownersCount() external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
}
