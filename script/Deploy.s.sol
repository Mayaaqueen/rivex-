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
import "../src/RivexDEXAggregator.sol";

contract DeployScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        vm.startBroadcast(deployerPrivateKey);
        
        console.log("Deploying RivexFi Protocol with Transparent Upgradeable Proxy");
        console.log("Deployer:", deployer);
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
        
        // Deploy RivexDEXAggregator Implementation
        console.log("Deploying RivexDEXAggregator implementation...");
        RivexDEXAggregator dexAggregatorImpl = new RivexDEXAggregator();
        
        // Deploy RivexDEXAggregator Transparent Proxy
        bytes memory dexAggregatorInitData = abi.encodeWithSelector(
            RivexDEXAggregator.initialize.selector,
            deployer,
            30,      // feeRate: 0.3%
            deployer // feeRecipient
        );
        TransparentUpgradeableProxy dexAggregatorProxy = new TransparentUpgradeableProxy(
            address(dexAggregatorImpl),
            address(proxyAdmin),
            dexAggregatorInitData
        );
        RivexDEXAggregator dexAggregator = RivexDEXAggregator(payable(address(dexAggregatorProxy)));
        console.log("RivexDEXAggregator proxy deployed at:", address(dexAggregator));
        
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
        
        // Setup DEX Aggregator - Authorize popular DEXs on Base
        console.log("Setting up DEX Aggregator...");
        
        // Uniswap V2 Router on Base
        dexAggregator.setDEXAuthorization(0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24, true);
        console.log("Uniswap V2 Router authorized");
        
        // Uniswap V3 Router on Base
        dexAggregator.setDEXAuthorization(0x2626664c2603336E57B271c5C0b26F421741e481, true);
        console.log("Uniswap V3 Router authorized");
        
        // Uniswap V3 SwapRouter02 on Base
        dexAggregator.setDEXAuthorization(0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45, true);
        console.log("Uniswap V3 SwapRouter02 authorized");
        
        // Aerodrome Router on Base
        dexAggregator.setDEXAuthorization(0xcF77a3Ba9A5CA399B7c97c74d54e5b1Beb874E43, true);
        console.log("Aerodrome Router authorized");
        
        // Aerodrome Sugar (Helper contract) on Base
        dexAggregator.setDEXAuthorization(0x1F98431c8aD98523631AE4a59f267346ea31F984, true);
        console.log("Aerodrome Sugar authorized");
        
        // SushiSwap V2 Router on Base
        dexAggregator.setDEXAuthorization(0x6BDED42c6DA8FBf0d2bA55B2fa120C5e0c8D7891, true);
        console.log("SushiSwap V2 Router authorized");
        
        // SushiSwap V3 Router on Base
        dexAggregator.setDEXAuthorization(0xFB7eF66a7e61224DD6FcD0D7d9C3be5C8B049b9f, true);
        console.log("SushiSwap V3 Router authorized");
        
        // Curve Finance Pools on Base (Main pools)
        // Curve 3Pool (USDC/USDT/DAI)
        dexAggregator.setDEXAuthorization(0x4DEcE678ceceb27446b35C672dC7d61F30bAD69E, true);
        console.log("Curve 3Pool authorized");
        
        // Curve crvUSD Pool
        dexAggregator.setDEXAuthorization(0x390f3595bCa2Df7d23783dFd126427CCeb997BF4, true);
        console.log("Curve crvUSD Pool authorized");
        
        // Balancer Vault on Base
        dexAggregator.setDEXAuthorization(0xBA12222222228d8Ba445958a75a0704d566BF2C8, true);
        console.log("Balancer Vault authorized");
        
        // 1inch Aggregation Router V5 on Base
        dexAggregator.setDEXAuthorization(0x1111111254EEB25477B68fb85Ed929f73A960582, true);
        console.log("1inch Aggregation Router V5 authorized");
        
        // 1inch Limit Order Protocol on Base
        dexAggregator.setDEXAuthorization(0x119c71D3BbAC22029622cbaEc24854d3D32D2828, true);
        console.log("1inch Limit Order Protocol authorized");
        
        // 0x Protocol Exchange Proxy on Base
        dexAggregator.setDEXAuthorization(0xDef1C0ded9bec7F1a1670819833240f027b25EfF, true);
        console.log("0x Protocol Exchange Proxy authorized");
        
        // PancakeSwap V2 Router on Base
        dexAggregator.setDEXAuthorization(0x8cFe327CEc66d1C090Dd72bd0FF11d690C33a2Eb, true);
        console.log("PancakeSwap V2 Router authorized");
        
        // PancakeSwap V3 Router on Base
        dexAggregator.setDEXAuthorization(0x1b81D678ffb9C0263b24A97847620C99d213eB14, true);
        console.log("PancakeSwap V3 Router authorized");
        
        // BaseSwap Router (Native Base DEX)
        dexAggregator.setDEXAuthorization(0x327Df1E6de05895d2ab08513aaDD9313Fe505d86, true);
        console.log("BaseSwap Router authorized");
        
        // SwapBased Router (Another Base DEX)
        dexAggregator.setDEXAuthorization(0x6131B5fae19EA4f9D964eAc0408E4408b66337b5, true);
        console.log("SwapBased Router authorized");

        // Authorize common tokens for trading
        console.log("Authorizing tokens for DEX trading...");
        
        dexAggregator.setTokenAuthorization(address(0), true); // ETH
        dexAggregator.setTokenAuthorization(address(wRivexETHToken), true); // wRivexETH
        dexAggregator.setTokenAuthorization(address(rivexToken), true); // RIVEX
        
        // Base Network Native Tokens
        dexAggregator.setTokenAuthorization(0x4200000000000000000000000000000000000006, true); // WETH
        dexAggregator.setTokenAuthorization(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913, true); // USDC
        dexAggregator.setTokenAuthorization(0xfde4C96c8593536E31F229EA8f37b2ADa2699bb2, true); // USDT
        dexAggregator.setTokenAuthorization(0x50c5725949A6F0c72E6C4a641F24049A917DB0Cb, true); // DAI
        dexAggregator.setTokenAuthorization(0x2Ae3F1Ec7F1F5012CFEab0185bfc7aa3cf0DEc22, true); // cbETH
        dexAggregator.setTokenAuthorization(0xB6fe221Fe9EeF5aBa221c348bA20A1Bf5e73624c, true); // rETH
        dexAggregator.setTokenAuthorization(0x940181a94A35A4569E4529A3CDfB74e38FD98631, true); // AERO
        dexAggregator.setTokenAuthorization(0x27D2DECb4bFC9C76F0309b8E88dec3a601Fe25a8, true); // BALD
        dexAggregator.setTokenAuthorization(0x0578292CB20a443bA1CdE459c985CE14Ca2bDEe5, true); // PRIME
        dexAggregator.setTokenAuthorization(0x4ed4E862860beD51a9570b96d89aF5E1B0Efefed, true); // DEGEN
        
        console.log("Base Network tokens authorized for DEX trading");
        
        vm.stopBroadcast();
        
        console.log("\n=== RivexFi Protocol Deployment Summary ===");
        console.log("ProxyAdmin:", address(proxyAdmin));
        console.log("RivexToken Proxy:", address(rivexToken));
        console.log("PriceOracle Proxy:", address(priceOracle));
        console.log("wRivexETH Proxy:", address(wRivexETHToken));
        console.log("LiquidStaking Proxy:", address(liquidStaking));
        console.log("RivexLending Proxy:", address(rivexLending));
        console.log("RivexDEXAggregator Proxy:", address(dexAggregator));
        console.log("Deployer:", deployer);
        
        console.log("\n=== Implementation Addresses ===");
        console.log("RivexToken Implementation:", address(rivexTokenImpl));
        console.log("PriceOracle Implementation:", address(priceOracleImpl));
        console.log("wRivexETH Implementation:", address(wRivexETHImpl));
        console.log("LiquidStaking Implementation:", address(liquidStakingImpl));
        console.log("RivexLending Implementation:", address(rivexLendingImpl));
        console.log("RivexDEXAggregator Implementation:", address(dexAggregatorImpl));
        
        console.log("\n=== Protocol Features ===");
        console.log("- Transparent Upgradeable Proxy Pattern");
        console.log("- OpenZeppelin v5.4.0 Contracts");
        console.log("- Liquid Staking with wRivexETH");
        console.log("- Lending & Borrowing Protocol");
        console.log("- Multi-DEX Aggregator with Multicall");
        console.log("- Chainlink Price Oracles");
        console.log("- Role-based Access Control");
        console.log("- Emergency Pause Functionality");
        
        console.log("\n=== Authorized DEXs on Base Network ===");
        console.log("Uniswap:");
        console.log("- V2 Router: 0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24");
        console.log("- V3 Router: 0x2626664c2603336E57B271c5C0b26F421741e481");
        console.log("- V3 SwapRouter02: 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45");
        
        console.log("Aerodrome:");
        console.log("- Router: 0xcF77a3Ba9A5CA399B7c97c74d54e5b1Beb874E43");
        console.log("- Sugar: 0x1F98431c8aD98523631AE4a59f267346ea31F984");
        
        console.log("SushiSwap:");
        console.log("- V2 Router: 0x6BDED42c6DA8FBf0d2bA55B2fa120C5e0c8D7891");
        console.log("- V3 Router: 0xFB7eF66a7e61224DD6FcD0D7d9C3be5C8B049b9f");
        
        console.log("Curve Finance:");
        console.log("- 3Pool: 0x4DEcE678ceceb27446b35C672dC7d61F30bAD69E");
        console.log("- crvUSD Pool: 0x390f3595bCa2Df7d23783dFd126427CCeb997BF4");
        
        console.log("Others:");
        console.log("- Balancer Vault: 0xBA12222222228d8Ba445958a75a0704d566BF2C8");
        console.log("- 1inch Router V5: 0x1111111254EEB25477B68fb85Ed929f73A960582");
        console.log("- 0x Exchange Proxy: 0xDef1C0ded9bec7F1a1670819833240f027b25EfF");
        console.log("- PancakeSwap V2: 0x8cFe327CEc66d1C090Dd72bd0FF11d690C33a2Eb");
        console.log("- BaseSwap: 0x327Df1E6de05895d2ab08513aaDD9313Fe505d86");
        
        console.log("\n=== Authorized Tokens on Base Network ===");
        console.log("Core Tokens:");
        console.log("- ETH: 0x0000000000000000000000000000000000000000");
        console.log("- WETH: 0x4200000000000000000000000000000000000006");
        console.log("- wRivexETH:", address(wRivexETHToken));
        console.log("- RIVEX:", address(rivexToken));
        
        console.log("Stablecoins:");
        console.log("- USDC: 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913");
        console.log("- USDT: 0xfde4C96c8593536E31F229EA8f37b2ADa2699bb2");
        console.log("- DAI: 0x50c5725949A6F0c72E6C4a641F24049A917DB0Cb");
        
        console.log("LSTs & Others:");
        console.log("- cbETH: 0x2Ae3F1Ec7F1F5012CFEab0185bfc7aa3cf0DEc22");
        console.log("- rETH: 0xB6fe221Fe9EeF5aBa221c348bA20A1Bf5e73624c");
        console.log("- AERO: 0x940181a94A35A4569E4529A3CDfB74e38FD98631");
        console.log("- DEGEN: 0x4ed4E862860beD51a9570b96d89aF5E1B0Efefed");
        
        console.log("\n=== Next Steps ===");
        console.log("1. Verify contracts on Basescan");
        console.log("2. Set up additional price feeds");
        console.log("3. Configure liquidation parameters");
        console.log("4. Add more DEX authorizations");
        console.log("5. Deploy frontend interface");
        console.log("6. Conduct security audit");
    }
}
