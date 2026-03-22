//SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DistributionMath} from "../libraries/DistributionMath.sol";

contract LiquidityDistributor {
    uint256 public totalLiquidity;
    uint256 public currentTick;
    uint256 public volatilityIndex;
    int24 private currentLowerTick;
    uint256 public constant TICKSPACING = 60; //ETH-USDC POOL
    uint256[] public weight;
    uint256[] public liquidityDistribution;

    struct SlotPlan {
        int24 lowerTick;
        int24 upperTick;
        uint256 liquidityAmount;
    }

    SlotPlan[] public slotPlan;

    constructor(
        uint256 _totalLiquidity,
        uint256 _currentTick,
        uint256 _volatilityIndex
    ) {
        totalLiquidity = _totalLiquidity;
        currentTick = _currentTick;
        volatilityIndex = _volatilityIndex;
    }

    /**
     * @dev Computes the distribution of liquidity across tick ranges based on the current tick and volatility index.
     * @dev calculates the number of slots to distribute liquidity into based on the volatility index, distributes the total liquidity according to predefined weights,
     *       and computes the lower and upper ticks for each slot. The resulting slot plan includes the tick ranges and corresponding liquidity amounts for each slot.
     */
    function computeDistribution() public returns (SlotPlan[] memory) {
        uint256 numberOfSlots = distributeWeights(volatilityIndex);

        liquidityDistribution = new uint256[](numberOfSlots);
        liquidityDistribution = DistributionMath.Distribute(
            totalLiquidity,
            weight
        );

        currentLowerTick = computeCurrentLowerTick(currentTick);

        SlotPlan[] memory computedPlans = new SlotPlan[](numberOfSlots);
        int256 center = int256(currentLowerTick);
        int256 halfWidth = int256((numberOfSlots - 1) / 2);
        for (uint256 i = 0; i < numberOfSlots; i++) {
            int256 offset = int256(i) - halfWidth;
            computedPlans[i].lowerTick = int24(
                center + (offset * int256(TICKSPACING))
            );
            computedPlans[i].upperTick = int24(
                center + ((offset + 1) * int256(TICKSPACING))
            );
            computedPlans[i].liquidityAmount = liquidityDistribution[i];
        }

        delete slotPlan;
        for (uint256 i = 0; i < numberOfSlots; i++) {
            slotPlan.push(computedPlans[i]);
        }

        return computedPlans;
    }

    /**
     * @dev calculate the number of slots to distribute liquidity into based on the volatility index. and initializes the weight array accordingly.
     * @param _volatilityIndex The current volatility index
     * @return n The number of slots to distribute liquidity into
     */
    function distributeWeights(
        uint256 _volatilityIndex
    ) internal returns (uint256) {
        uint256 n = 3 + (_volatilityIndex - 1) * 2;
        weight = new uint256[](n);
        return n;
    }

    function computeCurrentLowerTick(
        uint256 _currentTick
    ) internal pure returns (int24) {
        return int24(int256((_currentTick / TICKSPACING) * TICKSPACING));
    }
}
