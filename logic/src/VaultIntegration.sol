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
    function rebalance(uint256 totalLiquidityAvailable, uint256 _volatilityIndex) external;
    function needsTickDriftRebalance() external view returns (bool);
}

contract VaultIntegration is AutomationCompatibleInterface, Volatility {
/* --------------------------------- errors --------------------------------- */
    error VeryFrequentUpkeep();
    error NotAuthorized();
    error PoolInteractorNotSet();
/* -------------------------------------------------------------------------- */
/*                               state variables                              */
/* -------------------------------------------------------------------------- */
    uint public lastTimestamp;
    uint public interval = 300;
    uint8 public lastVolatilityIndex;
    address public owner;
    IPoolInteractorVolatility public poolInteractor;
    uint256 public rebalanceLiquidity;
    bool public autoRebalanceEnabled = true;
    bool public driftRebalanceEnabled = true;

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotAuthorized();
        _;
    }
/* ------------------------------- constructor ------------------------------ */
    constructor() Volatility() {
        lastTimestamp = block.timestamp;
        owner = msg.sender;
        lastVolatilityIndex = getVolatilityIndex();
    }

    function setPoolInteractor(address poolInteractorAddress) external onlyOwner {
        poolInteractor = IPoolInteractorVolatility(poolInteractorAddress);
    }

    function setInterval(uint256 newInterval) external onlyOwner {
        interval = newInterval;
    }

    function setRebalanceLiquidity(uint256 newRebalanceLiquidity) external onlyOwner {
        rebalanceLiquidity = newRebalanceLiquidity;
    }

    function setAutoRebalanceEnabled(bool enabled) external onlyOwner {
        autoRebalanceEnabled = enabled;
    }

    function setDriftRebalanceEnabled(bool enabled) external onlyOwner {
        driftRebalanceEnabled = enabled;
    }

    function syncVolatilityIndex() public returns (uint8 currentVolatilityIndex, uint256 currentVolatilityValue) {
        if (address(poolInteractor) == address(0)) revert PoolInteractorNotSet();

        calculateVolatility();
        currentVolatilityIndex = getVolatilityIndex();
        currentVolatilityValue = getVolatilityValue();

        if (currentVolatilityIndex != lastVolatilityIndex) {
            lastVolatilityIndex = currentVolatilityIndex;
        }

        poolInteractor.setVolatilityIndex(currentVolatilityIndex);
    }

    function rebalanceNow(uint256 totalLiquidityAvailable) external onlyOwner {
        if (address(poolInteractor) == address(0)) revert PoolInteractorNotSet();
        (uint8 currentVolatilityIndex,) = syncVolatilityIndex();
        poolInteractor.rebalance(totalLiquidityAvailable, currentVolatilityIndex);
    }

    function executeEngineCycle() external {
        if (address(poolInteractor) == address(0)) revert PoolInteractorNotSet();

        uint8 previousVolatilityIndex = lastVolatilityIndex;
        (uint8 currentVolatilityIndex,) = syncVolatilityIndex();

        bool shouldRebalance = false;
        if (autoRebalanceEnabled) {
            shouldRebalance = currentVolatilityIndex != previousVolatilityIndex;
        }

        if (driftRebalanceEnabled) {
            shouldRebalance = shouldRebalance || poolInteractor.needsTickDriftRebalance();
        }

        if (shouldRebalance && rebalanceLiquidity > 0) {
            poolInteractor.rebalance(rebalanceLiquidity, currentVolatilityIndex);
        }
    }

/* ------------------------------- checkUpKeep ------------------------------ */
    function checkUpkeep(bytes calldata checkData)
        external
        view
        override
        returns (bool upkeepNeeded, bytes memory performData)
    {
        bool timeElapsed = (block.timestamp - lastTimestamp) >= interval;
        bool driftNeedsRebalance = false;

        if (driftRebalanceEnabled && address(poolInteractor) != address(0)) {
            try poolInteractor.needsTickDriftRebalance() returns (bool needed) {
                driftNeedsRebalance = needed;
            } catch {
                driftNeedsRebalance = false;
            }
        }

        upkeepNeeded = timeElapsed || driftNeedsRebalance;
        performData = checkData;
    }
/* ------------------------------ performUpKeep ----------------------------- */
    function performUpkeep(bytes calldata performData) external override {
        if (address(poolInteractor) == address(0)) revert PoolInteractorNotSet();

        bool timeElapsed = (block.timestamp - lastTimestamp) >= interval;
        bool driftNeedsRebalance = driftRebalanceEnabled && poolInteractor.needsTickDriftRebalance();

        if (!timeElapsed && !driftNeedsRebalance) {
            revert VeryFrequentUpkeep();
        }

        if (timeElapsed) {
            lastTimestamp = block.timestamp;
        }

        uint256 liquidityToUse = rebalanceLiquidity;
        if (performData.length == 32) {
            liquidityToUse = abi.decode(performData, (uint256));
        }

        uint8 previousVolatilityIndex = lastVolatilityIndex;
        (uint8 currentVolatilityIndex,) = syncVolatilityIndex();

        bool indexChanged = currentVolatilityIndex != previousVolatilityIndex;
        bool shouldRebalance = (autoRebalanceEnabled && indexChanged) || driftNeedsRebalance;

        if (shouldRebalance && liquidityToUse > 0) {
            poolInteractor.rebalance(liquidityToUse, currentVolatilityIndex);
        }
    }
}