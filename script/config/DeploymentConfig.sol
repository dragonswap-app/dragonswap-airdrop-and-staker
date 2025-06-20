// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library DeploymentConfig {
    struct StakerConfig {
        address owner;
        address stakingToken;
        address treasury;
        uint256 fee;
        address[] rewardTokens;
    }

    struct AirdropConfig {
        address token;
        address treasury;
        address signer;
        address owner;
        uint256[] unlockTimestamps;
    }

    struct FactoryConfig {
        address owner;
    }

    struct DeployedAddresses {
        address staker;
        address airdropImpl;
        address factory;
        address[] airdrops;
    }
}
