// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

library VaultAccounting {
    function afterDeposit(uint256 highWaterMark, uint256 amount) internal pure returns (uint256) {
        return highWaterMark + amount;
    }

    function afterWithdrawal(uint256 highWaterMark, uint256 amount) internal pure returns (uint256) {
        return amount >= highWaterMark ? 0 : highWaterMark - amount;
    }
}
