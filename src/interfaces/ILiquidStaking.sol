// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface ILiquidStaking {
    event Stake(address indexed user, uint256 ethAmount, uint256 wRivexETHAmount);
    event Unstake(address indexed user, uint256 wRivexETHAmount, uint256 ethAmount);
    event RewardsDistributed(uint256 amount);
    event ValidatorAdded(address indexed validator);
    event ValidatorRemoved(address indexed validator);

    function stake() external payable returns (uint256);
    function unstake(uint256 wRivexETHAmount) external returns (uint256);
    function getExchangeRate() external view returns (uint256);
    function getTotalStaked() external view returns (uint256);
    function getPendingRewards() external view returns (uint256);
}
