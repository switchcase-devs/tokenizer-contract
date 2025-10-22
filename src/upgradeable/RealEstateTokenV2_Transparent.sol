// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {RealEstateToken} from "../RealEstateToken.sol";

contract RealEstateTokenV2_Transparent is RealEstateToken {
    function version() external pure returns (uint256) { return 2; }
}
