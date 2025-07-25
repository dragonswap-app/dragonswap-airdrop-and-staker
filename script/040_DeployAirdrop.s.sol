// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AirdropFactory} from "../src/AirdropFactory.sol";
import {Staker} from "../src/Staker.sol";
import {BaseDeployScript} from "./base/BaseDeployScript.s.sol";
import {console2} from "forge-std/console2.sol";

contract DeployAirdropAndSetOnStaker is BaseDeployScript {
    error DeployAirdropAndSetOnStaker__FactoryDoesNotExist();

    function run() public returns (address airdropAddress) {
        string memory config = loadConfig();

        if (!hasAddress("factory")) {
            revert DeployAirdropAndSetOnStaker__FactoryDoesNotExist();
        }

        // Get factory address
        address factoryAddress = getAddress("factory");
        address stakerAddress = getAddress("staker");

        // Parse airdrop configuration
        address owner = vm.parseJsonAddress(config, ".airdrop.owner");
        address token = vm.parseJsonAddress(config, ".airdrop.token");
        address signer = vm.parseJsonAddress(config, ".airdrop.signer");

        // Parse unlock timestamps
        uint256[] memory timestamps;
        timestamps = vm.parseJsonUintArray(config, ".airdrop.unlockTimestamps");

        vm.startBroadcast(vm.envUint("PK"));

        // Deploy through factory
        AirdropFactory factory = AirdropFactory(factoryAddress);
        address instance = factory.deploy(token, stakerAddress, signer, owner, timestamps);

        vm.stopBroadcast();

        saveAddress("airdrop", instance);

        console2.log("Deployed Airdrop (%s) at:", instance);
        return instance;
    }
}
