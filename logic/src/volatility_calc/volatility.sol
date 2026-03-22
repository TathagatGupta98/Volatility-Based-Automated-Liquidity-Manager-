/**
 * @title TickCalculator
 * @author PhAnToMxSD
 * @notice Library for calculating ticks and prices in a Uniswap V4 AMM.
 * @dev This library provides functions to convert between ticks and prices, as well as to calculate the tick corresponding to a given price. It uses fixed-point arithmetic for precision. Moreover, it includes functions to calculate the price at a given tick, which are essential for liquidity provision and trading in a Uniswap V4 AMM. The library is designed to be efficient and accurate, making it suitable for use in smart contracts that require precise tick calculations. It also helps us in calculating the price of the liquidity position at a given tick, which is crucial for determining the value of the position and for executing trades. The functions in this library are optimized for gas efficiency while maintaining accuracy, making it a valuable tool for developers working on Uniswap V4 AMM implementations.
 */

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/* -------------------------------- import -------------------------------- */

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {Config} from "../helpers/config.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";

contract Volatility {
    /* -------------------------------------------------------------------------- */
    /*                                   errors                                   */
    /* -------------------------------------------------------------------------- */
    error flashLoanAttack();

    /* -------------------------------------------------------------------------- */
    /*                                  constants                                 */
    /* -------------------------------------------------------------------------- */
    uint256 ewmaVariance = 0;
    int24 lastTick;
    uint32 lastObservationTimestamp;
    uint256 lastObservationBlock;

    /* ------------------------------- constructur ------------------------------ */
    constructor() {
        (, int24 tick,,) = StateLibrary.getSlot0(Config.poolManager, Config.poolId());

        lastTick = tick;
        lastObservationTimestamp = uint32(block.timestamp);
        lastObservationBlock = block.number;
    }

    /* -------------------------------------------------------------------------- */
    /*                               public funcions                              */
    /* -------------------------------------------------------------------------- */
    function calculateEWMA() public returns (uint256) {
        (, int24 m_currentTick,,) = StateLibrary.getSlot0(Config.poolManager, Config.poolId());

        uint32 m_currentTimestamp = uint32(block.timestamp);
        uint256 m_currentBlock = block.number;

        int24 delta = m_currentTick - lastTick;

        uint8 errorCode = _checkFlashLoanProtection(
            delta,
            m_currentTimestamp,
            m_currentBlock
        );

        if (errorCode != 0 && errorCode != 1) {
            revert flashLoanAttack();
        } else if (errorCode == 1) {
            delta = 300;
        }

        _calculateEwmaVariance(delta);

        lastTick = m_currentTick;
        lastObservationTimestamp = m_currentTimestamp;
        lastObservationBlock = m_currentBlock;

        return ewmaVariance;
    }

    /* -------------------------------------------------------------------------- */
    /*                             internal functions                             */
    /* -------------------------------------------------------------------------- */
    function _checkFlashLoanProtection(
        int24 delta,
        uint32 time,
        uint256 bnum
    ) internal view returns (uint8 errorCode) {
        if (bnum <= lastObservationBlock) {
            return 10;
        } else if (time <= lastObservationTimestamp + Config.TMIN) {
            return 11;
        } else if (delta > 300 || delta < -300) {
            return 1;
        } else {
            return 0;
        }
    }

    function _calculateEwmaVariance(int24 delta) internal {
        int256 delta256 = int256(delta);
        uint256 returnSquareScaled = uint256(delta256 * delta256) * Config.LNSQ_1E18;
        ewmaVariance =
            Config.LAMBDA *
            ewmaVariance +
            Config.ONE_MINUS_LAMBDA *
            returnSquareScaled;
        ewmaVariance = ewmaVariance / 1e18;
    }
}
