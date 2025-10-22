// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Test } from "forge-std/Test.sol";
import { RealEstateToken } from "src/RealEstateToken.sol";
import { Actors } from "test/utils/Actors.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract RealEstateToken_Invariants is Test {
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
            uint256(1000),
            admin
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        token = RealEstateToken(payable(address(proxy)));

        assertTrue(token.transfer(alice, 300));
        assertTrue(token.transfer(bob,   200));
        assertTrue(token.transfer(carol, 100));

        token.setWhitelistMode(true);
        token.setWhitelist(alice, true);
        token.setWhitelist(bob, true);
        token.setWhitelist(carol, true);

        vm.prank(alice); assertTrue(token.transfer(alice, 0));
        vm.prank(bob);   assertTrue(token.transfer(bob, 0));
        vm.prank(carol); assertTrue(token.transfer(carol, 0));
    }

    function invariant_LockedNeverExceedsBalance() public view {
        assertLe(_lockedOf(alice), token.balanceOf(alice), "ALICE locked <= balance");
        assertLe(_lockedOf(bob),   token.balanceOf(bob),   "BOB locked <= balance");
        assertLe(_lockedOf(carol), token.balanceOf(carol), "CAROL locked <= balance");
    }

    function invariant_VotesMirrorBalances() public view {
        assertEq(token.getVotes(alice), token.balanceOf(alice), "votes==balance ALICE");
        assertEq(token.getVotes(bob),   token.balanceOf(bob),   "votes==balance BOB");
        assertEq(token.getVotes(carol), token.balanceOf(carol), "votes==balance CAROL");
    }

    function _lockedOf(address who) internal view returns (uint256) {
        (bool ok, bytes memory data) =
                                address(token).staticcall(abi.encodeWithSignature("lockedBalanceOf(address)", who));
        require(ok);
        return abi.decode(data, (uint256));
    }
}
