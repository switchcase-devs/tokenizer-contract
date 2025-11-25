// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { Test } from "forge-std/Test.sol";
import { RealEstateToken } from "src/RealEstateToken.sol";
import { Actors } from "test/utils/Actors.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { ITransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

contract RealEstateToken_Locks_ForceTransfer_Test is Test {
    RealEstateToken token;
    address admin = address(this);
    address alice = Actors.ALICE;
    address bob   = Actors.BOB;

    function setUp() public {
        RealEstateToken impl = new RealEstateToken();
        bytes memory initData = abi.encodeWithSelector(
            RealEstateToken.initialize.selector,
            "Estate",
            "EST",
            uint256(500_000),
            admin
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        token = RealEstateToken(payable(address(proxy)));

        // `admin` receives all privileged roles in initialize, including ROLE_TRANSFER, ROLE_WHITELIST, ROLE_TRANSFER_RESTRICT, ROLE_PAUSER
        assertTrue(token.transfer(alice, 100_000));
        assertTrue(token.transfer(bob,   100_000));
    }

    function test_LockUnlock_EdgeCases() public {
        vm.expectRevert(abi.encodeWithSelector(RealEstateToken.LockExceedsUnlocked.selector, alice, uint256(0), uint256(100_000)));
        token.lockBalance(alice, 0);

        vm.expectRevert(abi.encodeWithSelector(RealEstateToken.LockExceedsUnlocked.selector, alice, uint256(100_001), uint256(100_000)));
        token.lockBalance(alice, 100_001);

        token.lockBalance(alice, 60_000);

        token.setWhitelistMode(true);
        token.setWhitelist(alice, true);
        token.setWhitelist(bob,   true);

        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(RealEstateToken.LockExceedsUnlocked.selector, alice, uint256(40_001), uint256(40_000)));
        token.transfer(bob, 40_001);
        vm.stopPrank();

        vm.prank(alice);
        token.transfer(bob, 40_000);

        vm.expectRevert(abi.encodeWithSelector(RealEstateToken.UnlockExceedsLocked.selector, alice, uint256(0), uint256(60_000)));
        token.unlockBalance(alice, 0);

        vm.expectRevert(abi.encodeWithSelector(RealEstateToken.UnlockExceedsLocked.selector, alice, uint256(60_001), uint256(60_000)));
        token.unlockBalance(alice, 60_001);

        token.unlockBalance(alice, 60_000);
    }

    function test_ForceTransfer_BypassesLocksAndWhitelist() public {
        // whitelist mode ON, only Alice whitelisted; Bob intentionally NOT whitelisted
        token.setWhitelistMode(true);
        token.setWhitelist(alice, true);

        // Admin (this) already has ROLE_TRANSFER and ROLE_TRANSFER_RESTRICT from initialize
        token.lockBalance(alice, 90_000); // leaves 10_000 unlocked

        bytes memory evidence = bytes("court:xyz");

        // Bypass lock & whitelist with forceTransfer:
        // attempt to move 10_001 (> unlocked) to non-whitelisted bob → should still succeed
        token.forceTransfer(alice, bob, 10_001, evidence);
        assertEq(token.balanceOf(bob), 100_000 + 10_001);

        // And can move additional 10_000 (still bypassing locks/whitelist)
        token.forceTransfer(alice, bob, 10_000, evidence);
        assertEq(token.balanceOf(bob), 100_000 + 10_001 + 10_000);
    }

    function test_ForceTransfer_RejectedWhenPaused() public {
        token.grantRole(token.ROLE_TRANSFER(), admin);
        token.pause();
        vm.expectRevert(bytes4(keccak256("EnforcedPause()")));
        token.forceTransfer(alice, bob, 1, bytes("x"));
    }

    function test_Mint_To_Frozen_Address_Reverts() public {
        token.setFrozen(bob, true);

        uint256 pre = token.balanceOf(bob);

        vm.expectRevert(
            abi.encodeWithSelector(RealEstateToken.AccountFrozen.selector, bob)
        );
        token.mint(bob, 1_234);

        assertEq(token.balanceOf(bob), pre);
    }

    function test_Mint_To_Unwhitelisted_Address_While_Whitelist_Enabled_Reverts() public {
        token.setWhitelistMode(true);
        token.setWhitelist(alice, true);

        uint256 pre = token.balanceOf(bob);

        vm.expectRevert(
            abi.encodeWithSelector(RealEstateToken.NotWhitelisted.selector, bob)
        );
        token.mint(bob, 2_345);

        assertEq(token.balanceOf(bob), pre);
    }
}