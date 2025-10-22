// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Test } from "forge-std/Test.sol";
import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import { TransparentUpgradeableProxy, ITransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import { RealEstateTokenTransparentUpgradeable } from "src/upgradeable/RealEstateTokenTransparentUpgradeable.sol";
import { RealEstateTokenV2_Transparent } from "src/upgradeable/RealEstateTokenV2_Transparent.sol";
import "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

contract RealEstateToken_Transparent_Test is Test {
    ProxyAdmin proxyAdmin;
    TransparentUpgradeableProxy proxy;
    RealEstateTokenTransparentUpgradeable impl;
    RealEstateTokenTransparentUpgradeable token;

    address admin = address(this);
    address alice = address(0xA11CE);
    address bob   = address(0xB0B);
    address rando = address(0xDEAD);

    function setUp() public {
        proxyAdmin = new ProxyAdmin(admin);

        impl = new RealEstateTokenTransparentUpgradeable();

        bytes memory initData = abi.encodeWithSelector(
            RealEstateTokenTransparentUpgradeable.initialize.selector,
            "Estate",
            "EST",
            uint256(1_000_000),
            admin
        );

        proxy = new TransparentUpgradeableProxy(address(impl), admin, initData);
        token = RealEstateTokenTransparentUpgradeable(address(proxy));

        assertTrue(token.transfer(alice, 300_000));
        assertTrue(token.transfer(bob,   200_000));
    }

    function test_InitAndRoles() public view {
        assertEq(token.name(), "Estate");
        assertEq(token.symbol(), "EST");
        assertEq(token.decimals(), 0);

        assertTrue(token.hasRole(token.ROLE_ADMIN(), admin));
        assertTrue(token.hasRole(token.ROLE_TRANSFER(), admin));
        assertTrue(token.hasRole(token.ROLE_MINTER(), admin));
        assertTrue(token.hasRole(token.ROLE_BURNER(), admin));
        assertTrue(token.hasRole(token.ROLE_PAUSER(), admin));
    }

    function test_Modes_Whitelist() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(RealEstateTokenTransparentUpgradeable.MissingTransferRole.selector, alice));
        token.transfer(bob, 1);

        token.setWhitelistMode(true);
        token.setWhitelist(alice, true);
        token.setWhitelist(bob, true);

        vm.prank(alice);
        assertTrue(token.transfer(bob, 1));
    }

    function test_Freeze_Lock_Pause() public {
        token.setWhitelistMode(true);
        token.setWhitelist(alice, true);
        token.setWhitelist(bob, true);

        token.lockBalance(alice, 299_999);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(RealEstateTokenTransparentUpgradeable.LockExceedsUnlocked.selector, alice, 2, 1));
        token.transfer(bob, 2);

        token.setFrozen(bob, true);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(RealEstateTokenTransparentUpgradeable.AccountFrozen.selector, bob));
        token.transfer(bob, 1);

        token.setFrozen(bob, false);
        token.pause();
        vm.prank(alice);
        vm.expectRevert(bytes4(keccak256("EnforcedPause()")));
        token.transfer(bob, 1);
        token.unpause();
    }

    function test_ForceTransfer() public {
        token.setWhitelistMode(true);
        token.setWhitelist(alice, true);
        token.lockBalance(alice, 299_999);

        vm.expectRevert(abi.encodeWithSelector(RealEstateTokenTransparentUpgradeable.EmptyForceTransferData.selector));
        token.forceTransfer(alice, bob, 1, "");

        vm.expectRevert(abi.encodeWithSelector(RealEstateTokenTransparentUpgradeable.LockExceedsUnlocked.selector, alice, 2, 1));
        token.forceTransfer(alice, bob, 2, bytes("order:xyz"));

        token.forceTransfer(alice, bob, 1, bytes("order:xyz"));
        assertEq(token.balanceOf(bob), 200_001);
    }

    function test_Delegation_Model() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(RealEstateTokenTransparentUpgradeable.DelegationDisabled.selector));
        token.delegate(bob);

        vm.prank(alice);
        token.delegate(alice);

        token.setWhitelistMode(true);
        token.setWhitelist(alice, true);
        token.setWhitelist(bob, true);

        vm.prank(alice);
        assertTrue(token.transfer(bob, 0));

        assertEq(token.getVotes(alice), token.balanceOf(alice));
        assertEq(token.getVotes(bob),   token.balanceOf(bob));
    }

    function test_Upgrade_ByProxyAdmin() public {
        uint256 balAlice = token.balanceOf(alice);
        bool wl = token.whitelistEnabled();

        RealEstateTokenV2_Transparent v2 = new RealEstateTokenV2_Transparent();

        bytes32 ADMIN_SLOT = bytes32(uint256(keccak256("eip1967.proxy.admin")) - 1);
        address paAddr = address(uint160(uint256(vm.load(address(proxy), ADMIN_SLOT))));
        ProxyAdmin pa = ProxyAdmin(paAddr);

        vm.prank(rando);
        vm.expectRevert();
        pa.upgradeAndCall(
            ITransparentUpgradeableProxy(address(proxy)),
            address(v2),
            bytes("")
        );

        vm.prank(admin);
        pa.upgradeAndCall(
            ITransparentUpgradeableProxy(address(proxy)),
            address(v2),
            bytes("")
        );

        assertEq(token.balanceOf(alice), balAlice);
        assertEq(token.whitelistEnabled(), wl);

        (bool ok, bytes memory data) = address(token).staticcall(
            abi.encodeWithSignature("version()")
        );
        assertTrue(ok);
        assertEq(abi.decode(data, (uint256)), 2);
    }
}
