// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {VaultIntegration} from "../src/VaultIntegration.sol";
import {Config} from "../src/helpers/config.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";
import {IChainlinkAggregatorV3} from "../src/interfaces/IChainlinkAggregatorV3.sol";
import {MockPoolInteractor} from "./mocks/MockPoolInteractor.sol";
import {MockPositionTracker} from "./mocks/MockPositionTracker.sol";

contract VaultRebalancerLocalTest is Test {
    event DistributionSnapshot(string phase, uint256 slotIndex, int24 lowerTick, int24 upperTick, uint256 liquidityAmount);

    VaultIntegration internal vault;
    MockPoolInteractor internal mockInteractor;
    MockPositionTracker internal mockTracker;

    address internal user = makeAddr("user");
    address internal keeper = makeAddr("keeper");

    uint160 internal constant SQRT_PRICE_X96_TICK0 = 79228162514264337593543950336;

    function setUp() external {
        _mockPoolAndOracle(SQRT_PRICE_X96_TICK0, int24(0));

        vault = new VaultIntegration();
        mockInteractor = new MockPoolInteractor();
        mockTracker = new MockPositionTracker();
        mockTracker.setSlotCount(3);

        vault.configureModules(address(mockInteractor), address(mockTracker), 1, 300);
        vault.setSelfAsPoolUpdater();

        vm.deal(user, 10 ether);
    }

    function test_engineReadiness_afterConfigureModules() external view {
        (bool isReady, bool hasPoolInteractor, bool hasPositionTracker, bool hasRebalanceLiquidity, bool updaterSetToVault,) =
            vault.getEngineReadiness();

        assertTrue(isReady);
        assertTrue(hasPoolInteractor);
        assertTrue(hasPositionTracker);
        assertTrue(hasRebalanceLiquidity);
        assertTrue(updaterSetToVault);
    }

    function test_checkUpkeepAndPerformUpkeep_timeElapsed_callsRebalance() external {
        _depositEthOnly(user, 1 ether);
        uint256 beforeCalls = mockInteractor.rebalanceCallCount();
        _advanceForVolatilitySync();

        vm.prank(keeper);
        (bool needed,) = vault.checkUpkeep("");
        assertTrue(needed);

        vm.prank(keeper);
        vault.performUpkeep("");

        assertEq(mockInteractor.rebalanceCallCount(), beforeCalls + 1);

        (, , uint256 navUsdc) = vault.previewNav();
        uint256 expectedLiquidity = (navUsdc * vault.REBALANCE_TARGET_BPS()) / vault.BPS_DENOMINATOR();
        assertEq(mockInteractor.lastRebalanceLiquidity(), expectedLiquidity);
        assertEq(vault.lastTimestamp(), block.timestamp);
    }

    function test_performUpkeep_revertsWhenTooFrequent() external {
        _depositEthOnly(user, 1 ether);

        vm.expectRevert(VaultIntegration.VeryFrequentUpkeep.selector);
        vault.performUpkeep("");
    }

    function test_executeEngineCycle_driftTrigger_callsRebalance() external {
        _depositEthOnly(user, 1 ether);
        uint256 beforeCalls = mockInteractor.rebalanceCallCount();
        _advanceForVolatilitySync();
        mockInteractor.setDriftNeeded(true);

        vault.executeEngineCycle();

        assertEq(mockInteractor.rebalanceCallCount(), beforeCalls + 1);
        assertGt(mockInteractor.lastRebalanceLiquidity(), 0);
    }

    function test_deposit_triggersEventRebalance_whenIntervalAllows() external {
        mockInteractor.setMinRebalanceInterval(0);

        vm.prank(user);
        vault.deposit{value: 1 ether}(0);

        assertEq(mockInteractor.rebalanceCallCount(), 2);
        assertGt(mockInteractor.lastRebalanceLiquidity(), 0);
    }

    function test_checkUpkeep_driftOnly_returnsTrue() external {
        _depositEthOnly(user, 1 ether);
        mockInteractor.setDriftNeeded(true);

        vm.prank(keeper);
        (bool needed,) = vault.checkUpkeep("");
        assertTrue(needed);
    }

    function test_demo_rebalancerDistribution_beforeAfterVolatilityChange() external {
        uint256 totalLiquidity = 9_000_000;
        uint256 expectedDeployable = totalLiquidity - ((totalLiquidity * 1000) / 10000);

        console2.log("================ DEMO: REBALANCER DISTRIBUTION SHIFT ================");
        console2.log("totalLiquidityInput", totalLiquidity);
        console2.log("bufferBps", uint256(1000));
        console2.log("expectedDeployableLiquidity", expectedDeployable);

        mockInteractor.setCurrentTick(120);
        console2.log("before.currentTick", uint256(120));
        mockInteractor.rebalance(totalLiquidity, 1);

        uint256 previousSlots = mockInteractor.getCurrentDistributionLength();
        assertEq(previousSlots, 3);
        console2.log("before.volatilityIndex", uint256(1));
        console2.log("before.slotCount", previousSlots);

        uint256 previousDistributed = _emitAndSumCurrentDistribution("before-vol-change");
        uint256 expectedBefore = expectedDeployable;
        assertEq(previousDistributed, expectedBefore);
        console2.log("before.totalDistributed", previousDistributed);

        mockInteractor.setCurrentTick(360);
        console2.log("after.currentTick", uint256(360));
        mockInteractor.rebalance(totalLiquidity, 3);

        uint256 currentSlots = mockInteractor.getCurrentDistributionLength();
        assertEq(currentSlots, 7);
        console2.log("after.volatilityIndex", uint256(3));
        console2.log("after.slotCount", currentSlots);

        uint256 copiedPrevSlots = mockInteractor.getPreviousDistributionLength();
        assertEq(copiedPrevSlots, 3);
        console2.log("copiedPrev.slotCount", copiedPrevSlots);

        uint256 copiedPrevDistributed = _emitAndSumPreviousDistribution("copied-previous-after-rebalance");
        assertEq(copiedPrevDistributed, expectedBefore);
        console2.log("copiedPrev.totalDistributed", copiedPrevDistributed);

        uint256 currentDistributed = _emitAndSumCurrentDistribution("after-vol-change");
        uint256 expectedAfter = expectedDeployable;
        assertEq(currentDistributed, expectedAfter);
        console2.log("after.totalDistributed", currentDistributed);

        (int24 firstLowerBefore,,) = mockInteractor.getPreviousDistributionAt(0);
        (int24 firstLowerAfter,,) = mockInteractor.getCurrentDistributionAt(0);
        assertTrue(firstLowerAfter > firstLowerBefore);
        console2.log("firstLowerTick.before", int256(firstLowerBefore));
        console2.log("firstLowerTick.after", int256(firstLowerAfter));
        console2.log("firstLowerTick.delta", int256(firstLowerAfter - firstLowerBefore));

        (, , uint256 centerBefore) = mockInteractor.getPreviousDistributionAt(copiedPrevSlots / 2);
        (, , uint256 centerAfter) = mockInteractor.getCurrentDistributionAt(currentSlots / 2);
        assertTrue(centerAfter < centerBefore);
        console2.log("centerSlotLiquidity.before", centerBefore);
        console2.log("centerSlotLiquidity.after", centerAfter);
        console2.log("centerSlotLiquidity.delta", int256(centerAfter) - int256(centerBefore));
        console2.log("=====================================================================");
    }

    function _depositEthOnly(address depositor, uint256 ethAmount) internal {
        vm.prank(depositor);
        vault.deposit{value: ethAmount}(0);
    }

    function _advanceForVolatilitySync() internal {
        vm.warp(block.timestamp + Config.TMIN + 1);
        vm.roll(block.number + 1);
    }

    function _emitAndSumCurrentDistribution(string memory phase) internal returns (uint256 sum) {
        uint256 len = mockInteractor.getCurrentDistributionLength();
        for (uint256 i = 0; i < len; i++) {
            (int24 lowerTick, int24 upperTick, uint256 liquidityAmount) = mockInteractor.getCurrentDistributionAt(i);
            emit DistributionSnapshot(phase, i, lowerTick, upperTick, liquidityAmount);
            console2.log(phase);
            console2.log("slotIndex", i);
            console2.log("lowerTick", int256(lowerTick));
            console2.log("upperTick", int256(upperTick));
            console2.log("liquidityAmount", liquidityAmount);
            sum += liquidityAmount;
        }
    }

    function _emitAndSumPreviousDistribution(string memory phase) internal returns (uint256 sum) {
        uint256 len = mockInteractor.getPreviousDistributionLength();
        for (uint256 i = 0; i < len; i++) {
            (int24 lowerTick, int24 upperTick, uint256 liquidityAmount) = mockInteractor.getPreviousDistributionAt(i);
            emit DistributionSnapshot(phase, i, lowerTick, upperTick, liquidityAmount);
            console2.log(phase);
            console2.log("slotIndex", i);
            console2.log("lowerTick", int256(lowerTick));
            console2.log("upperTick", int256(upperTick));
            console2.log("liquidityAmount", liquidityAmount);
            sum += liquidityAmount;
        }
    }

    function _mockPoolAndOracle(uint160 sqrtPriceX96, int24 tick) internal {
        PoolId poolId = Config.poolId();
        bytes32 stateSlot = keccak256(abi.encodePacked(PoolId.unwrap(poolId), bytes32(uint256(6))));

        uint24 tickBits = uint24(uint32(int32(tick)));
        uint256 packed =
            uint256(sqrtPriceX96)
            | (uint256(tickBits) << 160)
            | (uint256(uint24(0)) << 184)
            | (uint256(uint24(0)) << 208);

        vm.mockCall(
            Config.POOL_MANAGER_ADDRESS,
            abi.encodeWithSelector(bytes4(keccak256("extsload(bytes32)")), stateSlot),
            abi.encode(bytes32(packed))
        );

        vm.mockCall(
            Config.CHAINLINK_ETH_USD_FEED,
            abi.encodeWithSelector(IChainlinkAggregatorV3.latestRoundData.selector),
            abi.encode(uint80(1), int256(3000e8), uint256(0), block.timestamp, uint80(1))
        );

        vm.mockCall(
            Config.CHAINLINK_ETH_USD_FEED,
            abi.encodeWithSelector(IChainlinkAggregatorV3.decimals.selector),
            abi.encode(uint8(8))
        );
    }
}
