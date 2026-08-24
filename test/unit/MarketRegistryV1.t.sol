// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {MarketRegistryV1} from "../../src/MarketRegistryV1.sol";
import {VaultTypes} from "../../src/libraries/VaultTypes.sol";
import {
    MockSlipstreamFactory,
    MockSlipstreamPool,
    MockSlipstreamRouter,
    MockToken,
    TestSetup
} from "../helpers/TestSetup.sol";

contract MarketRegistryV1Test is TestSetup {
    function testStoresExactMarketIdentity() public view {
        VaultTypes.MarketConfig memory stored = registry.getMarket(MARKET_ID);
        VaultTypes.AssetConfig memory storedAsset = registry.getAsset(TARGET_ASSET_ID);

        assertEq(registry.chainId(), BASE_CHAIN_ID);
        assertEq(registry.registryId(), REGISTRY_ID);
        assertEq(registry.accountingAssetId(), USDC_ASSET_ID);
        assertEq(registry.accountingToken(), address(usdc));
        assertEq(registry.accountingTokenDecimals(), 6);
        assertEq(registry.accountingTokenCodeHash(), address(usdc).codehash);
        assertEq(registry.assetCount(), 2);
        assertEq(registry.assetIdAt(0), USDC_ASSET_ID);
        assertEq(registry.assetIdAt(1), TARGET_ASSET_ID);
        assertEq(storedAsset.token, address(target));
        assertEq(storedAsset.tokenDecimals, 18);
        assertEq(storedAsset.tokenCodeHash, address(target).codehash);
        assertEq(storedAsset.usdPriceFeed, address(targetPriceFeed));
        assertEq(storedAsset.priceFeedDescriptionHash, keccak256("ETH / USD"));
        assertEq(stored.targetAssetId, TARGET_ASSET_ID);
        assertEq(stored.router, address(router));
        assertEq(stored.routerCodeHash, address(router).codehash);
        assertEq(bytes32(registry.EXACT_INPUT_SINGLE_SELECTOR()), bytes32(bytes4(0xa026383e)));
        assertEq(registry.marketCount(), 1);
        assertEq(registry.marketIdAt(0), MARKET_ID);
    }

    function testRejectsUnknownMarket() public {
        bytes32 unknown = keccak256("unknown");
        vm.expectRevert(abi.encodeWithSelector(MarketRegistryV1.UnknownMarket.selector, unknown));
        registry.getMarket(unknown);
    }

    function testRejectsUnknownAsset() public {
        bytes32 unknown = keccak256("unknown");
        vm.expectRevert(abi.encodeWithSelector(MarketRegistryV1.UnknownAsset.selector, unknown));
        registry.getAsset(unknown);
    }

    function testMultipleMarketsMayShareOneTargetAsset() public {
        bytes32 secondMarketId = keccak256("weth-usdc-slipstream-200");
        (address token0, address token1) = sortedTokens(address(usdc), address(target));
        MockSlipstreamPool secondPool = new MockSlipstreamPool(address(poolFactory), token0, token1, 200);
        poolFactory.setPool(address(usdc), address(target), 200, address(secondPool));

        VaultTypes.MarketConfig[] memory markets = new VaultTypes.MarketConfig[](2);
        markets[0] = marketConfig(MARKET_ID);
        markets[1] = marketConfigFor(
            secondMarketId, TARGET_ASSET_ID, address(poolFactory), address(secondPool), address(router), 200
        );
        MarketRegistryV1 sharedAssetRegistry = _deploy(keccak256("shared-target-asset"), markets);

        assertEq(sharedAssetRegistry.marketCount(), 2);
        assertEq(sharedAssetRegistry.getMarket(MARKET_ID).targetAssetId, TARGET_ASSET_ID);
        assertEq(sharedAssetRegistry.getMarket(secondMarketId).targetAssetId, TARGET_ASSET_ID);
    }

    function testRejectsInvalidAssetFields() public {
        VaultTypes.AssetConfig[] memory assets = _assets();
        assets[1].assetId = bytes32(0);
        vm.expectRevert(abi.encodeWithSelector(MarketRegistryV1.InvalidAsset.selector, bytes32(0)));
        _deployWithAssets(keccak256("zero-asset-id"), assets, _singleMarket());

        assets = _assets();
        assets[1].token = address(0);
        vm.expectRevert(abi.encodeWithSelector(MarketRegistryV1.InvalidAsset.selector, TARGET_ASSET_ID));
        _deployWithAssets(keccak256("zero-token"), assets, _singleMarket());

        assets = _assets();
        assets[1].usdPriceFeed = address(0);
        vm.expectRevert(abi.encodeWithSelector(MarketRegistryV1.InvalidAsset.selector, TARGET_ASSET_ID));
        _deployWithAssets(keccak256("zero-price-feed"), assets, _singleMarket());

        assets = _assets();
        assets[1].priceFeedDescriptionHash = bytes32(0);
        vm.expectRevert(abi.encodeWithSelector(MarketRegistryV1.InvalidAsset.selector, TARGET_ASSET_ID));
        _deployWithAssets(keccak256("zero-feed-description"), assets, _singleMarket());

        assets = _assets();
        assets[1].priceFeedVersion = 0;
        vm.expectRevert(abi.encodeWithSelector(MarketRegistryV1.InvalidAsset.selector, TARGET_ASSET_ID));
        _deployWithAssets(keccak256("zero-feed-version"), assets, _singleMarket());
    }

    function testRejectsDuplicateAssetId() public {
        VaultTypes.AssetConfig[] memory assets = _assets();
        assets[1].assetId = USDC_ASSET_ID;

        vm.expectRevert(abi.encodeWithSelector(MarketRegistryV1.DuplicateAsset.selector, USDC_ASSET_ID));
        _deployWithAssets(keccak256("duplicate-asset"), assets, _singleMarket());
    }

    function testRejectsDuplicateToken() public {
        VaultTypes.AssetConfig[] memory assets = _assets();
        assets[1].token = address(usdc);

        vm.expectRevert(abi.encodeWithSelector(MarketRegistryV1.DuplicateToken.selector, address(usdc)));
        _deployWithAssets(keccak256("duplicate-token"), assets, _singleMarket());
    }

    function testRejectsDuplicatePriceFeed() public {
        VaultTypes.AssetConfig[] memory assets = _assets();
        assets[1].usdPriceFeed = address(usdcPriceFeed);

        vm.expectRevert(abi.encodeWithSelector(MarketRegistryV1.DuplicatePriceFeed.selector, address(usdcPriceFeed)));
        _deployWithAssets(keccak256("duplicate-feed"), assets, _singleMarket());
    }

    function testRejectsUnknownAccountingAsset() public {
        bytes32 unknown = keccak256("unknown-accounting");

        vm.expectRevert(abi.encodeWithSelector(MarketRegistryV1.UnknownAsset.selector, unknown));
        new MarketRegistryV1(BASE_CHAIN_ID, keccak256("unknown-accounting"), unknown, _assets(), _singleMarket());
    }

    function testRejectsUnknownTargetAsset() public {
        bytes32 unknown = keccak256("unknown-target");
        VaultTypes.MarketConfig[] memory markets = _singleMarket();
        markets[0].targetAssetId = unknown;

        vm.expectRevert(abi.encodeWithSelector(MarketRegistryV1.UnknownAsset.selector, unknown));
        _deploy(keccak256("unknown-target"), markets);
    }

    function testRejectsWrongPriceFeedIdentity() public {
        VaultTypes.AssetConfig[] memory assets = _assets();
        assets[1].priceFeedDecimals = 18;
        vm.expectRevert(
            abi.encodeWithSelector(
                MarketRegistryV1.PriceFeedDecimalsMismatch.selector, address(targetPriceFeed), uint8(18), uint8(8)
            )
        );
        _deployWithAssets(keccak256("wrong-feed-decimals"), assets, _singleMarket());

        assets = _assets();
        bytes32 wrongDescriptionHash = keccak256("WETH / EUR");
        assets[1].priceFeedDescriptionHash = wrongDescriptionHash;
        vm.expectRevert(
            abi.encodeWithSelector(
                MarketRegistryV1.PriceFeedDescriptionMismatch.selector,
                address(targetPriceFeed),
                wrongDescriptionHash,
                keccak256("ETH / USD")
            )
        );
        _deployWithAssets(keccak256("wrong-feed-description"), assets, _singleMarket());

        assets = _assets();
        assets[1].priceFeedVersion = 7;
        vm.expectRevert(
            abi.encodeWithSelector(
                MarketRegistryV1.PriceFeedVersionMismatch.selector, address(targetPriceFeed), uint256(7), uint256(6)
            )
        );
        _deployWithAssets(keccak256("wrong-feed-version"), assets, _singleMarket());
    }

    function testRejectsWrongPriceFeedCodeHash() public {
        VaultTypes.AssetConfig[] memory assets = _assets();
        bytes32 wrongCodeHash = keccak256("wrong-feed-code");
        assets[1].priceFeedCodeHash = wrongCodeHash;

        vm.expectRevert(
            abi.encodeWithSelector(
                MarketRegistryV1.CodeHashMismatch.selector,
                address(targetPriceFeed),
                wrongCodeHash,
                address(targetPriceFeed).codehash
            )
        );
        _deployWithAssets(keccak256("wrong-feed-code"), assets, _singleMarket());

        assets = _assets();
        assets[1].priceFeedCodeHash = bytes32(0);
        vm.expectRevert(abi.encodeWithSelector(MarketRegistryV1.EmptyCodeHash.selector, address(targetPriceFeed)));
        _deployWithAssets(keccak256("empty-feed-code"), assets, _singleMarket());
    }

    function testRejectsWrongCodeHash() public {
        VaultTypes.MarketConfig[] memory markets = new VaultTypes.MarketConfig[](1);
        markets[0] = marketConfig(MARKET_ID);
        markets[0].routerCodeHash = keccak256("wrong-code");

        vm.expectRevert(
            abi.encodeWithSelector(
                MarketRegistryV1.CodeHashMismatch.selector,
                address(router),
                markets[0].routerCodeHash,
                address(router).codehash
            )
        );
        _deploy(keccak256("bad-registry"), markets);
    }

    function testRejectsWrongAccountingTokenCodeHash() public {
        VaultTypes.MarketConfig[] memory markets = _singleMarket();
        VaultTypes.AssetConfig[] memory assets = _assets();
        bytes32 wrongCodeHash = keccak256("wrong-accounting-code");
        assets[0].tokenCodeHash = wrongCodeHash;

        vm.expectRevert(
            abi.encodeWithSelector(
                MarketRegistryV1.CodeHashMismatch.selector, address(usdc), wrongCodeHash, address(usdc).codehash
            )
        );
        _deployWithAssets(keccak256("wrong-usdc-code"), assets, markets);
    }

    function testRejectsEmptyCodeHash() public {
        VaultTypes.MarketConfig[] memory markets = _singleMarket();
        markets[0].routerCodeHash = bytes32(0);

        vm.expectRevert(abi.encodeWithSelector(MarketRegistryV1.EmptyCodeHash.selector, address(router)));
        _deploy(keccak256("empty-router-code-hash"), markets);
    }

    function testRejectsWrongAccountingTokenDecimals() public {
        VaultTypes.MarketConfig[] memory markets = _singleMarket();
        VaultTypes.AssetConfig[] memory assets = _assets();
        assets[0].tokenDecimals = 18;

        vm.expectRevert(
            abi.encodeWithSelector(MarketRegistryV1.TokenDecimalsMismatch.selector, address(usdc), uint8(18), uint8(6))
        );
        _deployWithAssets(keccak256("wrong-usdc-decimals"), assets, markets);
    }

    function testRejectsWrongTargetDecimals() public {
        VaultTypes.MarketConfig[] memory markets = _singleMarket();
        VaultTypes.AssetConfig[] memory assets = _assets();
        assets[1].tokenDecimals = 8;

        vm.expectRevert(
            abi.encodeWithSelector(
                MarketRegistryV1.TokenDecimalsMismatch.selector, address(target), uint8(8), uint8(18)
            )
        );
        _deployWithAssets(keccak256("wrong-target-decimals"), assets, markets);
    }

    function testRejectsWrongPoolPair() public {
        MockToken unrelated = new MockToken("Unrelated", "OTHER", 18);
        (address token0,) = sortedTokens(address(usdc), address(unrelated));
        address token1 = token0 == address(usdc) ? address(unrelated) : address(usdc);
        MockSlipstreamPool wrongPool = new MockSlipstreamPool(address(poolFactory), token0, token1, 100);
        VaultTypes.MarketConfig[] memory markets = _singleMarket();
        markets[0].pool = address(wrongPool);
        markets[0].poolCodeHash = address(wrongPool).codehash;

        vm.expectRevert(abi.encodeWithSelector(MarketRegistryV1.PoolTokenMismatch.selector, MARKET_ID, token0, token1));
        _deploy(keccak256("wrong-pair"), markets);
    }

    function testRejectsReversedPoolTokenOrder() public {
        (address expectedToken0, address expectedToken1) = sortedTokens(address(usdc), address(target));
        MockSlipstreamPool wrongPool = new MockSlipstreamPool(address(poolFactory), expectedToken1, expectedToken0, 100);
        VaultTypes.MarketConfig[] memory markets = _singleMarket();
        markets[0].pool = address(wrongPool);
        markets[0].poolCodeHash = address(wrongPool).codehash;

        vm.expectRevert(
            abi.encodeWithSelector(
                MarketRegistryV1.PoolTokenMismatch.selector, MARKET_ID, expectedToken1, expectedToken0
            )
        );
        _deploy(keccak256("reversed-pair"), markets);
    }

    function testRejectsWrongPoolTickSpacing() public {
        (address token0, address token1) = sortedTokens(address(usdc), address(target));
        MockSlipstreamPool wrongPool = new MockSlipstreamPool(address(poolFactory), token0, token1, 50);
        VaultTypes.MarketConfig[] memory markets = _singleMarket();
        markets[0].pool = address(wrongPool);
        markets[0].poolCodeHash = address(wrongPool).codehash;

        vm.expectRevert(
            abi.encodeWithSelector(MarketRegistryV1.PoolTickSpacingMismatch.selector, MARKET_ID, int24(100), int24(50))
        );
        _deploy(keccak256("wrong-tick-spacing"), markets);
    }

    function testRejectsWrongPoolFactory() public {
        MockSlipstreamFactory otherFactory = new MockSlipstreamFactory();
        (address token0, address token1) = sortedTokens(address(usdc), address(target));
        MockSlipstreamPool wrongPool = new MockSlipstreamPool(address(otherFactory), token0, token1, 100);
        VaultTypes.MarketConfig[] memory markets = _singleMarket();
        markets[0].pool = address(wrongPool);
        markets[0].poolCodeHash = address(wrongPool).codehash;

        vm.expectRevert(
            abi.encodeWithSelector(
                MarketRegistryV1.PoolFactoryMismatch.selector, MARKET_ID, address(poolFactory), address(otherFactory)
            )
        );
        _deploy(keccak256("wrong-pool-factory"), markets);
    }

    function testRejectsFactoryLookupMismatch() public {
        poolFactory.setPool(address(usdc), address(target), 100, address(0));
        VaultTypes.MarketConfig[] memory markets = _singleMarket();

        vm.expectRevert(
            abi.encodeWithSelector(
                MarketRegistryV1.FactoryLookupMismatch.selector, MARKET_ID, address(pool), address(0)
            )
        );
        _deploy(keccak256("wrong-factory-pool"), markets);
    }

    function testRejectsRouterFromAnotherFactory() public {
        MockSlipstreamFactory otherFactory = new MockSlipstreamFactory();
        MockSlipstreamRouter wrongRouter = new MockSlipstreamRouter(address(otherFactory));
        VaultTypes.MarketConfig[] memory markets = _singleMarket();
        markets[0].router = address(wrongRouter);
        markets[0].routerCodeHash = address(wrongRouter).codehash;

        vm.expectRevert(
            abi.encodeWithSelector(
                MarketRegistryV1.EndpointFactoryMismatch.selector,
                address(wrongRouter),
                address(poolFactory),
                address(otherFactory)
            )
        );
        _deploy(keccak256("wrong-router-factory"), markets);
    }

    function testRejectsDuplicateMarket() public {
        VaultTypes.MarketConfig[] memory markets = new VaultTypes.MarketConfig[](2);
        markets[0] = marketConfig(MARKET_ID);
        markets[1] = marketConfig(MARKET_ID);

        vm.expectRevert(abi.encodeWithSelector(MarketRegistryV1.DuplicateMarket.selector, MARKET_ID));
        _deploy(keccak256("duplicate-registry"), markets);
    }

    function testRejectsWrongChain() public {
        VaultTypes.MarketConfig[] memory markets = new VaultTypes.MarketConfig[](1);
        markets[0] = marketConfig(MARKET_ID);

        vm.expectRevert(abi.encodeWithSelector(MarketRegistryV1.WrongChain.selector, uint256(1), BASE_CHAIN_ID));
        new MarketRegistryV1(1, keccak256("wrong-chain"), USDC_ASSET_ID, _assets(), markets);
    }

    function testRejectsEmptyRegistry() public {
        VaultTypes.MarketConfig[] memory markets = new VaultTypes.MarketConfig[](0);

        vm.expectRevert(MarketRegistryV1.EmptyRegistry.selector);
        _deploy(keccak256("empty-registry"), markets);
    }

    function testRejectsEmptyAssetSet() public {
        VaultTypes.AssetConfig[] memory assets = new VaultTypes.AssetConfig[](0);

        vm.expectRevert(MarketRegistryV1.EmptyRegistry.selector);
        _deployWithAssets(keccak256("empty-assets"), assets, _singleMarket());
    }

    function testRejectsAccountingTokenAsTarget() public {
        VaultTypes.MarketConfig[] memory markets = new VaultTypes.MarketConfig[](1);
        markets[0] = marketConfig(MARKET_ID);
        markets[0].targetAssetId = USDC_ASSET_ID;

        vm.expectRevert(abi.encodeWithSelector(MarketRegistryV1.InvalidMarket.selector, MARKET_ID));
        _deploy(keccak256("invalid-market"), markets);
    }

    function _singleMarket() private view returns (VaultTypes.MarketConfig[] memory markets) {
        markets = new VaultTypes.MarketConfig[](1);
        markets[0] = marketConfig(MARKET_ID);
    }

    function _assets() private view returns (VaultTypes.AssetConfig[] memory assets) {
        assets = new VaultTypes.AssetConfig[](2);
        assets[0] = assetConfig(USDC_ASSET_ID, address(usdc), 6, address(usdcPriceFeed), "USDC / USD");
        assets[1] = assetConfig(TARGET_ASSET_ID, address(target), 18, address(targetPriceFeed), "ETH / USD");
    }

    function _deploy(bytes32 registryId_, VaultTypes.MarketConfig[] memory markets) private returns (MarketRegistryV1) {
        return _deployWithAssets(registryId_, _assets(), markets);
    }

    function _deployWithAssets(
        bytes32 registryId_,
        VaultTypes.AssetConfig[] memory assets,
        VaultTypes.MarketConfig[] memory markets
    ) private returns (MarketRegistryV1) {
        return new MarketRegistryV1(BASE_CHAIN_ID, registryId_, USDC_ASSET_ID, assets, markets);
    }
}
