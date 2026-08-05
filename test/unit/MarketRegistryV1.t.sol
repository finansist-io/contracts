// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {MarketRegistryV1} from "../../src/MarketRegistryV1.sol";
import {VaultTypes} from "../../src/libraries/VaultTypes.sol";
import {TestSetup} from "../helpers/TestSetup.sol";

contract MarketRegistryV1Test is TestSetup {
    function testStoresExactMarketIdentity() public view {
        VaultTypes.MarketConfig memory stored = registry.getMarket(MARKET_ID);

        assertEq(registry.chainId(), BASE_CHAIN_ID);
        assertEq(registry.registryId(), REGISTRY_ID);
        assertEq(registry.accountingToken(), address(usdc));
        assertEq(stored.targetToken, address(target));
        assertEq(stored.router, address(router));
        assertEq(stored.routerCodeHash, address(router).codehash);
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
        new MarketRegistryV1(BASE_CHAIN_ID, keccak256("bad-registry"), address(usdc), markets);
    }

    function testRejectsDuplicateMarket() public {
        VaultTypes.MarketConfig[] memory markets = new VaultTypes.MarketConfig[](2);
        markets[0] = marketConfig(MARKET_ID);
        markets[1] = marketConfig(MARKET_ID);

        vm.expectRevert(abi.encodeWithSelector(MarketRegistryV1.DuplicateMarket.selector, MARKET_ID));
        new MarketRegistryV1(BASE_CHAIN_ID, keccak256("duplicate-registry"), address(usdc), markets);
    }

    function testRejectsWrongChain() public {
        VaultTypes.MarketConfig[] memory markets = new VaultTypes.MarketConfig[](1);
        markets[0] = marketConfig(MARKET_ID);

        vm.expectRevert(abi.encodeWithSelector(MarketRegistryV1.WrongChain.selector, uint256(1), BASE_CHAIN_ID));
        new MarketRegistryV1(1, keccak256("wrong-chain"), address(usdc), markets);
    }

    function testRejectsEmptyRegistry() public {
        VaultTypes.MarketConfig[] memory markets = new VaultTypes.MarketConfig[](0);

        vm.expectRevert(MarketRegistryV1.EmptyRegistry.selector);
        new MarketRegistryV1(BASE_CHAIN_ID, keccak256("empty-registry"), address(usdc), markets);
    }

    function testRejectsAccountingTokenAsTarget() public {
        VaultTypes.MarketConfig[] memory markets = new VaultTypes.MarketConfig[](1);
        markets[0] = marketConfig(MARKET_ID);
        markets[0].targetToken = address(usdc);

        vm.expectRevert(abi.encodeWithSelector(MarketRegistryV1.InvalidMarket.selector, MARKET_ID));
        new MarketRegistryV1(BASE_CHAIN_ID, keccak256("invalid-market"), address(usdc), markets);
    }
}
