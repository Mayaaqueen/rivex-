// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "../src/RivexTokenUpgradeable.sol";
import "../src/PriceOracleUpgradeable.sol";
import "../src/RivexLendingUpgradeable.sol";
import "../src/wRivexETH.sol";
import "../src/LiquidStaking.sol";

contract RivexProtocolTransparentTest is Test {
    ProxyAdmin public proxyAdmin;
    RivexTokenUpgradeable public rivexToken;
    PriceOracleUpgradeable public priceOracle;
    RivexLendingUpgradeable public rivexLending;
    wRivexETH public wRivexETHToken;
    LiquidStaking public liquidStaking;
    
    address public admin = address(0x1);
    address public user1 = address(0x2);
    address public user2 = address(0x3);
    
    function setUp() public {
        vm.startPrank(admin);
        
        // Deploy ProxyAdmin
        proxyAdmin = new ProxyAdmin(admin);
        
        // Deploy RivexToken
        RivexTokenUpgradeable rivexTokenImpl = new RivexTokenUpgradeable();
        bytes memory rivexTokenInitData = abi.encodeWithSelector(
            RivexTokenUpgradeable.initialize.selector,
            admin
        );
        TransparentUpgradeableProxy rivexTokenProxy = new TransparentUpgradeableProxy(
            address(rivexTokenImpl),
            address(proxyAdmin),
            rivexTokenInitData
        );
        rivexToken = RivexTokenUpgradeable(address(rivexTokenProxy));
        
        // Deploy PriceOracle
        PriceOracleUpgradeable priceOracleImpl = new PriceOracleUpgradeable();
        bytes memory priceOracleInitData = abi.encodeWithSelector(
            PriceOracleUpgradeable.initialize.selector,
            admin
        );
        TransparentUpgradeableProxy priceOracleProxy = new TransparentUpgradeableProxy(
            address(priceOracleImpl),
            address(proxyAdmin),
            priceOracleInitData
        );
        priceOracle = PriceOracleUpgradeable(address(priceOracleProxy));
        
        // Deploy wRivexETH
        wRivexETH wRivexETHImpl = new wRivexETH();
        bytes memory wRivexETHInitData = abi.encodeWithSelector(
            wRivexETH.initialize.selector,
            admin
        );
        TransparentUpgradeableProxy wRivexETHProxy = new TransparentUpgradeableProxy(
            address(wRivexETHImpl),
            address(proxyAdmin),
            wRivexETHInitData
        );
        wRivexETHToken = wRivexETH(address(wRivexETHProxy));
        
        // Deploy LiquidStaking
        LiquidStaking liquidStakingImpl = new LiquidStaking();
        bytes memory liquidStakingInitData = abi.encodeWithSelector(
            LiquidStaking.initialize.selector,
            address(wRivexETHToken),
            admin,
            0.01 ether,
            100,
            500
        );
        TransparentUpgradeableProxy liquidStakingProxy = new TransparentUpgradeableProxy(
            address(liquidStakingImpl),
            address(proxyAdmin),
            liquidStakingInitData
        );
        liquidStaking = LiquidStaking(payable(address(liquidStakingProxy)));
        
        // Deploy RivexLending
        RivexLendingUpgradeable rivexLendingImpl = new RivexLendingUpgradeable();
        bytes memory rivexLendingInitData = abi.encodeWithSelector(
            RivexLendingUpgradeable.initialize.selector,
            address(priceOracle),
            address(rivexToken),
            address(wRivexETHToken),
            admin
        );
        TransparentUpgradeableProxy rivexLendingProxy = new TransparentUpgradeableProxy(
            address(rivexLendingImpl),
            address(proxyAdmin),
            rivexLendingInitData
        );
        rivexLending = RivexLendingUpgradeable(payable(address(rivexLendingProxy)));
        
        // Setup permissions
        wRivexETHToken.grantRole(wRivexETHToken.MINTER_ROLE(), address(liquidStaking));
        wRivexETHToken.grantRole(wRivexETHToken.BURNER_ROLE(), address(liquidStaking));
        wRivexETHToken.grantRole(wRivexETHToken.MINTER_ROLE(), address(rivexLending));
        wRivexETHToken.grantRole(wRivexETHToken.BURNER_ROLE(), address(rivexLending));
        
        // List wRivexETH market
        rivexLending.listMarket(
            address(wRivexETHToken),
            0.75e18,
            0.1e18,
            1000 ether,
            10000 ether
        );
        
        vm.stopPrank();
        
        // Fund test accounts
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
        vm.deal(address(liquidStaking), 0);
    }
    
    function testTransparentProxyDeployment() public {
        // Test that ProxyAdmin is deployed correctly
        assertEq(proxyAdmin.owner(), admin);
        
        // Test that all proxies are deployed correctly
        assertTrue(address(rivexToken) != address(0));
        assertTrue(address(priceOracle) != address(0));
        assertTrue(address(wRivexETHToken) != address(0));
        assertTrue(address(liquidStaking) != address(0));
        assertTrue(address(rivexLending) != address(0));
    }
    
    function testLiquidStaking() public {
        vm.startPrank(user1);
        
        // Test staking
        uint256 stakeAmount = 1 ether;
        liquidStaking.stake{value: stakeAmount}();
        
        assertEq(wRivexETHToken.balanceOf(user1), stakeAmount);
        assertEq(liquidStaking.getTotalStaked(), stakeAmount);
        assertEq(liquidStaking.getUserStake(user1), stakeAmount);
        
        // Test unstaking
        wRivexETHToken.approve(address(liquidStaking), stakeAmount);
        uint256 ethBefore = user1.balance;
        liquidStaking.unstake(stakeAmount);
        
        // Should receive ETH minus fee
        uint256 expectedETH = stakeAmount - (stakeAmount * 100) / 10000; // 1% fee
        assertApproxEqAbs(user1.balance - ethBefore, expectedETH, 1e15);
        
        vm.stopPrank();
    }
    
    function testLendingWithETH() public {
        vm.startPrank(user1);
        
        // Supply ETH
        uint256 supplyAmount = 1 ether;
        rivexLending.supplyETH{value: supplyAmount}();
        
        // Check wRivexETH balance in lending contract
        assertEq(wRivexETHToken.balanceOf(address(rivexLending)), supplyAmount);
        
        vm.stopPrank();
        
        vm.startPrank(user2);
        
        // Supply ETH as collateral
        rivexLending.supplyETH{value: 2 ether}();
        
        // Borrow ETH
        uint256 borrowAmount = 0.5 ether;
        uint256 ethBefore = user2.balance;
        rivexLending.borrowETH(borrowAmount);
        
        assertEq(user2.balance - ethBefore, borrowAmount);
        
        // Repay ETH
        rivexLending.repayETH{value: borrowAmount}();
        
        vm.stopPrank();
    }
    
    function testTransparentUpgradeability() public {
        vm.startPrank(admin);
        
        // Deploy new implementation
        RivexTokenUpgradeable newImpl = new RivexTokenUpgradeable();
        
        // Test upgrade via ProxyAdmin
        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(rivexToken)),
            address(newImpl),
            ""
        );
        
        // Test that contract still works after upgrade
        assertTrue(rivexToken.hasRole(rivexToken.MINTER_ROLE(), admin));
        
        vm.stopPrank();
    }
    
    function testAccessControl() public {
        // Test that non-admin cannot mint
        vm.startPrank(user1);
        vm.expectRevert();
        rivexToken.mint(user1, 1000 ether);
        
        vm.expectRevert();
        wRivexETHToken.mint(user1, 1000 ether);
        
        vm.stopPrank();
        
        // Test that admin can mint
        vm.startPrank(admin);
        rivexToken.mint(user1, 1000 ether);
        assertEq(rivexToken.balanceOf(user1), 1000 ether);
        
        vm.stopPrank();
    }
    
    function testProxyAdminOwnership() public {
        // Test that only admin can upgrade contracts
        vm.startPrank(user1);
        
        RivexTokenUpgradeable newImpl = new RivexTokenUpgradeable();
        
        vm.expectRevert();
        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(rivexToken)),
            address(newImpl),
            ""
        );
        
        vm.stopPrank();
    }
}
