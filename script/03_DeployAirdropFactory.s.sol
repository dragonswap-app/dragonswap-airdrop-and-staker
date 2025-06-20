// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AirdropFactory} from "../src/AirdropFactory.sol";
import {BaseDeployScript} from "./base/BaseDeployScript.sol";
import "../test/utils/LogUtils.sol";

contract DeployFactory is BaseDeployScript {
    function run() public returns (address factoryAddress) {
        string memory config = loadConfig();

        // Get required addresses
        address implementation = getAddress("airdropImpl");
        address owner = vm.parseJsonAddress(config, ".factory.owner");

        vm.startBroadcast();

        // Deploy Factory
        AirdropFactory factory = new AirdropFactory(implementation, owner);

        vm.stopBroadcast();

        factoryAddress = address(factory);
        saveAddress("factory", factoryAddress);

        LogUtils.logSuccess(string.concat("Deployed AirdropFactory at:", vm.toString(factoryAddress)));
        return factoryAddress;
    }
}
