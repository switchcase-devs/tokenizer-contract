// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { Test } from "forge-std/Test.sol";
import { RealEstateToken } from "src/RealEstateToken.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract RealEstateToken_Holders_Votes_Fuzz_Test is Test {
    RealEstateToken token;

    address admin = address(this);
    address[] participants;

    uint256 constant NUM_HOLDERS = 60;
    uint256 constant STEPS       = 200;

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

        participants.push(admin);

        for (uint256 i = 0; i < NUM_HOLDERS; ++i) {
            address h = vm.addr(i + 1);
            participants.push(h);
        }

        uint256 perHolder = 5_000;
        for (uint256 i = 1; i < participants.length; ++i) {
            token.transfer(participants[i], perHolder);
        }

        for (uint256 i = 0; i < participants.length; ++i) {
            token.grantRole(token.ROLE_TRANSFER(), participants[i]);
        }

        token.setWhitelistMode(true);
        for (uint256 i = 0; i < participants.length; ++i) {
            token.setWhitelist(participants[i], true);
        }

        _checkInvariants();
    }

    function test_Fuzz_HoldersBalancesAndVotes() public {
        uint256 seed = 0x123456789abcdef;

        for (uint256 step = 0; step < STEPS; ++step) {
            uint256 r = uint256(keccak256(abi.encode(seed, step)));

            uint256 op = r % 10;
            uint256 a  = (r >> 16) % participants.length;
            uint256 b  = (r >> 32) % participants.length;
            address addrA = participants[a];
            address addrB = participants[b];

            if (op == 0) {
                bool mode = ((r >> 48) & 1) == 1;
                try token.setWhitelistMode(mode) {} catch {}
            } else if (op == 1) {
                bool st = ((r >> 56) & 1) == 1;
                try token.setWhitelist(addrA, st) {} catch {}
            } else if (op == 2) {
                uint256 bal = token.balanceOf(addrA);
                if (bal > 0) {
                    uint256 amt = 1 + ((r >> 64) % bal);
                    try token.burnFrom(addrA, amt) {} catch {}
                }
            } else if (op == 3) {
                if (addrA != addrB) {
                    uint256 bal = token.balanceOf(addrA);
                    if (bal > 0) {
                        uint256 amt = 1 + ((r >> 80) % bal);
                        bytes memory data = abi.encodePacked(uint64(r));
                        try token.forceTransfer(addrA, addrB, amt, data) {} catch {}
                    }
                }
            } else if (op == 4) {
                if (token.whitelistEnabled()) {
                    uint256 bal = token.balanceOf(addrA);
                    if (bal > 0 && addrA != addrB) {
                        uint256 amt = 1 + ((r >> 96) % bal);
                        vm.startPrank(addrA);
                        try token.transfer(addrB, amt) returns (bool) {} catch {}
                        vm.stopPrank();
                    }
                }
            } else if (op == 5) {
                uint256 amt = 1 + ((r >> 112) % 10_000);
                try token.mint(addrA, amt) {} catch {}
            } else if (op == 6) {
                bool fr = ((r >> 128) & 1) == 1;
                try token.setFrozen(addrA, fr) {} catch {}
            } else if (op == 7) {
                uint256 bal = token.balanceOf(addrA);
                uint256 locked = token.lockedBalanceOf(addrA);
                if (bal > locked) {
                    uint256 unlocked = bal - locked;
                    uint256 amt = 1 + ((r >> 144) % unlocked);
                    try token.lockBalance(addrA, amt) {} catch {}
                }
            } else if (op == 8) {
                uint256 locked = token.lockedBalanceOf(addrA);
                if (locked > 0) {
                    uint256 amt = 1 + ((r >> 160) % locked);
                    try token.unlockBalance(addrA, amt) {} catch {}
                }
            } else if (op == 9) {
                if (!token.whitelistEnabled()) {
                    uint256 bal = token.balanceOf(addrA);
                    if (bal > 0 && addrA != addrB) {
                        uint256 amt = 1 + ((r >> 176) % bal);
                        vm.startPrank(addrA);
                        try token.transfer(addrB, amt) returns (bool) {} catch {}
                        vm.stopPrank();
                    }
                }
            }

            _checkInvariants();
        }
    }

    function _checkInvariants() internal view {
        bool wlMode = token.whitelistEnabled();

        for (uint256 i = 0; i < participants.length; ++i) {
            address a = participants[i];

            uint256 bal    = token.balanceOf(a);
            uint256 locked = token.lockedBalanceOf(a);
            bool frozen    = token.isFrozen(a);
            bool wh        = token.isWhitelisted(a);
            uint256 votes  = token.getVotes(a);

            assertLe(locked, bal, "locked > balance");

            uint256 expectedVotes;
            if (frozen || (wlMode && !wh)) {
                expectedVotes = 0;
            } else {
                uint256 unlocked = bal > locked ? bal - locked : 0;
                expectedVotes = unlocked;
            }

            assertEq(votes, expectedVotes, "votes mismatch");
        }
    }
}
