// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/RivexTokenUpgradeable.sol";
import "../src/PriceOracleUpgradeable.sol";
import "../src/RivexLendingUpgradeable.sol";
import "../src/wRivexETH.sol";
import "../src/LiquidStaking.sol";

contract RivexProtocolTest is Test {
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
        
        // Deploy RivexToken
        RivexTokenUpgradeable rivexTokenImpl = new RivexTokenUpgradeable();
        bytes memory rivexTokenInitData = abi.encodeWithSelector(
            RivexTokenUpgradeable.initialize.selector,
            admin
        );
        ERC1967Proxy rivexTokenProxy = new ERC1967Proxy(
            address(rivexTokenImpl),
            rivexTokenInitData
        );
        rivexToken = RivexTokenUpgradeable(address(rivexTokenProxy));
        
        // Deploy PriceOracle
        PriceOracleUpgradeable priceOracleImpl = new PriceOracleUpgradeable();
        bytes memory priceOracleInitData = abi.encodeWithSelector(
            PriceOracleUpgradeable.initialize.selector,
            admin
        );
        ERC1967Proxy priceOracleProxy = new ERC1967Proxy(
            address(priceOracleImpl),
            priceOracleInitData
        );
        priceOracle = PriceOracleUpgradeable(address(priceOracleProxy));
        
        // Deploy wRivexETH
        wRivexETH wRivexETHImpl = new wRivexETH();
        bytes memory wRivexETHInitData = abi.encodeWithSelector(
            wRivexETH.initialize.selector,
            admin
        );
        ERC1967Proxy wRivexETHProxy = new ERC1967Proxy(
            address(wRivexETHImpl),
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
        ERC1967Proxy liquidStakingProxy = new ERC1967Proxy(
            address(liquidStakingImpl),
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
        ERC1967Proxy rivexLendingProxy = new ERC1967Proxy(
            address(rivexLendingImpl),
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
    
    function testUpgradeability() public {
        vm.startPrank(admin);
        
        // Test that contracts are upgradeable
        assertTrue(rivexToken.hasRole(rivexToken.UPGRADER_ROLE(), admin));
        assertTrue(wRivexETHToken.hasRole(wRivexETHToken.UPGRADER_ROLE(), admin));
        
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
}
