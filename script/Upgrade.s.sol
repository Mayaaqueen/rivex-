// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "../src/RivexTokenUpgradeable.sol";
import "../src/PriceOracleUpgradeable.sol";
import "../src/RivexLendingUpgradeable.sol";
import "../src/wRivexETH.sol";
import "../src/LiquidStaking.sol";
import "../src/RivexDEXAggregator.sol";

contract UpgradeScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        vm.startBroadcast(deployerPrivateKey);
        
        console.log("Upgrading contracts with deployer:", deployer);
        
        // Get ProxyAdmin address
        address proxyAdminAddress = vm.envAddress("PROXY_ADMIN");
        ProxyAdmin proxyAdmin = ProxyAdmin(proxyAdminAddress);
        
        // Replace these addresses with your deployed proxy addresses
        address rivexTokenProxy = vm.envAddress("RIVEX_TOKEN_PROXY");
        address priceOracleProxy = vm.envAddress("PRICE_ORACLE_PROXY");
        address wRivexETHProxy = vm.envAddress("WRIVEXETH_PROXY");
        address liquidStakingProxy = vm.envAddress("LIQUID_STAKING_PROXY");
        address rivexLendingProxy = vm.envAddress("RIVEX_LENDING_PROXY");
        address dexAggregatorProxy = vm.envAddress("DEX_AGGREGATOR_PROXY");
        
        // Deploy new implementations
        console.log("Deploying new implementations...");
        
        RivexTokenUpgradeable newRivexTokenImpl = new RivexTokenUpgradeable();
        console.log("New RivexToken implementation:", address(newRivexTokenImpl));
        
        PriceOracleUpgradeable newPriceOracleImpl = new PriceOracleUpgradeable();
        console.log("New PriceOracle implementation:", address(newPriceOracleImpl));
        
        wRivexETH newWRivexETHImpl = new wRivexETH();
        console.log("New wRivexETH implementation:", address(newWRivexETHImpl));
        
        LiquidStaking newLiquidStakingImpl = new LiquidStaking();
        console.log("New LiquidStaking implementation:", address(newLiquidStakingImpl));
        
        RivexLendingUpgradeable newRivexLendingImpl = new RivexLendingUpgradeable();
        console.log("New RivexLending implementation:", address(newRivexLendingImpl));
        
        RivexDEXAggregator newDexAggregatorImpl = new RivexDEXAggregator();
        console.log("New RivexDEXAggregator implementation:", address(newDexAggregatorImpl));
        
        // Upgrade contracts through ProxyAdmin
        console.log("Upgrading contracts...");
        
        proxyAdmin.upgradeAndCall(
            rivexTokenProxy,
            address(newRivexTokenImpl),
            ""
        );
        console.log("RivexToken upgraded");
        
        proxyAdmin.upgradeAndCall(
            priceOracleProxy,
            address(newPriceOracleImpl),
            ""
        );
        console.log("PriceOracle upgraded");
        
        proxyAdmin.upgradeAndCall(
            wRivexETHProxy,
            address(newWRivexETHImpl),
            ""
        );
        console.log("wRivexETH upgraded");
        
        proxyAdmin.upgradeAndCall(
            liquidStakingProxy,
            address(newLiquidStakingImpl),
            ""
        );
        console.log("LiquidStaking upgraded");
        
        proxyAdmin.upgradeAndCall(
            rivexLendingProxy,
            address(newRivexLendingImpl),
            ""
        );
        console.log("RivexLending upgraded");
        
        proxyAdmin.upgradeAndCall(
            dexAggregatorProxy,
            address(newDexAggregatorImpl),
            ""
        );
        console.log("RivexDEXAggregator upgraded");
        
        vm.stopBroadcast();
        
        console.log("\n=== Upgrade Summary ===");
        console.log("All contracts upgraded successfully!");
        console.log("New implementation addresses:");
        console.log("RivexToken:", address(newRivexTokenImpl));
        console.log("PriceOracle:", address(newPriceOracleImpl));
        console.log("wRivexETH:", address(newWRivexETHImpl));
        console.log("LiquidStaking:", address(newLiquidStakingImpl));
        console.log("RivexLending:", address(newRivexLendingImpl));
        console.log("RivexDEXAggregator:", address(newDexAggregatorImpl));
    }
}
