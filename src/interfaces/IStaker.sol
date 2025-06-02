pragma solidity 0.8.30;

interface IStaker {
    function stake(address account, uint256 amount, bool locking) external;
    function fee() external view returns (uint256);
}
