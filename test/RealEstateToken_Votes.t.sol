// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { Test } from "forge-std/Test.sol";
import { RealEstateToken } from "src/RealEstateToken.sol";
import { Actors } from "test/utils/Actors.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract RealEstateToken_Votes_Test is Test {
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
            uint256(1_000_000),
            admin
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        token = RealEstateToken(payable(address(proxy)));

        assertTrue(token.transfer(alice, 100_000));
        assertTrue(token.transfer(bob,   50_000));

        token.setWhitelistMode(true);
        token.setWhitelist(alice, true);
        token.setWhitelist(bob,   true);

        vm.prank(alice);
        assertTrue(token.transfer(alice, 0));

        vm.prank(bob);
        assertTrue(token.transfer(bob, 0));
    }

    function test_SelfDelegationOnly_ThirdPartyDisabled() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(RealEstateToken.DelegationDisabled.selector));
        token.delegate(bob);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(RealEstateToken.DelegationDisabled.selector));
        token.delegate(alice);
    }

    function test_VotesTrackOnMintBurnTransfer() public {
        assertEq(token.getVotes(alice), token.balanceOf(alice));
        assertEq(token.getVotes(bob),   token.balanceOf(bob));

        token.grantRole(token.ROLE_MINTER(), admin);
        token.mint(bob, 10_000);
        assertEq(token.getVotes(bob), token.balanceOf(bob));

        token.grantRole(token.ROLE_BURNER(), admin);

        vm.prank(alice);
        assertTrue(token.approve(admin, 5_000));

        token.burnFrom(alice, 5_000);
        assertEq(token.getVotes(alice), token.balanceOf(alice));

        token.setWhitelistMode(true);
        token.setWhitelist(alice, true);
        token.setWhitelist(bob,   true);

        vm.prank(alice);
        assertTrue(token.transfer(bob, 1_234));

        assertEq(token.getVotes(alice), token.balanceOf(alice));
        assertEq(token.getVotes(bob),   token.balanceOf(bob));
    }

    function test_VotesZeroWhenFrozen_AndRestoreOnUnfreeze() public {
        uint256 aliceBalance = token.balanceOf(alice);
        assertEq(token.getVotes(alice), aliceBalance);

        token.setFrozen(alice, true);
        assertTrue(token.isFrozen(alice));
        assertEq(token.getVotes(alice), 0);

        token.setFrozen(alice, false);
        assertFalse(token.isFrozen(alice));
        assertEq(token.getVotes(alice), aliceBalance);
    }

    function test_VotesFollowLockedBalance() public {
        uint256 aliceBalance = token.balanceOf(alice);
        uint256 lockAmount   = 10_000;

        token.lockBalance(alice, lockAmount);
        assertEq(token.lockedBalanceOf(alice), lockAmount);
        assertEq(token.getVotes(alice), aliceBalance - lockAmount);

        uint256 unlockAmount = 4_000;
        token.unlockBalance(alice, unlockAmount);

        assertEq(token.lockedBalanceOf(alice), lockAmount - unlockAmount);
        assertEq(token.getVotes(alice), aliceBalance - (lockAmount - unlockAmount));
    }

    function test_VotesZeroForUnwhitelistedWhileWhitelistEnabled() public {
        uint256 bobBalance = token.balanceOf(bob);
        assertEq(token.getVotes(bob), bobBalance);

        token.setWhitelist(bob, false);
        assertFalse(token.isWhitelisted(bob));
        assertEq(token.getVotes(bob), 0);

        token.setWhitelist(bob, true);
        assertTrue(token.isWhitelisted(bob));
        assertEq(token.getVotes(bob), bobBalance);
    }

    function test_VotesReactOnWhitelistModeEnableDisable() public {
        uint256 bobBalance = token.balanceOf(bob);

        token.setWhitelistMode(false);
        token.setWhitelist(bob, false);
        assertEq(token.getVotes(bob), bobBalance);

        token.setWhitelistMode(true);
        token.setWhitelist(bob, false);
        assertEq(token.getVotes(bob), 0);

        token.setWhitelistMode(false);
        token.setWhitelist(bob, false);
        assertEq(token.getVotes(bob), bobBalance);
    }

    function test_WhitelistModeToggle_UpdatesVotes() public {
        uint256 aliceBalance = token.balanceOf(alice);
        uint256 bobBalance   = token.balanceOf(bob);

        assertEq(token.getVotes(alice), aliceBalance);
        assertEq(token.getVotes(bob),   bobBalance);

        token.setWhitelistMode(false);
        token.setWhitelist(alice, true);
        token.setWhitelist(bob,   false);

        assertEq(token.getVotes(alice), aliceBalance);
        assertEq(token.getVotes(bob),   bobBalance);

        token.setWhitelistMode(true);

        assertEq(token.getVotes(alice), aliceBalance);
        assertEq(token.getVotes(bob),   0);

        token.setWhitelist(bob, true);
        assertEq(token.getVotes(bob), bobBalance);

        token.setWhitelistMode(false);

        assertEq(token.getVotes(alice), aliceBalance);
        assertEq(token.getVotes(bob),   bobBalance);
    }

    function test_SyncHolder_RemovesMiddleHolder() public {
        address h1 = vm.addr(11);
        address h2 = vm.addr(12);
        address h3 = vm.addr(13);

        token.transfer(h1, 1_000);
        token.transfer(h2, 1_000);
        token.transfer(h3, 1_000);

        token.setWhitelist(h1, true);
        token.setWhitelist(h2, true);
        token.setWhitelist(h3, true);
        token.grantRole(token.ROLE_TRANSFER(), h1);
        token.grantRole(token.ROLE_TRANSFER(), h2);
        token.grantRole(token.ROLE_TRANSFER(), h3);

        vm.prank(h2);
        token.transfer(h1, 1_000);

        assertEq(token.balanceOf(h2), 0);
    }
}
