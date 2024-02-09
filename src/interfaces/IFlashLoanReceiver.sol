// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.20;

interface IFlashLoanReceiver {
    function executeFlashloan(
        address token,
        uint256 amount, /* uint256 fee, */
        address initiator,
        bytes calldata params
    ) external returns (bytes32);
    // fee will apply when swaping
    // in token factory the fee is taken as collateral
}
