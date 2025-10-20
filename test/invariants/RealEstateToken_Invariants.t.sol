// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/StdInvariant.sol";
import "../src/RealEstateToken.sol";
import "./utils/Actors.sol";

contract RealEstateToken_Invariants is Test, StdInvariant {
    RealEstateToken token;
    address admin = address(this);
    address alice = Actors.ALICE;
    address bob   = Actors.BOB;
    address carol = Actors.CAROL;

    function setUp() public {
        token = new RealEstateToken("Estate", "EST", 1000, admin);

        // Seed balances and initialize votes via 0-amount self-transfers
        token.transfer(alice, 300);
        token.transfer(bob,   200);
        token.transfer(carol, 100);

        token.setWhitelistMode(true);
        token.setWhitelist(alice, true);
        token.setWhitelist(bob, true);
        token.setWhitelist(carol, true);

        vm.prank(alice); token.transfer(alice, 0);
        vm.prank(bob);   token.transfer(bob, 0);
        vm.prank(carol); token.transfer(carol, 0);

        // We don't set a target contract/handler here; invariants check global properties
        // after each test case run.
    }

    function invariant_LockedNeverExceedsBalance() public view {
        assertLe(_lockedOf(alice), token.balanceOf(alice), "ALICE locked ≤ balance");
        assertLe(_lockedOf(bob),   token.balanceOf(bob),   "BOB locked ≤ balance");
        assertLe(_lockedOf(carol), token.balanceOf(carol), "CAROL locked ≤ balance");
    }

    function invariant_VotesMirrorBalances() public view {
        assertEq(token.getVotes(alice), token.balanceOf(alice), "votes==balance ALICE");
        assertEq(token.getVotes(bob),   token.balanceOf(bob),   "votes==balance BOB");
        assertEq(token.getVotes(carol), token.balanceOf(carol), "votes==balance CAROL");
    }

    function _lockedOf(address who) internal view returns (uint256) {
        (bool ok, bytes memory data) = address(token).staticcall(abi.encodeWithSignature("lockedBalanceOf(address)", who));
        require(ok, "lockedBalanceOf failed");
        return abi.decode(data, (uint256));
    }
}
