// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {Airdrop} from "../src/Airdrop.sol";

contract AirdropTest is Test {
    Airdrop public airdrop;

    function setUp() public {
        airdrop = new Airdrop();
    }

    function test_a() public {}

    function testFuzz_a(uint256 x) public {}
}
