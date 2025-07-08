// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Airdrop} from "../src/Airdrop.sol";
import {BaseDeployScript} from "./base/BaseDeployScript.sol";
import {console2} from "forge-std/console2.sol";
import {LogUtils} from "../test/utils/LogUtils.sol";

contract DepositTokenToAirdrop is BaseDeployScript {
    error DepositTokenToAirdrop__defaultDepositAmountNotSet();

    function run() public {
        // Load config file
        string memory config = loadConfig();

        // Lookup deployed addresses
        uint256 defaultDepositAmount = vm.parseJsonUint(config, ".airdrop.defaultDepositAmount");

        // Check if deployed airdrop address exists
        if (!hasAddress("airdrop")) {
            revert DepositTokenToAirdrop__defaultDepositAmountNotSet();
        }

        // Get deployed airdrop address
        address airdropAddress = getAddress("airdrop");

        vm.startBroadcast(vm.envUint("PK"));

        // Deposit funds to airdrop
        Airdrop airdrop = Airdrop(airdropAddress);

        // Deposit
        airdrop.deposit(defaultDepositAmount);
        LogUtils.logInfo(string.concat("Deposited to airdrop: ", vm.toString(defaultDepositAmount)));

        vm.stopBroadcast();
    }
}
