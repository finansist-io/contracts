// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IChainlinkAggregatorV3} from "../interfaces/IChainlinkAggregatorV3.sol";
import {VaultTypes} from "./VaultTypes.sol";

library ChainlinkPriceReference {
    uint8 private constant NORMALIZED_PRICE_DECIMALS = 18;

    error UnsupportedFeedDecimals(address priceFeed, uint8 decimals);
    error UnsupportedTokenDecimalDelta(uint8 lowerDecimals, uint8 higherDecimals);
    error PriceFeedDecimalsMismatch(address priceFeed, uint8 expected, uint8 actual);
    error InvalidPriceRound(address priceFeed);
    error FuturePriceRound(address priceFeed, uint256 updatedAt);
    error StalePriceRound(address priceFeed, uint256 updatedAt, uint256 maxAge);
    error PriceScaleOverflow();

    function quote(
        uint256 amountIn,
        VaultTypes.AssetConfig memory inputAsset,
        VaultTypes.AssetConfig memory outputAsset
    ) internal view returns (uint256) {
        uint256 inputPrice = readNormalizedPrice(inputAsset);
        uint256 outputPrice = readNormalizedPrice(outputAsset);

        if (inputAsset.tokenDecimals == outputAsset.tokenDecimals) {
            return Math.mulDiv(amountIn, inputPrice, outputPrice);
        }

        if (inputAsset.tokenDecimals < outputAsset.tokenDecimals) {
            uint256 inputScale = _decimalGapScale(inputAsset.tokenDecimals, outputAsset.tokenDecimals);
            (bool inputScaleValid, uint256 scaledInputPrice) = Math.tryMul(inputPrice, inputScale);
            if (!inputScaleValid) revert PriceScaleOverflow();
            return Math.mulDiv(amountIn, scaledInputPrice, outputPrice);
        }

        uint256 outputScale = _decimalGapScale(outputAsset.tokenDecimals, inputAsset.tokenDecimals);
        (bool outputScaleValid, uint256 scaledOutputPrice) = Math.tryMul(outputPrice, outputScale);
        if (!outputScaleValid) revert PriceScaleOverflow();
        return Math.mulDiv(amountIn, inputPrice, scaledOutputPrice);
    }

    function readNormalizedPrice(VaultTypes.AssetConfig memory asset) internal view returns (uint256) {
        IChainlinkAggregatorV3 priceFeed = IChainlinkAggregatorV3(asset.usdPriceFeed);
        uint8 actualDecimals = priceFeed.decimals();
        if (actualDecimals != asset.priceFeedDecimals) {
            revert PriceFeedDecimalsMismatch(asset.usdPriceFeed, asset.priceFeedDecimals, actualDecimals);
        }
        if (actualDecimals > NORMALIZED_PRICE_DECIMALS) {
            revert UnsupportedFeedDecimals(asset.usdPriceFeed, actualDecimals);
        }

        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            priceFeed.latestRoundData();
        if (
            roundId == 0 || answer <= 0 || startedAt == 0 || updatedAt == 0 || answeredInRound < roundId
                || startedAt > updatedAt
        ) revert InvalidPriceRound(asset.usdPriceFeed);
        if (updatedAt > block.timestamp) revert FuturePriceRound(asset.usdPriceFeed, updatedAt);
        if (block.timestamp - updatedAt > asset.priceMaxAge) {
            revert StalePriceRound(asset.usdPriceFeed, updatedAt, asset.priceMaxAge);
        }

        uint256 scale = 10 ** (NORMALIZED_PRICE_DECIMALS - actualDecimals);
        // forge-lint: disable-next-line(unsafe-typecast)
        (bool success, uint256 normalizedPrice) = Math.tryMul(uint256(answer), scale);
        if (!success) revert PriceScaleOverflow();
        return normalizedPrice;
    }

    function _decimalGapScale(uint8 lowerDecimals, uint8 higherDecimals) private pure returns (uint256) {
        uint8 exponent = higherDecimals - lowerDecimals;
        if (exponent > NORMALIZED_PRICE_DECIMALS) {
            revert UnsupportedTokenDecimalDelta(lowerDecimals, higherDecimals);
        }
        return 10 ** exponent;
    }
}
