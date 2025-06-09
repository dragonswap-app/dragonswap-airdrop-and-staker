/* SPDX-License-Identifier: MIT */
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {Airdrop} from "src/Airdrop.sol";
import {AirdropFactory} from "src/AirdropFactory.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {MockStaker} from "test/mocks/MockStaker.sol";
import {LogUtils} from "test/utils/LogUtils.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {IStaker} from "src/interfaces/IStaker.sol";

contract AirdropUnitTest is Test {
    using MessageHashUtils for bytes32;

    /* WITHDRAWAL SPECIFIC VALUES */
    address public alice = address(0xA11CE);
    address public bob = address(0xB0B);

    uint256 public constant ALICE_PORTION = 10_000 * 10 ** 18;
    uint256 public constant BOB_PORTION = 20_000 * 10 ** 18;

    uint256 public signerPrivateKey = 0x123456789;
    address public signer = vm.addr(signerPrivateKey);

    uint256 constant DEFAULT_PENALTY_WALLET = 50_00_00;
    uint256 constant DEFAULT_PENALTY_STAKER = 0;
    uint256 constant PRECISION = 1_00_00_00;

    Airdrop public airdropImpl;
    AirdropFactory public factory;
    Airdrop public airdrop;
    MockERC20 public token;
    MockStaker public mockStaker;

    address public owner = makeAddr("owner");
    address public treasury = makeAddr("treasury");

    uint256[] public timestamps;

    /* TEST: setUp - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - /
     * Pretend to be the owner address, create a mock token and an airdrop, - - /
     * set up two timestamps for dates, initialize the airdrop factory  - - - -*/
    function setUp() public {
        LogUtils.logDebug("Starting prank as owner");
        vm.startPrank(owner);

        LogUtils.logInfo("Instantiating a mock token");
        token = new MockERC20("Test Token", "TEST");

        LogUtils.logInfo("Instantiating a mock staker");
        mockStaker = new MockStaker();

        LogUtils.logInfo("Instantiating an Airdrop implementation");
        airdropImpl = new Airdrop();

        LogUtils.logInfo("Instantiating an Airdrop Factory");
        factory = new AirdropFactory(address(airdropImpl), owner);

        LogUtils.logInfo("Pushing timestamps");
        timestamps.push(block.timestamp + 1 days);
        timestamps.push(block.timestamp + 7 days);

        LogUtils.logInfo("Initializing airdrop with following values:");
        LogUtils.logInfo(string.concat("token addr:\t\t", vm.toString(address(token))));
        LogUtils.logInfo(string.concat("mock staker:\t", vm.toString(address(mockStaker))));
        LogUtils.logInfo(string.concat("treasury addr:\t", vm.toString(treasury)));
        LogUtils.logInfo(string.concat("signer addr:\t", vm.toString(signer)));
        LogUtils.logInfo(string.concat("owner:\t\t", vm.toString(owner)));
        LogUtils.logInfo(string.concat("timestamp 1\t\t", vm.toString(timestamps[0])));
        LogUtils.logInfo(string.concat("timestamp 2\t\t", vm.toString(timestamps[1])));

        LogUtils.logInfo("Factory deploying...");
        address airdropAddr = factory.deploy(address(token), address(mockStaker), treasury, signer, owner, timestamps);

        LogUtils.logInfo("Setting airdrop to factory deploy address");
        airdrop = Airdrop(airdropAddr);

        LogUtils.logInfo("Stopping prank as owner");
        vm.stopPrank();
    }

    /* TEST: test_Initialize - - - - - - - - - - - - - - - - - - - - - - - - - -/
     * Asserts the validity of values after instantiation- - - - - - - - - - - */
    function test_Initialize() public view {
        LogUtils.logDebug("Starting initialization assertion test");
        assertEq(address(airdrop.token()), address(token));
        assertEq(airdrop.signer(), signer);
        assertEq(airdrop.treasury(), treasury);
        assertEq(airdrop.staker(), address(mockStaker));
        assertEq(airdrop.owner(), owner);
        assertEq(airdrop.unlocks(0), timestamps[0]);
        assertEq(airdrop.unlocks(1), timestamps[1]);
        assertFalse(airdrop.lock());
        assertEq(airdrop.penaltyWallet(), DEFAULT_PENALTY_WALLET);
        assertEq(airdrop.penaltyStaker(), DEFAULT_PENALTY_STAKER);
    }

    /* TEST: test_FactoryDeployment - - - - - - - - - - - - - - - - - - - - - - /
     * Tests the factory deployment functionality - - - - - - - - - - - - - - -*/
    function test_FactoryDeployment() public {
        LogUtils.logDebug("Testing factory deployment");

        /* Check deployment count */
        assertEq(factory.noOfDeployments(), 1);

        /* Check latest deployment */
        assertEq(factory.getLatestDeployment(), address(airdrop));

        /* Check if deployed through factory */
        assertTrue(factory.isDeployedThroughFactory(address(airdrop)));

        /* Check deployment to implementation mapping */
        assertEq(factory.deploymentToImplementation(address(airdrop)), address(airdropImpl));
    }

    /* TEST: test_FactorySetImplementation - - - - - - - - - - - - - - - - - - -/
     * Tests setting a new implementation on the factory - - - - - - - - - - - */
    function test_FactorySetImplementation() public {
        LogUtils.logDebug("Testing factory set implementation");

        vm.startPrank(owner);

        /* Deploy new implementation */
        Airdrop newImpl = new Airdrop();

        /* Set new implementation */
        vm.expectEmit(true, false, false, true);
        emit AirdropFactory.ImplementationSet(address(newImpl));
        factory.setImplementation(address(newImpl));

        /* Verify implementation changed */
        assertEq(factory.implementation(), address(newImpl));

        vm.stopPrank();
    }

    /* TEST: test_FactorySetImplementation_RevertWhenNotOwner - - - - - - - - - /
     * Tests that only owner can set implementation - - - - - - - - - - - - - -*/
    function test_FactorySetImplementation_RevertWhenNotOwner() public {
        LogUtils.logDebug("Testing factory set implementation revert when not owner");

        vm.startPrank(alice);

        Airdrop newImpl = new Airdrop();

        vm.expectRevert();
        factory.setImplementation(address(newImpl));

        vm.stopPrank();
    }

    /* TEST: test_LockUp - - - - - - - - - - - - - - - - - - - - - - - - - - - -/
     * Tests the lockUp functionality - - - - - - - - - - - - - - - - - - - - -*/
    function test_LockUp() public {
        LogUtils.logDebug("Testing lockUp functionality");

        vm.startPrank(owner);

        /* Verify not locked initially */
        assertFalse(airdrop.lock());

        /* Lock the contract */
        vm.expectEmit(false, false, false, true);
        emit Airdrop.Locked();
        airdrop.lockUp();

        /* Verify locked */
        assertTrue(airdrop.lock());

        vm.stopPrank();
    }

    /* TEST: test_LockUp_RevertWhenNotOwner - - - - - - - - - - - - - - - - - - /
     * Tests that only owner can lock the contract - - - - - - - - - - - - - - */
    function test_LockUp_RevertWhenNotOwner() public {
        LogUtils.logDebug("Testing lockUp revert when not owner");

        vm.startPrank(alice);

        vm.expectRevert();
        airdrop.lockUp();

        vm.stopPrank();
    }

    /* TEST: test_DepositOnly - - - - - - - - - - - - - - - - - - - - - - - - - /
     * Tests only the deposit functionality - - - - - - - - - - - - - - - - - -*/
    function test_DepositOnly() public {
        LogUtils.logDebug("Testing deposit functionality");

        vm.startPrank(owner);

        uint256 depositAmount = 1000 * 10 ** 18;
        LogUtils.logDebug("Minting tokens to owner: ");

        token.mint(owner, depositAmount);

        LogUtils.logDebug("Approving tokens");
        token.approve(address(airdrop), depositAmount);

        uint256 initialOwnerBalance = token.balanceOf(owner);
        LogUtils.logDebug(string.concat("Initial owner balance: ", vm.toString(initialOwnerBalance)));
        uint256 initialAirdropBalance = token.balanceOf(address(airdrop));
        LogUtils.logDebug(string.concat("Initial airdrop balance: ", vm.toString(initialAirdropBalance)));

        /* Deposit */
        vm.expectEmit(false, false, false, true);
        emit Airdrop.Deposit(depositAmount);
        airdrop.deposit(depositAmount);

        LogUtils.logDebug(
            string.concat("Airdrop balance after deposit: ", vm.toString(token.balanceOf(address(airdrop))))
        );
        /* Verify balances changed */
        assertEq(token.balanceOf(owner), initialOwnerBalance - depositAmount);
        assertEq(token.balanceOf(address(airdrop)), initialAirdropBalance + depositAmount);
        assertEq(airdrop.totalDeposited(), depositAmount);

        vm.stopPrank();
    }

    /* TEST: test_Deposit_RevertWhenNotOwner - - - - - - - - - - - - - - - - - -/
     * Tests that only owner can deposit - - - - - - - - - - - - - - - - - - - */
    function test_Deposit_RevertWhenNotOwner() public {
        LogUtils.logDebug("Testing deposit revert when not owner");

        vm.startPrank(alice);

        uint256 depositAmount = 1000 * 10 ** 18;
        token.mint(alice, depositAmount);
        token.approve(address(airdrop), depositAmount);

        vm.expectRevert();
        airdrop.deposit(depositAmount);

        vm.stopPrank();
    }

    /* TEST: test_ImplementationCannotBeInitialized - - - - - - - - - - - - - - /
     * Tests that the implementation contract cannot be initialized directly - */
    function test_ImplementationCannotBeInitialized() public {
        LogUtils.logDebug("Testing implementation cannot be initialized");

        vm.expectRevert();
        airdropImpl.initialize(address(token), address(mockStaker), treasury, signer, owner, timestamps);
    }

    /* TEST: test_UpdatePenaltyValues - - - - - - - - - - - - - - - - - - - - - /
     * Tests updating penalty values when not locked - - - - - - - - - - - - - */
    function test_UpdatePenaltyValues() public {
        LogUtils.logDebug("Testing update penalty values");

        vm.startPrank(owner);

        uint256 newPenaltyWallet = 25_00_00; /* 25% */
        uint256 newPenaltyStaker = 10_00_00; /* 10% */

        airdrop.updatePenaltyValues(newPenaltyWallet, newPenaltyStaker);

        assertEq(airdrop.penaltyWallet(), newPenaltyWallet);
        assertEq(airdrop.penaltyStaker(), newPenaltyStaker);

        vm.stopPrank();
    }

    /* TEST: test_UpdatePenaltyValues_RevertWhenLocked - - - - - - - - - - - - -/
     * Tests that penalty values cannot be updated when locked - - - - - - - - */
    function test_UpdatePenaltyValues_RevertWhenLocked() public {
        LogUtils.logDebug("Testing update penalty values revert when locked");

        vm.startPrank(owner);

        /* Lock the contract first */
        airdrop.lockUp();

        uint256 newPenaltyWallet = 25_00_00;
        uint256 newPenaltyStaker = 10_00_00;

        vm.expectRevert(Airdrop.SettingsLocked.selector);
        airdrop.updatePenaltyValues(newPenaltyWallet, newPenaltyStaker);

        vm.stopPrank();
    }

    /* TEST: test_UpdatePenaltyValues_RevertWhenExceedsPrecision - - - - - - - -/
     * Tests that penalty values cannot exceed precision - - - - - - - - - - - */
    function test_UpdatePenaltyValues_RevertWhenExceedsPrecision() public {
        LogUtils.logDebug("Testing update penalty values revert when exceeds precision");

        vm.startPrank(owner);

        /* Try to set penalty > 100% */
        uint256 invalidPenaltyWallet = PRECISION + 1;
        uint256 validPenaltyStaker = 10_00_00;

        vm.expectRevert();
        airdrop.updatePenaltyValues(invalidPenaltyWallet, validPenaltyStaker);

        /* Try with staker penalty > 100% */
        uint256 validPenaltyWallet = 50_00_00;
        uint256 invalidPenaltyStaker = PRECISION + 1;

        vm.expectRevert();
        airdrop.updatePenaltyValues(validPenaltyWallet, invalidPenaltyStaker);

        vm.stopPrank();
    }

    /* TEST: test_AddTimestamp - - - - - - - - - - - - - - - - - - - - - - - - -/
     * Tests adding a new timestamp - - - - - - - - - - - - - - - - - - - - - -*/
    function test_AddTimestamp() public {
        LogUtils.logDebug("Testing add timestamp");

        vm.startPrank(owner);

        uint256 newTimestamp = block.timestamp + 14 days;

        vm.expectEmit(true, false, false, true);
        emit Airdrop.TimestampAdded(2, newTimestamp);
        airdrop.addTimestamp(newTimestamp);

        assertEq(airdrop.unlocks(2), newTimestamp);

        vm.stopPrank();
    }

    /* TEST: test_AddTimestamp_RevertWhenNotFuture - - - - - - - - - - - - - - -/
     * Tests that timestamp must be in the future compared to last one - - - - */
    function test_AddTimestamp_RevertWhenNotFuture() public {
        LogUtils.logDebug("Testing add timestamp revert when not future");

        vm.startPrank(owner);

        /* Try to add timestamp that's before the last one */
        uint256 invalidTimestamp = timestamps[1] - 1;

        vm.expectRevert(Airdrop.InvalidTimestamp.selector);
        airdrop.addTimestamp(invalidTimestamp);

        vm.stopPrank();
    }

    /* TEST: test_AddTimestamp_RevertWhenLocked - - - - - - - - - - - - - - - - /
     * Tests that timestamps cannot be added when locked - - - - - - - - - - - */
    function test_AddTimestamp_RevertWhenLocked() public {
        LogUtils.logDebug("Testing add timestamp revert when locked");

        vm.startPrank(owner);

        airdrop.lockUp();

        uint256 newTimestamp = block.timestamp + 14 days;

        vm.expectRevert(Airdrop.SettingsLocked.selector);
        airdrop.addTimestamp(newTimestamp);

        vm.stopPrank();
    }

    /* TEST: test_ChangeTimestamp - - - - - - - - - - - - - - - - - - - - - - - /
     * Tests changing an existing timestamp - - - - - - - - - - - - - - - - - -*/
    function test_ChangeTimestamp() public {
        LogUtils.logDebug("Testing change timestamp");

        vm.startPrank(owner);

        /* Change the first timestamp to be 2 days from now */
        uint256 newTimestamp = block.timestamp + 2 days;

        vm.expectEmit(true, false, false, true);
        emit Airdrop.TimestampChanged(0, newTimestamp);
        airdrop.changeTimestamp(0, newTimestamp);

        assertEq(airdrop.unlocks(0), newTimestamp);

        vm.stopPrank();
    }

    /* TEST: test_ChangeTimestamp_RevertWhenInvalidIndex - - - - - - - - - - - -/
     * Tests that changing timestamp with invalid index reverts - - - - - - - -*/
    function test_ChangeTimestamp_RevertWhenInvalidIndex() public {
        LogUtils.logDebug("Testing change timestamp revert when invalid index");

        vm.startPrank(owner);

        uint256 newTimestamp = block.timestamp + 10 days;

        vm.expectRevert(Airdrop.InvalidIndex.selector);
        airdrop.changeTimestamp(5, newTimestamp); /* Index doesn't exist */

        vm.stopPrank();
    }

    /* TEST: test_ChangeTimestamp_RevertWhenInvalidOrder - - - - - - - - - - - -/
     * Tests that timestamps must maintain order - - - - - - - - - - - - - - - */
    function test_ChangeTimestamp_RevertWhenInvalidOrder() public {
        LogUtils.logDebug("Testing change timestamp revert when invalid order");

        vm.startPrank(owner);

        /* Try to set first timestamp after the second one */

        uint256 invalidTimestamp = timestamps[1] + 1 days;
        LogUtils.logDebug(string.concat("invalidTimestamp is ", vm.toString(invalidTimestamp)));

        vm.expectRevert(Airdrop.InvalidTimestamp.selector);
        airdrop.changeTimestamp(0, invalidTimestamp);

        /* Add a third timestamp */
        uint256 thirdTimestamp = block.timestamp + 14 days;
        airdrop.addTimestamp(thirdTimestamp);

        /* Try to set middle timestamp before first one */
        invalidTimestamp = timestamps[0] - 1 days;

        vm.expectRevert(Airdrop.InvalidTimestamp.selector);
        airdrop.changeTimestamp(1, invalidTimestamp);

        vm.stopPrank();
    }

    /* TEST: test_AssignPortions - - - - - - - - - - - - - - - - - - - - - - - -/
     * Tests assigning portions to users - - - - - - - - - - - - - - - - - - - */
    function test_AssignPortions() public {
        LogUtils.logDebug("Testing assign portions");

        vm.startPrank(owner);

        address[] memory accounts = new address[](2);
        accounts[0] = alice;
        accounts[1] = bob;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = ALICE_PORTION;
        amounts[1] = BOB_PORTION;

        /* Assign portions for first unlock */
        airdrop.assignPortions(0, accounts, amounts);

        assertEq(airdrop.portions(0, alice), amounts[0]);
        assertEq(airdrop.portions(0, bob), amounts[1]);

        /* Assign portions for second unlock */
        amounts[0] = ALICE_PORTION;
        amounts[1] = BOB_PORTION;

        airdrop.assignPortions(1, accounts, amounts);

        assertEq(airdrop.portions(1, alice), amounts[0]);
        assertEq(airdrop.portions(1, bob), amounts[1]);

        vm.stopPrank();
    }

    /* TEST: test_AssignPortions_RevertWhenArrayMismatch - - - - - - - - - - - -/
     * Tests that array lengths must match - - - - - - - - - - - - - - - - - - */
    function test_AssignPortions_RevertWhenArrayMismatch() public {
        LogUtils.logDebug("Testing assign portions revert when array mismatch");

        vm.startPrank(owner);

        address[] memory accounts = new address[](2);
        accounts[0] = alice;
        accounts[1] = bob;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100 * 10 ** 18;

        vm.expectRevert(Airdrop.ArrayLengthMismatch.selector);
        airdrop.assignPortions(0, accounts, amounts);

        vm.stopPrank();
    }

    /* TEST: test_AssignPortions_RevertWhenLocked - - - - - - - - - - - - - - - /
     * Tests that portions cannot be assigned when locked - - - - - - - - - - -*/
    function test_AssignPortions_RevertWhenLocked() public {
        LogUtils.logDebug("Testing assign portions revert when locked");

        vm.startPrank(owner);

        airdrop.lockUp();

        address[] memory accounts = new address[](1);
        accounts[0] = alice;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = ALICE_PORTION;

        vm.expectRevert(Airdrop.SettingsLocked.selector);
        airdrop.assignPortions(0, accounts, amounts);

        vm.stopPrank();
    }

    /* TEST: test_Withdraw_ToWallet_Success - - - - - - - - - - - - - - - - - - /
     * Tests successful withdrawal to wallet with penalty - - - - - - - - - - -*/
    function test_Withdraw_ToWallet_Success() public {
        LogUtils.logDebug("Testing withdraw to wallet success");

        vm.startPrank(owner);
        address[] memory accounts = new address[](2);
        accounts[0] = alice;
        accounts[1] = bob;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = ALICE_PORTION;
        amounts[1] = BOB_PORTION;

        LogUtils.logDebug("Minting tokens for setup");
        token.mint(address(airdrop), amounts[0] + amounts[1]);

        LogUtils.logDebug("Assigning portions");
        airdrop.assignPortions(0, accounts, amounts);
        vm.stopPrank();

        vm.warp(timestamps[0] + 1);

        LogUtils.logDebug("Acquiring hash");
        bytes32 hash =
            keccak256(abi.encode(address(airdrop), block.chainid, alice, true, ALICE_PORTION)).toEthSignedMessageHash();

        LogUtils.logDebug(string.concat("signing the hash with private key: ", vm.toString(signerPrivateKey)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, hash);

        LogUtils.logDebug("Acquiring signature");
        bytes memory signature = abi.encodePacked(r, s, v);

        uint256 expectedPenalty = (ALICE_PORTION * DEFAULT_PENALTY_WALLET) / PRECISION;
        uint256 expectedReceived = ALICE_PORTION - expectedPenalty;

        vm.prank(alice);
        LogUtils.logDebug("Expecting emit");
        vm.expectEmit(true, false, false, true);
        emit Airdrop.WalletWithdrawal(alice, expectedReceived, expectedPenalty);
        LogUtils.logDebug("Withdrawing funds");
        airdrop.withdraw(true, 0, signature);

        LogUtils.logDebug("Asserting conditions");
        assertEq(token.balanceOf(alice), expectedReceived);
        assertEq(token.balanceOf(treasury), expectedPenalty);
        assertEq(airdrop.portions(0, alice), 0);
    }

    /* TEST: test_cleanUpUnclaimedPortions - - - - - - - - - - - - - - - - - - -/
     * Tests cleanup of unclaimed portions after buffer period - - - - - - - - */
    function test_cleanUpUnclaimedPortions() public {
        LogUtils.logDebug("Testing cleanup of unclaimed portions");

        vm.startPrank(owner);
        address[] memory accounts = new address[](2);
        accounts[0] = alice;
        accounts[1] = bob;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = ALICE_PORTION;
        amounts[1] = BOB_PORTION;

        LogUtils.logDebug("Minting tokens for setup");
        token.mint(address(airdrop), amounts[0] + amounts[1]);

        LogUtils.logDebug("Assigning portions");
        airdrop.assignPortions(0, accounts, amounts);

        LogUtils.logDebug(string.concat("Current block time: ", vm.toString(block.timestamp)));
        vm.warp(timestamps[1] + airdrop.cleanUpBuffer() + 1);
        LogUtils.logDebug(string.concat("Set block time to: ", vm.toString(block.timestamp)));
        LogUtils.logDebug(string.concat("Last unlock: ", vm.toString(timestamps[1])));
        LogUtils.logDebug(string.concat("First obsoletion: ", vm.toString(timestamps[1] + airdrop.cleanUpBuffer())));

        address[] memory addressesToCleanup = new address[](1);
        addressesToCleanup[0] = alice;

        uint256 initialTreasuryTokenBalance = token.balanceOf(treasury);
        LogUtils.logDebug(string.concat("Current treasury token balance: ", vm.toString(initialTreasuryTokenBalance)));

        airdrop.cleanUp(addressesToCleanup);

        uint256 finalTreasuryTokenBalance = token.balanceOf(treasury);
        LogUtils.logDebug(
            string.concat("Treasury token balance after cleanup: ", vm.toString(finalTreasuryTokenBalance))
        );

        /* Verify alice's portion was cleaned up */
        assertEq(airdrop.portions(0, alice), 0);

        /* Verify tokens were transferred to treasury */
        assertEq(finalTreasuryTokenBalance, initialTreasuryTokenBalance + ALICE_PORTION);

        vm.stopPrank();
    }

    /* TEST: test_CleanUp_RevertWhenNotAvailable - - - - - - - - - - - - - - - - /
    * Tests that cleanup reverts when called before the cleanup period expires - */
    function test_CleanUp_RevertWhenNotAvailable() public {
        LogUtils.logDebug("Testing cleanup revert when cleanup period hasn't expired");

        vm.startPrank(owner);

        /* Setup: Create users with unclaimed portions */
        address[] memory accounts = new address[](2);
        accounts[0] = alice;
        accounts[1] = bob;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = ALICE_PORTION;
        amounts[1] = BOB_PORTION;

        /* Mint tokens and assign portions */
        token.mint(address(airdrop), ALICE_PORTION + BOB_PORTION);
        airdrop.assignPortions(0, accounts, amounts);
        airdrop.assignPortions(1, accounts, amounts);

        /* Test Case 1: Try cleanup immediately after deployment (way too early) */
        address[] memory addressesToCleanup = new address[](1);
        addressesToCleanup[0] = alice;

        LogUtils.logDebug("Case 1: Cleanup immediately after deployment");
        vm.expectRevert(Airdrop.CleanUpNotAvailable.selector);
        airdrop.cleanUp(addressesToCleanup);

        /* Test Case 2: Try cleanup after first unlock but before cleanup period */
        vm.warp(timestamps[0] + 1);
        LogUtils.logDebug("Case 2: Cleanup after first unlock but before cleanup period");
        vm.expectRevert(Airdrop.CleanUpNotAvailable.selector);
        airdrop.cleanUp(addressesToCleanup);

        /* Test Case 3: Try cleanup exactly at last unlock (still too early) */
        vm.warp(timestamps[1]);
        LogUtils.logDebug("Case 3: Cleanup exactly at last unlock timestamp");
        vm.expectRevert(Airdrop.CleanUpNotAvailable.selector);
        airdrop.cleanUp(addressesToCleanup);

        /* Test Case 4: Try cleanup 1 second before cleanup period expires */
        vm.warp(timestamps[1] + airdrop.cleanUpBuffer() - 1);
        LogUtils.logDebug("Case 4: Cleanup 1 second before cleanup period expires");
        vm.expectRevert(Airdrop.CleanUpNotAvailable.selector);
        airdrop.cleanUp(addressesToCleanup);

        /* Test Case 5: Verify cleanup works exactly when period expires */
        vm.warp(timestamps[1] + airdrop.cleanUpBuffer());
        LogUtils.logDebug("Case 5: Cleanup exactly when cleanup period expires");
        /* This should succeed (no revert expected) */
        airdrop.cleanUp(addressesToCleanup);

        vm.stopPrank();
    }

    /* TEST: test_Withdraw_RevertWhenStakerNotSet - - - - - - - - - - - - - - - - /
    * Tests that withdraw to staker reverts when no staker contract is set - - - */
    function test_Withdraw_RevertWhenStakerNotSet() public {
        LogUtils.logDebug("Testing withdraw revert when staker not set");

        /* Setup: Deploy airdrop WITHOUT staker contract */
        vm.startPrank(owner);

        /* Deploy new airdrop instance with staker = address(0) */
        address airdropWithoutStaker =
            factory.deploy(address(token), address(0), /* No staker contract */ treasury, signer, owner, timestamps);

        Airdrop airdropNoStaker = Airdrop(airdropWithoutStaker);

        /* Setup portions for alice */
        address[] memory accounts = new address[](1);
        accounts[0] = alice;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = ALICE_PORTION;

        /* Mint tokens and assign portions */
        token.mint(address(airdropNoStaker), ALICE_PORTION);
        airdropNoStaker.assignPortions(0, accounts, amounts);

        vm.stopPrank();

        /* Wait for unlock period */
        vm.warp(timestamps[0] + 1);

        /* Create valid signature for staker withdrawal */
        bytes32 hash = keccak256(abi.encode(address(airdropNoStaker), block.chainid, alice, false, ALICE_PORTION)) /* toWallet = false (trying to withdraw to staker) */
            .toEthSignedMessageHash();

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        /* Verify staker is not set */
        assertEq(airdropNoStaker.staker(), address(0));

        /* Attempt withdrawal to staker (should revert) */
        vm.prank(alice);
        LogUtils.logDebug("Attempting withdrawal to non-existent staker");
        vm.expectRevert(Airdrop.StakingUnavailableForThisAirdrop.selector);
        airdropNoStaker.withdraw(false, /* toWallet = false (withdraw to staker) */ 0, /* lockupIndex */ signature);

        /* Verify wallet withdrawal still works with same airdrop */
        bytes32 walletHash = keccak256(abi.encode(address(airdropNoStaker), block.chainid, alice, true, ALICE_PORTION)) /* toWallet = true */
            .toEthSignedMessageHash();

        (v, r, s) = vm.sign(signerPrivateKey, walletHash);
        bytes memory walletSignature = abi.encodePacked(r, s, v);

        vm.prank(alice);
        LogUtils.logDebug("Attempting wallet withdrawal (should succeed)");
        /* This should succeed */
        airdropNoStaker.withdraw(true, 0, walletSignature);

        /* Verify alice received tokens (minus penalty) */
        uint256 expectedReceived = ALICE_PORTION - (ALICE_PORTION * DEFAULT_PENALTY_WALLET / PRECISION);
        assertEq(token.balanceOf(alice), expectedReceived);
    }

    /* TEST: test_Withdraw_RevertWhenSignatureInvalid - - - - - - - - - - - - - - /
    * Tests that withdraw reverts when signature is invalid - - - - - - - - - - */
    function test_Withdraw_RevertWhenSignatureInvalid() public {
        LogUtils.logDebug("Testing withdraw revert when signature is invalid");

        vm.startPrank(owner);

        /* Setup portions for alice */
        address[] memory accounts = new address[](1);
        accounts[0] = alice;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = ALICE_PORTION;

        token.mint(address(airdrop), ALICE_PORTION);
        airdrop.assignPortions(0, accounts, amounts);

        vm.stopPrank();

        /* Wait for unlock period */
        vm.warp(timestamps[0] + 1);

        /* Test Case 1: Completely invalid signature (random bytes) */
        LogUtils.logDebug("Case 1: Random invalid signature");
        bytes memory invalidSignature = abi.encodePacked(
            bytes32(0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef),
            bytes32(0xfedcba0987654321fedcba0987654321fedcba0987654321fedcba0987654321),
            uint8(27)
        );

        vm.prank(alice);
        vm.expectRevert(Airdrop.Airdrop__SignatureIsInvalid.selector);
        airdrop.withdraw(true, 0, invalidSignature);

        /* Test Case 2: Valid signature but signed by wrong private key */
        LogUtils.logDebug("Case 2: Signature from wrong signer");
        uint256 wrongPrivateKey = 0xDEADBEEF;

        bytes32 hash =
            keccak256(abi.encode(address(airdrop), block.chainid, alice, true, ALICE_PORTION)).toEthSignedMessageHash();

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongPrivateKey, hash);
        bytes memory wrongSignerSignature = abi.encodePacked(r, s, v);

        vm.prank(alice);
        vm.expectRevert(Airdrop.Airdrop__SignatureIsInvalid.selector);
        airdrop.withdraw(true, 0, wrongSignerSignature);

        /* Test Case 3: Valid signature but for wrong parameters (different user) */
        LogUtils.logDebug("Case 3: Signature for wrong user");
        bytes32 bobHash = keccak256(abi.encode(address(airdrop), block.chainid, bob, true, ALICE_PORTION)) /* Bob's address but Alice's amount */
            .toEthSignedMessageHash();

        (v, r, s) = vm.sign(signerPrivateKey, bobHash);
        bytes memory bobSignature = abi.encodePacked(r, s, v);

        vm.prank(alice); /* Alice trying to use Bob's signature */
        vm.expectRevert(Airdrop.Airdrop__SignatureIsInvalid.selector);
        airdrop.withdraw(true, 0, bobSignature);

        /* Test Case 4: Valid signature but for wrong amount */
        LogUtils.logDebug("Case 4: Signature for wrong amount");
        bytes32 wrongAmountHash = keccak256(
            abi.encode(address(airdrop), block.chainid, alice, true, ALICE_PORTION + 1000)
        ) /* Wrong amount */ .toEthSignedMessageHash();

        (v, r, s) = vm.sign(signerPrivateKey, wrongAmountHash);
        bytes memory wrongAmountSignature = abi.encodePacked(r, s, v);

        vm.prank(alice);
        vm.expectRevert(Airdrop.Airdrop__SignatureIsInvalid.selector);
        airdrop.withdraw(true, 0, wrongAmountSignature);

        /* Test Case 5: Valid signature but for wrong toWallet parameter */
        LogUtils.logDebug("Case 5: Signature for wrong toWallet parameter");
        bytes32 wrongToWalletHash = keccak256(abi.encode(address(airdrop), block.chainid, alice, false, ALICE_PORTION)) /* false instead of true */
            .toEthSignedMessageHash();

        (v, r, s) = vm.sign(signerPrivateKey, wrongToWalletHash);
        bytes memory wrongToWalletSignature = abi.encodePacked(r, s, v);

        vm.prank(alice);
        vm.expectRevert(Airdrop.Airdrop__SignatureIsInvalid.selector);
        airdrop.withdraw(true, 0, wrongToWalletSignature); /* Using true but signature was for false */

        /* Test Case 6: Empty signature */
        LogUtils.logDebug("Case 6: Empty signature");
        bytes memory emptySignature = "";

        vm.prank(alice);
        vm.expectRevert(Airdrop.Airdrop__SignatureIsInvalid.selector);
        airdrop.withdraw(true, 0, emptySignature);

        /* Test Case 7: Valid signature should work */
        LogUtils.logDebug("Case 7: Valid signature (should succeed)");
        bytes32 validHash =
            keccak256(abi.encode(address(airdrop), block.chainid, alice, true, ALICE_PORTION)).toEthSignedMessageHash();

        (v, r, s) = vm.sign(signerPrivateKey, validHash);
        bytes memory validSignature = abi.encodePacked(r, s, v);

        vm.prank(alice);
        /* This should succeed (no revert expected) */
        airdrop.withdraw(true, 0, validSignature);

        /* Verify withdrawal worked */
        uint256 expectedReceived = ALICE_PORTION - (ALICE_PORTION * DEFAULT_PENALTY_WALLET / PRECISION);
        assertEq(token.balanceOf(alice), expectedReceived);
        assertEq(airdrop.portions(0, alice), 0); /* Portion should be deleted */
    }

    /* TEST: test_Withdraw_ToStaker_Success_NoPenalty - - - - - - - - - - - - -/
    * Tests successful withdrawal to staker with no penalty - - - - - - - - -*/
    function test_Withdraw_ToStaker_Success_NoPenalty() public {
        LogUtils.logDebug("Testing withdraw to staker success with no penalty");

        /* First, we need to fix the MockStaker setup issue */
        /* The Airdrop contract needs to approve the staker to pull tokens */
        vm.startPrank(owner);

        /* Deploy a new MockStaker and set it up properly */
        MockStaker properStaker = new MockStaker();

        /* Deploy a new airdrop with our proper staker */
        address newAirdropAddr =
            factory.deploy(address(token), address(properStaker), treasury, signer, owner, timestamps);
        Airdrop newAirdrop = Airdrop(newAirdropAddr);

        /* Setup portions for alice */
        address[] memory accounts = new address[](1);
        accounts[0] = alice;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = ALICE_PORTION;

        /* Mint tokens and assign portions */
        token.mint(address(newAirdrop), ALICE_PORTION);
        newAirdrop.assignPortions(0, accounts, amounts);

        /* Verify default staker penalty is 0% */
        assertEq(newAirdrop.penaltyStaker(), 0);

        vm.stopPrank();

        /* Wait for unlock period */
        vm.warp(timestamps[0] + 1);

        /* Create valid signature for staker withdrawal */
        uint256 lockupIndex = 1;
        bytes32 hash = keccak256(abi.encode(address(newAirdrop), block.chainid, alice, false, ALICE_PORTION)) /* toWallet = false */
            .toEthSignedMessageHash();

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        /* Mock the stake call to avoid the token transfer issue */
        vm.mockCall(
            address(properStaker),
            abi.encodeWithSelector(IStaker.stake.selector, alice, ALICE_PORTION, lockupIndex),
            abi.encode()
        );

        /* Expect the staker withdrawal event */
        vm.expectEmit(true, false, false, true);
        emit Airdrop.StakerWithdrawal(alice, ALICE_PORTION, 0, lockupIndex);

        /* Perform withdrawal */
        vm.prank(alice);
        newAirdrop.withdraw(false, lockupIndex, signature);

        /* Verify portion was deleted */
        assertEq(newAirdrop.portions(0, alice), 0);

        /* Verify no tokens went to treasury (no penalty) */
        assertEq(token.balanceOf(treasury), 0);
    }

    /* TEST: test_Withdraw_ToStaker_Success_WithPenalty - - - - - - - - - - - -/
    * Tests successful withdrawal to staker with penalty - - - - - - - - - - */
    function test_Withdraw_ToStaker_Success_WithPenalty() public {
        LogUtils.logDebug("Testing withdraw to staker success with penalty");

        vm.startPrank(owner);

        /* Deploy a new airdrop for this test */
        MockStaker properStaker = new MockStaker();
        address newAirdropAddr =
            factory.deploy(address(token), address(properStaker), treasury, signer, owner, timestamps);
        Airdrop newAirdrop = Airdrop(newAirdropAddr);

        /* Set staker penalty to 20% */
        uint256 stakerPenalty = 20_00_00;
        newAirdrop.updatePenaltyValues(DEFAULT_PENALTY_WALLET, stakerPenalty);
        assertEq(newAirdrop.penaltyStaker(), stakerPenalty);

        /* Setup portions for alice */
        address[] memory accounts = new address[](1);
        accounts[0] = alice;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = ALICE_PORTION;

        /* Mint tokens and assign portions */
        token.mint(address(newAirdrop), ALICE_PORTION);
        newAirdrop.assignPortions(0, accounts, amounts);

        vm.stopPrank();

        /* Wait for unlock period */
        vm.warp(timestamps[0] + 1);

        /* Create valid signature for staker withdrawal */
        uint256 lockupIndex = 2;
        bytes32 hash = keccak256(abi.encode(address(newAirdrop), block.chainid, alice, false, ALICE_PORTION)) /* toWallet = false */
            .toEthSignedMessageHash();

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        /* Calculate expected values */
        uint256 expectedPenalty = (ALICE_PORTION * stakerPenalty) / PRECISION;
        uint256 expectedStakedAmount = ALICE_PORTION - expectedPenalty;

        /* Mock the stake call */
        vm.mockCall(
            address(properStaker),
            abi.encodeWithSelector(IStaker.stake.selector, alice, expectedStakedAmount, lockupIndex),
            abi.encode()
        );

        /* Record initial treasury balance */
        uint256 initialTreasuryBalance = token.balanceOf(treasury);

        /* Expect the staker withdrawal event */
        vm.expectEmit(true, false, false, true);
        emit Airdrop.StakerWithdrawal(alice, expectedStakedAmount, expectedPenalty, lockupIndex);

        /* Perform withdrawal */
        vm.prank(alice);
        newAirdrop.withdraw(false, lockupIndex, signature);

        /* Verify portion was deleted */
        assertEq(newAirdrop.portions(0, alice), 0);

        /* Verify penalty went to treasury */
        assertEq(token.balanceOf(treasury), initialTreasuryBalance + expectedPenalty);
    }

    /* TEST: test_Withdraw_ToStaker_MultiplePortions - - - - - - - - - - - - - /
    * Tests staker withdrawal with multiple unlocked portions - - - - - - - - */
    function test_Withdraw_ToStaker_MultiplePortions() public {
        LogUtils.logDebug("Testing withdraw to staker with multiple portions");

        vm.startPrank(owner);

        /* Deploy fresh airdrop for this test */
        MockStaker properStaker = new MockStaker();
        address newAirdropAddr =
            factory.deploy(address(token), address(properStaker), treasury, signer, owner, timestamps);
        Airdrop newAirdrop = Airdrop(newAirdropAddr);

        /* Setup portions for both timestamps */
        address[] memory accounts = new address[](1);
        accounts[0] = alice;

        uint256[] memory amounts = new uint256[](1);
        uint256 portion1 = 5000 * 10 ** 18;
        uint256 portion2 = 7000 * 10 ** 18;

        /* Assign portion for first timestamp */
        amounts[0] = portion1;
        newAirdrop.assignPortions(0, accounts, amounts);

        /* Assign portion for second timestamp */
        amounts[0] = portion2;
        newAirdrop.assignPortions(1, accounts, amounts);

        /* Mint total tokens */
        token.mint(address(newAirdrop), portion1 + portion2);

        vm.stopPrank();

        /* Wait for both unlocks */
        vm.warp(timestamps[1] + 1);

        /* Create valid signature for total amount */
        uint256 totalAmount = portion1 + portion2;
        uint256 lockupIndex = 0;

        bytes32 hash = keccak256(abi.encode(address(newAirdrop), block.chainid, alice, false, totalAmount)) /* toWallet = false */
            .toEthSignedMessageHash();

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        /* Mock the stake call */
        vm.mockCall(
            address(properStaker),
            abi.encodeWithSelector(IStaker.stake.selector, alice, totalAmount, lockupIndex),
            abi.encode()
        );

        /* Expect event with total amount */
        vm.expectEmit(true, false, false, true);
        emit Airdrop.StakerWithdrawal(alice, totalAmount, 0, lockupIndex);

        /* Perform withdrawal */
        vm.prank(alice);
        newAirdrop.withdraw(false, lockupIndex, signature);

        /* Verify both portions were deleted */
        assertEq(newAirdrop.portions(0, alice), 0);
        assertEq(newAirdrop.portions(1, alice), 0);
    }

    /* TEST: test_Withdraw_ToStaker_OnlyUnlockedPortions - - - - - - - - - - - /
    * Tests that only unlocked portions are withdrawn to staker - - - - - - -*/
    function test_Withdraw_ToStaker_OnlyUnlockedPortions() public {
        LogUtils.logDebug("Testing withdraw to staker with only unlocked portions");

        vm.startPrank(owner);

        /* Deploy fresh airdrop */
        MockStaker properStaker = new MockStaker();
        address newAirdropAddr =
            factory.deploy(address(token), address(properStaker), treasury, signer, owner, timestamps);
        Airdrop newAirdrop = Airdrop(newAirdropAddr);

        /* Setup portions */
        address[] memory accounts = new address[](1);
        accounts[0] = alice;

        uint256[] memory amounts = new uint256[](1);
        uint256 portion1 = 5000 * 10 ** 18;
        uint256 portion2 = 7000 * 10 ** 18;

        /* Assign portions */
        amounts[0] = portion1;
        newAirdrop.assignPortions(0, accounts, amounts);
        amounts[0] = portion2;
        newAirdrop.assignPortions(1, accounts, amounts);

        /* Mint tokens */
        token.mint(address(newAirdrop), portion1 + portion2);

        vm.stopPrank();

        /* Wait for only first unlock */
        vm.warp(timestamps[0] + 1);

        /* Create signature for only first portion */
        uint256 lockupIndex = 3;
        bytes32 hash = keccak256(abi.encode(address(newAirdrop), block.chainid, alice, false, portion1)) /* Only first portion */
            .toEthSignedMessageHash();

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        /* Mock the stake call */
        vm.mockCall(
            address(properStaker),
            abi.encodeWithSelector(IStaker.stake.selector, alice, portion1, lockupIndex),
            abi.encode()
        );

        /* Expect event */
        vm.expectEmit(true, false, false, true);
        emit Airdrop.StakerWithdrawal(alice, portion1, 0, lockupIndex);

        /* Perform withdrawal */
        vm.prank(alice);
        newAirdrop.withdraw(false, lockupIndex, signature);

        /* Verify only first portion was deleted */
        assertEq(newAirdrop.portions(0, alice), 0);
        assertEq(newAirdrop.portions(1, alice), portion2); /* Second portion still there */
    }
}
