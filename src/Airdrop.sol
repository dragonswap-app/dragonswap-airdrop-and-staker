pragma solidity 0.8.30;

import {IStaker} from "./interfaces/IStaker.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Initializable, OwnableUpgradeable} from "@openzeppelin/u-contracts/access/OwnableUpgradeable.sol";

contract Airdrop is Initializable, OwnableUpgradeable {
    uint256 public totalDeposited;
    uint256 public penalty = 50_00;
    bool public lock;

    uint256[] public unlocks;
    mapping(uint256 portionId => mapping(address account => uint256 amount)) public portions;

    address public staker;
    address public signer;
    address public treasury;
    address public dragonswapToken;

    uint256 public constant precision = 10_00_00;
    uint256 public constant cleanUpBuffer = 60 days;

    event Deposit(uint256 amount);
    event TimestampAdded(uint256 index, uint256 timestamp);
    event Locked();

    error CleanUpNotAvailable();
    error StakingUnavailableForThisAirdrop();

    function initialize(
        address _dragonswapToken,
        address _staker,
        address _treasury,
        address _signer,
        address initialOwner,
        uint256[] memory timestamps
    ) external {
        dragonswapToken = _dragonswapToken;
        staker = _staker;
        treasury = _treasury;
        signer = _signer;
        for (uint256 i; i < timestamps.length; ++i) {
            unlocks.push(timestamps[i]);
        }
    }

    function lockUp() external onlyOwner {
        lock = true;
        emit Locked();
    }

    function addTimestamp(uint256 timestamp) external onlyOwner {
        uint256 length = unlocks.length;
        if (length > 0 && timestamp <= unlocks[length - 1]) revert();
        unlocks.push(timestamp);
        emit TimestampAdded(length, timestamp);
    }

    function changeTimestamp(uint256 index, uint256 timestamp) external onlyOwner {
        if (index > unlocks.length - 1) revert();
        if (index < unlocks.length - 2 && timestamp > unlocks[index + 1]) revert();
        if (index > 0 && timestamp < unlocks[index - 1]) revert();
        unlocks[index] = timestamp;
    }

    function setPortions(uint256 index, address[] memory accounts, uint256[] memory amounts) external onlyOwner {
        if (lock) revert();
        mapping(address => uint256) storage _portions = portions[index];
        uint256 n = accounts.length;
        if (n == amounts.length) revert();
        for (uint256 i; i < n; ++i) {
            _portions[accounts[i]] = amounts[i];
        }
    }

    function deposit(uint256 amount) external onlyOwner {
        IERC20(dragonswapToken).transferFrom(msg.sender, address(this), amount);
        unchecked {
            totalDeposited += amount;
        }
        emit Deposit(amount);
    }

    function withdraw(bool toWallet, uint256 lockupIndex) external {
        uint256 n = unlocks.length;
        uint256 total;
        for (uint256 i; i < n; ++i) {
            total += portions[i][msg.sender];
            delete portions[i][msg.sender];
        }
        if (toWallet) {
            uint256 penaltyAmount = total * penalty / precision;
            IERC20(dragonswapToken).transfer(msg.sender, total - penaltyAmount);
            IERC20(dragonswapToken).transfer(treasury, penaltyAmount);
        } else {
            if (staker == address(0)) revert StakingUnavailableForThisAirdrop();
            IStaker(staker).stake(msg.sender, total, lockupIndex);
        }
    }

    function cleanUp(address[] calldata accounts) external onlyOwner {
        uint256 total;
        uint256 n = accounts.length;
        uint256 _unlocks = unlocks.length;
        if (block.timestamp < unlocks[_unlocks - 1] + cleanUpBuffer) revert CleanUpNotAvailable();
        for (uint256 i; i < n; ++i) {
            address account = accounts[i];
            for (uint256 j; j < _unlocks; ++j) {
                total += portions[j][account];
                delete portions[j][account];
            }
        }
        IERC20(dragonswapToken).transfer(treasury, total);
    }
}
