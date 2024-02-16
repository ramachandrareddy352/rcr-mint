// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

interface AggregatorV3Interface {
    function decimals() external view returns (uint8);
    function latestAnswer() external view returns (int256 price);
}
