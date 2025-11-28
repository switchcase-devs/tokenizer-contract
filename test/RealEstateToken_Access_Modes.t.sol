// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { Test } from "forge-std/Test.sol";
import { RealEstateToken } from "src/RealEstateToken.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { Actors } from "test/utils/Actors.sol";
import "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract RealEstateToken_Access_Modes_Test is Test {
    RealEstateToken token;
    address admin = address(this);
    address alice = Actors.ALICE;
    address bob   = Actors.BOB;
    address carol = Actors.CAROL;

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

        assertTrue(token.transfer(alice, 100_000));
        assertTrue(token.transfer(bob,   100_000));
        assertTrue(token.transfer(carol, 100_000));
    }

    function test_AdminHasDefaultRoleAndCanGrantRevoke() public {
        bytes32 adminRole = token.ROLE_ADMIN();
        assertTrue(token.hasRole(adminRole, admin));

        bytes32 minter = token.ROLE_MINTER();
        assertFalse(token.hasRole(minter, alice));
        token.grantRole(minter, alice);
        assertTrue(token.hasRole(minter, alice));
        token.revokeRole(minter, alice);
        assertFalse(token.hasRole(minter, alice));
    }

    function test_OnlyAdminCanSetWhitelistAndMode() public {
        vm.prank(alice);
        vm.expectRevert();
        token.setWhitelistMode(true);

        token.setWhitelistMode(true);

        vm.prank(alice);
        vm.expectRevert();
        token.setWhitelist(bob, true);

        token.setWhitelist(bob, true);
        assertTrue(token.isWhitelisted(bob));
    }

    function test_RoleGatedMode_OnlyTransferRoleCanMove() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(RealEstateToken.MissingTransferRole.selector, alice));
        token.transfer(bob, 1);
        token.grantRole(token.ROLE_TRANSFER(), alice);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 1));
    }

    function test_WhitelistMode_NonOperatorRequiresBothWhitelisted() public {
        token.setWhitelistMode(true);
        token.setWhitelist(alice, true);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(RealEstateToken.NotWhitelisted.selector, bob));
        token.transfer(bob, 1);
        token.setWhitelist(bob, true);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 1));
    }

    function test_WhitelistMode_OperatorBypassesWhitelist() public {
        token.setWhitelistMode(true);
        token.grantRole(token.ROLE_TRANSFER(), alice);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 10));
    }

    function test_FreezeBlocksBothDirections() public {
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

    function test_ZeroAddressGuards_ForceTransfer() public {
        token.grantRole(token.ROLE_TRANSFER(), admin);

        vm.expectRevert(abi.encodeWithSignature("ERC20InvalidSender(address)", address(0)));
        token.forceTransfer(address(0), bob, 1, bytes("x"));

        vm.expectRevert(abi.encodeWithSignature("ERC20InvalidReceiver(address)", address(0)));
        token.forceTransfer(alice, address(0), 1, bytes("x"));

        vm.expectRevert(abi.encodeWithSelector(RealEstateToken.EmptyForceTransferData.selector));
        token.forceTransfer(alice, bob, 1, "");
    }

    function test_DecimalsAreZero_NoFractionalAssumptions() public view {
        assertEq(token.decimals(), 0);
    }

    function test_Supports_IAccessControl_Interface() public view {
        assertTrue(token.supportsInterface(type(IAccessControl).interfaceId));
    }
}
