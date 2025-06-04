// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract Staker is Ownable {
    using SafeERC20 for IERC20;

    struct Stake {
        uint256 amount;
        uint256 unlockTimestamp;
        bool claimed;
    }

    /// @notice Withdrawal fee for users which haven't locked
    uint256 public fee;
    /// @notice Total amount of deposits
    uint256 public totalDeposits;
    /// @notice Array of tokens that users can be distributed as rewards to the stakers
    address[] public rewardTokens;
    /// @notice Mapping to check if a token is a reward token
    mapping(address token => bool) public isRewardToken;
    /// @notice Last reward balance of `token`
    mapping(address token => uint256) public lastRewardBalance;
    /// @notice Accumulated `token` rewards per share, scaled to `P`
    mapping(address token => uint256) public accRewardsPerShare;
    /// @notice Stakes of each account
    mapping(address account => Stake[]) private stakes;
    /// @notice Reward debt per token per user's stake
    mapping(bytes32 stakeHash => uint256) private rewardDebt;
    /// @notice Dragonswap token address
    IERC20 public immutable dragon;
    /// @notice Lock period length in seconds
    uint256 public immutable lockTimespan;
    /// @notice Base of a `stakeHash` - used to retrieve `rewardDebt``
    bytes32 private immutable debtHashBase = keccak256(abi.encode(block.chainid, address(this)));
    /// @notice The precision of `accRewardsPerShare`
    uint256 private constant accPrecision = 1e18;
    /// @notice The fee precision - bips
    uint256 private constant feePrecision = 1_00_00;
    /// @notice Minimum amount needed to make a deposit
    uint256 private constant minimumDeposit = 100e18;
    /// @notice Maximum amount of stakes allowed per user
    uint256 private constant stakeLimitPerUser = 100;

    /// Events
    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 amount);
    event Payout(address indexed user, IERC20 indexed rewardToken, uint256 amount);
    event RewardTokenAdded(address indexed token);
    event RewardTokenRemoved(address indexed token);
    event Swept(address indexed token, address indexed to, uint256 amount);
    event FeeRedistributed(address indexed user, uint256 amount);
    event FeeSet(uint256 fee);

    /// Errors
    error InvalidAddress();
    error InvalidValue();
    error ZeroAddress();
    error AlreadyAdded();
    error AlreadyClaimed();
    error InvalidStakeIndex();
    error NoBalance();
    error NotPresent();
    error AccountCrossingStakeLimit();
    error StakeLocked();

    constructor(address _owner, address _dragon, uint256 _fee, address[] memory _rewardTokens) Ownable(_owner) {
        // Set the Dragonswap token
        if (_dragon == address(0)) revert InvalidAddress();
        dragon = IERC20(_dragon);

        // Optional
        if (_fee > feePrecision * 9 / 10) revert();
        fee = _fee;
        emit FeeSet(_fee);

        // Add reward tokens
        isRewardToken[_dragon] = true;
        rewardTokens.push(_dragon);
        emit RewardTokenAdded(_dragon);
        for (uint256 i; i < _rewardTokens.length; ++i) {
            address _rewardToken = _rewardTokens[i];
            if (_rewardToken == address(0)) revert InvalidAddress();
            if (isRewardToken[_rewardToken]) continue;
            isRewardToken[_rewardToken] = true;
            rewardTokens.push(_rewardToken);
            emit RewardTokenAdded(_rewardToken);
        }
    }

    /**
     * @notice Function to change the withdrwal fee value.
     * @param _fee New fee value to be set.
     */
    function setFee(uint256 _fee) external onlyOwner {
        if (_fee > feePrecision * 9 / 10) revert();
        fee = _fee;
        emit FeeSet(_fee);
    }

    /**
     * @notice Deposit Dragon in order to receive the reward tokens
     * @param amount The amount of Dragon to deposit
     */
    function stake(address account, uint256 amount, bool locking) external {
        if (account == address(0)) revert ZeroAddress();
        if (amount < minimumDeposit) revert InvalidValue();

        // Calculate accumulation with total sDRG instead of drg
        totalDeposits += amount;

        // Check stake limit
        uint256 numberOfStakesOwnedByAnAccount = userStakeCount(account);
        if (numberOfStakesOwnedByAnAccount == stakeLimitPerUser) revert AccountCrossingStakeLimit();

        // Gas opt
        uint256 numberOfRewardTokens = rewardTokens.length;
        for (uint256 i; i < numberOfRewardTokens; ++i) {
            // Set reward debt
            address token = rewardTokens[i];
            _updateAccumulated(token);

            rewardDebt[computeDebtAccessHash(account, numberOfStakesOwnedByAnAccount, token)] =
                (amount * accRewardsPerShare[token]) / accPrecision;
        }

        // Add the stake
        stakes[account].push(
            Stake({amount: amount, unlockTimestamp: locking ? block.timestamp + lockTimespan : 0, claimed: false})
        );

        // Transfer tokens
        dragon.safeTransferFrom(msg.sender, address(this), amount);
        emit Deposit(msg.sender, amount);
    }

    /**
     * @notice Add a reward token
     * @dev Cannot re-add reward tokens once removed
     * @param _rewardToken The address of the reward token
     */
    function addRewardToken(address _rewardToken) external onlyOwner {
        if (isRewardToken[_rewardToken] || accRewardsPerShare[_rewardToken] != 0) revert AlreadyAdded();
        if (_rewardToken == address(0)) revert InvalidAddress();
        rewardTokens.push(_rewardToken);
        isRewardToken[_rewardToken] = true;
        emit RewardTokenAdded(_rewardToken);
    }

    /**
     * @notice Remove a reward token
     * @param _rewardToken The address of the reward token
     */
    function removeRewardToken(address _rewardToken) external onlyOwner {
        if (!isRewardToken[_rewardToken]) revert NotPresent();
        delete isRewardToken[_rewardToken];
        uint256 numberOfRewardTokens = rewardTokens.length;
        for (uint256 i; i < numberOfRewardTokens; ++i) {
            if (rewardTokens[i] == _rewardToken) {
                rewardTokens[i] = rewardTokens[numberOfRewardTokens - 1];
                rewardTokens.pop();
                break;
            }
        }
        emit RewardTokenRemoved(_rewardToken);
    }

    /**
     * Function to claim earnings from the selection of stakes.
     * @param stakeIndexes is an array of stake indexes to claim earnings from
     * @dev Updates accumulated rewards and reward debts
     */
    function claimEarnings(uint256[] calldata stakeIndexes) external {
        uint256 numberOfStakeIndexes = stakeIndexes.length;
        uint256 stakeCount = userStakeCount(msg.sender);
        Stake[] memory _stakes = stakes[msg.sender];

        for (uint256 i; i < numberOfStakeIndexes; ++i) {
            uint256 stakeIndex = stakeIndexes[i];
            if (stakeIndex >= stakeCount) revert InvalidStakeIndex();
            uint256 amount = _stakes[stakeIndex].amount;
            uint256 numberOfRewardTokens = rewardTokens.length;

            for (uint256 j; j < numberOfRewardTokens; ++j) {
                address token = rewardTokens[j];
                _updateAccumulated(token);

                bytes32 rewardDebtHash = computeDebtAccessHash(msg.sender, stakeIndex, token);

                uint256 _accRewardsPerShare = accRewardsPerShare[token];
                uint256 accumulated = (amount * _accRewardsPerShare) / accPrecision;
                uint256 pending = accumulated - rewardDebt[rewardDebtHash];
                rewardDebt[rewardDebtHash] = accumulated;

                if (pending != 0) {
                    _payout(IERC20(token), pending);
                }
            }
        }
    }

    /*
     * @notice Withdraw Dragon and harvest the rewards
     * @param amount The amount of Dragon to withdraw
     */
    function withdraw(uint256[] calldata stakeIndexes) external {
        uint256 numberOfStakeIndexes = stakeIndexes.length;
        uint256 stakeCount = userStakeCount(msg.sender);
        Stake[] storage _stakes = stakes[msg.sender];

        for (uint256 i; i < numberOfStakeIndexes; ++i) {
            uint256 stakeIndex = stakeIndexes[i];
            if (stakeIndex >= stakeCount) revert InvalidStakeIndex();
            Stake storage _stake = _stakes[stakeIndex];

            if (_stake.claimed) revert AlreadyClaimed();
            if (_stake.unlockTimestamp < block.timestamp) revert StakeLocked();

            uint256 amount = _stake.amount;
            uint256 numberOfRewardTokens = rewardTokens.length;

            for (uint256 j; j < numberOfRewardTokens; ++j) {
                address token = rewardTokens[j];
                _updateAccumulated(token);

                bytes32 rewardDebtHash = computeDebtAccessHash(msg.sender, stakeIndex, token);

                uint256 _accRewardsPerShare = accRewardsPerShare[token];
                uint256 pending = (amount * _accRewardsPerShare) / accPrecision - rewardDebt[rewardDebtHash];
                delete rewardDebt[rewardDebtHash];

                if (pending != 0) {
                    _payout(IERC20(token), pending);
                }
            }

            totalDeposits -= amount;
            _stake.claimed = true;

            // If user hasn't locked, penalty will be applied and redistributed to the active stakers.
            if (_stake.unlockTimestamp == 0) {
                uint256 feeAmount = amount * fee / feePrecision;
                amount -= feeAmount;
                emit FeeRedistributed(msg.sender, feeAmount);
            }

            dragon.safeTransfer(msg.sender, amount);
            emit Withdraw(msg.sender, amount);
        }
    }

    /**
     * @notice Withdraw without caring about rewards. EMERGENCY ONLY
     */
    function emergencyWithdraw(uint256[] calldata stakeIndexes) external {
        uint256 numberOfStakeIndexes = stakeIndexes.length;
        uint256 stakeCount = userStakeCount(msg.sender);
        Stake[] storage _stakes = stakes[msg.sender];

        for (uint256 i; i < numberOfStakeIndexes; ++i) {
            uint256 stakeIndex = stakeIndexes[i];
            if (stakeIndex >= stakeCount) revert InvalidStakeIndex();
            Stake storage _stake = _stakes[stakeIndex];

            if (_stake.claimed) revert AlreadyClaimed();
            if (_stake.unlockTimestamp < block.timestamp) revert StakeLocked();

            uint256 amount = _stake.amount;

            totalDeposits -= amount;
            _stake.claimed = true;

            if (_stake.unlockTimestamp == 0) {
                uint256 feeAmount = amount * fee / feePrecision;
                amount -= feeAmount;
                emit FeeRedistributed(msg.sender, feeAmount);
            }

            dragon.safeTransfer(msg.sender, amount);
            emit EmergencyWithdraw(msg.sender, stakeIndex);
        }
    }

    /**
     * @notice Sweep token to the `to` address
     * @param token The address of the token to sweep
     * @param to The address that will receive `token` balance
     */
    function sweep(IERC20 token, address to) external onlyOwner {
        if (isRewardToken[address(token)]) revert();

        uint256 balance = token.balanceOf(address(this));
        if (token == dragon) {
            unchecked {
                balance -= totalDeposits;
            }
        }
        if (balance == 0) revert();
        token.safeTransfer(to, balance);
        emit Swept(address(token), to, balance);
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
            _accRewardTokenPerShare += (accruedReward * accPrecision) / _totalDeposits;
        }
        return (stakes[account][stakeIndex].amount * _accRewardTokenPerShare) / accPrecision
            - rewardDebt[computeDebtAccessHash(account, stakeIndex, token)];
    }

    /**
     * @notice Function to retrieve stake data for account.
     * @dev Reward debts are returned in order of tokens present in the `rewardTokens` array
     */
    function getAccountStakeData(address account, uint256 stakeIndex)
        external
        view
        returns (uint256, uint256, uint256[] memory rewardDebts)
    {
        if (stakeIndex >= userStakeCount(account)) revert InvalidStakeIndex();
        Stake memory _stake = stakes[account][stakeIndex];
        address[] memory _rewardTokens = rewardTokens;

        rewardDebts = new uint256[](_rewardTokens.length);
        // Retrieve reward debts
        for (uint256 i; i < _rewardTokens.length; ++i) {
            rewardDebts[i] = rewardDebt[computeDebtAccessHash(account, stakeIndex, _rewardTokens[i])];
        }
        return (_stake.amount, _stake.unlockTimestamp, rewardDebts);
    }

    /**
     * @notice Function to compute the hash which helps access the rewardDebt for a certain user stake and token
     */
    function computeDebtAccessHash(address account, uint256 stakeIndex, address rewardToken)
        public
        view
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(debtHashBase, account, stakeIndex, rewardToken));
    }

    /**
     * @notice Get the number of account's stakes
     * @return The length of the array
     */
    function userStakeCount(address account) public view returns (uint256) {
        return stakes[account].length;
    }

    /**
     * @notice Get the number of reward tokens
     * @return The length of the array
     */
    function rewardTokensCounter() public view returns (uint256) {
        return rewardTokens.length;
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

        accRewardsPerShare[token] += ((rewardBalance - _lastRewardBalance) * accPrecision) / _totalDeposits;
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
