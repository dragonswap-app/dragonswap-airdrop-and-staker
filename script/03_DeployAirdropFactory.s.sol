// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AirdropFactory} from "../src/AirdropFactory.sol";
import {BaseDeployScript} from "./base/BaseDeployScript.sol";
import "../test/utils/LogUtils.sol";

contract DeployFactory is BaseDeployScript {
    function setUp() public {
        string memory rpcUrl = vm.envString("RPC_URL");

        uint256 forkId = vm.createFork(rpcUrl);

        vm.selectFork(forkId);
    }

    function run() public returns (address factoryAddress) {
        string memory config = loadConfig();

        address airdropImplAddr = address(0x0);

        if (hasAddress("airdropImpl")) {
            airdropImplAddr = getAddress("airdropImpl");
            LogUtils.logInfo(string.concat("Using existing airdropImpl address: ", vm.toString(airdropImplAddr)));
        } else {
            LogUtils.logInfo(
                string.concat(
                    "No previous AirdropImpl detected. Setting factory's airdropImpl address to zero address: "
                )
            );
        }

        address owner = vm.parseJsonAddress(config, ".factory.owner");

        vm.startBroadcast(vm.envUint("PK"));
        AirdropFactory factory = new AirdropFactory(airdropImplAddr, owner);
        vm.stopBroadcast();

        factoryAddress = address(factory);
        saveAddress("factory", factoryAddress);

        LogUtils.logSuccess(string.concat("Deployed AirdropFactory to ", vm.toString(factoryAddress)));
        return factoryAddress;
    }
}
