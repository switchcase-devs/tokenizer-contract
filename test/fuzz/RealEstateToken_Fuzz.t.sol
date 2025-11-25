// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { Test } from "forge-std/Test.sol";
import { RealEstateToken } from "src/RealEstateToken.sol";
import { Actors } from "test/utils/Actors.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract RealEstateToken_Fuzz_Test is Test {
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

        assertTrue(token.transfer(alice, 50_000));
        assertTrue(token.transfer(bob,   50_000));
        token.setWhitelistMode(true);
        token.setWhitelist(alice, true);
        token.setWhitelist(bob,   true);
    }

    function testFuzz_TransferRespectsUnlocked(uint128 lockAmt, uint128 xferAmt) public {
        lockAmt = uint128(bound(lockAmt, 0, 50_000));
        xferAmt = uint128(bound(xferAmt, 0, 50_000));

        if (lockAmt > 0) token.lockBalance(alice, lockAmt);

        uint256 bal = token.balanceOf(alice);
        uint256 unlocked = bal - lockAmt;

        vm.startPrank(alice);
        if (xferAmt > unlocked) {
            (bool ok, ) = address(token).call(
                abi.encodeWithSignature("transfer(address,uint256)", bob, xferAmt)
            );
            assertTrue(!ok); // must fail when exceeding unlocked
        } else {
            assertTrue(token.transfer(bob, xferAmt));
            assertEq(token.balanceOf(bob), 50_000 + xferAmt);
        }
        vm.stopPrank();

        (bool ok2, bytes memory data) =
                                address(token).staticcall(abi.encodeWithSignature("lockedBalanceOf(address)", alice));
        assertTrue(ok2);
        uint256 locked = abi.decode(data, (uint256));
        assertLe(locked, token.balanceOf(alice));
    }
}
