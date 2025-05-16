pragma solidity 0.8.30;

interface IStaker {
    function stake(address account, uint256 amount, uint256 lockupIndex) external;
}
