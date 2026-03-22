//SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DistributionMath} from "../libraries/DistributionMath.sol";

contract LiquidityDistributor {
    error LiquidityMustBeGreaterThanZero();
    error VolatilityIndexMustBeGreaterThanZero();
    error CurrentTickOutOfBounds();

    uint256 public totalLiquidity;
    int256 public currentTick;
    uint256 public volatilityIndex;
    int256 private currentLowerTick;
    uint256 public constant TICKSPACING = 60 ; //ETH-USDC POOL
    int256 public constant MAX_TICK = 887272;
    int256 public constant MIN_TICK = -887272; 
    uint256[] public weight;

    struct SlotPlan{
        int256 lowerTick;
        int256 upperTick;
        uint256 liquidityAmount;
    }

    SlotPlan[] public slotPlan;

    constructor(uint256 _totalLiquidity, int256 _currentTick, uint256 _volatilityIndex) {
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
    function computeDistribution() public returns (SlotPlan[] memory) {
        uint256 numberOfSlots = distributeWeights(volatilityIndex);
        uint256[] memory liquidityDistribution;

        liquidityDistribution = new uint256[](numberOfSlots);
        liquidityDistribution = DistributionMath.Distribute(
            totalLiquidity,
            weight
        );

        currentLowerTick = getCurrentLowerTick(int256(currentTick));
        delete slotPlan;

        for (uint256 i = 0; i < numberOfSlots; i++) {
            slotPlan.push(SlotPlan({
            lowerTick: int256(currentLowerTick + (int256((int256(i) - (int256(numberOfSlots) - 1) / 2) * int256(TICKSPACING)))),
            upperTick: int256(currentLowerTick + (int256((int256(i) - (int256(numberOfSlots) - 1) / 2 + 1) * int256(TICKSPACING)))),
            liquidityAmount: liquidityDistribution[i]
        }));
        }
        return slotPlan;
    }


    /**
     * @dev Calculates the current lower tick based on the current tick and tick spacing.
     */
    function getCurrentLowerTick(int256 _currentTick) internal pure returns (int256) {
        return (_currentTick - (_currentTick % int256(TICKSPACING)));
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

}
