// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {IMarketRegistryV1} from "./interfaces/IMarketRegistryV1.sol";
import {
    ISlipstreamFactoryIdentity,
    ISlipstreamPoolIdentity,
    ISlipstreamRouterIdentity
} from "./interfaces/ISlipstreamIdentity.sol";
import {VaultTypes} from "./libraries/VaultTypes.sol";

contract MarketRegistryV1 is IMarketRegistryV1 {
    bytes4 public constant override EXACT_INPUT_SINGLE_SELECTOR =
        bytes4(keccak256("exactInputSingle((address,address,int24,address,uint256,uint256,uint256,uint160))"));

    error WrongChain(uint256 expected, uint256 actual);
    error ZeroAddress();
    error EmptyRegistry();
    error InvalidMarket(bytes32 marketId);
    error DuplicateMarket(bytes32 marketId);
    error EmptyCodeHash(address target);
    error CodeHashMismatch(address target, bytes32 expected, bytes32 actual);
    error TokenDecimalsMismatch(address token, uint8 expected, uint8 actual);
    error PoolTokenMismatch(bytes32 marketId, address token0, address token1);
    error PoolTickSpacingMismatch(bytes32 marketId, int24 expected, int24 actual);
    error PoolFactoryMismatch(bytes32 marketId, address expected, address actual);
    error FactoryLookupMismatch(bytes32 marketId, address expected, address actual);
    error EndpointFactoryMismatch(address endpoint, address expected, address actual);
    error UnknownMarket(bytes32 marketId);

    uint256 private immutable _chainId;
    bytes32 private immutable _registryId;
    address private immutable _accountingToken;
    uint8 private immutable _accountingTokenDecimals;
    bytes32 private immutable _accountingTokenCodeHash;

    bytes32[] private _marketIds;
    mapping(bytes32 marketId => VaultTypes.MarketConfig config) private _markets;

    constructor(
        uint256 expectedChainId,
        bytes32 registryId_,
        address accountingToken_,
        uint8 accountingTokenDecimals_,
        bytes32 accountingTokenCodeHash_,
        VaultTypes.MarketConfig[] memory markets_
    ) {
        if (block.chainid != expectedChainId) {
            revert WrongChain(expectedChainId, block.chainid);
        }
        if (registryId_ == bytes32(0)) revert EmptyRegistry();
        if (accountingToken_ == address(0)) revert ZeroAddress();
        if (markets_.length == 0) revert EmptyRegistry();

        _requireCodeHash(accountingToken_, accountingTokenCodeHash_);
        _requireDecimals(accountingToken_, accountingTokenDecimals_);

        _chainId = expectedChainId;
        _registryId = registryId_;
        _accountingToken = accountingToken_;
        _accountingTokenDecimals = accountingTokenDecimals_;
        _accountingTokenCodeHash = accountingTokenCodeHash_;

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

    function accountingTokenDecimals() external view returns (uint8) {
        return _accountingTokenDecimals;
    }

    function accountingTokenCodeHash() external view returns (bytes32) {
        return _accountingTokenCodeHash;
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
                || market.tickSpacing <= 0
        ) revert InvalidMarket(market.marketId);

        _requireCodeHash(market.targetToken, market.targetTokenCodeHash);
        _requireCodeHash(market.factory, market.factoryCodeHash);
        _requireCodeHash(market.pool, market.poolCodeHash);
        _requireCodeHash(market.router, market.routerCodeHash);
        _requireDecimals(market.targetToken, market.targetTokenDecimals);

        ISlipstreamPoolIdentity pool = ISlipstreamPoolIdentity(market.pool);
        address token0 = pool.token0();
        address token1 = pool.token1();
        (address expectedToken0, address expectedToken1) = accountingToken_ < market.targetToken
            ? (accountingToken_, market.targetToken)
            : (market.targetToken, accountingToken_);
        if (token0 != expectedToken0 || token1 != expectedToken1) {
            revert PoolTokenMismatch(market.marketId, token0, token1);
        }

        int24 actualTickSpacing = pool.tickSpacing();
        if (actualTickSpacing != market.tickSpacing) {
            revert PoolTickSpacingMismatch(market.marketId, market.tickSpacing, actualTickSpacing);
        }

        address actualPoolFactory = pool.factory();
        if (actualPoolFactory != market.factory) {
            revert PoolFactoryMismatch(market.marketId, market.factory, actualPoolFactory);
        }

        address factoryPool = ISlipstreamFactoryIdentity(market.factory)
            .getPool(accountingToken_, market.targetToken, market.tickSpacing);
        if (factoryPool != market.pool) revert FactoryLookupMismatch(market.marketId, market.pool, factoryPool);

        address routerFactory = ISlipstreamRouterIdentity(market.router).factory();
        if (routerFactory != market.factory) {
            revert EndpointFactoryMismatch(market.router, market.factory, routerFactory);
        }
    }

    function _requireCodeHash(address target, bytes32 expected) private view {
        if (expected == bytes32(0)) revert EmptyCodeHash(target);
        bytes32 actual = target.codehash;
        if (actual != expected) revert CodeHashMismatch(target, expected, actual);
    }

    function _requireDecimals(address token, uint8 expected) private view {
        uint8 actual = IERC20Metadata(token).decimals();
        if (actual != expected) revert TokenDecimalsMismatch(token, expected, actual);
    }
}
