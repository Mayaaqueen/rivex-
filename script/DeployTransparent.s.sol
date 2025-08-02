// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "../src/RivexTokenUpgradeable.sol";
import "../src/PriceOracleUpgradeable.sol";
import "../src/RivexLendingUpgradeable.sol";
import "../src/wRivexETH.sol";
import "../src/LiquidStaking.sol";

contract DeployTransparentScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        vm.startBroadcast(deployerPrivateKey);
        
        console.log("Deploying Transparent Upgradeable contracts with deployer:", deployer);
        console.log("Deployer balance:", deployer.balance);
        
        // Deploy ProxyAdmin
        console.log("Deploying ProxyAdmin...");
        ProxyAdmin proxyAdmin = new ProxyAdmin(deployer);
        console.log("ProxyAdmin deployed at:", address(proxyAdmin));
        
        // Deploy RivexToken Implementation
        console.log("Deploying RivexToken implementation...");
        RivexTokenUpgradeable rivexTokenImpl = new RivexTokenUpgradeable();
        
        // Deploy RivexToken Transparent Proxy
        bytes memory rivexTokenInitData = abi.encodeWithSelector(
            RivexTokenUpgradeable.initialize.selector,
            deployer
        );
        TransparentUpgradeableProxy rivexTokenProxy = new TransparentUpgradeableProxy(
            address(rivexTokenImpl),
            address(proxyAdmin),
            rivexTokenInitData
        );
        RivexTokenUpgradeable rivexToken = RivexTokenUpgradeable(address(rivexTokenProxy));
        console.log("RivexToken proxy deployed at:", address(rivexToken));
        
        // Deploy PriceOracle Implementation
        console.log("Deploying PriceOracle implementation...");
        PriceOracleUpgradeable priceOracleImpl = new PriceOracleUpgradeable();
        
        // Deploy PriceOracle Transparent Proxy
        bytes memory priceOracleInitData = abi.encodeWithSelector(
            PriceOracleUpgradeable.initialize.selector,
            deployer
        );
        TransparentUpgradeableProxy priceOracleProxy = new TransparentUpgradeableProxy(
            address(priceOracleImpl),
            address(proxyAdmin),
            priceOracleInitData
        );
        PriceOracleUpgradeable priceOracle = PriceOracleUpgradeable(address(priceOracleProxy));
        console.log("PriceOracle proxy deployed at:", address(priceOracle));
        
        // Deploy wRivexETH Implementation
        console.log("Deploying wRivexETH implementation...");
        wRivexETH wRivexETHImpl = new wRivexETH();
        
        // Deploy wRivexETH Transparent Proxy
        bytes memory wRivexETHInitData = abi.encodeWithSelector(
            wRivexETH.initialize.selector,
            deployer
        );
        TransparentUpgradeableProxy wRivexETHProxy = new TransparentUpgradeableProxy(
            address(wRivexETHImpl),
            address(proxyAdmin),
            wRivexETHInitData
        );
        wRivexETH wRivexETHToken = wRivexETH(address(wRivexETHProxy));
        console.log("wRivexETH proxy deployed at:", address(wRivexETHToken));
        
        // Deploy LiquidStaking Implementation
        console.log("Deploying LiquidStaking implementation...");
        LiquidStaking liquidStakingImpl = new LiquidStaking();
        
        // Deploy LiquidStaking Transparent Proxy
        bytes memory liquidStakingInitData = abi.encodeWithSelector(
            LiquidStaking.initialize.selector,
            address(wRivexETHToken),
            deployer,
            0.01 ether,  // minStakeAmount: 0.01 ETH
            100,         // unstakeFee: 1%
            500          // rewardRate: 5% APY
        );
        TransparentUpgradeableProxy liquidStakingProxy = new TransparentUpgradeableProxy(
            address(liquidStakingImpl),
            address(proxyAdmin),
            liquidStakingInitData
        );
        LiquidStaking liquidStaking = LiquidStaking(payable(address(liquidStakingProxy)));
        console.log("LiquidStaking proxy deployed at:", address(liquidStaking));
        
        // Deploy RivexLending Implementation
        console.log("Deploying RivexLending implementation...");
        RivexLendingUpgradeable rivexLendingImpl = new RivexLendingUpgradeable();
        
        // Deploy RivexLending Transparent Proxy
        bytes memory rivexLendingInitData = abi.encodeWithSelector(
            RivexLendingUpgradeable.initialize.selector,
            address(priceOracle),
            address(rivexToken),
            address(wRivexETHToken),
            deployer
        );
        TransparentUpgradeableProxy rivexLendingProxy = new TransparentUpgradeableProxy(
            address(rivexLendingImpl),
            address(proxyAdmin),
            rivexLendingInitData
        );
        RivexLendingUpgradeable rivexLending = RivexLendingUpgradeable(payable(address(rivexLendingProxy)));
        console.log("RivexLending proxy deployed at:", address(rivexLending));
        
        // Setup permissions
        console.log("Setting up permissions...");
        
        // Grant MINTER_ROLE to LiquidStaking for wRivexETH
        wRivexETHToken.grantRole(wRivexETHToken.MINTER_ROLE(), address(liquidStaking));
        wRivexETHToken.grantRole(wRivexETHToken.BURNER_ROLE(), address(liquidStaking));
        
        // Grant MINTER_ROLE to RivexLending for wRivexETH
        wRivexETHToken.grantRole(wRivexETHToken.MINTER_ROLE(), address(rivexLending));
        wRivexETHToken.grantRole(wRivexETHToken.BURNER_ROLE(), address(rivexLending));
        
        // Grant MINTER_ROLE to RivexLending for rewards
        rivexToken.grantRole(rivexToken.MINTER_ROLE(), address(rivexLending));
        
        // Setup initial markets
        console.log("Setting up initial markets...");
        
        // List wRivexETH market
        rivexLending.listMarket(
            address(wRivexETHToken),
            0.75e18,    // 75% collateral factor
            0.1e18,     // 10% reserve factor
            1000 ether, // 1000 ETH borrow cap
            10000 ether // 10000 ETH supply cap
        );
        console.log("wRivexETH market listed");
        
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
        
        // Add price feed for wRivexETH (same as ETH)
        priceOracle.setPriceFeed(address(wRivexETHToken), 0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70);
        console.log("wRivexETH price feed set");
        
        vm.stopBroadcast();
        
        console.log("\n=== Transparent Proxy Deployment Summary ===");
        console.log("ProxyAdmin:", address(proxyAdmin));
        console.log("RivexToken Proxy:", address(rivexToken));
        console.log("PriceOracle Proxy:", address(priceOracle));
        console.log("wRivexETH Proxy:", address(wRivexETHToken));
        console.log("LiquidStaking Proxy:", address(liquidStaking));
        console.log("RivexLending Proxy:", address(rivexLending));
        console.log("Deployer:", deployer);
        
        console.log("\n=== Implementation Addresses ===");
        console.log("RivexToken Implementation:", address(rivexTokenImpl));
        console.log("PriceOracle Implementation:", address(priceOracleImpl));
        console.log("wRivexETH Implementation:", address(wRivexETHImpl));
        console.log("LiquidStaking Implementation:", address(liquidStakingImpl));
        console.log("RivexLending Implementation:", address(rivexLendingImpl));
        
        console.log("\n=== Usage Instructions ===");
        console.log("1. Stake ETH: Send ETH to LiquidStaking contract or call stake()");
        console.log("2. Supply to lending: Call supplyETH() or supply() with tokens");
        console.log("3. Borrow: Call borrowETH() or borrow() with tokens");
        console.log("4. Unstake: Call unstake() on LiquidStaking with wRivexETH amount");
        console.log("5. Upgrade contracts: Use ProxyAdmin to upgrade implementations");
    }
}
