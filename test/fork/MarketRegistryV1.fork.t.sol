// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {Test} from "forge-std/Test.sol";

import {MarketRegistryV1} from "../../src/MarketRegistryV1.sol";
import {VaultTypes} from "../../src/libraries/VaultTypes.sol";

contract MarketRegistryV1ForkTest is Test {
    string private constant MANIFEST_PATH = "registry/base-mainnet-v1.candidate.json";

    function testForkCandidateManifestBuildsRegistry() public {
        string memory rpcUrl = vm.envOr("BASE_FORK_RPC_URL", string(""));
        if (bytes(rpcUrl).length == 0) {
            vm.skip(true);
        }

        // forge-lint: disable-next-line(unsafe-cheatcode)
        string memory manifest = vm.readFile(MANIFEST_PATH);
        uint256 verificationBlock = vm.parseJsonUint(manifest, ".verificationBlock.number");
        vm.createSelectFork(rpcUrl, verificationBlock);

        VaultTypes.MarketConfig[] memory markets =
            new VaultTypes.MarketConfig[](vm.parseJsonUint(manifest, ".marketCount"));
        for (uint256 i = 0; i < markets.length; ++i) {
            markets[i] = _readMarket(manifest, i);
        }

        address accountingToken = vm.parseJsonAddress(manifest, ".tokens.USDC.address");
        MarketRegistryV1 registry = new MarketRegistryV1(
            vm.parseJsonUint(manifest, ".chainId"),
            vm.parseJsonBytes32(manifest, ".registryIdHash"),
            accountingToken,
            uint8(vm.parseJsonUint(manifest, ".tokens.USDC.decimals")),
            vm.parseJsonBytes32(manifest, ".tokens.USDC.codeHash"),
            markets
        );

        assertEq(registry.marketCount(), markets.length);
        assertEq(registry.accountingToken(), accountingToken);
        for (uint256 i = 0; i < markets.length; ++i) {
            assertEq(registry.marketIdAt(i), markets[i].marketId);
        }
    }

    function _readMarket(string memory manifest, uint256 index) private pure returns (VaultTypes.MarketConfig memory) {
        string memory root = string.concat(".markets[", vm.toString(index), "]");
        string memory targetSymbol = vm.parseJsonString(manifest, string.concat(root, ".target"));
        string memory deployment = vm.parseJsonString(manifest, string.concat(root, ".deployment"));
        string memory targetRoot = string.concat(".tokens.", targetSymbol);
        string memory deploymentRoot = string.concat(".deployments.", deployment);

        return VaultTypes.MarketConfig({
            marketId: vm.parseJsonBytes32(manifest, string.concat(root, ".marketIdHash")),
            targetToken: vm.parseJsonAddress(manifest, string.concat(targetRoot, ".address")),
            targetTokenDecimals: uint8(vm.parseJsonUint(manifest, string.concat(targetRoot, ".decimals"))),
            factory: vm.parseJsonAddress(manifest, string.concat(deploymentRoot, ".factory.address")),
            pool: vm.parseJsonAddress(manifest, string.concat(root, ".pool.address")),
            router: vm.parseJsonAddress(manifest, string.concat(deploymentRoot, ".router.address")),
            tickSpacing: int24(vm.parseJsonInt(manifest, string.concat(root, ".pool.tickSpacing"))),
            targetTokenCodeHash: vm.parseJsonBytes32(manifest, string.concat(targetRoot, ".codeHash")),
            factoryCodeHash: vm.parseJsonBytes32(manifest, string.concat(deploymentRoot, ".factory.codeHash")),
            poolCodeHash: vm.parseJsonBytes32(manifest, string.concat(root, ".pool.codeHash")),
            routerCodeHash: vm.parseJsonBytes32(manifest, string.concat(deploymentRoot, ".router.codeHash"))
        });
    }
}
