// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Script.sol";
import "../src/RivexToken.sol";
import "../src/PriceOracle.sol";
import "../src/RivexLending.sol";

contract DeployScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        vm.startBroadcast(deployerPrivateKey);
        
        console.log("Deploying contracts with deployer:", deployer);
        console.log("Deployer balance:", deployer.balance);
        
        // Deploy RivexToken
        console.log("Deploying RivexToken...");
        RivexToken rivexToken = new RivexToken(deployer);
        console.log("RivexToken deployed at:", address(rivexToken));
        
        // Deploy PriceOracle
        console.log("Deploying PriceOracle...");
        PriceOracle priceOracle = new PriceOracle();
        console.log("PriceOracle deployed at:", address(priceOracle));
        
        // Deploy RivexLending
        console.log("Deploying RivexLending...");
        RivexLending rivexLending = new RivexLending(
            address(priceOracle),
            address(rivexToken),
            deployer
        );
        console.log("RivexLending deployed at:", address(rivexLending));
        
        // Setup initial markets
        console.log("Setting up initial markets...");
        
        // List ETH market (address(0) represents ETH)
        rivexLending.listMarket(
            address(0), // ETH
            0.75e18,    // 75% collateral factor
            0.1e18,     // 10% reserve factor
            1000 ether, // 1000 ETH borrow cap
            10000 ether // 10000 ETH supply cap
        );
        console.log("ETH market listed");
        
        // List USDT market (Base network USDT address)
        address usdtAddress = 0xfde4C96c8593536E31F229EA8f37b2ADa2699bb2;
        rivexLending.listMarket(
            usdtAddress,
            0.8e18,      // 80% collateral factor
            0.1e18,      // 10% reserve factor
            1000000e6,   // 1M USDT borrow cap
            10000000e6   // 10M USDT supply cap
        );
        console.log("USDT market listed");
        
        // Grant MINTER_ROLE to RivexLending contract for rewards
        rivexToken.grantRole(rivexToken.MINTER_ROLE(), address(rivexLending));
        console.log("MINTER_ROLE granted to RivexLending");
        
        vm.stopBroadcast();
        
        console.log("\n=== Deployment Summary ===");
        console.log("RivexToken:", address(rivexToken));
        console.log("PriceOracle:", address(priceOracle));
        console.log("RivexLending:", address(rivexLending));
        console.log("Deployer:", deployer);
        
        console.log("\n=== Verification Commands ===");
        console.log("forge verify-contract", address(rivexToken), "src/RivexToken.sol:RivexToken --chain-id 8453 --constructor-args $(cast abi-encode 'constructor(address)' ", deployer, ")");
        console.log("forge verify-contract", address(priceOracle), "src/PriceOracle.sol:PriceOracle --chain-id 8453");
        console.log("forge verify-contract", address(rivexLending), "src/RivexLending.sol:RivexLending --chain-id 8453 --constructor-args $(cast abi-encode 'constructor(address,address,address)' ", address(priceOracle), " ", address(rivexToken), " ", deployer, ")");
    }
}
