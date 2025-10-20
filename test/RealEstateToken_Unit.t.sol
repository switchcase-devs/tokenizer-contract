// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/access/IAccessControl.sol";
import "@openzeppelin/contracts/interfaces/IERC20Errors.sol";
import "../src/RealEstateToken.sol";
import "./utils/Actors.sol";

contract RealEstateToken_Unit_Test is Test {
    using stdStorage for StdStorage;

    RealEstateToken token;
    address admin = address(this);
    address alice = Actors.ALICE;
    address bob   = Actors.BOB;
    address carol = Actors.CAROL;

    function setUp() public {
        token = new RealEstateToken("Estate", "EST", 1000, admin);

        // Distribute some tokens for tests via operator (admin has ROLE_TRANSFER by default)
        token.transfer(alice, 300);
        token.transfer(bob,   200);
        token.transfer(carol, 100);
    }

    function test_DecimalsIsZero() public view {
        assertEq(token.decimals(), 0, "decimals");
    }

    function test_RoleGatedMode_NonOperatorCannotTransfer() public {
        // default is whitelistEnabled == false (role-gated mode)
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(RealEstateToken.MissingTransferRole.selector, alice));
        token.transfer(bob, 1);
        vm.stopPrank();
    }

    function test_WhitelistMode_BlocksUntilBothWhitelisted() public {
        token.setWhitelistMode(true);
        // Not whitelisted yet
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(RealEstateToken.NotWhitelisted.selector, alice));
        token.transfer(bob, 1);
        vm.stopPrank();

        // Whitelist both
        token.setWhitelist(alice, true);
        token.setWhitelist(bob, true);

        vm.prank(alice);
        token.transfer(bob, 1); // should succeed
        assertEq(token.balanceOf(bob), 201);
    }

    function test_PauseBlocksTransfers() public {
        // Enter whitelist mode so non-operator can transfer
        token.setWhitelistMode(true);
        token.setWhitelist(alice, true);
        token.setWhitelist(bob, true);

        // Sanity transfer works before pause
        vm.prank(alice);
        token.transfer(bob, 1);
        assertEq(token.balanceOf(bob), 201);

        token.pause();
        vm.prank(alice);
        vm.expectRevert(bytes4(keccak256("EnforcedPause()"))); // OZ Pausable custom error
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
        // lock 100 for alice (alice has 299 now after earlier tests? ensure fresh by re-deploy)
        // redeploy to reset balances
        setUp();
        token.setWhitelistMode(true);
        token.setWhitelist(alice, true);
        token.setWhitelist(bob, true);

        // Lock 200 of alice's 300
        token.lockBalance(alice, 200);
        // cannot lock more than unlocked
        vm.expectRevert(); // generic check (LockExceedsUnlocked)
        token.lockBalance(alice, 101);

        // attempting to transfer > unlocked (300 - 200 = 100) reverts
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(RealEstateToken.LockExceedsUnlocked.selector, alice, 101, 100));
        token.transfer(bob, 101);

        // transferring exactly unlocked succeeds
        token.transfer(bob, 100);
        vm.stopPrank();

        // cannot unlock more than locked
        vm.expectRevert(abi.encodeWithSelector(RealEstateToken.UnlockExceedsLocked.selector, alice, 201, 200));
        token.unlockBalance(alice, 201);

        // unlock 50 and then 150 (total 200)
        token.unlockBalance(alice, 50);
        token.unlockBalance(alice, 150);
    }

    function test_ForceTransfer_RequiresData_RespectsLocks_EmitsEvent() public {
        // put alice in whitelist mode, but operator can bypass whitelist (still respects locks)
        token.setWhitelistMode(true);
        token.setWhitelist(alice, true);
        token.setWhitelist(bob,   false);

        // Lock most of alice
        token.lockBalance(alice, 250); // she had 300 at start of this test file
        bytes memory evidence = bytes("court:123");

        // No data → revert
        vm.expectRevert(abi.encodeWithSelector(RealEstateToken.EmptyForceTransferData.selector));
        token.forceTransfer(alice, bob, 1, "");

        // Amount > unlocked (300-250=50) → revert
        vm.expectRevert(abi.encodeWithSelector(RealEstateToken.LockExceedsUnlocked.selector, alice, 51, 50));
        token.forceTransfer(alice, bob, 51, evidence);

        // Good path → event emitted
        vm.expectEmit(true, true, true, true, address(token));
        emit RealEstateToken.ForcedTransfer(address(this), alice, bob, 50, evidence);
        token.forceTransfer(alice, bob, 50, evidence);
        assertEq(token.balanceOf(bob), 250);
    }

    function test_DelegationRestrictions_AndVotesTrackBalances() public {
        // third-party delegation disabled
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(RealEstateToken.DelegationDisabled.selector));
        token.delegate(bob);

        // self-delegate allowed (even with zero balance)
        vm.prank(alice);
        token.delegate(alice);

        // Votes are initialized lazily; trigger self-delegation for bob by moving tokens
        token.setWhitelistMode(true);
        token.setWhitelist(alice, true);
        token.setWhitelist(bob, true);

        // 0-amount self-transfer triggers auto self-delegation in _update
        vm.prank(bob);
        token.transfer(bob, 0);

        assertEq(token.getVotes(alice), token.balanceOf(alice), "votes==balance ALICE");
        assertEq(token.getVotes(bob),   token.balanceOf(bob),   "votes==balance BOB");
    }

    function test_BurnFrom_RoleAndAllowance() public {
        // Grant BOB burner role
        bytes32 ROLE_BURNER = token.ROLE_BURNER();
        token.grantRole(ROLE_BURNER, bob);

        // Without allowance → revert ERC20InsufficientAllowance
        vm.prank(bob);
        vm.expectRevert(IERC20Errors.ERC20InsufficientAllowance.selector);
        token.burnFrom(alice, 1);

        // Provide allowance; then burn succeeds
        vm.prank(alice);
        token.approve(bob, 5);
        vm.prank(bob);
        token.burnFrom(alice, 5);
        assertEq(token.balanceOf(alice), 295);
    }

    function test_SupportsInterface_AccessControl() public view {
        // AccessControl interface id should be supported
        bool ok = token.supportsInterface(type(IAccessControl).interfaceId);
        assertTrue(ok, "supports IAccessControl");
    }
}
