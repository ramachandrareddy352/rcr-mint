// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract AccessControl {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE"); // deployer

    event RoleGranted(bytes32 role, address account, address grantedBy);
    event RoleRevoked(bytes32 role, address account, address revokedBy);

    mapping(bytes32 role => address account) public s_roles;

    modifier onlyRole(bytes32 _role) {
        _checkRole(_role, msg.sender);
        _;
    }

    function _checkRole(bytes32 _role, address _account) internal view {
        require(_account != address(0), "Invalid zero address");
        require(s_roles[_role] == _account, "Invalid role called");
    }

    function grantRole(bytes32 _role, address _account) public onlyRole(ADMIN_ROLE) {
        // in this function we can also change admin role
        _grantRole(_role, _account);
    }

    function revokeRole(bytes32 _role, address _account) public onlyRole(ADMIN_ROLE) {
        _revokeRole(_role, _account);
    }

    // grant and update of role is same
    // while _grantRole is called from constructor msg.sender is token factory, after deploying only admin can modify
    // the role then only the role is granted by admin role
    function _grantRole(bytes32 _role, address _account) internal {
        require(_account != address(0), "Invalid zero address");
        s_roles[_role] = _account;
        emit RoleGranted(_role, _account, msg.sender);
    }

    function _revokeRole(bytes32 _role, address _account) internal {
        _checkRole(_role, _account);
        s_roles[_role] = address(0);
        emit RoleRevoked(_role, _account, msg.sender);
    }
}
