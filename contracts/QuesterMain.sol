// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import './interfaces/DFKInterfaces.sol';
import "./ERC20.sol";
import '@openzeppelin/contracts4/proxy/Clones.sol';

interface IHeroScore {
    function getHeroScore(uint256 heroId, bool getJewelMining) external view returns (uint256, uint256);
}

interface IMigrationEscrow {
    function migrationCallback(address user) external;
}

interface IBranch {
    function transferLocked(address _to) external;
    function initialize(string calldata _name) external;
}

interface IMigrationEscrowFactory {
    function escrowOf(address user) external view returns (address);
}

interface IGovToken {
    function mint(address to, uint256 amount) external;
}


/// @title Main contract for autoquester
contract QuesterMain is ERC20 {
    address private constant profiles = 0xabD4741948374b1f5DD5Dd7599AC1f85A34cAcDD;
    address private constant heroNFT = 0x5F753dcDf9b1AD9AabC1346614D1f4746fd6Ce5C;
    address private constant jewel = 0x72Cb10C6bfA5624dD07Ef608027E366bd690048F;
    address private constant dfkBank = 0xA9cE83507D872C5e1273E745aBcfDa849DAA654F;
    address private constant oldLJ = 0xD8c9802cedb63C827B797bf5EA18eb7aE7adC160;
    address private constant airdrop = 0x8AbEbcDBF5AF9FC602814Eabf6Fbf952acF682A2;
    
    address public governance;
    address public pendingGovernance;
    address public bot;
    address public guardian;
    address public treasury;
    address public heroScoreAddress;
    address public escrowFactory;
    
    address public immutable branchBase;
    address public immutable govToken;
    
    uint256 private _locked;
    bool private paused;
    
    mapping(uint256 => address) public ownerOf;
    mapping(address => uint256) public pendingRewardsOf;
    mapping(address => uint256) public pendingUnlockedOf;
    uint256 public totalPendingJewels;
    
    mapping(address => bool) public isBranchValid;
    address public possibleLockedWhale;
    
    // only UI
    mapping(address => uint256[]) private heroesOf;
    mapping(uint256 => uint256) private indexOf;
    
    event Deposit(address indexed user, uint256[] _heroes);
    event Withdraw(address indexed user, uint256[] _heroes);
    event Claimed(address indexed user, uint256 amountGovToken, uint256 amountJewel);
    event AssignedBranch(address indexed _branch, uint256 _heroId);
    event AssignLocked(address indexed _sender, address indexed _recipient, uint256 amount);
    event BranchCreated(address indexed newbranch);
    
    event LockedDeposit(address indexed user, uint256 lockedMigrated);
    event LockedWithdraw(address indexed user, address indexed branch, uint256 amount);
    event MigrateOldLJ(address indexed user, uint256 amount);
    
    constructor(address _govToken, address _branchBase) ERC20("Locked Jewel", "L-JEWEL") {
        governance = msg.sender;
        guardian = msg.sender;
        treasury = msg.sender;
        govToken = _govToken;
        branchBase = _branchBase;
        
        _locked = 1;
        
        /// @dev Profile may be needed to handle jewel/heroes
        require(IProfiles(profiles).createProfile("SG_Quester_v4", 1), "Profile creation failed");
    }
    
    modifier onlyGov() {
        require(governance == msg.sender, "NOT_GOV");
        _;
    }
    
    modifier onlyBot() {
        require(bot == msg.sender, "NOT_BOT");
        _;
    }
    
    modifier onlyGuardian() {
        require(guardian == msg.sender, "NOT_GUARDIAN");
        _;
    }
    
    modifier onlyBranch() {
        require(isBranchValid[msg.sender], "NOT_BRANCH");
        _;
    }
    
    modifier locked() {
        require(_locked == 1, "locked");
        _locked = 2;
        _;
        _locked = 1;
    }
    
    modifier nonPaused() {
        require(!paused, "paused");
        _;
    }
    
    /************************/
    /* Governance Functions */
    /************************/

    /// @notice Pending governance can accept ownership
    function acceptOwnership() external {
        require(pendingGovernance == msg.sender, "NOT_PENDING_GOV");
        governance = msg.sender;
        pendingGovernance = address(0);
    }

    /// @notice Choose pending governance
    /// @param newGov_ Address of new governance
    function proposeOwnership(address newGov_) external onlyGov {
        pendingGovernance = newGov_;
    }
    
    /// @notice Change guardian
    /// @param _newGuardian Address of new guardian
    function changeGuardian(address _newGuardian) external onlyGov {
        guardian = _newGuardian;
    }
    
    /// @notice Change bot address
    /// @dev On branches call setBot() to read new value
    /// @param _newBot Address of new bot
    function changeBot(address _newBot) external onlyGov {
        bot = _newBot;
    }
    
    /// @notice Change Hero score contract
    /// @param _heroScore Address of new contract
    function changeHeroScore(address _heroScore) external onlyGov {
        heroScoreAddress = _heroScore;
    }
    
    /// @notice Change Treasury contract
    /// @param _treasury Address of new contract
    function changeTreasury(address _treasury) external onlyGov {
        treasury = _treasury;
    }
    
    /// @notice Change EscrowFactory for locked jewels deposits
    /// @param _factory Address of new factory contract
    function changeEscrowFactory(address _factory) external onlyGov {
        escrowFactory = _factory;
    }
    
    /**********************/
    /* Guardian Functions */
    /**********************/
    
    /// @notice Pause deposits
    /// @param _status New boolean to set paused to
    function setPaused(bool _status) external onlyGuardian {
        paused = _status;
    }
    
    /// @notice Unstuck nft (ex. hero/land) incorrectly transferred to main/branch
    /// @param _nft Contract address of nft to transfer
    /// @param _recipient Address where to transfer
    /// @param _id Id of nft to transfer
    function unstuckNFT(address _nft, address _recipient, uint256 _id) external onlyGuardian {
        if (_nft == heroNFT) {
            require(ownerOf[_id] == address(0), "hero is correctly deposited");
            
            address currentOwner = IERC721(heroNFT).ownerOf(_id);
            require((currentOwner == address(this)) || isBranchValid[currentOwner], "hero is not in main/branch");
            IERC721(heroNFT).transferFrom(currentOwner, _recipient, _id);
        } else {
            IERC721(_nft).transferFrom(address(this), _recipient, _id);
        }
    }
    
    /*********************/
    /* User Functions    */
    /*********************/
    
    /// @notice Deposit Heroes
    /// @param _heroes Array of Heroes Ids to deposit
    function depositHeroes(uint256[] calldata _heroes) external locked nonPaused {
        require(_heroes.length > 0, "Zero heroes in input");
        
        for (uint256 i=0; i<_heroes.length; i++) {
            uint256 heroId = _heroes[i];
            
            /// @dev Hero must not already be in a quest
            _checkHeroStatusOnDeposit(heroId);
            
            IERC721(heroNFT).transferFrom(msg.sender, address(this), heroId);
            ownerOf[heroId] = msg.sender;
            
            indexOf[heroId] = heroesOf[msg.sender].length;
            heroesOf[msg.sender].push(heroId);
        }
        
        emit Deposit(msg.sender, _heroes);
    }
    
    /// @notice Withdraw Heroes
    /// @param _heroes Array of Heroes Ids to withdraw
    function withdrawHeroes(uint256[] calldata _heroes) external locked {
        require(_heroes.length > 0, "Zero heroes in input");
        
        for (uint256 i=0; i<_heroes.length; i++) {
            uint256 heroId = _heroes[i];
            
            require(ownerOf[heroId] == msg.sender, "Not owner!");
            _transferHeroTo(msg.sender, heroId);
            ownerOf[heroId] = address(0);
            
            uint256 _lastHero = heroesOf[msg.sender][heroesOf[msg.sender].length-1];
            heroesOf[msg.sender][indexOf[heroId]] = _lastHero;
            heroesOf[msg.sender].pop();
            indexOf[_lastHero] = indexOf[heroId];
        }
        
        emit Withdraw(msg.sender, _heroes);
    }
    
    /// @notice Claim jewel rewards + gov tokens
    function claim() external locked {
        uint256 amountRewards = pendingRewardsOf[msg.sender];
        uint256 amountUnlocked = pendingUnlockedOf[msg.sender];
        if (amountRewards > 0) pendingRewardsOf[msg.sender] = 0;
        if (amountUnlocked > 0) pendingUnlockedOf[msg.sender] = 0;
        
        uint256 amountTotal = amountRewards + amountUnlocked;
        require(amountTotal > 0, "No pending rewards");
        
        totalPendingJewels -= amountTotal;
        
        _leaveBank(amountTotal);
        
        IERC20(jewel).transfer(msg.sender, amountTotal);
        IGovToken(govToken).mint(msg.sender, amountRewards);
        
        emit Claimed(msg.sender, amountRewards, amountTotal);
    }
    
    /// @notice Deposit locked jewels to mint LJ
    /// @param migrationEscrow Address of escrow to callback
    function depositLocked(address migrationEscrow) external locked nonPaused {
        // only approved escrows (untrusted ext calls can be bad)
        require(IMigrationEscrowFactory(escrowFactory).escrowOf(msg.sender) == migrationEscrow, "only valid escrows");
    
        uint256 lockedBefore = IJewelToken(jewel).lockOf(address(this));
        uint256 unlockedBefore = IERC20(jewel).balanceOf(address(this));
        IMigrationEscrow(migrationEscrow).migrationCallback(msg.sender);
        uint256 lockedMigrated = IJewelToken(jewel).lockOf(address(this)) - lockedBefore;
        uint256 unlockedMigrated = IERC20(jewel).balanceOf(address(this)) - unlockedBefore;
        
        // return jewels to user
        require(IERC20(jewel).transfer(msg.sender, unlockedMigrated), "jewel transfer failed");
        
        // mint lockedJewels to user
        _mint(msg.sender, lockedMigrated);
        
        emit LockedDeposit(msg.sender, lockedMigrated);
    }
    
    /// @notice Withdraw locked jewels from branch by burning LJ
    /// @param _branch Address of branch to drain
    /// @param _minAmount Minimum amount (slippage check)
    /// @param _maxAmount Maximum amount (slippage check)
    function withdrawLocked(address _branch, uint256 _minAmount, uint256 _maxAmount) external locked nonPaused {
        require(isBranchValid[_branch], "branch address invalid");
        require(_minAmount > 0, "zero _minAmount");
        
        uint256 amount = IJewelToken(jewel).lockOf(_branch);
        require(amount >= _minAmount, "amount under minimum");
        require(amount <= _maxAmount, "amount over maximum");
        
        _burn(msg.sender, amount);  // check is inside here
        
        IBranch(_branch).transferLocked(msg.sender);
        
        emit LockedWithdraw(msg.sender, _branch, amount);
    }
    
    /// @notice Migrate Old LJ tokens to mint new ones
    /// @dev Old tokens are sent to dead address
    function migrateOldLJ() external locked {
        uint256 amount = IERC20(oldLJ).balanceOf(msg.sender);
        IERC20(oldLJ).transferFrom(msg.sender, 0x000000000000000000000000000000000000dEaD, amount);
        _mint(msg.sender, amount);
        
        emit MigrateOldLJ(msg.sender, amount);
    }
    
    /*******************/
    /* Bot Functions   */
    /*******************/
    
    /// @notice Create new branch
    /// @param _name Profile name for branch
    function createBranch(string calldata _name) external onlyBot {
        address newbranch = Clones.clone(branchBase);
        IBranch(newbranch).initialize(_name);
        
        isBranchValid[newbranch] = true;
        
        emit BranchCreated(newbranch);           
    }
    
    /// @notice Assign heroes to branches
    /// @param _branches Array of Addresses to move the hero to
    /// @param _heroes Array of Hero Ids to move
    function assignHeroes(address[] calldata _branches, uint256[] calldata _heroes) external onlyBot {
        require(_branches.length == _heroes.length, "different length");
        require(_branches.length > 0, "zero length");
        for (uint256 i=0; i<_branches.length; i++) {
            require(isBranchValid[_branches[i]], "BAD_BRANCH");
            
            _transferHeroTo(_branches[i], _heroes[i]);
            
            emit AssignedBranch(_branches[i], _heroes[i]);    
        }
    }
    
    /// @notice Move locked between branches/main/treasury
    /// @param _sender Address of sender to move from
    /// @param _recipient Address of recipient to move to
    function assignLocked(address _sender, address _recipient) external onlyBot {
        require(_sender != address(0), "zero address");
        require(_recipient != address(0), "zero address");
        require(_sender != _recipient, "same address");
        
        uint256 amount = IJewelToken(jewel).lockOf(_sender);
        require(amount > 0, "zero sender locked amount");
        
        if (_sender == address(this)) {
            require(isBranchValid[_recipient] || (_recipient == treasury), "recipient not a branch/treasury");
            IJewelToken(jewel).transferAll(_recipient);
        } else if (_recipient == address(this)) {
            require(isBranchValid[_sender], "sender not a branch");
            IBranch(_sender).transferLocked(_recipient);
        } else {
            require(isBranchValid[_recipient], "recipient not a branch");
            require(isBranchValid[_sender], "sender not a branch");
            IBranch(_sender).transferLocked(_recipient);
        }
        
        emit AssignLocked(_sender, _recipient, amount);
    }
    
    /// @notice Send token to treasury
    /// @dev For eggs, xJewels, land, etc...
    /// @param _token Address of the token to send
    /// @param _amount Amount of tokens to send
    function sendToTreasury(address _token, uint256 _amount) external onlyBot {
        require(_token != heroNFT, "Only ERC20 token");
        IERC20(_token).transfer(treasury, _amount);
    }
    
    /// @notice Deposit jewels in the bank (for xJewel)
    /// @param _amount Amount of jewel to deposit
    function enterBank(uint256 _amount) external onlyBot {
        // need to approve first
        uint256 allowance = IERC20(jewel).allowance(address(this), dfkBank);
        if (allowance < _amount) {
            IERC20(jewel).approve(dfkBank, type(uint256).max);
        }
        
        IBank(dfkBank).enter(_amount);
    }
    
    /// @notice Interact with airdrop contract
    /// @param _data Calldata to pass
    function checkAirdrop(bytes calldata _data) external onlyBot {
        (bool success, ) = airdrop.call(_data);
        require(success, "airdrop call failed");
    }
    
    /*********************/
    /* Branch Functions  */
    /*********************/
    
    /// @notice Accrue pending rewards for some heroes, no jewel-mining
    /// @dev Called from branch when completing a quest
    /// @param _heroes Array of Heroes Ids to accrue
    function accrueForHeroes(uint256[] calldata _heroes) external onlyBranch {
        uint256 _total;
        for (uint256 i=0; i<_heroes.length; i++) {
            uint256 heroId = _heroes[i];
            (uint256 score, ) = _getHeroScore(heroId, false);
            address _user = ownerOf[heroId];
            
            pendingRewardsOf[_user] += score;
            _total += score;
        }
        totalPendingJewels += _total;
    }
    
    /// @notice Accrue pending rewards for some heroes, for jewel-mining
    /// @dev Called from branch when completing a quest
    /// @param _heroes Array of Heroes Ids to accrue
    function accrueForMiningHeroes(uint256[] calldata _heroes) external onlyBranch {
        uint256 _totalPending;
        uint256 _totalMinable;
        for (uint256 i=0; i<_heroes.length; i++) {
            uint256 heroId = _heroes[i];
            (uint256 score, uint256 _singleMined) = _getHeroScore(heroId, true);
            
            address _user = ownerOf[heroId];
            uint256 _minable = balanceOf(_user);
            
            if (_minable < _singleMined) _singleMined = _minable;
            
            pendingRewardsOf[_user] += score;
            _totalPending += score;
            
            if (_singleMined > 0) {
                pendingUnlockedOf[_user] += _singleMined;
                _decreaseBalanceOf(_user, _singleMined);  //_balances[_user] -= _singleMined;
                _totalPending += _singleMined;
                _totalMinable += _singleMined;
            }
        }
        totalPendingJewels += _totalPending;
        if (_totalMinable > 0) _decreaseTotalSupply(_totalMinable);   //_totalSupply -= _totalMinable;
    }
    
    /// @notice Try assigning locked jewels to requesting branch
    function requestLocked() external onlyBranch {
        address _recipient = msg.sender;
        address _sender = possibleLockedWhale;
        
        if (_sender == address(0)) {
            possibleLockedWhale = _recipient;
            return;
        }
        
        if (_sender == _recipient) return;
        
        uint256 amount = IJewelToken(jewel).lockOf(_sender);
        if (amount == 0) return;
        
        IBranch(_sender).transferLocked(_recipient);
        possibleLockedWhale = _recipient;
        
        emit AssignLocked(_sender, _recipient, amount);
    }
    
    /***********************/
    /* Internal Functions  */
    /***********************/
        
    // get jewels from bank
    function _leaveBank(uint256 _amount) internal {
        uint256 totalShares = IERC20(dfkBank).totalSupply();
        uint256 totalJewels = IERC20(jewel).balanceOf(dfkBank);
        uint256 _shares = _amount*totalShares/totalJewels + 1; // to round up
        
        uint256 maxShares = IERC20(dfkBank).balanceOf(address(this));
        if (_shares > maxShares) _shares = maxShares;
        IBank(dfkBank).leave(_shares);
    }
    
    // get hero reward per quest in jewels (score)
    function _getHeroScore(uint256 heroId, bool getJewelMining) internal view returns(uint256, uint256) {
        return IHeroScore(heroScoreAddress).getHeroScore(heroId, getJewelMining);
    }
    
    // move heroes from main/branches
    function _transferHeroTo(address recipient, uint256 heroId) internal {    
        address currentOwner = IERC721(heroNFT).ownerOf(heroId);
        require((currentOwner == address(this)) || isBranchValid[currentOwner], "hero is not in main/branch");
        
        IERC721(heroNFT).transferFrom(currentOwner, recipient, heroId);
    }
    
    // revert if hero is on a quest
    function _checkHeroStatusOnDeposit(uint256 heroId) internal view {
        (bool success, bytes memory returndata) = heroNFT.staticcall(abi.encodeWithSelector(IERC721.getHero.selector, heroId));
        require(success, "heroNFT call failed");
        
        uint256 value;
        assembly {
            value := mload(add(add(returndata, 0x20), 704))
        }
        require(value == 0, "Hero on a quest");
    }
    
    /*********/
    /* View  */
    /*********/
    
    /// @notice Get Heroes deposited by specific user
    /// @param user Address of the user
    function getHeroes(address user) external view returns (uint256[] memory) {
        return heroesOf[user];
    }
    
    /// @notice Get Number of heroes owned by user
    /// @param user Address of the user
    function heroesBalanceOf(address user) external view returns (uint256) {
        return heroesOf[user].length;
    }
}