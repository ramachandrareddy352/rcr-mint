// SPDX-License-Identifier: MIT
pragma solidity =0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import {AggregatorV3Interface} from "./interfaces/AggregatorV3Interface.sol";
import {IFlashLoanReceiver} from "./interfaces/IFlashLoanReceiver.sol";
import {ICurrencyTokenContract} from "./interfaces/ICurrencyTokenContract.sol";
import {ICurrencyPrice} from "./interfaces/ICurrencyPrice.sol";
import {IConvertor} from "./interfaces/IConvertor.sol";
import {SafeMath} from "./libraries/SafeMath.sol";
import {CurrencyTokenContract} from "./CurrencyTokenContract.sol";
import {GoverenceToken} from "./GoverenceToken.sol";
import {TokenFactoryStorage} from "./TokenFactoryStorage.sol";

/*
 => Owner of this contract is Time lock contract
 => 
 */

contract TokenFactory is TokenFactoryStorage, Ownable, ReentrancyGuard {
    using SafeMath for uint256;

    IConvertor internal immutable i_convertor;
    GoverenceToken internal immutable i_goverenceToken;
    // The amount of currency tokens are minted in terms of usd, that much amount of goverence tokens are minted
    ICurrencyPrice internal i_currencyPrice;

    receive() external payable {}

    // first token factory is deployed by admin and owner of token factory is changed later to timelock controller
    constructor(
        address _owner,
        address _currencyPrice,
        address _convertor,
        address _ethReceiver,
        address _goverenceContract
    ) Ownable(_owner) {
        // Owner of this contract factory is TimeLock contract
        i_currencyPrice = ICurrencyPrice(_currencyPrice);
        i_goverenceToken = new GoverenceToken(_owner, _goverenceContract, address(this));
        // owner of goverence contract is token facotory
        i_convertor = IConvertor(_convertor);
        s_ethReceiver = _ethReceiver;
    }

    /* -------------------------- Add collateral data ---------------------------- */

    function addMultipleCollateralData(
        bytes32[] memory _collateralSymbols,
        address[] memory _collateralTokens,
        address[] memory _pricefeedAddress,
        uint16[] memory _bonuses,
        uint16[] memory _flashFees
    ) external nonReentrant onlyOwner {
        require(
            _collateralSymbols.length == _collateralTokens.length
                && _collateralTokens.length == _pricefeedAddress.length && _pricefeedAddress.length == _bonuses.length
                && _bonuses.length == _flashFees.length && _flashFees.length > 0,
            "Token factory : Invalid length of elements"
        );

        for (uint256 i = 0; i < _bonuses.length;) {
            _addCollateralData(
                _collateralSymbols[i], _collateralTokens[i], _pricefeedAddress[i], _bonuses[i], _flashFees[i]
            );

            unchecked {
                i = i.add(1);
            }
        }
    }

    function addSingleCollateralData(
        bytes32 _collateralSymbol,
        address _collateralToken,
        address _pricefeedAddress,
        uint16 _bonus,
        uint16 _flashFee
    ) external nonReentrant onlyOwner {
        _addCollateralData(_collateralSymbol, _collateralToken, _pricefeedAddress, _bonus, _flashFee);
    }

    function _addCollateralData(
        bytes32 _collateralSymbol,
        address _collateralToken,
        address _pricefeedAddress,
        uint16 _bonus,
        uint16 _flashfee
    ) private {
        require(
            s_symbolToCollateralToken[_collateralSymbol] == address(0),
            "Token factory : collateral symbol is already exist"
        );
        require(!isCollateralDataExist(_collateralToken), "Token factory : Collateral is already exist");
        require(_flashfee > 0 && _bonus > 0, "Token factory : Invalid flash fee or bonus");
        require(
            _collateralToken != address(0) && _pricefeedAddress != address(0), "Token factory : Invalid zero address"
        );

        s_symbolToCollateralToken[_collateralSymbol] = _collateralToken;
        s_collateralTokenToCollateralData[_collateralToken] =
            CollateralData(0, _pricefeedAddress, _bonus, _flashfee, true);
        s_allCollateralSymbols.push(_collateralSymbol);

        emit CollateralTokenAdded(_collateralToken, _pricefeedAddress, _collateralSymbol, _bonus, _flashfee);
    }

    /* -------------------------- Remove collateral data ----------------------------- */

    function removeMultipleCollateralData(bytes32 _collateralSymbols) external nonReentrant onlyOwner {
        require(_collateralSymbols.length > 0, "Token factory : length is zero");

        for (uint256 i = 0; i < _collateralSymbols.length;) {
            _removeCollateralData(_collateralSymbols[i]);

            unchecked {
                i = i.add(1);
            }
        }
    }

    function removeSingleleCollateralData(bytes32 _collateralSymbol) external nonReentrant onlyOwner {
        _removeCollateralData(_collateralSymbol);
    }

    function _removeCollateralData(bytes32 _collateralSymbol) private {
        address m_collateralToken = s_symbolToCollateralToken[_collateralSymbol];

        require(
            m_collateralToken != address(0) && isCollateralDataExist(m_collateralToken),
            "Token factory : Collateral is not exist"
        );

        delete s_symbolToCollateralToken[_collateralSymbol];
        delete s_collateralTokenToCollateralData[m_collateralToken];

        // before removing collateral all the balance is transfered to the eth receiver address
        uint256 m_balance = IERC20(m_collateralToken).balanceOf(address(this));
        _withdrawCollateralToken(s_ethReceiver, m_collateralToken, m_balance);

        bytes32[] memory m_allCollateralSymbols = s_allCollateralSymbols;

        for (uint256 i = 0; i < m_allCollateralSymbols.length;) {
            if (m_allCollateralSymbols[i] == _collateralSymbol) {
                s_allCollateralSymbols[i] = m_allCollateralSymbols[m_allCollateralSymbols.length.sub(1)];
                s_allCollateralSymbols.pop();

                emit CollateralTokenRemoved(m_collateralToken, _collateralSymbol);
                break;
            }

            unchecked {
                i = i.add(1);
            }
        }
    }

    /* ------------------------ Update Collateral bonus ------------------------ */

    function updateMultipleCollateralBonus(bytes32[] memory _collateralSymbols, uint16[] memory _newBonus)
        external
        nonReentrant
        onlyOwner
    {
        require(_collateralSymbols.length == _newBonus.length && _newBonus.length > 0, "Token factory : Invalid length");

        for (uint256 i = 0; i < _collateralSymbols.length;) {
            _updateBonus(_collateralSymbols[i], _newBonus[i]);

            unchecked {
                i = i.add(1);
            }
        }
    }

    function updateSingleCollateralBonus(bytes32 _collateralSymbol, uint16 _newBonus) external nonReentrant onlyOwner {
        _updateBonus(_collateralSymbol, _newBonus);
    }

    function _updateBonus(bytes32 _collateralSymbol, uint16 _newBonus) private {
        address m_collateralAddress = s_symbolToCollateralToken[_collateralSymbol];

        require(m_collateralAddress != address(0), "Token factory : Invalid collateral address");
        require(isCollateralDataExist(m_collateralAddress), "Token factory : collateral data not exist");
        require(_newBonus > 0, "Token factory : Invalid bonus");

        s_collateralTokenToCollateralData[m_collateralAddress].bonus = _newBonus;
    }

    /* -------------------- Update Collateral Pricefeed address ---------------------- */

    function updateMultiplePricefeedAddress(bytes32[] memory _collateralSymbols, address[] memory _pricefeedAddress)
        external
        nonReentrant
        onlyOwner
    {
        require(
            _collateralSymbols.length == _pricefeedAddress.length && _pricefeedAddress.length > 0,
            "Token factory : Invalid length"
        );

        for (uint256 i = 0; i < _collateralSymbols.length;) {
            _updatepricefeedAddress(_collateralSymbols[i], _pricefeedAddress[i]);

            unchecked {
                i = i.add(1);
            }
        }
    }

    function updateSinglePricefeedAddress(bytes32 _collateralSymbol, address _pricefeedAddress)
        external
        nonReentrant
        onlyOwner
    {
        _updatepricefeedAddress(_collateralSymbol, _pricefeedAddress);
    }

    function _updatepricefeedAddress(bytes32 _collateralSymbol, address _pricefeedAddress) private {
        address m_collateralAddress = s_symbolToCollateralToken[_collateralSymbol];

        require(m_collateralAddress != address(0), "Token factory : Invalid collateral address");
        require(isCollateralDataExist(m_collateralAddress), "Token factory : collateral data not exist");
        require(_pricefeedAddress != address(0), "Token factory : Invalid pricefeed Address");

        s_collateralTokenToCollateralData[m_collateralAddress].pricefeedAddress = _pricefeedAddress;
    }

    /* ------------------ Update Collateral Percentage ----------------------- */

    function updateMultipleFlashFeePercentage(bytes32[] memory _collateralSymbols, uint16[] memory _flashfees)
        external
        nonReentrant
        onlyOwner
    {
        require(
            _collateralSymbols.length == _flashfees.length && _flashfees.length > 0, "Token factory : Invalid length"
        );

        for (uint256 i = 0; i < _collateralSymbols.length;) {
            _updateFlashFeePercentage(_collateralSymbols[i], _flashfees[i]);

            unchecked {
                i = i.add(1);
            }
        }
    }

    function updateSingleFlashFeePercentage(bytes32 _collateralSymbol, uint16 _flashfee)
        external
        nonReentrant
        onlyOwner
    {
        _updateFlashFeePercentage(_collateralSymbol, _flashfee);
    }

    function _updateFlashFeePercentage(bytes32 _collateralSymbol, uint16 _newflashfee) private {
        address m_collateralAddress = s_symbolToCollateralToken[_collateralSymbol];

        require(m_collateralAddress != address(0), "Token factory : Invalid collateral address");
        require(isCollateralDataExist(m_collateralAddress), "Token factory : collateral data not exist");
        require(_newflashfee > 0, "Token factory : Invalid flash fee");

        s_collateralTokenToCollateralData[m_collateralAddress].flashFeePercent = _newflashfee;
    }

    /* ------------------ Create Currency token contracts ------------------ */

    function createMultipleCurrencyTokenContracts(string[] memory _names, string[] memory _symbols)
        external
        nonReentrant
        onlyOwner
    {
        require(_names.length == _symbols.length && _names.length > 0, "Token factory : Invalid length");

        for (uint256 i = 0; i < _names.length;) {
            _createCurrencyTokenContract(_names[i], _symbols[i]);

            unchecked {
                i = i.add(1);
            }
        }
    }

    function createSingleCurrencyTokenContract(string memory _name, string memory _symbol)
        external
        nonReentrant
        onlyOwner
    {
        _createCurrencyTokenContract(_name, _symbol);
    }

    function _createCurrencyTokenContract(string memory _name, string memory _symbol) private {
        bytes32 m_symbol = convertStringToBytes32(_symbol);
        require(s_symbolToCurrencyTokenContracts[m_symbol] == address(0), "Token factory : Symbol is already exist");

        CurrencyTokenContract currencyTokenContract = new CurrencyTokenContract(_name, _symbol);
        // Currency Token Contract owner is token factory

        s_symbolToCurrencyTokenContracts[m_symbol] = address(currencyTokenContract);
        s_allCurrencyTokenSymbols.push(m_symbol);

        emit TokenContractCreated(address(currencyTokenContract), address(this), _symbol, _name, owner());
    }

    /* ----------------- Remove Currency token contracts ---------------- */

    function removeMultipleTokenContracts(bytes32[] memory _symbols) external nonReentrant onlyOwner {
        require(_symbols.length > 0, "Token factory : length is zero");

        for (uint256 i = 0; i < _symbols.length;) {
            _removeTokenContract(_symbols[i]);

            unchecked {
                i = i.add(1);
            }
        }
    }

    function removeSingleleTokenContracts(bytes32 _symbol) external nonReentrant onlyOwner {
        _removeTokenContract(_symbol);
    }

    function _removeTokenContract(bytes32 _symbol) private {
        require(s_symbolToCurrencyTokenContracts[_symbol] != address(0), "Token factory : Symbol is not exist");

        address m_currencyTokenContract = s_symbolToCurrencyTokenContracts[_symbol];
        bytes32[] memory m_allCurrencyTokenSymbols = s_allCurrencyTokenSymbols;

        delete s_symbolToCurrencyTokenContracts[_symbol];

        for (uint256 i = 0; i < m_allCurrencyTokenSymbols.length;) {
            if (m_allCurrencyTokenSymbols[i] == _symbol) {
                s_allCurrencyTokenSymbols[i] = m_allCurrencyTokenSymbols[(m_allCurrencyTokenSymbols.length).sub(1)];
                s_allCurrencyTokenSymbols.pop();

                emit TokenContractRemoved(m_currencyTokenContract, _symbol, owner());
                break;
            }

            unchecked {
                i = i.add(1);
            }
        }
    }

    /* ----------------- Withdraw collateral tokens --------------------- */

    function withdrawMultipleCollateralTokens(
        address _to,
        address[] memory _collateralTokens,
        uint256[] memory _amounts
    ) external nonReentrant {
        require(
            _collateralTokens.length == _amounts.length && _amounts.length > 0,
            "Token factory : Invalid elements length"
        );

        for (uint256 i = 0; i < _collateralTokens.length;) {
            _withdrawCollateralToken(_to, _collateralTokens[i], _amounts[i]);

            unchecked {
                i = i.add(1);
            }
        }
    }

    function withdrawSingleCollateralToken(address _to, address _collateralToken, uint256 _amount)
        external
        nonReentrant
    {
        _withdrawCollateralToken(_to, _collateralToken, _amount);
    }

    function _withdrawCollateralToken(address _to, address _collateralToken, uint256 _amount) private {
        // if we are withdrawing USDT or USDC check th edecimals
        require(msg.sender == s_ethReceiver, "Token factory : Unknown ether receiver");
        // no need to update collateral traded data
        require(_to != address(0), "Token factory : Invalid zero address");
        // amount may be zero also, if we are removing collaterall address from list if there are no balance it may leads to error
        require(
            _amount <= IERC20(_collateralToken).balanceOf(address(this)),
            "Token factory : Insufficient balance to withdraw"
        );

        IERC20(_collateralToken).transfer(_to, _amount);
    }

    /* -------------------- Withdraw Ethers ---------------------- */

    function withdrawEth(address _to, uint256 _amount) external nonReentrant {
        // if the _to is a contract address, make shore to have fallback or receive functions in contract
        require(msg.sender == s_ethReceiver, "Token factory : Unknown ether receiver");
        require(_to != address(0), "Token factory : Invalid zero address");

        uint256 m_ethBalance = s_ethBalance;
        require(_amount <= m_ethBalance && _amount > 0, "Token factory : Insufficient amount");
        s_ethBalance = m_ethBalance.sub(_amount);

        (bool success,) = payable(_to).call{value: _amount}("");
        require(success, "Token factory : withdraw failed");
    }

    /* -------------------- Update eth receiver address ------------------- */

    function changeEthReceiverAddress(address _newEthReceiver) external nonReentrant {
        // if the _newEthReceiver is a contract address, make shore to have fallback or receive
        require(msg.sender == s_ethReceiver, "Token factory : Unknown eth receiver");
        require(_newEthReceiver != address(0), "Token factory : Invalid zero address");

        s_ethReceiver = _newEthReceiver;
    }

    /* ------------------ Update Currency Price address ------------------- */

    function changeCurrencyPriceAddress(address _newCurrencyPrice) external nonReentrant onlyOwner {
        // change using goverence voting method
        require(_newCurrencyPrice != address(0), "Token factory : Invalid zero address");
        i_currencyPrice = ICurrencyPrice(_newCurrencyPrice);
    }

    /* ------------------------ Remove goverence power ------------------------ */

    function burnGoverenceTokens(uint256 _amount) external nonReentrant {
        address m_owner = msg.sender;
        uint256 m_balance = i_goverenceToken.balanceOf(m_owner);
        require(_amount <= m_balance, "Token factory : Insufficient balance");
        // checks are at goverence contract

        i_goverenceToken.burnTokens(m_owner, _amount);
    }

    /* ----------------------- Burn currency tokens ---------------------- */

    function burnMultipleCurrencyTokens(bytes32[] memory _currencySymbols, uint256[] memory _currencyAmounts)
        external
        nonReentrant
    {
        require(
            _currencySymbols.length == _currencyAmounts.length && _currencySymbols.length > 0,
            "Token factory : Invalid length of elements"
        );
        address m_owner = msg.sender;

        for (uint256 i = 0; i < _currencySymbols.length;) {
            _burnCurrencyTokens(m_owner, _currencySymbols[i], _currencyAmounts[i]);

            unchecked {
                i = i.add(1);
            }
        }
    }

    function burnSingleCurrencyToken(bytes32 _currencySymbol, uint256 _currencyAmount) external nonReentrant {
        _burnCurrencyTokens(msg.sender, _currencySymbol, _currencyAmount);
    }

    function _burnCurrencyTokens(address _from, bytes32 _currencySymbol, uint256 _currencyAmount) private {
        address m_currenctContract = s_symbolToCurrencyTokenContracts[_currencySymbol];
        uint256 m_balance = ICurrencyTokenContract(m_currenctContract).balanceOf(_from);

        require(_from != address(0), "Token factory : Invalid zero address");
        require(m_balance >= _currencyAmount && _currencyAmount > 0, "Token factory : Invalid currency amount");
        require(m_currenctContract != address(0), "Token factory : currency token is not exist");

        ICurrencyTokenContract(m_currenctContract).burnTokens(_from, _currencyAmount);
    }

    /* --------------------- Mint currency tokens with ethers ------------------ */

    function mintWithEth(address _to, bytes32 _currencySymbol) external payable nonReentrant {
        // zero address of (_to) is verified at CurrencyTokenContract
        bytes32 _weth = convertStringToBytes32("WETH");
        address m_currencyTokenContact = s_symbolToCurrencyTokenContracts[_currencySymbol];
        uint256 m_ethAmount = msg.value;

        (uint256 m_currencyTokensToMint, uint256 m_collateralValueInUsd,) =
            getTokenTomintForGivenCollateral(_weth, m_ethAmount, _currencySymbol);
        // both m_currencyTokensToMint, m_collateralValueInUsd have 18 decimals

        s_ethBalance = s_ethBalance.add(m_ethAmount);
        s_totalVolumeTraded = s_totalVolumeTraded.add(m_collateralValueInUsd);
        // s_totalVolumeTraded have 18 decimals

        TraderData storage s_traderData = s_ownerTradedData[msg.sender];

        s_traderData.totalTraded = (s_traderData.totalTraded).add(m_collateralValueInUsd);
        s_traderData.tradedWithEth = (s_traderData.tradedWithEth).add(m_ethAmount);
        s_traderData.curencyTokenTraded[m_currencyTokenContact] =
            s_traderData.curencyTokenTraded[m_currencyTokenContact].add(m_currencyTokensToMint);

        ICurrencyTokenContract(m_currencyTokenContact).mintTokens(_to, m_currencyTokensToMint);
        i_goverenceToken.mintTokens(_to, m_collateralValueInUsd);

        emit MintTokens(_to, m_ethAmount, m_currencyTokensToMint, m_collateralValueInUsd, _weth, _currencySymbol);
    }

    /* ---------- Calculates Currency tokens to mint  for given collateral value --------- */

    function getTokenTomintForGivenCollateral(
        bytes32 _collateralSymbol,
        uint256 _collateralAmount,
        bytes32 _currencySymbol
    ) public view returns (uint256, uint256, uint256) {
        // return usd value of collateral to mint goverence tokens and currency tokens to mint
        require(
            s_symbolToCurrencyTokenContracts[_currencySymbol] != address(0),
            "Token factory : Currency token is not exist"
        );
        require(_collateralAmount > 0, "Token factory : value should be greater than zero");

        address m_collateralTokenAddress = s_symbolToCollateralToken[_collateralSymbol];
        CollateralData memory m_collateralData = s_collateralTokenToCollateralData[m_collateralTokenAddress];
        require(
            m_collateralTokenAddress != address(0) && m_collateralData.isExist,
            "Token factory : Invalid collateral token"
        );

        uint256 m_collateralDecimals = IERC20(m_collateralTokenAddress).decimals();

        if (m_collateralDecimals != 18) {
            if (m_collateralDecimals > 18) {
                _collateralAmount = _collateralAmount.div(10 ** (m_collateralDecimals - 18));
            } else {
                _collateralAmount = _collateralAmount.mul(10 ** (18 - m_collateralDecimals));
            }
        }

        address m_pricefeedAddress = m_collateralData.pricefeedAddress;
        uint256 m_pricefeedDecimals = AggregatorV3Interface(m_pricefeedAddress).decimals();
        uint256 m_priceOfCollateralInUsd = uint256(AggregatorV3Interface(m_pricefeedAddress).latestAnswer());

        if (m_pricefeedDecimals != 8) {
            if (m_pricefeedDecimals > 8) {
                m_priceOfCollateralInUsd = m_priceOfCollateralInUsd.div(10 ** (m_pricefeedDecimals - 8));
            } else {
                m_priceOfCollateralInUsd = m_priceOfCollateralInUsd.mul(10 ** (8 - m_pricefeedDecimals));
            }
        }

        uint256 m_collateralValueInUsd = (m_priceOfCollateralInUsd.mul(_collateralAmount)).div(10 ** 8); // returns - 18 decimals
        uint256 m_numerator =
            m_collateralValueInUsd * i_currencyPrice.getPriceOfSymbol(_currencySymbol) * m_collateralData.bonus;

        return (m_numerator.div(TOKEN_MINT_PRECISION), m_collateralValueInUsd, _collateralAmount);
    }

    /* ---------------- Mint Currency tokens with collaterals ----------------- */

    function mithWithMultipleCollateral(
        address _to,
        bytes32[] memory _currencySymbols,
        bytes32[] memory _collateralSymbols,
        uint256[] memory _collateralAmounts
    ) external nonReentrant {
        require(
            _currencySymbols.length > 0 && _currencySymbols.length == _collateralSymbols.length
                && _collateralSymbols.length == _collateralAmounts.length && _collateralAmounts.length > 0,
            "Token factory : Invalid length of elements"
        );

        address _minter = msg.sender;

        for (uint256 i = 0; i < _currencySymbols.length;) {
            _mithWithCollateral(_minter, _to, _currencySymbols[i], _collateralSymbols[i], _collateralAmounts[i]);

            unchecked {
                i = i.add(1);
            }
        }
    }

    function mintWithSingleCollateral(
        address _to,
        bytes32 _currencySymbol,
        bytes32 _collateralSymbol,
        uint256 _collateralAmount
    ) external nonReentrant {
        _mithWithCollateral(msg.sender, _to, _currencySymbol, _collateralSymbol, _collateralAmount);
    }

    function _mithWithCollateral(
        address _from,
        address _to,
        bytes32 _currencySymbol,
        bytes32 _collateralSymbol,
        uint256 _collateralAmount
    ) private {
        // zero address of (_to) is verified at CurrencyTokenContract
        // this function takes the approve collateral tokens to address(this) for another transaction
        address m_currencyTokenContact = s_symbolToCurrencyTokenContracts[_currencySymbol];
        address m_collateralTokenAddress = s_symbolToCollateralToken[_collateralSymbol];

        IERC20(m_collateralTokenAddress).transferFrom(_from, address(this), _collateralAmount);

        (uint256 m_currencyTokensToMint, uint256 m_collateralValueInUsd, uint256 m_collateralAmount) =
            getTokenTomintForGivenCollateral(_collateralSymbol, _collateralAmount, _currencySymbol);

        s_totalVolumeTraded = s_totalVolumeTraded.add(m_collateralValueInUsd);
        // s_totalVolumeTraded have 18 decimals

        TraderData storage s_traderData = s_ownerTradedData[_from];

        s_traderData.totalTraded = (s_traderData.totalTraded).add(m_collateralValueInUsd);

        s_traderData.collateralTokenTraded[m_collateralTokenAddress] =
            s_traderData.collateralTokenTraded[m_collateralTokenAddress].add(m_collateralAmount);

        s_traderData.curencyTokenTraded[m_currencyTokenContact] =
            s_traderData.curencyTokenTraded[m_currencyTokenContact].add(m_currencyTokensToMint);

        s_collateralTokenToCollateralData[m_collateralTokenAddress].totalTraded =
            (s_collateralTokenToCollateralData[m_collateralTokenAddress].totalTraded).add(m_collateralAmount);

        ICurrencyTokenContract(m_currencyTokenContact).mintTokens(_to, m_currencyTokensToMint);
        i_goverenceToken.mintTokens(_from, m_collateralValueInUsd);
        // currency tokens are minted to _to address and goverence power is goes to msg.sender
        emit MintTokens(
            _to, _collateralAmount, m_currencyTokensToMint, m_collateralValueInUsd, _collateralSymbol, _currencySymbol
        );
    }

    /* ------ Mint currency token by approve collateral tokens uisng signature ------- */

    function mintWithMultiplePermits(
        bytes32[] memory _collateralSymbols,
        bytes32[] memory _currencySymbols,
        address[] memory _owners,
        address[] memory _spenders,
        address[] memory _mintTo,
        uint256[] memory _collateralAmounts,
        uint256[] memory _deadlines,
        uint8[] memory _v,
        bytes32[] memory _r,
        bytes32[] memory _s
    ) external nonReentrant {
        require(
            _collateralSymbols.length == _currencySymbols.length && _currencySymbols.length == _owners.length
                && _owners.length == _spenders.length && _spenders.length == _collateralAmounts.length
                && _collateralAmounts.length == _v.length && _v.length == _r.length && _r.length == _s.length
                && _s.length == _deadlines.length && _mintTo.length == _s.length && _s.length > 0,
            "Token factory : Invalid length array elements"
        );

        address m_minter = msg.sender;
        address m_tokenFactory = address(this);

        for (uint256 i = 0; i < _v.length;) {
            require(
                _spenders[i] == m_tokenFactory && _owners[i] == m_minter,
                "Token factory : Invalid spender or receiver address"
            );

            _mintWithPermit(
                _collateralSymbols[i],
                _collateralSymbols[i],
                _owners[i],
                _spenders[i],
                _mintTo[i],
                _collateralAmounts[i],
                _deadlines[i],
                _v[i],
                _r[i],
                _s[i]
            );

            unchecked {
                i = i.add(1);
            }
        }
    }

    function mintWithSinglePermits(
        bytes32 _collateralSymbol,
        bytes32 _currencySymbol,
        address _owner,
        address _spender,
        address _mintTo,
        uint256 _collateralAmount,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external nonReentrant {
        require(
            _spender == address(this) && _owner == msg.sender, "Token factory : Invalid spender or receiver address"
        );

        _mintWithPermit(
            _collateralSymbol, _currencySymbol, _owner, _spender, _mintTo, _collateralAmount, _deadline, _v, _r, _s
        );
    }

    function _mintWithPermit(
        bytes32 _collateralSymbol,
        bytes32 _currencySymbol,
        address _owner,
        address _spender,
        address _mintTo,
        uint256 _collateralAmount,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) private {
        // approve _spender as address(this) contract
        // checks are at getTokenTomintForGivenCollateral() function
        address m_currencyTokenContact = s_symbolToCurrencyTokenContracts[_currencySymbol];
        address m_collateralTokenAddress = s_symbolToCollateralToken[_collateralSymbol];

        IERC20(m_collateralTokenAddress).permit(_owner, _spender, _collateralAmount, _deadline, _v, _r, _s);

        // here transferFrom is called from token factory(msg.sender), so he have to maintain allowance from _owner tokens to spend
        IERC20(m_collateralTokenAddress).transferFrom(_owner, _spender, _collateralAmount);

        (uint256 m_currencyTokensToMint, uint256 m_collateralValueInUsd, uint256 m_collateralAmount) =
            getTokenTomintForGivenCollateral(_collateralSymbol, _collateralAmount, _currencySymbol);

        s_totalVolumeTraded = s_totalVolumeTraded.add(m_collateralValueInUsd);
        // s_totalVolumeTraded have 18 decimals

        TraderData storage s_traderData = s_ownerTradedData[_owner];

        s_traderData.totalTraded = (s_traderData.totalTraded).add(m_collateralValueInUsd);

        s_traderData.collateralTokenTraded[m_collateralTokenAddress] =
            s_traderData.collateralTokenTraded[m_collateralTokenAddress].add(m_collateralAmount);

        s_traderData.curencyTokenTraded[m_currencyTokenContact] =
            s_traderData.curencyTokenTraded[m_currencyTokenContact].add(m_currencyTokensToMint);

        s_collateralTokenToCollateralData[m_collateralTokenAddress].totalTraded =
            (s_collateralTokenToCollateralData[m_collateralTokenAddress].totalTraded).add(m_collateralAmount);

        ICurrencyTokenContract(m_currencyTokenContact).mintTokens(_mintTo, m_currencyTokensToMint);
        i_goverenceToken.mintTokens(_owner, m_collateralValueInUsd);

        emit MintTokens(
            _owner,
            _collateralAmount,
            m_currencyTokensToMint,
            m_collateralValueInUsd,
            _collateralSymbol,
            _currencySymbol
        );
    }

    /* ------------- Flash mint the currency tokens by sending fee as collateral tokens ------------- */

    function flashMintWithCollateral(
        IFlashLoanReceiver _receiver,
        bytes32 _currencySymbol,
        uint256 _currencyAmountToMint,
        bytes32 _collateralSymbol,
        bytes memory _params
    ) external nonReentrant {
        // verify given receiver is contract or not
        require(address(_receiver).code.length > 0, "Token factory : flashloan receiver is not a contract or fallback");

        (uint256 m_mintAmountInUsd,, uint256 m_feeInTermsOfCollateral) =
            flashMintFee(_collateralSymbol, _currencyAmountToMint, _currencySymbol);

        address m_collateralAddress = s_symbolToCollateralToken[_collateralSymbol];

        s_totalVolumeTraded = s_totalVolumeTraded.add(m_mintAmountInUsd);

        s_collateralTokenToCollateralData[m_collateralAddress].totalTraded =
            (s_collateralTokenToCollateralData[m_collateralAddress].totalTraded).add(m_feeInTermsOfCollateral);

        // approve address(this) before token transfer
        IERC20(m_collateralAddress).transferFrom(msg.sender, address(this), m_feeInTermsOfCollateral);

        require(
            _flashMintLogic(
                _receiver,
                s_symbolToCurrencyTokenContracts[_currencySymbol],
                msg.sender,
                address(this),
                _currencyAmountToMint,
                _params
            ),
            "Token factory : Failed in flash loan logic execution"
        );

        emit FlashMintTokens(
            msg.sender,
            address(_receiver),
            _currencyAmountToMint,
            m_feeInTermsOfCollateral,
            _currencySymbol,
            _collateralSymbol
        );
    }

    /* ---------- Flash mint the currency tokens by sending fee as ethers -------------- */

    function flashMintWithEth(
        IFlashLoanReceiver _receiver,
        uint256 _currencyAmountToMint,
        bytes32 _currencySymbol,
        bytes memory _params
    ) external payable nonReentrant {
        // verify given receiver is contract or not
        require(address(_receiver).code.length > 0, "Token factory : flashloan receiver is not a contract or fallback");

        (uint256 m_mintAmountInUsd,, uint256 m_feeInTermsOfCollateral) =
            flashMintFee(i_convertor.stringToBytes32("WETH"), _currencyAmountToMint, _currencySymbol);

        uint256 m_ethAmount = msg.value;
        require(m_feeInTermsOfCollateral == m_ethAmount, "Token factory : Invalid fees amount");

        s_totalVolumeTraded = s_totalVolumeTraded.add(m_mintAmountInUsd);
        s_ethBalance = s_ethBalance.add(m_ethAmount);

        require(
            _flashMintLogic(
                _receiver,
                s_symbolToCurrencyTokenContracts[_currencySymbol],
                msg.sender,
                address(this),
                _currencyAmountToMint,
                _params
            ),
            "Token factory : Failed in flash mint logic"
        );

        emit FlashMintTokens(
            msg.sender,
            address(_receiver),
            _currencyAmountToMint,
            m_feeInTermsOfCollateral,
            _currencySymbol,
            i_convertor.stringToBytes32("WETH")
        );
    }

    /* ------ Flash mint the currency tokens by sending fee as collateral tokens using signature approval ------ */

    function flashMintWithCollateralAndPermit(
        IFlashLoanReceiver _receiver,
        bytes32 _currencySymbol,
        uint256 _currencyAmountToMint,
        bytes32 _collateralSymbol,
        bytes memory _params,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external nonReentrant {
        require(
            address(_receiver).code.length > 0,
            "Token factory : flashloan receiver is not a contract or may not have fallback"
        );

        address m_collateralAddress = s_symbolToCollateralToken[_collateralSymbol];
        address m_initiator = msg.sender;
        address m_tokenFactory = address(this);

        (uint256 m_mintAmountInUsd,, uint256 m_feeInTermsOfCollateral) =
            flashMintFee(_collateralSymbol, _currencyAmountToMint, _currencySymbol);

        s_totalVolumeTraded = s_totalVolumeTraded.add(m_mintAmountInUsd);
        s_collateralTokenToCollateralData[m_collateralAddress].totalTraded =
            (s_collateralTokenToCollateralData[m_collateralAddress].totalTraded).add(m_feeInTermsOfCollateral);

        IERC20(m_collateralAddress).permit(m_initiator, m_tokenFactory, m_feeInTermsOfCollateral, _deadline, _v, _r, _s);
        IERC20(m_collateralAddress).transferFrom(m_initiator, m_tokenFactory, m_feeInTermsOfCollateral);

        require(
            _flashMintLogic(
                _receiver,
                s_symbolToCurrencyTokenContracts[_currencySymbol],
                msg.sender,
                address(this),
                _currencyAmountToMint,
                _params
            ),
            "Token factory : Failed in logic execution"
        );

        emit FlashMintTokens(
            msg.sender,
            address(_receiver),
            _currencyAmountToMint,
            m_feeInTermsOfCollateral,
            _currencySymbol,
            _collateralSymbol
        );
    }

    /*-------------- flash mint logic implementation -----------------*/

    function _flashMintLogic(
        IFlashLoanReceiver _receiver,
        address _currencyTokenContact,
        address _initiator,
        address _tokenFactory,
        uint256 _currencyAmountToMint,
        bytes memory _params
    ) private returns (bool) {
        uint256 m_beforeCurrencyBalance = ICurrencyTokenContract(_currencyTokenContact).totalSupply();

        ICurrencyTokenContract(_currencyTokenContact).mintTokens(address(_receiver), _currencyAmountToMint);

        /* logic will be executed here */
        require(
            _receiver.executeFlashloan(_currencyTokenContact, _currencyAmountToMint, _initiator, _params)
                == CALLBACK_SUCCESS,
            "Token factory : Callback success failed"
        );

        /*
        _receiver.functionCall(
            abi.encodeCall(
                IFlashLoanReceiver.executeFlashloan,
                (
                    _currencyTokenContact,
                    _currencyAmountToMint,
                    msg.sender, // initiator;
                    _params
                )
            )
        );
        */

        ICurrencyTokenContract(_currencyTokenContact).transferFrom(
            address(_receiver), _tokenFactory, _currencyAmountToMint
        );
        // after minting approve address(this) after executing flash loan login, then tokens are transfered
        ICurrencyTokenContract(_currencyTokenContact).burnTokens(_tokenFactory, _currencyAmountToMint);

        uint256 m_afterCurrencyBalance = ICurrencyTokenContract(_currencyTokenContact).totalSupply();
        return m_afterCurrencyBalance == m_beforeCurrencyBalance;
    }

    /* --------- Calculate the amount of collateral fee for flash minting currency tokens --------- */

    function flashMintFee(bytes32 _collateralSymbol, uint256 _currencyAmountToMint, bytes32 _currencySymbol)
        public
        view
        returns (uint256 m_mintAmountInUsd, uint256 m_flashFeeInUsd, uint256 m_feeInTermsOfCollateral)
    {
        address m_collateralAddress = s_symbolToCollateralToken[_collateralSymbol];
        require(m_collateralAddress != address(0), "Token factory : Invalid collateral token address");
        require(
            s_symbolToCurrencyTokenContracts[_currencySymbol] != address(0),
            "Token factory : Invalid currency token address"
        );

        CollateralData memory collateralData = s_collateralTokenToCollateralData[m_collateralAddress];

        m_mintAmountInUsd = _calculateMintAmountInUsd(_currencyAmountToMint, _currencySymbol); // 1
        m_flashFeeInUsd = _calculateFeeInTermsOfUsd(m_mintAmountInUsd, collateralData.flashFeePercent); // 2
        m_feeInTermsOfCollateral =
            _calculateFeeInTermsOfCollateral(m_flashFeeInUsd, m_collateralAddress, collateralData.pricefeedAddress);
    }

    function _calculateMintAmountInUsd(uint256 _currencyAmountToMint, bytes32 _currencySymbol)
        private
        view
        returns (uint256)
    {
        require(_currencyAmountToMint > 0, "Token factory : Invalid amount");

        uint256 m_num = _currencyAmountToMint.mul(FLASH_FEE_PRECISION1);
        uint256 m_den = i_currencyPrice.getPriceOfSymbol(_currencySymbol);
        return m_num.div(m_den);
    }

    function _calculateFeeInTermsOfUsd(uint256 _mintAmountInUsd, uint256 _flashFeePercent)
        private
        view
        returns (uint256)
    {
        uint256 m_num = _mintAmountInUsd.mul(_flashFeePercent);
        return m_num.div(FLASH_FEE_PRECISION1);
    }

    function _calculateFeeInTermsOfCollateral(
        uint256 _flashFeeInUsd,
        address _collateralAddress,
        address _pricefeedAddress
    ) private view returns (uint256) {
        uint256 m_priceOfCollateralInUsd = uint256(AggregatorV3Interface(_pricefeedAddress).latestAnswer());
        uint256 m_collateralDecimals = IERC20(_collateralAddress).decimals();
        uint256 m_pricefeedDecimals = AggregatorV3Interface(_pricefeedAddress).decimals();

        if (m_pricefeedDecimals != 8) {
            if (m_pricefeedDecimals > 8) {
                m_priceOfCollateralInUsd = m_priceOfCollateralInUsd.div(10 ** (m_pricefeedDecimals - 8));
            } else {
                m_priceOfCollateralInUsd = m_priceOfCollateralInUsd.mul(10 ** (8 - m_pricefeedDecimals));
            }
        }

        uint256 m_num = _flashFeeInUsd.mul(m_collateralDecimals);
        uint256 m_den = m_priceOfCollateralInUsd.mul(FLASH_FEE_PRECISION2);

        return m_num.div(m_den);
    }

    /* ------------------ Getter functions --------------------- */

    function convertStringToBytes32(string memory _string) public view returns (bytes32) {
        return i_convertor.stringToBytes32(_string);
    }

    function convertBytes32ToString(bytes32 _bytes32) public view returns (string memory) {
        return i_convertor.bytes32ToString(_bytes32);
    }

    function getGoverenceContractAddress() external view returns (address) {
        return address(i_goverenceToken);
    }

    function getCurrencyPriceAddress() external view returns (address) {
        return address(i_currencyPrice);
    }

    function getFlashFeeCallbackValue() external view returns (bytes32) {
        return CALLBACK_SUCCESS;
    }

    function getEthBalance() external view returns (uint256) {
        return s_ethBalance;
    }

    function getEthReceiver() external view returns (address) {
        return s_ethReceiver;
    }

    function getTotalVolumeTraded() external view returns (uint256) {
        return s_totalVolumeTraded;
    }

    function getAllCollateralSymbols() external view returns (bytes32[] memory) {
        return s_allCollateralSymbols;
    }

    function getAllCurrencySymbols() external view returns (bytes32[] memory) {
        return s_allCurrencyTokenSymbols;
    }

    function getTotalTradedByUserInUsd(address _trader) external view returns (uint256) {
        return s_ownerTradedData[_trader].totalTraded;
    }

    function getTotalTradedByEthers(address _trader) external view returns (uint256) {
        return s_ownerTradedData[_trader].tradedWithEth;
    }

    function getUserCollateralTraded(address _trader, address _collateralAddress) external view returns (uint256) {
        require(isCollateralDataExist(_collateralAddress), "Collateral token is not exist");
        return s_ownerTradedData[_trader].collateralTokenTraded[_collateralAddress];
    }

    function getUserCurrencyMinted(address _trader, address _currenctTokenAddress) external view returns (uint256) {
        return s_ownerTradedData[_trader].curencyTokenTraded[_currenctTokenAddress];
    }

    function getCurrencyTokenAddress(bytes32 _currencySymbol) external view returns (address) {
        return s_symbolToCurrencyTokenContracts[_currencySymbol];
    }

    function getCollateralTokenAddress(bytes32 _collateralSymbol) external view returns (address) {
        return s_symbolToCollateralToken[_collateralSymbol];
    }

    function getCollateralData(address _collateralAddress) external view returns (CollateralData memory) {
        require(isCollateralDataExist(_collateralAddress), "Collateral token is not exist");
        return s_collateralTokenToCollateralData[_collateralAddress];
    }

    function getCollateralPricefeedAddress(address _collateralAddress) external view returns (address) {
        require(isCollateralDataExist(_collateralAddress), "Collateral token is not exist");
        return s_collateralTokenToCollateralData[_collateralAddress].pricefeedAddress;
    }

    function getCollateralTradedAmount(address _collateralAddress) external view returns (uint256) {
        return s_collateralTokenToCollateralData[_collateralAddress].totalTraded;
    }

    function getCollateralBonus(address _collateralAddress) external view returns (uint256) {
        require(isCollateralDataExist(_collateralAddress), "Collateral token is not exist");
        return s_collateralTokenToCollateralData[_collateralAddress].bonus;
    }

    function getCollateralFlashFee(address _collateralAddress) external view returns (uint256) {
        require(isCollateralDataExist(_collateralAddress), "Collateral token is not exist");
        return s_collateralTokenToCollateralData[_collateralAddress].flashFeePercent;
    }

    function isCollateralTokenExist(bytes32 _collateralSymbol) public view returns (bool) {
        return (s_symbolToCurrencyTokenContracts[_collateralSymbol] != address(0));
    }

    function isCollateralDataExist(address _collateralAddress) public view returns (bool) {
        return s_collateralTokenToCollateralData[_collateralAddress].isExist;
    }

    function isCurrencyTokenExist(bytes32 _currencySymbol) external view returns (bool) {
        return (s_symbolToCurrencyTokenContracts[_currencySymbol] != address(0));
    }
}
