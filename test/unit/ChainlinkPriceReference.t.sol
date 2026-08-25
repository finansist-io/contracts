// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {Test} from "forge-std/Test.sol";

import {ChainlinkPriceReference} from "../../src/libraries/ChainlinkPriceReference.sol";
import {VaultTypes} from "../../src/libraries/VaultTypes.sol";
import {MockChainlinkAggregatorV3} from "../helpers/MockChainlinkAggregatorV3.sol";

contract ChainlinkPriceReferenceHarness {
    function quote(
        uint256 amountIn,
        VaultTypes.AssetConfig memory inputAsset,
        VaultTypes.AssetConfig memory outputAsset
    ) external view returns (uint256) {
        return ChainlinkPriceReference.quote(amountIn, inputAsset, outputAsset);
    }
}

contract ChainlinkPriceReferenceTest is Test {
    uint256 private constant NOW = 1_800_000_000;

    ChainlinkPriceReferenceHarness private priceReference;
    MockChainlinkAggregatorV3 private usdcFeed;
    MockChainlinkAggregatorV3 private targetFeed;
    VaultTypes.AssetConfig private usdc;
    VaultTypes.AssetConfig private target;

    function setUp() public {
        vm.warp(NOW);
        priceReference = new ChainlinkPriceReferenceHarness();
        usdcFeed = new MockChainlinkAggregatorV3("USDC / USD", 8, 6);
        targetFeed = new MockChainlinkAggregatorV3("ETH / USD", 8, 6);
        usdcFeed.setRound(10, 1e8, NOW - 30, NOW - 20, 10);
        targetFeed.setRound(20, 2_000e8, NOW - 20, NOW - 10, 20);
        usdc = _asset(address(1), 6, usdcFeed, 8);
        target = _asset(address(2), 18, targetFeed, 8);
    }

    function testQuotesBothDirectionsWithFloorRounding() public view {
        uint256 targetAmount = priceReference.quote(1_000e6, usdc, target);
        assertEq(targetAmount, 0.5e18);
        assertEq(priceReference.quote(targetAmount, target, usdc), 1_000e6);
    }

    function testHandlesDifferentFeedDecimals() public {
        targetFeed.setDecimals(18);
        target.priceFeedDecimals = 18;
        targetFeed.setRound(20, 2_000e18, NOW - 20, NOW - 10, 20);

        assertEq(priceReference.quote(1_000e6, usdc, target), 0.5e18);
    }

    function testFloorRoundingNeverCreatesInputValue() public {
        target.tokenDecimals = 8;
        targetFeed.setRound(20, 6_287_175_751_889, NOW - 20, NOW - 10, 20);

        uint256 targetAmount = priceReference.quote(1_000e6, usdc, target);
        uint256 returnedUsdc = priceReference.quote(targetAmount, target, usdc);
        assertEq(targetAmount, 1_590_539);
        assertLe(returnedUsdc, 1_000e6);
    }

    function testRejectsFeedDecimalsDrift() public {
        targetFeed.setDecimals(9);
        vm.expectRevert(
            abi.encodeWithSelector(
                ChainlinkPriceReference.PriceFeedDecimalsMismatch.selector, address(targetFeed), 8, 9
            )
        );
        priceReference.quote(1_000e6, usdc, target);
    }

    function testRejectsUnsupportedDecimals() public {
        targetFeed.setDecimals(19);
        target.priceFeedDecimals = 19;
        vm.expectRevert(
            abi.encodeWithSelector(ChainlinkPriceReference.UnsupportedFeedDecimals.selector, address(targetFeed), 19)
        );
        priceReference.quote(1_000e6, usdc, target);
    }

    function testRejectsUnsupportedTokenDecimalDelta() public {
        target.tokenDecimals = 25;
        vm.expectRevert(abi.encodeWithSelector(ChainlinkPriceReference.UnsupportedTokenDecimalDelta.selector, 6, 25));
        priceReference.quote(1_000e6, usdc, target);
    }

    function testRejectsInvalidRounds() public {
        _expectInvalidRound(0, 1e8, NOW - 10, NOW - 5, 0);
        _expectInvalidRound(10, 0, NOW - 10, NOW - 5, 10);
        _expectInvalidRound(10, -1, NOW - 10, NOW - 5, 10);
        _expectInvalidRound(10, 1e8, 0, NOW - 5, 10);
        _expectInvalidRound(10, 1e8, NOW - 10, 0, 10);
        _expectInvalidRound(10, 1e8, NOW - 5, NOW - 10, 10);
        _expectInvalidRound(10, 1e8, NOW - 10, NOW - 5, 9);
    }

    function testRejectsFutureAndStaleRounds() public {
        usdcFeed.setRound(10, 1e8, NOW, NOW + 1, 10);
        vm.expectRevert(
            abi.encodeWithSelector(ChainlinkPriceReference.FuturePriceRound.selector, address(usdcFeed), NOW + 1)
        );
        priceReference.quote(1_000e6, usdc, target);

        usdcFeed.setRound(10, 1e8, NOW - 62, NOW - 61, 10);
        vm.expectRevert(
            abi.encodeWithSelector(ChainlinkPriceReference.StalePriceRound.selector, address(usdcFeed), NOW - 61, 60)
        );
        priceReference.quote(1_000e6, usdc, target);
    }

    function testAcceptsRoundAtMaximumAge() public {
        usdcFeed.setRound(10, 1e8, NOW - 61, NOW - 60, 10);
        assertEq(priceReference.quote(1_000e6, usdc, target), 0.5e18);
    }

    function testFuzzRoundTripCannotIncreaseInput(uint96 amountIn, uint64 inputPrice, uint64 outputPrice) public {
        vm.assume(inputPrice > 0 && outputPrice > 0);
        usdcFeed.setRound(10, int256(uint256(inputPrice)), NOW - 30, NOW - 20, 10);
        targetFeed.setRound(20, int256(uint256(outputPrice)), NOW - 20, NOW - 10, 20);

        uint256 amountOut = priceReference.quote(amountIn, usdc, target);
        uint256 roundTrip = priceReference.quote(amountOut, target, usdc);
        assertLe(roundTrip, amountIn);
    }

    function _asset(address token, uint8 tokenDecimals, MockChainlinkAggregatorV3 feed, uint8 feedDecimals)
        private
        view
        returns (VaultTypes.AssetConfig memory)
    {
        return VaultTypes.AssetConfig({
            assetId: keccak256(abi.encode(token)),
            token: token,
            usdPriceFeed: address(feed),
            tokenDecimals: tokenDecimals,
            priceFeedDecimals: feedDecimals,
            priceMaxAge: 60,
            priceFeedVersion: 6,
            tokenCodeHash: bytes32(uint256(1)),
            priceFeedCodeHash: address(feed).codehash,
            priceFeedDescriptionHash: keccak256(bytes(feed.description()))
        });
    }

    function _expectInvalidRound(
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) private {
        usdcFeed.setRound(roundId, answer, startedAt, updatedAt, answeredInRound);
        vm.expectRevert(abi.encodeWithSelector(ChainlinkPriceReference.InvalidPriceRound.selector, address(usdcFeed)));
        priceReference.quote(1_000e6, usdc, target);
    }
}
