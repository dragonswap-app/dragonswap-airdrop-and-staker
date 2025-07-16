// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

import {Staker} from "../src/Staker.sol";

import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract StakerTest is Test {
    using MessageHashUtils for bytes32;

    Staker public staker;
    ERC20Mock public stakingToken;
    ERC20Mock public rewardToken;

    address public constant OWNER = address(1);
    address public constant TREASURY = address(2);

    uint256 LOCK_TIMESPAN = 90 days;
    uint256 MINIMUM_DEPOSIT = 5 wei;
    uint256 public constant MINT_AMOUNT = 1_000_000e18;

    function setUp() public {
        stakingToken = new ERC20Mock();
        stakingToken.mint(address(this), MINT_AMOUNT);

        rewardToken = new ERC20Mock();
        rewardToken.mint(address(this), MINT_AMOUNT);

        address[] memory rewardTokens = new address[](1);
        rewardTokens[0] = address(rewardToken);

        staker = new Staker(OWNER, address(stakingToken), TREASURY, MINIMUM_DEPOSIT, 1_00, rewardTokens);
    }

    function test() external {
        // Stake tokens
        uint256 stakeAmount = 1000e18;
        uint256 rewardAmount = 100e18;
        stakingToken.approve(address(staker), stakeAmount);
        staker.stake(address(this), stakeAmount, true);

        // The earliest possible time the stake can be withdrawn
        vm.warp(block.timestamp + LOCK_TIMESPAN);

        assertEq(staker.pendingRewards(address(this), 0, address(rewardToken)), 0);

        rewardToken.transfer(address(staker), rewardAmount);

        assertEq(staker.pendingRewards(address(this), 0, address(rewardToken)), rewardAmount);

        uint256 preClaimBalance = rewardToken.balanceOf(address(this));
        uint256[] memory stakeIndexes = new uint256[](1);
        assertEq(staker.pendingRewards(address(this), 0, address(rewardToken)), rewardAmount);
        staker.claimEarnings(stakeIndexes, address(0x0));
        uint256 postClaimBalance = rewardToken.balanceOf(address(this));
        assertEq(preClaimBalance + rewardAmount, postClaimBalance);

        uint256 preWithdrwaBalance = stakingToken.balanceOf(address(this));
        staker.withdraw(stakeIndexes, address(0x0));
        uint256 postWithdrwaBalance = stakingToken.balanceOf(address(this));
        assertEq(preWithdrwaBalance + stakeAmount, postWithdrwaBalance);
    }
}
