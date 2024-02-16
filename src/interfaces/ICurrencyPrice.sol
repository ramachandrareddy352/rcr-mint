// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ICurrencyPrice {
    function s_symbolsCount() external view returns (uint256);
    function getPriceOfSymbol(bytes32 symbol) external view returns (uint256);
}
