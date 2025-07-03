// File: script/02_DeployAirdropImpl.s.sol
import {Airdrop} from "../src/Airdrop.sol";
import {BaseDeployScript} from "./base/BaseDeployScript.sol";
import {AirdropFactory} from "../src/AirdropFactory.sol";
import "../test/utils/LogUtils.sol";

contract DeployAirdropImplAndSetFactoryImpl is BaseDeployScript {
    function run() public returns (address implAddress) {
        // Check if factory address exists
        // If it already exists, overwrite it's airdrop implementation

        if (hasAddress("factory")) {
            LogUtils.logInfo(
                "Factory has already been deployed. Checking if it already has an airdrop implementation..."
            );
            address tempFactoryAddress = getAddress("factory");

            AirdropFactory previousFactory = AirdropFactory(tempFactoryAddress);

            LogUtils.logInfo(
                string.concat("Current implementation address: ", vm.toString(previousFactory.implementation()))
            );
        } else {
            LogUtils.logInfo("Factory has not been deployed. Only deploying the airdropImpl.");
        }

        vm.startBroadcast(vm.envUint("PK"));

        // Deploy Airdrop implementation
        Airdrop airdropImpl = new Airdrop();

        implAddress = address(airdropImpl);

        if (hasAddress("factory")) {
            AirdropFactory(getAddress("factory")).setImplementation(implAddress);

            LogUtils.logSuccess(string.concat("Set deployed factory's implementation to ", vm.toString(implAddress)));
        }

        vm.stopBroadcast();

        saveAddress("airdropImpl", implAddress);

        LogUtils.logInfo(string.concat("Deployed Airdrop Implementation at: ", vm.toString(implAddress)));
        return implAddress;
    }
}
