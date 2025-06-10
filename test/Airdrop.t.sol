// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

import {AirdropFactory} from "../src/AirdropFactory.sol";
import {Airdrop} from "../src/Airdrop.sol";
import {Staker} from "../src/Staker.sol";

import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract AirdropTest is Test {
    using MessageHashUtils for bytes32;

    AirdropFactory public airdropFactory;
    Airdrop public airdrop;

    function setUp() public {
        airdrop = new Airdrop();
        airdropFactory = new AirdropFactory(address(airdrop), address(this));
    }

    function test() external {
        // Deploy
        ERC20Mock token = new ERC20Mock();
        token.mint(address(this), 1_000_000e18);

        Vm.Wallet memory signer = vm.createWallet(vm.randomUint());

        address[] memory rewardTokens = new address[](1);
        rewardTokens[0] = address(2);

        Staker staker = new Staker(address(1), address(token), 1_00, rewardTokens);

        uint256[] memory timestamps = new uint256[](0);
        Airdrop instance = Airdrop(
            airdropFactory.deploy(address(token), address(staker), address(1), signer.addr, address(0), timestamps)
        );

        assertNotEq(address(instance), address(0));
        assertEq(address(instance), airdropFactory.getLatestDeployment());
        assertEq(1, airdropFactory.noOfDeployments());
        assertTrue(airdropFactory.isDeployedThroughFactory(address(instance)));
        console.log(address(instance));

        // Deposit
        token.approve(address(instance), type(uint256).max);
        uint256 depositAmount = 10_000e18;
        instance.deposit(depositAmount);
        assertEq(depositAmount, instance.totalDepositedForDistribution());

        // Add timestamp
        instance.addTimestamp(block.timestamp + 10);
        assertGt(instance.unlocks(0), 0);

        // Assing portions
        address user = address(2);
        address[] memory accounts = new address[](1);
        accounts[0] = user;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100e18;
        instance.assignPortions(0, accounts, amounts);
        assertEq(amounts[0], instance.portions(0, accounts[0]));

        // Withdraw
        bool toWallet = true;
        bytes32 hash =
            keccak256(abi.encode(address(instance), block.chainid, user, toWallet, amounts[0])).toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signer, hash);
        bytes memory signature = abi.encodePacked(r, s, v);
        vm.prank(user);
        vm.warp(block.timestamp + 11);
        instance.withdraw(toWallet, false, signature);
        uint256 penalty = amounts[0] * staker.fee() / 1_00_00;
        assertEq(token.balanceOf(user), amounts[0] - penalty);
        assertEq(token.balanceOf(address(staker)), penalty);
    }
}
