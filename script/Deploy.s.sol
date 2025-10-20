// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/RealEstateToken.sol";

contract Deploy is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address admin = vm.envAddress("ADMIN", vm.addr(pk));

        vm.startBroadcast(pk);
        RealEstateToken token = new RealEstateToken("Estate", "EST", 1_000_000, admin);
        vm.stopBroadcast();

        console2.log("RealEstateToken deployed at", address(token));
    }
}
