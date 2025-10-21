// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Test } from "forge-std/Test.sol";
import { RealEstateToken } from "src/RealEstateToken.sol";
import { Actors } from "test/utils/Actors.sol";

contract RealEstateToken_Votes_Test is Test {
    RealEstateToken token;
    address admin = address(this);
    address alice = Actors.ALICE;
    address bob   = Actors.BOB;

    function setUp() public {
        token = new RealEstateToken("Estate", "EST", 1_000_000, admin);
        assertTrue(token.transfer(alice, 100_000));
        assertTrue(token.transfer(bob,   50_000));
        token.setWhitelistMode(true);
        token.setWhitelist(alice, true);
        token.setWhitelist(bob, true);
        vm.prank(alice); assertTrue(token.transfer(alice, 0));
        vm.prank(bob);   assertTrue(token.transfer(bob, 0));
    }

    function test_SelfDelegationOnly_ThirdPartyDisabled() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(RealEstateToken.DelegationDisabled.selector));
        token.delegate(bob);
        vm.prank(alice);
        token.delegate(alice);
    }

    function test_VotesTrackOnMintBurnTransfer() public {
        assertEq(token.getVotes(alice), token.balanceOf(alice));
        assertEq(token.getVotes(bob),   token.balanceOf(bob));
        token.grantRole(token.ROLE_MINTER(), admin);
        token.mint(bob, 10_000);
        assertEq(token.getVotes(bob), token.balanceOf(bob));
        token.grantRole(token.ROLE_BURNER(), admin);
        vm.prank(alice); assertTrue(token.approve(admin, 5_000));
        token.burnFrom(alice, 5_000);
        assertEq(token.getVotes(alice), token.balanceOf(alice));
        token.setWhitelistMode(true);
        token.setWhitelist(alice, true);
        token.setWhitelist(bob,   true);
        vm.prank(alice); assertTrue(token.transfer(bob, 1234));
        assertEq(token.getVotes(alice), token.balanceOf(alice));
        assertEq(token.getVotes(bob),   token.balanceOf(bob));
    }
}
