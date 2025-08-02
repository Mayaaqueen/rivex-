// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title PriceOracleUpgradeable - Chainlink Price Feed Oracle
 * @notice Provides real-time price data from Chainlink oracles for various tokens
 * @dev Upgradeable contract that manages multiple price feeds and validates price data
 */
contract PriceOracleUpgradeable is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    mapping(address => AggregatorV3Interface) public priceFeeds;
    
    // Base network Chainlink price feeds
    address public constant ETH_USD_FEED = 0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70;
    address public constant USDT_USD_FEED = 0xf19d560eB8d2ADf07BD6D13ed03e1D11215721F9;
    
    event PriceFeedUpdated(address indexed token, address indexed priceFeed);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }
    
    /**
     * @notice Initializes the Price Oracle contract
     * @dev Sets up ownership and initializes default price feeds for Base network
     * @param admin The address that will become the owner of the contract
     * 
     * Success: Contract is initialized with owner set and default price feeds configured
     * Revert: If called more than once (already initialized)
     */
    function initialize(address admin) public initializer {
        __Ownable_init(admin);
        __UUPSUpgradeable_init();
        
        // Initialize price feeds for Base network
        priceFeeds[address(0)] = AggregatorV3Interface(ETH_USD_FEED); // ETH
        priceFeeds[0xfde4C96c8593536E31F229EA8f37b2ADa2699bb2] = AggregatorV3Interface(USDT_USD_FEED); // USDT on Base
    }
    
    /**
     * @notice Sets or updates a price feed for a specific token
     * @dev Only owner can set price feeds, emits PriceFeedUpdated event
     * @param token The token address (use address(0) for ETH)
     * @param priceFeed The Chainlink price feed contract address
     * 
     * Success: Price feed is set for the token and event is emitted
     * Revert: If caller is not owner or priceFeed is zero address
     */
    function setPriceFeed(address token, address priceFeed) external onlyOwner {
        require(priceFeed != address(0), "PriceOracle: Invalid price feed");
        priceFeeds[token] = AggregatorV3Interface(priceFeed);
        emit PriceFeedUpdated(token, priceFeed);
    }
    
    /**
     * @notice Gets the latest price for a specific token
     * @dev Fetches price from Chainlink oracle with validation checks
     * @param token The token address to get price for
     * @return The latest price scaled by the feed's decimals
     * 
     * Success: Returns valid, recent price from Chainlink oracle
     * Revert: If price feed not found, price is invalid/zero, or price data is too old (>1 hour)
     */
    function getPrice(address token) external view returns (uint256) {
        AggregatorV3Interface priceFeed = priceFeeds[token];
        require(address(priceFeed) != address(0), "PriceOracle: Price feed not found");
        
        (, int256 price, , uint256 updatedAt, ) = priceFeed.latestRoundData();
        require(price > 0, "PriceOracle: Invalid price");
        require(updatedAt > 0, "PriceOracle: Price not updated");
        require(block.timestamp - updatedAt <= 3600, "PriceOracle: Price too old"); // 1 hour
        
        return uint256(price);
    }
    
    /**
     * @notice Gets the decimal precision of a token's price feed
     * @dev Returns the number of decimals used by the Chainlink price feed
     * @param token The token address to get decimals for
     * @return The number of decimals (typically 8 for USD feeds)
     * 
     * Success: Returns the decimal precision of the price feed
     * Revert: If price feed not found for the token
     */
    function getPriceDecimals(address token) external view returns (uint8) {
        AggregatorV3Interface priceFeed = priceFeeds[token];
        require(address(priceFeed) != address(0), "PriceOracle: Price feed not found");
        return priceFeed.decimals();
    }
    
    /**
     * @notice Calculates the ETH/USDT exchange rate
     * @dev Combines ETH/USD and USDT/USD prices to get ETH/USDT ratio
     * @return The ETH price in USDT terms, scaled by 1e18
     * 
     * Success: Returns calculated ETH/USDT exchange rate
     * Revert: If either ETH or USDT price feeds fail or return invalid data
     */
    function getETHUSDTPrice() external view returns (uint256) {
        uint256 ethPrice = this.getPrice(address(0)); // ETH price in USD
        uint256 usdtPrice = this.getPrice(0xfde4C96c8593536E31F229EA8f37b2ADa2699bb2); // USDT price in USD
        
        // Return ETH price in USDT terms (scaled by 1e18)
        return (ethPrice * 1e18) / usdtPrice;
    }

    /**
     * @notice Authorizes contract upgrades
     * @dev Only owner can authorize upgrades
     * @param newImplementation Address of the new implementation
     * 
     * Success: Upgrade is authorized
     * Revert: If caller is not owner
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
