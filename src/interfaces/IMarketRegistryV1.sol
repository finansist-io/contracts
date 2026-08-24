// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {VaultTypes} from "../libraries/VaultTypes.sol";

interface IMarketRegistryV1 {
    function EXACT_INPUT_SINGLE_SELECTOR() external view returns (bytes4);
    function chainId() external view returns (uint256);
    function accountingToken() external view returns (address);
    function accountingTokenDecimals() external view returns (uint8);
    function accountingTokenCodeHash() external view returns (bytes32);
    function registryId() external view returns (bytes32);
    function marketCount() external view returns (uint256);
    function marketIdAt(uint256 index) external view returns (bytes32);
    function getMarket(bytes32 marketId) external view returns (VaultTypes.MarketConfig memory);
}
