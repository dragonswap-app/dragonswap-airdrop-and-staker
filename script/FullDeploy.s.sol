// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Staker} from "../src/Staker.sol";
import {Airdrop} from "../src/Airdrop.sol";
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
        string memory config = loadConfig();

        vm.startBroadcast();

        // Step 1: Deploy Staker
        LogUtils.logInfo("=== Step 1: Deploying Staker ===");
        stakerAddress = deployStaker(config);

        // Step 2: Deploy Airdrop Implementation
        LogUtils.logInfo("=== Step 2: Deploying Airdrop Implementation ===");
        airdropImplAddress = deployAirdropImpl();

        // Step 3: Deploy Factory
        LogUtils.logInfo("=== Step 3: Deploying Factory ===");
        factoryAddress = deployFactory(config, airdropImplAddress);

        // Step 4: Deploy Airdrop Instance (before transferring factory ownership)
        LogUtils.logInfo("=== Step 4: Deploying Airdrop Instance ===");
        airdropAddress = deployAirdropInstance(config, factoryAddress, stakerAddress);

        // Step 5: Transfer factory ownership
        LogUtils.logInfo("=== Step 5: Transferring Factory Ownership ===");
        transferFactoryOwnership(config, factoryAddress);

        vm.stopBroadcast();

        // Save all addresses
        saveAddress("staker", stakerAddress);
        saveAddress("airdropImpl", airdropImplAddress);
        saveAddress("factory", factoryAddress);
        saveAddress("airdrop", airdropAddress);

        LogUtils.logSuccess("=== Full deployment completed successfully! ===");
        LogUtils.logInfo(string.concat("Staker: ", vm.toString(stakerAddress)));
        LogUtils.logInfo(string.concat("Airdrop Implementation: ", vm.toString(airdropImplAddress)));
        LogUtils.logInfo(string.concat("Factory: ", vm.toString(factoryAddress)));
        LogUtils.logInfo(string.concat("Airdrop Instance: ", vm.toString(airdropAddress)));

        return (stakerAddress, airdropImplAddress, factoryAddress, airdropAddress);
    }

    function deployStaker(string memory config) internal returns (address) {
        LogUtils.logInfo("Loading Staker configuration...");

        address owner = vm.parseJsonAddress(config, ".staker.owner");
        LogUtils.logInfo(string.concat("Owner set to ", vm.toString(owner)));

        address stakingToken = vm.parseJsonAddress(config, ".staker.stakingToken");
        LogUtils.logInfo(string.concat("Staking token set to ", vm.toString(stakingToken)));

        address treasury = vm.parseJsonAddress(config, ".staker.treasury");
        LogUtils.logInfo(string.concat("Treasury set to ", vm.toString(treasury)));

        uint256 fee = vm.parseJsonUint(config, ".staker.fee");
        LogUtils.logInfo(string.concat("Fee set to ", vm.toString(fee)));

        // Parse reward tokens array
        address[] memory rewardTokens = vm.parseJsonAddressArray(config, ".staker.rewardTokens");
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            LogUtils.logInfo(
                string.concat("[+] Reward token [#", vm.toString(i), "] --> ", vm.toString(rewardTokens[i]))
            );
        }

        // Deploy Staker
        LogUtils.logInfo("Deploying staker...");
        Staker staker = new Staker(owner, stakingToken, treasury, fee, rewardTokens);

        address stakerAddr = address(staker);
        LogUtils.logSuccess(
            string.concat("Deployed staker at ", LogUtils.INFCOLOR, vm.toString(stakerAddr), LogUtils.NOCOLOR)
        );

        return stakerAddr;
    }

    function deployAirdropImpl() internal returns (address) {
        LogUtils.logInfo("Deploying Airdrop implementation...");

        // Deploy Airdrop implementation
        Airdrop airdropImpl = new Airdrop();

        address implAddr = address(airdropImpl);
        LogUtils.logInfo(string.concat("Deployed Airdrop Implementation at: ", vm.toString(implAddr)));

        return implAddr;
    }

    function deployFactory(string memory config, address implementation) internal returns (address) {
        LogUtils.logInfo("Deploying AirdropFactory...");

        address currentDeployer = msg.sender;

        // Deploy Factory with deployer as initial owner (we'll transfer later)
        AirdropFactory factory = new AirdropFactory(implementation, currentDeployer);
        address factoryAddr = address(factory);

        LogUtils.logSuccess(string.concat("Deployed AirdropFactory at: ", vm.toString(factoryAddr)));
        return factoryAddr;
    }

    function transferFactoryOwnership(string memory config, address factoryAddress) internal {
        address targetOwner = vm.parseJsonAddress(config, ".factory.owner");
        address currentDeployer = msg.sender;

        // Transfer ownership if different from deployer
        if (targetOwner != currentDeployer) {
            LogUtils.logInfo(string.concat("Transferring factory ownership to: ", vm.toString(targetOwner)));
            AirdropFactory factory = AirdropFactory(factoryAddress);
            factory.transferOwnership(targetOwner);
            LogUtils.logSuccess(string.concat("Factory ownership transferred to: ", vm.toString(targetOwner)));
        } else {
            LogUtils.logInfo("Factory owner is same as deployer, no transfer needed");
        }
    }

    function deployAirdropInstance(string memory config, address factoryAddress, address stakerAddress)
        internal
        returns (address)
    {
        LogUtils.logInfo("Deploying Airdrop instance through factory...");

        // Parse airdrop configuration
        address owner = vm.parseJsonAddress(config, ".airdrop.owner");
        address token = vm.parseJsonAddress(config, ".airdrop.token");
        address treasury = vm.parseJsonAddress(config, ".airdrop.treasury");
        address signer = vm.parseJsonAddress(config, ".airdrop.signer");

        LogUtils.logInfo(string.concat("Airdrop owner: ", vm.toString(owner)));
        LogUtils.logInfo(string.concat("Airdrop token: ", vm.toString(token)));
        LogUtils.logInfo(string.concat("Airdrop treasury: ", vm.toString(treasury)));
        LogUtils.logInfo(string.concat("Airdrop signer: ", vm.toString(signer)));

        // Parse unlock timestamps
        uint256[] memory timestamps = vm.parseJsonUintArray(config, ".airdrop.unlockTimestamps");
        LogUtils.logInfo(string.concat("Unlock timestamps count: ", vm.toString(timestamps.length)));
        for (uint256 i = 0; i < timestamps.length; i++) {
            LogUtils.logInfo(string.concat("Timestamp [", vm.toString(i), "]: ", vm.toString(timestamps[i])));
        }

        // Deploy through factory
        AirdropFactory factory = AirdropFactory(factoryAddress);
        address instance = factory.deploy(token, stakerAddress, treasury, signer, owner, timestamps);

        LogUtils.logSuccess(string.concat("Deployed Airdrop instance at: ", vm.toString(instance)));
        return instance;
    }
}
