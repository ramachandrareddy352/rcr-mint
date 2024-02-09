// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

interface IConvertor {
    function stringToBytes32(string memory str) external pure returns (bytes32 result);
    function bytes32ToString(bytes32 data) external pure returns (string memory);
    function splitSignature(bytes memory sig) external pure returns (bytes32 r, bytes32 s, uint8 v);
}
