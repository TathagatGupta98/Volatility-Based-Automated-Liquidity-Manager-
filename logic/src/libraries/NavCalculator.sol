// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/* --------------------------------- import --------------------------------- */
import {VaultStorage} from "../core/VaultStorage.sol";
import {Config} from "../helpers/config.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {FullMath} from "v4-core/src/libraries/FullMath.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {FixedPoint128} from "v4-core/src/libraries/FixedPoint128.sol";
import {SqrtPriceMath} from "v4-core/src/libraries/SqrtPriceMath.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";
import {IChainlinkAggregatorV3} from "../interfaces/IChainlinkAggregatorV3.sol";

abstract contract NavCalculator is VaultStorage {

    using StateLibrary for IPoolManager;

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
    ) internal pure returns (uint256 amount0, uint256 amount1) {
        uint160 sqrtPriceLower = TickMath.getSqrtPriceAtTick(tickLower);
        uint160 sqrtPriceUpper = TickMath.getSqrtPriceAtTick(tickUpper);

        if (sqrtPriceX96 <= sqrtPriceLower) {
            amount0 = SqrtPriceMath.getAmount0Delta(sqrtPriceLower, sqrtPriceUpper, liquidity, true);
        } else if (sqrtPriceX96 < sqrtPriceUpper) {
            amount0 = SqrtPriceMath.getAmount0Delta(sqrtPriceX96, sqrtPriceUpper, liquidity, true);
            amount1 = SqrtPriceMath.getAmount1Delta(sqrtPriceLower, sqrtPriceX96, liquidity, true);
        } else {
            amount1 = SqrtPriceMath.getAmount1Delta(sqrtPriceLower, sqrtPriceUpper, liquidity, true);
        }
    }
    
    /**
     * @notice Calculates uncollected fees for a position.
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
        currentTick;

        PoolId poolId = Config.poolId();
        (, uint256 feeGrowthInside0LastX128, uint256 feeGrowthInside1LastX128) =
            poolManager.getPositionInfo(poolId, address(this), tickLower, tickUpper, bytes32(0));
        (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) =
            poolManager.getFeeGrowthInside(poolId, tickLower, tickUpper);

        unchecked {
            if (feeGrowthInside0X128 > feeGrowthInside0LastX128) {
                feeAmount0 = FullMath.mulDiv(
                    liquidity,
                    feeGrowthInside0X128 - feeGrowthInside0LastX128,
                    FixedPoint128.Q128
                );
            }

            if (feeGrowthInside1X128 > feeGrowthInside1LastX128) {
                feeAmount1 = FullMath.mulDiv(
                    liquidity,
                    feeGrowthInside1X128 - feeGrowthInside1LastX128,
                    FixedPoint128.Q128
                );
            }
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
        uint256 ethPriceUsdc = _guardedEthUsdcPrice(sqrtPriceX96);
        uint256 ethValueInUsdc = FullMath.mulDiv(totalEth, ethPriceUsdc, ETH_DECIMALS);
        navUsdc = ethValueInUsdc + totalUsdc;
        lastNavUsdc      = navUsdc;
        lastNavTimestamp = block.timestamp;
    }

    function _guardedEthUsdcPrice(uint160 sqrtPriceX96) internal view returns (uint256) {
        uint256 priceX96 = FullMath.mulDiv(uint256(sqrtPriceX96), uint256(sqrtPriceX96), 1 << 96);
        uint256 poolPrice = FullMath.mulDiv(priceX96, ETH_DECIMALS, 1 << 96);
        uint256 oraclePrice = _oracleEthUsdcPriceForNav();

        if (oraclePrice == 0) return poolPrice;
        if (poolPrice == 0) return oraclePrice;

        uint256 diff = poolPrice > oraclePrice ? poolPrice - oraclePrice : oraclePrice - poolPrice;
        if (diff * 10_000 > oraclePrice * Config.MAX_POOL_ORACLE_DEVIATION_BPS) {
            return oraclePrice;
        }

        return poolPrice;
    }

    function _oracleEthUsdcPriceForNav() internal view returns (uint256) {
        IChainlinkAggregatorV3 feed = IChainlinkAggregatorV3(Config.CHAINLINK_ETH_USD_FEED);
        (, int256 answer, , uint256 updatedAt, ) = feed.latestRoundData();

        if (answer <= 0) return 0;
        if (updatedAt == 0) return 0;
        if (updatedAt + Config.ORACLE_STALE_THRESHOLD < block.timestamp) return 0;

        uint256 unsignedAnswer = uint256(answer);
        uint8 feedDecimals = feed.decimals();

        if (feedDecimals == 6) return unsignedAnswer;
        if (feedDecimals > 6) return unsignedAnswer / (10 ** (feedDecimals - 6));
        return unsignedAnswer * (10 ** (6 - feedDecimals));
    }
}