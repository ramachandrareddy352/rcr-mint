// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Pausable} from "./utils/Pausable.sol";
import {ERC20Permit, ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {AccessControl} from "./utils/AccessControl.sol";

contract GoverenceToken is ERC20, Pausable, ERC20Permit, AccessControl {
    bytes32 public constant GOVERENCE_CONTRACT_ROLE = keccak256("GOVERENCE_CONTRACT_ROLE"); // goverence contract
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE"); // token factory
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE"); // token factory

    uint256 public s_ownersCount;

    mapping(address => bool) public isOwner;

    constructor(address _admin, address _goverenceContract, address _tokenFactory)
        ERC20("GoverenceToken", "GOV_TK")
        ERC20Permit("GoverenceToken")
    {
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(MINTER_ROLE, _tokenFactory);
        _grantRole(BURNER_ROLE, _tokenFactory);
        _grantRole(GOVERENCE_CONTRACT_ROLE, _goverenceContract);
    }

    function pause() public onlyRole(GOVERENCE_CONTRACT_ROLE) {
        _pause();
    }

    function unpause() public onlyRole(GOVERENCE_CONTRACT_ROLE) {
        _unpause();
    }

    // The following functions are overrides required by Solidity.
    function _update(address from, address to, uint256 value) internal override(ERC20, ERC20Pausable) {
        super._update(from, to, value);
    }

    // minting and burning is done by token factory
    function mintTokens(address _to, uint256 _amount) public onlyRole(MINTER_ROLE) returns (bool) {
        require(_to != address(0), "Invalid zero address");
        require(_amount > 0, "Invalid amount to mint");
        if (!isOwner[_to]) {
            isOwner[_to] = true;
            s_ownersCount++;
        }
        _mint(_to, _amount);
        return true;
    }

    function burnTokens(address _to, uint256 _amount) public onlyRole(BURNER_ROLE) returns (bool) {
        require(_to != address(0), "Invalid zero address");
        require(_amount > 0, "Invalid amount to mint");
        _burn(_to, _amount);
        if (balanceOf(_to) == 0 && s_ownersCount > 0) {
            s_ownersCount--;
            isOwner[_to] = false;
        }
        return true;
    }

    // when voting is started tokens transfereing is freezed bu goverence contract
    function transfer(address to, uint256 value) public override whenNotPaused returns (bool) {
        return super.transfer(to, value);
    }

    function approve(address spender, uint256 value) public override whenNotPaused returns (bool) {
        return super.approve(spender, value);
    }

    function transferFrom(address from, address to, uint256 value) public override whenNotPaused returns (bool) {
        return super.transferFrom(from, to, value);
    }

    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        public
        override
        whenNotPaused
    {
        super.permit(owner, spender, value, deadline, v, r, s);
    }
}
