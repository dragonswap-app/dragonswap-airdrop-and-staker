// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IStaker} from "src/interfaces/IStaker.sol";

contract MockStaker is IStaker {
    uint256 private _fee = 50_00; // Default 50% fee
    IERC20 public token;

    mapping(address => uint256) public stakes;
    mapping(address => bool) public lockingStatus;

    event Staked(address indexed account, uint256 amount, bool locking);

    constructor() {}

    function setToken(address _token) external {
        token = IERC20(_token);
    }

    function setFee(uint256 newFee) external {
        _fee = newFee;
    }

    function fee() external view override returns (uint256) {
        return _fee;
    }

    function stake(address account, uint256 amount, bool locking) external override {
        // Transfer tokens from the caller (airdrop contract) to this contract
        if (address(token) != address(0)) {
            token.transferFrom(msg.sender, address(this), amount);
        }

        stakes[account] += amount;
        lockingStatus[account] = locking;

        emit Staked(account, amount, locking);
    }

    // Helper function to check staked amount (for testing)
    function getStakedAmount(address account) external view returns (uint256) {
        return stakes[account];
    }

    // Helper function to check locking status (for testing)
    function isLocked(address account) external view returns (bool) {
        return lockingStatus[account];
    }
}
