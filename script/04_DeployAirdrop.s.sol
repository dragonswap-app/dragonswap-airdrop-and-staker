// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AirdropFactory} from "../src/AirdropFactory.sol";
import {Staker} from "../src/Staker.sol";
import {BaseDeployScript} from "./base/BaseDeployScript.sol";
import {console2} from "forge-std/console2.sol";

contract DeployAirdrop is BaseDeployScript {
    function run() public returns (address airdropAddress) {
        string memory config = loadConfig();

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

        vm.startBroadcast();

        // Deploy through factory
        AirdropFactory factory = AirdropFactory(factoryAddress);
        address instance = factory.deploy(token, stakerAddress, signer, owner, timestamps);

        // In case the staker was already deployed (currently always TRUE, prepare for other variants)
        // This script will also set the airdropInstance of the staker to the
        // freshly deployed (current) Airdrop
        if (hasAddress("staker")) {
            address stakerAddress = getAddress("staker");
            Staker(stakerAddress).setAirdropAddress(instance);
        }

        Staker staker = Staker(stakerAddress);
        staker.setAirdropAddress(instance);

        vm.stopBroadcast();

        string memory addressKey = "airdrop";
        saveAddress(addressKey, instance);

        console2.log("Deployed Airdrop (%s) at:", instance);
        console2.log("Set staker airdrop to (%s)", instance);
        return instance;
    }
}
