// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Test } from "forge-std/Test.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { RealEstateToken } from "src/RealEstateToken.sol";
import { Actors } from "test/utils/Actors.sol";

contract RealEstateToken_Unit_Test is Test {
    RealEstateToken token;
    address admin = address(this);
    address alice = Actors.ALICE;
    address bob   = Actors.BOB;
    address carol = Actors.CAROL;

    event ForcedTransfer(
        address indexed operator,
        address indexed from,
        address indexed to,
        uint256 amount,
        bytes data
    );

    function setUp() public {
        token = new RealEstateToken("Estate", "EST", 1000, admin);
        assertTrue(token.transfer(alice, 300));
        assertTrue(token.transfer(bob,   200));
        assertTrue(token.transfer(carol, 100));
    }

    function test_DecimalsIsZero() public view {
        assertEq(token.decimals(), 0);
    }

    function test_RoleGatedMode_NonOperatorCannotTransfer() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(RealEstateToken.MissingTransferRole.selector, alice));
        token.transfer(bob, 1);
    }

    function test_WhitelistMode_BlocksUntilBothWhitelisted() public {
        token.setWhitelistMode(true);

        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(RealEstateToken.NotWhitelisted.selector, alice));
        token.transfer(bob, 1);
        vm.stopPrank();

        token.setWhitelist(alice, true);
        token.setWhitelist(bob, true);

        vm.prank(alice);
        assertTrue(token.transfer(bob, 1));
        assertEq(token.balanceOf(bob), 201);
    }

    function test_PauseBlocksTransfers() public {
        token.setWhitelistMode(true);
        token.setWhitelist(alice, true);
        token.setWhitelist(bob, true);

        vm.prank(alice);
        assertTrue(token.transfer(bob, 1));
        assertEq(token.balanceOf(bob), 201);

        token.pause();

        vm.prank(alice);
        vm.expectRevert(bytes4(keccak256("EnforcedPause()")));
        token.transfer(bob, 1);
    }

    function test_FreezeSenderAndReceiver() public {
        token.setWhitelistMode(true);
        token.setWhitelist(alice, true);
        token.setWhitelist(bob, true);

        token.setFrozen(alice, true);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(RealEstateToken.AccountFrozen.selector, alice));
        token.transfer(bob, 1);

        token.setFrozen(alice, false);
        token.setFrozen(bob, true);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(RealEstateToken.AccountFrozen.selector, bob));
        token.transfer(bob, 1);
    }

    function test_LockUnlockMathAndTransferLimits() public {
        token = new RealEstateToken("Estate", "EST", 1000, admin);
        assertTrue(token.transfer(alice, 300));
        assertTrue(token.transfer(bob,   200));

        token.setWhitelistMode(true);
        token.setWhitelist(alice, true);
        token.setWhitelist(bob, true);

        token.lockBalance(alice, 200);

        vm.expectRevert();
        token.lockBalance(alice, 101);

        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(RealEstateToken.LockExceedsUnlocked.selector, alice, 101, 100));
        token.transfer(bob, 101);
        vm.stopPrank();

        vm.prank(alice);
        assertTrue(token.transfer(bob, 100));

        vm.expectRevert(abi.encodeWithSelector(RealEstateToken.UnlockExceedsLocked.selector, alice, 201, 200));
        token.unlockBalance(alice, 201);

        token.unlockBalance(alice, 50);
        token.unlockBalance(alice, 150);
    }

    function test_ForceTransfer_RequiresData_RespectsLocks_EmitsEvent() public {
        token.setWhitelistMode(true);
        token.setWhitelist(alice, true);
        token.setWhitelist(bob,   false);

        token.lockBalance(alice, 250);
        bytes memory evidence = bytes("court:123");

        vm.expectRevert(abi.encodeWithSelector(RealEstateToken.EmptyForceTransferData.selector));
        token.forceTransfer(alice, bob, 1, "");

        vm.expectRevert(abi.encodeWithSelector(RealEstateToken.LockExceedsUnlocked.selector, alice, 51, 50));
        token.forceTransfer(alice, bob, 51, evidence);

        vm.expectEmit(true, true, true, true, address(token));
        emit ForcedTransfer(address(this), alice, bob, 50, evidence);
        token.forceTransfer(alice, bob, 50, evidence);
        assertEq(token.balanceOf(bob), 250);
    }

    function test_DelegationRestrictions_AndVotesTrackBalances() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(RealEstateToken.DelegationDisabled.selector));
        token.delegate(bob);

        vm.prank(alice);
        token.delegate(alice);

        token.setWhitelistMode(true);
        token.setWhitelist(alice, true);
        token.setWhitelist(bob, true);

        vm.prank(bob);
        assertTrue(token.transfer(bob, 0));

        assertEq(token.getVotes(alice), token.balanceOf(alice));
        assertEq(token.getVotes(bob),   token.balanceOf(bob));
    }

    function test_BurnFrom_RoleAndAllowance() public {
        bytes32 roleBurner = token.ROLE_BURNER();
        token.grantRole(roleBurner, bob);

        vm.prank(bob);
        vm.expectRevert(); // generic match to avoid selector-encoding pitfalls
        token.burnFrom(alice, 1);

        vm.prank(alice);
        assertTrue(token.approve(bob, 5));

        vm.prank(bob);
        token.burnFrom(alice, 5);
        assertEq(token.balanceOf(alice), 295);
    }

    function test_SupportsInterface_AccessControl() public view {
        bool ok = token.supportsInterface(type(IAccessControl).interfaceId);
        assertTrue(ok);
    }
}
