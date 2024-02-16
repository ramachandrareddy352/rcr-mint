// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeMath} from "../libraries/SafeMath.sol";

/**
 * This is controlled by the deployer, the prices are fixed by using centralization.
 * All the prices are based on usd dollar price.
 * Using bytes32 consume less gas than strings.
 */
contract CurrencyPrice is Ownable {
    using SafeMath for uint256;

    event PriceAdded(bytes32 symbol, uint256 price);
    event PriceUpdated(bytes32 symbol, uint256 newPrice);
    event PriceRemoved(bytes32 symbol);

    uint256 public constant DECIMALS = 10000; // 1 USD = 10000 value
    uint256 public s_symbolsCount;

    mapping(bytes32 symbol => uint256 price) public s_symbolToPrice;

    constructor(bytes32[] memory _symbols, uint256[] memory _prices, address _owner) Ownable(_owner) {
        uint256 m_len = _symbols.length;
        require(m_len == _prices.length && m_len > 0, "Currency Price : Wrong length of array elements");

        for (uint256 i = 0; i < m_len;) {
            _addPrice(_symbols[i], _prices[i]);
            unchecked {
                i = i.add(1);
            }
        }

        s_symbolsCount = s_symbolsCount.add(m_len);
    }

    function addMultiplePrices(bytes32[] memory _symbols, uint256[] memory _prices) external onlyOwner {
        uint256 m_len = _symbols.length;
        require(m_len == _prices.length && m_len > 0, "Currency Price : Wrong length of array elements");

        for (uint256 i = 0; i < m_len;) {
            _addPrice(_symbols[i], _prices[i]);
            unchecked {
                i = i.add(1);
            }
        }

        s_symbolsCount = s_symbolsCount.add(m_len);
    }

    function addSinglePrice(bytes32 _symbol, uint256 _price) external onlyOwner {
        _addPrice(_symbol, _price);
        s_symbolsCount = s_symbolsCount.add(1);
    }

    function _addPrice(bytes32 _symbol, uint256 _price) private {
        require(s_symbolToPrice[_symbol] == 0, "Currency Price : Symbol is already exist!");
        require(_price > 0, "Currency Price : Price is zero");
        s_symbolToPrice[_symbol] = _price;
    }

    function removeMultiplePrices(bytes32[] memory _symbols) external onlyOwner {
        uint256 m_len = _symbols.length;
        require(m_len != 0, "Currency Price : Zero length array");

        for (uint256 i = 0; i < m_len;) {
            _removePrice(_symbols[i]);
            unchecked {
                i = i.add(1);
            }
        }

        s_symbolsCount = s_symbolsCount.sub(m_len);
    }

    function removeSinglePrice(bytes32 _symbol) external onlyOwner {
        _removePrice(_symbol);
        s_symbolsCount = s_symbolsCount.sub(1);
    }

    function _removePrice(bytes32 _symbol) private {
        require(s_symbolToPrice[_symbol] > 0, "Currency Price : Symbol is not exist!");
        s_symbolToPrice[_symbol] = 0;
    }

    function updateMultiplePrices(bytes32[] memory _symbols, uint256[] memory _prices) external onlyOwner {
        uint256 m_len = _symbols.length;
        require(m_len == _prices.length && m_len > 0, "Currency Price : Wrong length of array elements");

        for (uint256 i = 0; i < m_len;) {
            _updatePrice(_symbols[i], _prices[i]);
            unchecked {
                i = i.add(1);
            }
        }
    }

    function updateSinglePrice(bytes32 _symbol, uint256 _price) external onlyOwner {
        _updatePrice(_symbol, _price);
    }

    function _updatePrice(bytes32 _symbol, uint256 _price) private {
        require(s_symbolToPrice[_symbol] > 0, "Currency Price : Symbol is not exist!");
        require(_price > 0, "Currency Price : Price is zero");
        s_symbolToPrice[_symbol] = _price;
    }

    function getPriceOfSymbol(bytes32 _symbol) public view returns (uint256) {
        require(s_symbolToPrice[_symbol] > 0, "Currency Price : Symbol is not exist!");
        return s_symbolToPrice[_symbol];
    }
}
