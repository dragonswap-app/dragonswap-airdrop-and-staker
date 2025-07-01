// File: script/02_DeployAirdropImpl.s.sol
import {Airdrop} from "../src/Airdrop.sol";
import {BaseDeployScript} from "./base/BaseDeployScript.sol";
import {AirdropFactory} from "../src/AirdropFactory.sol";
import "../test/utils/LogUtils.sol";

contract DeployAirdropImpl is BaseDeployScript {
    function setUp() public {
        string memory rpcUrl = vm.envString("RPC_URL");

        uint256 forkId = vm.createFork(rpcUrl);

        vm.selectFork(forkId);
    }

    function run() public returns (address implAddress) {
        bool _setFactorysImplementationToThis = false;

        // Check if factory address exists
        // If it already exists, and the airdropImpl is 0x0
        // Overwrite it

        if (hasAddress("factory")) {
            LogUtils.logInfo(
                "Factory has already been deployed. Checking if it already has an airdrop implementation..."
            );
            address tempFactoryAddress = getAddress("factory");

            AirdropFactory previousFactory = AirdropFactory(tempFactoryAddress);

            LogUtils.logInfo(
                string.concat("Current implementation address: ", vm.toString(previousFactory.implementation()))
            );

            // If the address is something else, don't set the implementation
            // change this line / delete this if you're sure you want to overwrite the
            // implementation
            if (previousFactory.implementation() == address(0x0)) {
                _setFactorysImplementationToThis = true;
            }
        } else {
            LogUtils.logInfo("Factory has not been deployed. Only deploying the airdropImpl.");
        }

        vm.startBroadcast(vm.envUint("PK"));

        // Deploy Airdrop implementation
        Airdrop airdropImpl = new Airdrop();

        implAddress = address(airdropImpl);

        if (_setFactorysImplementationToThis) {
            AirdropFactory(getAddress("factory")).setImplementation(implAddress);

            LogUtils.logSuccess(string.concat("Set deployed factory's implementation to ", vm.toString(implAddress)));
        }

        vm.stopBroadcast();

        saveAddress("airdropImpl", implAddress);

        LogUtils.logInfo(string.concat("Deployed Airdrop Implementation at: ", vm.toString(implAddress)));
        return implAddress;
    }
}
