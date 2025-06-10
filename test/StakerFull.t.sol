// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {Staker} from "../src/Staker.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

/* TODO: Add comments */
contract StakerFullTest is Test {
    Staker public staker;
    ERC20Mock public stakingToken;
    ERC20Mock public rewardToken1;
    ERC20Mock public rewardToken2;

    /* NOTE: Actors */
    address public owner = makeAddr("owner");
    address public treasury = makeAddr("treasury");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public charlie = makeAddr("charlie");
    address public attacker = makeAddr("attacker");

    /* NOTE: Constants */
    uint256 public constant INITIAL_MINT = 1_000_000e18;
    uint256 public constant STAKER_FEE = 5_00; // 5%
    uint256 public constant PRECISION = 1_00_00; // 10000 for percentage calculations

    // ==================== SETUP ====================

    function setUp() public {
        // Deploy mock tokens
        stakingToken = new ERC20Mock();
        rewardToken1 = new ERC20Mock();
        rewardToken2 = new ERC20Mock();

        // Mint initial tokens for distribution
        stakingToken.mint(address(this), INITIAL_MINT);
        rewardToken1.mint(address(this), INITIAL_MINT);
        rewardToken2.mint(address(this), INITIAL_MINT);

        // Setup reward tokens array
        address[] memory rewardTokens = new address[](2);
        rewardTokens[0] = address(rewardToken1);
        rewardTokens[1] = address(rewardToken2);

        // Deploy Staker contract
        staker = new Staker(owner, address(stakingToken), treasury, STAKER_FEE, rewardTokens);

        // Distribute tokens to test users
        stakingToken.transfer(alice, 100_000e18);
        stakingToken.transfer(bob, 100_000e18);
        stakingToken.transfer(charlie, 100_000e18);

        rewardToken1.transfer(alice, 10_000e18);
        rewardToken2.transfer(bob, 10_000e18);
    }

    function test_Initialization_Success() public view {
        assertEq(staker.owner(), owner);
        assertEq(staker.treasury(), treasury);
        assertEq(staker.fee(), STAKER_FEE);

        // Test reward tokens are properly indexed
        assertEq(staker.rewardTokens(0), address(rewardToken1));
        assertEq(staker.rewardTokens(1), address(rewardToken2));
    }

    function test_Initialization_RevertWhen_OwnerZeroAddress() public {
        address[] memory rewardTokens = new address[](1);
        rewardTokens[0] = address(rewardToken1);

        vm.expectRevert();
        new Staker(address(0), address(stakingToken), treasury, STAKER_FEE, rewardTokens);
    }
}
