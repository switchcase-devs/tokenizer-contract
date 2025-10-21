// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Test } from "forge-std/Test.sol";
import { RealEstateToken } from "src/RealEstateToken.sol";
import { Actors } from "test/utils/Actors.sol";

contract RealEstateToken_MoreInvariants is Test {
    RealEstateToken token;
    address admin = address(this);
    address alice = Actors.ALICE;
    address bob   = Actors.BOB;

    function setUp() public {
        token = new RealEstateToken("Estate", "EST", 1000, admin);
        assertTrue(token.transfer(alice, 300));
        assertTrue(token.transfer(bob,   200));
        token.setWhitelistMode(true);
        token.setWhitelist(alice, true);
        token.setWhitelist(bob, true);
    }

    function testInvariant_TransfersConserveSupply() public {
        uint256 supplyBefore = token.totalSupply();
        vm.prank(alice); token.transfer(bob, 10);
        assertEq(token.totalSupply(), supplyBefore);
        vm.prank(bob); token.transfer(alice, 5);
        assertEq(token.totalSupply(), supplyBefore);
    }

    function testInvariant_NoTransfersWhenPaused() public {
        token.pause();
        vm.prank(alice);
        vm.expectRevert(bytes4(keccak256("EnforcedPause()")));
        token.transfer(bob, 1);
        token.unpause();
        vm.prank(alice);
        assertTrue(token.transfer(bob, 1));
    }
}
