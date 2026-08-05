// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {TestSetup} from "../helpers/TestSetup.sol";

contract EntryGuardTest is TestSetup {
    function testEntriesAreAllowedByDefault() public view {
        assertTrue(guard.isEntryAllowed(MARKET_ID));
    }

    function testMarketPauseDoesNotPauseOtherMarkets() public {
        bytes32 otherMarket = keccak256("other-market");
        vm.prank(guardOwner);
        guard.pauseMarket(MARKET_ID);

        assertFalse(guard.isEntryAllowed(MARKET_ID));
        assertTrue(guard.isEntryAllowed(otherMarket));
    }

    function testGlobalPauseBlocksEveryMarket() public {
        vm.prank(guardOwner);
        guard.pauseGlobal();

        assertFalse(guard.isEntryAllowed(MARKET_ID));
        assertFalse(guard.isEntryAllowed(keccak256("other-market")));
    }

    function testGlobalAndMarketPausesCanBeLiftedIndependently() public {
        vm.startPrank(guardOwner);
        guard.pauseGlobal();
        guard.pauseMarket(MARKET_ID);
        guard.unpauseGlobal();
        vm.stopPrank();

        assertFalse(guard.isEntryAllowed(MARKET_ID));

        vm.prank(guardOwner);
        guard.unpauseMarket(MARKET_ID);
        assertTrue(guard.isEntryAllowed(MARKET_ID));
    }

    function testOnlyOwnerCanPause() public {
        address stranger = makeAddr("stranger");
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        guard.pauseGlobal();
    }
}
