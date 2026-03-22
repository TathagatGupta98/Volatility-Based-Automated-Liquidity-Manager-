// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title VaultIntegration Automation contract 
 * @author PhAnToMxSD
 * @notice This contract is designed to integrate with Chainlink Automation to trigger the volatility calculation and liquidity distribution processes in the vault system at regular intervals. It implements the AutomationCompatibleInterface, allowing it to be registered as an upkeep contract with Chainlink Automation.
 */

import "@chainlink/contracts/src/v0.8/automation/AutomationCompatible.sol";
import {Config} from "./helpers/config.sol";
import {Volatility} from "./volatility_calc/volatility.sol";

contract VaultIntegration is AutomationCompatibleInterface, Volatility {
/* --------------------------------- errors --------------------------------- */
    error VeryFrequentUpkeep();
    error NoChangeInVolatilityIndex();
/* -------------------------------------------------------------------------- */
/*                               state variables                              */
/* -------------------------------------------------------------------------- */
    uint public lastTimestamp;
    uint public interval = 300; 
    uint8 lastVolatilityIndex;
/* ------------------------------- constructor ------------------------------ */
    constructor() Volatility(){
        lastTimestamp = block.timestamp;
    }
/* ------------------------------- checkUpKeep ------------------------------ */
    function checkUpkeep(bytes calldata checkData)
        external
        view
        override
        returns (bool upkeepNeeded, bytes memory performData)
    {
        upkeepNeeded = (block.timestamp - lastTimestamp) >= interval;
    }
/* ------------------------------ performUpKeep ----------------------------- */
    function performUpkeep() external override {
        if ((block.timestamp - lastTimestamp) >= interval) {
            lastTimestamp = block.timestamp;
            calculateVolatility();
            uint m_currentVolatility = Config.volatility_index;
            if (m_currentVolatility != lastVolatilityIndex) {
                lastVolatilityIndex = m_currentVolatility;
                //implementing the rebalancer logic
            }
            else {
                revert NoChangeInVolatilityIndex();
            }
        }
        else {
            revert VeryFrequentUpkeep();
        }
    }
}