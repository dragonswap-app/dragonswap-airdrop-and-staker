// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Airdrop} from "../src/Airdrop.sol";
import {AirdropFactory} from "../src/AirdropFactory.sol";
import {Staker} from "../src/Staker.sol";
import {IStaker} from "../src/interfaces/IStaker.sol";
import {BaseDeployScript} from "./base/BaseDeployScript.sol";
import {console2} from "forge-std/console2.sol";
import "../test/utils/LogUtils.sol";

contract ChecksumScript is BaseDeployScript {
    struct CheckResult {
        bool passed;
        string message;
    }

    struct DeploymentState {
        address staker;
        address airdropImpl;
        address factory;
        address airdrop;
    }

    function run() public view {
        LogUtils.logInfo("=== DEPLOYMENT CHECKSUM VERIFICATION ===");

        // Load addresses and configuration
        DeploymentState memory deployment = loadDeployedAddresses();
        string memory config = loadConfig();

        uint256 totalChecks = 0;
        uint256 passedChecks = 0;

        // Verify Staker
        if (deployment.staker != address(0)) {
            (uint256 stakerPassed, uint256 stakerTotal) = verifyStaker(deployment.staker, config);
            passedChecks += stakerPassed;
            totalChecks += stakerTotal;
        }

        // Verify Airdrop Implementation
        if (deployment.airdropImpl != address(0)) {
            (uint256 implPassed, uint256 implTotal) = verifyAirdropImpl(deployment.airdropImpl);
            passedChecks += implPassed;
            totalChecks += implTotal;
        }

        // Verify Factory
        if (deployment.factory != address(0)) {
            (uint256 factoryPassed, uint256 factoryTotal) =
                verifyFactory(deployment.factory, deployment.airdropImpl, config);
            passedChecks += factoryPassed;
            totalChecks += factoryTotal;
        }

        // Verify Airdrop Instance
        if (deployment.airdrop != address(0)) {
            (uint256 airdropPassed, uint256 airdropTotal) = verifyAirdrop(deployment.airdrop, deployment.staker, config);
            passedChecks += airdropPassed;
            totalChecks += airdropTotal;
        }

        // Verify inter-contract relationships
        if (deployment.staker != address(0) && deployment.airdrop != address(0)) {
            (uint256 relationPassed, uint256 relationTotal) = verifyRelationships(deployment);
            passedChecks += relationPassed;
            totalChecks += relationTotal;
        }

        // Final summary
        LogUtils.logInfo("=== VERIFICATION SUMMARY ===");
        if (passedChecks == totalChecks) {
            LogUtils.logSuccess(
                string.concat("ALL CHECKS PASSED: ", vm.toString(passedChecks), "/", vm.toString(totalChecks))
            );
        } else {
            LogUtils.logError(
                string.concat("SOME CHECKS FAILED: ", vm.toString(passedChecks), "/", vm.toString(totalChecks))
            );
        }
    }

    function loadDeployedAddresses() internal view returns (DeploymentState memory) {
        DeploymentState memory deployment;

        if (hasAddress("staker")) {
            deployment.staker = getAddress("staker");
        }
        if (hasAddress("airdropImpl")) {
            deployment.airdropImpl = getAddress("airdropImpl");
        }
        if (hasAddress("factory")) {
            deployment.factory = getAddress("factory");
        }
        if (hasAddress("airdrop")) {
            deployment.airdrop = getAddress("airdrop");
        }

        return deployment;
    }

    function verifyStaker(address stakerAddr, string memory config)
        internal
        view
        returns (uint256 passed, uint256 total)
    {
        LogUtils.logInfo("=== VERIFYING STAKER ===");
        LogUtils.logInfo(string.concat("Address: ", vm.toString(stakerAddr)));

        CheckResult[] memory checks = new CheckResult[](7);
        uint256 checkIndex = 0;

        // Check if contract exists
        checks[checkIndex++] = checkContractExists(stakerAddr, "Staker");

        if (stakerAddr.code.length > 0) {
            Staker staker = Staker(stakerAddr);

            // Parse expected values
            address expectedAirdrop = getAddress("airdrop");
            address expectedOwner = vm.parseJsonAddress(config, ".staker.owner");
            address expectedStakingToken = vm.parseJsonAddress(config, ".staker.stakingToken");
            address expectedTreasury = vm.parseJsonAddress(config, ".staker.treasury");
            uint256 expectedFee = vm.parseJsonUint(config, ".staker.fee");
            address[] memory expectedRewardTokens = vm.parseJsonAddressArray(config, ".staker.rewardTokens");

            // Verify configuration
            checks[checkIndex++] = checkAddress(staker.owner(), expectedOwner, "Staker owner");
            checks[checkIndex++] = checkAddress(address(staker.stakingToken()), expectedStakingToken, "Staking token");
            checks[checkIndex++] = checkAddress(staker.treasury(), expectedTreasury, "Treasury");
            checks[checkIndex++] = checkUint(staker.fee(), expectedFee, "Fee");
            checks[checkIndex++] = checkRewardTokens(staker, expectedRewardTokens);
            checks[checkIndex++] = checkAddress(staker.airdrop(), expectedAirdrop, "Staker airdrop address");
        }

        (passed, total) = summarizeChecks(checks, checkIndex);
    }

    function verifyAirdropImpl(address implAddr) internal view returns (uint256 passed, uint256 total) {
        LogUtils.logInfo("=== VERIFYING AIRDROP IMPLEMENTATION ===");
        LogUtils.logInfo(string.concat("Address: ", vm.toString(implAddr)));

        CheckResult[] memory checks = new CheckResult[](2);
        uint256 checkIndex = 0;

        // Check if contract exists
        checks[checkIndex++] = checkContractExists(implAddr, "Airdrop Implementation");

        if (implAddr.code.length > 0) {
            // Check if it's uninitialized (implementation should not be initialized)
            try Airdrop(implAddr).token() returns (address token) {
                checks[checkIndex++] =
                    CheckResult({passed: token == address(0), message: "Implementation is properly uninitialized"});
            } catch {
                checks[checkIndex++] =
                    CheckResult({passed: true, message: "Implementation is properly uninitialized (reverts)"});
            }
        }

        (passed, total) = summarizeChecks(checks, checkIndex);
    }

    function verifyFactory(address factoryAddr, address expectedImpl, string memory config)
        internal
        view
        returns (uint256 passed, uint256 total)
    {
        LogUtils.logInfo("=== VERIFYING FACTORY ===");
        LogUtils.logInfo(string.concat("Address: ", vm.toString(factoryAddr)));

        CheckResult[] memory checks = new CheckResult[](4);
        uint256 checkIndex = 0;

        // Check if contract exists
        checks[checkIndex++] = checkContractExists(factoryAddr, "Factory");

        if (factoryAddr.code.length > 0) {
            AirdropFactory factory = AirdropFactory(factoryAddr);

            address expectedOwner = vm.parseJsonAddress(config, ".factory.owner");

            // Verify configuration
            checks[checkIndex++] = checkAddress(factory.owner(), expectedOwner, "Factory owner");
            checks[checkIndex++] = checkAddress(factory.implementation(), expectedImpl, "Implementation address");
            checks[checkIndex++] = checkUint(factory.noOfDeployments(), 1, "Initial deployment count");
        }

        (passed, total) = summarizeChecks(checks, checkIndex);
    }

    function verifyAirdrop(address airdropAddr, address expectedStaker, string memory config)
        internal
        view
        returns (uint256 passed, uint256 total)
    {
        LogUtils.logInfo("=== VERIFYING AIRDROP ===");
        LogUtils.logInfo(string.concat("Address: ", vm.toString(airdropAddr)));

        CheckResult[] memory checks = new CheckResult[](8);
        uint256 checkIndex = 0;

        // Check if contract exists
        checks[checkIndex++] = checkContractExists(airdropAddr, "Airdrop");

        if (airdropAddr.code.length > 0) {
            Airdrop airdrop = Airdrop(airdropAddr);

            // Parse expected values
            address expectedOwner = vm.parseJsonAddress(config, ".airdrop.owner");
            address expectedToken = vm.parseJsonAddress(config, ".airdrop.token");
            address expectedSigner = vm.parseJsonAddress(config, ".airdrop.signer");
            uint256[] memory expectedTimestamps = vm.parseJsonUintArray(config, ".airdrop.unlockTimestamps");

            // Verify configuration
            checks[checkIndex++] = checkAddress(airdrop.owner(), expectedOwner, "Airdrop owner");
            checks[checkIndex++] = checkAddress(airdrop.token(), expectedToken, "Token address");
            checks[checkIndex++] = checkAddress(airdrop.staker(), expectedStaker, "Staker address");
            checks[checkIndex++] =
                checks[checkIndex++] = checkAddress(airdrop.signer(), expectedSigner, "Signer address");
            checks[checkIndex++] = checkBool(!airdrop.isLocked(), true, "Not locked initially");
            checks[checkIndex++] = checkUnlockTimestamps(airdrop, expectedTimestamps);
        }

        (passed, total) = summarizeChecks(checks, checkIndex);
    }

    function verifyRelationships(DeploymentState memory deployment)
        internal
        view
        returns (uint256 passed, uint256 total)
    {
        LogUtils.logInfo("=== VERIFYING INTER-CONTRACT RELATIONSHIPS ===");

        CheckResult[] memory checks = new CheckResult[](3);
        uint256 checkIndex = 0;

        if (deployment.factory != address(0) && deployment.airdrop != address(0)) {
            AirdropFactory factory = AirdropFactory(deployment.factory);

            // Check if airdrop was deployed through factory
            checks[checkIndex++] = checkBool(
                factory.isDeployedThroughFactory(deployment.airdrop), true, "Airdrop deployed through factory"
            );

            // Check if factory has correct deployment count
            checks[checkIndex++] = checkBool(factory.noOfDeployments() >= 1, true, "Factory has deployments");

            // Check if latest deployment matches our airdrop
            if (factory.noOfDeployments() > 0) {
                checks[checkIndex++] =
                    checkAddress(factory.getLatestDeployment(), deployment.airdrop, "Latest deployment matches airdrop");
            }
        }

        (passed, total) = summarizeChecks(checks, checkIndex);
    }

    // Helper functions
    function checkContractExists(address addr, string memory name) internal view returns (CheckResult memory) {
        bool exists = addr.code.length > 0;
        return CheckResult({
            passed: exists,
            message: exists ? string.concat(name, " contract exists") : string.concat(name, " contract not found")
        });
    }

    function checkAddress(address actual, address expected, string memory name)
        internal
        pure
        returns (CheckResult memory)
    {
        bool matches = actual == expected;
        return CheckResult({
            passed: matches,
            message: matches
                ? string.concat(name, " matches")
                : string.concat(name, " mismatch: expected ", vm.toString(expected), ", got ", vm.toString(actual))
        });
    }

    function checkUint(uint256 actual, uint256 expected, string memory name)
        internal
        pure
        returns (CheckResult memory)
    {
        bool matches = actual == expected;
        return CheckResult({
            passed: matches,
            message: matches
                ? string.concat(name, " matches")
                : string.concat(name, " mismatch: expected ", vm.toString(expected), ", got ", vm.toString(actual))
        });
    }

    function checkBool(bool actual, bool expected, string memory name) internal pure returns (CheckResult memory) {
        bool matches = actual == expected;
        return CheckResult({
            passed: matches,
            message: matches ? string.concat(name, " correct") : string.concat(name, " incorrect")
        });
    }

    function checkRewardTokens(Staker staker, address[] memory expected) internal view returns (CheckResult memory) {
        uint256 actualCount = staker.rewardTokensCounter();

        if (actualCount != expected.length) {
            return CheckResult({
                passed: false,
                message: string.concat(
                    "Reward tokens count mismatch: expected ",
                    vm.toString(expected.length),
                    ", got ",
                    vm.toString(actualCount)
                )
            });
        }

        // Check each token
        for (uint256 i = 0; i < expected.length; i++) {
            if (!staker.isRewardToken(expected[i])) {
                return CheckResult({
                    passed: false,
                    message: string.concat("Missing reward token: ", vm.toString(expected[i]))
                });
            }
        }

        return CheckResult({passed: true, message: "All reward tokens configured correctly"});
    }

    function checkUnlockTimestamps(Airdrop airdrop, uint256[] memory expected)
        internal
        view
        returns (CheckResult memory)
    {
        uint256 actualCount = airdrop.unlocksCounter();

        if (actualCount != expected.length) {
            return CheckResult({
                passed: false,
                message: string.concat(
                    "Unlock timestamps count mismatch: expected ",
                    vm.toString(expected.length),
                    ", got ",
                    vm.toString(actualCount)
                )
            });
        }

        // Check each timestamp
        for (uint256 i = 0; i < expected.length; i++) {
            uint256 actualTimestamp = airdrop.unlocks(i);
            if (actualTimestamp != expected[i]) {
                return CheckResult({
                    passed: false,
                    message: string.concat(
                        "Unlock timestamp ",
                        vm.toString(i),
                        " mismatch: expected ",
                        vm.toString(expected[i]),
                        ", got ",
                        vm.toString(actualTimestamp)
                    )
                });
            }
        }

        return CheckResult({passed: true, message: "All unlock timestamps configured correctly"});
    }

    function summarizeChecks(CheckResult[] memory checks, uint256 count)
        internal
        pure
        returns (uint256 passed, uint256 total)
    {
        total = count;
        passed = 0;

        for (uint256 i = 0; i < count; i++) {
            if (checks[i].passed) {
                LogUtils.logSuccess(string.concat("[OK]   ", checks[i].message));
                passed++;
            } else {
                LogUtils.logError(string.concat("[FAIL] ", checks[i].message));
            }
        }
    }
}
