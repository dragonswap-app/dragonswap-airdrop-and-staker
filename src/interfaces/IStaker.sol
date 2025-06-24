pragma solidity 0.8.30;

interface IStaker {
    function stake(address account, uint256 amount, bool locking) external;
    function treasury() external view returns (address);
    function fee() external view returns (uint256);
    function computeFeeAmount(uint256 amount) external view returns (uint256);
}
