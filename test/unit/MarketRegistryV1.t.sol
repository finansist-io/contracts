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

        assertEq(registry.chainId(), BASE_CHAIN_ID);
        assertEq(registry.registryId(), REGISTRY_ID);
        assertEq(registry.accountingToken(), address(usdc));
        assertEq(registry.accountingTokenDecimals(), 6);
        assertEq(registry.accountingTokenCodeHash(), address(usdc).codehash);
        assertEq(stored.targetToken, address(target));
        assertEq(stored.targetTokenDecimals, 18);
        assertEq(stored.targetTokenCodeHash, address(target).codehash);
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
        bytes32 wrongCodeHash = keccak256("wrong-accounting-code");

        vm.expectRevert(
            abi.encodeWithSelector(
                MarketRegistryV1.CodeHashMismatch.selector, address(usdc), wrongCodeHash, address(usdc).codehash
            )
        );
        new MarketRegistryV1(BASE_CHAIN_ID, keccak256("wrong-usdc-code"), address(usdc), 6, wrongCodeHash, markets);
    }

    function testRejectsEmptyCodeHash() public {
        VaultTypes.MarketConfig[] memory markets = _singleMarket();
        markets[0].routerCodeHash = bytes32(0);

        vm.expectRevert(abi.encodeWithSelector(MarketRegistryV1.EmptyCodeHash.selector, address(router)));
        _deploy(keccak256("empty-router-code-hash"), markets);
    }

    function testRejectsWrongAccountingTokenDecimals() public {
        VaultTypes.MarketConfig[] memory markets = _singleMarket();

        vm.expectRevert(
            abi.encodeWithSelector(MarketRegistryV1.TokenDecimalsMismatch.selector, address(usdc), uint8(18), uint8(6))
        );
        new MarketRegistryV1(
            BASE_CHAIN_ID, keccak256("wrong-usdc-decimals"), address(usdc), 18, address(usdc).codehash, markets
        );
    }

    function testRejectsWrongTargetDecimals() public {
        VaultTypes.MarketConfig[] memory markets = _singleMarket();
        markets[0].targetTokenDecimals = 8;

        vm.expectRevert(
            abi.encodeWithSelector(
                MarketRegistryV1.TokenDecimalsMismatch.selector, address(target), uint8(8), uint8(18)
            )
        );
        _deploy(keccak256("wrong-target-decimals"), markets);
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
        new MarketRegistryV1(1, keccak256("wrong-chain"), address(usdc), 6, address(usdc).codehash, markets);
    }

    function testRejectsEmptyRegistry() public {
        VaultTypes.MarketConfig[] memory markets = new VaultTypes.MarketConfig[](0);

        vm.expectRevert(MarketRegistryV1.EmptyRegistry.selector);
        _deploy(keccak256("empty-registry"), markets);
    }

    function testRejectsAccountingTokenAsTarget() public {
        VaultTypes.MarketConfig[] memory markets = new VaultTypes.MarketConfig[](1);
        markets[0] = marketConfig(MARKET_ID);
        markets[0].targetToken = address(usdc);

        vm.expectRevert(abi.encodeWithSelector(MarketRegistryV1.InvalidMarket.selector, MARKET_ID));
        _deploy(keccak256("invalid-market"), markets);
    }

    function _singleMarket() private view returns (VaultTypes.MarketConfig[] memory markets) {
        markets = new VaultTypes.MarketConfig[](1);
        markets[0] = marketConfig(MARKET_ID);
    }

    function _deploy(bytes32 registryId_, VaultTypes.MarketConfig[] memory markets) private returns (MarketRegistryV1) {
        return new MarketRegistryV1(BASE_CHAIN_ID, registryId_, address(usdc), 6, address(usdc).codehash, markets);
    }
}
