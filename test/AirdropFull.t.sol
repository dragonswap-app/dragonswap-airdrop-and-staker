// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {Airdrop} from "src/Airdrop.sol";
import {AirdropFactory} from "src/AirdropFactory.sol";
import {Staker} from "src/Staker.sol";
import {LogUtils} from "test/utils/LogUtils.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {IStaker} from "src/interfaces/IStaker.sol";

/* NOTE: These tests do not check common attack vectors like signatures and reentrancy */
contract AirdropFullTest is Test {
    using MessageHashUtils for bytes32;

    address public alice = address(0xA11CE);
    address public bob = address(0xB0B);

    uint256 public constant ALICE_PORTION = 10_000 * 10 ** 18;
    uint256 public constant BOB_PORTION = 20_000 * 10 ** 18;

    uint256 public signerPrivateKey = 0x123456789;
    address public signer = vm.addr(signerPrivateKey);

    uint256 constant PRECISION = 1_00_00;
    uint256 constant MINIMUM_DEPOSIT = 5 wei;
    uint256 constant DEFAULT_STAKER_FEE = 50_00; // 50% fee from staker
    uint256 CENTURY22TIMESTAMP = 400102528271;

    Airdrop public airdropImpl;
    AirdropFactory public factory;
    Airdrop public airdrop;
    ERC20Mock public token;
    Staker public staker;

    address public owner = makeAddr("owner");
    address public treasury = makeAddr("treasury");

    uint256[] public timestamps;

    /* TEST: setUp - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - /
     * Pretend to be the owner address, create a mock token and an airdrop, - - /
     * set up two timestamps for dates, initialize the airdrop factory  - - - -*/
    function setUp() public {
        LogUtils.logInfo("Instantiating a mock token");
        token = new ERC20Mock();

        LogUtils.logInfo("Instantiating a mock staker");

        address[] memory rewardTokens = new address[](1);
        rewardTokens[0] = address(2);
        vm.prank(owner);
        staker = new Staker(owner, address(token), treasury, MINIMUM_DEPOSIT, DEFAULT_STAKER_FEE, rewardTokens);

        LogUtils.logInfo("Instantiating an Airdrop implementation");
        airdropImpl = new Airdrop();

        LogUtils.logInfo("Instantiating an Airdrop Factory");
        factory = new AirdropFactory(address(airdropImpl), owner);

        LogUtils.logInfo("Pushing timestamps");
        timestamps.push(block.timestamp + 1 days);
        timestamps.push(block.timestamp + 7 days);

        LogUtils.logInfo("Initializing airdrop with following values:");
        LogUtils.logInfo(string.concat("token addr:\t\t", vm.toString(address(token))));
        LogUtils.logInfo(string.concat("mock staker:\t", vm.toString(address(staker))));
        LogUtils.logInfo(string.concat("treasury addr:\t", vm.toString(treasury)));
        LogUtils.logInfo(string.concat("signer addr:\t", vm.toString(signer)));
        LogUtils.logInfo(string.concat("owner:\t\t", vm.toString(owner)));
        LogUtils.logInfo(string.concat("timestamp 1\t\t", vm.toString(timestamps[0])));
        LogUtils.logInfo(string.concat("timestamp 2\t\t", vm.toString(timestamps[1])));

        LogUtils.logInfo("Factory deploying...");
        vm.prank(owner);
        address airdropAddr = factory.deploy(address(token), address(staker), signer, owner, timestamps);

        LogUtils.logInfo("Setting airdrop to factory deploy address");
        airdrop = Airdrop(airdropAddr);
    }

    /* TEST: test_Initialize - - - - - - - - - - - - - - - - - - - - - - - - - -/
     * Asserts the validity of values after instantiation- - - - - - - - - - - */
    function test_Initialize() public view {
        LogUtils.logDebug("Starting initialization assertion test");
        assertEq(address(airdrop.token()), address(token));
        assertEq(airdrop.signer(), signer);
        assertEq(airdrop.staker(), address(staker));
        assertEq(airdrop.owner(), owner);
        assertEq(airdrop.unlocks(0), timestamps[0]);
        assertEq(airdrop.unlocks(1), timestamps[1]);
        assertFalse(airdrop.isLocked());
        /* NOTE: penaltyWallet and penaltyStaker are */
        /* not initialized in the contract           */
    }

    /* TEST: test_FactoryDeployment - - - - - - - - - - - - - - - - - - - - - - /
     * Tests the factory deployment functionality - - - - - - - - - - - - - - -*/
    function test_FactoryDeployment() public view {
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

        /* Deploy new implementation */
        Airdrop newImpl = new Airdrop();

        /* Set new implementation */
        vm.expectEmit();
        emit AirdropFactory.ImplementationSet(address(newImpl));
        vm.prank(owner);
        factory.setImplementation(address(newImpl));

        /* Verify implementation changed */
        assertEq(factory.implementation(), address(newImpl));
    }

    /* TEST: test_FactorySetImplementation_RevertWhenNotOwner - - - - - - - - - /
     * Tests that only owner can set implementation - - - - - - - - - - - - - -*/
    function test_FactorySetImplementation_RevertWhenNotOwner() public {
        LogUtils.logDebug("Testing factory set implementation revert when not owner");

        Airdrop newImpl = new Airdrop();

        vm.expectRevert();
        vm.prank(alice);
        factory.setImplementation(address(newImpl));
    }

    /* TEST: test_LockUp - - - - - - - - - - - - - - - - - - - - - - - - - - - -/
     * Tests the lockUp functionality - - - - - - - - - - - - - - - - - - - - -*/
    function test_LockUp() public {
        LogUtils.logDebug("Testing lockUp functionality");

        /* Verify not locked initially */
        assertFalse(airdrop.isLocked());

        /* Lock the contract */
        vm.expectEmit();
        emit Airdrop.Locked();
        vm.prank(owner);
        airdrop.lockUp();

        /* Verify locked - FIXED: should be assertTrue */
        assertTrue(airdrop.isLocked());
    }

    /* TEST: test_LockUp_RevertWhenNotOwner - - - - - - - - - - - - - - - - - - /
     * Tests that only owner can lock the contract - - - - - - - - - - - - - - */
    function test_LockUp_RevertWhenNotOwner() public {
        LogUtils.logDebug("Testing lockUp revert when not owner");

        vm.expectRevert();
        vm.prank(alice);
        airdrop.lockUp();
    }

    /* TEST: test_LockUp_RevertWhenAlreadyLocked - - - - - - - - - - - - - - - - /
     * Tests that contract cannot be locked twice - - - - - - - - - - - - - - -*/
    function test_LockUp_RevertWhenAlreadyLocked() public {
        LogUtils.logDebug("Testing lockUp revert when already locked");

        /* Lock once */
        vm.prank(owner);
        airdrop.lockUp();
        assertTrue(airdrop.isLocked());

        /* Try to lock again */
        vm.expectRevert(Airdrop.AlreadyLocked.selector);
        vm.prank(owner);
        airdrop.lockUp();
    }

    /* TEST: test_DepositOnly - - - - - - - - - - - - - - - - - - - - - - - - - /
     * Tests only the deposit functionality - - - - - - - - - - - - - - - - - -*/
    function test_DepositOnly() public {
        LogUtils.logDebug("Testing deposit functionality");

        uint256 depositAmount = 1000 * 10 ** 18;
        LogUtils.logDebug("Minting tokens to owner: ");

        vm.prank(owner);
        token.mint(owner, depositAmount);

        LogUtils.logDebug("Approving tokens");
        vm.prank(owner);
        token.approve(address(airdrop), depositAmount);

        uint256 initialOwnerBalance = token.balanceOf(owner);
        LogUtils.logDebug(string.concat("Initial owner balance: ", vm.toString(initialOwnerBalance)));
        uint256 initialAirdropBalance = token.balanceOf(address(airdrop));
        LogUtils.logDebug(string.concat("Initial airdrop balance: ", vm.toString(initialAirdropBalance)));

        /* Deposit */
        vm.expectEmit();
        emit Airdrop.Deposit(depositAmount);
        vm.prank(owner);
        airdrop.deposit(depositAmount);

        LogUtils.logDebug(
            string.concat("Airdrop balance after deposit: ", vm.toString(token.balanceOf(address(airdrop))))
        );
        /* Verify balances changed */
        assertEq(token.balanceOf(owner), initialOwnerBalance - depositAmount);
        assertEq(token.balanceOf(address(airdrop)), initialAirdropBalance + depositAmount);
        assertEq(airdrop.totalDepositedForDistribution(), depositAmount);
    }

    /* TEST: test_Deposit_RevertWhenNotOwner - - - - - - - - - - - - - - - - - -/
     * Tests that only owner can deposit - - - - - - - - - - - - - - - - - - - */
    function test_Deposit_RevertWhenNotOwner() public {
        LogUtils.logDebug("Testing deposit revert when not owner");

        uint256 depositAmount = 1000 * 10 ** 18;
        token.mint(alice, depositAmount);
        vm.prank(alice);
        token.approve(address(airdrop), depositAmount);

        vm.expectRevert();
        vm.prank(alice);
        airdrop.deposit(depositAmount);
    }

    /* TEST: test_ImplementationCannotBeInitialized - - - - - - - - - - - - - - /
     * Tests that the implementation contract cannot be initialized directly - */
    function test_ImplementationCannotBeInitialized() public {
        LogUtils.logDebug("Testing implementation cannot be initialized");

        vm.expectRevert();
        airdropImpl.initialize(address(token), address(staker), signer, owner, timestamps);
    }

    /* TEST: test_AddTimestamp - - - - - - - - - - - - - - - - - - - - - - - - -/
     * Tests adding a new timestamp - - - - - - - - - - - - - - - - - - - - - -*/
    function test_AddTimestamp() public {
        LogUtils.logDebug("Testing add timestamp");

        uint256 newTimestamp = block.timestamp + 14 days;

        vm.expectEmit();
        emit Airdrop.TimestampAdded(2, newTimestamp);
        vm.prank(owner);
        airdrop.addTimestamp(newTimestamp);

        assertEq(airdrop.unlocks(2), newTimestamp);
    }

    /* TEST: test_AddTimestamp_RevertWhenNotFuture - - - - - - - - - - - - - - -/
     * Tests that timestamp must be in the future compared to last one - - - - */
    function test_AddTimestamp_RevertWhenNotFuture() public {
        LogUtils.logDebug("Testing add timestamp revert when not future");

        /* Try to add timestamp that's before the last one */
        uint256 invalidTimestamp = timestamps[1] - 1;

        vm.expectRevert(Airdrop.InvalidTimestamp.selector);
        vm.prank(owner);
        airdrop.addTimestamp(invalidTimestamp);
    }

    /* TEST: test_AddTimestamp_RevertWhenLocked - - - - - - - - - - - - - - - - /
     * Tests that timestamps cannot be added when locked - - - - - - - - - - - */
    function test_AddTimestamp_RevertWhenLocked() public {
        LogUtils.logDebug("Testing add timestamp revert when locked");

        vm.prank(owner);
        airdrop.lockUp();

        uint256 newTimestamp = block.timestamp + 14 days;

        vm.expectRevert(Airdrop.SettingsLocked.selector);
        vm.prank(owner);
        airdrop.addTimestamp(newTimestamp);
    }

    /* TEST: test_ChangeTimestamp - - - - - - - - - - - - - - - - - - - - - - - /
     * Tests changing an existing timestamp - - - - - - - - - - - - - - - - - -*/
    function test_ChangeTimestamp() public {
        LogUtils.logDebug("Testing change timestamp");

        /* Change the first timestamp to be 2 days from now */
        uint256 newTimestamp = block.timestamp + 2 days;

        vm.expectEmit();
        emit Airdrop.TimestampChanged(0, newTimestamp);
        vm.prank(owner);
        airdrop.changeTimestamp(0, newTimestamp);

        assertEq(airdrop.unlocks(0), newTimestamp);
    }

    /* TEST: test_ChangeTimestamp_RevertWhenInvalidIndex - - - - - - - - - - - -/
     * Tests that changing timestamp with invalid index reverts - - - - - - - -*/
    function test_ChangeTimestamp_RevertWhenInvalidIndex() public {
        LogUtils.logDebug("Testing change timestamp revert when invalid index");

        uint256 newTimestamp = block.timestamp + 10 days;

        vm.expectRevert(Airdrop.InvalidIndex.selector);
        vm.prank(owner);
        airdrop.changeTimestamp(5, newTimestamp); /* Index doesn't exist */
    }

    /* TEST: test_ChangeTimestamp_RevertWhenInvalidOrder - - - - - - - - - - - -/
     * Tests that timestamps must maintain order - - - - - - - - - - - - - - - */
    function test_ChangeTimestamp_RevertWhenInvalidOrder() public {
        LogUtils.logDebug("Testing change timestamp revert when invalid order");

        /* Try to set first timestamp after the second one */
        uint256 invalidTimestamp = timestamps[1] + 1 days;
        LogUtils.logDebug(string.concat("invalidTimestamp is ", vm.toString(invalidTimestamp)));

        vm.expectRevert(Airdrop.InvalidTimestamp.selector);
        vm.prank(owner);
        airdrop.changeTimestamp(0, invalidTimestamp);

        /* Add a third timestamp */
        uint256 thirdTimestamp = block.timestamp + 14 days;
        vm.prank(owner);
        airdrop.addTimestamp(thirdTimestamp);

        /* Try to set middle timestamp before first one */
        invalidTimestamp = timestamps[0] - 1 days;

        vm.expectRevert(Airdrop.InvalidTimestamp.selector);
        vm.prank(owner);
        airdrop.changeTimestamp(1, invalidTimestamp);
    }

    /* TEST: test_AssignPortions - - - - - - - - - - - - - - - - - - - - - - - -/
     * Tests assigning portions to users - - - - - - - - - - - - - - - - - - - */
    function test_AssignPortions() public {
        LogUtils.logDebug("Testing assign portions");

        address[] memory accounts = new address[](2);
        accounts[0] = alice;
        accounts[1] = bob;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = ALICE_PORTION;
        amounts[1] = BOB_PORTION;

        /* Assign portions for first unlock */
        vm.prank(owner);
        airdrop.assignPortions(0, accounts, amounts);

        assertEq(airdrop.portions(0, alice), amounts[0]);
        assertEq(airdrop.portions(0, bob), amounts[1]);

        /* Assign portions for second unlock */
        amounts[0] = ALICE_PORTION;
        amounts[1] = BOB_PORTION;

        vm.prank(owner);
        airdrop.assignPortions(1, accounts, amounts);

        assertEq(airdrop.portions(1, alice), amounts[0]);
        assertEq(airdrop.portions(1, bob), amounts[1]);
    }

    /* TEST: test_AssignPortions_RevertWhenArrayMismatch - - - - - - - - - - - -/
     * Tests that array lengths must match - - - - - - - - - - - - - - - - - - */
    function test_AssignPortions_RevertWhenArrayMismatch() public {
        LogUtils.logDebug("Testing assign portions revert when array mismatch");

        address[] memory accounts = new address[](2);
        accounts[0] = alice;
        accounts[1] = bob;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100 * 10 ** 18;

        vm.expectRevert(Airdrop.ArrayLengthMismatch.selector);
        vm.prank(owner);
        airdrop.assignPortions(0, accounts, amounts);
    }

    /* TEST: test_AssignPortions_RevertWhenLocked - - - - - - - - - - - - - - - /
     * Tests that portions cannot be assigned when locked - - - - - - - - - - -*/
    function test_AssignPortions_RevertWhenLocked() public {
        LogUtils.logDebug("Testing assign portions revert when locked");

        vm.prank(owner);
        airdrop.lockUp();

        address[] memory accounts = new address[](1);
        accounts[0] = alice;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = ALICE_PORTION;

        vm.expectRevert(Airdrop.SettingsLocked.selector);
        vm.prank(owner);
        airdrop.assignPortions(0, accounts, amounts);
    }

    /* TEST: test_Withdraw_ToWallet_Success - - - - - - - - - - - - - - - - - - /
     * Tests successful withdrawal to wallet with penalty - - - - - - - - - - -*/
    function test_Withdraw_ToWallet_Success() public {
        LogUtils.logDebug("Testing withdraw to wallet success");

        address[] memory accounts = new address[](2);
        accounts[0] = alice;
        accounts[1] = bob;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = ALICE_PORTION;
        amounts[1] = BOB_PORTION;

        LogUtils.logDebug("Minting tokens for setup");
        token.mint(address(airdrop), amounts[0] + amounts[1]);

        LogUtils.logDebug("Assigning portions");
        vm.prank(owner);
        airdrop.assignPortions(0, accounts, amounts);

        vm.warp(timestamps[0] + 1);

        LogUtils.logDebug("Acquiring hash");
        bytes32 hash = keccak256(
            abi.encode(address(airdrop), block.chainid, alice, true, ALICE_PORTION, CENTURY22TIMESTAMP)
        ).toEthSignedMessageHash();

        LogUtils.logDebug(string.concat("signing the hash with private key: ", vm.toString(signerPrivateKey)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, hash);

        LogUtils.logDebug("Acquiring signature");
        bytes memory signature = abi.encodePacked(r, s, v);

        /* Updated penalty calculation based on contract implementation */
        uint256 expectedPenalty = (ALICE_PORTION * DEFAULT_STAKER_FEE) / PRECISION;
        uint256 expectedReceived = ALICE_PORTION - expectedPenalty;

        uint256 treasuryBalanceBefore = token.balanceOf(treasury);
        uint256 aliceBalanceBefore = token.balanceOf(alice);

        vm.prank(alice);
        LogUtils.logDebug("Expecting emit");
        vm.expectEmit();
        emit Airdrop.WalletWithdrawal(alice, expectedReceived, expectedPenalty);
        LogUtils.logDebug("Withdrawing funds");
        airdrop.withdraw(true, false, CENTURY22TIMESTAMP, signature); // Updated to match function signature

        LogUtils.logDebug("Asserting conditions");
        assertEq(token.balanceOf(alice), aliceBalanceBefore + expectedReceived);
        /* Penalty goes to staker contract, not treasury based on contract implementation */
        assertEq(token.balanceOf(address(treasury)), treasuryBalanceBefore + expectedPenalty);
        assertEq(airdrop.portions(0, alice), 0);
    }

    /* TEST: test_Withdraw_ToStaker_Success - - - - - - - - - - - - - - - - - - /
     * Tests successful withdrawal to staker - - - - - - - - - - - - - - - - - */
    function test_Withdraw_ToStaker_Success() public {
        LogUtils.logDebug("Testing withdraw to staker success");

        address[] memory accounts = new address[](1);
        accounts[0] = alice;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = ALICE_PORTION;

        token.mint(address(airdrop), ALICE_PORTION);
        vm.prank(owner);
        airdrop.assignPortions(0, accounts, amounts);

        vm.warp(timestamps[0] + 1);

        bytes32 hash = keccak256(
            abi.encode(address(airdrop), block.chainid, alice, false, ALICE_PORTION, CENTURY22TIMESTAMP)
        ).toEthSignedMessageHash();

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.prank(alice);
        vm.expectEmit();
        emit Airdrop.StakerWithdrawal(alice, ALICE_PORTION, true); // Updated event signature
        airdrop.withdraw(false, true, CENTURY22TIMESTAMP, signature); // toWallet=false, locking=true

        /* Verify portion was deleted */
        assertEq(airdrop.portions(0, alice), 0);
        /* Verify tokens went to staker */
        assertEq(token.balanceOf(address(staker)), ALICE_PORTION);
    }

    /* TEST: test_Withdraw_RevertWhenTotalZero - - - - - - - - - - - - - - - - - /
     * Tests withdrawal reverts when no unlocked portions available - - - - - -*/
    function test_Withdraw_RevertWhenTotalZero() public {
        LogUtils.logDebug("Testing withdraw revert when total is zero");

        address[] memory accounts = new address[](1);
        accounts[0] = alice;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = ALICE_PORTION;

        token.mint(address(airdrop), ALICE_PORTION);
        vm.prank(owner);
        airdrop.assignPortions(0, accounts, amounts);

        /* Don't warp past unlock time, so no portions are available */

        bytes32 hash = keccak256(abi.encode(address(airdrop), block.chainid, alice, true, 0, CENTURY22TIMESTAMP))
            .toEthSignedMessageHash();

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.prank(alice);
        vm.expectRevert(Airdrop.TotalZero.selector);
        airdrop.withdraw(true, false, CENTURY22TIMESTAMP, signature);
    }

    /* TEST: test_Withdraw_RevertWhenSignatureInvalid - - - - - - - - - - - - - /
     * Tests withdrawal reverts when signature is invalid - - - - - - - - - - -*/
    function test_Withdraw_RevertWhenSignatureInvalid() public {
        LogUtils.logDebug("Testing withdraw revert when signature is invalid");

        address[] memory accounts = new address[](1);
        accounts[0] = alice;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = ALICE_PORTION;

        token.mint(address(airdrop), ALICE_PORTION);
        vm.prank(owner);
        airdrop.assignPortions(0, accounts, amounts);

        vm.warp(timestamps[0] + 1);

        /* Create invalid signature */
        bytes memory invalidSignature = abi.encodePacked(
            bytes32(0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef),
            bytes32(0xfedcba0987654321fedcba0987654321fedcba0987654321fedcba0987654321),
            uint8(27)
        );

        vm.prank(alice);
        vm.expectRevert(Airdrop.SignatureInvalid.selector);
        airdrop.withdraw(true, false, CENTURY22TIMESTAMP, invalidSignature);
    }

    /* TEST: test_cleanUpUnclaimedPortions - - - - - - - - - - - - - - - - - - -/
     * Tests cleanup of unclaimed portions after buffer period - - - - - - - - */
    function test_cleanUpUnclaimedPortions() public {
        LogUtils.logDebug("Testing cleanup of unclaimed portions");

        address[] memory accounts = new address[](2);
        accounts[0] = alice;
        accounts[1] = bob;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = ALICE_PORTION;
        amounts[1] = BOB_PORTION;

        LogUtils.logDebug("Minting tokens for setup");
        token.mint(address(airdrop), amounts[0] + amounts[1]);

        LogUtils.logDebug("Assigning portions");
        vm.prank(owner);
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

        vm.prank(owner);
        airdrop.cleanUp(addressesToCleanup);

        uint256 finalTreasuryTokenBalance = token.balanceOf(treasury);
        LogUtils.logDebug(
            string.concat("Treasury token balance after cleanup: ", vm.toString(finalTreasuryTokenBalance))
        );

        /* Verify alice's portion was cleaned up */
        assertEq(airdrop.portions(0, alice), 0);

        /* Verify tokens were transferred to treasury */
        assertEq(finalTreasuryTokenBalance, initialTreasuryTokenBalance + ALICE_PORTION);
    }

    /* TEST: test_CleanUp_RevertWhenNotAvailable - - - - - - - - - - - - - - - - /
    * Tests that cleanup reverts when called before the cleanup period expires - */
    function test_CleanUp_RevertWhenNotAvailable() public {
        LogUtils.logDebug("Testing cleanup revert when cleanup period hasn't expired");

        address[] memory accounts = new address[](1);
        accounts[0] = alice;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = ALICE_PORTION;

        token.mint(address(airdrop), ALICE_PORTION);
        vm.prank(owner);
        airdrop.assignPortions(0, accounts, amounts);

        address[] memory addressesToCleanup = new address[](1);
        addressesToCleanup[0] = alice;

        // Try cleanup before period expires
        vm.expectRevert(Airdrop.CleanUpNotAvailable.selector);
        vm.prank(owner);
        airdrop.cleanUp(addressesToCleanup);
    }

    /* TEST: test_Initialize_RevertWhenTokenZeroAddress - - - - - - - - - - - - /
     * Tests that initialization reverts when token address is zero - - - - - */
    function test_Initialize_RevertWhenTokenZeroAddress() public {
        LogUtils.logDebug("Testing initialize revert when token is zero address");

        vm.expectRevert();
        vm.prank(owner);
        factory.deploy(
            address(0), // Zero token address
            address(staker),
            signer,
            owner,
            timestamps
        );
    }

    /* TEST: test_Initialize_RevertWhenStakerZeroAddress - - - - - - - - - - - - /
     * Tests that initialization reverts when staker address is zero - - - - - */
    function test_Initialize_RevertWhenStakerZeroAddress() public {
        LogUtils.logDebug("Testing initialize revert when staker is zero address");

        vm.expectRevert();
        vm.prank(owner);
        factory.deploy(
            address(token),
            address(0), // Zero staker address
            signer,
            owner,
            timestamps
        );
    }

    /* TEST: test_Initialize_RevertWhenSignerZeroAddress - - - - - - - - - - - - /
     * Tests that initialization reverts when signer address is zero - - - - - */
    function test_Initialize_RevertWhenSignerZeroAddress() public {
        LogUtils.logDebug("Testing initialize revert when signer is zero address");

        vm.expectRevert();
        vm.prank(owner);
        factory.deploy(address(token), address(staker), address(0), owner, timestamps);
    }

    /* TEST: test_Initialize_RevertWhenInvalidTimestampOrder - - - - - - - - - - /
     * Tests that initialization reverts when timestamps are not in order - - -*/
    function test_Initialize_RevertWhenInvalidTimestampOrder() public {
        LogUtils.logDebug("Testing initialize revert when timestamps not in order");

        uint256[] memory invalidTimestamps = new uint256[](3);
        invalidTimestamps[0] = block.timestamp + 7 days;
        invalidTimestamps[1] = block.timestamp + 1 days; // Invalid: earlier than previous
        invalidTimestamps[2] = block.timestamp + 14 days;

        vm.expectRevert();
        vm.prank(owner);
        factory.deploy(address(token), address(staker), signer, owner, invalidTimestamps);
    }
}
