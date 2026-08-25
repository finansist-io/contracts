// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {IChainlinkAggregatorV3} from "../interfaces/IChainlinkAggregatorV3.sol";

library ChainlinkSequencerGuard {
    error SequencerFeedDecimalsMismatch(address feed, uint8 actual);
    error InvalidSequencerRound(address feed);
    error FutureSequencerRound(address feed, uint256 updatedAt);
    error SequencerDown(address feed);
    error SequencerGracePeriod(address feed, uint256 startedAt, uint256 gracePeriod);

    function requireUp(address feed, uint256 gracePeriod) internal view {
        IChainlinkAggregatorV3 uptimeFeed = IChainlinkAggregatorV3(feed);
        uint8 decimals = uptimeFeed.decimals();
        if (decimals != 0) revert SequencerFeedDecimalsMismatch(feed, decimals);

        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            uptimeFeed.latestRoundData();
        if (roundId == 0 || startedAt == 0 || updatedAt == 0 || answeredInRound < roundId || startedAt > updatedAt) {
            revert InvalidSequencerRound(feed);
        }
        if (updatedAt > block.timestamp) revert FutureSequencerRound(feed, updatedAt);
        if (answer != 0) revert SequencerDown(feed);
        if (block.timestamp - startedAt <= gracePeriod) {
            revert SequencerGracePeriod(feed, startedAt, gracePeriod);
        }
    }
}
