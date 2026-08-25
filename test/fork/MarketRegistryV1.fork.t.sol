// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {Test} from "forge-std/Test.sol";

import {MarketRegistryV1} from "../../src/MarketRegistryV1.sol";
import {ChainlinkPriceReference} from "../../src/libraries/ChainlinkPriceReference.sol";
import {ChainlinkSequencerGuard} from "../../src/libraries/ChainlinkSequencerGuard.sol";
import {SlipstreamPriceGuard} from "../../src/libraries/SlipstreamPriceGuard.sol";
import {VaultTypes} from "../../src/libraries/VaultTypes.sol";

interface ISlipstreamPoolState {
    function slot0()
        external
        view
        returns (
            uint160 sqrtPriceX96,
            int24 tick,
            uint16 observationIndex,
            uint16 observationCardinality,
            uint16 observationCardinalityNext,
            bool unlocked
        );
}

contract ForkProtectionHarness {
    function quote(
        uint256 amountIn,
        VaultTypes.AssetConfig memory inputAsset,
        VaultTypes.AssetConfig memory outputAsset
    ) external view returns (uint256) {
        return ChainlinkPriceReference.quote(amountIn, inputAsset, outputAsset);
    }

    function requireSequencerUp(address feed, uint256 gracePeriod) external view {
        ChainlinkSequencerGuard.requireUp(feed, gracePeriod);
    }

    function sqrtPriceLimitX96(
        VaultTypes.AssetConfig memory token0,
        VaultTypes.AssetConfig memory token1,
        uint16 maxSlippageBps,
        bool zeroForOne
    ) external view returns (uint160) {
        return SlipstreamPriceGuard.sqrtPriceLimitX96(
            ChainlinkPriceReference.readNormalizedPrice(token0),
            token0.tokenDecimals,
            ChainlinkPriceReference.readNormalizedPrice(token1),
            token1.tokenDecimals,
            maxSlippageBps,
            zeroForOne
        );
    }

    function requireCurrentPriceWithinLimit(uint160 current, uint160 limit, bool zeroForOne) external pure {
        SlipstreamPriceGuard.requireCurrentPriceWithinLimit(current, limit, zeroForOne);
    }
}

contract MarketRegistryV1ForkTest is Test {
    string private constant MANIFEST_PATH = "registry/base-mainnet-v1.candidate.json";
    uint16 private constant VECTOR_SLIPPAGE_BPS = 100;
    uint256 private constant VECTOR_SEQUENCER_GRACE = 3_600;

    function testForkCandidateManifestBuildsRegistryAndMatchesProtectionVectors() public {
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

        _assertPriceVectors(manifest, registry, markets);
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
            priceMaxAge: uint32(vm.parseJsonUint(manifest, string.concat(feedRoot, ".maxAgeSeconds"))),
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
        VaultTypes.MarketConfig[] memory markets
    ) private {
        ForkProtectionHarness protection = new ForkProtectionHarness();
        protection.requireSequencerUp(
            vm.parseJsonAddress(manifest, ".sequencerUptimeFeed.proxy.address"), VECTOR_SEQUENCER_GRACE
        );
        VaultTypes.AssetConfig memory accountingAsset = registry.getAsset(registry.accountingAssetId());
        for (uint256 i = 0; i < markets.length; ++i) {
            _assertMarketVectors(manifest, registry, accountingAsset, markets[i], protection, i);
        }
    }

    function _assertMarketVectors(
        string memory manifest,
        MarketRegistryV1 registry,
        VaultTypes.AssetConfig memory accountingAsset,
        VaultTypes.MarketConfig memory market,
        ForkProtectionHarness protection,
        uint256 marketIndex
    ) private view {
        VaultTypes.AssetConfig memory targetAsset = registry.getAsset(market.targetAssetId);
        uint256 targetAmount = protection.quote(1_000e6, accountingAsset, targetAsset);
        assertEq(targetAmount, _expectedTargetAmount(market.targetAssetId));
        assertEq(
            protection.quote(targetAmount, targetAsset, accountingAsset), _expectedReturnedUsdc(market.targetAssetId)
        );

        (uint160 currentSqrtPriceX96, int24 currentTick,,,,) = ISlipstreamPoolState(market.pool).slot0();
        string memory marketRoot = string.concat(".markets[", vm.toString(marketIndex), "].mutableSnapshot");
        assertEq(currentSqrtPriceX96, vm.parseJsonUint(manifest, string.concat(marketRoot, ".sqrtPriceX96")));
        assertEq(currentTick, vm.parseJsonInt(manifest, string.concat(marketRoot, ".tick")));

        bool entryZeroForOne = accountingAsset.token < targetAsset.token;
        (VaultTypes.AssetConfig memory token0, VaultTypes.AssetConfig memory token1) =
            entryZeroForOne ? (accountingAsset, targetAsset) : (targetAsset, accountingAsset);
        uint160 entryLimit = protection.sqrtPriceLimitX96(token0, token1, VECTOR_SLIPPAGE_BPS, entryZeroForOne);
        uint160 exitLimit = protection.sqrtPriceLimitX96(token0, token1, VECTOR_SLIPPAGE_BPS, !entryZeroForOne);
        protection.requireCurrentPriceWithinLimit(currentSqrtPriceX96, entryLimit, entryZeroForOne);
        protection.requireCurrentPriceWithinLimit(currentSqrtPriceX96, exitLimit, !entryZeroForOne);
        assertEq(entryLimit, _expectedEntryLimit(market.targetAssetId));
        assertEq(exitLimit, _expectedExitLimit(market.targetAssetId));
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

    function _expectedEntryLimit(bytes32 targetAssetId) private pure returns (uint160) {
        if (targetAssetId == keccak256("cbBTC")) return 3_143_707_547_979_681_810_455_370_500;
        if (targetAssetId == keccak256("WETH")) return 3_450_288_033_517_193_855_727_111;
        if (targetAssetId == keccak256("AERO")) return 124_621_490_350_542_697_062_429_537_865_826_304;
        if (targetAssetId == keccak256("EURC")) return 85_625_435_833_776_395_409_571_184_640;
        revert("unknown target");
    }

    function _expectedExitLimit(bytes32 targetAssetId) private pure returns (uint160) {
        if (targetAssetId == keccak256("cbBTC")) return 3_175_462_169_676_446_273_187_242_928;
        if (targetAssetId == keccak256("WETH")) return 3_415_785_153_182_021_917_169_841;
        if (targetAssetId == keccak256("AERO")) return 125_880_293_283_376_461_679_221_749_302_951_936;
        if (targetAssetId == keccak256("EURC")) return 84_769_181_475_438_631_460_414_685_184;
        revert("unknown target");
    }
}
