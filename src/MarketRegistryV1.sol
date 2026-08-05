// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {IMarketRegistryV1} from "./interfaces/IMarketRegistryV1.sol";
import {VaultTypes} from "./libraries/VaultTypes.sol";

contract MarketRegistryV1 is IMarketRegistryV1 {
    error WrongChain(uint256 expected, uint256 actual);
    error ZeroAddress();
    error EmptyRegistry();
    error InvalidMarket(bytes32 marketId);
    error DuplicateMarket(bytes32 marketId);
    error CodeHashMismatch(address target, bytes32 expected, bytes32 actual);
    error UnknownMarket(bytes32 marketId);

    uint256 private immutable _chainId;
    bytes32 private immutable _registryId;
    address private immutable _accountingToken;

    bytes32[] private _marketIds;
    mapping(bytes32 marketId => VaultTypes.MarketConfig config) private _markets;

    constructor(
        uint256 expectedChainId,
        bytes32 registryId_,
        address accountingToken_,
        VaultTypes.MarketConfig[] memory markets_
    ) {
        if (block.chainid != expectedChainId) {
            revert WrongChain(expectedChainId, block.chainid);
        }
        if (registryId_ == bytes32(0)) revert EmptyRegistry();
        if (accountingToken_ == address(0) || accountingToken_.code.length == 0) revert ZeroAddress();
        if (markets_.length == 0) revert EmptyRegistry();

        _chainId = expectedChainId;
        _registryId = registryId_;
        _accountingToken = accountingToken_;

        for (uint256 i = 0; i < markets_.length; ++i) {
            VaultTypes.MarketConfig memory market = markets_[i];
            _validateMarket(market, accountingToken_);
            if (_markets[market.marketId].marketId != bytes32(0)) revert DuplicateMarket(market.marketId);
            _markets[market.marketId] = market;
            _marketIds.push(market.marketId);
        }
    }

    function marketCount() external view returns (uint256) {
        return _marketIds.length;
    }

    function chainId() external view returns (uint256) {
        return _chainId;
    }

    function registryId() external view returns (bytes32) {
        return _registryId;
    }

    function accountingToken() external view returns (address) {
        return _accountingToken;
    }

    function marketIdAt(uint256 index) external view returns (bytes32) {
        return _marketIds[index];
    }

    function getMarket(bytes32 marketId) external view returns (VaultTypes.MarketConfig memory market) {
        market = _markets[marketId];
        if (market.marketId == bytes32(0)) revert UnknownMarket(marketId);
    }

    function _validateMarket(VaultTypes.MarketConfig memory market, address accountingToken_) private view {
        if (
            market.marketId == bytes32(0) || market.targetToken == address(0) || market.targetToken == accountingToken_
                || market.factory == address(0) || market.pool == address(0) || market.router == address(0)
                || market.quoter == address(0) || market.tickSpacing <= 0 || market.swapSelector == bytes4(0)
        ) revert InvalidMarket(market.marketId);

        if (market.targetToken.code.length == 0) revert ZeroAddress();
        _requireCodeHash(market.factory, market.factoryCodeHash);
        _requireCodeHash(market.pool, market.poolCodeHash);
        _requireCodeHash(market.router, market.routerCodeHash);
        _requireCodeHash(market.quoter, market.quoterCodeHash);
    }

    function _requireCodeHash(address target, bytes32 expected) private view {
        bytes32 actual = target.codehash;
        if (expected == bytes32(0) || actual != expected) revert CodeHashMismatch(target, expected, actual);
    }
}
