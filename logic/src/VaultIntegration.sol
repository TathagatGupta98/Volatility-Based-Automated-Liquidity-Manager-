// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DepositManager} from "./core/DepositManager.sol";
import {Config} from "./helpers/config.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";

interface AutomationCompatibleInterface {
    function checkUpkeep(bytes calldata checkData)
        external
        returns (bool upkeepNeeded, bytes memory performData);

    function performUpkeep(bytes calldata performData) external;
}

interface IPoolInteractorVolatility {
    function setVolatilityIndex(uint8 newVolatilityIndex) external;
    function setVolatilityUpdater(address updater) external;
    function rebalance(uint256 totalLiquidityAvailable, uint256 _volatilityIndex) external;
    function needsTickDriftRebalance() external view returns (bool);
    function owner() external view returns (address);
    function volatilityUpdater() external view returns (address);
    function volatilityIndex() external view returns (uint8);
}

interface IPositionTrackerReader {
    function slotCount() external view returns (uint256);
}

contract VaultIntegration is DepositManager, AutomationCompatibleInterface {
    using StateLibrary for IPoolManager;

    error VeryFrequentUpkeep();
    error PoolInteractorNotSet();
    error PositionTrackerNotSet();
    error flashLoanAttack();

    uint256 public lastTimestamp;
    uint256 public interval = 300;
    uint8 public lastVolatilityIndex;

    IPoolInteractorVolatility public poolInteractor;
    IPositionTrackerReader public positionTracker;

    uint256 public rebalanceLiquidity = 1;
    bool public autoRebalanceEnabled = true;
    bool public driftRebalanceEnabled = true;

    uint256 private volatilityCalculated;
    int24 private volatilityLastTick;
    uint256 private volatilityLastObservationBlock;
    uint8 private volatilityIndexState;

    constructor() DepositManager() {
        (, int24 tick,,) = StateLibrary.getSlot0(Config.poolManager, Config.poolId());

        lastTimestamp = block.timestamp;
        volatilityLastTick = tick;
        lastObservationTimestamp = block.timestamp;
        volatilityLastObservationBlock = block.number;
        ewmaVariance = 0;
        volatilityIndexState = Config.LOW_VOLATILITY;
        lastVolatilityIndex = volatilityIndexState;
        paused = false;
    }

    function calculateVolatility() public {
        (, int24 currentTick,,) = StateLibrary.getSlot0(Config.poolManager, Config.poolId());

        uint256 currentTimestamp = block.timestamp;
        uint256 currentBlock = block.number;

        int24 delta = currentTick - volatilityLastTick;

        uint8 errorCode = _checkFlashLoanProtection(delta, currentTimestamp, currentBlock);

        if (errorCode != 0 && errorCode != 1) {
            revert flashLoanAttack();
        } else if (errorCode == 1) {
            delta = 150;
        }

        _calculateEwmaVariance(delta);
        volatilityCalculated = _calculateVolatilityValue();
        _updateVolatilityIndexValue(volatilityCalculated);

        volatilityLastTick = currentTick;
        lastObservationTimestamp = currentTimestamp;
        volatilityLastObservationBlock = currentBlock;
    }

    function getVolatilityIndex() public view returns (uint8) {
        return volatilityIndexState;
    }

    function getVolatilityValue() public view returns (uint256) {
        return volatilityCalculated;
    }

    function _checkFlashLoanProtection(
        int24 delta,
        uint256 time,
        uint256 bnum
    ) internal view returns (uint8 errorCode) {
        if (bnum <= volatilityLastObservationBlock) {
            return 10;
        } else if (time <= lastObservationTimestamp + Config.TMIN) {
            return 11;
        } else if (delta > 150 || delta < -150) {
            return 1;
        } else {
            return 0;
        }
    }

    function _calculateEwmaVariance(int24 delta) internal {
        int256 delta256 = int256(delta);
        uint256 returnSquareScaled = uint256(delta256 * delta256) * Config.LNSQ_1E18;
        ewmaVariance = Config.LAMBDA * ewmaVariance + Config.ONE_MINUS_LAMBDA * returnSquareScaled;
        ewmaVariance = ewmaVariance / 1e18;
    }

    function _calculateVolatilityValue() internal view returns (uint256 volatility) {
        return _sqrt(ewmaVariance) * 1e9;
    }

    function _updateVolatilityIndexValue(uint256 volatility) internal {
        if (volatility < 2000000000000000) {
            volatilityIndexState = Config.LOW_VOLATILITY;
        } else if (volatility < 7000000000000000) {
            volatilityIndexState = Config.MEDIUM_VOLATILITY;
        } else {
            volatilityIndexState = Config.HIGH_VOLATILITY;
        }
    }

    function _sqrt(uint256 x) internal pure returns (uint256 y) {
        if (x == 0) return 0;
        uint256 z = (x + 1) / 2;
        y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }

    function setPoolInteractor(address poolInteractorAddress) external {
        if (poolInteractorAddress == address(0)) revert PoolInteractorNotSet();
        poolInteractor = IPoolInteractorVolatility(poolInteractorAddress);
    }

    function setPositionTracker(address positionTrackerAddress) external {
        if (positionTrackerAddress == address(0)) revert PositionTrackerNotSet();
        positionTracker = IPositionTrackerReader(positionTrackerAddress);
    }

    function configureModules(
        address poolInteractorAddress,
        address positionTrackerAddress,
        uint256 rebalanceLiquidityAmount,
        uint256 upkeepInterval
    ) external {
        if (poolInteractorAddress != address(0)) {
            poolInteractor = IPoolInteractorVolatility(poolInteractorAddress);
        }
        if (positionTrackerAddress != address(0)) {
            positionTracker = IPositionTrackerReader(positionTrackerAddress);
        }
        if (rebalanceLiquidityAmount > 0) {
            rebalanceLiquidity = rebalanceLiquidityAmount;
        }
        if (upkeepInterval > 0) {
            interval = upkeepInterval;
        }

        autoRebalanceEnabled = true;
        driftRebalanceEnabled = true;
        paused = false;
    }

    function turnEverythingOn(uint256 rebalanceLiquidityAmount, uint256 upkeepInterval) external {
        autoRebalanceEnabled = true;
        driftRebalanceEnabled = true;
        paused = false;

        if (rebalanceLiquidityAmount > 0) {
            rebalanceLiquidity = rebalanceLiquidityAmount;
        }
        if (upkeepInterval > 0) {
            interval = upkeepInterval;
        }

        if (address(poolInteractor) != address(0)) {
            poolInteractor.setVolatilityUpdater(address(this));
        }
    }

    function setSelfAsPoolUpdater() external {
        if (address(poolInteractor) == address(0)) revert PoolInteractorNotSet();
        poolInteractor.setVolatilityUpdater(address(this));
    }

    function setInterval(uint256 newInterval) external {
        require(newInterval > 0, "Interval must be greater than 0");
        interval = newInterval;
    }

    function setRebalanceLiquidity(uint256 newRebalanceLiquidity) external {
        require(newRebalanceLiquidity > 0, "Rebalance liquidity must be greater than 0");
        rebalanceLiquidity = newRebalanceLiquidity;
    }

    function setAutoRebalanceEnabled(bool enabled) external {
        autoRebalanceEnabled = enabled;
    }

    function setDriftRebalanceEnabled(bool enabled) external {
        driftRebalanceEnabled = enabled;
    }

    function unpauseVault() external {
        paused = false;
    }

    function getProtocolCoreAddresses()
        external
        pure
        returns (
            address poolManagerAddress,
            address positionManagerAddress,
            address permit2Address,
            address usdcAddress
        )
    {
        poolManagerAddress = Config.POOL_MANAGER_ADDRESS;
        positionManagerAddress = Config.POSITION_MANAGER_ADDRESS;
        permit2Address = Config.PERMIT2_ADDRESS;
        usdcAddress = Config.USDC_ADDRESS;
    }

    function getModuleAddresses()
        external
        view
        returns (address poolInteractorAddress, address vaultAddress, address positionTrackerAddress)
    {
        poolInteractorAddress = address(poolInteractor);
        vaultAddress = address(this);
        positionTrackerAddress = address(positionTracker);
    }

    function getUserInteractionTargets() external view returns (address vaultDepositTarget, address vaultWithdrawTarget) {
        vaultDepositTarget = address(this);
        vaultWithdrawTarget = address(this);
    }

    function getVolatilitySnapshot()
        external
        view
        returns (
            uint8 currentVolatilityIndex,
            uint256 currentVolatilityValue,
            uint8 lowIndex,
            uint8 mediumIndex,
            uint8 highIndex
        )
    {
        currentVolatilityIndex = getVolatilityIndex();
        currentVolatilityValue = getVolatilityValue();
        lowIndex = uint8(Config.LOW_VOLATILITY);
        mediumIndex = uint8(Config.MEDIUM_VOLATILITY);
        highIndex = uint8(Config.HIGH_VOLATILITY);
    }

    function getEngineReadiness()
        external
        view
        returns (
            bool isReady,
            bool hasPoolInteractor,
            bool hasPositionTracker,
            bool hasRebalanceLiquidity,
            bool updaterSetToVault,
            uint256 trackerSlotCount
        )
    {
        hasPoolInteractor = address(poolInteractor) != address(0);
        hasPositionTracker = address(positionTracker) != address(0);
        hasRebalanceLiquidity = rebalanceLiquidity > 0;

        if (hasPoolInteractor) {
            updaterSetToVault = poolInteractor.volatilityUpdater() == address(this);
        }

        if (hasPositionTracker) {
            trackerSlotCount = positionTracker.slotCount();
        }

        isReady = hasPoolInteractor && hasPositionTracker && hasRebalanceLiquidity && updaterSetToVault;
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

    function previewSyncVolatilityIndex()
        external
        view
        returns (uint8 currentVolatilityIndex, uint256 currentVolatilityValue)
    {
        currentVolatilityIndex = getVolatilityIndex();
        currentVolatilityValue = getVolatilityValue();
    }

    function getIntegrationStatus()
        external
        view
        returns (
            bool poolInteractorConfigured,
            bool canVaultUpdateVolatilityIndex,
            bool canVaultCallRebalance,
            uint8 configuredPoolVolatilityIndex,
            bool driftNeedsRebalance,
            uint256 configuredRebalanceLiquidity,
            uint256 configuredInterval
        )
    {
        poolInteractorConfigured = address(poolInteractor) != address(0);
        configuredRebalanceLiquidity = rebalanceLiquidity;
        configuredInterval = interval;

        if (!poolInteractorConfigured) {
            return (false, false, false, 0, false, configuredRebalanceLiquidity, configuredInterval);
        }

        address poolOwner = poolInteractor.owner();
        address updater = poolInteractor.volatilityUpdater();
        configuredPoolVolatilityIndex = poolInteractor.volatilityIndex();

        canVaultUpdateVolatilityIndex = updater == address(this) || poolOwner == address(this);
        canVaultCallRebalance = poolOwner == address(this);

        try poolInteractor.needsTickDriftRebalance() returns (bool needed) {
            driftNeedsRebalance = needed;
        } catch {
            driftNeedsRebalance = false;
        }
    }

    function rebalanceNow(uint256 totalLiquidityAvailable) external {
        if (address(poolInteractor) == address(0)) revert PoolInteractorNotSet();
        (uint8 currentVolatilityIndex,) = syncVolatilityIndex();
        poolInteractor.rebalance(totalLiquidityAvailable, currentVolatilityIndex);
    }

    function pushVolatilityIndexOnly()
        external
        returns (uint8 currentVolatilityIndex, uint256 currentVolatilityValue)
    {
        return syncVolatilityIndex();
    }

    function previewShouldRebalanceNow() external view returns (bool shouldRebalance, bool driftNeedsRebalance) {
        if (address(poolInteractor) == address(0)) revert PoolInteractorNotSet();
        driftNeedsRebalance = driftRebalanceEnabled && poolInteractor.needsTickDriftRebalance();
        bool indexChanged = getVolatilityIndex() != lastVolatilityIndex;
        shouldRebalance = (autoRebalanceEnabled && indexChanged) || driftNeedsRebalance;
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

    function executeEngineCycleWithLiquidity(uint256 liquidityToUse) external {
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

        if (shouldRebalance && liquidityToUse > 0) {
            poolInteractor.rebalance(liquidityToUse, currentVolatilityIndex);
        }
    }

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
