// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {DeployStaker} from "./01_DeployStaker.s.sol";
import {DeployAirdropImpl} from "./02_DeployAirdropImpl.s.sol";
import {DeployFactory} from "./03_DeployAirdropFactory.s.sol";
import {DeployAirdrop} from "./04_DeployAirdrop.s.sol";
import {AirdropFactory} from "../src/AirdropFactory.sol";
import {BaseDeployScript} from "./base/BaseDeployScript.sol";
import {console2} from "forge-std/console2.sol";
import "../test/utils/LogUtils.sol";

contract DeployAll is BaseDeployScript {
    function run()
        public
        returns (address stakerAddress, address airdropImplAddress, address factoryAddress, address airdropAddress)
    {
        LogUtils.logInfo("Starting full deployment sequence...");

        // Step 1: Deploy Staker
        LogUtils.logInfo("=== Step 1: Deploying Staker ===");
        DeployStaker stakerDeployer = new DeployStaker();
        stakerAddress = stakerDeployer.run();

        // Step 2: Deploy Airdrop Implementation
        LogUtils.logInfo("=== Step 2: Deploying Airdrop Implementation ===");
        DeployAirdropImpl implDeployer = new DeployAirdropImpl();
        airdropImplAddress = implDeployer.run();

        // Step 3: Deploy Factory (modified to use deployer as initial owner)
        LogUtils.logInfo("=== Step 3: Deploying Factory ===");

        factoryAddress = deployFactoryWithDeployerOwner(airdropImplAddress);

        // Step 4: Deploy Airdrop Instance (while deployer owns factory)

        LogUtils.logInfo("=== Step 4: Deploying Airdrop Instance ===");
        DeployAirdrop airdropDeployer = new DeployAirdrop();
        airdropAddress = airdropDeployer.run();

        // Step 5: Optional: Transfer factory ownership after deployment
        // LogUtils.logInfo("=== Step 5: Transferring Factory Ownership ===");
        // transferFactoryOwnership(factoryAddress);

        LogUtils.logSuccess("=== Full deployment completed successfully! ===");
        LogUtils.logInfo(string.concat("Staker: ", vm.toString(stakerAddress)));
        LogUtils.logInfo(string.concat("Airdrop Implementation: ", vm.toString(airdropImplAddress)));
        LogUtils.logInfo(string.concat("Factory: ", vm.toString(factoryAddress)));
        LogUtils.logInfo(string.concat("Airdrop Instance: ", vm.toString(airdropAddress)));

        return (stakerAddress, airdropImplAddress, factoryAddress, airdropAddress);
    }

    function deployFactoryWithDeployerOwner(address implementation) internal returns (address) {
        LogUtils.logInfo("Deploying AirdropFactory with deployer as initial owner...");

        address currentDeployer = msg.sender;

        vm.startBroadcast();

        // Deploy Factory with deployer as initial owner (transfer may be done later)
        AirdropFactory factory = new AirdropFactory(implementation, currentDeployer);
        address factoryAddr = address(factory);

        vm.stopBroadcast();

        // Save the factory address so DeployAirdrop can find it
        saveAddress("factory", factoryAddr);

        LogUtils.logSuccess(string.concat("Deployed AirdropFactory at: ", vm.toString(factoryAddr)));
        return factoryAddr;
    }

    function transferFactoryOwnership(address factoryAddress) internal {
        string memory config = loadConfig();
        address targetOwner = vm.parseJsonAddress(config, ".factory.owner");
        address currentDeployer = msg.sender;

        // Transfer ownership if different from deployer
        if (targetOwner != currentDeployer) {
            LogUtils.logInfo(string.concat("Transferring factory ownership to: ", vm.toString(targetOwner)));

            vm.startBroadcast();
            AirdropFactory factory = AirdropFactory(factoryAddress);
            factory.transferOwnership(targetOwner);
            vm.stopBroadcast();

            LogUtils.logSuccess(string.concat("Factory ownership transferred to: ", vm.toString(targetOwner)));
        } else {
            LogUtils.logInfo("Factory owner is same as deployer, no transfer needed");
        }
    }
}
