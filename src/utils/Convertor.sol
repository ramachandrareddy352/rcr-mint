// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

contract Convertor {
    function stringToBytes32(string memory str) public pure returns (bytes32 result) {
        // Ensure the input string is not longer than 32 characters
        require(bytes(str).length <= 32, "Convertor : String is too long");
        assembly {
            result := mload(add(str, 32))
        }
    }

    function bytes32ToString(bytes32 data) public pure returns (string memory) {
        bytes memory bytesData = new bytes(32);
        for (uint256 i = 0; i < 32; i++) {
            bytesData[i] = data[i];
        }

        // Find the end of the string (trimming trailing zeros)
        uint256 end;
        for (end = 31; end > 0; end--) {
            if (bytesData[end] != 0) {
                break;
            }
        }

        bytes memory trimmedBytes = new bytes(end + 1);
        for (uint256 j = 0; j <= end; j++) {
            trimmedBytes[j] = bytesData[j];
        }

        return string(trimmedBytes);
    }

    function splitSignature(bytes memory sig) public pure returns (bytes32 r, bytes32 s, uint8 v) {
        require(sig.length == 65, "Convertor : Invalid signature length");
        assembly {
            r := mload(add(sig, 32))
            s := mload(add(sig, 64))
            v := byte(0, mload(add(sig, 96)))
        }
    }
}
