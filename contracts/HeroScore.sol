// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

interface IDecoder {
    function decode(uint256 _param1) external view;  // returns something
}

import './interfaces/DFKInterfaces.sol';

contract HeroScore {
    address private constant decoder = 0x6b696520997d3eaEE602D348F380cA1A0F1252d5;
    address private constant heroNFT = 0x5F753dcDf9b1AD9AabC1346614D1f4746fd6Ce5C;
    
    address public strategist;
    
    uint256 private constant JEWEL_DECIMALS = 1e18;
    
    struct Parameters {
        uint256 A_mnr;
        uint256 A_grd;
        uint256 A_fsh;
        uint256 A_frg;
        uint256 B_mnr;
        uint256 B_no_mnr;
    }
    Parameters public parameters;
    
    event ChangedParameters(Parameters);
    
    struct HeroInfo {
        uint256 rarity;
        uint256 class;
        uint256 subclass;
        uint256 profession;
        uint256 boost1;
        uint256 boost2;
        uint256 stamina;
        uint256 level;
        uint256 profscore;
        uint256 STR;
        uint256 INT;
        uint256 WIS;
        uint256 LCK;
        uint256 AGI;
        uint256 VIT;
        uint256 END;
        uint256 DEX;
    }
    
    constructor() {
        strategist = msg.sender;
    }
    
    /********************/
    /* Public Functions */
    /********************/
    
    /// @notice Get amount of jewels gained per quest on average
    /// @param heroId Id of the hero
    /// @param getJewelMining True returns *also* jewelMiningScore
    /// @return score Jewel/quest excluding mined from locked
    /// @return jewelMiningScore Jewel/quest mined from locked
    function getHeroScore(uint256 heroId, bool getJewelMining) public view returns(uint256 score, uint256 jewelMiningScore) {
        HeroInfo memory heroInfo = _getHeroInfo(heroId);
        
        uint256 prof = heroInfo.profession;
        if (prof == 0) {
            // miner (this should be gold mining)
            score = parameters.A_mnr;
        } else if (prof == 2) {
            // gardener
            score = parameters.A_grd * heroInfo.stamina/25;
        } else if (prof == 4) {
            // fisher
            score = parameters.A_fsh;
        } else if (prof == 6) {
            // forager
            score = parameters.A_frg;
        }
        
        if (getJewelMining) {
            if (prof == 0) {
                // miner
                jewelMiningScore = parameters.B_mnr;
            } else {
                // anything else
                jewelMiningScore = parameters.B_no_mnr;
            }
        }
    }
    
    /************************/
    /* Strategist Functions */
    /************************/
    
    /// @notice Change parameters for score calculation
    /// @param _newParams New Parameters to use
    function changeParameters(Parameters calldata _newParams) external {
        require(msg.sender == strategist, "ONLY strategist");
        
        parameters = _newParams;
        
        emit ChangedParameters(_newParams);
    }
    
    /// @notice Change strategist for this contract
    /// @param _newStrategist Address of new strategist
    function changeStrategist(address _newStrategist) external {
        require(msg.sender == strategist, "ONLY strategist");
        require(_newStrategist != address(0), "zero address input");
        
        strategist = _newStrategist;
    }
    
    /**********************/
    /* Internal Functions */
    /**********************/
    
    // get info from hero contract
    function _getHeroInfo(uint256 heroId) internal view returns(HeroInfo memory) {
        bytes memory stats = new bytes(32);
        HeroInfo memory heroInfo;
        uint256 miningScore;
        uint256 gardeningScore;
        uint256 foragingScore;
        uint256 fishingScore;
        
        {
            (bool success, bytes memory returndata) = heroNFT.staticcall(abi.encodeWithSelector(IERC721.getHero.selector, heroId));
            require(success, "heroNFT call failed");
            
            heroInfo.rarity = _getValue(returndata, 9);
            heroInfo.class = _getValue(returndata, 15);
            heroInfo.subclass = _getValue(returndata, 16);
            heroInfo.level = _getValue(returndata, 20);
            heroInfo.STR = _getValue(returndata, 25);
            heroInfo.INT = _getValue(returndata, 26);
            heroInfo.WIS = _getValue(returndata, 27);
            heroInfo.LCK = _getValue(returndata, 28);
            heroInfo.AGI = _getValue(returndata, 29);
            heroInfo.VIT = _getValue(returndata, 30);
            heroInfo.END = _getValue(returndata, 31);
            heroInfo.DEX = _getValue(returndata, 32);
            heroInfo.stamina = _getValue(returndata, 35);
            
            for (uint256 i=0; i<32; i++) {
                stats[i] = returndata[i+7*32];
            }
            
            miningScore = _getValue(returndata, 64);
            gardeningScore = _getValue(returndata, 65);
            foragingScore = _getValue(returndata, 66);
            fishingScore = _getValue(returndata, 67);
        }
        
        // decoding
        {
            (bool success2, bytes memory returndata2) = decoder.staticcall(abi.encodeWithSelector(IDecoder.decode.selector, uint256(bytes32(stats))));
            require(success2, "decoder call failed");
            
            //heroInfo.profscore = uint256(bytes32(profscore));
            uint256 prof = _getValue(returndata2, 38);
            heroInfo.profession = prof;
            heroInfo.boost1 = _getValue(returndata2, 18);
            heroInfo.boost2 = _getValue(returndata2, 14);
            
            if (prof == 0) {
                heroInfo.profscore = miningScore;
            } else if (prof == 2) {
                heroInfo.profscore = gardeningScore;
            } else if (prof == 4) {
                heroInfo.profscore = fishingScore;
            } else if (prof == 6) {
                heroInfo.profscore = foragingScore;
            } else {
                revert("Bad profession");
            }
        }
        
        return heroInfo;
    }
    
    // read uint256 inside bytes
    function _getValue(bytes memory data, uint256 index) internal pure returns (uint256 value) {
        uint256 index32 = index*32;
        assembly {
            //value := mload(add(data, add(0x20, index32)))
            value := mload(add(add(data, 0x20), index32))
        }
    }
}