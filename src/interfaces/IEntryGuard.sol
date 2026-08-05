// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

interface IEntryGuard {
    function isEntryAllowed(bytes32 marketId) external view returns (bool);
}
