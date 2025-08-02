// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "./PriceOracle.sol";
import "./RivexToken.sol";

contract RivexLending is AccessControl, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;
    
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant LIQUIDATOR_ROLE = keccak256("LIQUIDATOR_ROLE");
    
    struct Market {
        bool isListed;
        uint256 collateralFactor; // Scaled by 1e18
        uint256 reserveFactor; // Scaled by 1e18
        uint256 borrowCap;
        uint256 supplyCap;
        uint256 totalSupply;
        uint256 totalBorrows;
        uint256 borrowIndex;
        uint256 supplyIndex;
        uint256 lastUpdateTime;
        uint256 borrowRate;
        uint256 supplyRate;
    }
    
    struct UserInfo {
        uint256 supplied;
        uint256 borrowed;
        uint256 supplyIndex;
        uint256 borrowIndex;
    }
    
    mapping(address => Market) public markets;
    mapping(address => mapping(address => UserInfo)) public userInfo; // user => token => info
    mapping(address => address[]) public userSuppliedTokens;
    mapping(address => address[]) public userBorrowedTokens;
    
    PriceOracle public immutable priceOracle;
    RivexToken public immutable rivexToken;
    
    uint256 public constant CLOSE_FACTOR = 0.5e18; // 50%
    uint256 public constant LIQUIDATION_INCENTIVE = 1.08e18; // 8% bonus
    uint256 public constant BASE_RATE = 0.02e18; // 2% base rate
    uint256 public constant MULTIPLIER = 0.1e18; // 10% multiplier
    uint256 public constant KINK = 0.8e18; // 80% utilization kink
    uint256 public constant JUMP_MULTIPLIER = 1.09e18; // 109% jump multiplier
    
    event Supply(address indexed user, address indexed token, uint256 amount);
    event Withdraw(address indexed user, address indexed token, uint256 amount);
    event Borrow(address indexed user, address indexed token, uint256 amount);
    event Repay(address indexed user, address indexed token, uint256 amount);
    event Liquidate(address indexed liquidator, address indexed borrower, address indexed tokenBorrowed, address tokenCollateral, uint256 amount);
    event MarketListed(address indexed token);
    
    constructor(address _priceOracle, address _rivexToken, address admin) {
        priceOracle = PriceOracle(_priceOracle);
        rivexToken = RivexToken(_rivexToken);
        
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
        _grantRole(LIQUIDATOR_ROLE, admin);
    }
    
    function listMarket(
        address token,
        uint256 collateralFactor,
        uint256 reserveFactor,
        uint256 borrowCap,
        uint256 supplyCap
    ) external onlyRole(ADMIN_ROLE) {
        require(!markets[token].isListed, "RivexLending: Market already listed");
        require(collateralFactor <= 0.9e18, "RivexLending: Invalid collateral factor");
        require(reserveFactor <= 0.5e18, "RivexLending: Invalid reserve factor");
        
        markets[token] = Market({
            isListed: true,
            collateralFactor: collateralFactor,
            reserveFactor: reserveFactor,
            borrowCap: borrowCap,
            supplyCap: supplyCap,
            totalSupply: 0,
            totalBorrows: 0,
            borrowIndex: 1e18,
            supplyIndex: 1e18,
            lastUpdateTime: block.timestamp,
            borrowRate: BASE_RATE,
            supplyRate: 0
        });
        
        emit MarketListed(token);
    }
    
    function supply(address token, uint256 amount) external nonReentrant whenNotPaused {
        require(markets[token].isListed, "RivexLending: Market not listed");
        require(amount > 0, "RivexLending: Invalid amount");
        
        Market storage market = markets[token];
        require(market.totalSupply + amount <= market.supplyCap, "RivexLending: Supply cap exceeded");
        
        _accrueInterest(token);
        
        UserInfo storage user = userInfo[msg.sender][token];
        
        // Update user's supply with accrued interest
        if (user.supplied > 0) {
            uint256 supplierAccrued = (user.supplied * market.supplyIndex) / user.supplyIndex;
            user.supplied = supplierAccrued;
        }
        
        // Transfer tokens
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        
        // Update user info
        user.supplied += amount;
        user.supplyIndex = market.supplyIndex;
        
        // Update market
        market.totalSupply += amount;
        
        // Add to user's supplied tokens if first time
        if (user.supplied == amount) {
            userSuppliedTokens[msg.sender].push(token);
        }
        
        _updateRates(token);
        
        emit Supply(msg.sender, token, amount);
    }
    
    function withdraw(address token, uint256 amount) external nonReentrant whenNotPaused {
        require(markets[token].isListed, "RivexLending: Market not listed");
        require(amount > 0, "RivexLending: Invalid amount");
        
        _accrueInterest(token);
        
        UserInfo storage user = userInfo[msg.sender][token];
        Market storage market = markets[token];
        
        // Update user's supply with accrued interest
        uint256 supplierAccrued = (user.supplied * market.supplyIndex) / user.supplyIndex;
        user.supplied = supplierAccrued;
        user.supplyIndex = market.supplyIndex;
        
        require(user.supplied >= amount, "RivexLending: Insufficient balance");
        
        // Check if withdrawal would make account unhealthy
        require(_isWithdrawAllowed(msg.sender, token, amount), "RivexLending: Insufficient collateral");
        
        // Update user info
        user.supplied -= amount;
        
        // Update market
        market.totalSupply -= amount;
        
        // Transfer tokens
        IERC20(token).safeTransfer(msg.sender, amount);
        
        _updateRates(token);
        
        emit Withdraw(msg.sender, token, amount);
    }
    
    function borrow(address token, uint256 amount) external nonReentrant whenNotPaused {
        require(markets[token].isListed, "RivexLending: Market not listed");
        require(amount > 0, "RivexLending: Invalid amount");
        
        Market storage market = markets[token];
        require(market.totalBorrows + amount <= market.borrowCap, "RivexLending: Borrow cap exceeded");
        
        _accrueInterest(token);
        
        UserInfo storage user = userInfo[msg.sender][token];
        
        // Update user's borrow with accrued interest
        if (user.borrowed > 0) {
            uint256 borrowerAccrued = (user.borrowed * market.borrowIndex) / user.borrowIndex;
            user.borrowed = borrowerAccrued;
        }
        
        // Check if borrow would make account unhealthy
        require(_isBorrowAllowed(msg.sender, token, amount), "RivexLending: Insufficient collateral");
        
        // Update user info
        user.borrowed += amount;
        user.borrowIndex = market.borrowIndex;
        
        // Update market
        market.totalBorrows += amount;
        
        // Add to user's borrowed tokens if first time
        if (user.borrowed == amount) {
            userBorrowedTokens[msg.sender].push(token);
        }
        
        // Transfer tokens
        IERC20(token).safeTransfer(msg.sender, amount);
        
        _updateRates(token);
        
        emit Borrow(msg.sender, token, amount);
    }
    
    function repay(address token, uint256 amount) external nonReentrant whenNotPaused {
        require(markets[token].isListed, "RivexLending: Market not listed");
        require(amount > 0, "RivexLending: Invalid amount");
        
        _accrueInterest(token);
        
        UserInfo storage user = userInfo[msg.sender][token];
        Market storage market = markets[token];
        
        // Update user's borrow with accrued interest
        uint256 borrowerAccrued = (user.borrowed * market.borrowIndex) / user.borrowIndex;
        user.borrowed = borrowerAccrued;
        user.borrowIndex = market.borrowIndex;
        
        uint256 repayAmount = amount > user.borrowed ? user.borrowed : amount;
        require(repayAmount > 0, "RivexLending: No debt to repay");
        
        // Transfer tokens
        IERC20(token).safeTransferFrom(msg.sender, address(this), repayAmount);
        
        // Update user info
        user.borrowed -= repayAmount;
        
        // Update market
        market.totalBorrows -= repayAmount;
        
        _updateRates(token);
        
        emit Repay(msg.sender, token, repayAmount);
    }
    
    function liquidate(
        address borrower,
        address tokenBorrowed,
        uint256 amount,
        address tokenCollateral
    ) external nonReentrant whenNotPaused onlyRole(LIQUIDATOR_ROLE) {
        require(markets[tokenBorrowed].isListed && markets[tokenCollateral].isListed, "RivexLending: Market not listed");
        require(_isAccountLiquidatable(borrower), "RivexLending: Account not liquidatable");
        
        _accrueInterest(tokenBorrowed);
        _accrueInterest(tokenCollateral);
        
        UserInfo storage borrowerInfo = userInfo[borrower][tokenBorrowed];
        UserInfo storage collateralInfo = userInfo[borrower][tokenCollateral];
        
        // Update borrower's debt with accrued interest
        uint256 borrowerAccrued = (borrowerInfo.borrowed * markets[tokenBorrowed].borrowIndex) / borrowerInfo.borrowIndex;
        borrowerInfo.borrowed = borrowerAccrued;
        borrowerInfo.borrowIndex = markets[tokenBorrowed].borrowIndex;
        
        // Calculate max liquidation amount
        uint256 maxLiquidation = (borrowerInfo.borrowed * CLOSE_FACTOR) / 1e18;
        uint256 liquidationAmount = amount > maxLiquidation ? maxLiquidation : amount;
        
        // Calculate collateral to seize
        uint256 collateralPrice = priceOracle.getPrice(tokenCollateral);
        uint256 borrowPrice = priceOracle.getPrice(tokenBorrowed);
        uint256 collateralToSeize = (liquidationAmount * borrowPrice * LIQUIDATION_INCENTIVE) / (collateralPrice * 1e18);
        
        // Update borrower's collateral
        uint256 supplierAccrued = (collateralInfo.supplied * markets[tokenCollateral].supplyIndex) / collateralInfo.supplyIndex;
        collateralInfo.supplied = supplierAccrued;
        collateralInfo.supplyIndex = markets[tokenCollateral].supplyIndex;
        
        require(collateralInfo.supplied >= collateralToSeize, "RivexLending: Insufficient collateral");
        
        // Transfer repayment from liquidator
        IERC20(tokenBorrowed).safeTransferFrom(msg.sender, address(this), liquidationAmount);
        
        // Transfer collateral to liquidator
        IERC20(tokenCollateral).safeTransfer(msg.sender, collateralToSeize);
        
        // Update borrower's positions
        borrowerInfo.borrowed -= liquidationAmount;
        collateralInfo.supplied -= collateralToSeize;
        
        // Update markets
        markets[tokenBorrowed].totalBorrows -= liquidationAmount;
        markets[tokenCollateral].totalSupply -= collateralToSeize;
        
        _updateRates(tokenBorrowed);
        _updateRates(tokenCollateral);
        
        emit Liquidate(msg.sender, borrower, tokenBorrowed, tokenCollateral, liquidationAmount);
    }
    
    function _accrueInterest(address token) internal {
        Market storage market = markets[token];
        uint256 currentTime = block.timestamp;
        uint256 deltaTime = currentTime - market.lastUpdateTime;
        
        if (deltaTime == 0) return;
        
        uint256 borrowRate = market.borrowRate;
        uint256 interestAccumulated = (market.totalBorrows * borrowRate * deltaTime) / (365 days * 1e18);
        
        market.totalBorrows += interestAccumulated;
        market.borrowIndex = market.borrowIndex + (market.borrowIndex * borrowRate * deltaTime) / (365 days * 1e18);
        
        uint256 reserveAmount = (interestAccumulated * market.reserveFactor) / 1e18;
        uint256 supplierAmount = interestAccumulated - reserveAmount;
        
        if (market.totalSupply > 0) {
            market.supplyIndex = market.supplyIndex + (market.supplyIndex * supplierAmount) / market.totalSupply;
        }
        
        market.lastUpdateTime = currentTime;
    }
    
    function _updateRates(address token) internal {
        Market storage market = markets[token];
        
        if (market.totalSupply == 0) {
            market.borrowRate = BASE_RATE;
            market.supplyRate = 0;
            return;
        }
        
        uint256 utilization = (market.totalBorrows * 1e18) / market.totalSupply;
        
        if (utilization <= KINK) {
            market.borrowRate = BASE_RATE + (utilization * MULTIPLIER) / 1e18;
        } else {
            uint256 excessUtilization = utilization - KINK;
            market.borrowRate = BASE_RATE + (KINK * MULTIPLIER) / 1e18 + (excessUtilization * JUMP_MULTIPLIER) / 1e18;
        }
        
        market.supplyRate = (market.borrowRate * utilization * (1e18 - market.reserveFactor)) / (1e18 * 1e18);
    }
    
    function _isWithdrawAllowed(address user, address token, uint256 amount) internal view returns (bool) {
        uint256 collateralValue = _getAccountCollateralValue(user) - _getTokenCollateralValue(user, token, amount);
        uint256 borrowValue = _getAccountBorrowValue(user);
        
        return collateralValue >= borrowValue;
    }
    
    function _isBorrowAllowed(address user, address token, uint256 amount) internal view returns (bool) {
        uint256 collateralValue = _getAccountCollateralValue(user);
        uint256 borrowValue = _getAccountBorrowValue(user) + _getTokenBorrowValue(token, amount);
        
        return collateralValue >= borrowValue;
    }
    
    function _isAccountLiquidatable(address user) internal view returns (bool) {
        uint256 collateralValue = _getAccountCollateralValue(user);
        uint256 borrowValue = _getAccountBorrowValue(user);
        
        return borrowValue > collateralValue;
    }
    
    function _getAccountCollateralValue(address user) internal view returns (uint256) {
        uint256 totalValue = 0;
        address[] memory suppliedTokens = userSuppliedTokens[user];
        
        for (uint256 i = 0; i < suppliedTokens.length; i++) {
            address token = suppliedTokens[i];
            UserInfo memory userToken = userInfo[user][token];
            Market memory market = markets[token];
            
            if (userToken.supplied > 0) {
                uint256 supplierAccrued = (userToken.supplied * market.supplyIndex) / userToken.supplyIndex;
                uint256 tokenPrice = priceOracle.getPrice(token);
                uint256 collateralValue = (supplierAccrued * tokenPrice * market.collateralFactor) / (1e18 * 1e18);
                totalValue += collateralValue;
            }
        }
        
        return totalValue;
    }
    
    function _getAccountBorrowValue(address user) internal view returns (uint256) {
        uint256 totalValue = 0;
        address[] memory borrowedTokens = userBorrowedTokens[user];
        
        for (uint256 i = 0; i < borrowedTokens.length; i++) {
            address token = borrowedTokens[i];
            UserInfo memory userToken = userInfo[user][token];
            Market memory market = markets[token];
            
            if (userToken.borrowed > 0) {
                uint256 borrowerAccrued = (userToken.borrowed * market.borrowIndex) / userToken.borrowIndex;
                uint256 tokenPrice = priceOracle.getPrice(token);
                uint256 borrowValue = (borrowerAccrued * tokenPrice) / 1e18;
                totalValue += borrowValue;
            }
        }
        
        return totalValue;
    }
    
    function _getTokenCollateralValue(address user, address token, uint256 amount) internal view returns (uint256) {
        uint256 tokenPrice = priceOracle.getPrice(token);
        uint256 collateralFactor = markets[token].collateralFactor;
        return (amount * tokenPrice * collateralFactor) / (1e18 * 1e18);
    }
    
    function _getTokenBorrowValue(address token, uint256 amount) internal view returns (uint256) {
        uint256 tokenPrice = priceOracle.getPrice(token);
        return (amount * tokenPrice) / 1e18;
    }
    
    // View functions
    function getAccountLiquidity(address user) external view returns (uint256 collateralValue, uint256 borrowValue) {
        collateralValue = _getAccountCollateralValue(user);
        borrowValue = _getAccountBorrowValue(user);
    }
    
    function getUserSuppliedTokens(address user) external view returns (address[] memory) {
        return userSuppliedTokens[user];
    }
    
    function getUserBorrowedTokens(address user) external view returns (address[] memory) {
        return userBorrowedTokens[user];
    }
    
    // Admin functions
    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }
    
    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }
    
    function updateMarketParams(
        address token,
        uint256 collateralFactor,
        uint256 reserveFactor,
        uint256 borrowCap,
        uint256 supplyCap
    ) external onlyRole(ADMIN_ROLE) {
        require(markets[token].isListed, "RivexLending: Market not listed");
        require(collateralFactor <= 0.9e18, "RivexLending: Invalid collateral factor");
        require(reserveFactor <= 0.5e18, "RivexLending: Invalid reserve factor");
        
        Market storage market = markets[token];
        market.collateralFactor = collateralFactor;
        market.reserveFactor = reserveFactor;
        market.borrowCap = borrowCap;
        market.supplyCap = supplyCap;
    }
}
