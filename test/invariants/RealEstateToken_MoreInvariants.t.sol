// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { Test } from "forge-std/Test.sol";
import { RealEstateToken } from "src/RealEstateToken.sol";
import { Actors } from "test/utils/Actors.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract RealEstateToken_MoreInvariants is Test {
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
            uint256(1000),
            admin
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        token = RealEstateToken(payable(address(proxy)));

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
