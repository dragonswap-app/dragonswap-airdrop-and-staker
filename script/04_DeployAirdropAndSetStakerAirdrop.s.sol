// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AirdropFactory} from "../src/AirdropFactory.sol";
import {Staker} from "../src/Staker.sol";
import {BaseDeployScript} from "./base/BaseDeployScript.sol";
import {console2} from "forge-std/console2.sol";

contract DeployAirdropAndSetStakerAirdrop is BaseDeployScript {
    error DeployAirdropAndSetStakerAirdrop__FactoryDoesNotExist();

    function setUp() public {
        string memory rpcUrl = vm.envString("RPC_URL");

        uint256 forkId = vm.createFork(rpcUrl);

        vm.selectFork(forkId);
    }

    function run() public returns (address airdropAddress) {
        string memory config = loadConfig();

        if (!hasAddress("factory")) {
            revert DeployAirdropAndSetStakerAirdrop__FactoryDoesNotExist();
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

        // Set active airdrop on the staker side
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
