//SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DistributionMath} from "../libraries/DistributionMath.sol";

contract LiquidityDistributor {
    uint256 public totalLiquidity;
    uint256 public currentTick;
    uint256 public volatilityIndex;
    uint256 private currentLowerTick;
    uint256 public constant TICKSPACING = 60 ; //ETH-USDC POOL
    uint256[] public weight;
    uint256[] public liquidityDistribution;

    struct SlotPlan{
        int24 lowerTick;
        int24 upperTick;
        uint256 liquidityAmount;
    }

    SlotPlan[] public slotPlan;

    constructor(uint256 _totalLiquidity, uint256 _currentTick, uint256 _volatilityIndex) {
        totalLiquidity = _totalLiquidity;
        currentTick = _currentTick;
        volatilityIndex = _volatilityIndex;
    }

    function computeDistribution () public returns (SlotPlan[] memory) {
        uint256 numberOfSlots = distributeWeights(volatilityIndex);
        liquidityDistribution = new uint256[](numberOfSlots);
        liquidityDistribution = DistributionMath.Distribute(totalLiquidity, weight);
        currentLowerTick = computeCurrentLowerTick(currentTick);
        slotPlan = new SlotPlan[](numberOfSlots);
        for ( uint256 i=0 ; i < numberOfSlots ; i++){
            slotPlan[i].lowerTick = int24(currentLowerTick + (i - (numberOfSlots -1)/2)*TICKSPACING);
            slotPlan[i].upperTick = int24(currentLowerTick + (i - (numberOfSlots -1)/2 + 1)*TICKSPACING);
            slotPlan[i].liquidityAmount = liquidityDistribution[i];
        }

        return slotPlan;
    }
}
