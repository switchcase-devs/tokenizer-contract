// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { Test } from "forge-std/Test.sol";
import { RealEstateToken } from "src/RealEstateToken.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract RealEstateToken_MintBurn_Test is Test {
    RealEstateToken token;

    address admin = address(this);
    address alice;
    address bob;
    address stranger;
    address charlie;

    function setUp() public {
        RealEstateToken impl = new RealEstateToken();
        bytes memory initData = abi.encodeWithSelector(
            RealEstateToken.initialize.selector,
            "Estate",
            "EST",
            uint256(1_000_000),
            admin
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        token = RealEstateToken(payable(address(proxy)));

        alice    = vm.addr(1);
        bob      = vm.addr(2);
        stranger = vm.addr(3);
        charlie  = vm.addr(4);

        token.transfer(alice, 50_000);
        token.transfer(bob,   50_000);

        token.setWhitelistMode(true);
        token.setWhitelist(alice, true);
        token.setWhitelist(bob,   true);
        token.setWhitelist(admin, true);
    }

    function test_Mint_RequiresMinterRole() public {
        vm.prank(stranger);
        vm.expectRevert();
        token.mint(alice, 1_000);

        uint256 balBefore = token.balanceOf(alice);
        token.mint(alice, 1_000);
        uint256 balAfter = token.balanceOf(alice);

        assertEq(balAfter, balBefore + 1_000);
    }

    function test_Burn_RequiresBurnerRole() public {
        uint256 balBefore = token.balanceOf(admin);

        vm.prank(stranger);
        vm.expectRevert();
        token.burn(1_000);

        token.burn(1_000);
        uint256 balAfter = token.balanceOf(admin);

        assertEq(balAfter, balBefore - 1_000);
    }

    function test_BurnFrom_RequiresBurnerRole() public {
        uint256 amt = 2_000;

        vm.prank(alice);
        token.approve(stranger, amt);

        vm.prank(stranger);
        vm.expectRevert();
        token.burnFrom(alice, amt);

        vm.prank(alice);
        token.approve(admin, amt);

        uint256 balBefore = token.balanceOf(alice);
        token.burnFrom(alice, amt);
        uint256 balAfter = token.balanceOf(alice);

        assertEq(balAfter, balBefore - amt);
    }

    function test_Mint_RespectsFreezeAndWhitelist() public {
        token.setWhitelistMode(true);
        token.setWhitelist(alice, true);

        token.setFrozen(alice, true);
        vm.expectRevert(
            abi.encodeWithSelector(RealEstateToken.AccountFrozen.selector, alice)
        );
        token.mint(alice, 1_000);

        token.setFrozen(alice, false);

        token.setWhitelist(alice, false);
        vm.expectRevert(
            abi.encodeWithSelector(RealEstateToken.NotWhitelisted.selector, alice)
        );
        token.mint(alice, 1_000);

        token.setWhitelist(alice, true);
        uint256 balBefore = token.balanceOf(alice);
        token.mint(alice, 1_000);
        uint256 balAfter = token.balanceOf(alice);

        assertEq(balAfter, balBefore + 1_000);
    }

    function test_Burn_RespectsFreezeAndWhitelist_OnSender() public {
        uint256 amt = 1_000;

        token.transfer(bob, amt);
        token.setWhitelist(bob, true);

        vm.prank(bob);
        vm.expectRevert();
        token.burn(amt);

        token.grantRole(token.ROLE_BURNER(), bob);

        token.setFrozen(bob, true);
        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(RealEstateToken.AccountFrozen.selector, bob)
        );
        token.burn(amt);

        token.setFrozen(bob, false);
        token.setWhitelistMode(true);
        token.setWhitelist(bob, false);

        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(RealEstateToken.NotWhitelisted.selector, bob)
        );
        token.burn(amt);

        token.setWhitelist(bob, true);

        uint256 balBefore = token.balanceOf(bob);
        vm.prank(bob);
        token.burn(amt);
        uint256 balAfter = token.balanceOf(bob);

        assertEq(balAfter, balBefore - amt);
    }

    function test_BurnFrom_RespectsFreezeAndWhitelist_OnAccount() public {
        uint256 amt = 2_000;

        vm.prank(alice);
        token.approve(admin, amt);

        token.setFrozen(alice, true);
        vm.expectRevert(
            abi.encodeWithSelector(RealEstateToken.AccountFrozen.selector, alice)
        );
        token.burnFrom(alice, amt);

        token.setFrozen(alice, false);
        token.setWhitelistMode(true);
        token.setWhitelist(alice, false);

        vm.expectRevert(
            abi.encodeWithSelector(RealEstateToken.NotWhitelisted.selector, alice)
        );
        token.burnFrom(alice, amt);

        token.setWhitelist(alice, true);

        uint256 balBefore = token.balanceOf(alice);
        token.burnFrom(alice, amt);
        uint256 balAfter = token.balanceOf(alice);

        assertEq(balAfter, balBefore - amt);
    }

    function test_Mint_DoesNotChangeLocked() public {
        uint256 lockAmt = 10_000;
        token.lockBalance(alice, lockAmt);

        uint256 lockedBefore = token.lockedBalanceOf(alice);
        uint256 balBefore    = token.balanceOf(alice);

        token.mint(alice, 3_000);

        uint256 lockedAfter = token.lockedBalanceOf(alice);
        uint256 balAfter    = token.balanceOf(alice);

        assertEq(lockedAfter, lockedBefore);
        assertEq(balAfter, balBefore + 3_000);
    }

    function test_BurnFrom_AdjustsLockedWhenBurningLockedTokens() public {
        token.transfer(charlie, 8_000);
        token.setWhitelist(charlie, true);

        uint256 balStart = token.balanceOf(charlie);
        assertEq(balStart, 8_000);

        token.lockBalance(charlie, 8_000);
        assertEq(token.lockedBalanceOf(charlie), 8_000);

        uint256 burnAmt = 1_000;

        vm.prank(charlie);
        token.approve(admin, burnAmt);

        token.burnFrom(charlie, burnAmt);

        uint256 balAfter    = token.balanceOf(charlie);
        uint256 lockedAfter = token.lockedBalanceOf(charlie);

        assertEq(balAfter, 7_000);
        assertEq(lockedAfter, balAfter);
    }

    function test_Burn_AdjustsLockedWhenBurningLockedTokens_Sender() public {
        address burner = vm.addr(10);

        token.transfer(burner, 10_000);
        token.setWhitelist(burner, true);
        token.grantRole(token.ROLE_BURNER(), burner);

        token.lockBalance(burner, 8_000);
        assertEq(token.lockedBalanceOf(burner), 8_000);

        vm.prank(burner);
        token.burn(5_000);

        uint256 balAfter    = token.balanceOf(burner);
        uint256 lockedAfter = token.lockedBalanceOf(burner);

        assertEq(balAfter, 5_000);
        assertEq(lockedAfter, 5_000);
    }
}
