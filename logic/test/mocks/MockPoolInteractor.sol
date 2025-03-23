// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

contract MockPoolInteractor {
    struct SlotDistribution {
        int24 lowerTick;
        int24 upperTick;
        uint256 liquidityAmount;
    }

    uint8 public volatilityIndex;
    address public volatilityUpdater;
    uint256 public lastRebalanceTimestamp;
    uint256 public MIN_REBALANCE_INTERVAL;
    address public owner;
    bool public driftNeeded;
    int24 public simulatedCurrentTick;

    uint256 public rebalanceCallCount;
    uint256 public lastRebalanceLiquidity;
    uint256 public lastRebalanceVolatility;

    SlotDistribution[] private previousDistribution;
    SlotDistribution[] private currentDistribution;

    constructor() {
        owner = msg.sender;
    }

    function setOwner(address newOwner) external {
        owner = newOwner;
    }

    function setDriftNeeded(bool needed) external {
        driftNeeded = needed;
    }

    function setMinRebalanceInterval(uint256 interval) external {
        MIN_REBALANCE_INTERVAL = interval;
    }

    function setLastRebalanceTimestamp(uint256 ts) external {
        lastRebalanceTimestamp = ts;
    }

    function setCurrentTick(int24 newTick) external {
        simulatedCurrentTick = newTick;
    }

    function setVolatilityIndex(uint8 newVolatilityIndex) external {
        volatilityIndex = newVolatilityIndex;
    }

    function setVolatilityUpdater(address updater) external {
        volatilityUpdater = updater;
    }

    function rebalance(uint256 totalLiquidityAvailable, uint256 _volatilityIndex) external {
        rebalanceCallCount += 1;
        lastRebalanceLiquidity = totalLiquidityAvailable;
        lastRebalanceVolatility = _volatilityIndex;
        lastRebalanceTimestamp = block.timestamp;

        _snapshotCurrentAsPrevious();
        _recomputeDistribution(totalLiquidityAvailable, _volatilityIndex);
    }

    function needsTickDriftRebalance() external view returns (bool) {
        return driftNeeded;
    }

    function getCurrentDistributionLength() external view returns (uint256) {
        return currentDistribution.length;
    }

    function getPreviousDistributionLength() external view returns (uint256) {
        return previousDistribution.length;
    }

    function getCurrentDistributionAt(uint256 index) external view returns (int24 lowerTick, int24 upperTick, uint256 liquidityAmount) {
        SlotDistribution memory slot = currentDistribution[index];
        return (slot.lowerTick, slot.upperTick, slot.liquidityAmount);
    }

    function getPreviousDistributionAt(uint256 index) external view returns (int24 lowerTick, int24 upperTick, uint256 liquidityAmount) {
        SlotDistribution memory slot = previousDistribution[index];
        return (slot.lowerTick, slot.upperTick, slot.liquidityAmount);
    }

    function _snapshotCurrentAsPrevious() internal {
        delete previousDistribution;
        for (uint256 i = 0; i < currentDistribution.length; i++) {
            previousDistribution.push(currentDistribution[i]);
        }
    }

    function _recomputeDistribution(uint256 totalLiquidityAvailable, uint256 volIndex) internal {
        delete currentDistribution;

        if (volIndex < 1 || volIndex > 3) {
            return;
        }

        uint256 deployableLiquidity = totalLiquidityAvailable - ((totalLiquidityAvailable * 1000) / 10000);
        uint256 slotCount = 3 + (volIndex - 1) * 2;
        if (slotCount == 0) {
            return;
        }

        int24 alignedTick = _alignTick(simulatedCurrentTick);
        int24 centerIndex = int24(int256((slotCount - 1) / 2));
        uint256 basePerSlot = deployableLiquidity / slotCount;
        uint256 dust = deployableLiquidity - (basePerSlot * slotCount);

        for (uint256 i = 0; i < slotCount; i++) {
            int24 offset = int24(int256(i)) - centerIndex;
            uint256 liquidityAmount = basePerSlot;
            if (i == slotCount / 2) {
                liquidityAmount += dust;
            }

            int24 lowerTick = alignedTick + (offset * 60);
            int24 upperTick = lowerTick + 60;

            currentDistribution.push(
                SlotDistribution({lowerTick: lowerTick, upperTick: upperTick, liquidityAmount: liquidityAmount})
            );
        }
    }

    function _alignTick(int24 tick) internal pure returns (int24) {
        int24 spacing = 60;
        int24 compressed = tick / spacing;
        if (tick < 0 && tick % spacing != 0) {
            compressed--;
        }
        return compressed * spacing;
    }
}
