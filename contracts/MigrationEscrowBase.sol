// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import './interfaces/DFKInterfaces.sol';

contract MigrationEscrowBase {
    address private constant profiles = 0xabD4741948374b1f5DD5Dd7599AC1f85A34cAcDD;
    address private constant jewel = 0x72Cb10C6bfA5624dD07Ef608027E366bd690048F;
    
    address public questerMain;
    address public owner;
    
    bool private initialized;
    
    event MigrationCalled();
    event Returned();
    
    /// @notice Initialize contract variables
    /// @dev called on deployment, only once
    /// @param _owner Address of the owner (user)
    /// @param _main Address of QuesterMain contract
    /// @param name Profile name to use
    function initialize(address _owner, address _main, string calldata name) external {
        require(!initialized, "initialized");
        initialized = true;
        
        require(_owner != address(0) && _main != address(0), "zero");
        owner = _owner;
        questerMain = _main;
        
        // may need a profile to receive jewels
        require(IProfiles(profiles).createProfile(name, 1), "profile failed");
    }
    
    /// @notice Callback from questerMain asking for locked jewels
    /// @param user Address of this user
    function migrationCallback(address user) external {
        require(msg.sender == questerMain, "only questerMain");
        require(user == owner, "user not owner");
        
        IJewelToken(jewel).transferAll(questerMain);
        
        emit MigrationCalled();
    }
    
    /// @notice Return all jewels to owner
    function returnToOwner() external {
        require(msg.sender == owner, "only owner");
        
        IJewelToken(jewel).transferAll(owner);
        
        emit Returned();
    }
}