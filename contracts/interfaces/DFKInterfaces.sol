// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

interface IERC721 {
    function transferFrom(address from, address to, uint256 tokenId) external;
    function ownerOf(uint256 tokenId) external view returns (address);
    function setApprovalForAll(address operator, bool approved) external;
    function totalSupply() external view returns (uint256);
    
    function getHero(uint256 id) external view;  // returns something
}

//interface IERC20 {
//    function transfer(address to, uint256 amount) external returns(bool);
//    function balanceOf(address owner) external view returns(uint256);
//    function approve(address spender, uint256 amount) external returns(bool);
//    function allowance(address owner, address spender) external view returns (uint256);
//    function totalSupply() external view returns (uint256);
//    
//    function mint(address to, uint256 amount) external;
//    function burn(address from, uint256 amount) external;
//}

interface IJewelToken {
    function lockOf ( address _holder ) external view returns ( uint256 );
    function transferAll ( address _to ) external;
    function unlock (  ) external;
}

interface IProfiles {
    function createProfile (string memory _name, uint8 _picId) external returns (bool success);
}

interface IBank {
    function enter (uint256 amount) external;
    function leave (uint256 share) external;
}

interface IMasterGardener {
    function totalAllocPoint() external view returns (uint256);
    function deposit(uint256 _pid, uint256 _amount, address ref) external;  // added ref
    
    function poolId1(address) external view returns(uint256);
    
    function claimReward(uint256 poolId) external;
    
    function withdraw(uint256 poolId, uint256 amount, address ref) external;
    
    function emergencyWithdraw(uint256 poolId) external;
    
    function userDelta(uint256 poolId) external view returns(uint256);
    
    function userInfo(uint256 poolId, address user) external view returns (
        uint256 amount,
        uint256 rewardDebt,
        uint256 rewardDebtAtBlock,
        uint256 lastWithdrawBlock,
        uint256 firstDepositBlock,
        uint256 blockdelta,
        uint256 lastDepositBlock
    );
    
    function poolInfo(uint256 poolId) external view returns (
        address lpToken,
        uint256 allocPoint,
        uint256 lastRewardBlock,
        uint256 accGovTokenPerShare
    );
}

interface IUniswapV2Pair {
    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external;
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
}