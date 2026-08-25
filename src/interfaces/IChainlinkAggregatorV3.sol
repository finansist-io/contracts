// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {IChainlinkFeedIdentity} from "./IChainlinkFeedIdentity.sol";

interface IChainlinkAggregatorV3 is IChainlinkFeedIdentity {
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}
