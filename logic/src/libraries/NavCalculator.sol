// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/* --------------------------------- import --------------------------------- */
import {VaultStorage} from "./VaultStorage.sol";
import {Config} from "../helpers/config.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {FullMath} from "v4-core/src/libraries/FullMath.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {FixedPoint128} from "v4-core/src/libraries/FixedPoint128.sol";
import {LiquidityAmounts} from "v4-periphery/src/libraries/LiquidityAmounts.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";

contract NavCalculator is VaultStorage {

    using StateLibrary for IPoolManager;

/* ------------------------------- constructor ------------------------------ */
    /**
     * @notice Initializes `NavCalculator` by forwarding configuration to `VaultStorage`.
     */
    constructor() VaultStorage(
        Config.POOL_MANAGER_ADDRESS,
        Config.POSITION_MANAGER_ADDRESS,
        Config.PERMIT2_ADDRESS,
        Config.USDC_ADDRESS,
        Config.poolKey(),
        Config.TICK_SPACING * 10,
        6e17
    ) {}

/* -------------------------------------------------------------------------- */
/*                                  functions                                 */
/* -------------------------------------------------------------------------- */

    /**
     * @notice Retrieves the current sqrt price from the pool.
     * @return sqrtPriceX96 The current price in TickMath format.
     */
    function getCurrentSqrtPriceX96() internal view returns (uint160 sqrtPriceX96) {
        (sqrtPriceX96,,,) = poolManager.getSlot0(Config.poolId());
    }

    /**
     * @notice Computes token amounts for a position given price and liquidity.
     * @param liquidity The position's liquidity.
     * @param sqrtPriceX96 Current sqrt price in TickMath format.
     * @param tickLower Lower tick boundary.
     * @param tickUpper Upper tick boundary.
     * @return amount0 Amount of token0 (ETH).
     * @return amount1 Amount of token1 (USDC).
     */
    function getPositionTokenAmounts(
        uint128 liquidity,
        uint160 sqrtPriceX96,
        int24 tickLower,
        int24 tickUpper
    ) internal view returns (uint256 amount0, uint256 amount1) {
        uint160 sqrtPriceLower = TickMath.getSqrtPriceAtTick(tickLower);
        uint160 sqrtPriceUpper = TickMath.getSqrtPriceAtTick(tickUpper);
        (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(sqrtPriceX96, sqrtPriceLower, sqrtPriceUpper, liquidity);
    }
    
    /**
     * @notice Calculates uncollected fees for a position.
     * @param tokenId Position identifier.
     * @param tickLower Lower tick.
     * @param tickUpper Upper tick.
     * @param liquidity Position liquidity.
     * @return feeAmount0 Uncollected fee in token0 (ETH).
     * @return feeAmount1 Uncollected fee in token1 (USDC).
     */
    function getPositionUncollectedFees(
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity,
        int24 currentTick
    ) internal view returns (uint256 feeAmount0, uint256 feeAmount1) {
        if (liquidity == 0) return (0, 0);
        PoolId poolId = Config.poolId();
        (uint256 feeGrowthGlobal0X128, uint256 feeGrowthGlobal1X128) = poolManager.getPoolFeeGrowthGlobal(poolId);
        (uint256 feeGrowthOutsideLower0X128, uint256 feeGrowthOutsideLower1X128) = poolManager.getTickFeeGrowthOutside(poolId, tickLower);
        (uint256 feeGrowthOutsideUpper0X128, uint256 feeGrowthOutsideUpper1X128) = poolManager.getTickFeeGrowthOutside(poolId, tickUpper);
        ( , uint256 feeGrowthInside0LastX128, uint256 feeGrowthInside1LastX128 ) = poolManager.getPositionInfo(
            poolId,
            address(this),
            tickLower,
            tickUpper,
            bytes32(0)
        );
        uint256 feeGrowthBelow0X128;
        uint256 feeGrowthBelow1X128;
        uint256 feeGrowthAbove0X128;
        uint256 feeGrowthAbove1X128;
        unchecked {
            if (currentTick >= tickLower) {
                feeGrowthBelow0X128 = feeGrowthOutsideLower0X128;
                feeGrowthBelow1X128 = feeGrowthOutsideLower1X128;
            } else {
                feeGrowthBelow0X128 = feeGrowthGlobal0X128 - feeGrowthOutsideLower0X128;
                feeGrowthBelow1X128 = feeGrowthGlobal1X128 - feeGrowthOutsideLower1X128;
            }
            if (currentTick < tickUpper) {
                feeGrowthAbove0X128 = feeGrowthOutsideUpper0X128;
                feeGrowthAbove1X128 = feeGrowthOutsideUpper1X128;
            } else {
                feeGrowthAbove0X128 = feeGrowthGlobal0X128 - feeGrowthOutsideUpper0X128;
                feeGrowthAbove1X128 = feeGrowthGlobal1X128 - feeGrowthOutsideUpper1X128;
            }
            uint256 feeGrowthInside0X128 = feeGrowthGlobal0X128 - feeGrowthBelow0X128 - feeGrowthAbove0X128;
            uint256 feeGrowthInside1X128 = feeGrowthGlobal1X128 - feeGrowthBelow1X128 - feeGrowthAbove1X128;
            feeAmount0 = FullMath.mulDiv(
                liquidity,
                feeGrowthInside0X128 - feeGrowthInside0LastX128,
                FixedPoint128.Q128
            );
            feeAmount1 = FullMath.mulDiv(
                liquidity,
                feeGrowthInside1X128 - feeGrowthInside1LastX128,
                FixedPoint128.Q128
            );
        }
    }

    /**
     * @notice Sums all active position token amounts and uncollected fees.
     * @param sqrtPriceX96 Current sqrt price.
     * @param currentTick Current tick.
     * @return totalPositionEth Total ETH in positions.
     * @return totalPositionUsdc Total USDC in positions.
     */
    function computeTotalPositionValue(
        uint160 sqrtPriceX96,
        int24 currentTick
    ) internal view returns (
        uint256 totalPositionEth,
        uint256 totalPositionUsdc
    ) {
        uint256 len = positions.length;
        for (uint256 i = 0; i < len; i++) {
            PositionInfo storage pos = positions[i];
            if (!pos.isActive) continue;
            if (pos.liquidity > 0) {
                (uint256 amt0, uint256 amt1) = getPositionTokenAmounts(
                    pos.liquidity,
                    sqrtPriceX96,
                    pos.tickLower,
                    pos.tickUpper
                );
                totalPositionEth  += amt0;
                totalPositionUsdc += amt1;
            }
            (uint256 fee0, uint256 fee1) = getPositionUncollectedFees(
                pos.tickLower,
                pos.tickUpper,
                pos.liquidity,
                currentTick
            );
            totalPositionEth  += fee0;
            totalPositionUsdc += fee1;
        }
    }

    /**
     * @notice Computes vault NAV: total positions + idle buffer, valued in USDC.
     * @return totalEth Combined ETH from positions and idle buffer.
     * @return totalUsdc Combined USDC from positions and idle buffer.
     * @return navUsdc Net asset value in USDC.
     */
    function computeNav() internal returns (
        uint256 totalEth,
        uint256 totalUsdc,
        uint256 navUsdc
    ) {
        (uint160 sqrtPriceX96, int24 currentTick, , ) = poolManager.getSlot0(Config.poolId());
        (uint256 totalPositionEth, uint256 totalPositionUsdc) = computeTotalPositionValue(sqrtPriceX96, currentTick);
        totalEth  = totalPositionEth  + idleEth;
        totalUsdc = totalPositionUsdc + idleUsdc;
        uint256 ethPriceUsdc = FullMath.mulDiv(uint256(sqrtPriceX96), uint256(sqrtPriceX96), 1 << 192) * 1e12;
        uint256 ethValueInUsdc = FullMath.mulDiv(totalEth, ethPriceUsdc, ETH_DECIMALS);
        navUsdc = ethValueInUsdc + totalUsdc;
        lastNavUsdc      = navUsdc;
        lastNavTimestamp = block.timestamp;
    }
}