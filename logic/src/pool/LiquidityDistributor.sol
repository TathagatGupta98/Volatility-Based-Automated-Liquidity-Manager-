//SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DistributionMath} from "../libraries/DistributionMath.sol";


contract LiquidityDistributor {
    error LiquidityMustBeGreaterThanZero();
    error VolatilityIndexMustBeGreaterThanZero();
    error CurrentTickOutOfBounds();

    uint256 public totalLiquidity;
    uint256 public currentTick;
    uint256 public volatilityIndex;
    uint256 private currentLowerTick;
    uint256 public constant TICKSPACING = 60 ; //ETH-USDC POOL
    uint256 public constant MAX_TICK = 887272;
    uint256 public constant MIN_TICK = -887272; 
    uint256[] public weight;

    struct SlotPlan{
        int24 lowerTick;
        int24 upperTick;
        uint256 liquidityAmount;
    }

    SlotPlan[] public slotPlan;

    constructor(uint256 _totalLiquidity, uint256 _currentTick, uint256 _volatilityIndex) {
        if(_totalLiquidity == 0){
            revert LiquidityMustBeGreaterThanZero();
        }
        if(_volatilityIndex == 0){
            revert VolatilityIndexMustBeGreaterThanZero();
        }
        if (_currentTick < MIN_TICK || _currentTick > MAX_TICK){
            revert CurrentTickOutOfBounds();
        }

        totalLiquidity = _totalLiquidity;
        currentTick = _currentTick;
        volatilityIndex = _volatilityIndex;
    }

    /**
     * @dev Computes the distribution of liquidity across tick ranges based on the current tick and volatility index.
     * @dev calculates the number of slots to distribute liquidity into based on the volatility index, distributes the total liquidity according to predefined weights, 
     *       and computes the lower and upper ticks for each slot. The resulting slot plan includes the tick ranges and corresponding liquidity amounts for each slot.
     */
    function computeDistribution () public returns (SlotPlan[] memory) {
        uint256 numberOfSlots = distributeWeights(volatilityIndex);
        uint256[] memory liquidityDistribution;

        liquidityDistribution = new uint256[](numberOfSlots);
        liquidityDistribution = DistributionMath.Distribute(totalLiquidity, weight);

        currentLowerTick = getCurrentLowerTick(currentTick);

        slotPlan = new SlotPlan[](numberOfSlots);
        for ( uint256 i=0 ; i < numberOfSlots ; i++){
            slotPlan[i].lowerTick = int24(currentLowerTick + (i - (numberOfSlots -1)/2)*TICKSPACING);
            slotPlan[i].upperTick = int24(currentLowerTick + (i - (numberOfSlots -1)/2 + 1)*TICKSPACING);
            slotPlan[i].liquidityAmount = liquidityDistribution[i];
        }

        return slotPlan;
    }


    /**
     * @dev Calculates the current lower tick based on the current tick and tick spacing.
     * @return The current lower tick
     */
    function getCurrentLowerTick(uint256 _currentTick) internal pure returns (uint256) {
        return (_currentTick - (_currentTick % TICKSPACING));
    }


    /**
     * @dev calculate the number of slots to distribute liquidity into based on the volatility index. and initializes the weight array accordingly.
     * @param _volatilityIndex The current volatility index
     * @return n The number of slots to distribute liquidity into
     */
    function distributeWeights(uint256 _volatilityIndex) internal returns (uint256) {
        uint256 n = 3 + (_volatilityIndex - 1) * 2;
        weight = new uint256[](n);
        return n;
    }
}
