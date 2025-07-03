// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Staker} from "../src/Staker.sol";
import {BaseDeployScript} from "./base/BaseDeployScript.sol";
import {console2} from "forge-std/console2.sol";
import "../test/utils/LogUtils.sol";

contract DeployStaker is BaseDeployScript {
    function setUp() public {
        string memory rpcUrl = vm.envString("RPC_URL");

        uint256 forkId = vm.createFork(rpcUrl);

        vm.selectFork(forkId);
    }

    function run() public returns (address stakerAddress) {
        loadAddresses();
        LogUtils.logInfo("Deploying Staker configuration");
        LogUtils.logInfo("Loading Staker configuration...");
        string memory config = loadConfig();

        // Parse staker configuration
        address owner = vm.parseJsonAddress(config, ".staker.owner");
        LogUtils.logInfo(string.concat("Owner set to ", vm.toString(owner)));

        address stakingToken = vm.parseJsonAddress(config, ".staker.stakingToken");
        LogUtils.logInfo(string.concat("Staking token set to ", vm.toString(stakingToken)));

        address treasury = vm.parseJsonAddress(config, ".staker.treasury");
        LogUtils.logInfo(string.concat("Treasury set to ", vm.toString(treasury)));

        uint256 fee = vm.parseJsonUint(config, ".staker.fee");
        LogUtils.logInfo(string.concat("Fee set to ", vm.toString(fee)));

        uint256 minimumDeposit = vm.parseJsonUint(config, ".staker.minimumDeposit");
        LogUtils.logInfo(string.concat("Minimum deposit set to ", vm.toString(minimumDeposit)));

        if (hasAddress("airdrop")) {
            LogUtils.logDebug("AIRDROP ADDRESS EXISTS");
        }

        address[] memory rewardTokens = vm.parseJsonAddressArray(config, ".staker.rewardTokens");

        for (uint256 i = 0; i < rewardTokens.length; i++) {
            LogUtils.logInfo(
                string.concat("[+] Reward token [#", vm.toString(i), "] --> ", vm.toString(rewardTokens[i]))
            );
        }

        vm.startBroadcast(vm.envUint("PK"));

        address airdropAddress = address(0x0);

        Staker staker = new Staker(owner, stakingToken, treasury, minimumDeposit, fee, rewardTokens);
        LogUtils.logSuccess("Staker deployed.");

        // Check if existing airdrop available and assign
        if (hasAddress("airdrop")) {
            airdropAddress = getAddress("airdrop");
            LogUtils.logInfo(string.concat("Setting existing airdrop address to staker: ", vm.toString(airdropAddress)));
            staker.setAirdropAddress(airdropAddress);
        } else {
            LogUtils.logInfo(string.concat("No previous Airdrop address detected. Staker airdrop remains unassigned."));
        }

        vm.stopBroadcast();

        stakerAddress = address(staker);
        saveAddress("staker", stakerAddress);

        LogUtils.logSuccess(
            string.concat("Deployed staker at ", LogUtils.INFCOLOR, vm.toString(stakerAddress), LogUtils.NOCOLOR)
        );

        return stakerAddress;
    }
}
