// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {RealEstateToken} from "src/RealEstateToken.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract RealEstateToken_SupportsInterface_Test is Test {
    RealEstateToken token;
    address admin = address(this);
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
    }
    function test_SupportsInterface() public view {
        assertTrue(token.supportsInterface(0x01ffc9a7));
        assertTrue(token.supportsInterface(0x7965db0b));
    }
}