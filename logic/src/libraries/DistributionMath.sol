// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title DistributionMath
 * @dev Library for distributing liquidity based on weights.
 *      Weights are in whole-number percentages and MUST sum to 100.
 *      Rounding dust is added to the centre slot.
 */
library DistributionMath {
    error SumWeightsNotEqual100();
    error WeightsArrayLengthZero();

    /**
     * @param totalLiquidity Total liquidity (in token units or abstract units)
     * @param weights        Array of percentage weights, each 0-100, summing to 100
     * @return amounts       Liquidity allocated to each slot
     */
    function distribute(
        uint256 totalLiquidity,
        uint256[] memory weights
    ) internal pure returns (uint256[] memory amounts) {
        uint256 n = weights.length;
        if (n == 0) revert WeightsArrayLengthZero();
        if (!_validateWeights(weights)) revert SumWeightsNotEqual100();

        amounts = new uint256[](n);
        uint256 allocated;

        for (uint256 i = 0; i < n; i++) {
            amounts[i] = (totalLiquidity * weights[i]) / 100;
            allocated += amounts[i];
        }

        // Add rounding dust to centre slot
        uint256 dust = totalLiquidity - allocated;
        if (dust > 0) {
            amounts[n / 2] += dust;
        }
    }

    function _validateWeights(
        uint256[] memory weights
    ) private pure returns (bool) {
        uint256 total;
        for (uint256 i = 0; i < weights.length; i++) {
            total += weights[i];
        }
        return total == 100;
    }
}