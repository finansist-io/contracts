// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {Test} from "forge-std/Test.sol";

import {ChainlinkSequencerGuard} from "../../src/libraries/ChainlinkSequencerGuard.sol";
import {MockChainlinkAggregatorV3} from "../helpers/MockChainlinkAggregatorV3.sol";

contract ChainlinkSequencerGuardHarness {
    function requireUp(address feed, uint256 gracePeriod) external view {
        ChainlinkSequencerGuard.requireUp(feed, gracePeriod);
    }
}

contract ChainlinkSequencerGuardTest is Test {
    uint256 private constant NOW = 1_800_000_000;

    ChainlinkSequencerGuardHarness private guard;
    MockChainlinkAggregatorV3 private feed;

    function setUp() public {
        vm.warp(NOW);
        guard = new ChainlinkSequencerGuardHarness();
        feed = new MockChainlinkAggregatorV3("L2 Sequencer Uptime Status Feed", 0, 1);
        feed.setRound(10, 0, NOW - 3_601, NOW - 1, 10);
    }

    function testAcceptsUpStatusAfterGrace() public view {
        guard.requireUp(address(feed), 3_600);
    }

    function testDoesNotApplyPriceStyleMaximumAge() public {
        feed.setRound(10, 0, NOW - 30 days, NOW - 29 days, 10);
        guard.requireUp(address(feed), 3_600);
    }

    function testRejectsAtGraceBoundary() public {
        feed.setRound(10, 0, NOW - 3_600, NOW - 1, 10);
        vm.expectRevert(
            abi.encodeWithSelector(
                ChainlinkSequencerGuard.SequencerGracePeriod.selector, address(feed), NOW - 3_600, 3_600
            )
        );
        guard.requireUp(address(feed), 3_600);
    }

    function testRejectsDownStatus() public {
        feed.setRound(10, 1, NOW - 3_601, NOW - 1, 10);
        vm.expectRevert(abi.encodeWithSelector(ChainlinkSequencerGuard.SequencerDown.selector, address(feed)));
        guard.requireUp(address(feed), 3_600);
    }

    function testRejectsWrongDecimals() public {
        feed.setDecimals(8);
        vm.expectRevert(
            abi.encodeWithSelector(ChainlinkSequencerGuard.SequencerFeedDecimalsMismatch.selector, address(feed), 8)
        );
        guard.requireUp(address(feed), 3_600);
    }

    function testRejectsInvalidRounds() public {
        _expectInvalidRound(0, NOW - 3_601, NOW - 1, 0);
        _expectInvalidRound(10, 0, NOW - 1, 10);
        _expectInvalidRound(10, NOW - 3_601, 0, 10);
        _expectInvalidRound(10, NOW - 1, NOW - 2, 10);
        _expectInvalidRound(10, NOW - 3_601, NOW - 1, 9);
    }

    function testRejectsFutureRound() public {
        feed.setRound(10, 0, NOW, NOW + 1, 10);
        vm.expectRevert(
            abi.encodeWithSelector(ChainlinkSequencerGuard.FutureSequencerRound.selector, address(feed), NOW + 1)
        );
        guard.requireUp(address(feed), 3_600);
    }

    function _expectInvalidRound(uint80 roundId, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) private {
        feed.setRound(roundId, 0, startedAt, updatedAt, answeredInRound);
        vm.expectRevert(abi.encodeWithSelector(ChainlinkSequencerGuard.InvalidSequencerRound.selector, address(feed)));
        guard.requireUp(address(feed), 3_600);
    }
}
