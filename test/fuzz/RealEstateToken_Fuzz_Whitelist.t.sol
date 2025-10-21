// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Test } from "forge-std/Test.sol";
import { RealEstateToken } from "src/RealEstateToken.sol";
import { Actors } from "test/utils/Actors.sol";

contract RealEstateToken_Fuzz_Whitelist_Test is Test {
    RealEstateToken token;
    address admin = address(this);
    address alice = Actors.ALICE;
    address bob   = Actors.BOB;

    function setUp() public {
        token = new RealEstateToken("Estate", "EST", 1_000_000, admin);
        assertTrue(token.transfer(alice, 100_000));
        assertTrue(token.transfer(bob,   100_000));
        token.setWhitelistMode(true);
    }

    function testFuzz_WhitelistMatrix(bool wlFrom, bool wlTo, bool operator, uint96 amount) public {
        amount = uint96(bound(amount, 0, 100_000));

        token.setWhitelist(alice, wlFrom);
        token.setWhitelist(bob,   wlTo);

        if (operator) {
            token.grantRole(token.ROLE_TRANSFER(), alice);
        } else if (token.hasRole(token.ROLE_TRANSFER(), alice)) {
            token.revokeRole(token.ROLE_TRANSFER(), alice);
        }

        vm.startPrank(alice);
        if (!operator && (!wlFrom || !wlTo)) {
            vm.expectRevert(); // NotWhitelisted(from|to) even for amount == 0
            token.transfer(bob, amount);
        } else {
            bool ok = token.transfer(bob, amount);
            assertTrue(ok);
        }
        vm.stopPrank();
    }
}
