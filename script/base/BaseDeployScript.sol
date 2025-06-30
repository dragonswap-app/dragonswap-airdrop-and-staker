// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {console2} from "forge-std/console2.sol";
import "../../test/utils/LogUtils.sol";

abstract contract BaseDeployScript is Script {
    using stdJson for string;

    string internal CONFIG_PATH = "./script/config/deploy-config.json";
    string internal ADDRESSES_PATH = "./script/config/deployed-addresses.json";

    function loadConfig() internal view returns (string memory) {
        return vm.readFile(CONFIG_PATH);
    }

    function loadAddresses() internal view returns (string memory) {
        try vm.readFile(ADDRESSES_PATH) returns (string memory data) {
            return data;
        } catch {
            return "{}";
        }
    }

    function saveAddress(string memory key, address addr) internal {
        string memory existingJson = loadAddresses();
        string memory finalJson;

        // Check if we have an empty json file, simple write and return if yes
        if (bytes(existingJson).length <= 2) {
            finalJson = vm.serializeAddress("", key, addr);
            vm.writeFile(ADDRESSES_PATH, finalJson);
            return;
        }

        // Parse existing keys and overwrite key if it exists
        string[] memory keys = vm.parseJsonKeys(existingJson, ".");

        // Serialize all existing keys
        for (uint256 i = 0; i < keys.length; i++) {
            if (keccak256(bytes(keys[i])) == keccak256(bytes(key))) {
                // Update existing key
                finalJson = vm.serializeAddress("", keys[i], addr);
            } else {
                // Keep existing address
                address existingAddr = vm.parseJsonAddress(existingJson, string.concat(".", keys[i]));
                finalJson = vm.serializeAddress("", keys[i], existingAddr);
            }
        }

        // Add new key if it doesn't exist
        bool keyExists = false;
        for (uint256 i = 0; i < keys.length; i++) {
            if (keccak256(bytes(keys[i])) == keccak256(bytes(key))) {
                keyExists = true;
                break;
            }
        }
        if (!keyExists) {
            finalJson = vm.serializeAddress("", key, addr);
        }

        vm.writeFile(ADDRESSES_PATH, finalJson);
    }

    function getAddress(string memory key) internal view returns (address) {
        string memory json = loadAddresses();

        // Try new format first
        try vm.parseJsonAddress(json, string.concat(".", key)) returns (address addr) {
            return addr;
        } catch {
            // Try legacy format
            try vm.parseJsonAddress(json, string.concat(".", key)) returns (address addr) {
                return addr;
            } catch {
                revert(string.concat("Address not found for key: ", key));
            }
        }
    }

    function hasAddress(string memory key) internal view returns (bool) {
        try vm.readFile(ADDRESSES_PATH) returns (string memory json) {
            // Try new format first
            try vm.parseJsonAddress(json, string.concat(".", key)) returns (address) {
                return true;
            } catch {
                // Try legacy format
                try vm.parseJsonAddress(json, string.concat(".", key)) returns (address) {
                    return true;
                } catch {
                    return false;
                }
            }
        } catch {
            return false;
        }
    }
}
