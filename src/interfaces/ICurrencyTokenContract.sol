// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ICurrencyTokenContract {
    function mintTokens(address _to, uint256 _amount) external returns (bool);
    function burnTokens(address _from, uint256 _value) external returns (bool);

    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external;
    function decimals() external view returns (uint8);
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function nonces(address owner) external view returns (uint256);
}
