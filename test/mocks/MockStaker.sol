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

    address public token;
    address public airdrop;

    event Staked(address indexed staker, uint256 amount, uint256 lockupIndex);

    constructor() {}

    // Set the token address that this staker will work with
    function setToken(address _token) external {
        token = _token;
    }

    // Set the airdrop address that is allowed to call stake
    function setAirdrop(address _airdrop) external {
        airdrop = _airdrop;
    }

    function stake(address staker, uint256 amount, uint256 lockupIndex) external override {
        require(msg.sender == airdrop, "Only airdrop can call stake");

        /* Pull tokens from the Airdrop contract */
        IERC20(token).transferFrom(msg.sender, address(this), amount);

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
