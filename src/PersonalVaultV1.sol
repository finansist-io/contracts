// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {IEntryGuard} from "./interfaces/IEntryGuard.sol";
import {IMarketRegistryV1} from "./interfaces/IMarketRegistryV1.sol";
import {VaultAccounting} from "./libraries/VaultAccounting.sol";
import {VaultTypes} from "./libraries/VaultTypes.sol";

contract PersonalVaultV1 is Initializable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint16 public constant MAX_AUTHOR_FEE_BPS = 800;
    uint16 public constant MAX_PLATFORM_FEE_BPS = 300;
    uint16 public constant MAX_SLIPPAGE_BPS = 1_000;

    error Unauthorized();
    error ZeroAddress();
    error InvalidAmount();
    error InvalidMandate();
    error NoActiveMandate();
    error InsufficientOwnerBalance(uint256 available, uint256 requested);
    error UnexpectedTokenDelta(uint256 expected, uint256 actual);
    error Insolvent();
    error NoSurplus();

    address public factory;
    address public owner;
    address public accountingToken;
    address public targetToken;
    address public registry;
    address public entryGuard;
    bytes32 public strategyLineage;
    bytes32 public marketId;

    VaultTypes.Mandate public mandate;
    uint64 public mandateVersion;
    bool public mandateActive;

    uint256 public accountedOwnerUsdc;
    uint256 public highWaterMark;

    event VaultInitialized(
        address indexed factory,
        address indexed owner,
        bytes32 indexed strategyLineage,
        bytes32 marketId,
        address targetToken,
        address registry
    );
    event Deposited(uint256 amount, uint256 ownerUsdc, uint256 highWaterMark);
    event Withdrawn(address indexed recipient, uint256 amount, uint256 ownerUsdc, uint256 highWaterMark);
    event MandateActivated(
        uint64 indexed version, bytes32 indexed strategyVersionHash, address indexed executor, uint64 expiresAt
    );
    event MandateRevoked(uint64 indexed version);
    event ExecutorReplaced(uint64 indexed version, address indexed previousExecutor, address indexed nextExecutor);
    event ExcessRecovered(address indexed token, uint256 amount);

    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address owner_,
        bytes32 strategyLineage_,
        bytes32 marketId_,
        address registry_,
        address entryGuard_
    ) external initializer {
        if (
            owner_ == address(0) || strategyLineage_ == bytes32(0) || marketId_ == bytes32(0) || registry_ == address(0)
                || entryGuard_ == address(0) || registry_.code.length == 0 || entryGuard_.code.length == 0
        ) revert ZeroAddress();

        // Interface view calls use STATICCALL, so registry lookups cannot re-enter with state changes.
        VaultTypes.MarketConfig memory market = IMarketRegistryV1(registry_).getMarket(marketId_);
        VaultTypes.AssetConfig memory targetAsset = IMarketRegistryV1(registry_).getAsset(market.targetAssetId);
        address accountingToken_ = IMarketRegistryV1(registry_).accountingToken();
        if (accountingToken_ == address(0) || accountingToken_.code.length == 0) revert ZeroAddress();

        factory = msg.sender;
        owner = owner_;
        accountingToken = accountingToken_;
        targetToken = targetAsset.token;
        registry = registry_;
        entryGuard = entryGuard_;
        strategyLineage = strategyLineage_;
        marketId = marketId_;
        emit VaultInitialized(msg.sender, owner_, strategyLineage_, marketId_, targetAsset.token, registry_);
    }

    function deposit(uint256 amount) external nonReentrant onlyOwner {
        if (amount == 0) revert InvalidAmount();

        IERC20 token = IERC20(accountingToken);
        // Exact received-value accounting needs post-transfer balance reads; nonReentrant guards the interaction.
        uint256 beforeBalance = token.balanceOf(address(this));
        token.safeTransferFrom(owner, address(this), amount);
        uint256 received = token.balanceOf(address(this)) - beforeBalance;
        if (received != amount) revert UnexpectedTokenDelta(amount, received);

        accountedOwnerUsdc += received;
        highWaterMark = VaultAccounting.afterDeposit(highWaterMark, received);
        _assertSolvent();
        emit Deposited(received, accountedOwnerUsdc, highWaterMark);
    }

    function withdrawIdle(uint256 amount, address recipient) external nonReentrant onlyOwner {
        if (amount == 0 || recipient == address(0)) revert InvalidAmount();
        if (amount > accountedOwnerUsdc) revert InsufficientOwnerBalance(accountedOwnerUsdc, amount);

        accountedOwnerUsdc -= amount;
        highWaterMark = VaultAccounting.afterWithdrawal(highWaterMark, amount);
        IERC20(accountingToken).safeTransfer(recipient, amount);
        _assertSolvent();
        emit Withdrawn(recipient, amount, accountedOwnerUsdc, highWaterMark);
    }

    function activateMandate(VaultTypes.Mandate calldata next) external onlyOwner {
        if (
            next.strategyVersionHash == bytes32(0) || next.executor == address(0) || next.maxDeployableUsdc == 0
                || next.maxPerEntryUsdc == 0 || next.maxPerEntryUsdc > next.maxDeployableUsdc
                || next.maxSlippageBps == 0 || next.maxSlippageBps > MAX_SLIPPAGE_BPS
                || next.authorFeeBps > MAX_AUTHOR_FEE_BPS || next.platformFeeBps > MAX_PLATFORM_FEE_BPS
                || next.expiresAt <= block.timestamp
                || (next.authorFeeBps != 0 && next.authorFeeRecipient == address(0))
                || (next.platformFeeBps != 0 && next.platformFeeRecipient == address(0))
        ) revert InvalidMandate();

        mandate = next;
        mandateVersion += 1;
        mandateActive = true;
        emit MandateActivated(mandateVersion, next.strategyVersionHash, next.executor, next.expiresAt);
    }

    function revokeMandate() external onlyOwner {
        if (!mandateActive) revert NoActiveMandate();
        mandateActive = false;
        emit MandateRevoked(mandateVersion);
    }

    function replaceExecutor(address nextExecutor) external onlyOwner {
        if (!mandateActive) revert NoActiveMandate();
        if (nextExecutor == address(0)) revert ZeroAddress();
        address previous = mandate.executor;
        mandate.executor = nextExecutor;
        emit ExecutorReplaced(mandateVersion, previous, nextExecutor);
    }

    function canEnter(uint256 amount) external view returns (bool) {
        if (
            !mandateActive || block.timestamp >= mandate.expiresAt || amount == 0 || amount > accountedOwnerUsdc
                || amount > mandate.maxDeployableUsdc || amount > mandate.maxPerEntryUsdc
        ) return false;
        return IEntryGuard(entryGuard).isEntryAllowed(marketId);
    }

    function accountingSurplus() public view returns (uint256) {
        uint256 balance = IERC20(accountingToken).balanceOf(address(this));
        return balance > accountedOwnerUsdc ? balance - accountedOwnerUsdc : 0;
    }

    function targetSurplus() public view returns (uint256) {
        return IERC20(targetToken).balanceOf(address(this));
    }

    function recoverExcess(address token) external nonReentrant onlyOwner returns (uint256 amount) {
        if (token == address(0)) revert ZeroAddress();

        if (token == accountingToken) {
            amount = accountingSurplus();
        } else if (token == targetToken) {
            amount = targetSurplus();
        } else {
            amount = IERC20(token).balanceOf(address(this));
        }
        if (amount == 0) revert NoSurplus();

        IERC20(token).safeTransfer(owner, amount);
        _assertSolvent();
        emit ExcessRecovered(token, amount);
    }

    function _assertSolvent() private view {
        if (IERC20(accountingToken).balanceOf(address(this)) < accountedOwnerUsdc) {
            revert Insolvent();
        }
    }

    function _checkOwner() private view {
        if (msg.sender != owner) revert Unauthorized();
    }
}
