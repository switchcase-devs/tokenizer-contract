// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {RealEstateToken} from "src/RealEstateToken.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract RealEstateToken_Views_And_DelegationDisabled_Test is Test {
    RealEstateToken token;
    address admin = address(this);
    address alice = address(0xA11CE);
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

        token.transfer(alice, 1);
        token.setWhitelistMode(true);
        token.setWhitelist(alice, true);
        token.setFrozen(alice, true);
        token.lockBalance(alice, 1);
    }

    function test_Getters_And_Delegation_Disabled() public {
        assertEq(token.decimals(), 0);
        assertEq(IERC20Metadata(address(token)).decimals(), 0);
        (bool ok, bytes memory data) = address(token).staticcall(abi.encodeWithSignature("decimals()"));
        assertTrue(ok);
        assertEq(abi.decode(data, (uint8)), 0);
        assertEq(token.isWhitelisted(alice), true);
        assertEq(token.isFrozen(alice), true);
        assertEq(token.lockedBalanceOf(alice), 1);
        assertEq(token.delegates(alice), alice);
        vm.expectRevert(abi.encodeWithSelector(RealEstateToken.DelegationDisabled.selector));
        token.delegate(alice);
        vm.expectRevert(abi.encodeWithSelector(RealEstateToken.DelegationDisabled.selector));
        token.delegateBySig(alice, 0, 0, 27, bytes32(0), bytes32(0));
    }
}
