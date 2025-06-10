// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {Staker} from "src/Staker.sol";
import {LogUtils} from "test/utils/LogUtils.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/* TODO: Convert startPrank to prank where applicable */
/* TODO: Clean up the comments                        */
/* TODO: Check precision                              */
/* TODO: Check signatures                             */
/* TODO: Check reentrancy                             */
contract StakerFullTest is Test {
    address public alice = address(0xA11CE);
    address public bob = address(0xB0B);
    address public charlie = address(0xCACCE);

    uint256 public constant ALICE_STAKE = 10_000 * 10 ** 18;
    uint256 public constant BOB_STAKE = 20_000 * 10 ** 18;
    uint256 public constant CHARLIE_STAKE = 30_000 * 10 ** 18;
    uint256 public constant MIN_DEPOSIT = 100 * 10 ** 18;

    uint256 constant PRECISION = 1_00_00;
    uint256 constant DEFAULT_FEE = 25_00; // 25% fee
    uint256 constant LOCK_TIMESPAN = 30 days;

    Staker public staker;
    ERC20Mock public dragon;
    ERC20Mock public rewardToken1;
    ERC20Mock public rewardToken2;

    address public owner = makeAddr("owner");
    address public treasury = makeAddr("treasury");

    /* TEST: setUp - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -/
     * Pretend to be the owner address, create mock tokens and a staker, - - - -/
     * set up reward tokens and initialize the staker contract - - - - - - - - */
    function setUp() public {
        LogUtils.logDebug("Starting prank as owner");
        vm.startPrank(owner);

        LogUtils.logInfo("Instantiating mock tokens");
        dragon = new ERC20Mock();
        rewardToken1 = new ERC20Mock();
        rewardToken2 = new ERC20Mock();

        LogUtils.logInfo("Setting up reward tokens array");
        address[] memory rewardTokens = new address[](1);
        rewardTokens[0] = address(rewardToken1);

        LogUtils.logInfo("Instantiating Staker contract with following values:");
        LogUtils.logInfo(string.concat("owner:\t\t", vm.toString(owner)));
        LogUtils.logInfo(string.concat("dragon addr:\t", vm.toString(address(dragon))));
        LogUtils.logInfo(string.concat("treasury addr:\t", vm.toString(treasury)));
        LogUtils.logInfo(string.concat("default fee:\t", vm.toString(DEFAULT_FEE)));
        LogUtils.logInfo(string.concat("reward token 1:\t", vm.toString(address(rewardToken1))));

        staker = new Staker(owner, address(dragon), treasury, DEFAULT_FEE, rewardTokens);

        LogUtils.logInfo("Stopping prank as owner");
        vm.stopPrank();

        LogUtils.logInfo("Minting tokens to test users");
        dragon.mint(alice, ALICE_STAKE * 10);
        dragon.mint(bob, BOB_STAKE * 10);
        dragon.mint(charlie, CHARLIE_STAKE * 10);

        LogUtils.logInfo("Setting up approvals");
        vm.prank(alice);
        dragon.approve(address(staker), type(uint256).max);
        vm.prank(bob);
        dragon.approve(address(staker), type(uint256).max);
        vm.prank(charlie);
        dragon.approve(address(staker), type(uint256).max);
    }

    /* TEST: test_Initialize - - - - - - - - - - - - - - - - - - - - - - - - - -/
     * Asserts the validity of values after instantiation- - - - - - - - - - - */
    function test_Initialize() public view {
        LogUtils.logDebug("Starting initialization assertion test");
        assertEq(address(staker.dragon()), address(dragon));
        assertEq(staker.treasury(), treasury);
        assertEq(staker.fee(), DEFAULT_FEE);
        assertEq(staker.owner(), owner);
        assertEq(staker.lockTimespan(), LOCK_TIMESPAN);
        assertEq(staker.totalDeposits(), 0);
        assertEq(staker.rewardTokensCounter(), 2); // dragon + rewardToken1
        assertTrue(staker.isRewardToken(address(dragon)));
        assertTrue(staker.isRewardToken(address(rewardToken1)));
        assertEq(staker.rewardTokens(0), address(dragon));
        assertEq(staker.rewardTokens(1), address(rewardToken1));
    }

    /* TEST: test_SetTreasury - - - - - - - - - - - - - - - - - - - - - - - - - /
     * Tests the setTreasury functionality - - - - - - - - - - - - - - - - - - */
    function test_SetTreasury() public {
        LogUtils.logDebug("Testing setTreasury functionality");

        vm.startPrank(owner);

        address newTreasury = makeAddr("newTreasury");

        vm.expectEmit();
        emit Staker.TreasurySet(newTreasury);
        staker.setTreasury(newTreasury);

        assertEq(staker.treasury(), newTreasury);

        vm.stopPrank();
    }

    /* TEST: test_SetTreasury_RevertWhenNotOwner - - - - - - - - - - - - - - - -/
     * Tests that only owner can set treasury - - - - - - - - - - - - - - - - */
    function test_SetTreasury_RevertWhenNotOwner() public {
        LogUtils.logDebug("Testing setTreasury revert when not owner");

        vm.startPrank(alice);

        address newTreasury = makeAddr("newTreasury");

        vm.expectRevert();
        staker.setTreasury(newTreasury);

        vm.stopPrank();
    }

    /* TEST: test_SetTreasury_RevertWhenZeroAddress - - - - - - - - - - - - - - /
     * Tests that treasury cannot be set to zero address - - - - - - - - - - - */
    function test_SetTreasury_RevertWhenZeroAddress() public {
        LogUtils.logDebug("Testing setTreasury revert when zero address");

        vm.startPrank(owner);

        vm.expectRevert(Staker.InvalidAddress.selector);
        staker.setTreasury(address(0));

        vm.stopPrank();
    }

    /* TEST: test_SetFee - - - - - - - - - - - - - - - - - - - - - - - - - - - -/
     * Tests the setFee functionality - - - - - - - - - - - - - - - - - - - - -*/
    function test_SetFee() public {
        LogUtils.logDebug("Testing setFee functionality");

        vm.startPrank(owner);

        uint256 newFee = 10_00; // 10%

        vm.expectEmit();
        emit Staker.FeeSet(newFee);
        staker.setFee(newFee);

        assertEq(staker.fee(), newFee);

        vm.stopPrank();
    }

    /* TEST: test_SetFee_RevertWhenNotOwner - - - - - - - - - - - - - - - - - - /
     * Tests that only owner can set fee - - - - - - - - - - - - - - - - - - - */
    function test_SetFee_RevertWhenNotOwner() public {
        LogUtils.logDebug("Testing setFee revert when not owner");

        vm.startPrank(alice);

        vm.expectRevert();
        staker.setFee(10_00);

        vm.stopPrank();
    }

    /* TEST: test_SetFee_RevertWhenTooHigh - - - - - - - - - - - - - - - - - - -/
     * Tests that fee cannot be set above 90% - - - - - - - - - - - - - - - - */
    function test_SetFee_RevertWhenTooHigh() public {
        LogUtils.logDebug("Testing setFee revert when fee too high");

        vm.startPrank(owner);

        uint256 invalidFee = 91_00; // 91%

        vm.expectRevert(Staker.InvalidValue.selector);
        staker.setFee(invalidFee);

        vm.stopPrank();
    }

    /* TEST: test_Stake_Success - - - - - - - - - - - - - - - - - - - - - - - - /
     * Tests successful staking without locking - - - - - - - - - - - - - - - -*/
    function test_Stake_Success() public {
        LogUtils.logDebug("Testing stake functionality");

        uint256 initialBalance = dragon.balanceOf(alice);
        uint256 initialTotalDeposits = staker.totalDeposits();

        vm.prank(alice);
        vm.expectEmit();
        emit Staker.Deposit(alice, alice, ALICE_STAKE, false);
        staker.stake(alice, ALICE_STAKE, false);

        assertEq(dragon.balanceOf(alice), initialBalance - ALICE_STAKE);
        assertEq(dragon.balanceOf(address(staker)), ALICE_STAKE);
        assertEq(staker.totalDeposits(), initialTotalDeposits + ALICE_STAKE);
        assertEq(staker.userStakeCount(alice), 1);

        // Check stake details
        (uint256 amount, uint256 unlockTimestamp,) = staker.getAccountStakeData(alice, 0);
        assertEq(amount, ALICE_STAKE);
        assertEq(unlockTimestamp, 0); // Not locked
    }

    /* TEST: test_Stake_WithLocking_Success - - - - - - - - - - - - - - - - - - /
     * Tests successful staking with locking - - - - - - - - - - - - - - - - - */
    function test_Stake_WithLocking_Success() public {
        LogUtils.logDebug("Testing stake with locking functionality");

        vm.prank(alice);
        vm.expectEmit();
        emit Staker.Deposit(alice, alice, ALICE_STAKE, true);
        staker.stake(alice, ALICE_STAKE, true);

        // Check stake details
        (uint256 amount, uint256 unlockTimestamp,) = staker.getAccountStakeData(alice, 0);
        assertEq(amount, ALICE_STAKE);
        assertEq(unlockTimestamp, block.timestamp + LOCK_TIMESPAN);
    }

    /* TEST: test_Stake_ForAnotherAccount_Success - - - - - - - - - - - - - - - /
     * Tests staking on behalf of another account - - - - - - - - - - - - - - -*/
    function test_Stake_ForAnotherAccount_Success() public {
        LogUtils.logDebug("Testing stake for another account");

        vm.prank(alice);
        vm.expectEmit();
        emit Staker.Deposit(alice, bob, ALICE_STAKE, false);
        staker.stake(bob, ALICE_STAKE, false);

        assertEq(staker.userStakeCount(bob), 1);
        (uint256 amount,,) = staker.getAccountStakeData(bob, 0);
        assertEq(amount, ALICE_STAKE);
    }

    /* TEST: test_Stake_RevertWhenZeroAddress - - - - - - - - - - - - - - - - - /
     * Tests that staking reverts for zero address account - - - - - - - - - -*/
    function test_Stake_RevertWhenZeroAddress() public {
        LogUtils.logDebug("Testing stake revert when zero address");

        vm.prank(alice);
        vm.expectRevert(Staker.ZeroAddress.selector);
        staker.stake(address(0), ALICE_STAKE, false);
    }

    /* TEST: test_Stake_RevertWhenBelowMinimum - - - - - - - - - - - - - - - - -/
     * Tests that staking reverts when amount is below minimum - - - - - - - - */
    function test_Stake_RevertWhenBelowMinimum() public {
        LogUtils.logDebug("Testing stake revert when below minimum");

        vm.prank(alice);
        vm.expectRevert(Staker.InvalidValue.selector);
        staker.stake(alice, MIN_DEPOSIT - 1, false);
    }

    /* TEST: test_LockStake_Success - - - - - - - - - - - - - - - - - - - - - - /
     * Tests locking an unlocked stake - - - - - - - - - - - - - - - - - - - - */
    function test_LockStake_Success() public {
        LogUtils.logDebug("Testing lockStake functionality");

        // First stake without locking
        vm.prank(alice);
        staker.stake(alice, ALICE_STAKE, false);

        // Then lock it
        vm.prank(alice);
        vm.expectEmit();
        emit Staker.StakeLocked(alice, 0);
        staker.lockStake(0);

        // Verify it's locked
        (, uint256 unlockTimestamp,) = staker.getAccountStakeData(alice, 0);
        assertEq(unlockTimestamp, block.timestamp + LOCK_TIMESPAN);
    }

    /* TEST: test_LockStake_RevertWhenInvalidIndex - - - - - - - - - - - - - - -/
     * Tests that lockStake reverts with invalid index - - - - - - - - - - - - */
    function test_LockStake_RevertWhenInvalidIndex() public {
        LogUtils.logDebug("Testing lockStake revert when invalid index");

        vm.prank(alice);
        vm.expectRevert(Staker.InvalidValue.selector);
        staker.lockStake(0); // No stakes yet
    }

    /* TEST: test_LockStake_RevertWhenAlreadyLocked - - - - - - - - - - - - - - /
     * Tests that lockStake reverts when stake is already locked - - - - - - - */
    function test_LockStake_RevertWhenAlreadyLocked() public {
        LogUtils.logDebug("Testing lockStake revert when already locked");

        // Stake with locking
        vm.prank(alice);
        staker.stake(alice, ALICE_STAKE, true);

        // Try to lock again
        vm.prank(alice);
        vm.expectRevert();
        staker.lockStake(0);
    }

    /* TEST: test_AddRewardToken_Success - - - - - - - - - - - - - - - - - - - -/
     * Tests adding a new reward token - - - - - - - - - - - - - - - - - - - - */
    function test_AddRewardToken_Success() public {
        LogUtils.logDebug("Testing addRewardToken functionality");

        vm.startPrank(owner);

        vm.expectEmit();
        emit Staker.RewardTokenAdded(address(rewardToken2));
        staker.addRewardToken(address(rewardToken2));

        assertTrue(staker.isRewardToken(address(rewardToken2)));
        assertEq(staker.rewardTokensCounter(), 3); // dragon + rewardToken1 + rewardToken2
        assertEq(staker.rewardTokens(2), address(rewardToken2));

        vm.stopPrank();
    }

    /* TEST: test_AddRewardToken_RevertWhenNotOwner - - - - - - - - - - - - - - /
     * Tests that only owner can add reward tokens - - - - - - - - - - - - - - */
    function test_AddRewardToken_RevertWhenNotOwner() public {
        LogUtils.logDebug("Testing addRewardToken revert when not owner");

        vm.prank(alice);
        vm.expectRevert();
        staker.addRewardToken(address(rewardToken2));
    }

    /* TEST: test_AddRewardToken_RevertWhenAlreadyAdded - - - - - - - - - - - - /
     * Tests that reward tokens cannot be added twice - - - - - - - - - - - - -*/
    function test_AddRewardToken_RevertWhenAlreadyAdded() public {
        LogUtils.logDebug("Testing addRewardToken revert when already added");

        vm.startPrank(owner);

        vm.expectRevert(Staker.AlreadyAdded.selector);
        staker.addRewardToken(address(dragon)); // Already added in constructor

        vm.stopPrank();
    }

    /* TEST: test_AddRewardToken_RevertWhenZeroAddress - - - - - - - - - - - - -/
     * Tests that zero address cannot be added as reward token - - - - - - - - */
    function test_AddRewardToken_RevertWhenZeroAddress() public {
        LogUtils.logDebug("Testing addRewardToken revert when zero address");

        vm.startPrank(owner);

        vm.expectRevert(Staker.InvalidAddress.selector);
        staker.addRewardToken(address(0));

        vm.stopPrank();
    }

    /* TEST: test_RemoveRewardToken_Success - - - - - - - - - - - - - - - - - - /
     * Tests removing a reward token - - - - - - - - - - - - - - - - - - - - - */
    function test_RemoveRewardToken_Success() public {
        LogUtils.logDebug("Testing removeRewardToken functionality");

        vm.startPrank(owner);

        // First add rewardToken2
        staker.addRewardToken(address(rewardToken2));
        uint256 countBefore = staker.rewardTokensCounter();

        vm.expectEmit();
        emit Staker.RewardTokenRemoved(address(rewardToken1));
        staker.removeRewardToken(address(rewardToken1));

        assertFalse(staker.isRewardToken(address(rewardToken1)));
        assertEq(staker.rewardTokensCounter(), countBefore - 1);

        vm.stopPrank();
    }

    /* TEST: test_RemoveRewardToken_RevertWhenNotOwner - - - - - - - - - - - - -/
     * Tests that only owner can remove reward tokens - - - - - - - - - - - - -*/
    function test_RemoveRewardToken_RevertWhenNotOwner() public {
        LogUtils.logDebug("Testing removeRewardToken revert when not owner");

        vm.prank(alice);
        vm.expectRevert();
        staker.removeRewardToken(address(rewardToken1));
    }

    /* TEST: test_RemoveRewardToken_RevertWhenNotPresent - - - - - - - - - - - -/
     * Tests that non-existent tokens cannot be removed - - - - - - - - - - - -*/
    function test_RemoveRewardToken_RevertWhenNotPresent() public {
        LogUtils.logDebug("Testing removeRewardToken revert when not present");

        vm.startPrank(owner);

        vm.expectRevert(Staker.NotPresent.selector);
        staker.removeRewardToken(address(rewardToken2)); // Not added yet

        vm.stopPrank();
    }

    /* TEST: test_ClaimEarnings_Success - - - - - - - - - - - - - - - - - - - - /
     * Tests claiming earnings from stakes - - - - - - - - - - - - - - - - - - */
    function test_ClaimEarnings_Success() public {
        LogUtils.logDebug("Testing claimEarnings functionality");

        // Setup: Alice stakes
        vm.prank(alice);
        staker.stake(alice, ALICE_STAKE, false);

        // Send reward tokens to staker
        uint256 rewardAmount = 1000 * 10 ** 18;
        rewardToken1.mint(address(staker), rewardAmount);

        // Claim earnings
        uint256[] memory stakeIndexes = new uint256[](1);
        stakeIndexes[0] = 0;

        uint256 aliceBalanceBefore = rewardToken1.balanceOf(alice);

        vm.prank(alice);
        vm.expectEmit();
        emit Staker.Payout(alice, rewardToken1, rewardAmount);
        staker.claimEarnings(stakeIndexes);

        assertEq(rewardToken1.balanceOf(alice), aliceBalanceBefore + rewardAmount);
    }

    /* TEST: test_ClaimEarnings_MultipleStakes - - - - - - - - - - - - - - - - -/
     * Tests claiming earnings from multiple stakes - - - - - - - - - - - - - -*/
    function test_ClaimEarnings_MultipleStakes() public {
        LogUtils.logDebug("Testing claimEarnings with multiple stakes");

        // Alice makes two stakes
        vm.startPrank(alice);
        staker.stake(alice, ALICE_STAKE, false);
        staker.stake(alice, ALICE_STAKE, false);
        vm.stopPrank();

        // Send reward tokens
        uint256 rewardAmount = 2000 * 10 ** 18;
        rewardToken1.mint(address(staker), rewardAmount);

        // Claim from both stakes
        uint256[] memory stakeIndexes = new uint256[](2);
        stakeIndexes[0] = 0;
        stakeIndexes[1] = 1;

        vm.prank(alice);
        staker.claimEarnings(stakeIndexes);

        // Each stake should get half the rewards
        assertEq(rewardToken1.balanceOf(alice), rewardAmount);
    }

    /* TEST: test_ClaimEarnings_RevertWhenInvalidIndex - - - - - - - - - - - - -/
     * Tests that claiming reverts with invalid stake index - - - - - - - - - -*/
    function test_ClaimEarnings_RevertWhenInvalidIndex() public {
        LogUtils.logDebug("Testing claimEarnings revert when invalid index");

        uint256[] memory stakeIndexes = new uint256[](1);
        stakeIndexes[0] = 0; // No stakes yet

        vm.prank(alice);
        vm.expectRevert(Staker.InvalidStakeIndex.selector);
        staker.claimEarnings(stakeIndexes);
    }

    /* TEST: test_Withdraw_Success_NoLock - - - - - - - - - - - - - - - - - - - /
     * Tests withdrawing an unlocked stake with fee - - - - - - - - - - - - - */
    function test_Withdraw_Success_NoLock() public {
        LogUtils.logDebug("Testing withdraw functionality for unlocked stake");

        // Alice stakes without locking
        vm.prank(alice);
        staker.stake(alice, ALICE_STAKE, false);

        // Send some rewards
        uint256 rewardAmount = 1000 * 10 ** 18;
        rewardToken1.mint(address(staker), rewardAmount);

        uint256[] memory stakeIndexes = new uint256[](1);
        stakeIndexes[0] = 0;

        uint256 expectedFee = (ALICE_STAKE * DEFAULT_FEE) / PRECISION;
        uint256 expectedReturn = ALICE_STAKE - expectedFee;

        uint256 treasuryBalanceBefore = dragon.balanceOf(treasury);
        uint256 aliceBalanceBefore = dragon.balanceOf(alice);

        vm.prank(alice);
        // The contract emits Payout first, then Withdraw
        vm.expectEmit();
        emit Staker.Payout(alice, rewardToken1, rewardAmount);
        vm.expectEmit();
        emit Staker.Withdraw(alice, 0, expectedFee);
        staker.withdraw(stakeIndexes);

        // Check balances
        assertEq(dragon.balanceOf(alice), aliceBalanceBefore + expectedReturn);
        assertEq(dragon.balanceOf(treasury), treasuryBalanceBefore + expectedFee);
        assertEq(rewardToken1.balanceOf(alice), rewardAmount);
        assertEq(staker.totalDeposits(), 0);

        // Check stake is claimed
        (,, uint256[] memory rewardDebts) = staker.getAccountStakeData(alice, 0);
        assertTrue(rewardDebts.length > 0); // Stake still exists but is claimed
    }

    /* TEST: test_Withdraw_Success_WithLock - - - - - - - - - - - - - - - - - - /
     * Tests withdrawing a locked stake after unlock period - - - - - - - - - -*/
    function test_Withdraw_Success_WithLock() public {
        LogUtils.logDebug("Testing withdraw functionality for locked stake");

        // Alice stakes with locking
        vm.prank(alice);
        staker.stake(alice, ALICE_STAKE, true);

        // Wait for unlock period
        vm.warp(block.timestamp + LOCK_TIMESPAN + 1);

        uint256[] memory stakeIndexes = new uint256[](1);
        stakeIndexes[0] = 0;

        uint256 aliceBalanceBefore = dragon.balanceOf(alice);

        vm.prank(alice);
        staker.withdraw(stakeIndexes);

        // No fee for locked stakes
        assertEq(dragon.balanceOf(alice), aliceBalanceBefore + ALICE_STAKE);
        assertEq(dragon.balanceOf(treasury), 0);
    }

    /* TEST: test_Withdraw_RevertWhenAlreadyClaimed - - - - - - - - - - - - - -/
     * Tests that claimed stakes cannot be withdrawn again - - - - - - - - - - */
    function test_Withdraw_RevertWhenAlreadyClaimed() public {
        LogUtils.logDebug("Testing withdraw revert when already claimed");

        vm.prank(alice);
        staker.stake(alice, ALICE_STAKE, false);

        uint256[] memory stakeIndexes = new uint256[](1);
        stakeIndexes[0] = 0;

        vm.prank(alice);
        staker.withdraw(stakeIndexes);

        // Try to withdraw again
        vm.prank(alice);
        vm.expectRevert(Staker.AlreadyClaimed.selector);
        staker.withdraw(stakeIndexes);
    }

    /* TEST: test_Withdraw_RevertWhenStillLocked - - - - - - - - - - - - - - - -/
     * Tests that locked stakes cannot be withdrawn before unlock - - - - - - -*/
    function test_Withdraw_RevertWhenStillLocked() public {
        LogUtils.logDebug("Testing withdraw revert when still locked");

        vm.prank(alice);
        staker.stake(alice, ALICE_STAKE, true);

        uint256[] memory stakeIndexes = new uint256[](1);
        stakeIndexes[0] = 0;

        vm.prank(alice);
        vm.expectRevert(Staker.StakeIsLocked.selector);
        staker.withdraw(stakeIndexes);
    }

    /* TEST: test_EmergencyWithdraw_Success - - - - - - - - - - - - - - - - - - /
     * Tests emergency withdrawal without rewards - - - - - - - - - - - - - - -*/
    function test_EmergencyWithdraw_Success() public {
        LogUtils.logDebug("Testing emergencyWithdraw functionality");

        // Alice stakes without locking
        vm.prank(alice);
        staker.stake(alice, ALICE_STAKE, false);

        // Send rewards but don't claim them
        rewardToken1.mint(address(staker), 1000 * 10 ** 18);

        uint256[] memory stakeIndexes = new uint256[](1);
        stakeIndexes[0] = 0;

        uint256 expectedFee = (ALICE_STAKE * DEFAULT_FEE) / PRECISION;
        uint256 expectedReturn = ALICE_STAKE - expectedFee;

        uint256 aliceBalanceBefore = dragon.balanceOf(alice);
        uint256 aliceRewardBalanceBefore = rewardToken1.balanceOf(alice);

        vm.prank(alice);
        vm.expectEmit();
        emit Staker.EmergencyWithdraw(alice, 0, expectedFee);
        staker.emergencyWithdraw(stakeIndexes);

        // Check only principal was withdrawn, no rewards
        assertEq(dragon.balanceOf(alice), aliceBalanceBefore + expectedReturn);
        assertEq(rewardToken1.balanceOf(alice), aliceRewardBalanceBefore); // No rewards claimed
    }

    /* TEST: test_EmergencyWithdraw_RevertWhenAlreadyClaimed - - - - - - - - - /
     * Tests that emergency withdraw reverts for claimed stakes - - - - - - - -*/
    function test_EmergencyWithdraw_RevertWhenAlreadyClaimed() public {
        LogUtils.logDebug("Testing emergencyWithdraw revert when already claimed");

        vm.prank(alice);
        staker.stake(alice, ALICE_STAKE, false);

        uint256[] memory stakeIndexes = new uint256[](1);
        stakeIndexes[0] = 0;

        vm.prank(alice);
        staker.withdraw(stakeIndexes);

        vm.prank(alice);
        vm.expectRevert(Staker.AlreadyClaimed.selector);
        staker.emergencyWithdraw(stakeIndexes);
    }

    /* TEST: test_Sweep_Success - - - - - - - - - - - - - - - - - - - - - - - - /
     * Tests sweeping non-reward tokens - - - - - - - - - - - - - - - - - - - -*/
    function test_Sweep_Success() public {
        LogUtils.logDebug("Testing sweep functionality");

        // Create a non-reward token
        ERC20Mock nonRewardToken = new ERC20Mock();
        uint256 sweepAmount = 5000 * 10 ** 18;
        nonRewardToken.mint(address(staker), sweepAmount);

        address recipient = makeAddr("recipient");

        vm.startPrank(owner);
        vm.expectEmit();
        emit Staker.Swept(address(nonRewardToken), recipient, sweepAmount);
        staker.sweep(IERC20(address(nonRewardToken)), recipient);
        vm.stopPrank();

        assertEq(nonRewardToken.balanceOf(recipient), sweepAmount);
        assertEq(nonRewardToken.balanceOf(address(staker)), 0);
    }

    /* TEST: test_Sweep_DragonToken_RevertWhenRewardToken - - - - - - - - - - - /
     * Tests that dragon token cannot be swept as it's a reward token - - - - */
    function test_Sweep_DragonToken_RevertWhenRewardToken() public {
        LogUtils.logDebug("Testing sweep dragon token reverts");

        // Alice stakes
        vm.prank(alice);
        staker.stake(alice, ALICE_STAKE, false);

        // Send extra dragon tokens directly to staker
        uint256 excessAmount = 1000 * 10 ** 18;
        dragon.mint(address(staker), excessAmount);

        address recipient = makeAddr("recipient");

        // Dragon is a reward token, so sweep should revert
        vm.startPrank(owner);
        vm.expectRevert();
        staker.sweep(IERC20(address(dragon)), recipient);
        vm.stopPrank();

        // Verify tokens remain in staker
        assertEq(dragon.balanceOf(address(staker)), ALICE_STAKE + excessAmount);
    }

    /* TEST: test_Sweep_RevertWhenNotOwner - - - - - - - - - - - - - - - - - - -/
     * Tests that only owner can sweep - - - - - - - - - - - - - - - - - - - - */
    function test_Sweep_RevertWhenNotOwner() public {
        LogUtils.logDebug("Testing sweep revert when not owner");

        ERC20Mock nonRewardToken = new ERC20Mock();
        nonRewardToken.mint(address(staker), 1000 * 10 ** 18);

        vm.prank(alice);
        vm.expectRevert();
        staker.sweep(IERC20(address(nonRewardToken)), alice);
    }

    /* TEST: test_Sweep_RevertWhenRewardToken - - - - - - - - - - - - - - - - - /
     * Tests that reward tokens cannot be swept - - - - - - - - - - - - - - - -*/
    function test_Sweep_RevertWhenRewardToken() public {
        LogUtils.logDebug("Testing sweep revert when reward token");

        vm.startPrank(owner);
        vm.expectRevert();
        staker.sweep(IERC20(address(rewardToken1)), owner);
        vm.stopPrank();
    }

    /* TEST: test_Sweep_RevertWhenNoBalance - - - - - - - - - - - - - - - - - - /
     * Tests that sweep reverts when no balance to sweep - - - - - - - - - - -*/
    function test_Sweep_RevertWhenNoBalance() public {
        LogUtils.logDebug("Testing sweep revert when no balance");

        ERC20Mock nonRewardToken = new ERC20Mock();

        vm.startPrank(owner);
        vm.expectRevert();
        staker.sweep(IERC20(address(nonRewardToken)), owner);
        vm.stopPrank();
    }

    /* TEST: test_PendingRewards - - - - - - - - - - - - - - - - - - - - - - - -/
     * Tests the pendingRewards view function - - - - - - - - - - - - - - - - -*/
    function test_PendingRewards() public {
        LogUtils.logDebug("Testing pendingRewards view function");

        // Alice stakes
        vm.prank(alice);
        staker.stake(alice, ALICE_STAKE, false);

        // Send reward tokens
        uint256 rewardAmount = 1000 * 10 ** 18;
        rewardToken1.mint(address(staker), rewardAmount);

        // Check pending rewards
        uint256 pending = staker.pendingRewards(alice, 0, address(rewardToken1));
        assertEq(pending, rewardAmount);

        // Bob stakes
        vm.prank(bob);
        staker.stake(bob, BOB_STAKE, false);

        // Send more rewards
        rewardToken1.mint(address(staker), rewardAmount);

        // Check pending rewards are distributed proportionally
        uint256 alicePending = staker.pendingRewards(alice, 0, address(rewardToken1));
        uint256 bobPending = staker.pendingRewards(bob, 0, address(rewardToken1));

        // Alice should have original rewards plus her share of new rewards
        // Using the same precision as the contract (accPrecision = 1e18)
        uint256 totalStake = ALICE_STAKE + BOB_STAKE;
        uint256 accPrecision = 1e18;
        uint256 aliceShare = (rewardAmount * accPrecision / totalStake * ALICE_STAKE) / accPrecision;
        assertEq(alicePending, rewardAmount + aliceShare);

        // Bob should have his share of new rewards only
        uint256 bobShare = (rewardAmount * accPrecision / totalStake * BOB_STAKE) / accPrecision;
        assertEq(bobPending, bobShare);
    }

    /* TEST: test_PendingRewards_RevertWhenInvalidToken - - - - - - - - - - - - /
     * Tests that pendingRewards reverts for non-reward tokens - - - - - - - -*/
    function test_PendingRewards_RevertWhenInvalidToken() public {
        LogUtils.logDebug("Testing pendingRewards revert when invalid token");

        vm.prank(alice);
        staker.stake(alice, ALICE_STAKE, false);

        vm.expectRevert(Staker.InvalidValue.selector);
        staker.pendingRewards(alice, 0, address(rewardToken2)); // Not a reward token
    }

    /* TEST: test_ComplexScenario_MultipleUsersAndRewards - - - - - - - - - - - /
     * Tests complex scenario with multiple users and reward distributions - - -*/
    function test_ComplexScenario_MultipleUsersAndRewards() public {
        LogUtils.logDebug("Testing complex scenario with multiple users and rewards");

        // Alice stakes with lock
        vm.prank(alice);
        staker.stake(alice, ALICE_STAKE, true);

        // Bob stakes without lock
        vm.prank(bob);
        staker.stake(bob, BOB_STAKE, false);

        // Send first batch of rewards
        uint256 firstReward = 3000 * 10 ** 18;
        rewardToken1.mint(address(staker), firstReward);
        dragon.mint(address(staker), firstReward / 2); // Dragon rewards too

        // Charlie stakes
        vm.prank(charlie);
        staker.stake(charlie, CHARLIE_STAKE, false);

        // Send second batch of rewards
        uint256 secondReward = 6000 * 10 ** 18;
        rewardToken1.mint(address(staker), secondReward);

        // Alice claims rewards
        uint256[] memory aliceIndexes = new uint256[](1);
        aliceIndexes[0] = 0;
        vm.prank(alice);
        staker.claimEarnings(aliceIndexes);

        // Bob withdraws (with fee)
        uint256[] memory bobIndexes = new uint256[](1);
        bobIndexes[0] = 0;
        vm.prank(bob);
        staker.withdraw(bobIndexes);

        // Warp time for Alice's lock to expire
        vm.warp(block.timestamp + LOCK_TIMESPAN + 1);

        // Alice withdraws (no fee)
        vm.prank(alice);
        staker.withdraw(aliceIndexes);

        // Verify final state
        assertGt(rewardToken1.balanceOf(alice), 0);
        assertGt(rewardToken1.balanceOf(bob), 0);
        assertEq(rewardToken1.balanceOf(charlie), 0); // Hasn't claimed yet
    }

    /* TEST: test_Constructor_RevertConditions - - - - - - - - - - - - - - - - -/
     * Tests constructor revert conditions - - - - - - - - - - - - - - - - - - */
    function test_Constructor_RevertConditions() public {
        LogUtils.logDebug("Testing constructor revert conditions");

        address[] memory emptyRewardTokens = new address[](0);

        // Test dragon zero address
        vm.expectRevert(Staker.InvalidAddress.selector);
        new Staker(owner, address(0), treasury, DEFAULT_FEE, emptyRewardTokens);

        // Test treasury zero address
        vm.expectRevert(Staker.InvalidAddress.selector);
        new Staker(owner, address(dragon), address(0), DEFAULT_FEE, emptyRewardTokens);

        // Test fee too high
        vm.expectRevert();
        new Staker(owner, address(dragon), treasury, 91_00, emptyRewardTokens);

        // Test reward token zero address
        address[] memory invalidRewardTokens = new address[](1);
        invalidRewardTokens[0] = address(0);
        vm.expectRevert(Staker.InvalidAddress.selector);
        new Staker(owner, address(dragon), treasury, DEFAULT_FEE, invalidRewardTokens);
    }

    /* TEST: test_ComputeDebtAccessHash - - - - - - - - - - - - - - - - - - - - /
     * Tests the computeDebtAccessHash function - - - - - - - - - - - - - - - -*/
    function test_ComputeDebtAccessHash() public view {
        LogUtils.logDebug("Testing computeDebtAccessHash function");

        bytes32 hash1 = staker.computeDebtAccessHash(alice, 0, address(dragon));
        bytes32 hash2 = staker.computeDebtAccessHash(alice, 0, address(rewardToken1));
        bytes32 hash3 = staker.computeDebtAccessHash(alice, 1, address(dragon));
        bytes32 hash4 = staker.computeDebtAccessHash(bob, 0, address(dragon));

        // All hashes should be different
        assertTrue(hash1 != hash2);
        assertTrue(hash1 != hash3);
        assertTrue(hash1 != hash4);
    }

    /* TEST: test_GetAccountStakeData_RevertWhenInvalidIndex - - - - - - - - - -/
     * Tests getAccountStakeData reverts with invalid index - - - - - - - - - -*/
    function test_GetAccountStakeData_RevertWhenInvalidIndex() public {
        LogUtils.logDebug("Testing getAccountStakeData revert when invalid index");

        vm.expectRevert(Staker.InvalidStakeIndex.selector);
        staker.getAccountStakeData(alice, 0); // No stakes yet
    }
}
