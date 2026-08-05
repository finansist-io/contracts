// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

library VaultTypes {
    struct MarketConfig {
        bytes32 marketId;
        address targetToken;
        address factory;
        address pool;
        address router;
        address quoter;
        int24 tickSpacing;
        bytes4 swapSelector;
        bytes32 factoryCodeHash;
        bytes32 poolCodeHash;
        bytes32 routerCodeHash;
        bytes32 quoterCodeHash;
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
