// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract AirdropFactory is Ownable {
    address public implementation;
    address[] public deployments;
    mapping(address => address) public deploymentToImplementation;

    // Events
    event ImplementationSet(address indexed implementation);
    event Deployed(address indexed instance, address indexed token, address indexed implementation);

    // Errors
    error ImplementationNotSet();
    error CloneCreationFailed();
    error CloneInitializationFailed();
    error InvalidIndexRange();

    constructor(address _implementation, address initialOwner) Ownable(initialOwner) {
        implementation = _implementation;
        emit ImplementationSet(_implementation);
    }

    /// @notice Function to set the airdrop implementation on this factory
    function setImplementation(address _implementation) external onlyOwner {
        implementation = _implementation;
        emit ImplementationSet(_implementation);
    }

    /// @notice Function to deploy new airdrop instance through the factory
    function deploy(
        address token,
        address staker,
        address signer,
        address _owner,
        uint256[] calldata timestamps
    ) external onlyOwner returns (address instance) {
        // Gas opt
        address impl = implementation;
        // Require that implementation is set
        if (impl == address(0)) {
            revert ImplementationNotSet();
        }

        // Encode data
        bytes memory data = abi.encodeWithSignature(
            "initialize(address,address,address,address,uint256[])",
            token,
            staker,
            signer,
            _owner != address(0) ? _owner : owner(),
            timestamps
        );

        /// @solidity memory-safe-assembly
        assembly {
            // Cleans the upper 96 bits of the `implementation` word, then packs the first 3 bytes
            // of the `implementation` address with the bytecode before the address.
            mstore(0x00, or(shr(0xe8, shl(0x60, impl)), 0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000))
            // Packs the remaining 17 bytes of `implementation` with the bytecode after the address.
            mstore(0x20, or(shl(0x78, impl), 0x5af43d82803e903d91602b57fd5bf3))
            instance := create(0, 0x09, 0x37)
        }
        // Make sure that a new instance is created
        if (instance == address(0)) {
            revert CloneCreationFailed();
        }

        // Initialize / fund with native coins
        (bool success,) = instance.call(data);
        if (!success) revert CloneInitializationFailed();

        // Push instance to deployments
        deployments.push(instance);
        deploymentToImplementation[instance] = impl;

        emit Deployed(instance, token, impl);
    }

    /// @notice Get total number of instances deployed through the factory
    function noOfDeployments() public view returns (uint256) {
        return deployments.length;
    }

    /// @notice Get the latest airdrop instance deployed through the factory
    function getLatestDeployment() external view returns (address) {
        uint256 _noOfDeployments = noOfDeployments();
        if (_noOfDeployments > 0) return deployments[_noOfDeployments - 1];
        // Return zero address if no deployments were made
        return address(0);
    }

    /// @notice Get all deployments between the start and the end index
    /// @param startIndex is an index of the first instance to be retrieved
    /// @param endIndex is an index of the last instance to be retrieved
    /// @return _deployments - All deployments between provided indexes, inclusive
    function getDeployments(uint256 startIndex, uint256 endIndex)
        external
        view
        returns (address[] memory _deployments)
    {
        // Require valid index input
        if (endIndex < startIndex || endIndex >= deployments.length) {
            revert InvalidIndexRange();
        }
        // Initialize new array
        _deployments = new address[](endIndex - startIndex + 1);
        uint256 index = 0;
        // Fill the array with deployment addresses
        for (uint256 i = startIndex; i <= endIndex; i++) {
            _deployments[index] = deployments[i];
            index++;
        }
    }

    /// @notice Check if the deployment of an instance was made through the factory
    function isDeployedThroughFactory(address deployment) external view returns (bool) {
        return deploymentToImplementation[deployment] != address(0);
    }
}
