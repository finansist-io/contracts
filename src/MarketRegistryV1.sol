// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {IChainlinkFeedIdentity} from "./interfaces/IChainlinkFeedIdentity.sol";
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
    error EmptyRegistry();
    error InvalidAsset(bytes32 assetId);
    error DuplicateAsset(bytes32 assetId);
    error DuplicateToken(address token);
    error DuplicatePriceFeed(address priceFeed);
    error InvalidMarket(bytes32 marketId);
    error DuplicateMarket(bytes32 marketId);
    error EmptyCodeHash(address target);
    error CodeHashMismatch(address target, bytes32 expected, bytes32 actual);
    error TokenDecimalsMismatch(address token, uint8 expected, uint8 actual);
    error PriceFeedDecimalsMismatch(address priceFeed, uint8 expected, uint8 actual);
    error PriceFeedDescriptionMismatch(address priceFeed, bytes32 expected, bytes32 actual);
    error PriceFeedVersionMismatch(address priceFeed, uint256 expected, uint256 actual);
    error PoolTokenMismatch(bytes32 marketId, address token0, address token1);
    error PoolTickSpacingMismatch(bytes32 marketId, int24 expected, int24 actual);
    error PoolFactoryMismatch(bytes32 marketId, address expected, address actual);
    error FactoryLookupMismatch(bytes32 marketId, address expected, address actual);
    error EndpointFactoryMismatch(address endpoint, address expected, address actual);
    error UnknownAsset(bytes32 assetId);
    error UnknownMarket(bytes32 marketId);

    uint256 private immutable _chainId;
    bytes32 private immutable _registryId;
    bytes32 private immutable _accountingAssetId;

    bytes32[] private _assetIds;
    bytes32[] private _marketIds;
    mapping(bytes32 assetId => VaultTypes.AssetConfig config) private _assets;
    mapping(bytes32 marketId => VaultTypes.MarketConfig config) private _markets;

    constructor(
        uint256 expectedChainId,
        bytes32 registryId_,
        bytes32 accountingAssetId_,
        VaultTypes.AssetConfig[] memory assets_,
        VaultTypes.MarketConfig[] memory markets_
    ) {
        if (block.chainid != expectedChainId) {
            revert WrongChain(expectedChainId, block.chainid);
        }
        if (registryId_ == bytes32(0)) revert EmptyRegistry();
        if (assets_.length == 0 || markets_.length == 0) revert EmptyRegistry();

        _chainId = expectedChainId;
        _registryId = registryId_;
        _accountingAssetId = accountingAssetId_;

        for (uint256 i = 0; i < assets_.length; ++i) {
            _registerAsset(assets_[i]);
        }

        VaultTypes.AssetConfig memory accountingAsset = _assets[accountingAssetId_];
        if (accountingAsset.assetId == bytes32(0)) revert UnknownAsset(accountingAssetId_);

        for (uint256 i = 0; i < markets_.length; ++i) {
            VaultTypes.MarketConfig memory market = markets_[i];
            if (_markets[market.marketId].marketId != bytes32(0)) revert DuplicateMarket(market.marketId);
            _validateMarket(market, accountingAsset);
            _markets[market.marketId] = market;
            _marketIds.push(market.marketId);
        }
    }

    function assetCount() external view returns (uint256) {
        return _assetIds.length;
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

    function accountingAssetId() external view returns (bytes32) {
        return _accountingAssetId;
    }

    function accountingToken() external view returns (address) {
        return _assets[_accountingAssetId].token;
    }

    function accountingTokenDecimals() external view returns (uint8) {
        return _assets[_accountingAssetId].tokenDecimals;
    }

    function accountingTokenCodeHash() external view returns (bytes32) {
        return _assets[_accountingAssetId].tokenCodeHash;
    }

    function assetIdAt(uint256 index) external view returns (bytes32) {
        return _assetIds[index];
    }

    function getAsset(bytes32 assetId) external view returns (VaultTypes.AssetConfig memory asset) {
        asset = _assets[assetId];
        if (asset.assetId == bytes32(0)) revert UnknownAsset(assetId);
    }

    function marketIdAt(uint256 index) external view returns (bytes32) {
        return _marketIds[index];
    }

    function getMarket(bytes32 marketId) external view returns (VaultTypes.MarketConfig memory market) {
        market = _markets[marketId];
        if (market.marketId == bytes32(0)) revert UnknownMarket(marketId);
    }

    function _registerAsset(VaultTypes.AssetConfig memory asset) private {
        if (
            asset.assetId == bytes32(0) || asset.token == address(0) || asset.usdPriceFeed == address(0)
                || asset.priceFeedDescriptionHash == bytes32(0) || asset.priceFeedVersion == 0
        ) revert InvalidAsset(asset.assetId);
        if (_assets[asset.assetId].assetId != bytes32(0)) revert DuplicateAsset(asset.assetId);
        for (uint256 i = 0; i < _assetIds.length; ++i) {
            VaultTypes.AssetConfig storage registered = _assets[_assetIds[i]];
            if (registered.token == asset.token) revert DuplicateToken(asset.token);
            if (registered.usdPriceFeed == asset.usdPriceFeed) revert DuplicatePriceFeed(asset.usdPriceFeed);
        }

        _requireCodeHash(asset.token, asset.tokenCodeHash);
        _requireDecimals(asset.token, asset.tokenDecimals);
        _requireCodeHash(asset.usdPriceFeed, asset.priceFeedCodeHash);

        IChainlinkFeedIdentity priceFeed = IChainlinkFeedIdentity(asset.usdPriceFeed);
        uint8 actualDecimals = priceFeed.decimals();
        if (actualDecimals != asset.priceFeedDecimals) {
            revert PriceFeedDecimalsMismatch(asset.usdPriceFeed, asset.priceFeedDecimals, actualDecimals);
        }
        // forge-lint: disable-next-line(asm-keccak256)
        bytes32 actualDescriptionHash = keccak256(bytes(priceFeed.description()));
        if (actualDescriptionHash != asset.priceFeedDescriptionHash) {
            revert PriceFeedDescriptionMismatch(
                asset.usdPriceFeed, asset.priceFeedDescriptionHash, actualDescriptionHash
            );
        }
        uint256 actualVersion = priceFeed.version();
        if (actualVersion != asset.priceFeedVersion) {
            revert PriceFeedVersionMismatch(asset.usdPriceFeed, asset.priceFeedVersion, actualVersion);
        }

        _assets[asset.assetId] = asset;
        _assetIds.push(asset.assetId);
    }

    function _validateMarket(VaultTypes.MarketConfig memory market, VaultTypes.AssetConfig memory accountingAsset)
        private
        view
    {
        if (
            market.marketId == bytes32(0) || market.targetAssetId == bytes32(0)
                || market.targetAssetId == accountingAsset.assetId || market.factory == address(0)
                || market.pool == address(0) || market.router == address(0) || market.tickSpacing <= 0
        ) revert InvalidMarket(market.marketId);

        VaultTypes.AssetConfig memory targetAsset = _assets[market.targetAssetId];
        if (targetAsset.assetId == bytes32(0)) revert UnknownAsset(market.targetAssetId);

        _requireCodeHash(market.factory, market.factoryCodeHash);
        _requireCodeHash(market.pool, market.poolCodeHash);
        _requireCodeHash(market.router, market.routerCodeHash);

        ISlipstreamPoolIdentity pool = ISlipstreamPoolIdentity(market.pool);
        address token0 = pool.token0();
        address token1 = pool.token1();
        (address expectedToken0, address expectedToken1) = accountingAsset.token < targetAsset.token
            ? (accountingAsset.token, targetAsset.token)
            : (targetAsset.token, accountingAsset.token);
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
            .getPool(accountingAsset.token, targetAsset.token, market.tickSpacing);
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
