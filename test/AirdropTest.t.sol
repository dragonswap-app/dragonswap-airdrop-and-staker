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

    // Updated to match contract precision
    uint256 constant PRECISION = 1_00_00;
    uint256 constant DEFAULT_STAKER_FEE = 50_00; // 50% fee from staker

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

        mockStaker.setTreasury(treasury);
        mockStaker.setFee(DEFAULT_STAKER_FEE); // Set default fee
        mockStaker.setToken(address(token)); // Set token address

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
        assertFalse(airdrop.isLocked());
        // penaltyWallet and penaltyStaker are not initialized in the contract
        assertEq(airdrop.penaltyWallet(), 0);
        assertEq(airdrop.penaltyStaker(), 0);
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
        assertFalse(airdrop.isLocked());

        /* Lock the contract */
        vm.expectEmit(false, false, false, true);
        emit Airdrop.Locked();
        airdrop.lockUp();

        /* Verify locked - FIXED: should be assertTrue */
        assertTrue(airdrop.isLocked());

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

    /* TEST: test_LockUp_RevertWhenAlreadyLocked - - - - - - - - - - - - - - - - /
     * Tests that contract cannot be locked twice - - - - - - - - - - - - - - -*/
    function test_LockUp_RevertWhenAlreadyLocked() public {
        LogUtils.logDebug("Testing lockUp revert when already locked");

        vm.startPrank(owner);

        // Lock once
        airdrop.lockUp();
        assertTrue(airdrop.isLocked());

        // Try to lock again
        vm.expectRevert(Airdrop.AlreadyLocked.selector);
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
        assertEq(airdrop.totalDepositedForDistribution(), depositAmount);

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

        // Updated penalty calculation based on contract implementation
        uint256 expectedPenalty = (ALICE_PORTION * DEFAULT_STAKER_FEE) / PRECISION;
        uint256 expectedReceived = ALICE_PORTION - expectedPenalty;

        vm.prank(alice);
        LogUtils.logDebug("Expecting emit");
        vm.expectEmit(true, false, false, true);
        emit Airdrop.WalletWithdrawal(alice, expectedReceived, expectedPenalty);
        LogUtils.logDebug("Withdrawing funds");
        airdrop.withdraw(true, false, signature); // Updated to match function signature

        LogUtils.logDebug("Asserting conditions");
        assertEq(token.balanceOf(alice), expectedReceived);
        // Penalty goes to staker contract, not treasury based on contract implementation
        assertEq(token.balanceOf(address(treasury)), expectedPenalty);
        assertEq(airdrop.portions(0, alice), 0);
    }

    /* TEST: test_Withdraw_ToStaker_Success - - - - - - - - - - - - - - - - - - /
     * Tests successful withdrawal to staker - - - - - - - - - - - - - - - - - */
    function test_Withdraw_ToStaker_Success() public {
        LogUtils.logDebug("Testing withdraw to staker success");

        vm.startPrank(owner);
        address[] memory accounts = new address[](1);
        accounts[0] = alice;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = ALICE_PORTION;

        token.mint(address(airdrop), ALICE_PORTION);
        airdrop.assignPortions(0, accounts, amounts);
        vm.stopPrank();

        vm.warp(timestamps[0] + 1);

        bytes32 hash =
            keccak256(abi.encode(address(airdrop), block.chainid, alice, false, ALICE_PORTION)).toEthSignedMessageHash();

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.prank(alice);
        vm.expectEmit(true, false, false, true);
        emit Airdrop.StakerWithdrawal(alice, ALICE_PORTION, true); // Updated event signature
        airdrop.withdraw(false, true, signature); // toWallet=false, locking=true

        // Verify portion was deleted
        assertEq(airdrop.portions(0, alice), 0);
        // Verify tokens went to staker
        assertEq(token.balanceOf(address(mockStaker)), ALICE_PORTION);
    }

    /* TEST: test_Withdraw_RevertWhenTotalZero - - - - - - - - - - - - - - - - - /
     * Tests withdrawal reverts when no unlocked portions available - - - - - -*/
    function test_Withdraw_RevertWhenTotalZero() public {
        LogUtils.logDebug("Testing withdraw revert when total is zero");

        vm.startPrank(owner);
        address[] memory accounts = new address[](1);
        accounts[0] = alice;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = ALICE_PORTION;

        token.mint(address(airdrop), ALICE_PORTION);
        airdrop.assignPortions(0, accounts, amounts);
        vm.stopPrank();

        // Don't warp past unlock time, so no portions are available

        bytes32 hash = keccak256(abi.encode(address(airdrop), block.chainid, alice, true, 0)).toEthSignedMessageHash();

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.prank(alice);
        vm.expectRevert(Airdrop.TotalZero.selector);
        airdrop.withdraw(true, false, signature);
    }

    /* TEST: test_Withdraw_RevertWhenSignatureInvalid - - - - - - - - - - - - - /
     * Tests withdrawal reverts when signature is invalid - - - - - - - - - - -*/
    function test_Withdraw_RevertWhenSignatureInvalid() public {
        LogUtils.logDebug("Testing withdraw revert when signature is invalid");

        vm.startPrank(owner);
        address[] memory accounts = new address[](1);
        accounts[0] = alice;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = ALICE_PORTION;

        token.mint(address(airdrop), ALICE_PORTION);
        airdrop.assignPortions(0, accounts, amounts);
        vm.stopPrank();

        vm.warp(timestamps[0] + 1);

        // Create invalid signature
        bytes memory invalidSignature = abi.encodePacked(
            bytes32(0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef),
            bytes32(0xfedcba0987654321fedcba0987654321fedcba0987654321fedcba0987654321),
            uint8(27)
        );

        vm.prank(alice);
        vm.expectRevert(Airdrop.SignatureInvalid.selector);
        airdrop.withdraw(true, false, invalidSignature);
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

        address[] memory accounts = new address[](1);
        accounts[0] = alice;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = ALICE_PORTION;

        token.mint(address(airdrop), ALICE_PORTION);
        airdrop.assignPortions(0, accounts, amounts);

        address[] memory addressesToCleanup = new address[](1);
        addressesToCleanup[0] = alice;

        // Try cleanup before period expires
        vm.expectRevert(Airdrop.CleanUpNotAvailable.selector);
        airdrop.cleanUp(addressesToCleanup);

        vm.stopPrank();
    }

    /* TEST: test_Initialize_RevertWhenTokenZeroAddress - - - - - - - - - - - - /
     * Tests that initialization reverts when token address is zero - - - - - */
    function test_Initialize_RevertWhenTokenZeroAddress() public {
        LogUtils.logDebug("Testing initialize revert when token is zero address");

        vm.startPrank(owner);

        vm.expectRevert();
        factory.deploy(
            address(0), // Zero token address
            address(mockStaker),
            treasury,
            signer,
            owner,
            timestamps
        );

        vm.stopPrank();
    }

    /* TEST: test_Initialize_RevertWhenStakerZeroAddress - - - - - - - - - - - - /
     * Tests that initialization reverts when staker address is zero - - - - - */
    function test_Initialize_RevertWhenStakerZeroAddress() public {
        LogUtils.logDebug("Testing initialize revert when staker is zero address");

        vm.startPrank(owner);

        vm.expectRevert();
        factory.deploy(
            address(token),
            address(0), // Zero staker address
            treasury,
            signer,
            owner,
            timestamps
        );

        vm.stopPrank();
    }

    /* TEST: test_Initialize_RevertWhenTreasuryZeroAddress - - - - - - - - - - - /
     * Tests that initialization reverts when treasury address is zero - - - - */
    function test_Initialize_RevertWhenTreasuryZeroAddress() public {
        LogUtils.logDebug("Testing initialize revert when treasury is zero address");

        vm.startPrank(owner);

        vm.expectRevert();
        factory.deploy(
            address(token),
            address(mockStaker),
            address(0), // Zero treasury address
            signer,
            owner,
            timestamps
        );

        vm.stopPrank();
    }

    /* TEST: test_Initialize_RevertWhenSignerZeroAddress - - - - - - - - - - - - /
     * Tests that initialization reverts when signer address is zero - - - - - */
    function test_Initialize_RevertWhenSignerZeroAddress() public {
        LogUtils.logDebug("Testing initialize revert when signer is zero address");

        vm.startPrank(owner);

        vm.expectRevert();
        factory.deploy(
            address(token),
            address(mockStaker),
            treasury,
            address(0), // Zero signer address
            owner,
            timestamps
        );

        vm.stopPrank();
    }

    /* TEST: test_Initialize_RevertWhenInvalidTimestampOrder - - - - - - - - - - /
     * Tests that initialization reverts when timestamps are not in order - - -*/
    function test_Initialize_RevertWhenInvalidTimestampOrder() public {
        LogUtils.logDebug("Testing initialize revert when timestamps not in order");

        vm.startPrank(owner);

        uint256[] memory invalidTimestamps = new uint256[](3);
        invalidTimestamps[0] = block.timestamp + 7 days;
        invalidTimestamps[1] = block.timestamp + 1 days; // Invalid: earlier than previous
        invalidTimestamps[2] = block.timestamp + 14 days;

        vm.expectRevert();
        factory.deploy(address(token), address(mockStaker), treasury, signer, owner, invalidTimestamps);

        vm.stopPrank();
    }
}
