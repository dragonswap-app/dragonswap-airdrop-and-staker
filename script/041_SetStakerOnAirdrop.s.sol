// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AirdropFactory} from "../src/AirdropFactory.sol";
import {Staker} from "../src/Staker.sol";
import {BaseDeployScript} from "./base/BaseDeployScript.s.sol";
import {console2} from "forge-std/console2.sol";

contract DeployAirdropAndSetOnStaker is BaseDeployScript {
    error DeployAirdropAndSetOnStaker__FactoryDoesNotExist();

    function run() public returns (address airdropAddress) {
        // Get staker address from deployed addresses
        address stakerAddress = getAddress("staker");

        // Get airdrop address from deployed addresses
        airdropAddress = getAddress("airdrop");

        vm.startBroadcast(vm.envUint("PK"));

        // Deploy through factory
        Staker staker = Staker(stakerAddress);
        staker.setAirdropAddress(airdropAddress);

        vm.stopBroadcast();

        console2.log("Set staker airdrop to (%s)", airdropAddress);
        return airdropAddress;
    }
}
