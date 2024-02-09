//SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {ERC20Permit, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title MintERC20 tokens for given value of collateral
 * @author rcr
 * @notice This contract mints the currency tokens and which is only minted by token factory. Only this tokens are traded in rcr-dex and lending/borrowing protocols
 */
contract CurrencyTokenContract is ERC20Permit, Ownable, ReentrancyGuard {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) ERC20Permit(name) Ownable(msg.sender) {
        // owner is the TokenFactory contract
    }

    function mintTokens(address _to, uint256 _amount) external onlyOwner nonReentrant returns (bool) {
        require(_to != address(0), "Invalid msg.sender");
        require(_amount > 0, "Amount must be greater than zero");
        _mint(_to, _amount);
        return true;
    }

    function burnTokens(address _from, uint256 _value) external onlyOwner nonReentrant returns (bool) {
        // all tokens are send to token factory and token factory burns from their balance
        require(_value > 0, "zero value");
        require(_from != address(0), "Invalid address");
        _burn(_from, _value);
        return true;
    }

    // split signature is present in utils/convertor
}
