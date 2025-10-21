// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Test } from "forge-std/Test.sol";
import { RealEstateToken } from "src/RealEstateToken.sol";
import { Actors } from "test/utils/Actors.sol";

contract RealEstateToken_Locks_ForceTransfer_Test is Test {
    RealEstateToken token;
    address admin = address(this);
    address alice = Actors.ALICE;
    address bob   = Actors.BOB;

    function setUp() public {
        token = new RealEstateToken("Estate", "EST", 500_000, admin);
        assertTrue(token.transfer(alice, 100_000));
        assertTrue(token.transfer(bob,   100_000));
    }

    function test_LockUnlock_EdgeCases() public {
        vm.expectRevert();
        token.lockBalance(alice, 0);
        vm.expectRevert();
        token.lockBalance(alice, 100_001);

        token.lockBalance(alice, 60_000);

        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(RealEstateToken.LockExceedsUnlocked.selector, alice, 40_001, 40_000));
        token.transfer(bob, 40_001);
        vm.stopPrank();

        vm.expectRevert();
        token.unlockBalance(alice, 0);
        vm.expectRevert(abi.encodeWithSelector(RealEstateToken.UnlockExceedsLocked.selector, alice, 60_001, 60_000));
        token.unlockBalance(alice, 60_001);

        token.unlockBalance(alice, 20_000);

        token.grantRole(token.ROLE_TRANSFER(), alice);

        vm.prank(alice);
        assertTrue(token.transfer(bob, 40_000));
    }

    function test_ForceTransfer_RespectsLocksAndWhitelistPolicy() public {
        token.setWhitelistMode(true);
        token.setWhitelist(alice, true);
        token.grantRole(token.ROLE_TRANSFER(), admin);
        token.lockBalance(alice, 90_000);
        vm.expectRevert(abi.encodeWithSelector(RealEstateToken.LockExceedsUnlocked.selector, alice, 10_001, 10_000));
        token.forceTransfer(alice, bob, 10_001, bytes("court:xyz"));
        token.forceTransfer(alice, bob, 10_000, bytes("court:xyz"));
        assertEq(token.balanceOf(bob), 110_000);
    }

    function test_ForceTransfer_RejectedWhenPaused() public {
        token.grantRole(token.ROLE_TRANSFER(), admin);
        token.pause();
        vm.expectRevert(bytes4(keccak256("EnforcedPause()")));
        token.forceTransfer(alice, bob, 1, bytes("x"));
    }
}
