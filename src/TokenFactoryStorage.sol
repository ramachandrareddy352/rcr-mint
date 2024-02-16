// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract TokenFactoryStorage {
    event TokenContractCreated(
        address indexed currencyTokenContract, address owner, string symbol, string name, address createdBy
    );

    event TokenContractRemoved(address indexed tokenContractAddress, bytes32 tokenSymbol, address removedBy);

    event CollateralTokenAdded(
        address indexed collateralTokenAddress,
        address indexed pricefeedAddress,
        bytes32 collateralSymbol,
        uint16 initialBonus,
        uint16 initialFlashfeePercentage
    );

    event CollateralTokenRemoved(address indexed collateralTokenAddress, bytes32 collateralSymbol);

    event MintTokens(
        address indexed mintedTo,
        uint256 collateralAmount,
        uint256 currencyTokensMinted,
        uint256 collateralValueInUsd,
        bytes32 collateralSymbol,
        bytes32 currencySymbol
    );

    event FlashMintTokens(
        address indexed initiator,
        address indexed receiver,
        uint256 currencyAmountMinted,
        uint256 feeInTermsOfCollateral,
        bytes32 currencySymbol,
        bytes32 collateralSymbol
    );

    struct TraderData {
        uint256 totalTraded; // Total amount of owner traded in terms of usd
        uint256 tradedWithEth; // Total amount of owner draded using ethers
        mapping(address collateralToken => uint256 amount) collateralTokenTraded; // amount in 1e18
        // Using collateral amount th eowner traded details
        mapping(address curencyTokenContract => uint256 amount) curencyTokenTraded; // amount in 1e18
    }
    // Total currency tokens that the owner got in exchange
    // Above mapping is total minted by owner, after transfering currency tokens it is not tracked.
    // So for display of trader info show both curencyTokenTraded and their current balance using IERC20().balanceOf();
    // All currency tokens and all collateral amounts traded is shown with 18 decimal values

    struct CollateralData {
        uint256 totalTraded; // Total collateral traded (decimals - 18), even usdc, usdt shows in 18 decimals
        address pricefeedAddress; // chainlink pricefeed adddress to compute the price of collateral
        uint16 bonus; // 100% = 10000 (1% = 100)
        uint16 flashFeePercent; // 100% = 10000 (1% = 100)
        bool isExist; // exist tokens are considered as a collateral
    }

    uint256 internal constant TOKEN_MINT_PRECISION = 1e6;
    uint256 internal constant FLASH_FEE_PRECISION1 = 1e4;
    uint256 internal constant FLASH_FEE_PRECISION2 = 1e10;
    bytes32 internal constant CALLBACK_SUCCESS = keccak256("IFlashLoanReceiver.executeFlashloan");
    // call back return value for `executeFlashloan` function for flashloans

    uint256 internal s_ethBalance; // address(this).balance
    address internal s_ethReceiver; // address who receives the ethers deposited in this contract

    uint256 internal s_totalVolumeTraded; // total voulme that had traded in terms of USD (decimas-18)

    mapping(address trader => TraderData) internal s_ownerTradedData;
    mapping(bytes32 currencySymbol => address CurrencyTokenContract) internal s_symbolToCurrencyTokenContracts;
    mapping(bytes32 collateralSymbol => address collateralToken) internal s_symbolToCollateralToken;
    mapping(address collateralToken => CollateralData) internal s_collateralTokenToCollateralData;

    bytes32[] internal s_allCollateralSymbols;
    bytes32[] internal s_allCurrencyTokenSymbols;
}
