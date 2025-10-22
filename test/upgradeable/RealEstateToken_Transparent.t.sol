// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Test } from "forge-std/Test.sol";
import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import { TransparentUpgradeableProxy, ITransparentUpgradeableProxy } from
"@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {RealEstateToken} from "../../src/RealEstateToken.sol";
import { RealEstateTokenV2_Transparent } from "src/upgradeable/RealEstateTokenV2_Transparent.sol";
import "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract RealEstateToken_Transparent_Test is Test {
    TransparentUpgradeableProxy proxy;
    RealEstateToken impl;
    RealEstateToken token;

    address admin = address(this);
    address alice = address(0xA11CE);
    address bob   = address(0xB0B);
    address rando = address(0xDEAD);

    function setUp() public {
        impl = new RealEstateToken();
        bytes memory initData = abi.encodeWithSelector(
            RealEstateToken.initialize.selector,
            "Estate",
            "EST",
            uint256(1_000_000),
            admin
        );
        proxy = new TransparentUpgradeableProxy(address(impl), admin, initData);
        token = RealEstateToken(address(proxy));
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
        vm.expectRevert(abi.encodeWithSelector(RealEstateToken.MissingTransferRole.selector, alice));
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
        vm.expectRevert(abi.encodeWithSelector(RealEstateToken.LockExceedsUnlocked.selector, alice, 2, 1));
        token.transfer(bob, 2);
        token.setFrozen(bob, true);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(RealEstateToken.AccountFrozen.selector, bob));
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

        vm.expectRevert(abi.encodeWithSelector(RealEstateToken.EmptyForceTransferData.selector));
        token.forceTransfer(alice, bob, 1, "");

        token.forceTransfer(alice, bob, 2, bytes("order:xyz"));
        token.forceTransfer(alice, bob, 1, bytes("order:xyz"));

        assertEq(token.balanceOf(bob), 200_003);
    }

    function test_Delegation_Model() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(RealEstateToken.DelegationDisabled.selector));
        token.delegate(bob);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(RealEstateToken.DelegationDisabled.selector));
        token.delegate(alice);

        token.setWhitelistMode(true);
        token.setWhitelist(alice, true);
        token.setWhitelist(bob, true);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 0));
        assertEq(token.getVotes(alice), token.balanceOf(alice));
        assertEq(token.getVotes(bob),   token.balanceOf(bob));
    }

    function test_Permit_Proxy_NoReplay() public {
        uint256 ownerPk = 0x1234;
        address ownerAddr = vm.addr(ownerPk);
        assertTrue(token.transfer(ownerAddr, 10_000));
        uint256 deadline = block.timestamp + 1 days;
        bytes32 typehash = keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
        bytes32 ds = token.DOMAIN_SEPARATOR();
        bytes32 structHash = keccak256(abi.encode(typehash, ownerAddr, bob, uint256(777), token.nonces(ownerAddr), deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", ds, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPk, digest);
        token.permit(ownerAddr, bob, 777, deadline, v, r, s);
        assertEq(token.allowance(ownerAddr, bob), 777);
        assertEq(token.nonces(ownerAddr), 1);
        vm.expectRevert();
        token.permit(ownerAddr, bob, 777, deadline, v, r, s);
    }

    function test_PauseBlocks_Mint_Burn() public {
        token.grantRole(token.ROLE_MINTER(), address(this));
        token.grantRole(token.ROLE_BURNER(), address(this));

        token.pause();

        vm.expectRevert(bytes4(keccak256("EnforcedPause()")));
        token.mint(alice, 1);

        vm.prank(alice);
        token.approve(address(this), 5);

        vm.expectRevert(bytes4(keccak256("EnforcedPause()")));
        token.burnFrom(alice, 1);
    }

    function test_WhitelistMode_OperatorBypass() public {
        token.setWhitelistMode(true);
        token.grantRole(token.ROLE_TRANSFER(), alice);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 1));
    }

    event ForcedTransfer(address indexed operator, address indexed from, address indexed to, uint256 amount, bytes data);

    function test_ForceTransfer_Emits() public {
        token.setWhitelistMode(true);
        token.setWhitelist(alice, true);
        token.lockBalance(alice, 299_999);
        bytes memory evidence = bytes("x");
        vm.expectEmit(true, true, true, true, address(token));
        emit ForcedTransfer(address(this), alice, bob, 1, evidence);
        token.forceTransfer(alice, bob, 1, evidence);
    }

    function test_Initialize_CannotBeCalledTwice() public {
        vm.expectRevert();
        RealEstateToken(address(proxy)).initialize("X","Y",1,admin);
    }

    function test_EIP1967_Slots_And_State_Preserved_OnUpgrade_v5() public {
        bytes32 ADMIN_SLOT = bytes32(uint256(keccak256("eip1967.proxy.admin")) - 1);
        bytes32 IMPL_SLOT  = bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);

        address paAddr     = address(uint160(uint256(vm.load(address(proxy), ADMIN_SLOT))));
        address implBefore = address(uint160(uint256(vm.load(address(proxy), IMPL_SLOT))));

        uint256 balAlice = token.balanceOf(alice);
        bool wl = token.whitelistEnabled();

        RealEstateTokenV2_Transparent v2 = new RealEstateTokenV2_Transparent();

        ProxyAdmin pa = ProxyAdmin(paAddr);

        vm.prank(address(this));
        pa.upgradeAndCall(
            ITransparentUpgradeableProxy(address(proxy)),
            address(v2),
            bytes("")
        );

        address implAfter = address(uint160(uint256(vm.load(address(proxy), IMPL_SLOT))));
        assertTrue(implAfter != implBefore);

        assertEq(token.balanceOf(alice), balAlice);
        assertEq(token.whitelistEnabled(), wl);

        (bool ok, bytes memory data) = address(token).staticcall(abi.encodeWithSignature("version()"));
        assertTrue(ok);
        assertEq(abi.decode(data, (uint256)), 2);
    }
}
