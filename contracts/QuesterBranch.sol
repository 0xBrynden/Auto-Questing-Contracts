// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

interface IQuesterMain {
    function accrueForHeroes(uint256[] calldata _heroes) external;
    function accrueForMiningHeroes(uint256[] calldata _heroes) external;
    function requestLocked() external;
    function bot() external view returns (address);
}

struct Quest {
    uint256 id;
    address questAddr;
    uint256[] heroes;
    address player;
    uint256 startTime;
    uint256 startBlock;
    uint256 completeAtTime;
    uint8 attempts;
    uint8 status;
}

interface ICORE {
    function getHeroQuest(uint256 heroId) external view returns (Quest memory);
    function completeQuest(uint256 heroId) external;
}

import './libraries/UniswapV2Library.sol';
import './interfaces/DFKInterfaces.sol';
import "@openzeppelin/contracts4/token/ERC20/IERC20.sol";

contract QuesterBranch {
    address private constant profiles = 0xabD4741948374b1f5DD5Dd7599AC1f85A34cAcDD;
    address private constant heroNFT = 0x5F753dcDf9b1AD9AabC1346614D1f4746fd6Ce5C;
    address private constant questCore = 0x5100Bd31b822371108A0f63DCFb6594b9919Eaf4;
    address private constant zada = 0xe53BF78F8b99B6d356F93F41aFB9951168cca2c6;
    address private constant jewel = 0x72Cb10C6bfA5624dD07Ef608027E366bd690048F;
    address private constant dfkFactory = 0x9014B937069918bd319f80e8B3BB4A2cf6FAA5F7;
    address private constant dfkGarden = 0xDB30643c71aC9e2122cA0341ED77d09D5f99F924;
    address private constant jewelMiningAddr = 0x6FF019415Ee105aCF2Ac52483A33F5B43eaDB8d0;
    address private constant airdrop = 0x8AbEbcDBF5AF9FC602814Eabf6Fbf952acF682A2;
    
    address public questerMain;
    address public bot;
    uint256 public lockedJewelThreshold;
    
    bool private initialized;
    
    event Unlocked(uint256 unlocked);
    
    function initialize(string calldata _name) external {
        require(!initialized, "initialized");
        initialized = true;
        
        questerMain = msg.sender;
        bot = IQuesterMain(questerMain).bot();
        lockedJewelThreshold = 9*1000*1e18;  // 9k locked
        
        // profile
        require(IProfiles(profiles).createProfile(_name, 1), "Profile creation failed");
        
        // hero approval
        IERC721(heroNFT).setApprovalForAll(msg.sender, true); 
    }
    
    modifier onlyMain() {
        require(msg.sender == questerMain, "NOT_MAIN");
        _;
    }
    
    modifier onlyBot() {
        require(bot == msg.sender, "NOT_BOT");
        _;
    }
    
    /// @notice Refresh bot address to main one (during changes)
    function setBot() external {
        bot = IQuesterMain(questerMain).bot();
    }
    
    /*******************/
    /* Bot Functions   */
    /*******************/
    
    /// @notice Change threshold over which request more locked jewels
    /// @param _newValue New threshold value
    function setLockedJewelThreshold(uint256 _newValue) external onlyBot {
        lockedJewelThreshold = _newValue;
    }
    
    /// @notice Interact with airdrop contract
    /// @param _data Calldata to pass
    function checkAirdrop(bytes calldata _data) external onlyBot {
        (bool success, ) = airdrop.call(_data);
        require(success, "airdrop call failed");
    }
    
    // ---------
    // Sell tokens
    
    /// @notice Convert tokens to gold through Zada
    /// @param _tokens Array of token addresses to convert
    function convertToGold(address[] calldata _tokens) external onlyBot {
        for (uint256 i=0; i<_tokens.length; i++) {
            address token = _tokens[i];
            uint256 amount = IERC20(token).balanceOf(address(this));
            if (amount > 0) {
                // approve if necessary
                if (IERC20(token).allowance(address(this), zada) < amount) {
                    IERC20(token).approve(zada, type(uint256).max);
                }
                // sell
                bytes memory data = abi.encodeWithSelector(0x096c5e1a, token, amount);
                (bool success, ) = zada.call(data);
                require(success, "zada call failed");   
            }
        }
    }
    
    /// @notice Sell tokens in marketplace to Jewel
    /// @dev Recipient is questerMain; no router; path=[token, jewel]
    /// @param _tokens Array of token addresses to sell
    function sellToJewel(address[] calldata _tokens) external onlyBot {
        for (uint256 i=0; i<_tokens.length; i++) {
            address input = _tokens[i];
            uint256 balance = IERC20(input).balanceOf(address(this));
            // require(input != jewel, "token must not be jewel");  // already in sortTokens()
            require(balance > 0, "zero balance for token");
            
            (address token0,) = UniswapV2Library.sortTokens(input, jewel);
            IUniswapV2Pair pair = IUniswapV2Pair(UniswapV2Library.pairFor(dfkFactory, input, jewel));
            
            // transfer to pair
            IERC20(input).transfer(address(pair), balance);
            
            (uint reserve0, uint reserve1,) = pair.getReserves();
            (uint reserveInput, uint reserveOutput) = input == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
            uint256 amountInput = IERC20(input).balanceOf(address(pair)) - reserveInput;
            uint256 amountOutput = UniswapV2Library.getAmountOut(amountInput, reserveInput, reserveOutput);
            (uint amount0Out, uint amount1Out) = input == token0 ? (uint(0), amountOutput) : (amountOutput, uint(0));
            
            pair.swap(amount0Out, amount1Out, questerMain, new bytes(0));
        }
    }
    
    /// @notice Send token to main
    /// @dev For tokens (like eggs) that cannot be sold to jewel
    /// @param _token Address of the token to send
    /// @param _amount Amount of tokens to send
    /// @param isERC721 True if token is ERC721 (else ERC20)
    function sendToMain(address _token, uint256 _amount, bool isERC721) external onlyBot {
        require(_token != heroNFT, "Can't move heroes");
        if (isERC721) {
            IERC721(_token).transferFrom(address(this), questerMain, _amount);
        } else {
            IERC20(_token).transfer(questerMain, _amount);
        }
    }
    
    // ---------
    // Do quests
    
    /// @notice Call to quest core contract, to start/cancel
    /// @param _data Calldata for questCore w/ function signature
    /// @param requestJewel True to abide locked jewel requirements
    function startQuest(bytes calldata _data, bool requestJewel) external onlyBot {
        if (requestJewel) _checkLockedBalance();
        
        (bool success, ) = questCore.call(_data);
        require(success, "questCore quest call failed");
    }
    
    /// @notice Call to quest core contract, to complete
    /// @param heroId Id of hero to complete
    /// @param requestJewel True to abide locked jewel requirements
    function completeQuest(uint256 heroId, bool requestJewel) external onlyBot {
        // get heroes that complete
        Quest memory quest = ICORE(questCore).getHeroQuest(heroId);
        
        if (requestJewel) _checkLockedBalance();
        
        ICORE(questCore).completeQuest(heroId);
        
        if (quest.questAddr == jewelMiningAddr) {
            IQuesterMain(questerMain).accrueForMiningHeroes(quest.heroes);
        } else {
            IQuesterMain(questerMain).accrueForHeroes(quest.heroes);
        }
    }
    
    // ---------
    // LPs stuff
    
    /// @notice Stake LP-token present in this contract
    /// @param lpToken Address of LP token pair to stake
    function stakeLP(address lpToken) external onlyBot {
        uint256 amount = IERC20(lpToken).balanceOf(address(this));
        uint256 poolId = _getPoolId(lpToken);
        
        if (IERC20(lpToken).allowance(address(this), dfkGarden) != type(uint256).max) {
            IERC20(lpToken).approve(dfkGarden, type(uint256).max);
        }
        
        IMasterGardener(dfkGarden).deposit(poolId, amount, address(0));
    }
    
    /// @notice Unstake all LP-token and send them to treasury
    /// @param lpToken Address of LP token pair to unstake
    function unstakeAndReturnLP(address lpToken) external onlyBot {
        uint256 poolId = _getPoolId(lpToken);
        (uint256 amount,,,,,,) = IMasterGardener(dfkGarden).userInfo(poolId, address(this));
        
        IMasterGardener(dfkGarden).withdraw(poolId, amount, address(0));
        
        IERC20(dfkGarden).transfer(questerMain, amount);
    }
    
    /// @notice Harvest garden pool
    /// @param lpToken Address of LP token pair to harvest
    function harvestLP(address lpToken) external onlyBot {
        uint256 poolId = _getPoolId(lpToken);
        
        IMasterGardener(dfkGarden).claimReward(poolId);
    }
    
    // --------
    // Unlocking normally
    
    /// @notice Unlock Jewels here
    function unlock() external onlyBot {
        uint256 amountBefore = IJewelToken(jewel).lockOf(address(this));
        if (amountBefore > 0) {
            IJewelToken(jewel).unlock();
            uint256 unlocked = amountBefore - IJewelToken(jewel).lockOf(address(this));
            emit Unlocked(unlocked);
        }
    }
    
    /***************************/
    /* QuesterMain Functions   */
    /***************************/
    
    /// @notice Transfer Locked Jewels to another address
    /// @param _to Recipient of the transfer
    function transferLocked(address _to) external onlyMain {
        require(_to != address(0), "transferLocked:: zero address");
        require(_to != address(this), "transferLocked:: this address");
        
        // first move unlocked to main
        uint256 _unlocked = IERC20(jewel).balanceOf(address(this));
        if (_unlocked > 0) {
            IERC20(jewel).transfer(questerMain, _unlocked);
        }
        
        IJewelToken(jewel).transferAll(_to);
    }
    
    /***********************/
    /* Internal Functions  */
    /***********************/
    
    // look at locked balance, if lower than threshold request from main w/o reverting
    function _checkLockedBalance() internal {
        uint256 lockedHere = IJewelToken(jewel).lockOf(address(this));
        
        if (lockedHere >= lockedJewelThreshold) return; // ok
        
        IQuesterMain(questerMain).requestLocked();
    }
    
    // get poolId from LP-token address
    function _getPoolId(address lpToken) internal view returns(uint256) {
        uint256 poolId = IMasterGardener(dfkGarden).poolId1(lpToken);
        require(poolId > 0, "wrong LP-token");
        poolId -= 1; // this is the way
        return poolId;
    }
}