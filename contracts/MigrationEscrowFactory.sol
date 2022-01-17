// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import '@openzeppelin/contracts4/proxy/Clones.sol';
import './MigrationEscrowBase.sol';
import './interfaces/DFKInterfaces.sol';

interface IMigrationEscrow {
    function initialize(address _owner, address _main, string calldata name) external;
}

contract MigrationEscrowFactory {    
    address public immutable base;
    address public immutable questerMain;
    
    mapping(address => address) public escrowOf;
        
    event CreateEscrow(address indexed user, address indexed escrow);
    
    constructor(address _main) {
        require(_main != address(0));
        questerMain = _main;
        base = address (new MigrationEscrowBase());
    }
    
    /// @notice Make a new escrow for user
    /// @dev Clones an implementation
    /// @param name Profile name for escrow
    function createMigrationEscrow(string calldata name) external returns (address) {
        address escrow = Clones.clone(base);
        IMigrationEscrow(escrow).initialize(msg.sender, questerMain, name);
        escrowOf[msg.sender] = escrow;
        
        emit CreateEscrow(msg.sender, escrow);
        return escrow;
    }
}