// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {Test} from "forge-std/Test.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {SlipstreamPriceGuard} from "../../src/libraries/SlipstreamPriceGuard.sol";

contract SlipstreamPriceGuardHarness {
    function minimumAmountOut(uint256 referenceAmountOut, uint16 maxSlippageBps) external pure returns (uint256) {
        return SlipstreamPriceGuard.minimumAmountOut(referenceAmountOut, maxSlippageBps);
    }

    function sqrtPriceLimitX96(
        uint256 token0Price18,
        uint8 token0Decimals,
        uint256 token1Price18,
        uint8 token1Decimals,
        uint16 maxSlippageBps,
        bool zeroForOne
    ) external pure returns (uint160) {
        return SlipstreamPriceGuard.sqrtPriceLimitX96(
            token0Price18, token0Decimals, token1Price18, token1Decimals, maxSlippageBps, zeroForOne
        );
    }

    function requireCurrentPriceWithinLimit(uint160 current, uint160 limit, bool zeroForOne) external pure {
        SlipstreamPriceGuard.requireCurrentPriceWithinLimit(current, limit, zeroForOne);
    }
}

contract SlipstreamPriceGuardTest is Test {
    uint256 private constant Q192 = 1 << 192;
    uint160 private constant MIN_SQRT_RATIO = 4_295_128_739;
    uint160 private constant MAX_SQRT_RATIO = 1_461_446_703_485_210_103_287_273_052_203_988_822_378_723_970_342;

    SlipstreamPriceGuardHarness private guard;

    function setUp() public {
        guard = new SlipstreamPriceGuardHarness();
    }

    function testRoundsMinimumOutputUp() public view {
        assertEq(guard.minimumAmountOut(101, 100), 100);
        assertEq(guard.minimumAmountOut(100, 100), 99);
    }

    function testUsesReciprocalBoundForOneForZero() public view {
        uint160 lower = guard.sqrtPriceLimitX96(1e18, 6, 2_000e18, 18, 100, true);
        uint160 referenceLimit = guard.sqrtPriceLimitX96(1e18, 6, 2_000e18, 18, 0, true);
        uint160 upper = guard.sqrtPriceLimitX96(1e18, 6, 2_000e18, 18, 100, false);

        assertLt(lower, referenceLimit);
        assertGt(upper, referenceLimit);
    }

    function testRejectsInvalidInputs() public {
        vm.expectRevert(abi.encodeWithSelector(SlipstreamPriceGuard.InvalidSlippageBps.selector, uint16(10_000)));
        guard.minimumAmountOut(1, 10_000);

        vm.expectRevert(SlipstreamPriceGuard.InvalidReferencePrice.selector);
        guard.sqrtPriceLimitX96(0, 6, 1e18, 18, 100, true);

        vm.expectRevert(abi.encodeWithSelector(SlipstreamPriceGuard.UnsupportedTokenDecimals.selector, uint8(19)));
        guard.sqrtPriceLimitX96(1e18, 19, 1e18, 18, 100, true);
    }

    function testRejectsRatiosOutsideSlipstreamRange() public {
        vm.expectRevert(abi.encodeWithSelector(SlipstreamPriceGuard.SqrtPriceOutOfRange.selector, uint256(5)));
        guard.sqrtPriceLimitX96(1, 18, type(uint128).max, 0, 100, true);

        vm.expectRevert(SlipstreamPriceGuard.PriceRatioOverflow.selector);
        guard.sqrtPriceLimitX96(type(uint128).max, 0, 1, 18, 100, false);
    }

    function testChecksCurrentPriceDirection() public {
        guard.requireCurrentPriceWithinLimit(101, 100, true);
        guard.requireCurrentPriceWithinLimit(99, 100, false);

        vm.expectRevert(abi.encodeWithSelector(SlipstreamPriceGuard.CurrentPriceOutsideLimit.selector, 100, 100, true));
        guard.requireCurrentPriceWithinLimit(100, 100, true);

        vm.expectRevert(abi.encodeWithSelector(SlipstreamPriceGuard.CurrentPriceOutsideLimit.selector, 100, 100, false));
        guard.requireCurrentPriceWithinLimit(100, 100, false);
    }

    function testFuzzLowerLimitNeverFallsBelowExactBound(
        uint96 token0Price,
        uint96 token1Price,
        uint8 token0Decimals,
        uint8 token1Decimals,
        uint16 slippageBps
    ) public view {
        token0Price = uint96(bound(token0Price, 1, type(uint96).max));
        token1Price = uint96(bound(token1Price, 1, type(uint96).max));
        token0Decimals = uint8(bound(token0Decimals, 0, 18));
        token1Decimals = uint8(bound(token1Decimals, 0, 18));
        slippageBps = uint16(bound(slippageBps, 0, 9_999));
        (uint256 numerator, uint256 denominator) =
            _ratio(token0Price, token0Decimals, token1Price, token1Decimals, 10_000 - slippageBps, 10_000);
        vm.assume(_insideRange(numerator, denominator));

        uint160 limit =
            guard.sqrtPriceLimitX96(token0Price, token0Decimals, token1Price, token1Decimals, slippageBps, true);
        assertGe(_compareSquareToRatio(limit, numerator, denominator), 0);
    }

    function testFuzzUpperLimitNeverExceedsExactBound(
        uint96 token0Price,
        uint96 token1Price,
        uint8 token0Decimals,
        uint8 token1Decimals,
        uint16 slippageBps
    ) public view {
        token0Price = uint96(bound(token0Price, 1, type(uint96).max));
        token1Price = uint96(bound(token1Price, 1, type(uint96).max));
        token0Decimals = uint8(bound(token0Decimals, 0, 18));
        token1Decimals = uint8(bound(token1Decimals, 0, 18));
        slippageBps = uint16(bound(slippageBps, 0, 9_999));
        (uint256 numerator, uint256 denominator) =
            _ratio(token0Price, token0Decimals, token1Price, token1Decimals, 10_000, 10_000 - slippageBps);
        vm.assume(_insideRange(numerator, denominator));

        uint160 limit =
            guard.sqrtPriceLimitX96(token0Price, token0Decimals, token1Price, token1Decimals, slippageBps, false);
        assertLe(_compareSquareToRatio(limit, numerator, denominator), 0);
    }

    function _ratio(
        uint256 token0Price,
        uint8 token0Decimals,
        uint256 token1Price,
        uint8 token1Decimals,
        uint256 factorNumerator,
        uint256 factorDenominator
    ) private pure returns (uint256 numerator, uint256 denominator) {
        numerator = token0Price * (10 ** token1Decimals) * factorNumerator;
        denominator = token1Price * (10 ** token0Decimals) * factorDenominator;
    }

    function _insideRange(uint256 numerator, uint256 denominator) private pure returns (bool) {
        return _compareSquareToRatio(MIN_SQRT_RATIO, numerator, denominator) < 0
            && _compareSquareToRatio(MAX_SQRT_RATIO, numerator, denominator) > 0;
    }

    function _compareSquareToRatio(uint160 sqrtPriceX96, uint256 numerator, uint256 denominator)
        private
        pure
        returns (int256)
    {
        uint256 squareWhole = Math.mulDiv(sqrtPriceX96, sqrtPriceX96, Q192);
        uint256 ratioWhole = numerator / denominator;
        if (squareWhole < ratioWhole) return -1;
        if (squareWhole > ratioWhole) return 1;

        uint256 squareRemainder = mulmod(sqrtPriceX96, sqrtPriceX96, Q192);
        uint256 ratioRemainder = numerator % denominator;
        uint256 fractionalWhole = Math.mulDiv(squareRemainder, denominator, Q192);
        if (fractionalWhole < ratioRemainder) return -1;
        if (fractionalWhole > ratioRemainder) return 1;
        return mulmod(squareRemainder, denominator, Q192) == 0 ? int256(0) : int256(1);
    }
}
