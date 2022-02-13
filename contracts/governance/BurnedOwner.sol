// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

interface IContract {
	function acceptOwnership() external;
}

contract BurnedOwner {
	function acceptOwnership(address _contract) external {
		IContract(_contract).acceptOwnership();
	}
}