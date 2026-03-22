// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title VaultIntegration Automation contract 
 * @author PhAnToMxSD
 * @notice This contract is designed to integrate with Chainlink Automation to trigger the volatility calculation and liquidity distribution processes in the vault system at regular intervals. It implements the AutomationCompatibleInterface, allowing it to be registered as an upkeep contract with Chainlink Automation.
 */

import {Volatility} from "./volatility_calc/volatility.sol";
import {Config} from "./helpers/config.sol";

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

interface IDepositManager {
    function deposit(uint256 usdcAmount) external payable;
    function withdraw(uint256 sharesToBurn) external;
}

interface IPositionTrackerReader {
    function slotCount() external view returns (uint256);
}

contract VaultIntegration is AutomationCompatibleInterface, Volatility {
/* --------------------------------- errors --------------------------------- */
    error VeryFrequentUpkeep();
    error NotAuthorized();
    error PoolInteractorNotSet();
    error InvalidOwnerAddress();
    error DepositManagerNotSet();
    error PositionTrackerNotSet();
    error DirectVaultCallRequired(address target);
/* -------------------------------------------------------------------------- */
/*                               state variables                              */
/* -------------------------------------------------------------------------- */
    uint public lastTimestamp;
    uint public interval = 300;
    uint8 public lastVolatilityIndex;
    address public owner;
    IPoolInteractorVolatility public poolInteractor;
    IDepositManager public depositManager;
    IPositionTrackerReader public positionTracker;
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

    function setDepositManager(address depositManagerAddress) external onlyOwner {
        depositManager = IDepositManager(depositManagerAddress);
    }

    function setPositionTracker(address positionTrackerAddress) external onlyOwner {
        positionTracker = IPositionTrackerReader(positionTrackerAddress);
    }

    function configureModules(
        address poolInteractorAddress,
        address depositManagerAddress,
        address positionTrackerAddress,
        uint256 rebalanceLiquidityAmount,
        uint256 upkeepInterval
    ) external onlyOwner {
        poolInteractor = IPoolInteractorVolatility(poolInteractorAddress);
        depositManager = IDepositManager(depositManagerAddress);
        positionTracker = IPositionTrackerReader(positionTrackerAddress);
        rebalanceLiquidity = rebalanceLiquidityAmount;
        interval = upkeepInterval;
    }

    function setSelfAsPoolUpdater() external onlyOwner {
        if (address(poolInteractor) == address(0)) revert PoolInteractorNotSet();
        poolInteractor.setVolatilityUpdater(address(this));
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert InvalidOwnerAddress();
        owner = newOwner;
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
        returns (address poolInteractorAddress, address depositManagerAddress, address positionTrackerAddress)
    {
        poolInteractorAddress = address(poolInteractor);
        depositManagerAddress = address(depositManager);
        positionTrackerAddress = address(positionTracker);
    }

    function getUserInteractionTargets() external view returns (address vaultDepositTarget, address vaultWithdrawTarget) {
        vaultDepositTarget = address(depositManager);
        vaultWithdrawTarget = address(depositManager);
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
            bool hasDepositManager,
            bool hasPositionTracker,
            bool hasRebalanceLiquidity,
            bool poolOwnerSetToVault,
            bool updaterSetToVault,
            uint256 trackerSlotCount
        )
    {
        hasPoolInteractor = address(poolInteractor) != address(0);
        hasDepositManager = address(depositManager) != address(0);
        hasPositionTracker = address(positionTracker) != address(0);
        hasRebalanceLiquidity = rebalanceLiquidity > 0;

        if (hasPoolInteractor) {
            poolOwnerSetToVault = poolInteractor.owner() == address(this);
            updaterSetToVault = poolInteractor.volatilityUpdater() == address(this);
        }

        if (hasPositionTracker) {
            trackerSlotCount = positionTracker.slotCount();
        }

        isReady =
            hasPoolInteractor &&
            hasDepositManager &&
            hasPositionTracker &&
            hasRebalanceLiquidity &&
            poolOwnerSetToVault &&
            updaterSetToVault;
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

    function previewSyncVolatilityIndex() external view returns (uint8 currentVolatilityIndex, uint256 currentVolatilityValue) {
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

    function rebalanceNow(uint256 totalLiquidityAvailable) external onlyOwner {
        if (address(poolInteractor) == address(0)) revert PoolInteractorNotSet();
        (uint8 currentVolatilityIndex,) = syncVolatilityIndex();
        poolInteractor.rebalance(totalLiquidityAvailable, currentVolatilityIndex);
    }

    function pushVolatilityIndexOnly() external onlyOwner returns (uint8 currentVolatilityIndex, uint256 currentVolatilityValue) {
        return syncVolatilityIndex();
    }

    function previewShouldRebalanceNow() external view returns (bool shouldRebalance, bool driftNeedsRebalance) {
        if (address(poolInteractor) == address(0)) revert PoolInteractorNotSet();
        driftNeedsRebalance = driftRebalanceEnabled && poolInteractor.needsTickDriftRebalance();
        bool indexChanged = getVolatilityIndex() != lastVolatilityIndex;
        shouldRebalance = (autoRebalanceEnabled && indexChanged) || driftNeedsRebalance;
    }

    function userDeposit(uint256) external payable {
        if (address(depositManager) == address(0)) revert DepositManagerNotSet();
        revert DirectVaultCallRequired(address(depositManager));
    }

    function userWithdraw(uint256) external view {
        if (address(depositManager) == address(0)) revert DepositManagerNotSet();
        revert DirectVaultCallRequired(address(depositManager));
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