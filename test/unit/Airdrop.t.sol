pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {Airdrop} from "src/Airdrop.sol";
import {AirdropFactory} from "src/AirdropFactory.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {console} from "forge-std/console.sol";

contract AirdropTest is Test {
    uint256 constant DEFAULT_PENALTY_WALLET = 50_00_00;
    uint256 constant DEFAULT_PENALTY_STAKER = 0;

    string constant INFCOLOR = "\x1B[34m";
    string constant WRNCOLOR = "\x1B[32m";
    string constant DBGCOLOR = "\x1B[33m";
    string constant ERRCOLOR = "\x1B[31m";
    string constant NOCOLOR = "\x1B[0m";

    Airdrop public airdropImpl;
    AirdropFactory public factory;
    Airdrop public airdrop;
    MockERC20 public token;

    address public owner = makeAddr("owner");
    address public signer = makeAddr("signer");
    address public treasury = makeAddr("treasury");
    address public staker = makeAddr("staker");

    uint256[] public timestamps;

    /* setUp - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -/
     * Pretend to be the owner address, create a mock token and an airdrop,           /
     * set up two timestamps for dates, initialize the airdrop with those timestamps */
    function setUp() public {
        /* Start pretending to be the owner */

        _log_info("Starting prank as owner");
        vm.startPrank(owner);

        /* Create a mock token */
        _log_info("Instantiating a mock token");
        token = new MockERC20("Test Token", "TEST");

        /* Create a new airdrop */
        _log_info("Instantiating an Airdrop implementation");
        airdropImpl = new Airdrop();

        /* Create a new airdrop factory */
        _log_info("Instantiating an Airdrop Factory");
        factory = new AirdropFactory(address(airdropImpl), owner);

        /* Set up the timestamps */
        _log_info("Pushing timestamps");
        timestamps.push(block.timestamp + 1 days);
        timestamps.push(block.timestamp + 7 days);

        /* Initialize the airdrop */
        _log_info("Initializing airdrop with following values:");
        _log_info(vm.toString(address(token)));
        _log_info(vm.toString(staker));
        _log_info(vm.toString(treasury));
        _log_info(vm.toString(signer));
        _log_info(vm.toString(owner));
        _log_info(vm.toString(timestamps[0]));
        _log_info(vm.toString(timestamps[1]));
        _log_info("Factory deploying...");
        address airdropAddr = factory.deploy(address(token), staker, treasury, signer, owner, timestamps);

        _log_info("Initializing airdrop");
        airdrop = Airdrop(airdropAddr);

        /* Stop pretending to be the owner */
        _log_info("Stopping prank as owner");
        vm.stopPrank();
    }

    function test_Initialize() public {
        assertEq(address(airdrop.token()), address(token));
        assertEq(airdrop.signer(), signer);
        assertEq(airdrop.treasury(), treasury);
        assertEq(airdrop.staker(), staker);
        assertEq(airdrop.owner(), owner);
        assertEq(airdrop.unlocks(0), timestamps[0]);
        assertEq(airdrop.unlocks(1), timestamps[1]);
        assertFalse(airdrop.lock());
        assertEq(airdrop.penaltyWallet(), DEFAULT_PENALTY_WALLET);
        assertEq(airdrop.penaltyStaker(), DEFAULT_PENALTY_STAKER);
    }

    function _log_info(string memory strinput) private {
        console.log(INFCOLOR, "[INFO] ", NOCOLOR, strinput);
    }
}
