// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/RealEstateToken.sol";
import "./utils/Actors.sol";

contract RealEstateToken_Fuzz_Test is Test {
    RealEstateToken token;
    address admin = address(this);
    address alice = Actors.ALICE;
    address bob   = Actors.BOB;

    function setUp() public {
        token = new RealEstateToken("Estate", "EST", 1_000_000, admin);
        // Give ALICE and BOB balances
        token.transfer(alice, 50_000);
        token.transfer(bob,   50_000);

        // Enable whitelist mode and whitelist both so they can transfer without ROLE_TRANSFER
        token.setWhitelistMode(true);
        token.setWhitelist(alice, true);
        token.setWhitelist(bob,   true);
    }

    function testFuzz_TransferRespectsUnlocked(uint128 lockAmt, uint128 xferAmt) public {
        // bound values
        lockAmt = uint128(bound(lockAmt, 0, 50_000));
        xferAmt = uint128(bound(xferAmt, 0, 50_000));

        // lock some of ALICE
        if (lockAmt > 0) {
            token.lockBalance(alice, lockAmt);
        }

        uint256 bal = token.balanceOf(alice);
        uint256 unlocked = bal - (lockAmt);

        vm.startPrank(alice);
        if (xferAmt > unlocked) {
            vm.expectRevert(); // LockExceedsUnlocked or balance error
            token.transfer(bob, xferAmt);
        } else {
            token.transfer(bob, xferAmt);
            assertEq(token.balanceOf(bob), 50_000 + xferAmt);
        }
        vm.stopPrank();

        // sanity: locked never exceeds new balance
        (, bytes memory data) = address(token).staticcall(abi.encodeWithSignature("lockedBalanceOf(address)", alice));
        uint256 locked = abi.decode(data, (uint256));
        assertLe(locked, token.balanceOf(alice), "locked ≤ balance");
    }
}
