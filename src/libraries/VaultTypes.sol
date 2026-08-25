// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

library VaultTypes {
    struct AssetConfig {
        bytes32 assetId;
        address token;
        address usdPriceFeed;
        uint8 tokenDecimals;
        uint8 priceFeedDecimals;
        uint32 priceMaxAge;
        uint256 priceFeedVersion;
        bytes32 tokenCodeHash;
        bytes32 priceFeedCodeHash;
        bytes32 priceFeedDescriptionHash;
    }

    struct MarketConfig {
        bytes32 marketId;
        bytes32 targetAssetId;
        address factory;
        address pool;
        address router;
        int24 tickSpacing;
        bytes32 factoryCodeHash;
        bytes32 poolCodeHash;
        bytes32 routerCodeHash;
    }

    struct Mandate {
        bytes32 strategyVersionHash;
        address executor;
        address authorFeeRecipient;
        address platformFeeRecipient;
        uint128 maxDeployableUsdc;
        uint128 maxPerEntryUsdc;
        uint16 maxSlippageBps;
        uint16 authorFeeBps;
        uint16 platformFeeBps;
        uint64 expiresAt;
    }
}
