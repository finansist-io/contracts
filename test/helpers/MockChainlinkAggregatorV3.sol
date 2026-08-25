// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {IChainlinkAggregatorV3} from "../../src/interfaces/IChainlinkAggregatorV3.sol";

contract MockChainlinkAggregatorV3 is IChainlinkAggregatorV3 {
    uint8 public override decimals;
    uint256 public override version;
    string public override description;

    uint80 private _roundId;
    int256 private _answer;
    uint256 private _startedAt;
    uint256 private _updatedAt;
    uint80 private _answeredInRound;

    constructor(string memory description_, uint8 decimals_, uint256 version_) {
        description = description_;
        decimals = decimals_;
        version = version_;
    }

    function setDecimals(uint8 decimals_) external {
        decimals = decimals_;
    }

    function setRound(uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
        external
    {
        _roundId = roundId;
        _answer = answer;
        _startedAt = startedAt;
        _updatedAt = updatedAt;
        _answeredInRound = answeredInRound;
    }

    function latestRoundData()
        external
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (_roundId, _answer, _startedAt, _updatedAt, _answeredInRound);
    }
}
