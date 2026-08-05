// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {PersonalVaultV1} from "../../src/PersonalVaultV1.sol";
import {MarketRegistryV1} from "../../src/MarketRegistryV1.sol";
import {VaultFactoryV1} from "../../src/VaultFactoryV1.sol";
import {VaultTypes} from "../../src/libraries/VaultTypes.sol";
import {FeeToken, MockToken, TestSetup} from "../helpers/TestSetup.sol";

contract PersonalVaultV1Test is TestSetup {
    function testDepositAndWithdrawalTrackOwnerMoneyAndHighWaterMark() public {
        depositAsOwner(1_000e6);

        assertEq(vault.accountedOwnerUsdc(), 1_000e6);
        assertEq(vault.highWaterMark(), 1_000e6);
        assertEq(usdc.balanceOf(address(vault)), 1_000e6);

        address recipient = makeAddr("recipient");
        vm.prank(owner);
        vault.withdrawIdle(250e6, recipient);

        assertEq(vault.accountedOwnerUsdc(), 750e6);
        assertEq(vault.highWaterMark(), 750e6);
        assertEq(usdc.balanceOf(recipient), 250e6);
    }

    function testDonationIsSurplusNotOwnerAccounting() public {
        depositAsOwner(1_000e6);
        usdc.mint(address(vault), 100e6);

        assertEq(vault.accountedOwnerUsdc(), 1_000e6);
        assertEq(vault.highWaterMark(), 1_000e6);
        assertEq(vault.accountingSurplus(), 100e6);

        uint256 ownerBefore = usdc.balanceOf(owner);
        vm.prank(owner);
        uint256 recovered = vault.recoverExcess(address(usdc));

        assertEq(recovered, 100e6);
        assertEq(usdc.balanceOf(owner) - ownerBefore, 100e6);
        assertEq(vault.accountedOwnerUsdc(), 1_000e6);
    }

    function testTargetDonationCannotCreatePosition() public {
        target.mint(address(vault), 2 ether);

        assertEq(vault.targetSurplus(), 2 ether);

        vm.prank(owner);
        vault.recoverExcess(address(target));
        assertEq(target.balanceOf(owner), 2 ether);
    }

    function testUnrelatedTokenCanBeRecoveredWithoutChangingAccounting() public {
        MockToken unrelated = new MockToken("Unrelated", "OTHER", 18);
        unrelated.mint(address(vault), 3 ether);

        vm.prank(owner);
        assertEq(vault.recoverExcess(address(unrelated)), 3 ether);
        assertEq(unrelated.balanceOf(owner), 3 ether);
        assertEq(vault.accountedOwnerUsdc(), 0);
    }

    function testRecoverExcessRejectsEmptyBalance() public {
        vm.prank(owner);
        vm.expectRevert(PersonalVaultV1.NoSurplus.selector);
        vault.recoverExcess(address(usdc));
    }

    function testMandateIsOwnerAuthorizedAndGuarded() public {
        depositAsOwner(2_000e6);
        VaultTypes.Mandate memory next = validMandate();

        vm.prank(owner);
        vault.activateMandate(next);

        assertTrue(vault.mandateActive());
        assertEq(vault.mandateVersion(), 1);
        assertTrue(vault.canEnter(1_000e6));
        assertFalse(vault.canEnter(1_001e6));

        vm.prank(guardOwner);
        guard.pauseMarket(MARKET_ID);
        assertFalse(vault.canEnter(1_000e6));

        vm.prank(owner);
        vault.revokeMandate();
        assertFalse(vault.mandateActive());
    }

    function testOwnerCanReplaceExecutorWithoutExpandingMandate() public {
        VaultTypes.Mandate memory next = validMandate();
        vm.prank(owner);
        vault.activateMandate(next);

        address replacement = makeAddr("replacement");
        vm.prank(owner);
        vault.replaceExecutor(replacement);

        (bytes32 strategyHash, address storedExecutor,,,,,,,,) = vault.mandate();
        assertEq(strategyHash, next.strategyVersionHash);
        assertEq(storedExecutor, replacement);
    }

    function testNonOwnerCannotMoveFundsOrAuthorizeMandate() public {
        address stranger = makeAddr("stranger");
        vm.prank(stranger);
        vm.expectRevert(PersonalVaultV1.Unauthorized.selector);
        vault.withdrawIdle(1, stranger);

        VaultTypes.Mandate memory next = validMandate();
        vm.prank(stranger);
        vm.expectRevert(PersonalVaultV1.Unauthorized.selector);
        vault.activateMandate(next);
    }

    function testRejectsFeesOutsideLaunchCaps() public {
        VaultTypes.Mandate memory next = validMandate();
        next.authorFeeBps = vault.MAX_AUTHOR_FEE_BPS() + 1;

        vm.prank(owner);
        vm.expectRevert(PersonalVaultV1.InvalidMandate.selector);
        vault.activateMandate(next);
    }

    function testRejectsInvalidMandateLimitsAndRecipients() public {
        VaultTypes.Mandate memory next = validMandate();
        next.maxPerEntryUsdc = next.maxDeployableUsdc + 1;
        _expectInvalidMandate(next);

        next = validMandate();
        next.maxSlippageBps = vault.MAX_SLIPPAGE_BPS() + 1;
        _expectInvalidMandate(next);

        next = validMandate();
        next.expiresAt = uint64(block.timestamp);
        _expectInvalidMandate(next);

        next = validMandate();
        next.authorFeeRecipient = address(0);
        _expectInvalidMandate(next);
    }

    function testInactiveMandateCannotBeRevokedOrEdited() public {
        vm.startPrank(owner);
        vm.expectRevert(PersonalVaultV1.NoActiveMandate.selector);
        vault.revokeMandate();
        vm.expectRevert(PersonalVaultV1.NoActiveMandate.selector);
        vault.replaceExecutor(makeAddr("replacement"));
        vm.stopPrank();
    }

    function testWithdrawalRejectsInvalidOrUnavailableAmount() public {
        depositAsOwner(100e6);

        vm.startPrank(owner);
        vm.expectRevert(PersonalVaultV1.InvalidAmount.selector);
        vault.withdrawIdle(0, owner);
        vm.expectRevert(PersonalVaultV1.InvalidAmount.selector);
        vault.withdrawIdle(1, address(0));
        vm.expectRevert(
            abi.encodeWithSelector(PersonalVaultV1.InsufficientOwnerBalance.selector, uint256(100e6), uint256(101e6))
        );
        vault.withdrawIdle(101e6, owner);
        vm.stopPrank();
    }

    function testDepositRejectsFeeOnTransferAccountingToken() public {
        FeeToken feeToken = new FeeToken();
        VaultTypes.MarketConfig[] memory markets = new VaultTypes.MarketConfig[](1);
        markets[0] = marketConfig(MARKET_ID);
        MarketRegistryV1 feeRegistry =
            new MarketRegistryV1(BASE_CHAIN_ID, keccak256("fee-token-registry"), address(feeToken), markets);
        VaultFactoryV1 feeFactory = new VaultFactoryV1(address(feeRegistry), address(guard));
        PersonalVaultV1 feeVault = PersonalVaultV1(feeFactory.createVault(owner, LINEAGE, MARKET_ID));

        feeToken.mint(owner, 100e18);
        vm.startPrank(owner);
        feeToken.approve(address(feeVault), 100e18);
        vm.expectRevert(
            abi.encodeWithSelector(PersonalVaultV1.UnexpectedTokenDelta.selector, uint256(100e18), uint256(100e18 - 1))
        );
        feeVault.deposit(100e18);
        vm.stopPrank();
    }

    function testExpiredMandateCannotEnter() public {
        depositAsOwner(2_000e6);
        VaultTypes.Mandate memory next = validMandate();
        vm.prank(owner);
        vault.activateMandate(next);

        vm.warp(next.expiresAt);
        assertFalse(vault.canEnter(1_000e6));
    }

    function _expectInvalidMandate(VaultTypes.Mandate memory next) private {
        vm.prank(owner);
        vm.expectRevert(PersonalVaultV1.InvalidMandate.selector);
        vault.activateMandate(next);
    }
}
