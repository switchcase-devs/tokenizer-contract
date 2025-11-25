// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { Test } from "forge-std/Test.sol";
import { RealEstateToken } from "src/RealEstateToken.sol";
import { Actors } from "test/utils/Actors.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract RealEstateToken_Permit_Test is Test {
    RealEstateToken token;
    address admin = address(this);
    address owner = address(0xA11CE);
    address spender = address(0xB0B);

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

        assertTrue(token.transfer(owner, 100_000));
    }

    function _signPermit(
        uint256 ownerPk,
        address ownerAddr,
        address spenderAddr,
        uint256 value,
        uint256 deadline
    ) internal view returns (uint8 v, bytes32 r, bytes32 s) {
        bytes32 typehash = keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
        bytes32 DOMAIN_SEPARATOR = token.DOMAIN_SEPARATOR();
        bytes32 structHash = keccak256(abi.encode(
            typehash,
            ownerAddr,
            spenderAddr,
            value,
            token.nonces(ownerAddr),
            deadline
        ));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));
        (v, r, s) = vm.sign(ownerPk, digest);
    }

    function test_Permit_AllowsSpender_NoReplay() public {
        uint256 ownerPk = 0x1234;
        address ownerAddr = vm.addr(ownerPk);
        assertTrue(token.transfer(ownerAddr, 10_000));
        uint256 deadline = block.timestamp + 1 days;
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(ownerPk, ownerAddr, spender, 777, deadline);
        token.permit(ownerAddr, spender, 777, deadline, v, r, s);
        assertEq(token.allowance(ownerAddr, spender), 777);
        assertEq(token.nonces(ownerAddr), 1);
        vm.expectRevert();
        token.permit(ownerAddr, spender, 777, deadline, v, r, s);
    }

    function test_Permit_ExpiredDeadline() public {
        uint256 ownerPk = 0x5678;
        address ownerAddr = vm.addr(ownerPk);
        assertTrue(token.transfer(ownerAddr, 9_000));

        uint256 deadline = block.timestamp - 1; // already expired
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(ownerPk, ownerAddr, spender, 100, deadline);

        vm.expectRevert(abi.encodeWithSelector(
            bytes4(keccak256("ERC2612ExpiredSignature(uint256)")),
            deadline
        ));
        token.permit(ownerAddr, spender, 100, deadline, v, r, s);
    }
}
