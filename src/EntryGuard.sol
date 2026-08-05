// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";

import {IEntryGuard} from "./interfaces/IEntryGuard.sol";

contract EntryGuard is IEntryGuard, Ownable2Step {
    bool public globalPaused;
    mapping(bytes32 marketId => bool paused) public marketPaused;

    event GlobalEntryPauseChanged(bool paused);
    event MarketEntryPauseChanged(bytes32 indexed marketId, bool paused);

    constructor(address initialOwner) Ownable(initialOwner) {}

    function pauseGlobal() external onlyOwner {
        if (!globalPaused) {
            globalPaused = true;
            emit GlobalEntryPauseChanged(true);
        }
    }

    function unpauseGlobal() external onlyOwner {
        if (globalPaused) {
            globalPaused = false;
            emit GlobalEntryPauseChanged(false);
        }
    }

    function pauseMarket(bytes32 marketId) external onlyOwner {
        if (!marketPaused[marketId]) {
            marketPaused[marketId] = true;
            emit MarketEntryPauseChanged(marketId, true);
        }
    }

    function unpauseMarket(bytes32 marketId) external onlyOwner {
        if (marketPaused[marketId]) {
            marketPaused[marketId] = false;
            emit MarketEntryPauseChanged(marketId, false);
        }
    }

    function isEntryAllowed(bytes32 marketId) external view returns (bool) {
        return !globalPaused && !marketPaused[marketId];
    }
}
