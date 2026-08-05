// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {Test} from "forge-std/Test.sol";

import {PersonalVaultV1} from "../../src/PersonalVaultV1.sol";
import {MockToken, TestSetup} from "../helpers/TestSetup.sol";

contract VaultCustodyHandler is Test {
    MockToken public immutable USDC;
    PersonalVaultV1 public immutable VAULT;
    address public immutable OWNER;

    constructor(MockToken usdc_, PersonalVaultV1 vault_, address owner_) {
        USDC = usdc_;
        VAULT = vault_;
        OWNER = owner_;
        vm.prank(owner_);
        usdc_.approve(address(vault_), type(uint256).max);
    }

    function deposit(uint96 rawAmount) external {
        uint256 amount = bound(uint256(rawAmount), 1, 1_000_000e6);
        USDC.mint(OWNER, amount);
        vm.prank(OWNER);
        VAULT.deposit(amount);
    }

    function withdraw(uint96 rawAmount) external {
        uint256 available = VAULT.accountedOwnerUsdc();
        if (available == 0) return;
        uint256 amount = bound(uint256(rawAmount), 1, available);
        vm.prank(OWNER);
        VAULT.withdrawIdle(amount, OWNER);
    }

    function donate(uint96 rawAmount) external {
        uint256 amount = bound(uint256(rawAmount), 1, 1_000_000e6);
        USDC.mint(address(VAULT), amount);
    }

    function recoverDonation() external {
        if (VAULT.accountingSurplus() == 0) return;
        vm.prank(OWNER);
        VAULT.recoverExcess(address(USDC));
    }
}

contract VaultCustodyInvariantTest is TestSetup {
    VaultCustodyHandler private handler;

    function setUp() public override {
        super.setUp();
        handler = new VaultCustodyHandler(usdc, vault, owner);
        targetContract(address(handler));
    }

    function invariantAccountedUsdcIsAlwaysBacked() public view {
        assertGe(usdc.balanceOf(address(vault)), vault.accountedOwnerUsdc());
    }

    function invariantFlowAdjustedHighWaterMarkMatchesOwnerAccounting() public view {
        assertEq(vault.highWaterMark(), vault.accountedOwnerUsdc());
    }
}
