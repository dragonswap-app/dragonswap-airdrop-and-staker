// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IStaker} from "src/interfaces/IStaker.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockStaker is IStaker {
    struct StakeInfo {
        address staker;
        uint256 amount;
        uint256 lockupIndex;
        uint256 timestamp;
    }

    mapping(address => StakeInfo[]) public stakes;
    mapping(address => uint256) public totalStaked;

    event Staked(address indexed staker, uint256 amount, uint256 lockupIndex);

    function stake(address staker, uint256 amount, uint256 lockupIndex) external override {
        /* Pull tokens from msg.sender (should be the Airdrop contract) */
        IERC20 token = IERC20(msg.sender);
        token.transferFrom(msg.sender, address(this), amount);

        /* Record stake */
        stakes[staker].push(
            StakeInfo({staker: staker, amount: amount, lockupIndex: lockupIndex, timestamp: block.timestamp})
        );

        totalStaked[staker] += amount;

        emit Staked(staker, amount, lockupIndex);
    }

    /* Helper function for testing */
    function getStakeCount(address staker) external view returns (uint256) {
        return stakes[staker].length;
    }

    /* Helper function for testing */
    function getStake(address staker, uint256 index) external view returns (StakeInfo memory) {
        return stakes[staker][index];
    }
}
