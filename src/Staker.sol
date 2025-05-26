// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {StakedDragonswapToken} from "./StakedDragonswapToken.sol";

contract DragonswapRevenueShareStaking is Ownable, StakedDragonswapToken {
    using SafeERC20 for IERC20;

    struct Stake {
        uint256 amount;
        uint256 unlockTimestamp;
        // bool claimed;
    }
    //uint256 multiplier;

    /// @notice The address of the Dragonswap token
    IERC20 public immutable dragon;
    /// @notice Total amount of deposits
    uint256 public totalDeposits;
    /// @notice Array of tokens that users can be distributed as rewards to the stakers
    address[] public rewardTokens;
    uint256[3] public lockTimespans = [90 days, 180 days, 365 days];
    uint256 private constant minimumDeposit = 100e18;
    uint256 private constant stakeLimitPerUser = 100;
    /// @notice Mapping to check if a token is a reward token
    mapping(address => bool) public isRewardToken;
    /// @notice Last reward balance of `token`
    mapping(address => uint256) public lastRewardBalance;
    /// @notice Accumulated `token` rewards per share, scaled to `P`
    mapping(address => uint256) public accRewardsPerShare;

    mapping(address => Stake[]) private stakes;
    mapping(bytes32 => uint256) private rewardDebt;
    mapping(address => uint256) private stakeCounter;

    address private airdropContract;

    bytes32 private immutable debtHashBase = keccak256(abi.encode(block.chainid, address(this)));

    /// @notice The precision of `accRewardsPerShare`
    uint256 private constant P = 1e18;

    /// Events
    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 amount);
    event Payout(address indexed user, IERC20 indexed rewardToken, uint256 amount);
    event RewardTokenAdded(address indexed token);
    event RewardTokenRemoved(IERC20 indexed token);
    event Unstuck(address indexed token, address indexed to, uint256 amount);

    /// Errors
    error InvalidAddress();
    error InvalidValue();
    error AlreadyAdded();
    error NoBalance();
    error NotPresent();
    error InvalidLockIndex();
    error AccountCrossingStakeLimit();

    constructor(address _owner, address _dragon, address _airdropContract, address[] memory _rewardTokens)
        Ownable(_owner)
    {
        if (_dragon == address(0)) revert InvalidAddress();
        dragon = IERC20(_dragon);

        // Optional
        airdropContract = _airdropContract;

        for (uint256 i; i < _rewardTokens.length; ++i) {
            address _rewardToken = _rewardTokens[i];
            if (_rewardToken == address(0)) revert InvalidAddress();
            isRewardToken[_rewardToken] = true;
            rewardTokens.push(_rewardToken);
            emit RewardTokenAdded(_rewardToken);
        }
    }

    function setAirdropContract(address _airdropContract) external onlyOwner {
        airdropContract = _airdropContract;
    }

    /**
     * @notice Deposit Dragon in order to receive the reward tokens
     * @param amount The amount of Dragon to deposit
     */
    function deposit(address account, uint256 amount, uint256 lockIndex) private {
        if (msg.sender != airdropContract) account = msg.sender;
        // if (account == address(0)) revert();
        if (amount < minimumDeposit) revert InvalidValue();
        if (lockIndex >= lockTimespans.length) revert InvalidLockIndex();
        // check stake limit

        // calculate accumulation with total sDRG instead of drg
        totalDeposits += amount;

        uint256 numberOfStakesOwnedByAnAccount = stakes[account].length;
        if (numberOfStakesOwnedByAnAccount == stakeLimitPerUser) revert AccountCrossingStakeLimit();

        uint256 numberOfRewardTokens = rewardTokens.length;
        for (uint256 i; i < numberOfRewardTokens; ++i) {
            address token = rewardTokens[i];
            _updateAccumulated(token);

            uint256 _accRewardsPerShare = accRewardsPerShare[token];
            rewardDebt[computeDebtAccessHash(account, numberOfStakesOwnedByAnAccount, token)] =
                (amount * _accRewardsPerShare) / P;
        }

        stakes[account].push(Stake({amount: amount, unlockTimestamp: block.timestamp + lockTimespans[lockIndex]}));

        ++stakeCounter[account];

        _mint(account, amount);

        dragon.safeTransferFrom(msg.sender, address(this), amount);

        emit Deposit(msg.sender, amount);
    }

    function getAccountStakeAndDebts(address account, uint256 stakeIndex)
        external
        view
        returns (uint256, uint256, uint256[] memory)
    {
        Stake memory stake = stakes[account][stakeIndex];
        address[] memory _rewardTokens = rewardTokens;

        uint256[] memory rewardDebts = new uint256[](_rewardTokens.length);
        for (uint256 i; i < _rewardTokens.length; ++i) {
            rewardDebts[i] = rewardDebt[computeDebtAccessHash(account, stakeIndex, _rewardTokens[i])];
        }

        return (stake.amount, stake.unlockTimestamp, rewardDebts);
    }

    function computeDebtAccessHash(address account, uint256 stakeIndex, address rewardToken)
        public
        view
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(debtHashBase, account, stakeIndex, rewardToken));
    }

    /**
     * @notice Get the number of reward tokens
     * @return The length of the array
     */
    function rewardTokensCounter() public view returns (uint256) {
        return rewardTokens.length;
    }

    /**
     * @notice Add a reward token
     * @dev Cannot re-add reward tokens once removed
     * @param _rewardToken The address of the reward token
     */
    function addRewardToken(address _rewardToken) external onlyOwner {
        if (isRewardToken[_rewardToken] || accRewardsPerShare[_rewardToken] != 0) revert AlreadyAdded();
        if (address(_rewardToken) == address(0)) revert InvalidAddress();

        rewardTokens.push(_rewardToken);
        isRewardToken[_rewardToken] = true;
        emit RewardTokenAdded(_rewardToken);
    }

    /**
     * @notice View function to see pending reward token on frontend
     * @param account The address of the user
     * @param token The address of the token
     * @return `_user`'s pending reward token
     */
    function pendingRewards(address account, uint256 stakeIndex, address token) external view returns (uint256) {
        if (!isRewardToken[token]) revert InvalidValue();
        uint256 _totalDeposits = totalDeposits;
        uint256 _accRewardTokenPerShare = accRewardsPerShare[token];

        uint256 currRewardBalance = IERC20(token).balanceOf(address(this));
        uint256 rewardBalance = token == address(dragon) ? currRewardBalance - _totalDeposits : currRewardBalance;

        if (rewardBalance != lastRewardBalance[token] && _totalDeposits != 0) {
            uint256 accruedReward = rewardBalance - lastRewardBalance[token];
            _accRewardTokenPerShare += (accruedReward * P) / _totalDeposits;
        }
        return (stakes[account][stakeIndex].amount * _accRewardTokenPerShare) / P
            - rewardDebt[computeDebtAccessHash(account, stakeIndex, token)];
    }

    function claimEarnings(uint256 stakeIndex) external {
        // Add stake out of bounds error
        Stake[] storage accountStakes = stakes[msg.sender];

        uint256 amount = accountStakes[stakeIndex].amount;
        uint256 numberOfRewardTokens = rewardTokens.length;

        for (uint256 i; i < numberOfRewardTokens; ++i) {
            address token = rewardTokens[i];
            _updateAccumulated(token);

            bytes32 rewardDebtHash = computeDebtAccessHash(msg.sender, stakeIndex, token);

            uint256 _accRewardsPerShare = accRewardsPerShare[token];
            uint256 accumulated = (amount * _accRewardsPerShare) / P;
            uint256 pending = accumulated - rewardDebt[rewardDebtHash];
            rewardDebt[rewardDebtHash] = accumulated;

            if (pending != 0) {
                _payout(IERC20(token), pending);
            }
        }
    }

    /*
     * @notice Withdraw Dragon and harvest the rewards
     * @param amount The amount of Dragon to withdraw
     */
    function withdraw(uint256 stakeIndex) external {
        Stake[] storage accountStakes = stakes[msg.sender];

        if (accountStakes[stakeIndex].unlockTimestamp < block.timestamp) revert();

        uint256 amount = accountStakes[stakeIndex].amount;
        uint256 numberOfRewardTokens = rewardTokens.length;

        for (uint256 i; i < numberOfRewardTokens; ++i) {
            address token = rewardTokens[i];
            _updateAccumulated(token);

            bytes32 rewardDebtHash = computeDebtAccessHash(msg.sender, stakeIndex, token);

            uint256 _accRewardsPerShare = accRewardsPerShare[token];
            uint256 pending = (amount * _accRewardsPerShare) / P - rewardDebt[rewardDebtHash];
            delete rewardDebt[rewardDebtHash];

            if (pending != 0) {
                _payout(IERC20(token), pending);
            }
        }

        totalDeposits -= amount;
        // Remove a withdrawn stake
        // Issue assigning the reward debts to an another stake
        //accountStakes[stakeIndex] = accountStakes[accountStakes.length - 1];
        // accountStakes.pop();
        // accountStake.claim = true;
        --stakeCounter[msg.sender];
        _burn(msg.sender, amount);

        dragon.safeTransfer(msg.sender, amount);

        emit Withdraw(msg.sender, amount);
    }

    /**
     * @notice Withdraw without caring about rewards. EMERGENCY ONLY
     */
    function emergencyWithdraw(uint256 stakeIndex) external {
        Stake[] storage accountStakes = stakes[msg.sender];

        if (accountStakes[stakeIndex].unlockTimestamp < block.timestamp) revert();

        uint256 numberOfRewardTokens = rewardTokens.length;
        for (uint256 i; i < numberOfRewardTokens; ++i) {
            delete rewardDebt[computeDebtAccessHash(msg.sender, stakeIndex, rewardTokens[i])];
        }
        uint256 stakedAmount = accountStakes[stakeIndex].amount;
        totalDeposits -= stakedAmount;
        // Remove a withdrawn stake
        accountStakes[stakeIndex] = accountStakes[accountStakes.length - 1];
        accountStakes.pop();
        --stakeCounter[msg.sender];
        _burn(msg.sender, stakedAmount);

        dragon.safeTransfer(msg.sender, stakeIndex);
        emit EmergencyWithdraw(msg.sender, stakeIndex);
    }

    /**
     * @dev Update reward variables
     * Needs to be called before any deposit or withdrawal
     * @param token The address of the reward token
     */
    function _updateAccumulated(address token) private {
        if (!isRewardToken[token]) revert InvalidValue();

        // Gas optimizations
        uint256 _totalDeposits = totalDeposits;
        uint256 _lastRewardBalance = lastRewardBalance[token];

        uint256 balance = IERC20(token).balanceOf(address(this));
        uint256 rewardBalance = token == address(dragon) ? balance - _totalDeposits : balance;

        if (rewardBalance == _lastRewardBalance || _totalDeposits == 0) return;

        accRewardsPerShare[token] += ((rewardBalance - _lastRewardBalance) * P) / _totalDeposits;
        lastRewardBalance[token] = rewardBalance;
    }

    function _payout(IERC20 token, uint256 pending) private {
        uint256 currRewardBalance = token.balanceOf(address(this));
        uint256 rewardBalance = token == dragon ? currRewardBalance - totalDeposits : currRewardBalance;
        uint256 amount = pending > rewardBalance ? rewardBalance : pending;
        lastRewardBalance[address(token)] -= amount;
        token.safeTransfer(msg.sender, amount);
        emit Payout(msg.sender, token, pending);
    }
}
