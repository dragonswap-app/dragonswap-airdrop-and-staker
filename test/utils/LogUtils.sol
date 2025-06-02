// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/console.sol";
import {Vm} from "forge-std/Vm.sol";

library LogUtils {
    /* Color constants */
    string constant INFCOLOR = "\x1B[34m"; // Blue
    string constant WRNCOLOR = "\x1B[33m"; // Yellow
    string constant DBGCOLOR = "\x1B[35m"; // Magenta
    string constant ERRCOLOR = "\x1B[31m"; // Red
    string constant SUCCOLOR = "\x1B[32m"; // Green
    string constant NOCOLOR = "\x1B[0m"; // Reset

    /**
     * @dev Log info message in blue
     */
    function logInfo(string memory message) internal pure {
        console.log(INFCOLOR, "[INFO] ", NOCOLOR, message);
    }

    /**
     * @dev Log warning message in yellow
     */
    function logWarning(string memory message) internal pure {
        console.log(WRNCOLOR, "[WARN] ", NOCOLOR, message);
    }

    /**
     * @dev Log error message in red
     */
    function logError(string memory message) internal pure {
        console.log(ERRCOLOR, "[ERROR]", NOCOLOR, message);
    }

    /**
     * @dev Log debug message in magenta
     */
    function logDebug(string memory message) internal pure {
        console.log(DBGCOLOR, "[DEBUG]", NOCOLOR, message);
    }

    /**
     * @dev Log success message in green
     */
    function logSuccess(string memory message) internal pure {
        console.log(SUCCOLOR, "[SUCCESS]", NOCOLOR, message);
    }
}
