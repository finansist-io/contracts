// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {Test} from "forge-std/Test.sol";

import {ChainlinkPriceReference} from "../../src/libraries/ChainlinkPriceReference.sol";
import {VaultTypes} from "../../src/libraries/VaultTypes.sol";

contract RoundPriceFeed {
    uint8 public decimals;
    uint256 public version = 6;
    string public description;

    uint80 private _roundId;
    int256 private _answer;
    uint256 private _startedAt;
    uint256 private _updatedAt;
    uint80 private _answeredInRound;

    constructor(string memory description_, uint8 decimals_) {
        description = description_;
        decimals = decimals_;
    }

    function setDecimals(uint8 decimals_) external {
        decimals = decimals_;
    }

    function setRound(uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
        external
    {
        _roundId = roundId;
        _answer = answer;
        _startedAt = startedAt;
        _updatedAt = updatedAt;
        _answeredInRound = answeredInRound;
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (_roundId, _answer, _startedAt, _updatedAt, _answeredInRound);
    }
}

contract ChainlinkPriceReferenceHarness {
    function quote(
        uint256 amountIn,
        VaultTypes.AssetConfig memory inputAsset,
        uint256 inputMaxAge,
        VaultTypes.AssetConfig memory outputAsset,
        uint256 outputMaxAge
    ) external view returns (uint256) {
        return ChainlinkPriceReference.quote(amountIn, inputAsset, inputMaxAge, outputAsset, outputMaxAge);
    }
}

contract ChainlinkPriceReferenceTest is Test {
    uint256 private constant NOW = 1_800_000_000;

    ChainlinkPriceReferenceHarness private priceReference;
    RoundPriceFeed private usdcFeed;
    RoundPriceFeed private targetFeed;
    VaultTypes.AssetConfig private usdc;
    VaultTypes.AssetConfig private target;

    function setUp() public {
        vm.warp(NOW);
        priceReference = new ChainlinkPriceReferenceHarness();
        usdcFeed = new RoundPriceFeed("USDC / USD", 8);
        targetFeed = new RoundPriceFeed("ETH / USD", 8);
        usdcFeed.setRound(10, 1e8, NOW - 30, NOW - 20, 10);
        targetFeed.setRound(20, 2_000e8, NOW - 20, NOW - 10, 20);
        usdc = _asset(address(1), 6, usdcFeed, 8);
        target = _asset(address(2), 18, targetFeed, 8);
    }

    function testQuotesBothDirectionsWithFloorRounding() public view {
        uint256 targetAmount = priceReference.quote(1_000e6, usdc, 60, target, 60);
        assertEq(targetAmount, 0.5e18);
        assertEq(priceReference.quote(targetAmount, target, 60, usdc, 60), 1_000e6);
    }

    function testHandlesDifferentFeedDecimals() public {
        targetFeed.setDecimals(18);
        target.priceFeedDecimals = 18;
        targetFeed.setRound(20, 2_000e18, NOW - 20, NOW - 10, 20);

        assertEq(priceReference.quote(1_000e6, usdc, 60, target, 60), 0.5e18);
    }

    function testFloorRoundingNeverCreatesInputValue() public {
        target.tokenDecimals = 8;
        targetFeed.setRound(20, 6_287_175_751_889, NOW - 20, NOW - 10, 20);

        uint256 targetAmount = priceReference.quote(1_000e6, usdc, 60, target, 60);
        uint256 returnedUsdc = priceReference.quote(targetAmount, target, 60, usdc, 60);
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
        priceReference.quote(1_000e6, usdc, 60, target, 60);
    }

    function testRejectsUnsupportedDecimals() public {
        targetFeed.setDecimals(19);
        target.priceFeedDecimals = 19;
        vm.expectRevert(
            abi.encodeWithSelector(ChainlinkPriceReference.UnsupportedFeedDecimals.selector, address(targetFeed), 19)
        );
        priceReference.quote(1_000e6, usdc, 60, target, 60);
    }

    function testRejectsUnsupportedTokenDecimalDelta() public {
        target.tokenDecimals = 25;
        vm.expectRevert(abi.encodeWithSelector(ChainlinkPriceReference.UnsupportedTokenDecimalDelta.selector, 6, 25));
        priceReference.quote(1_000e6, usdc, 60, target, 60);
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
        priceReference.quote(1_000e6, usdc, 60, target, 60);

        usdcFeed.setRound(10, 1e8, NOW - 62, NOW - 61, 10);
        vm.expectRevert(
            abi.encodeWithSelector(ChainlinkPriceReference.StalePriceRound.selector, address(usdcFeed), NOW - 61, 60)
        );
        priceReference.quote(1_000e6, usdc, 60, target, 60);
    }

    function testAcceptsRoundAtMaximumAge() public {
        usdcFeed.setRound(10, 1e8, NOW - 61, NOW - 60, 10);
        assertEq(priceReference.quote(1_000e6, usdc, 60, target, 60), 0.5e18);
    }

    function testFuzzRoundTripCannotIncreaseInput(uint96 amountIn, uint64 inputPrice, uint64 outputPrice) public {
        vm.assume(inputPrice > 0 && outputPrice > 0);
        usdcFeed.setRound(10, int256(uint256(inputPrice)), NOW - 30, NOW - 20, 10);
        targetFeed.setRound(20, int256(uint256(outputPrice)), NOW - 20, NOW - 10, 20);

        uint256 amountOut = priceReference.quote(amountIn, usdc, 60, target, 60);
        uint256 roundTrip = priceReference.quote(amountOut, target, 60, usdc, 60);
        assertLe(roundTrip, amountIn);
    }

    function _asset(address token, uint8 tokenDecimals, RoundPriceFeed feed, uint8 feedDecimals)
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
        priceReference.quote(1_000e6, usdc, 60, target, 60);
    }
}
