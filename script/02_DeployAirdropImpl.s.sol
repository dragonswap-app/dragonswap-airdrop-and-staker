// File: script/02_DeployAirdropImpl.s.sol
import {Airdrop} from "../src/Airdrop.sol";
import {BaseDeployScript} from "./base/BaseDeployScript.sol";
import "../test/utils/LogUtils.sol";

contract DeployAirdropImpl is BaseDeployScript {
    function run() public returns (address implAddress) {
        // Check if we need staker address
        address stakerAddress;
        if (hasAddress("staker")) {
            stakerAddress = getAddress("staker");
            LogUtils.logInfo(string.concat("Using existing Staker: ", vm.toString(stakerAddress)));
        } else {
            revert("Staker not deployed. Run 01_DeployStaker.s.sol first or manually insert into deploy-config.json.");
        }

        vm.startBroadcast();

        // Deploy Airdrop implementation
        Airdrop airdropImpl = new Airdrop();

        vm.stopBroadcast();

        implAddress = address(airdropImpl);
        saveAddress("airdropImpl", implAddress);

        LogUtils.logInfo(string.concat("Deployed Airdrop Implementation at: ", vm.toString(implAddress)));
        return implAddress;
    }
}
