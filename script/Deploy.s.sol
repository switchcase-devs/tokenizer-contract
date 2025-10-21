// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Script } from "forge-std/Script.sol";
import { RealEstateToken } from "src/RealEstateToken.sol";

contract Deploy is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address admin = vm.addr(pk);

        vm.startBroadcast(pk);
        new RealEstateToken("Estate", "EST", 1_000_000, admin);
        vm.stopBroadcast();
    }
}
