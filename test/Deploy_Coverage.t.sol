// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Deploy} from "script/Deploy.s.sol";

contract Deploy_Coverage_Test is Test {
    function test_Run_Script_Covers() public {
        vm.setEnv("PRIVATE_KEY", "1");
        Deploy d = new Deploy();
        d.run();
    }
}
