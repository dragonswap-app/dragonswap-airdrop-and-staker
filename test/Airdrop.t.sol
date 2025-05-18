// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {AirdropFactory} from "../src/AirdropFactory.sol";
import {Airdrop} from "../src/Airdrop.sol";

contract AirdropTest is Test {
    AirdropFactory public airdropFactory;
    Airdrop public airdrop;

    function setUp() public {
        airdrop = new Airdrop();
        airdropFactory = new AirdropFactory(address(airdrop), address(this));
    }

    function testDeploy() external {
        uint256[] memory timestamps = new uint256[](0);
        address instance = airdropFactory.deploy(address(1), address(1), address(1), address(1), timestamps);
        assertNotEq(instance, address(0));
        assertEq(instance, airdropFactory.getLatestDeployment());
        assertEq(1, airdropFactory.noOfDeployments());
        assertTrue(airdropFactory.isDeployedThroughFactory(instance));
        console.log(instance);
    }
}
