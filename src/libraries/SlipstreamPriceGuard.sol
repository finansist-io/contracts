// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

library SlipstreamPriceGuard {
    uint256 internal constant BPS_DENOMINATOR = 10_000;
    uint160 internal constant MIN_SQRT_RATIO = 4_295_128_739;
    uint160 internal constant MAX_SQRT_RATIO = 1_461_446_703_485_210_103_287_273_052_203_988_822_378_723_970_342;

    uint256 private constant Q128 = 1 << 128;
    uint256 private constant Q192 = 1 << 192;
    uint256 private constant Q32 = 1 << 32;
    uint8 private constant MAX_TOKEN_DECIMALS = 18;

    error InvalidSlippageBps(uint16 slippageBps);
    error InvalidReferencePrice();
    error UnsupportedTokenDecimals(uint8 decimals);
    error PriceRatioOverflow();
    error SqrtPriceOutOfRange(uint256 sqrtPriceX96);
    error CurrentPriceOutsideLimit(uint160 currentSqrtPriceX96, uint160 limitSqrtPriceX96, bool zeroForOne);

    function minimumAmountOut(uint256 referenceAmountOut, uint16 maxSlippageBps) internal pure returns (uint256) {
        uint256 remainingBps = _remainingBps(maxSlippageBps);
        return Math.mulDiv(referenceAmountOut, remainingBps, BPS_DENOMINATOR, Math.Rounding.Ceil);
    }

    function sqrtPriceLimitX96(
        uint256 token0Price18,
        uint8 token0Decimals,
        uint256 token1Price18,
        uint8 token1Decimals,
        uint16 maxSlippageBps,
        bool zeroForOne
    ) internal pure returns (uint160) {
        if (token0Price18 == 0 || token1Price18 == 0) revert InvalidReferencePrice();
        uint256 remainingBps = _remainingBps(maxSlippageBps);

        uint256 numerator = _checkedMul(token0Price18, _tokenScale(token1Decimals));
        uint256 denominator = _checkedMul(token1Price18, _tokenScale(token0Decimals));
        Math.Rounding rounding;
        if (zeroForOne) {
            numerator = _checkedMul(numerator, remainingBps);
            denominator = _checkedMul(denominator, BPS_DENOMINATOR);
            rounding = Math.Rounding.Ceil;
        } else {
            numerator = _checkedMul(numerator, BPS_DENOMINATOR);
            denominator = _checkedMul(denominator, remainingBps);
            rounding = Math.Rounding.Floor;
        }

        uint256 sqrtPrice = _sqrtRatioX96(numerator, denominator, rounding);
        if (sqrtPrice <= MIN_SQRT_RATIO || sqrtPrice >= MAX_SQRT_RATIO) {
            revert SqrtPriceOutOfRange(sqrtPrice);
        }
        // Bounded above by Slipstream's uint160 MAX_SQRT_RATIO.
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint160(sqrtPrice);
    }

    function requireCurrentPriceWithinLimit(uint160 currentSqrtPriceX96, uint160 limitSqrtPriceX96, bool zeroForOne)
        internal
        pure
    {
        if (
            (zeroForOne && currentSqrtPriceX96 <= limitSqrtPriceX96)
                || (!zeroForOne && currentSqrtPriceX96 >= limitSqrtPriceX96)
        ) revert CurrentPriceOutsideLimit(currentSqrtPriceX96, limitSqrtPriceX96, zeroForOne);
    }

    function _sqrtRatioX96(uint256 numerator, uint256 denominator, Math.Rounding rounding)
        private
        pure
        returns (uint256)
    {
        if (numerator < denominator) {
            uint256 ratioX192 = Math.mulDiv(numerator, Q192, denominator, rounding);
            return Math.sqrt(ratioX192, rounding);
        }

        if (numerator / denominator >= Q128) revert PriceRatioOverflow();
        uint256 ratioX128 = Math.mulDiv(numerator, Q128, denominator, rounding);
        return _checkedMul(Math.sqrt(ratioX128, rounding), Q32);
    }

    function _remainingBps(uint16 maxSlippageBps) private pure returns (uint256) {
        if (maxSlippageBps >= BPS_DENOMINATOR) revert InvalidSlippageBps(maxSlippageBps);
        return BPS_DENOMINATOR - maxSlippageBps;
    }

    function _tokenScale(uint8 decimals) private pure returns (uint256) {
        if (decimals > MAX_TOKEN_DECIMALS) revert UnsupportedTokenDecimals(decimals);
        return 10 ** decimals;
    }

    function _checkedMul(uint256 left, uint256 right) private pure returns (uint256 product) {
        bool success;
        (success, product) = Math.tryMul(left, right);
        if (!success) revert PriceRatioOverflow();
    }
}
