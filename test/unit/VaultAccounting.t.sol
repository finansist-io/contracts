// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {Test} from "forge-std/Test.sol";

import {VaultAccounting} from "../../src/libraries/VaultAccounting.sol";

contract VaultAccountingHarness {
    function afterDeposit(uint256 highWaterMark, uint256 amount) external pure returns (uint256) {
        return VaultAccounting.afterDeposit(highWaterMark, amount);
    }

    function afterWithdrawal(uint256 highWaterMark, uint256 amount) external pure returns (uint256) {
        return VaultAccounting.afterWithdrawal(highWaterMark, amount);
    }
}

contract VaultAccountingTest is Test {
    VaultAccountingHarness private accounting;

    function setUp() public {
        accounting = new VaultAccountingHarness();
    }

    function testWithdrawalSaturatesHighWaterMark() public view {
        assertEq(accounting.afterWithdrawal(50e6, 20e6), 30e6);
        assertEq(accounting.afterWithdrawal(50e6, 60e6), 0);
    }

    function testFuzzFlowAdjustments(uint128 highWaterMark, uint128 deposit, uint128 withdrawal) public view {
        uint256 afterDeposit = accounting.afterDeposit(highWaterMark, deposit);
        assertEq(afterDeposit, uint256(highWaterMark) + deposit);
        assertEq(
            accounting.afterWithdrawal(afterDeposit, withdrawal),
            withdrawal >= afterDeposit ? 0 : afterDeposit - withdrawal
        );
    }
}
