// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./wRivexETH.sol";
import "./interfaces/ILiquidStaking.sol";

/**
 * @title LiquidStaking - RivexFi Liquid Staking Protocol
 * @notice Allows users to stake ETH and receive wRivexETH tokens with rewards
 * @dev Upgradeable contract with dynamic exchange rates and validator management
 */
contract LiquidStaking is 
    Initializable,
    ReentrancyGuardUpgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable,
    ILiquidStaking
{
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant VALIDATOR_ROLE = keccak256("VALIDATOR_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    wRivexETH public wRivexETHToken;
    
    uint256 public totalETHStaked;
    uint256 public totalRewards;
    uint256 public exchangeRate; // wRivexETH per ETH (scaled by 1e18)
    uint256 public minStakeAmount;
    uint256 public unstakeFee; // Fee in basis points (100 = 1%)
    uint256 public rewardRate; // Annual reward rate in basis points
    
    mapping(address => bool) public validators;
    mapping(address => uint256) public userStakes;
    mapping(address => uint256) public userRewards;
    
    address[] public validatorList;
    
    uint256 public lastRewardUpdate;
    uint256 public constant SECONDS_PER_YEAR = 365 days;
    uint256 public constant BASIS_POINTS = 10000;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the Liquid Staking contract
     * @dev Sets up all necessary parameters and roles for the staking protocol
     * @param _wRivexETHToken Address of the wRivexETH token contract
     * @param admin Address that will receive admin roles
     * @param _minStakeAmount Minimum amount of ETH required for staking
     * @param _unstakeFee Fee charged when unstaking (in basis points)
     * @param _rewardRate Annual reward rate (in basis points)
     * 
     * Success: Contract is initialized with proper parameters and roles
     * Revert: If called more than once or with invalid parameters
     */
    function initialize(
        address _wRivexETHToken,
        address admin,
        uint256 _minStakeAmount,
        uint256 _unstakeFee,
        uint256 _rewardRate
    ) public initializer {
        __ReentrancyGuard_init();
        __AccessControl_init();
        __Pausable_init();
        __UUPSUpgradeable_init();

        wRivexETHToken = wRivexETH(_wRivexETHToken);
        exchangeRate = 1e18; // 1:1 initially
        minStakeAmount = _minStakeAmount;
        unstakeFee = _unstakeFee;
        rewardRate = _rewardRate;
        lastRewardUpdate = block.timestamp;

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
        _grantRole(UPGRADER_ROLE, admin);
    }

    /**
     * @notice Fallback function to handle direct ETH deposits
     * @dev Automatically stakes any ETH sent to the contract
     * 
     * Success: ETH is staked and wRivexETH tokens are minted to sender
     * Revert: If contract is paused or amount is below minimum
     */
    receive() external payable {
        if (msg.value > 0) {
            _stake(msg.sender, msg.value);
        }
    }

    /**
     * @notice Stakes ETH and receives wRivexETH tokens in return
     * @dev Converts ETH to wRivexETH based on current exchange rate
     * @return wRivexETHAmount The amount of wRivexETH tokens minted
     * 
     * Success: ETH is staked, wRivexETH tokens are minted, user stake is recorded
     * Revert: If amount is below minimum, contract is paused, or reentrancy detected
     */
    function stake() external payable override nonReentrant whenNotPaused returns (uint256) {
        require(msg.value >= minStakeAmount, "LiquidStaking: Amount below minimum");
        return _stake(msg.sender, msg.value);
    }

    /**
     * @notice Unstakes wRivexETH tokens and receives ETH back
     * @dev Burns wRivexETH tokens and returns ETH minus unstaking fee
     * @param wRivexETHAmount Amount of wRivexETH tokens to unstake
     * @return ethAmount The amount of ETH returned to user
     * 
     * Success: wRivexETH tokens are burned, ETH is returned minus fee
     * Revert: If insufficient wRivexETH balance, insufficient ETH in contract, or contract is paused
     */
    function unstake(uint256 wRivexETHAmount) external override nonReentrant whenNotPaused returns (uint256) {
        require(wRivexETHAmount > 0, "LiquidStaking: Invalid amount");
        require(wRivexETHToken.balanceOf(msg.sender) >= wRivexETHAmount, "LiquidStaking: Insufficient balance");

        _updateRewards();

        // Calculate ETH amount to return
        uint256 ethAmount = (wRivexETHAmount * 1e18) / exchangeRate;
        
        // Apply unstaking fee
        uint256 fee = (ethAmount * unstakeFee) / BASIS_POINTS;
        uint256 ethToReturn = ethAmount - fee;

        require(address(this).balance >= ethToReturn, "LiquidStaking: Insufficient ETH balance");

        // Burn wRivexETH tokens
        wRivexETHToken.burnFrom(msg.sender, wRivexETHAmount);

        // Update state
        totalETHStaked -= ethAmount;
        userStakes[msg.sender] -= ethAmount;

        // Transfer ETH back to user
        (bool success, ) = payable(msg.sender).call{value: ethToReturn}("");
        require(success, "LiquidStaking: ETH transfer failed");

        emit Unstake(msg.sender, wRivexETHAmount, ethToReturn);
        return ethToReturn;
    }

    /**
     * @notice Internal function to handle staking logic
     * @dev Updates rewards, calculates wRivexETH amount, and mints tokens
     * @param user Address of the user staking ETH
     * @param ethAmount Amount of ETH being staked
     * @return wRivexETHAmount Amount of wRivexETH tokens minted
     * 
     * Success: User stake is recorded, wRivexETH tokens are minted
     * Revert: If minting fails
     */
    function _stake(address user, uint256 ethAmount) internal returns (uint256) {
        _updateRewards();

        // Calculate wRivexETH amount to mint
        uint256 wRivexETHAmount = (ethAmount * exchangeRate) / 1e18;

        // Update state
        totalETHStaked += ethAmount;
        userStakes[user] += ethAmount;

        // Mint wRivexETH tokens
        wRivexETHToken.mint(user, wRivexETHAmount);

        emit Stake(user, ethAmount, wRivexETHAmount);
        return wRivexETHAmount;
    }

    /**
     * @notice Updates reward calculations and exchange rate
     * @dev Calculates time-based rewards and updates exchange rate accordingly
     * 
     * Success: Rewards are calculated and exchange rate is updated
     * Revert: Never reverts, but may not update if no time has passed
     */
    function _updateRewards() internal {
        if (totalETHStaked == 0) {
            lastRewardUpdate = block.timestamp;
            return;
        }

        uint256 timeElapsed = block.timestamp - lastRewardUpdate;
        if (timeElapsed == 0) return;

        // Calculate rewards based on time elapsed and reward rate
        uint256 rewardAmount = (totalETHStaked * rewardRate * timeElapsed) / (BASIS_POINTS * SECONDS_PER_YEAR);
        
        if (rewardAmount > 0) {
            totalRewards += rewardAmount;
            
            // Update exchange rate to reflect rewards
            uint256 totalValue = totalETHStaked + totalRewards;
            uint256 totalSupply = wRivexETHToken.totalSupply();
            
            if (totalSupply > 0) {
                exchangeRate = (totalValue * 1e18) / totalSupply;
            }
            
            emit RewardsDistributed(rewardAmount);
        }

        lastRewardUpdate = block.timestamp;
    }

    /**
     * @notice Distributes external rewards to the staking pool
     * @dev Allows admin to add ETH rewards which increases the exchange rate
     * 
     * Success: Rewards are added to pool and exchange rate is updated
     * Revert: If caller is not admin or no ETH is sent
     */
    function distributeRewards() external payable onlyRole(ADMIN_ROLE) {
        require(msg.value > 0, "LiquidStaking: No rewards to distribute");
        
        totalRewards += msg.value;
        
        // Update exchange rate
        uint256 totalValue = totalETHStaked + totalRewards;
        uint256 totalSupply = wRivexETHToken.totalSupply();
        
        if (totalSupply > 0) {
            exchangeRate = (totalValue * 1e18) / totalSupply;
        }
        
        emit RewardsDistributed(msg.value);
    }

    /**
     * @notice Adds a new validator to the protocol
     * @dev Only admin can add validators, grants VALIDATOR_ROLE
     * @param validator Address of the validator to add
     * 
     * Success: Validator is added to the list and granted VALIDATOR_ROLE
     * Revert: If caller is not admin, validator is zero address, or already exists
     */
    function addValidator(address validator) external onlyRole(ADMIN_ROLE) {
        require(validator != address(0), "LiquidStaking: Invalid validator");
        require(!validators[validator], "LiquidStaking: Validator already exists");
        
        validators[validator] = true;
        validatorList.push(validator);
        _grantRole(VALIDATOR_ROLE, validator);
        
        emit ValidatorAdded(validator);
    }

    /**
     * @notice Removes a validator from the protocol
     * @dev Only admin can remove validators, revokes VALIDATOR_ROLE
     * @param validator Address of the validator to remove
     * 
     * Success: Validator is removed from list and VALIDATOR_ROLE is revoked
     * Revert: If caller is not admin or validator doesn't exist
     */
    function removeValidator(address validator) external onlyRole(ADMIN_ROLE) {
        require(validators[validator], "LiquidStaking: Validator not found");
        
        validators[validator] = false;
        _revokeRole(VALIDATOR_ROLE, validator);
        
        // Remove from validator list
        for (uint256 i = 0; i < validatorList.length; i++) {
            if (validatorList[i] == validator) {
                validatorList[i] = validatorList[validatorList.length - 1];
                validatorList.pop();
                break;
            }
        }
        
        emit ValidatorRemoved(validator);
    }

    /**
     * @notice Gets the current exchange rate of wRivexETH to ETH
     * @dev Returns the rate scaled by 1e18
     * @return Current exchange rate
     * 
     * Success: Always returns current exchange rate
     * Revert: Never reverts
     */
    function getExchangeRate() external view override returns (uint256) {
        return exchangeRate;
    }

    /**
     * @notice Gets the total amount of ETH staked in the protocol
     * @dev Returns the sum of all user stakes
     * @return Total ETH staked
     * 
     * Success: Always returns total staked amount
     * Revert: Never reverts
     */
    function getTotalStaked() external view override returns (uint256) {
        return totalETHStaked;
    }

    /**
     * @notice Calculates pending rewards that haven't been distributed yet
     * @dev Calculates time-based rewards since last update
     * @return Amount of pending rewards
     * 
     * Success: Always returns calculated pending rewards
     * Revert: Never reverts
     */
    function getPendingRewards() external view override returns (uint256) {
        if (totalETHStaked == 0) return 0;
        
        uint256 timeElapsed = block.timestamp - lastRewardUpdate;
        return (totalETHStaked * rewardRate * timeElapsed) / (BASIS_POINTS * SECONDS_PER_YEAR);
    }

    /**
     * @notice Gets the stake amount for a specific user
     * @param user Address of the user
     * @return Amount of ETH staked by the user
     * 
     * Success: Always returns user's stake amount
     * Revert: Never reverts
     */
    function getUserStake(address user) external view returns (uint256) {
        return userStakes[user];
    }

    /**
     * @notice Gets the list of all validators
     * @return Array of validator addresses
     * 
     * Success: Always returns validator list
     * Revert: Never reverts
     */
    function getValidators() external view returns (address[] memory) {
        return validatorList;
    }

    /**
     * @notice Gets the ETH balance of the contract
     * @return Contract's ETH balance
     * 
     * Success: Always returns contract balance
     * Revert: Never reverts
     */
    function getContractBalance() external view returns (uint256) {
        return address(this).balance;
    }

    /**
     * @notice Sets the minimum stake amount
     * @dev Only admin can change this parameter
     * @param _minStakeAmount New minimum stake amount
     * 
     * Success: Minimum stake amount is updated
     * Revert: If caller is not admin
     */
    function setMinStakeAmount(uint256 _minStakeAmount) external onlyRole(ADMIN_ROLE) {
        minStakeAmount = _minStakeAmount;
    }

    /**
     * @notice Sets the unstaking fee
     * @dev Only admin can change this parameter, maximum 10%
     * @param _unstakeFee New unstaking fee in basis points
     * 
     * Success: Unstaking fee is updated
     * Revert: If caller is not admin or fee exceeds 10%
     */
    function setUnstakeFee(uint256 _unstakeFee) external onlyRole(ADMIN_ROLE) {
        require(_unstakeFee <= 1000, "LiquidStaking: Fee too high"); // Max 10%
        unstakeFee = _unstakeFee;
    }

    /**
     * @notice Sets the annual reward rate
     * @dev Only admin can change this parameter, maximum 20%
     * @param _rewardRate New reward rate in basis points
     * 
     * Success: Reward rate is updated after updating current rewards
     * Revert: If caller is not admin or rate exceeds 20%
     */
    function setRewardRate(uint256 _rewardRate) external onlyRole(ADMIN_ROLE) {
        require(_rewardRate <= 2000, "LiquidStaking: Reward rate too high"); // Max 20%
        _updateRewards();
        rewardRate = _rewardRate;
    }

    /**
     * @notice Emergency withdrawal function for admin
     * @dev Allows admin to withdraw ETH in emergency situations
     * @param amount Amount of ETH to withdraw
     * 
     * Success: ETH is transferred to admin
     * Revert: If caller is not admin, insufficient balance, or transfer fails
     */
    function emergencyWithdraw(uint256 amount) external onlyRole(ADMIN_ROLE) {
        require(amount <= address(this).balance, "LiquidStaking: Insufficient balance");
        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "LiquidStaking: Transfer failed");
    }

    /**
     * @notice Pauses the contract, stopping all staking operations
     * @dev Only admin can pause the contract
     * 
     * Success: Contract is paused
     * Revert: If caller is not admin or contract is already paused
     */
    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    /**
     * @notice Unpauses the contract, resuming all operations
     * @dev Only admin can unpause the contract
     * 
     * Success: Contract is unpaused
     * Revert: If caller is not admin or contract is not paused
     */
    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    /**
     * @notice Authorizes contract upgrades
     * @dev Only addresses with UPGRADER_ROLE can authorize upgrades
     * @param newImplementation Address of the new implementation
     * 
     * Success: Upgrade is authorized
     * Revert: If caller doesn't have UPGRADER_ROLE
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}
}
