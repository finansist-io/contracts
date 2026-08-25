// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {EntryGuard} from "../../src/EntryGuard.sol";
import {MarketRegistryV1} from "../../src/MarketRegistryV1.sol";
import {PersonalVaultV1} from "../../src/PersonalVaultV1.sol";
import {VaultFactoryV1} from "../../src/VaultFactoryV1.sol";
import {VaultTypes} from "../../src/libraries/VaultTypes.sol";

contract MockToken is ERC20 {
    uint8 private immutable _tokenDecimals;

    constructor(string memory name_, string memory symbol_, uint8 decimals_) ERC20(name_, symbol_) {
        _tokenDecimals = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return _tokenDecimals;
    }

    function mint(address recipient, uint256 amount) external {
        _mint(recipient, amount);
    }
}

contract FeeToken is ERC20 {
    constructor() ERC20("Fee Token", "FEE") {}

    function mint(address recipient, uint256 amount) external {
        _mint(recipient, amount);
    }

    function _update(address from, address to, uint256 value) internal override {
        if (from != address(0) && to != address(0) && value != 0) {
            super._update(from, address(0), 1);
            value -= 1;
        }
        super._update(from, to, value);
    }
}

contract MockSlipstreamFactory {
    mapping(bytes32 poolKey => address pool) private _pools;

    function setPool(address tokenA, address tokenB, int24 tickSpacing, address pool) external {
        _pools[_poolKey(tokenA, tokenB, tickSpacing)] = pool;
        _pools[_poolKey(tokenB, tokenA, tickSpacing)] = pool;
    }

    function getPool(address tokenA, address tokenB, int24 tickSpacing) external view returns (address) {
        return _pools[_poolKey(tokenA, tokenB, tickSpacing)];
    }

    function _poolKey(address tokenA, address tokenB, int24 tickSpacing) private pure returns (bytes32) {
        return keccak256(abi.encode(tokenA, tokenB, tickSpacing));
    }
}

contract MockSlipstreamPool {
    address public immutable factory;
    address public immutable token0;
    address public immutable token1;
    int24 public immutable tickSpacing;

    constructor(address factory_, address token0_, address token1_, int24 tickSpacing_) {
        factory = factory_;
        token0 = token0_;
        token1 = token1_;
        tickSpacing = tickSpacing_;
    }
}

contract MockSlipstreamRouter {
    address public immutable factory;

    constructor(address factory_) {
        factory = factory_;
    }
}

contract MockPriceFeed {
    uint8 public immutable decimals;
    uint256 public immutable version;
    string public description;

    constructor(string memory description_, uint8 decimals_, uint256 version_) {
        description = description_;
        decimals = decimals_;
        version = version_;
    }
}

abstract contract TestSetup is Test {
    uint256 internal constant BASE_CHAIN_ID = 8453;
    bytes32 internal constant REGISTRY_ID = keccak256("base-mainnet-v1-test");
    bytes32 internal constant USDC_ASSET_ID = keccak256("USDC");
    bytes32 internal constant TARGET_ASSET_ID = keccak256("WETH");
    bytes32 internal constant MARKET_ID = keccak256("weth-usdc-slipstream-test");
    bytes32 internal constant LINEAGE = keccak256("strategy-lineage");

    address internal owner = makeAddr("owner");
    address internal guardOwner = makeAddr("guardOwner");
    address internal executor = makeAddr("executor");
    address internal author = makeAddr("author");
    address internal platform = makeAddr("platform");

    MockToken internal usdc;
    MockToken internal target;
    MockSlipstreamFactory internal poolFactory;
    MockSlipstreamPool internal pool;
    MockSlipstreamRouter internal router;
    MockPriceFeed internal usdcPriceFeed;
    MockPriceFeed internal targetPriceFeed;
    EntryGuard internal guard;
    MarketRegistryV1 internal registry;
    VaultFactoryV1 internal vaultFactory;
    PersonalVaultV1 internal vault;

    function setUp() public virtual {
        vm.chainId(BASE_CHAIN_ID);
        usdc = new MockToken("USD Coin", "USDC", 6);
        target = new MockToken("Wrapped Ether", "WETH", 18);
        poolFactory = new MockSlipstreamFactory();
        (address token0, address token1) = sortedTokens(address(usdc), address(target));
        pool = new MockSlipstreamPool(address(poolFactory), token0, token1, 100);
        router = new MockSlipstreamRouter(address(poolFactory));
        usdcPriceFeed = new MockPriceFeed("USDC / USD", 8, 6);
        targetPriceFeed = new MockPriceFeed("ETH / USD", 8, 6);
        poolFactory.setPool(address(usdc), address(target), 100, address(pool));
        guard = new EntryGuard(guardOwner);

        VaultTypes.AssetConfig[] memory assets = new VaultTypes.AssetConfig[](2);
        assets[0] = assetConfig(USDC_ASSET_ID, address(usdc), 6, address(usdcPriceFeed), "USDC / USD");
        assets[1] = assetConfig(TARGET_ASSET_ID, address(target), 18, address(targetPriceFeed), "ETH / USD");
        VaultTypes.MarketConfig[] memory markets = new VaultTypes.MarketConfig[](1);
        markets[0] = marketConfig(MARKET_ID);
        registry = new MarketRegistryV1(BASE_CHAIN_ID, REGISTRY_ID, USDC_ASSET_ID, assets, markets);
        vaultFactory = new VaultFactoryV1(address(registry), address(guard));
        vault = PersonalVaultV1(vaultFactory.createVault(owner, LINEAGE, MARKET_ID));
    }

    function marketConfig(bytes32 marketId) internal view returns (VaultTypes.MarketConfig memory) {
        return marketConfigFor(marketId, TARGET_ASSET_ID, address(poolFactory), address(pool), address(router), 100);
    }

    function marketConfigFor(
        bytes32 marketId,
        bytes32 targetAssetId,
        address factory,
        address pool_,
        address router_,
        int24 tickSpacing
    ) internal view returns (VaultTypes.MarketConfig memory) {
        return VaultTypes.MarketConfig({
            marketId: marketId,
            targetAssetId: targetAssetId,
            factory: factory,
            pool: pool_,
            router: router_,
            tickSpacing: tickSpacing,
            factoryCodeHash: factory.codehash,
            poolCodeHash: pool_.codehash,
            routerCodeHash: router_.codehash
        });
    }

    function assetConfig(
        bytes32 assetId,
        address token,
        uint8 tokenDecimals,
        address priceFeed,
        string memory priceFeedDescription
    ) internal view returns (VaultTypes.AssetConfig memory) {
        return VaultTypes.AssetConfig({
            assetId: assetId,
            token: token,
            usdPriceFeed: priceFeed,
            tokenDecimals: tokenDecimals,
            priceFeedDecimals: 8,
            priceMaxAge: 60,
            priceFeedVersion: 6,
            tokenCodeHash: token.codehash,
            priceFeedCodeHash: priceFeed.codehash,
            priceFeedDescriptionHash: keccak256(bytes(priceFeedDescription))
        });
    }

    function validMandate() internal view returns (VaultTypes.Mandate memory) {
        return VaultTypes.Mandate({
            strategyVersionHash: keccak256("strategy-v1"),
            executor: executor,
            authorFeeRecipient: author,
            platformFeeRecipient: platform,
            maxDeployableUsdc: 5_000e6,
            maxPerEntryUsdc: 1_000e6,
            maxSlippageBps: 100,
            authorFeeBps: 500,
            platformFeeBps: 300,
            expiresAt: uint64(block.timestamp + 30 days)
        });
    }

    function sortedTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        return tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
    }

    function depositAsOwner(uint256 amount) internal {
        usdc.mint(owner, amount);
        vm.startPrank(owner);
        usdc.approve(address(vault), amount);
        vault.deposit(amount);
        vm.stopPrank();
    }
}
