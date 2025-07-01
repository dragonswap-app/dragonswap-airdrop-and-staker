// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {Airdrop} from "src/Airdrop.sol";
import {AirdropFactory} from "src/AirdropFactory.sol";
import {Staker} from "src/Staker.sol";
import {LogUtils} from "test/utils/LogUtils.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/* NOTE: These tests do not check common attack vectors like signatures and reentrancy */
contract AirdropFactoryFullTest is Test {
    address public alice = address(0xA11CE);
    address public bob = address(0xB0B);
    address public charlie = address(0xC44);

    uint256 public signerPrivateKey = 0x123456789;
    address public signer = vm.addr(signerPrivateKey);

    uint256 constant PRECISION = 1_00_00;
    uint256 constant DEFAULT_STAKER_FEE = 50_00; // 50% fee from staker

    uint256 MINIMUM_DEPOSIT = 5 wei;

    Airdrop public airdropImpl;
    AirdropFactory public factory;
    ERC20Mock public token;
    Staker public staker;

    address public owner = makeAddr("owner");
    address public treasury = makeAddr("treasury");
    address public notOwner = makeAddr("notOwner");

    uint256[] public timestamps;

    /* TEST: setUp - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - /
     * Set up the test environment with factory, implementation and mock deps - -*/
    function setUp() public {
        LogUtils.logInfo(string.concat("[OWNER] ", vm.toString(owner)));
        token = new ERC20Mock();

        LogUtils.logInfo("Instantiating a mock staker");
        address[] memory rewardTokens = new address[](1);
        rewardTokens[0] = address(2);
        vm.prank(owner);
        staker = new Staker(owner, address(token), treasury, MINIMUM_DEPOSIT, DEFAULT_STAKER_FEE, rewardTokens);
        LogUtils.logInfo(string.concat("[TOKEN] ", vm.toString(address(token))));
        LogUtils.logInfo(string.concat("[TREASURY] ", vm.toString(address(treasury))));

        LogUtils.logInfo("Instantiating an Airdrop implementation");
        airdropImpl = new Airdrop();
        LogUtils.logInfo(string.concat("[AIRIMPL] ", vm.toString(address(airdropImpl))));

        LogUtils.logInfo("Instantiating an Airdrop Factory");
        factory = new AirdropFactory(address(airdropImpl), owner);

        LogUtils.logInfo(string.concat("[FACTORY] ", vm.toString(address(factory))));

        LogUtils.logInfo("Pushing timestamps");
        timestamps.push(block.timestamp + 1 days);
        timestamps.push(block.timestamp + 7 days);
    }

    /* TEST: test_Constructor - - - - - - - - - - - - - - - - - - - - - - - - - -/
     * Tests that constructor properly sets implementation and owner - - - - - -*/
    function test_Constructor() public view {
        LogUtils.logDebug("Testing constructor initialization");

        assertEq(factory.implementation(), address(airdropImpl));
        assertEq(factory.owner(), owner);
    }

    /* TEST: test_Constructor_EmitsEvent - - - - - - - - - - - - - - - - - - - -/
     * Tests that constructor emits ImplementationSet event - - - - - - - - - -*/
    function test_Constructor_EmitsEvent() public {
        LogUtils.logDebug("Testing constructor event emission");

        vm.expectEmit();
        emit AirdropFactory.ImplementationSet(address(airdropImpl));

        AirdropFactory newFactory = new AirdropFactory(address(airdropImpl), owner);

        assertEq(newFactory.implementation(), address(airdropImpl));
    }

    /* TEST: test_SetImplementation - - - - - - - - - - - - - - - - - - - - - - -/
     * Tests setting a new implementation address - - - - - - - - - - - - - - -*/
    function test_SetImplementation() public {
        LogUtils.logDebug("Testing setImplementation functionality");

        LogUtils.logInfo("Creating new implementation");
        Airdrop newImpl = new Airdrop();

        LogUtils.logInfo("Setting new implementation");
        vm.expectEmit();
        emit AirdropFactory.ImplementationSet(address(newImpl));
        vm.prank(owner);
        factory.setImplementation(address(newImpl));

        assertEq(factory.implementation(), address(newImpl));
    }

    /* TEST: test_SetImplementation_RevertWhenNotOwner - - - - - - - - - - - - - /
     * Tests that only owner can set implementation - - - - - - - - - - - - - -*/
    function test_SetImplementation_RevertWhenNotOwner() public {
        LogUtils.logDebug("Testing setImplementation revert when not owner");

        Airdrop newImpl = new Airdrop();

        vm.expectRevert();
        vm.prank(notOwner);
        factory.setImplementation(address(newImpl));
    }

    /* TEST: test_Deploy_Success - - - - - - - - - - - - - - - - - - - - - - - - /
     * Tests successful deployment of new airdrop instance - - - - - - - - - - */
    function test_Deploy_Success() public {
        LogUtils.logDebug("Testing successful deployment");

        LogUtils.logInfo("Deploying new airdrop instance");
        vm.prank(owner);
        address instance = factory.deploy(
            address(token),
            address(staker),
            signer,
            address(0), // Should default to owner
            timestamps
        );

        LogUtils.logInfo(string.concat("Deployed instance at: ", vm.toString(instance)));

        // Verify deployment
        assertTrue(instance != address(0));
        assertEq(factory.noOfDeployments(), 1);
        assertEq(factory.getLatestDeployment(), instance);
        assertTrue(factory.isDeployedThroughFactory(instance));
        assertEq(factory.deploymentToImplementation(instance), address(airdropImpl));

        // Verify instance initialization
        Airdrop airdrop = Airdrop(instance);
        assertEq(address(airdrop.token()), address(token));
        assertEq(airdrop.staker(), address(staker));
        assertEq(airdrop.signer(), signer);
        assertEq(airdrop.owner(), owner); // Should default to factory owner
        assertEq(airdrop.unlocks(0), timestamps[0]);
        assertEq(airdrop.unlocks(1), timestamps[1]);
    }

    /* TEST: test_Deploy_WithCustomOwner - - - - - - - - - - - - - - - - - - - - /
     * Tests deployment with custom owner address - - - - - - - - - - - - - - -*/
    function test_Deploy_WithCustomOwner() public {
        LogUtils.logDebug("Testing deployment with custom owner");

        address customOwner = makeAddr("customOwner");

        vm.prank(owner);
        address instance = factory.deploy(address(token), address(staker), signer, customOwner, timestamps);

        Airdrop airdrop = Airdrop(instance);
        assertEq(airdrop.owner(), customOwner);
    }

    /* TEST: test_Deploy_EmitsEvent - - - - - - - - - - - - - - - - - - - - - - -/
     * Tests that deploy emits Deployed event - - - - - - - - - - - - - - - - -*/
    function test_Deploy_EmitsEvent() public {
        LogUtils.logDebug("Testing deploy event emission");

        LogUtils.logDebug("Expecting emit");

        address instance = address(0x50FFC001);

        vm.expectEmit(false, true, true, false);
        emit AirdropFactory.Deployed(address(instance), address(token), address(airdropImpl));

        vm.prank(owner);
        factory.deploy(address(token), address(staker), signer, owner, timestamps);
    }

    /* TEST: test_Deploy_RevertWhenNotOwner - - - - - - - - - - - - - - - - - - /
     * Tests that only owner can deploy new instances - - - - - - - - - - - - -*/
    function test_Deploy_RevertWhenNotOwner() public {
        LogUtils.logDebug("Testing deploy revert when not owner");

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, notOwner));
        vm.prank(notOwner);
        factory.deploy(address(token), address(staker), signer, owner, timestamps);
    }

    /* TEST: test_Deploy_RevertWhenImplementationNotSet - - - - - - - - - - - - -/
     * Tests deployment fails when implementation is zero address - - - - - - - */
    function test_Deploy_RevertWhenImplementationNotSet() public {
        LogUtils.logDebug("Testing deploy revert when implementation not set");

        // Set implementation to zero address
        vm.prank(owner);
        factory.setImplementation(address(0));

        vm.expectRevert(AirdropFactory.ImplementationNotSet.selector);
        vm.prank(owner);
        factory.deploy(address(token), address(staker), signer, owner, timestamps);
    }

    /* TEST: test_Deploy_MultipleInstances - - - - - - - - - - - - - - - - - - - /
     * Tests deploying multiple instances - - - - - - - - - - - - - - - - - - -*/
    function test_Deploy_MultipleInstances() public {
        LogUtils.logDebug("Testing multiple deployments");

        LogUtils.logInfo("Deploying first instance");
        vm.prank(owner);
        address instance1 = factory.deploy(address(token), address(staker), signer, alice, timestamps);

        LogUtils.logInfo("Deploying second instance");
        vm.prank(owner);
        address instance2 = factory.deploy(address(token), address(staker), signer, bob, timestamps);

        LogUtils.logInfo("Deploying third instance");
        vm.prank(owner);
        address instance3 = factory.deploy(address(token), address(staker), signer, charlie, timestamps);

        // Verify all deployments
        assertEq(factory.noOfDeployments(), 3);
        assertEq(factory.getLatestDeployment(), instance3);

        assertTrue(factory.isDeployedThroughFactory(instance1));
        assertTrue(factory.isDeployedThroughFactory(instance2));
        assertTrue(factory.isDeployedThroughFactory(instance3));

        assertEq(factory.deployments(0), instance1);
        assertEq(factory.deployments(1), instance2);
        assertEq(factory.deployments(2), instance3);
    }

    /* TEST: test_NoOfDeployments - - - - - - - - - - - - - - - - - - - - - - - -/
     * Tests noOfDeployments returns correct count - - - - - - - - - - - - - - */
    function test_NoOfDeployments() public {
        LogUtils.logDebug("Testing noOfDeployments");

        assertEq(factory.noOfDeployments(), 0);

        vm.prank(owner);
        factory.deploy(address(token), address(staker), signer, owner, timestamps);
        assertEq(factory.noOfDeployments(), 1);

        vm.prank(owner);
        factory.deploy(address(token), address(staker), signer, owner, timestamps);
        assertEq(factory.noOfDeployments(), 2);
    }

    /* TEST: test_GetLatestDeployment_WhenNoDeployments - - - - - - - - - - - - -/
     * Tests getLatestDeployment returns zero when no deployments - - - - - - -*/
    function test_GetLatestDeployment_WhenNoDeployments() public view {
        LogUtils.logDebug("Testing getLatestDeployment with no deployments");

        assertEq(factory.getLatestDeployment(), address(0));
    }

    /* TEST: test_GetLatestDeployment_WithDeployments - - - - - - - - - - - - - -/
     * Tests getLatestDeployment returns correct address - - - - - - - - - - - */
    function test_GetLatestDeployment_WithDeployments() public {
        LogUtils.logDebug("Testing getLatestDeployment with deployments");

        vm.prank(owner);
        address instance1 = factory.deploy(address(token), address(staker), signer, owner, timestamps);
        assertEq(factory.getLatestDeployment(), instance1);

        vm.prank(owner);
        address instance2 = factory.deploy(address(token), address(staker), signer, owner, timestamps);
        assertEq(factory.getLatestDeployment(), instance2);
    }

    /* TEST: test_GetDeployments_Success - - - - - - - - - - - - - - - - - - - - /
     * Tests getDeployments returns correct range - - - - - - - - - - - - - - -*/
    function test_GetDeployments_Success() public {
        LogUtils.logDebug("Testing getDeployments");

        // Deploy 5 instances
        address[] memory instances = new address[](5);
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(owner);
            instances[i] = factory.deploy(address(token), address(staker), signer, owner, timestamps);
        }

        // Get deployments from index 1 to 3
        address[] memory deployments = factory.getDeployments(1, 3);

        assertEq(deployments.length, 3);
        assertEq(deployments[0], instances[1]);
        assertEq(deployments[1], instances[2]);
        assertEq(deployments[2], instances[3]);

        // Get all deployments
        deployments = factory.getDeployments(0, 4);
        assertEq(deployments.length, 5);
        for (uint256 i = 0; i < 5; i++) {
            assertEq(deployments[i], instances[i]);
        }
    }

    /* TEST: test_GetDeployments_SingleElement - - - - - - - - - - - - - - - - - /
     * Tests getDeployments with single element range - - - - - - - - - - - - -*/
    function test_GetDeployments_SingleElement() public {
        LogUtils.logDebug("Testing getDeployments with single element");

        vm.prank(owner);
        address instance = factory.deploy(address(token), address(staker), signer, owner, timestamps);

        address[] memory deployments = factory.getDeployments(0, 0);
        assertEq(deployments.length, 1);
        assertEq(deployments[0], instance);
    }

    /* TEST: test_GetDeployments_RevertWhenInvalidRange - - - - - - - - - - - - -/
     * Tests getDeployments reverts on invalid range - - - - - - - - - - - - - */
    function test_GetDeployments_RevertWhenInvalidRange() public {
        LogUtils.logDebug("Testing getDeployments revert on invalid range");

        // Deploy 3 instances
        for (uint256 i = 0; i < 3; i++) {
            vm.prank(owner);
            factory.deploy(address(token), address(staker), signer, owner, timestamps);
        }

        // Test endIndex < startIndex
        vm.expectRevert(AirdropFactory.InvalidIndexRange.selector);
        factory.getDeployments(2, 1);

        // Test endIndex >= deployments.length
        vm.expectRevert(AirdropFactory.InvalidIndexRange.selector);
        factory.getDeployments(0, 3);

        // Test when array is empty
        // Deploy new factory with no deployments
        AirdropFactory emptyFactory = new AirdropFactory(address(airdropImpl), owner);

        vm.expectRevert(AirdropFactory.InvalidIndexRange.selector);
        emptyFactory.getDeployments(0, 0);
    }

    /* TEST: test_IsDeployedThroughFactory - - - - - - - - - - - - - - - - - - - /
     * Tests isDeployedThroughFactory correctly identifies deployments - - - - */
    function test_IsDeployedThroughFactory() public {
        LogUtils.logDebug("Testing isDeployedThroughFactory");

        // Deploy through factory
        vm.prank(owner);
        address factoryDeployment = factory.deploy(address(token), address(staker), signer, owner, timestamps);

        // Deploy directly (not through factory)
        Airdrop directDeployment = new Airdrop();

        assertTrue(factory.isDeployedThroughFactory(factoryDeployment));
        assertFalse(factory.isDeployedThroughFactory(address(directDeployment)));
        assertFalse(factory.isDeployedThroughFactory(address(0)));
        assertFalse(factory.isDeployedThroughFactory(alice));
    }

    /* TEST: test_DeploymentToImplementation_Mapping - - - - - - - - - - - - - - /
     * Tests deploymentToImplementation mapping is correctly set - - - - - - - */
    function test_DeploymentToImplementation_Mapping() public {
        LogUtils.logDebug("Testing deploymentToImplementation mapping");

        // Deploy with first implementation
        vm.prank(owner);
        address instance1 = factory.deploy(address(token), address(staker), signer, owner, timestamps);
        assertEq(factory.deploymentToImplementation(instance1), address(airdropImpl));

        // Change implementation
        Airdrop newImpl = new Airdrop();
        vm.prank(owner);
        factory.setImplementation(address(newImpl));

        // Deploy with new implementation
        vm.prank(owner);
        address instance2 = factory.deploy(address(token), address(staker), signer, owner, timestamps);
        assertEq(factory.deploymentToImplementation(instance2), address(newImpl));

        // Verify first deployment still points to old implementation
        assertEq(factory.deploymentToImplementation(instance1), address(airdropImpl));
    }

    /* TEST: test_Deploy_InitializationFailure - - - - - - - - - - - - - - - - - /
     * Tests deployment handles initialization failure - - - - - - - - - - - - -*/
    function test_Deploy_InitializationFailure() public {
        LogUtils.logDebug("Testing deployment with initialization failure");

        // Deploy with invalid parameters that will cause initialization to fail
        vm.expectRevert();
        vm.prank(owner);
        factory.deploy(
            address(0), // Invalid token address
            address(staker),
            signer,
            owner,
            timestamps
        );

        // Verify no deployment was recorded
        assertEq(factory.noOfDeployments(), 0);
    }

    /* TEST: test_Deployments_ArrayAccess - - - - - - - - - - - - - - - - - - - -/
     * Tests direct access to deployments array - - - - - - - - - - - - - - - -*/
    function test_Deployments_ArrayAccess() public {
        LogUtils.logDebug("Testing deployments array direct access");

        vm.prank(owner);
        address instance1 = factory.deploy(address(token), address(staker), signer, owner, timestamps);
        vm.prank(owner);
        address instance2 = factory.deploy(address(token), address(staker), signer, owner, timestamps);
        vm.prank(owner);
        address instance3 = factory.deploy(address(token), address(staker), signer, owner, timestamps);

        assertEq(factory.deployments(0), instance1);
        assertEq(factory.deployments(1), instance2);
        assertEq(factory.deployments(2), instance3);
    }

    /* TEST: test_ClonePattern_Verification - - - - - - - - - - - - - - - - - - -/
     * Tests that clones are properly created using EIP-1167 pattern - - - - - */
    function test_ClonePattern_Verification() public {
        LogUtils.logDebug("Testing clone pattern implementation");

        vm.prank(owner);
        address instance1 = factory.deploy(address(token), address(staker), signer, owner, timestamps);
        vm.prank(owner);
        address instance2 = factory.deploy(address(token), address(staker), signer, owner, timestamps);

        // Verify instances are different addresses
        assertTrue(instance1 != instance2);

        // Verify both point to same implementation
        assertEq(factory.deploymentToImplementation(instance1), factory.deploymentToImplementation(instance2));

        // Verify instances have minimal bytecode (characteristic of clones)
        uint256 codeSize1;
        uint256 codeSize2;
        assembly {
            codeSize1 := extcodesize(instance1)
            codeSize2 := extcodesize(instance2)
        }

        LogUtils.logInfo(string.concat("Clone 1 code size: ", vm.toString(codeSize1)));
        LogUtils.logInfo(string.concat("Clone 2 code size: ", vm.toString(codeSize2)));

        // Clone bytecode should be small (45 bytes for EIP-1167)
        assertEq(codeSize1, 45);
        assertEq(codeSize2, 45);
        assertEq(codeSize1, codeSize2);
    }
    /* TEST: test_Debug_DecodeError - - - - - - - - - - - - - - - - - - - - - - - -/
    * Decode the exact 4-byte error from initialization - - - - - - - - - - - - */

    function test_Debug_DecodeError() public {
        LogUtils.logDebug("=== DECODING INITIALIZATION ERROR ===");

        Airdrop directAirdrop = new Airdrop();

        try directAirdrop.initialize(address(token), address(staker), signer, owner, timestamps) {
            LogUtils.logDebug(" Initialization succeeded");
        } catch (bytes memory lowLevelData) {
            LogUtils.logDebug(" Initialization failed");
            LogUtils.logDebug(string.concat("Error data length: ", vm.toString(lowLevelData.length)));

            if (lowLevelData.length >= 4) {
                // Extract the 4-byte error selector
                bytes4 errorSelector;
                assembly {
                    errorSelector := mload(add(lowLevelData, 0x20))
                }
                LogUtils.logDebug(string.concat("Error selector: 0x", vm.toString(uint256(uint32(errorSelector)))));

                // Check common error selectors
                bytes4 notOwnerSelector = bytes4(keccak256("OwnableUnauthorizedAccount(address)"));
                bytes4 initializedSelector = bytes4(keccak256("InvalidInitialization()"));
                bytes4 alreadyInitializedSelector = bytes4(keccak256("AlreadyInitialized()"));

                LogUtils.logDebug(
                    string.concat(
                        "OwnableUnauthorizedAccount selector: 0x", vm.toString(uint256(uint32(notOwnerSelector)))
                    )
                );
                LogUtils.logDebug(
                    string.concat(
                        "InvalidInitialization selector: 0x", vm.toString(uint256(uint32(initializedSelector)))
                    )
                );
                LogUtils.logDebug(
                    string.concat(
                        "AlreadyInitialized selector: 0x", vm.toString(uint256(uint32(alreadyInitializedSelector)))
                    )
                );

                if (errorSelector == notOwnerSelector) {
                    LogUtils.logDebug("ERROR: OwnableUnauthorizedAccount - ownership issue");
                } else if (errorSelector == initializedSelector) {
                    LogUtils.logDebug("ERROR: InvalidInitialization - initialization state issue");
                } else if (errorSelector == alreadyInitializedSelector) {
                    LogUtils.logDebug("ERROR: AlreadyInitialized - contract already initialized");
                } else {
                    LogUtils.logDebug("ERROR: Unknown custom error");
                }
            }
        }
    }

    /* TEST: test_Debug_ParameterValidation - - - - - - - - - - - - - - - - - - - -/
    * Test each parameter individually to isolate the issue - - - - - - - - - - */
    function test_Debug_ParameterValidation() public {
        LogUtils.logDebug("=== PARAMETER VALIDATION ===");

        // Check if any of our parameters are causing issues
        LogUtils.logDebug("Checking each parameter:");
        LogUtils.logDebug(string.concat("Token address: ", vm.toString(address(token))));
        LogUtils.logDebug(string.concat("Token is contract: ", address(token).code.length > 0 ? "true" : "false"));

        LogUtils.logDebug(string.concat("Staker address: ", vm.toString(address(staker))));
        LogUtils.logDebug(string.concat("Staker is contract: ", address(staker).code.length > 0 ? "true" : "false"));

        LogUtils.logDebug(string.concat("Treasury address: ", vm.toString(treasury)));
        LogUtils.logDebug(string.concat("Treasury is contract: ", treasury.code.length > 0 ? "true" : "false"));

        LogUtils.logDebug(string.concat("Signer address: ", vm.toString(signer)));
        LogUtils.logDebug(string.concat("Signer is contract: ", signer.code.length > 0 ? "true" : "false"));

        LogUtils.logDebug(string.concat("Owner address: ", vm.toString(owner)));
        LogUtils.logDebug(string.concat("Owner is contract: ", owner.code.length > 0 ? "true" : "false"));

        LogUtils.logDebug(string.concat("Timestamps array length: ", vm.toString(timestamps.length)));
        for (uint256 i = 0; i < timestamps.length; i++) {
            LogUtils.logDebug(string.concat("Timestamp[", vm.toString(i), "]: ", vm.toString(timestamps[i])));
            LogUtils.logDebug(string.concat("Current block.timestamp: ", vm.toString(block.timestamp)));
            LogUtils.logDebug(
                string.concat("Is future timestamp: ", timestamps[i] > block.timestamp ? "true" : "false")
            );
        }
    }

    /* TEST: test_Debug_CheckInitializeFunction - - - - - - - - - - - - - - - - - -/
    * Verify the initialize function exists with correct signature - - - - - - - */
    function test_Debug_CheckInitializeFunction() public {
        LogUtils.logDebug("=== CHECKING INITIALIZE FUNCTION ===");

        bytes4 expectedSelector = bytes4(keccak256("initialize(address,address,address,address,address,uint256[])"));
        LogUtils.logDebug(
            string.concat("Expected initialize selector: 0x", vm.toString(uint256(uint32(expectedSelector))))
        );

        // Try to call with staticcall to check if function exists
        Airdrop directAirdrop = new Airdrop();
        bytes memory data =
            abi.encodeWithSelector(expectedSelector, address(token), address(staker), signer, owner, timestamps);

        LogUtils.logDebug("Attempting call to initialize function...");
        (bool success, bytes memory result) = address(directAirdrop).call(data);
        LogUtils.logDebug(string.concat("Call success: ", success ? "true" : "false"));
        LogUtils.logDebug(string.concat("Result length: ", vm.toString(result.length)));

        if (!success && result.length == 0) {
            LogUtils.logDebug("ERROR: Function does not exist or has wrong signature");
        }
    }
}
