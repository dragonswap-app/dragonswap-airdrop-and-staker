// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IStaker} from "./interfaces/IStaker.sol";

import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Initializable, OwnableUpgradeable} from "@openzeppelin/u-contracts/access/OwnableUpgradeable.sol";

contract Airdrop is Initializable, OwnableUpgradeable {
    using MessageHashUtils for bytes32;
    using SignatureChecker for address;

    address public staker;
    address public signer;
    address public treasury;
    address public token;
    uint256 public totalDeposited;
    uint256 public penalty;
    bool public lock;
    uint256[] public unlocks;
    mapping(uint256 portionId => mapping(address account => uint256 amount)) public portions;

    uint256 public constant precision = 10_00_00;
    uint256 public constant cleanUpBuffer = 60 days;

    /// Events
    event Deposit(uint256 amount);
    event TimestampAdded(uint256 indexed index, uint256 timestamp);
    event Locked();
    event TimestampChanged(uint256 indexed index, uint256 newTimestamp);
    event WalletWithdrawal(address indexed account, uint256 total, uint256 penalty);
    event StakerWithdrawal(address indexed account, uint256 total, uint256 indexed lockupIndex);

    /// Errors
    error CleanUpNotAvailable();
    error StakingUnavailableForThisAirdrop();
    error SettingsLocked();
    error NotEligibleOrAlreadyClaimed();
    error ZeroAddress();
    error InvalidTimestamp();
    error ArrayLengthMismatch();
    error InvalidIndex();

    modifier locked() {
        _lockCheck();
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
        uint256[] memory timestamps
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
        // Leaving this parameter unset will permanently disable the option the 'withdraw funds to staker contract' for this airdrop.
        staker = _staker;

        // Push timestamps
        uint256 n = timestamps.length;
        if (n != 0) unlocks.push(timestamps[0]);
        for (uint256 i = 1; i < n; ++i) {
            if (timestamps[i] <= timestamps[i - 1]) revert InvalidTimestamp();
            unlocks.push(timestamps[i]);
        }
        // Default value for penalty will be 50%.
        penalty = 50_00;
    }

    /// @notice Function to lock the contract settings in place.
    /// @dev Once locked, settings cannot be changed and there is no way to unlock the contract.
    function lockUp() external onlyOwner {
        lock = true;
        emit Locked();
    }

    /// @notice Function to change the penalty percentage, represented in bps.
    function updatePenalty(uint256 _penalty) external onlyOwner locked {
        if (_penalty > precision) revert();
        penalty = _penalty;
    }

    /// @notice Function to introduce a new timestamp to the unlocks array.
    function addTimestamp(uint256 timestamp) external onlyOwner locked {
        // Gas opt.
        uint256 length = unlocks.length;
        // Ensure the new timestamp is in the future compared to the latest one.
        if (length > 0 && timestamp <= unlocks[length - 1]) revert InvalidTimestamp();
        unlocks.push(timestamp);
        // Length represents timestamp's id in the unlocks array.
        emit TimestampAdded(length, timestamp);
    }

    /// @notice Function to change the value of a certain timestamp.
    function changeTimestamp(uint256 index, uint256 timestamp) external onlyOwner /* add lock? */ {
        // Ensure that the new timestamp value is lower than the next one and greater than the previous one (if they exist).
        if (index > unlocks.length - 1) revert InvalidIndex();
        if (
            (index < unlocks.length - 2 && timestamp > unlocks[index + 1])
                || (index > 0 && timestamp < unlocks[index - 1])
        ) revert InvalidTimestamp();
        // Assign the timestamp.
        unlocks[index] = timestamp;
        emit TimestampChanged(index, timestamp);
    }

    /// @notice Assign portions of a determined unlock index for accounts.
    function assignPortions(uint256 index, address[] memory accounts, uint256[] memory amounts)
        external
        onlyOwner
        locked
    {
        // Gas opt.
        mapping(address => uint256) storage _portions = portions[index];
        uint256 n = accounts.length;
        // Ensure array lengths match.
        if (n == amounts.length) revert ArrayLengthMismatch();
        for (uint256 i; i < n; ++i) {
            // Assign the account's portion for the index.
            _portions[accounts[i]] = amounts[i];
        }
    }

    /// @notice Function to deposit airdrop rewards.
    /// @notice Callable by the contract owner.
    function deposit(uint256 amount) external onlyOwner {
        IERC20(token).transferFrom(msg.sender, address(this), amount);
        unchecked {
            totalDeposited += amount;
        }
        emit Deposit(amount);
    }

    /// @notice Function to withdraw the airdrop.
    /// @dev Callable by anyone eligible.
    /// @param toWallet describes if user wants to retrieves the airdrop directly to the owned EOA (includes penalty) or to the staker contract with a chosen lockup period.
    /// @param lockupIndex is an index of a lockup period. This argument is required only if user chooses 'withdrawal to staker' (`toWallet` == false) option when calling this function.
    /// @param signature represents an extra layer of safety, a message of approval signed by `signer`.
    function withdraw(bool toWallet, uint256 lockupIndex, bytes calldata signature) external {
        uint256 n = unlocks.length;
        uint256 total;
        for (uint256 i; i < n; ++i) {
            total += portions[i][msg.sender];
            delete portions[i][msg.sender];
        }
        // Ensure user has unwithdrawn funds.
        if (total == 0) revert NotEligibleOrAlreadyClaimed();
        // Compute the message hash.
        bytes32 hash =
            keccak256(abi.encode(address(this), block.chainid, msg.sender, toWallet, total)).toEthSignedMessageHash();
        // Ensure signature validity.
        if (signer.isValidSignatureNow(hash, signature)) revert();
        // Make the withdrawal, either to wallet (fees applied) or to the staker contract (if available for the present airdrop).
        if (toWallet) {
            // Compute penalty, transfer it to treasury and the rest to the user..
            uint256 penaltyAmount = total * penalty / precision;
            IERC20(token).transfer(msg.sender, total - penaltyAmount);
            IERC20(token).transfer(treasury, penaltyAmount);
            emit WalletWithdrawal(msg.sender, total, penaltyAmount);
        } else {
            // Check if staker is set.
            if (staker == address(0)) revert StakingUnavailableForThisAirdrop();
            // Forward funds to the staker, with information about the chosen lockup period.
            IStaker(staker).stake(msg.sender, total, lockupIndex);
            emit StakerWithdrawal(msg.sender, total, lockupIndex);
        }
    }

    /// @notice Function to clean up the portions if they remain unclaimed for a `cleanUpBuffer` period of time after the final portion unlock.
    function cleanUp(address[] calldata accounts) external onlyOwner {
        // Gas opts.
        uint256 n = accounts.length;
        uint256 _unlocks = unlocks.length;
        // Ensure cleanup is available according to the previously described time-lock rule.
        if (block.timestamp < unlocks[_unlocks - 1] + cleanUpBuffer) revert CleanUpNotAvailable();
        uint256 total;
        for (uint256 i; i < n; ++i) {
            address account = accounts[i];
            for (uint256 j; j < _unlocks; ++j) {
                // Sum up amounts and delete acquired portions.
                total += portions[j][account];
                delete portions[j][account];
            }
        }
        // Send tokens to treasury.
        IERC20(token).transfer(treasury, total);
    }

    /// @notice Function to revert once contract is locked.
    function _lockCheck() private view {
        if (lock) revert SettingsLocked();
    }
}
