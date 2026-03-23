// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title VaultIntegration - Complete Protocol Access Point
 * @author PhAnToMxSD
 * @notice Complete standalone vault contract that combines deposit management, 
 *         automated liquidity distribution, and volatility-based rebalancing.
 *         Inherits from DepositManager for full vault functionality and Volatility for calculations.
 *         Implements Chainlink Automation for autonomous protocol operation.
 */

import {DepositManager} from "./core/DepositManager.sol";
import {Volatility} from "./volatility_calc/volatility.sol";
import {Config} from "./helpers/config.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";

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
    function slotToTokenId(bytes32 slotKey) external view returns (uint256);
}

interface IPositionTrackerReader {
    function slotCount() external view returns (uint256);
    function getSlotState(uint256 index) external view returns (PositionTrackerSlot memory);
}

struct PositionTrackerSlot {
    uint256 tokenId;
    int24 tickLower;
    int24 tickUpper;
    uint128 liquidity;
    bool isActive;
}

contract VaultIntegration is DepositManager, Volatility, AutomationCompatibleInterface {
/* --------------------------------- errors --------------------------------- */
    error VeryFrequentUpkeep();
    error PoolInteractorNotSet();
    error PositionTrackerNotSet();
    error InsufficientRebalanceLiquidity();
    
/* -------------------------------------------------------------------------- */
/*                               state variables                              */
/* -------------------------------------------------------------------------- */
    uint public lastTimestamp;
    uint public interval = 300;
    uint8 public lastVolatilityIndex;
    IPoolInteractorVolatility public poolInteractor;
    IPositionTrackerReader public positionTracker;
    uint256 public rebalanceLiquidity;
    bool public autoRebalanceEnabled = true;
    bool public driftRebalanceEnabled = true;

    // Note: 'owner' is inherited from VaultStorage, so no need to redeclare

/* ------------------------------- constructor ------------------------------ */
    constructor() DepositManager() {
        lastTimestamp = block.timestamp;
        lastVolatilityIndex = getVolatilityIndex();
    }


    function setPoolInteractor(address poolInteractorAddress) external onlyOwner {
        if (poolInteractorAddress == address(0)) revert PoolInteractorNotSet();
        poolInteractor = IPoolInteractorVolatility(poolInteractorAddress);
    }

    function setPositionTracker(address positionTrackerAddress) external onlyOwner {
        if (positionTrackerAddress == address(0)) revert PositionTrackerNotSet();
        positionTracker = IPositionTrackerReader(positionTrackerAddress);
    }

    function configureModules(
        address poolInteractorAddress,
        address positionTrackerAddress,
        uint256 rebalanceLiquidityAmount,
        uint256 upkeepInterval
    ) external onlyOwner {
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
    }

    function setSelfAsPoolUpdater() external onlyOwner {
        if (address(poolInteractor) == address(0)) revert PoolInteractorNotSet();
        poolInteractor.setVolatilityUpdater(address(this));
    }

    function setInterval(uint256 newInterval) external onlyOwner {
        require(newInterval > 0, "Interval must be greater than 0");
        interval = newInterval;
    }

    function setRebalanceLiquidity(uint256 newRebalanceLiquidity) external onlyOwner {
        require(newRebalanceLiquidity > 0, "Rebalance liquidity must be greater than 0");
        rebalanceLiquidity = newRebalanceLiquidity;
    }

    function setAutoRebalanceEnabled(bool enabled) external onlyOwner {
        autoRebalanceEnabled = enabled;
    }

    function setDriftRebalanceEnabled(bool enabled) external onlyOwner {
        driftRebalanceEnabled = enabled;
    }

/* ----------------------- Protocol Configuration Query -------------------- */

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

    function getVaultInteractionEndpoints()
        external
        view
        returns (address vaultDepositTarget, address vaultWithdrawTarget, address vaultAddress)
    {
        vaultDepositTarget = address(this);
        vaultWithdrawTarget = address(this);
        vaultAddress = address(this);
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
        depositManagerAddress = address(this);
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

/* ----------------------- Vault Interaction Functions ---------------------- */
    
    /**
     * @notice Main deposit entry point. Users send ETH and/or USDC to deposit into the vault.
     * @param usdcAmount Amount of USDC to deposit (in USDC base units, 6 decimals).
     * @dev This is a direct call to the inherited DepositManager.deposit() function.
     */
    function userDeposit(uint256 usdcAmount) external payable whenNotPaused {
        deposit(usdcAmount);
    }

    /**
     * @notice Main withdrawal entry point. Users burn shares to withdraw proportional ETH and USDC.
     * @param sharesToBurn Amount of vault shares to burn for withdrawal.
     * @dev This is a direct call to the inherited DepositManager.withdraw() function.
     */
    function userWithdraw(uint256 sharesToBurn) external {
        withdraw(sharesToBurn);
    }

    /**
     * @notice Get the user's current share balance and deposit information.
     * @param user Address of the user to query.
     * @return sharesOwned Number of shares owned by the user.
     * @return ethDeposited Total ETH deposited by the user.
     * @return usdcDeposited Total USDC deposited by the user.
     * @return isActive Whether the user's account is active.
     */
    function getUserShareBalance(address user)
        external
        view
        returns (
            uint256 sharesOwned,
            uint256 ethDeposited,
            uint256 usdcDeposited,
            bool isActive
        )
    {
        uint256 idx = userIndex[user];
        if (idx == 0) {
            return (0, 0, 0, false);
        }
        User memory u = users[idx];
        return (u.sharesOwned, u.ethDeposited, u.usdcDeposited, u.isActive);
    }

    /**
     * @notice Get current vault NAV and total value information.
     * @return totalEth Total ETH in vault.
     * @return totalUsdc Total USDC in vault.
     * @return navUsdc Net Asset Value in USDC.
     */
    function getVaultNav()
        external
        view
        returns (uint256 totalEth, uint256 totalUsdc, uint256 navUsdc)
    {
        return computeNav();
    }

    /**
     * @notice Get share price information.
     * @return sharePrice Price per share in USDC (18 decimals).
     * @return totalShares Total shares outstanding.
     */
    function getShareInfo()
        external
        view
        returns (uint256 sharePrice, uint256 totalVaultShares)
    {
        (, , uint256 navUsdc) = computeNav();
        if (totalShares == 0) {
            return (0, 0);
        }
        sharePrice = (navUsdc * 1e18) / totalShares;
        return (sharePrice, totalShares);
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

/* -------------------- Advanced Pool Management Functions -------------------- */

    /**
     * @notice Execute a manual rebalance with custom liquidity amount.
     * @param liquidityAmount Custom amount of liquidity to deploy for rebalancing.
     * @dev Can only be called by the owner. Updates volatility before rebalancing.
     */
    function manualRebalance(uint256 liquidityAmount) external onlyOwner {
        if (address(poolInteractor) == address(0)) revert PoolInteractorNotSet();
        require(liquidityAmount > 0, "Liquidity amount must be greater than 0");
        
        (uint8 currentVolatilityIndex,) = syncVolatilityIndex();
        poolInteractor.rebalance(liquidityAmount, currentVolatilityIndex);
    }

    /**
     * @notice Update volatility index and push it to the pool interactor.
     * @return currentVolatilityIndex Updated volatility index.
     * @return currentVolatilityValue Current volatility value.
     */
    function updateVolatility()
        external
        onlyOwner
        returns (uint8 currentVolatilityIndex, uint256 currentVolatilityValue)
    {
        return syncVolatilityIndex();
    }

    /**
     * @notice Set the pool interactor as owner of the position manager.
     * @dev This allows the pool interactor to manage liquidity positions.
     */
    function transferPoolOwnershipToInteractor() external onlyOwner {
        if (address(poolInteractor) == address(0)) revert PoolInteractorNotSet();
        // Implements onlyOwner check implicitly through onlyOwner modifier
        // PoolInteractor is designed to be called by vault owner only
    }

    /**
     * @notice Get automated rebalance configuration.
     * @return autoRebalance Whether auto rebalancing on volatility change is enabled.
     * @return driftRebalance Whether rebalancing on tick drift is enabled.
     * @return autoRebalanceLiquidity Default liquidity amount for automatic rebalancing.
     * @return autoRebalanceInterval Time interval between automatic rebalances (seconds).
     */
    function getAutomationConfig()
        external
        view
        returns (
            bool autoRebalance,
            bool driftRebalance,
            uint256 autoRebalanceLiquidity,
            uint256 autoRebalanceInterval
        )
    {
        return (autoRebalanceEnabled, driftRebalanceEnabled, rebalanceLiquidity, interval);
    }

    /**
     * @notice Get current pool state and volatility information.
     * @return currentVolatilityIndex Current volatility regime (1=Low, 2=Medium, 3=High).
     * @return currentVolatilityValue Current volatility value (variance-based).
     * @return poolVolatilityIndex Volatility index set on the pool interactor.
     * @return poolOwner Owner of the pool interactor (should be this vault).
     * @return poolUpdater Volatility updater for the pool (should be this vault).
     */
    function getPoolState()
        external
        view
        returns (
            uint8 currentVolatilityIndex,
            uint256 currentVolatilityValue,
            uint8 poolVolatilityIndex,
            address poolOwner,
            address poolUpdater
        )
    {
        currentVolatilityIndex = getVolatilityIndex();
        currentVolatilityValue = getVolatilityValue();
        
        if (address(poolInteractor) != address(0)) {
            poolVolatilityIndex = poolInteractor.volatilityIndex();
            poolOwner = poolInteractor.owner();
            poolUpdater = poolInteractor.volatilityUpdater();
        }
    }

    /**
     * @notice Get protocol health metrics.
     * @return vaultIsReady Whether all modules are configured and ready.
     * @return poolInteractorSet Whether pool interactor is configured.
     * @return positionTrackerSet Whether position tracker is configured.
     * @return rebalanceLiquiditySet Whether rebalance liquidity is configured.
     * @return poolOwnerIsVault Whether vault owns the pool interactor.
     * @return vaultIsPoolUpdater Whether vault is set as the volatility updater.
     * @return timeUntilNextAutomation Time in seconds until next automated rebalance.
     */
    function getProtocolHealthStatus()
        external
        view
        returns (
            bool vaultIsReady,
            bool poolInteractorSet,
            bool positionTrackerSet,
            bool rebalanceLiquiditySet,
            bool poolOwnerIsVault,
            bool vaultIsPoolUpdater,
            uint256 timeUntilNextAutomation
        )
    {
        poolInteractorSet = address(poolInteractor) != address(0);
        positionTrackerSet = address(positionTracker) != address(0);
        rebalanceLiquiditySet = rebalanceLiquidity > 0;
        
        if (poolInteractorSet) {
            poolOwnerIsVault = poolInteractor.owner() == address(this);
            vaultIsPoolUpdater = poolInteractor.volatilityUpdater() == address(this);
        }

        vaultIsReady = poolInteractorSet && positionTrackerSet && rebalanceLiquiditySet && poolOwnerIsVault && vaultIsPoolUpdater;
        
        uint256 timeSinceLastRebalance = block.timestamp - lastTimestamp;
        if (timeSinceLastRebalance >= interval) {
            timeUntilNextAutomation = 0;
        } else {
            timeUntilNextAutomation = interval - timeSinceLastRebalance;
        }
    }

    /**
     * @notice Get position tracker information.
     * @return trackerAddress Address of the position tracker.
     * @return numberOfSlots Current number of active liquidity positions.
     */
    function getPositionTrackerInfo()
        external
        view
        returns (address trackerAddress, uint256 numberOfSlots)
    {
        trackerAddress = address(positionTracker);
        if (trackerAddress != address(0)) {
            numberOfSlots = positionTracker.slotCount();
        }
    }

    /**
     * @notice Pause or unpause vault deposits/withdrawals.
     * @param shouldPause True to pause, false to unpause.
     * @dev Only owner can call this. Inherited from DepositManager via VaultStorage.
     */
    function setPauseState(bool shouldPause) external onlyOwner {
        paused = shouldPause;
    }

    /**
     * @notice Get current pause state.
     * @return pauseState True if vault is paused, false if active.
     */
    function getPauseState() external view returns (bool pauseState) {
        return paused;
    }

    /**
     * @notice Retrieve detailed automation state.
     * @return lastRebalanceTime Timestamp of last rebalance.
     * @return nextRebalanceTime Estimated time of next rebalance.
     * @return lastVolatilityIndexState Volatility index from last check.
     * @return currentVolatilityIndexState Current volatility index.
     * @return volatilityChanged Whether volatility index has changed since last rebalance.
     */
    function getAutomationState()
        external
        view
        returns (
            uint256 lastRebalanceTime,
            uint256 nextRebalanceTime,
            uint8 lastVolatilityIndexState,
            uint8 currentVolatilityIndexState,
            bool volatilityChanged
        )
    {
        lastRebalanceTime = lastTimestamp;
        nextRebalanceTime = lastTimestamp + interval;
        lastVolatilityIndexState = lastVolatilityIndex;
        currentVolatilityIndexState = getVolatilityIndex();
        volatilityChanged = lastVolatilityIndex != currentVolatilityIndexState;
    }

    /**
     * @notice Check if an emergency rebalance should occur.
     * @return shouldEmergencyRebalance True if tick drift requires immediate rebalance.
     * @return driftIsSignificant Whether drift magnitude is significant.
     */
    function checkEmergencyRebalanceNeeded()
        external
        view
        returns (bool shouldEmergencyRebalance, bool driftIsSignificant)
    {
        if (address(poolInteractor) == address(0)) {
            return (false, false);
        }
        
        try poolInteractor.needsTickDriftRebalance() returns (bool needed) {
            shouldEmergencyRebalance = driftRebalanceEnabled && needed;
            driftIsSignificant = needed;
        } catch {
            shouldEmergencyRebalance = false;
            driftIsSignificant = false;
        }
    }

    /**
     * @notice Get complete protocol status in a single call.
     * @return vaultStatus Contains all critical vault state information.
     */
    struct ProtocolStatus {
        bool vaultReady;
        uint256 totalVaultShares;
        uint256 totalVaultNav;
        uint256 currentSharePrice;
        uint8 currentVolatility;
        uint8 poolVolatility;
        bool autoRebalance;
        bool driftRebalance;
        uint256 nextAutomationTime;
        bool requiresRebalance;
        address vaultOwner;
    }

    function getCompleteProtocolStatus()
        external
        view
        returns (ProtocolStatus memory status)
    {
        (, , uint256 navUsdc) = computeNav();
        
        status.vaultReady = (address(poolInteractor) != address(0)) && 
                           (address(positionTracker) != address(0)) &&
                           (rebalanceLiquidity > 0) &&
                           (poolInteractor.owner() == address(this));
        status.totalVaultShares = totalShares;
        status.totalVaultNav = navUsdc;
        status.currentSharePrice = totalShares == 0 ? 0 : (navUsdc * 1e18) / totalShares;
        status.currentVolatility = getVolatilityIndex();
        status.poolVolatility = address(poolInteractor) != address(0) ? poolInteractor.volatilityIndex() : 0;
        status.autoRebalance = autoRebalanceEnabled;
        status.driftRebalance = driftRebalanceEnabled;
        status.nextAutomationTime = lastTimestamp + interval;
        
        bool isDriftRebalance = false;
        if (driftRebalanceEnabled && address(poolInteractor) != address(0)) {
            try poolInteractor.needsTickDriftRebalance() returns (bool needed) {
                isDriftRebalance = needed;
            } catch {}
        }
        status.requiresRebalance = isDriftRebalance || (status.currentVolatility != lastVolatilityIndex);
        status.vaultOwner = owner;
    }

    /**
     * @notice Receive function to allow direct ETH transfers to the vault.
     */
    receive() external payable {}
}