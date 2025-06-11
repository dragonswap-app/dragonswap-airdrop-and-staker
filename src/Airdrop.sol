// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IStaker} from "./interfaces/IStaker.sol";

import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {Initializable, OwnableUpgradeable} from "@openzeppelin/u-contracts/access/OwnableUpgradeable.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract Airdrop is Initializable, OwnableUpgradeable {
    using MessageHashUtils for bytes32;
    using SignatureChecker for address;
    using SafeERC20 for IERC20;

    bool public isLocked;
    address public token;
    address public staker;
    address public signer;
    address public treasury;
    uint256 public penaltyWallet;
    uint256 public penaltyStaker;
    uint256 public totalDepositedForDistribution;

    uint256[] public unlocks;
    mapping(uint256 portionId => mapping(address account => uint256 amount)) public portions;

    uint256 public constant precision = 1_00_00;
    uint256 public constant cleanUpBuffer = 60 days;

    /// Events
    event Deposit(uint256 amount);
    event TimestampAdded(uint256 indexed index, uint256 timestamp);
    event Locked();
    event CleanUp(address indexed account);
    event PortionsAssigned(address[] accounts, uint256[] amounts);
    event TimestampChanged(uint256 indexed index, uint256 newTimestamp);
    event WalletWithdrawal(address indexed account, uint256 total, uint256 penalty);
    event StakerWithdrawal(address indexed account, uint256 total, bool indexed locking);

    /// Errors
    error CleanUpNotAvailable();
    error SettingsLocked();
    error AlreadyLocked();
    error TotalZero();
    error ZeroAddress();
    error InvalidTimestamp();
    error ArrayLengthMismatch();
    error InvalidIndex();
    error SignatureInvalid();

    /// @dev Disables addition of new portions, changing amounts and adding new unlock timestamps.
    modifier lock() {
        _isLocked();
        _;
    }

    // Prevent malicious third-parties from initializing the implementation.
    constructor() {
        _disableInitializers();
    }

    /// @notice Function to initialize the airdrop contract.
    function initialize(
        address _token,
        address _staker,
        address _treasury,
        address _signer,
        address initialOwner,
        uint256[] calldata _unlockTimestamps
    ) external initializer {
        // Initialize inheritance.
        __Ownable_init(initialOwner);

        // Validate and assign the values.
        if (_token == address(0)) revert ZeroAddress();
        token = _token;
        if (_signer == address(0)) revert ZeroAddress();
        signer = _signer;
        if (_treasury == address(0)) revert ZeroAddress();
        treasury = _treasury;
        if (_staker == address(0)) revert ZeroAddress();
        staker = _staker;

        // Push timestamps
        uint256 n = _unlockTimestamps.length;
        if (n != 0) unlocks.push(_unlockTimestamps[0]);
        for (uint256 i = 1; i < n; ++i) {
            if (_unlockTimestamps[i] <= _unlockTimestamps[i - 1]) revert InvalidTimestamp();
            unlocks.push(_unlockTimestamps[i]);
        }
    }

    /// @notice Function to lock the contract settings in place.
    /// @dev Once locked, settings cannot be changed and there is no way to unlock the contract.
    function lockUp() external onlyOwner {
        if (isLocked) revert AlreadyLocked();
        isLocked = true;
        emit Locked();
    }

    /// @notice Function to introduce a new timestamp to the unlocks array.
    function addTimestamp(uint256 timestamp) external onlyOwner lock {
        // Gas opt.
        uint256 length = unlocks.length;
        // Ensure the new timestamp is in the future compared to the latest one.
        if (length > 0 && timestamp <= unlocks[length - 1]) revert InvalidTimestamp();
        unlocks.push(timestamp);
        // Length represents timestamp's id in the unlocks array.
        emit TimestampAdded(length, timestamp);
    }

    /// @notice Function to change the value of a certain timestamp.
    /// @dev Leaving this function without a lock lets us shift times if needed. Might change this.
    function changeTimestamp(uint256 index, uint256 timestamp) external onlyOwner {
        // Ensure that the new timestamp value is lower than the next one and greater than the previous one (if they exist).
        if (index > unlocks.length - 1) revert InvalidIndex();
        if (
            (index < unlocks.length - 1 && timestamp >= unlocks[index + 1])
                || (index > 0 && timestamp <= unlocks[index - 1])
        ) revert InvalidTimestamp();
        // Assign the timestamp.
        unlocks[index] = timestamp;
        emit TimestampChanged(index, timestamp);
    }

    /// @notice Assign portions of a determined unlock index for accounts.
    function assignPortions(uint256 index, address[] memory accounts, uint256[] memory amounts)
        external
        onlyOwner
        lock
    {
        // Gas opt.
        mapping(address => uint256) storage _portions = portions[index];
        uint256 n = accounts.length;
        // Ensure array lengths match.
        if (n != amounts.length) revert ArrayLengthMismatch();
        for (uint256 i; i < n; ++i) {
            // Assign the account's portion for the index.
            _portions[accounts[i]] = amounts[i];
        }
        emit PortionsAssigned(accounts, amounts);
    }

    /// @notice Function to deposit airdrop rewards.
    /// @notice Callable by the contract owner.
    function deposit(uint256 amount) external onlyOwner {
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        unchecked {
            totalDepositedForDistribution += amount;
        }
        emit Deposit(amount);
    }

    /// @notice Function to withdraw the airdrop.
    /// @dev Callable by anyone eligible.
    /// @param toWallet describes if user wants to retrieves the airdrop directly to the owned EOA (includes penalty by default) or to the staker contract with a chosen lockup period (can include penalty but doesn't by default).
    /// @param locking determines if user is locking tokens inside the staker contract or not.
    /// @param signature represents an extra layer of safety, a message of approval signed by `signer`.
    function withdraw(bool toWallet, bool locking, bytes calldata signature) external {
        uint256 n = unlocks.length;
        uint256 total;
        for (uint256 i; i < n; ++i) {
            if (block.timestamp > unlocks[i]) {
                total += portions[i][msg.sender];
                delete portions[i][msg.sender];
            }
        }
        // Ensure user has unwithdrawn funds.
        if (total == 0) revert TotalZero();
        // Compute the message hash.
        bytes32 hash =
            keccak256(abi.encode(address(this), block.chainid, msg.sender, toWallet, total)).toEthSignedMessageHash();
        // Ensure signature validity.
        if (!signer.isValidSignatureNow(hash, signature)) revert SignatureInvalid();
        // Make the withdrawal, either to wallet or to the staker contract.
        if (toWallet) {
            // Compute penalty, transfer it to treasury and the rest to the user..
            uint256 penaltyAmount = total * IStaker(staker).fee() / precision;
            if (penaltyAmount != 0) {
                IERC20(token).safeTransfer(IStaker(staker).treasury(), penaltyAmount);
                total -= penaltyAmount;
            }
            IERC20(token).safeTransfer(msg.sender, total);
            emit WalletWithdrawal(msg.sender, total, penaltyAmount);
        } else {
            IERC20(token).approve(staker, total);
            IStaker(staker).stake(msg.sender, total, locking);
            emit StakerWithdrawal(msg.sender, total, locking);
        }
    }

    /// @notice Function to clean up the portions if they remain unclaimed for a `cleanUpBuffer` period of time after the final portion unlock.
    /// @dev Specifying wallets is present as it's needed for the portion removal.
    function cleanUp(address[] calldata accounts) external onlyOwner {
        // Gas opts.
        uint256 n = accounts.length;
        uint256 _unlocks = unlocks.length;
        // Ensure cleanup is available according to the previously described time-lock rule.
        if (block.timestamp < unlocks[_unlocks - 1] + cleanUpBuffer) revert CleanUpNotAvailable();
        uint256 total;
        for (uint256 i; i < n; ++i) {
            address account = accounts[i];
            uint256 _total = total;
            for (uint256 j; j < _unlocks; ++j) {
                // Sum up amounts and delete acquired portions.
                total += portions[j][account];
                delete portions[j][account];
            }
            if (total > _total) emit CleanUp(account);
        }
        // Send tokens to treasury.
        IERC20(token).safeTransfer(treasury, total);
    }

    /// @notice Function to get the amount of unlocks per account.
    function unlocksCounter() external view returns (uint256) {
        return unlocks.length;
    }

    /// @notice Function to revert once contract is locked.
    function _isLocked() private view {
        if (isLocked) revert SettingsLocked();
    }
}
