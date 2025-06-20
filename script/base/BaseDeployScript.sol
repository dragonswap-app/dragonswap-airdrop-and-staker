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

        // Object key for addresses
        string memory objectKey = "addresses";
        string memory finalJson;

        // Check if we have existing addresses in proper format
        bool hasExistingAddresses = false;
        try vm.parseJsonKeys(existingJson, ".addresses") returns (string[] memory) {
            hasExistingAddresses = true;
        } catch {}

        if (!hasExistingAddresses && bytes(existingJson).length > 2) {
            // Check if the file has a different structure (legacy flat format)
            try vm.parseJsonKeys(existingJson, ".") returns (string[] memory rootKeys) {
                if (rootKeys.length > 0) {
                    // Migrate from flat structure to nested structure
                    bool isFirst = true;
                    for (uint256 i = 0; i < rootKeys.length; i++) {
                        if (
                            bytes(rootKeys[i]).length > 0
                                && keccak256(bytes(rootKeys[i])) != keccak256(bytes("addresses"))
                        ) {
                            address existingAddr = vm.parseJsonAddress(existingJson, string.concat(".", rootKeys[i]));
                            if (isFirst) {
                                finalJson = vm.serializeAddress(objectKey, rootKeys[i], existingAddr);
                                isFirst = false;
                            } else {
                                finalJson = vm.serializeAddress(objectKey, rootKeys[i], existingAddr);
                            }
                        }
                    }
                    // Add the new address
                    finalJson = vm.serializeAddress(objectKey, key, addr);
                } else {
                    // Start fresh
                    finalJson = vm.serializeAddress(objectKey, key, addr);
                }
            } catch {
                // Start fresh
                finalJson = vm.serializeAddress(objectKey, key, addr);
            }
        } else if (hasExistingAddresses) {
            // We have proper structure, preserve existing addresses
            string[] memory keys = vm.parseJsonKeys(existingJson, ".addresses");

            // Add all existing addresses (including updating if key exists)
            bool foundKey = false;
            for (uint256 i = 0; i < keys.length; i++) {
                if (keccak256(bytes(keys[i])) == keccak256(bytes(key))) {
                    // Update existing key
                    finalJson = vm.serializeAddress(objectKey, keys[i], addr);
                    foundKey = true;
                } else {
                    // Keep existing address
                    address existingAddr = vm.parseJsonAddress(existingJson, string.concat(".addresses.", keys[i]));
                    finalJson = vm.serializeAddress(objectKey, keys[i], existingAddr);
                }
            }

            // Add new key if not found
            if (!foundKey) {
                finalJson = vm.serializeAddress(objectKey, key, addr);
            }
        } else {
            // Empty or new file
            finalJson = vm.serializeAddress(objectKey, key, addr);
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
