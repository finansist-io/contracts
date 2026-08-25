// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {Test} from "forge-std/Test.sol";

import {MarketRegistryV1} from "../../src/MarketRegistryV1.sol";
import {ChainlinkPriceReference} from "../../src/libraries/ChainlinkPriceReference.sol";
import {VaultTypes} from "../../src/libraries/VaultTypes.sol";

contract ForkPriceReferenceHarness {
    function quote(
        uint256 amountIn,
        VaultTypes.AssetConfig memory inputAsset,
        uint256 inputMaxAge,
        VaultTypes.AssetConfig memory outputAsset,
        uint256 outputMaxAge
    ) external view returns (uint256) {
        return ChainlinkPriceReference.quote(amountIn, inputAsset, inputMaxAge, outputAsset, outputMaxAge);
    }
}

contract MarketRegistryV1ForkTest is Test {
    string private constant MANIFEST_PATH = "registry/base-mainnet-v1.candidate.json";

    function testForkCandidateManifestBuildsRegistryAndMatchesPriceVectors() public {
        string memory rpcUrl = vm.envOr("BASE_FORK_RPC_URL", string(""));
        if (bytes(rpcUrl).length == 0) {
            vm.skip(true);
        }

        // forge-lint: disable-next-line(unsafe-cheatcode)
        string memory manifest = vm.readFile(MANIFEST_PATH);
        uint256 verificationBlock = vm.parseJsonUint(manifest, ".verificationBlock.number");
        vm.createSelectFork(rpcUrl, verificationBlock);

        string[] memory assetKeys = vm.parseJsonKeys(manifest, ".tokens");
        VaultTypes.AssetConfig[] memory assets = new VaultTypes.AssetConfig[](assetKeys.length);
        for (uint256 i = 0; i < assets.length; ++i) {
            assets[i] = _readAsset(manifest, assetKeys[i]);
        }

        VaultTypes.MarketConfig[] memory markets =
            new VaultTypes.MarketConfig[](vm.parseJsonUint(manifest, ".marketCount"));
        for (uint256 i = 0; i < markets.length; ++i) {
            markets[i] = _readMarket(manifest, i);
        }

        string memory accountingAssetKey = vm.parseJsonString(manifest, ".accountingAsset");
        bytes32 accountingAssetId = keccak256(bytes(accountingAssetKey));
        address accountingToken =
            vm.parseJsonAddress(manifest, string.concat(".tokens.", accountingAssetKey, ".address"));
        MarketRegistryV1 registry = new MarketRegistryV1(
            vm.parseJsonUint(manifest, ".chainId"),
            vm.parseJsonBytes32(manifest, ".registryIdHash"),
            accountingAssetId,
            assets,
            markets
        );

        assertEq(registry.assetCount(), assets.length);
        assertEq(registry.accountingAssetId(), accountingAssetId);
        assertEq(registry.marketCount(), markets.length);
        assertEq(registry.accountingToken(), accountingToken);
        for (uint256 i = 0; i < markets.length; ++i) {
            assertEq(registry.marketIdAt(i), markets[i].marketId);
        }

        _assertPriceVectors(manifest, registry, markets, accountingAssetKey);
    }

    function _readAsset(string memory manifest, string memory symbol)
        private
        pure
        returns (VaultTypes.AssetConfig memory)
    {
        string memory tokenRoot = string.concat(".tokens.", symbol);
        string memory feedRoot = string.concat(".priceFeeds.", symbol);
        return VaultTypes.AssetConfig({
            assetId: keccak256(bytes(symbol)),
            token: vm.parseJsonAddress(manifest, string.concat(tokenRoot, ".address")),
            usdPriceFeed: vm.parseJsonAddress(manifest, string.concat(feedRoot, ".proxy.address")),
            tokenDecimals: uint8(vm.parseJsonUint(manifest, string.concat(tokenRoot, ".decimals"))),
            priceFeedDecimals: uint8(vm.parseJsonUint(manifest, string.concat(feedRoot, ".decimals"))),
            priceFeedVersion: vm.parseJsonUint(manifest, string.concat(feedRoot, ".version")),
            tokenCodeHash: vm.parseJsonBytes32(manifest, string.concat(tokenRoot, ".codeHash")),
            priceFeedCodeHash: vm.parseJsonBytes32(manifest, string.concat(feedRoot, ".proxy.codeHash")),
            priceFeedDescriptionHash: vm.parseJsonBytes32(manifest, string.concat(feedRoot, ".descriptionHash"))
        });
    }

    function _readMarket(string memory manifest, uint256 index) private pure returns (VaultTypes.MarketConfig memory) {
        string memory root = string.concat(".markets[", vm.toString(index), "]");
        string memory targetSymbol = vm.parseJsonString(manifest, string.concat(root, ".target"));
        string memory deployment = vm.parseJsonString(manifest, string.concat(root, ".deployment"));
        string memory deploymentRoot = string.concat(".deployments.", deployment);

        return VaultTypes.MarketConfig({
            marketId: vm.parseJsonBytes32(manifest, string.concat(root, ".marketIdHash")),
            targetAssetId: keccak256(bytes(targetSymbol)),
            factory: vm.parseJsonAddress(manifest, string.concat(deploymentRoot, ".factory.address")),
            pool: vm.parseJsonAddress(manifest, string.concat(root, ".pool.address")),
            router: vm.parseJsonAddress(manifest, string.concat(deploymentRoot, ".router.address")),
            tickSpacing: int24(vm.parseJsonInt(manifest, string.concat(root, ".pool.tickSpacing"))),
            factoryCodeHash: vm.parseJsonBytes32(manifest, string.concat(deploymentRoot, ".factory.codeHash")),
            poolCodeHash: vm.parseJsonBytes32(manifest, string.concat(root, ".pool.codeHash")),
            routerCodeHash: vm.parseJsonBytes32(manifest, string.concat(deploymentRoot, ".router.codeHash"))
        });
    }

    function _assertPriceVectors(
        string memory manifest,
        MarketRegistryV1 registry,
        VaultTypes.MarketConfig[] memory markets,
        string memory accountingAssetKey
    ) private {
        ForkPriceReferenceHarness priceReference = new ForkPriceReferenceHarness();
        VaultTypes.AssetConfig memory accountingAsset = registry.getAsset(registry.accountingAssetId());
        uint256 accountingMaxAge =
            vm.parseJsonUint(manifest, string.concat(".priceFeeds.", accountingAssetKey, ".catalogHeartbeatSeconds"));

        for (uint256 i = 0; i < markets.length; ++i) {
            string memory marketRoot = string.concat(".markets[", vm.toString(i), "]");
            string memory targetSymbol = vm.parseJsonString(manifest, string.concat(marketRoot, ".target"));
            uint256 targetMaxAge =
                vm.parseJsonUint(manifest, string.concat(".priceFeeds.", targetSymbol, ".catalogHeartbeatSeconds"));
            VaultTypes.AssetConfig memory targetAsset = registry.getAsset(markets[i].targetAssetId);

            uint256 targetAmount =
                priceReference.quote(1_000e6, accountingAsset, accountingMaxAge, targetAsset, targetMaxAge);
            assertEq(targetAmount, _expectedTargetAmount(markets[i].targetAssetId));
            assertEq(
                priceReference.quote(targetAmount, targetAsset, targetMaxAge, accountingAsset, accountingMaxAge),
                _expectedReturnedUsdc(markets[i].targetAssetId)
            );
        }
    }

    function _expectedTargetAmount(bytes32 targetAssetId) private pure returns (uint256) {
        if (targetAssetId == keccak256("cbBTC")) return 1_590_339;
        if (targetAssetId == keccak256("WETH")) return 532_614_847_622_860_256;
        if (targetAssetId == keccak256("AERO")) return 2_499_145_372_505_486_874_728;
        if (targetAssetId == keccak256("EURC")) return 864_805_380;
        revert("unknown target");
    }

    function _expectedReturnedUsdc(bytes32 targetAssetId) private pure returns (uint256) {
        if (targetAssetId == keccak256("cbBTC")) return 999_999_529;
        if (
            targetAssetId == keccak256("WETH") || targetAssetId == keccak256("AERO")
                || targetAssetId == keccak256("EURC")
        ) return 999_999_999;
        revert("unknown target");
    }
}
