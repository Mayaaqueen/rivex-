// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract PriceOracle is Ownable {
    mapping(address => AggregatorV3Interface) public priceFeeds;
    
    // Base network Chainlink price feeds
    address public constant ETH_USD_FEED = 0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70;
    address public constant USDT_USD_FEED = 0xf19d560eB8d2ADf07BD6D13ed03e1D11215721F9;
    
    event PriceFeedUpdated(address indexed token, address indexed priceFeed);
    
    constructor() Ownable(msg.sender) {
        // Initialize price feeds for Base network
        priceFeeds[address(0)] = AggregatorV3Interface(ETH_USD_FEED); // ETH
        priceFeeds[0xfde4C96c8593536E31F229EA8f37b2ADa2699bb2] = AggregatorV3Interface(USDT_USD_FEED); // USDT on Base
    }
    
    function setPriceFeed(address token, address priceFeed) external onlyOwner {
        require(priceFeed != address(0), "PriceOracle: Invalid price feed");
        priceFeeds[token] = AggregatorV3Interface(priceFeed);
        emit PriceFeedUpdated(token, priceFeed);
    }
    
    function getPrice(address token) external view returns (uint256) {
        AggregatorV3Interface priceFeed = priceFeeds[token];
        require(address(priceFeed) != address(0), "PriceOracle: Price feed not found");
        
        (, int256 price, , uint256 updatedAt, ) = priceFeed.latestRoundData();
        require(price > 0, "PriceOracle: Invalid price");
        require(updatedAt > 0, "PriceOracle: Price not updated");
        require(block.timestamp - updatedAt <= 3600, "PriceOracle: Price too old"); // 1 hour
        
        return uint256(price);
    }
    
    function getPriceDecimals(address token) external view returns (uint8) {
        AggregatorV3Interface priceFeed = priceFeeds[token];
        require(address(priceFeed) != address(0), "PriceOracle: Price feed not found");
        return priceFeed.decimals();
    }
    
    // Get ETH/USDT price ratio
    function getETHUSDTPrice() external view returns (uint256) {
        uint256 ethPrice = this.getPrice(address(0)); // ETH price in USD
        uint256 usdtPrice = this.getPrice(0xfde4C96c8593536E31F229EA8f37b2ADa2699bb2); // USDT price in USD
        
        // Return ETH price in USDT terms (scaled by 1e18)
        return (ethPrice * 1e18) / usdtPrice;
    }
}
