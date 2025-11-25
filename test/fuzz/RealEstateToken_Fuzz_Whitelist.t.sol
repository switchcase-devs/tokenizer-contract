// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { Test } from "forge-std/Test.sol";
import { RealEstateToken } from "src/RealEstateToken.sol";
import { Actors } from "test/utils/Actors.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract RealEstateToken_Fuzz_Whitelist_Test is Test {
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
        assertTrue(token.transfer(bob,   100_000));
        token.setWhitelistMode(true);
    }

    function testFuzz_WhitelistMatrix(bool wlFrom, bool wlTo, bool operator, uint96 amount) public {
        amount = uint96(bound(amount, 0, 100_000));

        token.setWhitelist(alice, wlFrom);
        token.setWhitelist(bob,   wlTo);

        if (operator) {
            token.grantRole(token.ROLE_TRANSFER(), alice);
        } else if (token.hasRole(token.ROLE_TRANSFER(), alice)) {
            token.revokeRole(token.ROLE_TRANSFER(), alice);
        }

        vm.startPrank(alice);
        if (!operator && (!wlFrom || !wlTo)) {
            vm.expectRevert(); // NotWhitelisted(from|to) even for amount == 0
            token.transfer(bob, amount);
        } else {
            bool ok = token.transfer(bob, amount);
            assertTrue(ok);
        }
        vm.stopPrank();
    }
}
