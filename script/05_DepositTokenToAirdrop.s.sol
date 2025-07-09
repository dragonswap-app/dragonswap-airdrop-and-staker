// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Airdrop} from "../src/Airdrop.sol";
import {BaseDeployScript} from "./base/BaseDeployScript.s.sol";
import {console2} from "forge-std/console2.sol";
import {LogUtils} from "../test/utils/LogUtils.sol";

contract DepositTokenToAirdrop is BaseDeployScript {
    error DepositTokenToAirdrop__AirdropAddressNotSet();
    error DepositTokenToAirdrop__DepositAmountIsZero();

    function run() public {
        // Load config file
        string memory config = loadConfig();

        // Lookup deployed addresses
        uint256 depositAmount = vm.parseJsonUint(config, ".airdrop.depositAmount");

        if (depositAmount == 0) {
            revert DepositTokenToAirdrop__DepositAmountIsZero();
        }

        // Check if deployed airdrop address exists
        if (!hasAddress("airdrop")) {
            revert DepositTokenToAirdrop__AirdropAddressNotSet();
        }

        // Get deployed airdrop address
        address airdropAddress = getAddress("airdrop");

        vm.startBroadcast(vm.envUint("PK"));

        // Deposit funds to airdrop
        Airdrop airdrop = Airdrop(airdropAddress);

        // Deposit
        airdrop.deposit(depositAmount);
        LogUtils.logInfo(string.concat("Deposited to airdrop: ", vm.toString(depositAmount)));

        vm.stopBroadcast();
    }
}
