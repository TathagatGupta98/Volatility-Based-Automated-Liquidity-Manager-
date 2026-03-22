// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title VaultIntegration Automation contract 
 * @author PhAnToMxSD
 * @notice This contract is designed to integrate with Chainlink Automation to trigger the volatility calculation and liquidity distribution processes in the vault system at regular intervals. It implements the AutomationCompatibleInterface, allowing it to be registered as an upkeep contract with Chainlink Automation.
 */

import "@chainlink/contracts/src/v0.8/automation/AutomationCompatible.sol";

contract VaultIntegration is AutomationCompatibleInterface {
/* --------------------------------- errors --------------------------------- */
    error VeryFrequentUpkeep();
    uint public counter;
    uint public lastTimestamp;
    uint public interval = 60; // seconds
/* ------------------------------- constructor ------------------------------ */
    constructor() {
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
        performData = ""; 
    }
/* ------------------------------ performUpKeep ----------------------------- */
    function performUpkeep(bytes calldata performData) external override {
        if ((block.timestamp - lastTimestamp) >= interval) {
            lastTimestamp = block.timestamp;
            counter++;
        }
        else {
            revert VeryFrequentUpkeep();
        }
    }
}