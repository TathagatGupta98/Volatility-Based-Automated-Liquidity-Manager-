// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/* --------------------------------- import --------------------------------- */
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {FullMath} from "v4-core/src/libraries/FullMath.sol";

library NavCalculator {
/* -------------------------------------------------------------------------- */
/*                                  functions                                 */
/* -------------------------------------------------------------------------- */

    function getCurrentSqrtPriceX96() internal view returns (uint160 sqrtPriceX96) {
        (sqrtPriceX96,,,) = poolManager.getSlot0(Config.poolId());
    }

    function getPositionTokenAmounts(
        uint128 liquidity,
        uint160 sqrtPriceX96,
        int24 tickLower,
        int24 tickUpper
    ) internal view returns (uint256 amount0, uint256 amount1){
        uint160 sqrtPriceLower = TickMath.getSqrtPriceAtTick(tickLower);
        uint160 sqrtPriceUpper = TickMath.getSqrtPriceAtTick(tickUpper)

        sqrtPriceX96 = getCurrentSqrtPriceX96();

        (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(sqrtPriceX96, sqrtPriceLower, sqrtPriceUpper, liquidity)
    }
    
    function getPositionUncollectedFees(
        uint256 tokenId, 
        int24 tickLower, 
        int24 tickUpper, 
        uint128 liquidity
    ) returns (uint256 feeAmount0, uint256 feeAmount1){

        (uint256 feeGrowthGlobal0X128, uint256 feeGrowthGlobal1X128) = StateLibrary.getPoolFeeGrowthGlobal();
        (uint256 feeGrowthOutside0X128, uint256 feeGrowthOutside1X128) = StateLibrary.getTickFeeGrowthOutside();
        (uint256 feeGrowthInside0LastX128, uint256 feeGrowthInside1LastX128) = StateLibrary.getPositionInfo(); 

        feeGrowthInside0 = feeGrowthGlobal0 - feeGrowthBelowLower0 - feeGrowthAboveUpper0;

        uint256 feeAmount0 = liquidity * (feeGrowthInside0 - feeGrowthInside0Last) / 2**128;
        uint256 feeAmount1 = liquidity * (feeGrowthInside1 - feeGrowthInside1Last) / 2**128;
    }
    
}