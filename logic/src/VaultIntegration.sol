// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title VaultIntegration Automation contract 
 * @author PhAnToMxSD
 * @notice This contract is designed to integrate with Chainlink Automation to trigger the volatility calculation and liquidity distribution processes in the vault system at regular intervals. It implements the AutomationCompatibleInterface, allowing it to be registered as an upkeep contract with Chainlink Automation.
 */

import "@chainlink/contracts/src/v0.8/automation/AutomationCompatible.sol";
import {Volatility} from "./volatility_calc/volatility.sol";

interface IPoolInteractorVolatility {
    function setVolatilityIndex(uint8 newVolatilityIndex) external;
}

contract VaultIntegration is AutomationCompatibleInterface, Volatility {
/* --------------------------------- errors --------------------------------- */
    error VeryFrequentUpkeep();
    error NoChangeInVolatilityIndex();
    error NotAuthorized();
/* -------------------------------------------------------------------------- */
/*                               state variables                              */
/* -------------------------------------------------------------------------- */
    uint public lastTimestamp;
    uint public interval = 300; 
    uint8 lastVolatilityIndex;
    address public owner;
    IPoolInteractorVolatility public poolInteractor;

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotAuthorized();
        _;
    }
/* ------------------------------- constructor ------------------------------ */
    constructor() Volatility(){
        lastTimestamp = block.timestamp;
        owner = msg.sender;
    }

    function setPoolInteractor(address poolInteractorAddress) external onlyOwner {
        poolInteractor = IPoolInteractorVolatility(poolInteractorAddress);
    }
/* ------------------------------- checkUpKeep ------------------------------ */
    function checkUpkeep(bytes calldata checkData)
        external
        view
        override
        returns (bool upkeepNeeded, bytes memory performData)
    {
        upkeepNeeded = (block.timestamp - lastTimestamp) >= interval;
        performData = checkData;
    }
/* ------------------------------ performUpKeep ----------------------------- */
    function performUpkeep(bytes calldata) external override {
        if ((block.timestamp - lastTimestamp) >= interval) {
            lastTimestamp = block.timestamp;
            calculateVolatility();
            uint8 m_currentVolatility = getVolatilityIndex();
            if (m_currentVolatility != lastVolatilityIndex) {
                lastVolatilityIndex = m_currentVolatility;
                if (address(poolInteractor) != address(0)) {
                    poolInteractor.setVolatilityIndex(m_currentVolatility);
                }
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