// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {VaultTypes} from "../libraries/VaultTypes.sol";

interface IMarketRegistryV1 {
    function accountingToken() external view returns (address);
    function registryId() external view returns (bytes32);
    function getMarket(bytes32 marketId) external view returns (VaultTypes.MarketConfig memory);
}
