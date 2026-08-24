// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

interface IChainlinkFeedIdentity {
    function decimals() external view returns (uint8);
    function description() external view returns (string memory);
    function version() external view returns (uint256);
}
