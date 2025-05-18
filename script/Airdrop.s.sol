// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {AirdropFactory} from "../src/AirdropFactory.sol";
import {Airdrop} from "../src/Airdrop.sol";

contract AirdropInitScript is Script {
    AirdropFactory public airdropFactory;
    Airdrop public airdrop;

    function run() public {
        vm.startBroadcast();

        airdrop = new Airdrop();
        console.log(address(airdrop));
        airdropFactory = new AirdropFactory(address(airdrop), msg.sender);
        console.log(address(airdropFactory));

        vm.stopBroadcast();
    }
}
