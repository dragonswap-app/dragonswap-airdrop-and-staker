// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test, console2} from "forge-std/Test.sol";
import {Airdrop} from "../src/Airdrop.sol";
import {AirdropFactory} from "../src/AirdropFactory.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

/* TODO */
/* Refactor all the things */

// Mock ERC20 token for testing
contract MockToken is ERC20 {
    constructor() ERC20("Mock Token", "MOCK") {
        _mint(msg.sender, 1_000_000 * 10 ** 18);
    }
}

contract AirdropSigningVulnerabilityTest is Test {
    using MessageHashUtils for bytes32;

    Airdrop public airdropImpl;
    AirdropFactory public factory;
    Airdrop public airdrop;
    MockToken public token;

    address public owner;
    address public treasury;
    address public alice;
    address public bob;

    // Signer wallet (private key known for testing)
    uint256 public signerPrivateKey = 0xA11CE;
    address public signer;

    // Test constants
    uint256 public constant TOTAL_AIRDROP = 100_000 * 10 ** 18;
    uint256 public constant ALICE_PORTION = 10_000 * 10 ** 18;
    uint256 public constant BOB_PORTION = 20_000 * 10 ** 18;

    function setUp() public {
        // Setup accounts
        owner = address(this);
        treasury = address(0x7EA5);
        alice = address(0xA11CE);
        bob = address(0xB0B);
        signer = vm.addr(signerPrivateKey);

        // Deploy contracts
        token = new MockToken();
        airdropImpl = new Airdrop();
        factory = new AirdropFactory(address(airdropImpl), owner);

        // Deploy airdrop instance through factory
        uint256[] memory timestamps = new uint256[](2);
        timestamps[0] = block.timestamp + 1 days;
        timestamps[1] = block.timestamp + 7 days;

        address airdropAddress = factory.deploy(
            address(token),
            address(0), // No staker for this test
            treasury,
            signer,
            owner,
            timestamps
        );

        airdrop = Airdrop(airdropAddress);

        // Setup airdrop
        _setupAirdrop();
    }

    function _setupAirdrop() internal {
        // Approve and deposit tokens
        token.approve(address(airdrop), TOTAL_AIRDROP);
        airdrop.deposit(TOTAL_AIRDROP);

        // Assign portions for first unlock (index 0)
        address[] memory accounts = new address[](2);
        accounts[0] = alice;
        accounts[1] = bob;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = ALICE_PORTION;
        amounts[1] = BOB_PORTION;

        airdrop.assignPortions(0, accounts, amounts);

        // Lock the contract
        airdrop.lockUp();
    }

    function testValidSignatureShouldPass() public {
        console2.log("\x1B[35mSTARTING VALID SIGNATURE TEST \x1B[0m");
        console2.log("\x1B[34mAlice balance before:\x1B[0m", token.balanceOf(alice) / 10 ** 18);
        console2.log("\x1B[34mContract balance before:\x1B[0m", token.balanceOf(address(airdrop)) / 10 ** 18);

        // Fast forward past first unlock
        vm.warp(block.timestamp + 2 days);

        // Create valid signature for Alice's withdrawal
        bytes32 messageHash = keccak256(abi.encode(address(airdrop), block.chainid, alice, true, ALICE_PORTION)) // toWallet
            .toEthSignedMessageHash();

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, messageHash);
        bytes memory validSignature = abi.encodePacked(r, s, v);

        // Try to withdraw with valid signature
        vm.startPrank(alice);
        airdrop.withdraw(true, 0, validSignature);
        vm.stopPrank();

        console2.log("\x1B[33mAlice balance after:\x1B[0m", token.balanceOf(alice) / 10 ** 18);
        console2.log("\x1B[33mContract balance after:", token.balanceOf(address(airdrop)) / 10 ** 18, "\x1B[0m");
    }

    function testInvalidSignatureShouldRevert() public {
        console2.log("\x1B[35mSTARTING INVALID SIGNATURE TEST \x1B[0m");
        console2.log("\x1B[34mAlice balance before:\x1B[0m", token.balanceOf(alice) / 10 ** 18);
        console2.log("\x1B[34mContract balance before:\x1B[0m", token.balanceOf(address(airdrop)) / 10 ** 18);

        // ARRANGE
        vm.warp(block.timestamp + 2 days);

        uint256 wrongSignerKey = 0xDEADBEEF; // Invalid signature

        bytes32 messageHash = keccak256(abi.encode(address(airdrop), block.chainid, alice, true, ALICE_PORTION)) // toWallet
            .toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongSignerKey, messageHash);
        bytes memory invalidSignature = abi.encodePacked(r, s, v);

        // ASSERT
        vm.startPrank(alice);
        vm.expectRevert(); // TODO: reenable for test
        airdrop.withdraw(true, 0, invalidSignature);
        console2.log("\x1B[35mAlice balance after:\x1B[0m", token.balanceOf(alice) / 10 ** 18);
        console2.log("\x1B[35mContract balance after:\x1B[0m", token.balanceOf(address(airdrop)) / 10 ** 18);
        vm.stopPrank();
    }
}
