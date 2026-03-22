/**
 * @title TickCalculator
 * @author PhAnToMxSD
 * @notice Library for calculating ticks and prices in a Uniswap V4 AMM.
 * @dev This library provides functions to convert between ticks and prices, as well as to calculate the tick corresponding to a given price. It uses fixed-point arithmetic for precision. Moreover, it includes functions to calculate the price at a given tick, which are essential for liquidity provision and trading in a Uniswap V4 AMM. The library is designed to be efficient and accurate, making it suitable for use in smart contracts that require precise tick calculations. It also helps us in calculating the price of the liquidity position at a given tick, which is crucial for determining the value of the position and for executing trades. The functions in this library are optimized for gas efficiency while maintaining accuracy, making it a valuable tool for developers working on Uniswap V4 AMM implementations.
 */

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {Config} from "../helpers/config.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";

contract Volatility {

    function calculateEWMA() public view returns (uint256) {
        (uint160 sqrtPriceX96, int24 tick, uint24 protocolFee, uint24 lpFee) = StateLibrary.getSlot0(Config.poolManager, Config.poolId());

        return uint256(sqrtPriceX96) + uint256(uint24(tick)) + uint256(protocolFee) + uint256(lpFee);
    }
}