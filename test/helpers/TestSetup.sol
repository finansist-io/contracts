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

contract MockEndpoint {}

abstract contract TestSetup is Test {
    uint256 internal constant BASE_CHAIN_ID = 8453;
    bytes32 internal constant REGISTRY_ID = keccak256("base-mainnet-v1-test");
    bytes32 internal constant MARKET_ID = keccak256("weth-usdc-slipstream-test");
    bytes32 internal constant LINEAGE = keccak256("strategy-lineage");

    address internal owner = makeAddr("owner");
    address internal guardOwner = makeAddr("guardOwner");
    address internal executor = makeAddr("executor");
    address internal author = makeAddr("author");
    address internal platform = makeAddr("platform");

    MockToken internal usdc;
    MockToken internal target;
    MockEndpoint internal poolFactory;
    MockEndpoint internal pool;
    MockEndpoint internal router;
    MockEndpoint internal quoter;
    EntryGuard internal guard;
    MarketRegistryV1 internal registry;
    VaultFactoryV1 internal vaultFactory;
    PersonalVaultV1 internal vault;

    function setUp() public virtual {
        vm.chainId(BASE_CHAIN_ID);
        usdc = new MockToken("USD Coin", "USDC", 6);
        target = new MockToken("Wrapped Ether", "WETH", 18);
        poolFactory = new MockEndpoint();
        pool = new MockEndpoint();
        router = new MockEndpoint();
        quoter = new MockEndpoint();
        guard = new EntryGuard(guardOwner);

        VaultTypes.MarketConfig[] memory markets = new VaultTypes.MarketConfig[](1);
        markets[0] = marketConfig(MARKET_ID);
        registry = new MarketRegistryV1(BASE_CHAIN_ID, REGISTRY_ID, address(usdc), markets);
        vaultFactory = new VaultFactoryV1(address(registry), address(guard));
        vault = PersonalVaultV1(vaultFactory.createVault(owner, LINEAGE, MARKET_ID));
    }

    function marketConfig(bytes32 marketId) internal view returns (VaultTypes.MarketConfig memory) {
        return VaultTypes.MarketConfig({
            marketId: marketId,
            targetToken: address(target),
            factory: address(poolFactory),
            pool: address(pool),
            router: address(router),
            quoter: address(quoter),
            tickSpacing: 100,
            swapSelector: bytes4(keccak256("exactInputSingle(bytes)")),
            factoryCodeHash: address(poolFactory).codehash,
            poolCodeHash: address(pool).codehash,
            routerCodeHash: address(router).codehash,
            quoterCodeHash: address(quoter).codehash
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

    function depositAsOwner(uint256 amount) internal {
        usdc.mint(owner, amount);
        vm.startPrank(owner);
        usdc.approve(address(vault), amount);
        vault.deposit(amount);
        vm.stopPrank();
    }
}
