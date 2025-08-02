// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./PriceOracleUpgradeable.sol";
import "./RivexTokenUpgradeable.sol";
import "./wRivexETH.sol";

/**
 * @title RivexLendingUpgradeable - RivexFi Lending Protocol
 * @notice Decentralized lending protocol allowing users to supply, borrow, and earn interest
 * @dev Upgradeable lending protocol with dynamic interest rates and liquidation mechanisms using Transparent Proxy
 */
contract RivexLendingUpgradeable is 
    Initializable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable
{
    
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
    
    PriceOracleUpgradeable public priceOracle;
    RivexTokenUpgradeable public rivexToken;
    wRivexETH public wRivexETHToken;
    
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

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the RivexFi Lending Protocol
     * @dev Sets up all contract dependencies and grants initial roles
     * @param _priceOracle Address of the price oracle contract
     * @param _rivexToken Address of the RIVEX token contract
     * @param _wRivexETHToken Address of the wRivexETH token contract
     * @param initialOwner Address that will receive all admin roles
     * 
     * Success: Contract is initialized with proper dependencies and roles
     * Revert: If called more than once or with invalid addresses
     */
    function initialize(
        address _priceOracle,
        address _rivexToken,
        address _wRivexETHToken,
        address initialOwner
    ) public initializer {
        __AccessControl_init();
        __ReentrancyGuard_init();
        __Pausable_init();

        priceOracle = PriceOracleUpgradeable(_priceOracle);
        rivexToken = RivexTokenUpgradeable(_rivexToken);
        wRivexETHToken = wRivexETH(_wRivexETHToken);
        
        _grantRole(DEFAULT_ADMIN_ROLE, initialOwner);
        _grantRole(ADMIN_ROLE, initialOwner);
        _grantRole(LIQUIDATOR_ROLE, initialOwner);
    }
    
    /**
     * @notice Lists a new token market for lending and borrowing
     * @dev Only admin can list markets, sets initial parameters and interest rates
     * @param token Address of the token to list
     * @param collateralFactor Percentage of token value that can be used as collateral (scaled by 1e18)
     * @param reserveFactor Percentage of interest that goes to reserves (scaled by 1e18)
     * @param borrowCap Maximum amount that can be borrowed from this market
     * @param supplyCap Maximum amount that can be supplied to this market
     * 
     * Success: Market is listed and available for supply/borrow operations
     * Revert: If caller is not admin, market already exists, or parameters are invalid
     */
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
    
    /**
     * @notice Supplies tokens to the lending protocol to earn interest
     * @dev Transfers tokens from user, updates interest, and records supply position
     * @param token Address of the token to supply
     * @param amount Amount of tokens to supply
     * 
     * Success: Tokens are supplied, user earns interest, and can use as collateral
     * Revert: If market not listed, amount is zero, supply cap exceeded, insufficient balance, or contract paused
     */
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
        require(IERC20(token).transferFrom(msg.sender, address(this), amount), "Transfer failed");
        
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

    /**
     * @notice Supplies ETH to the lending protocol by converting to wRivexETH
     * @dev Converts ETH to wRivexETH and supplies to the lending market
     * 
     * Success: ETH is converted to wRivexETH, supplied to market, and user earns interest
     * Revert: If no ETH sent, wRivexETH market not listed, supply cap exceeded, or contract paused
     */
    function supplyETH() external payable nonReentrant whenNotPaused {
        require(msg.value > 0, "RivexLending: Invalid amount");
        require(markets[address(wRivexETHToken)].isListed, "RivexLending: wRivexETH market not listed");
        
        // Convert ETH to wRivexETH first
        wRivexETHToken.mint(address(this), msg.value);
        
        Market storage market = markets[address(wRivexETHToken)];
        require(market.totalSupply + msg.value <= market.supplyCap, "RivexLending: Supply cap exceeded");
        
        _accrueInterest(address(wRivexETHToken));
        
        UserInfo storage user = userInfo[msg.sender][address(wRivexETHToken)];
        
        // Update user's supply with accrued interest
        if (user.supplied > 0) {
            uint256 supplierAccrued = (user.supplied * market.supplyIndex) / user.supplyIndex;
            user.supplied = supplierAccrued;
        }
        
        // Update user info
        user.supplied += msg.value;
        user.supplyIndex = market.supplyIndex;
        
        // Update market
        market.totalSupply += msg.value;
        
        // Add to user's supplied tokens if first time
        if (user.supplied == msg.value) {
            userSuppliedTokens[msg.sender].push(address(wRivexETHToken));
        }
        
        _updateRates(address(wRivexETHToken));
        
        emit Supply(msg.sender, address(wRivexETHToken), msg.value);
    }
    
    /**
     * @notice Withdraws supplied tokens from the lending protocol
     * @dev Updates interest, checks collateral requirements, and transfers tokens back
     * @param token Address of the token to withdraw
     * @param amount Amount of tokens to withdraw
     * 
     * Success: Tokens are withdrawn and transferred back to user
     * Revert: If market not listed, amount invalid/exceeds balance, would make account unhealthy, or contract paused
     */
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
        require(IERC20(token).transfer(msg.sender, amount), "Transfer failed");
        
        _updateRates(token);
        
        emit Withdraw(msg.sender, token, amount);
    }

    /**
     * @notice Withdraws ETH by converting wRivexETH back to ETH
     * @dev Burns wRivexETH from market and sends ETH to user
     * @param amount Amount of wRivexETH to withdraw (equivalent to ETH amount)
     * 
     * Success: wRivexETH is burned and equivalent ETH is sent to user
     * Revert: If amount invalid/exceeds balance, would make account unhealthy, insufficient ETH, or contract paused
     */
    function withdrawETH(uint256 amount) external nonReentrant whenNotPaused {
        require(amount > 0, "RivexLending: Invalid amount");
        require(markets[address(wRivexETHToken)].isListed, "RivexLending: wRivexETH market not listed");
        
        _accrueInterest(address(wRivexETHToken));
        
        UserInfo storage user = userInfo[msg.sender][address(wRivexETHToken)];
        Market storage market = markets[address(wRivexETHToken)];
        
        // Update user's supply with accrued interest
        uint256 supplierAccrued = (user.supplied * market.supplyIndex) / user.supplyIndex;
        user.supplied = supplierAccrued;
        user.supplyIndex = market.supplyIndex;
        
        require(user.supplied >= amount, "RivexLending: Insufficient balance");
        
        // Check if withdrawal would make account unhealthy
        require(_isWithdrawAllowed(msg.sender, address(wRivexETHToken), amount), "RivexLending: Insufficient collateral");
        
        // Update user info
        user.supplied -= amount;
        
        // Update market
        market.totalSupply -= amount;
        
        // Burn wRivexETH and send ETH
        wRivexETHToken.burn(amount);
        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "RivexLending: ETH transfer failed");
        
        _updateRates(address(wRivexETHToken));
        
        emit Withdraw(msg.sender, address(wRivexETHToken), amount);
    }
    
    /**
     * @notice Borrows tokens from the lending protocol against collateral
     * @dev Checks collateral requirements, updates interest, and transfers tokens to borrower
     * @param token Address of the token to borrow
     * @param amount Amount of tokens to borrow
     * 
     * Success: Tokens are borrowed and transferred to user, interest starts accruing
     * Revert: If market not listed, amount invalid, borrow cap exceeded, insufficient collateral, or contract paused
     */
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
        require(IERC20(token).transfer(msg.sender, amount), "Transfer failed");
        
        _updateRates(token);
        
        emit Borrow(msg.sender, token, amount);
    }

    /**
     * @notice Borrows ETH by minting wRivexETH and converting to ETH
     * @dev Mints wRivexETH to market and sends equivalent ETH to borrower
     * @param amount Amount of ETH to borrow
     * 
     * Success: wRivexETH is minted to market and equivalent ETH is sent to user
     * Revert: If amount invalid, borrow cap exceeded, insufficient collateral, insufficient ETH, or contract paused
     */
    function borrowETH(uint256 amount) external nonReentrant whenNotPaused {
        require(amount > 0, "RivexLending: Invalid amount");
        require(markets[address(wRivexETHToken)].isListed, "RivexLending: wRivexETH market not listed");
        
        Market storage market = markets[address(wRivexETHToken)];
        require(market.totalBorrows + amount <= market.borrowCap, "RivexLending: Borrow cap exceeded");
        
        _accrueInterest(address(wRivexETHToken));
        
        UserInfo storage user = userInfo[msg.sender][address(wRivexETHToken)];
        
        // Update user's borrow with accrued interest
        if (user.borrowed > 0) {
            uint256 borrowerAccrued = (user.borrowed * market.borrowIndex) / user.borrowIndex;
            user.borrowed = borrowerAccrued;
        }
        
        // Check if borrow would make account unhealthy
        require(_isBorrowAllowed(msg.sender, address(wRivexETHToken), amount), "RivexLending: Insufficient collateral");
        
        // Update user info
        user.borrowed += amount;
        user.borrowIndex = market.borrowIndex;
        
        // Update market
        market.totalBorrows += amount;
        
        // Add to user's borrowed tokens if first time
        if (user.borrowed == amount) {
            userBorrowedTokens[msg.sender].push(address(wRivexETHToken));
        }
        
        // Mint wRivexETH and send ETH
        wRivexETHToken.mint(address(this), amount);
        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "RivexLending: ETH transfer failed");
        
        _updateRates(address(wRivexETHToken));
        
        emit Borrow(msg.sender, address(wRivexETHToken), amount);
    }
    
    /**
     * @notice Repays borrowed tokens to reduce debt and interest
     * @dev Updates interest, accepts repayment, and reduces user's debt
     * @param token Address of the token to repay
     * @param amount Amount of tokens to repay (will be capped at total debt)
     * 
     * Success: Debt is reduced by repayment amount, interest stops accruing on repaid amount
     * Revert: If market not listed, amount invalid, no debt to repay, insufficient balance, or contract paused
     */
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
        require(IERC20(token).transferFrom(msg.sender, address(this), repayAmount), "Transfer failed");
        
        // Update user info
        user.borrowed -= repayAmount;
        
        // Update market
        market.totalBorrows -= repayAmount;
        
        _updateRates(token);
        
        emit Repay(msg.sender, token, repayAmount);
    }

    /**
     * @notice Repays ETH debt by converting ETH to wRivexETH
     * @dev Converts sent ETH to wRivexETH and reduces user's debt, refunds excess
     * 
     * Success: ETH debt is reduced, excess ETH is refunded if overpaid
     * Revert: If no ETH sent, wRivexETH market not listed, no debt to repay, or contract paused
     */
    function repayETH() external payable nonReentrant whenNotPaused {
        require(msg.value > 0, "RivexLending: Invalid amount");
        require(markets[address(wRivexETHToken)].isListed, "RivexLending: wRivexETH market not listed");
        
        _accrueInterest(address(wRivexETHToken));
        
        UserInfo storage user = userInfo[msg.sender][address(wRivexETHToken)];
        Market storage market = markets[address(wRivexETHToken)];
        
        // Update user's borrow with accrued interest
        uint256 borrowerAccrued = (user.borrowed * market.borrowIndex) / user.borrowIndex;
        user.borrowed = borrowerAccrued;
        user.borrowIndex = market.borrowIndex;
        
        uint256 repayAmount = msg.value > user.borrowed ? user.borrowed : msg.value;
        require(repayAmount > 0, "RivexLending: No debt to repay");
        
        // Convert ETH to wRivexETH
        wRivexETHToken.mint(address(this), repayAmount);
        
        // Update user info
        user.borrowed -= repayAmount;
        
        // Update market
        market.totalBorrows -= repayAmount;
        
        // Refund excess ETH
        if (msg.value > repayAmount) {
            (bool success, ) = payable(msg.sender).call{value: msg.value - repayAmount}("");
            require(success, "RivexLending: ETH refund failed");
        }
        
        _updateRates(address(wRivexETHToken));
        
        emit Repay(msg.sender, address(wRivexETHToken), repayAmount);
    }
    
    /**
     * @notice Liquidates an unhealthy borrower's position
     * @dev Allows liquidators to repay debt and seize collateral with bonus
     * @param borrower Address of the borrower to liquidate
     * @param tokenBorrowed Address of the borrowed token to repay
     * @param amount Amount of borrowed token to repay
     * @param tokenCollateral Address of the collateral token to seize
     * 
     * Success: Borrower's debt is reduced, liquidator receives collateral with 8% bonus
     * Revert: If caller lacks LIQUIDATOR_ROLE, account not liquidatable, markets not listed, insufficient collateral, or contract paused
     */
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
        require(IERC20(tokenBorrowed).transferFrom(msg.sender, address(this), liquidationAmount), "Transfer failed");
        
        // Transfer collateral to liquidator
        require(IERC20(tokenCollateral).transfer(msg.sender, collateralToSeize), "Transfer failed");
        
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
    
    /**
     * @notice Accrues interest for a specific market
     * @dev Updates borrow and supply indices based on time elapsed and interest rates
     * @param token Address of the token market to update
     * 
     * Success: Interest is accrued and indices are updated
     * Revert: Never reverts, but may not update if no time has passed
     */
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
    
    /**
     * @notice Updates borrow and supply rates based on utilization
     * @dev Calculates new interest rates using kink model
     * @param token Address of the token market to update rates for
     * 
     * Success: Borrow and supply rates are updated based on current utilization
     * Revert: Never reverts
     */
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
    
    /**
     * @notice Checks if a withdrawal would leave the account healthy
     * @dev Compares collateral value after withdrawal with borrow value
     * @param user Address of the user attempting withdrawal
     * @param token Address of the token being withdrawn
     * @param amount Amount of tokens to withdraw
     * @return bool True if withdrawal is allowed, false otherwise
     * 
     * Success: Always returns boolean result of health check
     * Revert: Never reverts
     */
    function _isWithdrawAllowed(address user, address token, uint256 amount) internal view returns (bool) {
        uint256 collateralValue = _getAccountCollateralValue(user) - _getTokenCollateralValue(user, token, amount);
        uint256 borrowValue = _getAccountBorrowValue(user);
        
        return collateralValue >= borrowValue;
    }
    
    /**
     * @notice Checks if a borrow would leave the account healthy
     * @dev Compares collateral value with borrow value after new borrow
     * @param user Address of the user attempting to borrow
     * @param token Address of the token being borrowed
     * @param amount Amount of tokens to borrow
     * @return bool True if borrow is allowed, false otherwise
     * 
     * Success: Always returns boolean result of health check
     * Revert: Never reverts
     */
    function _isBorrowAllowed(address user, address token, uint256 amount) internal view returns (bool) {
        uint256 collateralValue = _getAccountCollateralValue(user);
        uint256 borrowValue = _getAccountBorrowValue(user) + _getTokenBorrowValue(token, amount);
        
        return collateralValue >= borrowValue;
    }
    
    /**
     * @notice Checks if an account is eligible for liquidation
     * @dev Compares total borrow value with total collateral value
     * @param user Address of the user to check
     * @return bool True if account can be liquidated, false otherwise
     * 
     * Success: Always returns boolean result of liquidation eligibility
     * Revert: Never reverts
     */
    function _isAccountLiquidatable(address user) internal view returns (bool) {
        uint256 collateralValue = _getAccountCollateralValue(user);
        uint256 borrowValue = _getAccountBorrowValue(user);
        
        return borrowValue > collateralValue;
    }
    
    /**
     * @notice Calculates total collateral value for a user across all markets
     * @dev Sums up collateral value from all supplied tokens with their collateral factors
     * @param user Address of the user
     * @return Total collateral value in USD (scaled by price feed decimals)
     * 
     * Success: Always returns calculated total collateral value
     * Revert: May revert if price oracle fails
     */
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
    
    /**
     * @notice Calculates total borrow value for a user across all markets
     * @dev Sums up borrow value from all borrowed tokens
     * @param user Address of the user
     * @return Total borrow value in USD (scaled by price feed decimals)
     * 
     * Success: Always returns calculated total borrow value
     * Revert: May revert if price oracle fails
     */
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
    
    /**
     * @notice Calculates collateral value for a specific token amount
     * @dev Multiplies token amount by price and collateral factor
     * @param user Address of the user (unused but kept for interface consistency)
     * @param token Address of the token
     * @param amount Amount of tokens
     * @return Collateral value in USD (scaled by price feed decimals)
     * 
     * Success: Always returns calculated collateral value
     * Revert: May revert if price oracle fails
     */
    function _getTokenCollateralValue(address user, address token, uint256 amount) internal view returns (uint256) {
        uint256 tokenPrice = priceOracle.getPrice(token);
        uint256 collateralFactor = markets[token].collateralFactor;
        return (amount * tokenPrice * collateralFactor) / (1e18 * 1e18);
    }
    
    /**
     * @notice Calculates borrow value for a specific token amount
     * @dev Multiplies token amount by current price
     * @param token Address of the token
     * @param amount Amount of tokens
     * @return Borrow value in USD (scaled by price feed decimals)
     * 
     * Success: Always returns calculated borrow value
     * Revert: May revert if price oracle fails
     */
    function _getTokenBorrowValue(address token, uint256 amount) internal view returns (uint256) {
        uint256 tokenPrice = priceOracle.getPrice(token);
        return (amount * tokenPrice) / 1e18;
    }
    
    /**
     * @notice Gets account liquidity information for a user
     * @dev Returns both collateral and borrow values for health assessment
     * @param user Address of the user to check
     * @return collateralValue Total collateral value in USD
     * @return borrowValue Total borrow value in USD
     * 
     * Success: Always returns both values for account assessment
     * Revert: May revert if price oracle fails
     */
    function getAccountLiquidity(address user) external view returns (uint256 collateralValue, uint256 borrowValue) {
        collateralValue = _getAccountCollateralValue(user);
        borrowValue = _getAccountBorrowValue(user);
    }
    
    /**
     * @notice Gets list of tokens supplied by a user
     * @dev Returns array of token addresses that user has supplied
     * @param user Address of the user
     * @return Array of token addresses
     * 
     * Success: Always returns array of supplied token addresses
     * Revert: Never reverts
     */
    function getUserSuppliedTokens(address user) external view returns (address[] memory) {
        return userSuppliedTokens[user];
    }
    
    /**
     * @notice Gets list of tokens borrowed by a user
     * @dev Returns array of token addresses that user has borrowed
     * @param user Address of the user
     * @return Array of token addresses
     * 
     * Success: Always returns array of borrowed token addresses
     * Revert: Never reverts
     */
    function getUserBorrowedTokens(address user) external view returns (address[] memory) {
        return userBorrowedTokens[user];
    }
    
    /**
     * @notice Pauses the contract, stopping all lending operations
     * @dev Only admin can pause the contract
     * 
     * Success: Contract is paused, all operations are blocked
     * Revert: If caller is not admin or contract is already paused
     */
    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }
    
    /**
     * @notice Unpauses the contract, resuming all operations
     * @dev Only admin can unpause the contract
     * 
     * Success: Contract is unpaused, all operations are allowed again
     * Revert: If caller is not admin or contract is not paused
     */
    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }
    
    /**
     * @notice Updates market parameters for a listed token
     * @dev Only admin can update market parameters
     * @param token Address of the token market to update
     * @param collateralFactor New collateral factor (max 90%)
     * @param reserveFactor New reserve factor (max 50%)
     * @param borrowCap New borrow cap
     * @param supplyCap New supply cap
     * 
     * Success: Market parameters are updated
     * Revert: If caller is not admin, market not listed, or parameters are invalid
     */
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

    /**
     * @notice Fallback function to receive ETH
     * @dev Allows contract to receive ETH for ETH-based operations
     * 
     * Success: ETH is received by the contract
     * Revert: Never reverts
     */
    receive() external payable {}
}
