// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {Staker} from "src/Staker.sol";
import {LogUtils} from "test/utils/LogUtils.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/* NOTE: These tests do not check common attack vectors like signatures and reentrancy */
contract StakerFullTest is Test {
    address public alice = address(0xA11CE);
    address public bob = address(0xB0B);
    address public charlie = address(0xCACCE);

    uint256 public constant ALICE_STAKE = 10_000 * 10 ** 18;
    uint256 public constant BOB_STAKE = 20_000 * 10 ** 18;
    uint256 public constant CHARLIE_STAKE = 30_000 * 10 ** 18;
    uint256 public constant MINIMUM_DEPOSIT = 1 wei;

    uint256 constant PRECISION = 1_00_00;
    uint256 constant DEFAULT_FEE = 25_00; // 25% fee
    uint256 constant LOCK_TIMESPAN = 90 days;
    uint256 CENTURY22TIMESTAMP = 4102528271;

    Staker public staker;

    ERC20Mock public stakingToken;
    ERC20Mock public rewardToken1;
    ERC20Mock public rewardToken2;

    address public owner = makeAddr("owner");
    address public treasury = makeAddr("treasury");

    /* TEST: setUp - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -/
     * Pretend to be the owner address, create mock tokens and a staker, - - - -/
     * set up reward tokens and initialize the staker contract - - - - - - - - */
    function setUp() public {
        LogUtils.logInfo("Instantiating mock tokens");
        stakingToken = new ERC20Mock();
        rewardToken1 = new ERC20Mock();
        rewardToken2 = new ERC20Mock();

        LogUtils.logInfo("Setting up reward tokens array");
        address[] memory rewardTokens = new address[](1);
        rewardTokens[0] = address(rewardToken1);

        LogUtils.logInfo("Instantiating Staker contract with following values:");
        LogUtils.logInfo(string.concat("owner:\t\t", vm.toString(owner)));
        LogUtils.logInfo(string.concat("stakingToken addr:\t", vm.toString(address(stakingToken))));
        LogUtils.logInfo(string.concat("treasury addr:\t", vm.toString(treasury)));
        LogUtils.logInfo(string.concat("default fee:\t", vm.toString(DEFAULT_FEE)));
        LogUtils.logInfo(string.concat("reward token 1:\t", vm.toString(address(rewardToken1))));

        vm.prank(owner);
        staker = new Staker(owner, address(stakingToken), treasury, MINIMUM_DEPOSIT, DEFAULT_FEE, rewardTokens);

        LogUtils.logInfo("Minting tokens to test users");
        stakingToken.mint(alice, ALICE_STAKE * 10);
        stakingToken.mint(bob, BOB_STAKE * 10);
        stakingToken.mint(charlie, CHARLIE_STAKE * 10);

        LogUtils.logInfo("Setting up approvals");
        vm.prank(alice);
        stakingToken.approve(address(staker), type(uint256).max);
        vm.prank(bob);
        stakingToken.approve(address(staker), type(uint256).max);
        vm.prank(charlie);
        stakingToken.approve(address(staker), type(uint256).max);
    }

    /* TEST: test_Initialize - - - - - - - - - - - - - - - - - - - - - - - - - -/
     * Asserts the validity of values after instantiation- - - - - - - - - - - */
    function test_Initialize() public view {
        LogUtils.logDebug("Starting initialization assertion test");
        assertEq(address(staker.stakingToken()), address(stakingToken));
        assertEq(staker.treasury(), treasury);
        assertEq(staker.fee(), DEFAULT_FEE);
        assertEq(staker.owner(), owner);
        assertEq(staker.lockTimespan(), LOCK_TIMESPAN);
        assertEq(staker.totalDeposits(), 0);
        assertEq(staker.rewardTokensCounter(), 2); // stakingToken + rewardToken1
        assertTrue(staker.isRewardToken(address(stakingToken)));
        assertTrue(staker.isRewardToken(address(rewardToken1)));
        assertEq(staker.rewardTokens(0), address(stakingToken));
        assertEq(staker.rewardTokens(1), address(rewardToken1));
    }

    /* TEST: test_SetTreasury - - - - - - - - - - - - - - - - - - - - - - - - - /
     * Tests the setTreasury functionality - - - - - - - - - - - - - - - - - - */
    function test_SetTreasury() public {
        LogUtils.logDebug("Testing setTreasury functionality");

        address newTreasury = makeAddr("newTreasury");

        vm.expectEmit();
        emit Staker.TreasurySet(newTreasury);
        vm.prank(owner);
        staker.setTreasury(newTreasury);

        assertEq(staker.treasury(), newTreasury);
    }

    /* TEST: test_SetTreasury_RevertWhenNotOwner - - - - - - - - - - - - - - - -/
     * Tests that only owner can set treasury - - - - - - - - - - - - - - - - */
    function test_SetTreasury_RevertWhenNotOwner() public {
        LogUtils.logDebug("Testing setTreasury revert when not owner");

        address newTreasury = makeAddr("newTreasury");

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        vm.prank(alice);
        staker.setTreasury(newTreasury);
    }

    /* TEST: test_SetTreasury_RevertWhenZeroAddress - - - - - - - - - - - - - - /
     * Tests that treasury cannot be set to zero address - - - - - - - - - - - */
    function test_SetTreasury_RevertWhenZeroAddress() public {
        LogUtils.logDebug("Testing setTreasury revert when zero address");

        vm.expectRevert(Staker.InvalidAddress.selector);
        vm.prank(owner);
        staker.setTreasury(address(0));
    }

    /* TEST: test_SetFee - - - - - - - - - - - - - - - - - - - - - - - - - - - -/
     * Tests the setFee functionality - - - - - - - - - - - - - - - - - - - - -*/
    function test_SetFee() public {
        LogUtils.logDebug("Testing setFee functionality");

        uint256 newFee = 10_00; // 10%

        vm.expectEmit();
        emit Staker.FeeSet(newFee);
        vm.prank(owner);
        staker.setFee(newFee);

        assertEq(staker.fee(), newFee);
    }

    /* TEST: test_SetFee_RevertWhenNotOwner - - - - - - - - - - - - - - - - - - /
     * Tests that only owner can set fee - - - - - - - - - - - - - - - - - - - */
    function test_SetFee_RevertWhenNotOwner() public {
        LogUtils.logDebug("Testing setFee revert when not owner");

        vm.expectRevert();
        vm.prank(alice);
        staker.setFee(10_00);
    }

    /* TEST: test_SetFee_RevertWhenTooHigh - - - - - - - - - - - - - - - - - - -/
     * Tests that fee cannot be set above 90% - - - - - - - - - - - - - - - - */
    function test_SetFee_RevertWhenTooHigh() public {
        LogUtils.logDebug("Testing setFee revert when fee too high");

        uint256 invalidFee = 91_00; // 91%

        vm.expectRevert(Staker.InvalidValue.selector);
        vm.prank(owner);
        staker.setFee(invalidFee);
    }

    /* TEST: test_Stake_Success - - - - - - - - - - - - - - - - - - - - - - - - /
     * Tests successful staking without locking - - - - - - - - - - - - - - - -*/
    function test_Stake_Success() public {
        LogUtils.logDebug("Testing stake functionality");

        uint256 initialBalance = stakingToken.balanceOf(alice);
        uint256 initialTotalDeposits = staker.totalDeposits();

        vm.prank(alice);
        vm.expectEmit();

        emit Staker.Deposit(alice, alice, ALICE_STAKE, false, 0);
        staker.stake(alice, ALICE_STAKE, false);

        assertEq(stakingToken.balanceOf(alice), initialBalance - ALICE_STAKE);
        assertEq(stakingToken.balanceOf(address(staker)), ALICE_STAKE);
        assertEq(staker.totalDeposits(), initialTotalDeposits + ALICE_STAKE);
        assertEq(staker.userStakeCount(alice), 1);

        // Check stake details
        (uint256 amount, uint256 unlockTimestamp,,) = staker.getAccountStakeData(alice, 0);
        assertEq(amount, ALICE_STAKE);
        assertEq(unlockTimestamp, 0); // Not locked
    }

    /* TEST: test_Stake_WithLocking_Success - - - - - - - - - - - - - - - - - - /
     * Tests successful staking with locking - - - - - - - - - - - - - - - - - */
    function test_Stake_WithLocking_Success() public {
        LogUtils.logDebug("Testing stake with locking functionality");

        vm.prank(alice);
        vm.expectEmit();
        emit Staker.Deposit(alice, alice, ALICE_STAKE, true, 0);
        staker.stake(alice, ALICE_STAKE, true);

        // Check stake details
        (uint256 amount, uint256 unlockTimestamp,,) = staker.getAccountStakeData(alice, 0);
        assertEq(amount, ALICE_STAKE);
        assertEq(unlockTimestamp, block.timestamp + LOCK_TIMESPAN);
    }

    /* TEST: test_Stake_ForAnotherAccount_Success - - - - - - - - - - - - - - - /
     * Tests staking on behalf of another account - - - - - - - - - - - - - - -*/
    function test_Stake_ForAnotherAccount_Success() public {
        LogUtils.logDebug("Testing stake for another account");

        vm.prank(alice);
        vm.expectEmit();
        emit Staker.Deposit(alice, bob, ALICE_STAKE, false, 0);
        staker.stake(bob, ALICE_STAKE, false);

        assertEq(staker.userStakeCount(bob), 1);
        (uint256 amount,,,) = staker.getAccountStakeData(bob, 0);
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
        staker.stake(alice, MINIMUM_DEPOSIT - 1, false);
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
        (, uint256 unlockTimestamp,,) = staker.getAccountStakeData(alice, 0);
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

        vm.expectEmit();
        emit Staker.RewardTokenAdded(address(rewardToken2));
        vm.prank(owner);
        staker.addRewardToken(address(rewardToken2));

        assertTrue(staker.isRewardToken(address(rewardToken2)));
        assertEq(staker.rewardTokensCounter(), 3); // stakingToken + rewardToken1 + rewardToken2
        assertEq(staker.rewardTokens(2), address(rewardToken2));
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

        vm.expectRevert(Staker.AlreadyAdded.selector);
        vm.prank(owner);
        staker.addRewardToken(address(stakingToken)); // Already added in constructor
    }

    /* TEST: test_AddRewardToken_RevertWhenZeroAddress - - - - - - - - - - - - -/
     * Tests that zero address cannot be added as reward token - - - - - - - - */
    function test_AddRewardToken_RevertWhenZeroAddress() public {
        LogUtils.logDebug("Testing addRewardToken revert when zero address");

        vm.expectRevert(Staker.InvalidAddress.selector);
        vm.prank(owner);
        staker.addRewardToken(address(0));
    }

    /* TEST: test_RemoveRewardToken_Success - - - - - - - - - - - - - - - - - - /
     * Tests removing a reward token - - - - - - - - - - - - - - - - - - - - - */
    function test_RemoveRewardToken_Success() public {
        LogUtils.logDebug("Testing removeRewardToken functionality");

        // First add rewardToken2
        vm.prank(owner);
        staker.addRewardToken(address(rewardToken2));
        uint256 countBefore = staker.rewardTokensCounter();

        vm.expectEmit();
        emit Staker.RewardTokenRemoved(address(rewardToken1));
        vm.prank(owner);
        staker.removeRewardToken(address(rewardToken1));

        assertFalse(staker.isRewardToken(address(rewardToken1)));
        assertEq(staker.rewardTokensCounter(), countBefore - 1);
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

        vm.expectRevert(Staker.NotPresent.selector);
        vm.prank(owner);
        staker.removeRewardToken(address(rewardToken2)); // Not added yet
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
        emit Staker.Payout(alice, rewardToken1, rewardAmount, 0);
        staker.claimEarnings(stakeIndexes, address(0x0));

        assertEq(rewardToken1.balanceOf(alice), aliceBalanceBefore + rewardAmount);
    }

    /* TEST: test_ClaimEarnings_MultipleStakes - - - - - - - - - - - - - - - - -/
     * Tests claiming earnings from multiple stakes - - - - - - - - - - - - - -*/
    function test_ClaimEarnings_MultipleStakes() public {
        LogUtils.logDebug("Testing claimEarnings with multiple stakes");

        // Alice makes two stakes
        vm.prank(alice);
        staker.stake(alice, ALICE_STAKE, false);
        vm.prank(alice);
        staker.stake(alice, ALICE_STAKE, false);

        // Send reward tokens
        uint256 rewardAmount = 2000 * 10 ** 18;
        rewardToken1.mint(address(staker), rewardAmount);

        // Claim from both stakes
        uint256[] memory stakeIndexes = new uint256[](2);
        stakeIndexes[0] = 0;
        stakeIndexes[1] = 1;

        vm.prank(alice);
        staker.claimEarnings(stakeIndexes, address(0x0));

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
        staker.claimEarnings(stakeIndexes, address(0x0));
    }

    /* TEST: test_ClaimEarnings_RemovedRewardToken - - - - - - - - - - - - - - -/
     * Tests claiming earnings of a removed reward token - - - - - - - - - - - -*/
    function test_ClaimEarnings_RemovedRewardToken() public {
        LogUtils.logDebug("Testing claimEarnings with removed reward token");

        // Add second reward token
        vm.prank(owner);
        staker.addRewardToken(address(rewardToken2));

        // Alice stakes
        vm.prank(alice);
        staker.stake(alice, ALICE_STAKE, true);

        // Send rewards for both tokens
        rewardToken1.mint(address(staker), 1000 * 10 ** 18);
        rewardToken2.mint(address(staker), 500 * 10 ** 18);

        // Verify pending rewards
        assertEq(staker.pendingRewards(alice, 0, address(rewardToken1)), 1000 * 10 ** 18);
        assertEq(staker.pendingRewards(alice, 0, address(rewardToken2)), 500 * 10 ** 18);

        // Remove rewardToken2
        vm.prank(owner);
        staker.removeRewardToken(address(rewardToken2));

        // Try to claim earnings
        uint256[] memory stakeIndexes = new uint256[](1);
        stakeIndexes[0] = 0;

        uint256 aliceBalance1Before = rewardToken1.balanceOf(alice);
        uint256 aliceBalance2Before = rewardToken2.balanceOf(alice);

        vm.prank(alice);
        staker.claimEarnings(stakeIndexes, address(0x0));

        // Should only receive rewardToken1
        assertEq(rewardToken1.balanceOf(alice), aliceBalance1Before + 1000 * 10 ** 18);
        assertEq(rewardToken2.balanceOf(alice), aliceBalance2Before); // No change

        // Verify pending rewards after claim
        assertEq(staker.pendingRewards(alice, 0, address(rewardToken1)), 0);
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

        uint256 treasuryBalanceBefore = stakingToken.balanceOf(treasury);
        uint256 aliceBalanceBefore = stakingToken.balanceOf(alice);

        vm.prank(alice);
        // The contract emits Payout first, then Withdraw
        vm.expectEmit();
        emit Staker.Payout(alice, rewardToken1, rewardAmount, 0);
        vm.expectEmit();
        emit Staker.Withdraw(alice, 0, address(alice), expectedFee);
        staker.withdraw(stakeIndexes, address(alice));

        // Check balances
        assertEq(stakingToken.balanceOf(alice), aliceBalanceBefore + expectedReturn);
        assertEq(stakingToken.balanceOf(treasury), treasuryBalanceBefore + expectedFee);
        assertEq(rewardToken1.balanceOf(alice), rewardAmount);
        assertEq(staker.totalDeposits(), 0);

        // Check stake is claimed
        (,,, uint256[] memory rewardDebts) = staker.getAccountStakeData(alice, 0);
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

        uint256 aliceBalanceBefore = stakingToken.balanceOf(alice);

        vm.prank(alice);
        staker.withdraw(stakeIndexes, address(0x0));

        // No fee for locked stakes
        assertEq(stakingToken.balanceOf(alice), aliceBalanceBefore + ALICE_STAKE);
        assertEq(stakingToken.balanceOf(treasury), 0);
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
        staker.withdraw(stakeIndexes, address(0x0));

        // Try to withdraw again
        vm.prank(alice);
        vm.expectRevert(Staker.AlreadyClaimed.selector);
        staker.withdraw(stakeIndexes, address(0x0));
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
        staker.withdraw(stakeIndexes, address(0x0));
    }

    /* TEST: test_EmergencyWithdraw_Success - - - - - - - - - - - - - - - - - - /
     * Tests emergency withdrawal without rewards - - - - - - - - - - - - - - -*/
    function test_EmergencyWithdraw_Success() public {
        uint256 LOCAL_SMALL_ALICE_STAKE = 1000;
        LogUtils.logDebug("Testing emergencyWithdraw functionality");

        LogUtils.logDebug(
            string.concat("Starting alice balance of token: ", vm.toString(stakingToken.balanceOf(alice)))
        );
        // Alice stakes without locking
        vm.prank(alice);
        staker.stake(alice, LOCAL_SMALL_ALICE_STAKE, false);

        LogUtils.logDebug(string.concat("ALICE IS STAKING: ", vm.toString(LOCAL_SMALL_ALICE_STAKE)));

        // Send rewards but don't claim them
        rewardToken1.mint(address(staker), 10000000 * 10 ** 18);

        uint256[] memory stakeIndexes = new uint256[](1);
        stakeIndexes[0] = 0;

        uint256 expectedFee = (LOCAL_SMALL_ALICE_STAKE * DEFAULT_FEE) / PRECISION;

        LogUtils.logDebug(string.concat("Expecting the fee of 25%: ", vm.toString(expectedFee)));
        uint256 expectedReturn = LOCAL_SMALL_ALICE_STAKE - expectedFee;

        uint256 aliceBalanceBefore = stakingToken.balanceOf(alice);
        uint256 aliceRewardBalanceBefore = rewardToken1.balanceOf(alice);

        LogUtils.logDebug(
            string.concat("Staker balance before: ", vm.toString(stakingToken.balanceOf(address(staker))))
        );
        LogUtils.logDebug(string.concat("Alice balance before: ", vm.toString(stakingToken.balanceOf(address(alice)))));

        vm.prank(alice);
        vm.expectEmit();
        emit Staker.EmergencyWithdraw(alice, 0, address(alice), expectedFee);

        staker.emergencyWithdraw(stakeIndexes, address(alice));
        LogUtils.logDebug(string.concat("Staker balance after: ", vm.toString(stakingToken.balanceOf(address(staker)))));

        LogUtils.logDebug(string.concat("Alice balance after: ", vm.toString(stakingToken.balanceOf(address(alice)))));
        // Check only principal was withdrawn, no rewards
        assertEq(stakingToken.balanceOf(alice), aliceBalanceBefore + expectedReturn);
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
        staker.withdraw(stakeIndexes, address(0x0));

        vm.prank(alice);
        vm.expectRevert(Staker.AlreadyClaimed.selector);
        staker.emergencyWithdraw(stakeIndexes, address(0x0));
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

        vm.expectEmit();
        emit Staker.Swept(address(nonRewardToken), recipient, sweepAmount);
        vm.prank(owner);
        staker.sweep(IERC20(address(nonRewardToken)), recipient);

        assertEq(nonRewardToken.balanceOf(recipient), sweepAmount);
        assertEq(nonRewardToken.balanceOf(address(staker)), 0);
    }

    /* TEST: test_Sweep_AfterRemovingRewardToken - - - - - - - - - - - - - - - -/
     * Tests sweeping after removing an existing reward token - - - - - - - - -*/
    function test_Sweep_AfterRemovingRewardToken() public {
        LogUtils.logDebug("Testing sweep after removing reward token");

        // Add second reward token
        vm.prank(owner);
        staker.addRewardToken(address(rewardToken2));

        // Alice and Bob stake
        vm.prank(alice);
        staker.stake(alice, ALICE_STAKE, true);

        vm.prank(bob);
        staker.stake(bob, BOB_STAKE, true);

        // Send rewards
        rewardToken1.mint(address(staker), 2000 * 10 ** 18);
        rewardToken2.mint(address(staker), 1000 * 10 ** 18);

        // Remove rewardToken2
        vm.prank(owner);
        staker.removeRewardToken(address(rewardToken2));

        uint256 treasuryBalanceBefore = rewardToken2.balanceOf(treasury);

        // Sweep the removed token
        vm.expectEmit();
        emit Staker.Swept(address(rewardToken2), treasury, 1000 * 10 ** 18);
        vm.prank(owner);
        staker.sweep(IERC20(address(rewardToken2)), treasury);

        // Verify the full balance was sent to treasury
        assertEq(rewardToken2.balanceOf(treasury), treasuryBalanceBefore + 1000 * 10 ** 18);
        assertEq(rewardToken2.balanceOf(address(staker)), 0);
    }

    /* TEST: test_Sweep_StakingToken_RevertWhenRewardToken - - - - - - - - - - - /
     * Tests that stakingToken token cannot be swept as it's a reward token - - - - */
    function test_Sweep_StakingToken_RevertWhenRewardToken() public {
        LogUtils.logDebug("Testing sweep stakingToken token reverts");

        // Alice stakes
        vm.prank(alice);
        staker.stake(alice, ALICE_STAKE, false);

        // Send extra stakingToken tokens directly to staker
        uint256 excessAmount = 1000 * 10 ** 18;
        stakingToken.mint(address(staker), excessAmount);

        address recipient = makeAddr("recipient");

        // stakingToken is a reward token, so sweep should revert
        vm.expectRevert();
        vm.prank(owner);
        staker.sweep(IERC20(address(stakingToken)), recipient);

        // Verify tokens remain in staker
        assertEq(stakingToken.balanceOf(address(staker)), ALICE_STAKE + excessAmount);
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

        vm.expectRevert();
        vm.prank(owner);
        staker.sweep(IERC20(address(rewardToken1)), owner);
    }

    /* TEST: test_Sweep_RevertWhenNoBalance - - - - - - - - - - - - - - - - - - /
    * Tests that sweep reverts when no balance to sweep - - - - - - - - - - -*/
    function test_Sweep_RevertWhenNoBalance() public {
        LogUtils.logDebug("Testing sweep revert when no balance");

        ERC20Mock nonRewardToken = new ERC20Mock();

        vm.expectRevert();
        vm.prank(owner);
        staker.sweep(IERC20(address(nonRewardToken)), owner);
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
        stakingToken.mint(address(staker), firstReward / 2); // stakingToken rewards too

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
        staker.claimEarnings(aliceIndexes, address(0x0));

        // Bob withdraws (with fee)
        uint256[] memory bobIndexes = new uint256[](1);
        bobIndexes[0] = 0;
        vm.prank(bob);
        staker.withdraw(bobIndexes, address(0x0));

        // Warp time for Alice's lock to expire
        vm.warp(block.timestamp + LOCK_TIMESPAN + 1);

        // Alice withdraws (no fee)
        vm.prank(alice);
        staker.withdraw(aliceIndexes, address(0x0));

        // Verify final state
        assertGt(rewardToken1.balanceOf(alice), 0);
        assertGt(rewardToken1.balanceOf(bob), 0);
        assertEq(rewardToken1.balanceOf(charlie), 0); // Hasn't claimed yet
    }

    /* TEST: test_ExactRewardDistribution_ThreeUsers - - - - - - - - - - - - - -/
    * Tests exact reward calculations for three users with different stakes - -*/
    function test_ExactRewardDistribution_ThreeUsers() public {
        LogUtils.logDebug("Testing exact reward distribution for three users");

        // Three users stake different amounts
        uint256 totalStake = ALICE_STAKE + BOB_STAKE + CHARLIE_STAKE;

        vm.prank(alice);
        staker.stake(alice, ALICE_STAKE, true);

        vm.prank(bob);
        staker.stake(bob, BOB_STAKE, true);

        vm.prank(charlie);
        staker.stake(charlie, CHARLIE_STAKE, true);

        // Send rewards
        uint256 totalRewards = 6000 * 10 ** 18;
        rewardToken1.mint(address(staker), totalRewards);

        // Calculate expected rewards based on stake proportion
        uint256 expectedAliceReward = (totalRewards * ALICE_STAKE) / totalStake;
        uint256 expectedBobReward = (totalRewards * BOB_STAKE) / totalStake;
        uint256 expectedCharlieReward = (totalRewards * CHARLIE_STAKE) / totalStake;

        // Verify pending rewards match expected values
        assertEq(staker.pendingRewards(alice, 0, address(rewardToken1)), expectedAliceReward);
        assertEq(staker.pendingRewards(bob, 0, address(rewardToken1)), expectedBobReward);
        assertEq(staker.pendingRewards(charlie, 0, address(rewardToken1)), expectedCharlieReward);

        // Claim and verify exact balances
        uint256[] memory stakeIndexes = new uint256[](1);
        stakeIndexes[0] = 0;

        uint256 aliceBalanceBefore = rewardToken1.balanceOf(alice);
        vm.prank(alice);
        staker.claimEarnings(stakeIndexes, address(0x0));
        assertEq(rewardToken1.balanceOf(alice), aliceBalanceBefore + expectedAliceReward);

        uint256 bobBalanceBefore = rewardToken1.balanceOf(bob);
        vm.prank(bob);
        staker.claimEarnings(stakeIndexes, address(0x0));
        assertEq(rewardToken1.balanceOf(bob), bobBalanceBefore + expectedBobReward);

        uint256 charlieBalanceBefore = rewardToken1.balanceOf(charlie);
        vm.prank(charlie);
        staker.claimEarnings(stakeIndexes, address(0x0));
        assertEq(rewardToken1.balanceOf(charlie), charlieBalanceBefore + expectedCharlieReward);

        // Verify all rewards distributed (accounting for rounding)
        uint256 totalDistributed = expectedAliceReward + expectedBobReward + expectedCharlieReward;
        assertLe(totalRewards - totalDistributed, 2);
    }

    /* TEST: test_Constructor_RevertConditions - - - - - - - - - - - - - - - - -/
    * Tests constructor revert conditions - - - - - - - - - - - - - - - - - - */
    function test_Constructor_RevertConditions() public {
        LogUtils.logDebug("Testing constructor revert conditions");

        address[] memory emptyRewardTokens = new address[](0);

        // Test stakingToken zero address
        vm.expectRevert(Staker.InvalidAddress.selector);
        new Staker(owner, address(0), treasury, MINIMUM_DEPOSIT, DEFAULT_FEE, emptyRewardTokens);

        // Test treasury zero address
        vm.expectRevert(Staker.InvalidAddress.selector);
        new Staker(owner, address(stakingToken), address(0), MINIMUM_DEPOSIT, DEFAULT_FEE, emptyRewardTokens);

        // Test fee too high
        vm.expectRevert();
        new Staker(owner, address(stakingToken), treasury, MINIMUM_DEPOSIT, 91_00, emptyRewardTokens);

        // Test reward token zero address
        address[] memory invalidRewardTokens = new address[](1);
        invalidRewardTokens[0] = address(0);
        vm.expectRevert(Staker.InvalidAddress.selector);
        new Staker(owner, address(stakingToken), treasury, MINIMUM_DEPOSIT, DEFAULT_FEE, invalidRewardTokens);
    }

    /* TEST: test_ComputeDebtAccessHash - - - - - - - - - - - - - - - - - - - - /
    * Tests the computeDebtAccessHash function - - - - - - - - - - - - - - - -*/
    function test_ComputeDebtAccessHash() public view {
        LogUtils.logDebug("Testing computeDebtAccessHash function");

        // Compute the debtHashBase that the staker uses
        // debtHashBase = keccak256(abi.encode(block.chainid, address(staker)))
        bytes32 debtHashBase = keccak256(abi.encode(block.chainid, address(staker)));

        // Test case 1: Alice, stake 0, stakingToken
        bytes32 expectedHash1 = keccak256(abi.encodePacked(debtHashBase, alice, uint256(0), address(stakingToken)));
        bytes32 actualHash1 = staker.computeDebtAccessHash(alice, 0, address(stakingToken));
        assertEq(actualHash1, expectedHash1, "Hash1 computation incorrect");

        // Test case 2: Alice, stake 0, rewardToken1
        bytes32 expectedHash2 = keccak256(abi.encodePacked(debtHashBase, alice, uint256(0), address(rewardToken1)));
        bytes32 actualHash2 = staker.computeDebtAccessHash(alice, 0, address(rewardToken1));
        assertEq(actualHash2, expectedHash2, "Hash2 computation incorrect");

        // Test case 3: Alice, stake 1, stakingToken
        bytes32 expectedHash3 = keccak256(abi.encodePacked(debtHashBase, alice, uint256(1), address(stakingToken)));
        bytes32 actualHash3 = staker.computeDebtAccessHash(alice, 1, address(stakingToken));
        assertEq(actualHash3, expectedHash3, "Hash3 computation incorrect");

        // Test case 4: Bob, stake 0, stakingToken
        bytes32 expectedHash4 = keccak256(abi.encodePacked(debtHashBase, bob, uint256(0), address(stakingToken)));
        bytes32 actualHash4 = staker.computeDebtAccessHash(bob, 0, address(stakingToken));
        assertEq(actualHash4, expectedHash4, "Hash4 computation incorrect");

        // Test case 5: High stake index
        bytes32 expectedHash5 = keccak256(abi.encodePacked(debtHashBase, alice, uint256(999), address(stakingToken)));
        bytes32 actualHash5 = staker.computeDebtAccessHash(alice, 999, address(stakingToken));
        assertEq(actualHash5, expectedHash5, "High index hash computation incorrect");

        // Test case 6: Zero address (edge case)
        bytes32 expectedHash6 = keccak256(abi.encodePacked(debtHashBase, address(0), uint256(0), address(stakingToken)));
        bytes32 actualHash6 = staker.computeDebtAccessHash(address(0), 0, address(stakingToken));
        assertEq(actualHash6, expectedHash6, "Zero address hash computation incorrect");

        // Verify all hashes are unique (collision resistance)
        assertNotEq(actualHash1, actualHash2, "Different tokens should produce different hashes");
        assertNotEq(actualHash1, actualHash3, "Different stake indices should produce different hashes");
        assertNotEq(actualHash1, actualHash4, "Different users should produce different hashes");
        assertNotEq(actualHash2, actualHash3, "Different token/index combinations should be unique");
        assertNotEq(actualHash2, actualHash4, "Different user/token combinations should be unique");
        assertNotEq(actualHash3, actualHash4, "Different user/index combinations should be unique");
        assertNotEq(actualHash1, actualHash5, "Different indices should be unique");
        assertNotEq(actualHash1, actualHash6, "Different addresses should be unique");

        // Logs
        LogUtils.logInfo(string.concat("Chain ID: ", vm.toString(block.chainid)));
        LogUtils.logInfo(string.concat("Staker address: ", vm.toString(address(staker))));
        LogUtils.logInfo(string.concat("Computed debtHashBase: ", vm.toString(debtHashBase)));
        LogUtils.logInfo(string.concat("Sample hash (Alice, 0, stakingToken): ", vm.toString(actualHash1)));
    }
    /* TEST: test_ComputeDebtAccessHash_RealScenario - - - - - - - - - - - - - -/
     * Tests debt hash computation aligns with hash map keys in real scenario- -*/

    function test_ComputeDebtAccessHash_RealScenario() public {
        LogUtils.logDebug("Testing computeDebtAccessHash in real scenario");

        // Alice stakes
        vm.prank(alice);
        staker.stake(alice, ALICE_STAKE, true);

        // Send rewards
        rewardToken1.mint(address(staker), 1000 * 10 ** 18);

        // Get stake data before claim
        (uint256 amount, uint256 unlockTimestamp,, uint256[] memory rewardDebts) = staker.getAccountStakeData(alice, 0);
        assertEq(amount, ALICE_STAKE);
        assertGt(unlockTimestamp, 0);

        // Initial debt should be 0
        assertEq(rewardDebts[0], 0); // stakingToken debt
        assertEq(rewardDebts[1], 0); // rewardToken1 debt

        // Compute the hash
        bytes32 computedHash = staker.computeDebtAccessHash(alice, 0, address(rewardToken1));

        // Claim rewards
        uint256[] memory stakeIndexes = new uint256[](1);
        stakeIndexes[0] = 0;
        vm.prank(alice);
        staker.claimEarnings(stakeIndexes, address(0x0));

        // Get stake data after claim
        (,,, uint256[] memory newRewardDebts) = staker.getAccountStakeData(alice, 0);

        // Debt should have increased after claiming
        assertGt(newRewardDebts[1], rewardDebts[1]); // rewardToken1 debt increased

        // Verify hash is deterministic
        bytes32 newComputedHash = staker.computeDebtAccessHash(alice, 0, address(rewardToken1));
        assertEq(computedHash, newComputedHash);
    }

    /* TEST: test_GetAccountStakeData_RevertWhenInvalidIndex - - - - - - - - - -/
    * Tests getAccountStakeData reverts with invalid index - - - - - - - - - -*/
    function test_GetAccountStakeData_RevertWhenInvalidIndex() public {
        LogUtils.logDebug("Testing getAccountStakeData revert when invalid index");

        vm.expectRevert(Staker.InvalidStakeIndex.selector);
        staker.getAccountStakeData(alice, 0); // No stakes yet
    }

    /* TEST: test_GetAccountStakeData_RevertWhenInvalidIndex_ExistingStake - - -/
    * Tests getAccountStakeData reverts on existing stake with invalid index -*/
    function test_GetAccountStakeData_RevertWhenInvalidIndex_ExistingStake() public {
        LogUtils.logDebug("Testing getAccountStakeData revert on existing stake with invalid index");

        // Alice creates multiple stakes
        vm.prank(alice);
        staker.stake(alice, ALICE_STAKE, true);
        vm.prank(alice);
        staker.stake(alice, ALICE_STAKE, true);
        vm.prank(alice);
        staker.stake(alice, ALICE_STAKE, true);

        // Verify valid indexes work
        staker.getAccountStakeData(alice, 0);
        staker.getAccountStakeData(alice, 1);
        staker.getAccountStakeData(alice, 2);

        // Try invalid index
        vm.expectRevert(Staker.InvalidStakeIndex.selector);
        staker.getAccountStakeData(alice, 3);

        // Try much larger invalid index
        vm.expectRevert(Staker.InvalidStakeIndex.selector);
        staker.getAccountStakeData(alice, 999);

        // Withdraw one stake
        uint256[] memory stakeIndexes = new uint256[](1);
        stakeIndexes[0] = 1;

        // Wait for unlock
        vm.warp(block.timestamp + LOCK_TIMESPAN + 1);

        vm.prank(alice);
        staker.withdraw(stakeIndexes, address(0x0));

        (uint256 amount, uint256 unlockTimestamp,,) = staker.getAccountStakeData(alice, 1);
        assertEq(amount, ALICE_STAKE);
        assertGt(unlockTimestamp, 0);
    }

    function _stake(address user, uint256 amount, bool isLocked) internal {
        vm.prank(user);
        stakingToken.approve(address(staker), amount);
        vm.prank(user);
        staker.stake(user, amount, isLocked);
    }
    /* TEST: test_ClaimEarnings_AfterWithdraw_ShouldRevert - - - - - - - - - - -/
    * Should revert when claiming on withdrawn stake - FAILS due to exploit - */

    function test_ClaimEarnings_AfterWithdraw_ShouldRevert() public {
        LogUtils.logDebug("Testing claim should revert on withdrawn stake");

        // Alice stakes locked, Charlie stakes unlocked
        vm.prank(alice);
        staker.stake(alice, ALICE_STAKE, true);
        vm.prank(charlie);
        staker.stake(charlie, CHARLIE_STAKE, false);

        // Charlie withdraws
        uint256[] memory stakeIndexes = new uint256[](1);
        stakeIndexes[0] = 0;
        vm.prank(charlie);
        staker.withdraw(stakeIndexes, address(0x0));

        // Add rewards
        rewardToken1.mint(address(staker), 1_000 * 10 ** 18);

        vm.prank(charlie);
        vm.expectRevert(Staker.AlreadyClaimed.selector);
        staker.claimEarnings(stakeIndexes, address(0x0));
    }

    /* TEST: test_WithdrawnStake_ShouldNotAccumulateRewards - - - - - - - - - - /
    * Withdrawn stakes should show 0 pending - FAILS due to exploit - - - - -*/
    function test_WithdrawnStake_ShouldNotAccumulateRewards() public {
        LogUtils.logDebug("Testing withdrawn stake should not accumulate rewards");

        // Charlie stakes and withdraws
        vm.prank(charlie);
        staker.stake(charlie, CHARLIE_STAKE, false);

        uint256[] memory stakeIndexes = new uint256[](1);
        stakeIndexes[0] = 0;
        vm.prank(charlie);
        staker.withdraw(stakeIndexes, address(0x0));

        // Add rewards after withdrawal
        rewardToken1.mint(address(staker), 1_000 * 10 ** 18);

        // Pending rewards should be 0 for withdrawn stake
        uint256 charliePending = staker.pendingRewards(charlie, 0, address(rewardToken1));
        assertEq(charliePending, 0, "Withdrawn stake should not show pending rewards");
    }

    /* TEST: test_CannotClaimTwiceOnSameRewards - - - - - - - - - - - - - - - - /
    * Should not allow claiming more than fair share - FAILS due to exploit - */
    function test_CannotClaimTwiceOnSameRewards() public {
        LogUtils.logDebug("Testing cannot claim twice on same rewards");

        uint256 rewardAmount = 1_000 * 10 ** 18;

        // Both stake equal amounts
        vm.prank(alice);
        staker.stake(alice, ALICE_STAKE, true);
        vm.prank(charlie);
        staker.stake(charlie, ALICE_STAKE, false);

        // Add rewards
        rewardToken1.mint(address(staker), rewardAmount);

        // Charlie withdraws (should get 50% rewards)
        uint256[] memory stakeIndexes = new uint256[](1);
        stakeIndexes[0] = 0;
        vm.prank(charlie);
        staker.withdraw(stakeIndexes, address(0x0));

        uint256 charlieBalance = rewardToken1.balanceOf(charlie);

        // Charlie tries to claim again - should get 0 more rewards
        vm.prank(charlie);
        vm.expectRevert(Staker.AlreadyClaimed.selector);
        staker.claimEarnings(stakeIndexes, address(0x0));

        assertEq(rewardToken1.balanceOf(charlie), charlieBalance, "Should not claim additional rewards");
    }

    /* TEST: test_FairRewardDistribution_AfterWithdraw - - - - - - - - - - - - -/
    * Alice should get all rewards after Charlie withdraws - FAILS - - - - - -*/
    function test_FairRewardDistribution_AfterWithdraw() public {
        LogUtils.logDebug("Testing fair reward distribution after withdrawal");

        // Both stake
        vm.prank(alice);
        staker.stake(alice, ALICE_STAKE, true);
        vm.prank(charlie);
        staker.stake(charlie, ALICE_STAKE, false);

        // Charlie withdraws immediately
        uint256[] memory stakeIndexes = new uint256[](1);
        stakeIndexes[0] = 0;
        vm.prank(charlie);
        staker.withdraw(stakeIndexes, address(0x0));

        // Add rewards - should only go to Alice now
        uint256 rewardAmount = 1_000 * 10 ** 18;
        rewardToken1.mint(address(staker), rewardAmount);

        // Alice claims
        vm.prank(alice);
        staker.claimEarnings(stakeIndexes, address(0x0));

        // Alice should get ALL rewards since Charlie withdrew
        assertEq(rewardToken1.balanceOf(alice), rewardAmount, "Alice should get all rewards");

        // Charlie should get 0 new rewards
        vm.prank(charlie);
        vm.expectRevert(Staker.AlreadyClaimed.selector);
        staker.claimEarnings(stakeIndexes, address(0x0));
        assertEq(rewardToken1.balanceOf(charlie), 0, "Charlie should get no new rewards after withdrawal");
    }

    /* TEST: test_MultipleWithdrawn_CannotClaim - - - - - - - - - - - - - - - - /
    * Multiple withdrawn stakes should not claim - FAILS due to exploit - - - */
    function test_MultipleWithdrawn_CannotClaim() public {
        LogUtils.logDebug("Testing multiple withdrawn stakes cannot claim");

        // Charlie creates and withdraws 3 stakes
        uint256[] memory stakeIndexes = new uint256[](3);
        stakeIndexes[0] = 0;
        stakeIndexes[1] = 1;
        stakeIndexes[2] = 2;

        vm.startPrank(charlie);
        staker.stake(charlie, ALICE_STAKE, false);
        staker.stake(charlie, ALICE_STAKE, false);
        staker.stake(charlie, ALICE_STAKE, false);
        staker.withdraw(stakeIndexes, address(0x0));
        vm.stopPrank();

        // Add rewards after withdrawal
        rewardToken1.mint(address(staker), 3_000 * 10 ** 18);

        // Should revert when claiming on withdrawn stakes
        vm.prank(charlie);
        vm.expectRevert(Staker.AlreadyClaimed.selector);
        staker.claimEarnings(stakeIndexes, address(0x0));
    }

    /* TEST: test_ClaimEarnings_GasIncrease_WithLessStakes - - - - - - - - - - -/
     * Tests gas consumption increase in claimEarnings with 10 stakes - - - - -*/
    function test_ClaimEarnings_GasIncrease_B_WithLessStakes() public {
        uint256 smallStakeCount = 10;
        uint256 smallStakeClaimDeltaGas;
        uint256 stakeAmount = 100 * 10 ** 18;
        uint256 rewardPerRound = 1000 * 10 ** 18;

        // Mint additional tokens for gas test
        stakingToken.mint(alice, ALICE_STAKE * 5000);
        stakingToken.mint(bob, BOB_STAKE * 5000);

        for (uint256 i = 0; i < smallStakeCount; i++) {
            // Alice stakes
            vm.prank(alice);
            staker.stake(alice, stakeAmount, false);

            // Bob stakes
            vm.prank(bob);
            staker.stake(bob, stakeAmount, false);

            // Distribute rewards
            rewardToken1.mint(address(staker), rewardPerRound);

            // Measure gas on final iteration
            if (i == smallStakeCount - 1) {
                uint256[] memory stakeIndexes = new uint256[](1);
                stakeIndexes[0] = 0; // Claim only first stake

                uint256 gasBefore = gasleft();
                vm.prank(alice);
                staker.claimEarnings(stakeIndexes, address(0x0));
                uint256 gasUsed = gasBefore - gasleft();
                smallStakeClaimDeltaGas = gasUsed;

                LogUtils.logInfo(
                    string.concat(
                        "Gas used for claimEarnings with ",
                        vm.toString(smallStakeCount),
                        " total stakes: ",
                        vm.toString(gasUsed)
                    )
                );

                // Assert reasonable gas consumption
                // This test may fail if there's a gas DoS vulnerability
                assertLt(gasUsed, 1_000_000, "Gas leak - potential DoS vulnerability");
            }
        }

        // Check with arbitrary value
        assertLt(smallStakeClaimDeltaGas, 58495);
    }

    /* TEST: test_ClaimEarnings_GasIncrease_WithManyStakes - - - - - - - - - - -/
     * Tests gas consumption increase in claimEarnings with 7000 stakes - - - -*/
    function test_ClaimEarnings_GasIncrease_A_WithManyStakes() public {
        LogUtils.logDebug("Testing gas increase in claimEarnings with many stakes");

        // Mint additional tokens for gas test
        stakingToken.mint(alice, ALICE_STAKE * 5000);
        stakingToken.mint(bob, BOB_STAKE * 5000);

        uint256 largeStakeCount = 7000;

        uint256 largeStakeClaimDeltaGas;

        uint256 stakeAmount = 100 * 10 ** 18;
        uint256 rewardPerRound = 1000 * 10 ** 18;

        LogUtils.logInfo(string.concat("Creating ", vm.toString(largeStakeCount), " stakes to test gas consumption"));

        for (uint256 i = 0; i < largeStakeCount; i++) {
            // Alice
            vm.prank(alice);
            staker.stake(alice, stakeAmount, false);

            // Bob
            vm.prank(bob);
            staker.stake(bob, stakeAmount, false);

            // Distribute rewards
            rewardToken1.mint(address(staker), rewardPerRound);

            // Measure gas on final iteration
            if (i == largeStakeCount - 1) {
                uint256[] memory stakeIndexes = new uint256[](1);
                stakeIndexes[0] = 0; // Claim only first stake

                uint256 gasBefore = gasleft();
                vm.prank(alice);
                staker.claimEarnings(stakeIndexes, address(0x0));
                uint256 gasUsed = gasBefore - gasleft();

                largeStakeClaimDeltaGas = gasUsed;

                LogUtils.logInfo(
                    string.concat(
                        "Gas used for claimEarnings with ",
                        vm.toString(largeStakeCount),
                        " total stakes: ",
                        vm.toString(gasUsed)
                    )
                );

                // Assert reasonable gas consumption
                // This test may fail if there's a gas DoS vulnerability
                assertLt(gasUsed, 1_000_000, "Gas leak - potential DoS vulnerability");
            }
        }

        // Check with arbitrary value
        assertLt(largeStakeClaimDeltaGas, 58495);

        LogUtils.logInfo("Gas consumption test completed");
    }
}
