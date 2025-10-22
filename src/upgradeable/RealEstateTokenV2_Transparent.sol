// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { RealEstateTokenTransparentUpgradeable } from "./RealEstateTokenTransparentUpgradeable.sol";

contract RealEstateTokenV2_Transparent is RealEstateTokenTransparentUpgradeable {
    function version() external pure returns (uint256) { return 2; }
}
