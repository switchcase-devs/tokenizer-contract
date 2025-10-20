// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library Actors {
    address constant ADMIN = address(uint160(uint256(keccak256("ADMIN"))));
    address constant ALICE = address(uint160(uint256(keccak256("ALICE"))));
    address constant BOB   = address(uint160(uint256(keccak256("BOB"))));
    address constant CAROL = address(uint160(uint256(keccak256("CAROL"))));
    address constant DAVE  = address(uint160(uint256(keccak256("DAVE"))));
}
