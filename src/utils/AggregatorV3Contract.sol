// SPDX-Licence-Identifier: MIT
pragma solidity ^0.8.18;

import {AggregatorV3Interface} from "../interfaces/AggregatorV3Interface.sol";

contract AggregatorV3Contract {
    function getLatestPrice(address priceFeedAddress) public view returns (uint256, uint8) {
        int256 price = AggregatorV3Interface(priceFeedAddress).latestAnswer();
        uint8 decimals = AggregatorV3Interface(priceFeedAddress).decimals();

        return (uint256(price), decimals);
    }
}
