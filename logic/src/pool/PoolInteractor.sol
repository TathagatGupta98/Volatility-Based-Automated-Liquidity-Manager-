//SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {Actions} from "v4-periphery/src/libraries/Actions.sol";
import {IERC20} from "v4-core/lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "v4-core/lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {PositionTracker} from "./PositionTracker.sol";
import {LiquidityDistributor} from "./LiquidityDistributor.sol";
import {DistributionMath} from "../libraries/DistributionMath.sol";
import {Config} from "../helpers/config.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {IUnlockCallback} from "v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {SwapParams} from "v4-core/src/types/PoolOperation.sol";

contract PoolInteractor is IUnlockCallback {
    using SafeERC20     for IERC20;
    using PoolIdLibrary for PoolKey;
    using StateLibrary  for IPoolManager;

    /* --------------------------------- errors --------------------------------- */
    error NotAuthorized();
    error RebalanceTooSoon();
    error SwapSlippageExceeded();
    error InsufficientBuffer();
    error InvalidVolatilityIndex();
    error NotUpdater();

    /* --------------------------------- state ---------------------------------- */
    IPositionManager public immutable positionManager;
    IPoolManager     public immutable poolManager;
    PositionTracker  public immutable positionTracker;
    address          public immutable USDC;
    address          public owner;
    address          public volatilityUpdater;

    uint256 public constant BUFFER_BPS = 1000; // 10% buffer
    uint256 public constant BPS_DENOM  = 10000;
    uint256 public constant SWAP_THRESHOLD_BPS = 8500; // swap when 85%+ is single token
    uint256 public constant MIN_REBALANCE_INTERVAL = 60; // seconds
    uint256 public lastRebalanceTimestamp;

    uint256 public idleEth;
    uint256 public idleUsdc;
    uint8   public volatilityIndex;

    struct Slot {
        int24 lowerTick;
        int24 upperTick;
    }

    mapping(bytes32 => uint256) public slotToTokenId;

    enum Action {
        SKIP,
        MINT,
        INCREASE,
        DECREASE,
        DECREASE_TO_ZERO,
        RESTAKE,
        REACTIVATE
    }

    struct SlotDecision {
        Action  action;
        uint256 tokenId;
        uint128 currentLiq;
        uint128 targetLiq;
        int24   tickLower;
        int24   tickUpper;
    }

    /* -------------------------------- modifiers ------------------------------- */
    modifier onlyOwner() {
        if (msg.sender != owner) revert NotAuthorized();
        _;
    }

    modifier onlyOwnerOrUpdater() {
        if (msg.sender != owner && msg.sender != volatilityUpdater) revert NotUpdater();
        _;
    }

    /* ------------------------------- constructor ------------------------------ */
    constructor(address _positionTracker) {
        poolManager     = Config.poolManager;
        positionManager = Config.positionManager;
        USDC            = Config.USDC_ADDRESS;
        positionTracker = PositionTracker(_positionTracker);
        owner           = msg.sender;
        volatilityIndex = Config.DEFAULT_VOLATILITY_INDEX;
    }

    function setVolatilityUpdater(address updater) external onlyOwner {
        volatilityUpdater = updater;
    }

    function setVolatilityIndex(uint8 newVolatilityIndex) external onlyOwnerOrUpdater {
        if (newVolatilityIndex < 1 || newVolatilityIndex > 3) {
            revert InvalidVolatilityIndex();
        }
        volatilityIndex = newVolatilityIndex;
    }

    /* -------------------------------------------------------------------------- */
    /*                              REBALANCE ENTRY                               */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Main rebalance function. Called by VaultIntegration when volatility
     *         changes OR when the current tick drifts outside the center slot.
     * @param totalLiquidityAvailable Total liquidity (in token units) the vault
     *        wants deployed *after* the 10% buffer is separated.
     */
    function rebalance(uint256 totalLiquidityAvailable, uint256 _volatilityIndex) external onlyOwner {
        if (block.timestamp < lastRebalanceTimestamp + MIN_REBALANCE_INTERVAL) {
            revert RebalanceTooSoon();
        }

        if (_volatilityIndex < 1 || _volatilityIndex > 3) {
            revert InvalidVolatilityIndex();
        }
        // forge-lint: disable-next-line(unsafe-typecast)
        volatilityIndex = uint8(_volatilityIndex);

        // --- Step 0: rebalance idle buffer if token ratio is skewed ---
        _rebalanceIdleBuffer();

        // --- Step 1: separate 10% buffer ---
        uint256 bufferAmount   = (totalLiquidityAvailable * BUFFER_BPS) / BPS_DENOM;
        uint256 deployableLiq  = totalLiquidityAvailable - bufferAmount;

        // --- Step 2: read current tick & use passed volatility index ---
        (, int24 currentTick,,) = poolManager.getSlot0(Config.poolId());
        uint256 volIndex = volatilityIndex;

        // --- Step 3: compute number of slots from volatility ---
        uint256 numSlots = 3 + (volIndex - 1) * 2;
        // LOW=1 -> 3 slots, MEDIUM=2 -> 5 slots, HIGH=3 -> 7 slots

        // --- Step 4: build equal-weight array & distribute liquidity ---
        uint256[] memory weights = _buildEqualWeights(numSlots);
        uint256[] memory liqPerSlot = DistributionMath.Distribute(deployableLiq, weights);

        // --- Step 5: compute tick ranges for each slot ---
        int24 currentLowerTick = _alignTick(currentTick);

        SlotDecision[] memory decisions = new SlotDecision[](numSlots);

        for (uint256 i = 0; i < numSlots; i++) {
            // forge-lint: disable-next-line(unsafe-typecast)
            int24 offset    = int24(int256(i)) - int24(int256(numSlots - 1) / 2);
            int24 tickLower = currentLowerTick + offset * Config.TICK_SPACING;
            int24 tickUpper = tickLower + Config.TICK_SPACING;

            bytes32 slotKey = _slotKey(tickLower, tickUpper);
            uint256 existingTokenId = slotToTokenId[slotKey];

            SlotDecision memory d;
            d.tickLower = tickLower;
            d.tickUpper = tickUpper;
            d.targetLiq = uint128(liqPerSlot[i]);

            if (existingTokenId == 0) {
                // no position exists at this range -> mint new
                d.action     = Action.MINT;
                d.tokenId    = 0;
                d.currentLiq = 0;
            } else {
                uint128 currentLiq = _getCurrentLiquidity(existingTokenId, tickLower, tickUpper);
                d.tokenId    = existingTokenId;
                d.currentLiq = currentLiq;

                if (currentLiq == 0) {
                    d.action = Action.REACTIVATE;
                } else if (d.targetLiq > currentLiq) {
                    d.action = Action.INCREASE;
                } else if (d.targetLiq < currentLiq) {
                    d.action = Action.DECREASE;
                } else {
                    d.action = Action.SKIP;
                }
            }

            decisions[i] = d;
        }

        // --- Step 6: close old slots that are no longer in the target set ---
        uint256 oldSlotCount = positionTracker.slotCount();
        for (uint256 i = 0; i < oldSlotCount; i++) {
            PositionTracker.SlotState memory stored = positionTracker.getSlotState(i);
            if (!stored.isActive) continue;

            bool stillNeeded = false;
            for (uint256 j = 0; j < numSlots; j++) {
                if (stored.lowerTick == int256(decisions[j].tickLower) &&
                    stored.upperTick == int256(decisions[j].tickUpper)) {
                    stillNeeded = true;
                    break;
                }
            }

            if (!stillNeeded && stored.tokenId != 0) {
                uint128 liq = _getCurrentLiquidity(
                    stored.tokenId,
                    int24(int256(stored.lowerTick)),
                    int24(int256(stored.upperTick))
                );
                if (liq > 0) {
                    _decreaseLiquidity(stored.tokenId, liq);
                }
                // Fully deactivate the old slot
                positionTracker.setSlotState(
                    i,
                    stored.tokenId,
                    stored.lowerTick,
                    stored.upperTick,
                    0,
                    false
                );
            }
        }

        // --- Step 7: execute each decision ---
        for (uint256 i = 0; i < numSlots; i++) {
            SlotDecision memory d = decisions[i];

            if (d.action == Action.SKIP) {
                continue;
            } else if (d.action == Action.MINT || d.action == Action.REACTIVATE) {
                if (d.tokenId == 0) {
                    _mint(Config.poolKey(), d.tickLower, d.tickUpper, uint256(d.targetLiq));
                } else {
                    _increaseLiquidity(d.tokenId, uint256(d.targetLiq), type(uint128).max, type(uint128).max);
                }
            } else if (d.action == Action.INCREASE) {
                uint128 delta = d.targetLiq - d.currentLiq;
                _increaseLiquidity(d.tokenId, uint256(delta), type(uint128).max, type(uint128).max);
            } else if (d.action == Action.DECREASE) {
                uint128 delta = d.currentLiq - d.targetLiq;
                _decreaseLiquidity(d.tokenId, delta);
            }

            // update tracker
            positionTracker.setSlotState(
                i,
                d.tokenId != 0 ? d.tokenId : slotToTokenId[_slotKey(d.tickLower, d.tickUpper)],
                int256(d.tickLower),
                int256(d.tickUpper),
                uint256(d.targetLiq),
                d.targetLiq > 0
            );
        }

        positionTracker.setSlotCount(numSlots);
        lastRebalanceTimestamp = block.timestamp;

        // Update idle balances after all position changes
        idleEth  = address(this).balance;
        idleUsdc = IERC20(USDC).balanceOf(address(this));
    }

    /* -------------------------------------------------------------------------- */
    /*                        PRICE-DRIFT REBALANCE CHECK                         */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Returns true if the current tick has drifted outside the center
     *         slot of our active distribution, meaning a rebalance is needed.
     */
    function needsTickDriftRebalance() external view returns (bool) {
        if (positionTracker.slotCount() == 0) return false;

        (, int24 currentTick,,) = poolManager.getSlot0(Config.poolId());
        uint256 centerIndex = positionTracker.slotCount() / 2;
        PositionTracker.SlotState memory center = positionTracker.getSlotState(centerIndex);

        return currentTick < int24(int256(center.lowerTick)) ||
               currentTick >= int24(int256(center.upperTick));
    }

    /* -------------------------------------------------------------------------- */
    /*                          TOKEN-RATIO SWAP LOGIC                            */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Checks if the idle buffer is skewed >85% toward one token and
     *         returns which direction to swap.
     * @return shouldSwap  Whether a swap is warranted
     * @return zeroForOne  true = sell ETH for USDC, false = sell USDC for ETH
     * @return amountToSwap The amount of the overweight token to swap
     */
    function checkAndComputeSwap(
        uint256 _idleEth,
        uint256 _idleUsdc,
        uint160 sqrtPriceX96
    ) external pure returns (bool shouldSwap, bool zeroForOne, uint256 amountToSwap) {
        // price in token1/token0 raw decimals = (sqrtPriceX96)^2 / 2^192
        // For ETH(18dec)/USDC(6dec): result is in USDC-raw per ETH-raw
        // ethValueUsdc (in 6-decimal USDC) = _idleEth * priceX192 / 2^192
        // But direct multiplication overflows, so we split:
        // ethValueUsdc = (_idleEth * (sqrtPriceX96/2^48)^2) / 2^96
        
        uint256 sqrtPriceReduced = uint256(sqrtPriceX96);
        // Use mulDiv pattern to avoid overflow
        // price = sqrtPriceX96^2 / 2^192
        // ethValueUsdc = _idleEth * sqrtPriceX96^2 / 2^192
        
        // Split: ethValueUsdc = (_idleEth * sqrtPriceX96 / 2^96) * sqrtPriceX96 / 2^96
        uint256 intermediate = (_idleEth * sqrtPriceReduced) >> 96;
        uint256 ethValueUsdc = (intermediate * sqrtPriceReduced) >> 96;
        
        // ethValueUsdc is now in USDC raw units (6 decimals) — no extra scaling needed

        uint256 totalValueUsdc = ethValueUsdc + _idleUsdc;
        if (totalValueUsdc == 0) return (false, false, 0);

        uint256 ethRatioBps = (ethValueUsdc * BPS_DENOM) / totalValueUsdc;

        if (ethRatioBps > SWAP_THRESHOLD_BPS) {
            uint256 excessUsdc = ethValueUsdc - (totalValueUsdc / 2);
            // Convert USDC value back to ETH: ethAmt = excessUsdc * 2^192 / sqrtPrice^2
            // = excessUsdc * 2^96 / sqrtPrice * 2^96 / sqrtPrice
            amountToSwap = (excessUsdc << 96) / sqrtPriceReduced;
            amountToSwap = (amountToSwap << 96) / sqrtPriceReduced;
            return (true, true, amountToSwap);
        }

        uint256 usdcRatioBps = (_idleUsdc * BPS_DENOM) / totalValueUsdc;
        if (usdcRatioBps > SWAP_THRESHOLD_BPS) {
            uint256 excessUsdc = _idleUsdc - (totalValueUsdc / 2);
            amountToSwap = excessUsdc;
            return (true, false, amountToSwap);
        }

        return (false, false, 0);
    }

    /**
     * @notice Executes a swap on the Uniswap pool if the idle buffer is skewed
     *         >85% toward one token. Called internally before rebalancing.
     */
    function _rebalanceIdleBuffer() internal {
        (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(Config.poolId());
        
        (bool shouldSwap, bool zeroForOne, uint256 amountToSwap) = this.checkAndComputeSwap(
            idleEth,
            idleUsdc,
            sqrtPriceX96
        );

        if (shouldSwap && amountToSwap > 0) {
            _executeSwap(zeroForOne, amountToSwap);
        }
    }

    struct SwapCallbackData {
        bool zeroForOne;
        uint256 amountIn;
    }

    bytes internal _pendingSwapData;

    function _executeSwap(bool zeroForOne, uint256 amountIn) internal {
        _pendingSwapData = abi.encode(SwapCallbackData({
            zeroForOne: zeroForOne,
            amountIn: amountIn
        }));
        poolManager.unlock(abi.encode(uint8(1))); // 1 = swap action
    }

    function unlockCallback(bytes calldata data) external override returns (bytes memory) {
        require(msg.sender == address(poolManager), "only pool manager");
        
        uint8 action = abi.decode(data, (uint8));
        
        if (action == 1) {
            SwapCallbackData memory swapData = abi.decode(_pendingSwapData, (SwapCallbackData));
            delete _pendingSwapData;
            
            SwapParams memory params = SwapParams({
                zeroForOne: swapData.zeroForOne,
                amountSpecified: -int256(swapData.amountIn), // exact input (negative = exact input)
                sqrtPriceLimitX96: swapData.zeroForOne 
                    ? TickMath.MIN_SQRT_PRICE + 1 
                    : TickMath.MAX_SQRT_PRICE - 1
            });

            poolManager.swap(Config.poolKey(), params, "");

            // Settle both currencies — the pool manager knows who owes what
            // For the currency we're selling: settle (pay in)
            // For the currency we're buying: take (withdraw)
            _settleCurrencyDebt(Currency.wrap(address(0)), swapData.zeroForOne ? swapData.amountIn : 0);
            _settleCurrencyDebt(Currency.wrap(USDC), swapData.zeroForOne ? 0 : swapData.amountIn);
        }

        idleEth  = address(this).balance;
        idleUsdc = IERC20(USDC).balanceOf(address(this));

        return "";
    }

    function _settleCurrencyDebt(Currency currency, uint256 maxSettle) internal {
        if (maxSettle > 0) {
            if (Currency.unwrap(currency) == address(0)) {
                poolManager.settle{value: maxSettle}();
            } else {
                IERC20(Currency.unwrap(currency)).safeTransfer(address(poolManager), maxSettle);
                poolManager.settle();
            }
        }
    }

    /* -------------------------------------------------------------------------- */
    /*                             INTERNAL FUNCTIONS                             */
    /* -------------------------------------------------------------------------- */

    function _slotKey(int24 lower, int24 upper) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(lower, upper));
    }

    function _alignTick(int24 tick) internal pure returns (int24) {
        int24 spacing = Config.TICK_SPACING;
        // floor division toward negative infinity
        int24 compressed = tick / spacing;
        if (tick < 0 && tick % spacing != 0) compressed--;
        return compressed * spacing;
    }

    function _buildEqualWeights(uint256 n) internal pure returns (uint256[] memory weights) {
        weights = new uint256[](n);
        uint256 base = 100 / n;
        uint256 remainder = 100 - base * n;
        for (uint256 i = 0; i < n; i++) {
            weights[i] = base;
        }
        // give remainder to the center slot
        weights[n / 2] += remainder;
    }

    function _mint(
        PoolKey memory key,
        int24 tickLower,
        int24 tickUpper,
        uint256 liquidity
    ) internal {
        bytes memory actions = abi.encodePacked(
            uint8(Actions.MINT_POSITION),
            uint8(Actions.SETTLE_PAIR),
            uint8(Actions.SWEEP),
            uint8(Actions.SWEEP)
        );
        bytes[] memory params = new bytes[](4);
        params[0] = abi.encode(
            key,
            tickLower,
            tickUpper,
            liquidity,
            type(uint128).max,
            type(uint128).max,
            address(this),
            ""
        );
        params[1] = abi.encode(address(0), USDC);
        params[2] = abi.encode(address(0), address(this));  // sweep ETH
        params[3] = abi.encode(USDC, address(this));         // sweep USDC

        uint256 tokenId = positionManager.nextTokenId();

        // Approve USDC to positionManager before minting
        IERC20(USDC).forceApprove(address(positionManager), type(uint256).max);

        positionManager.modifyLiquidities{value: address(this).balance}(
            abi.encode(actions, params), block.timestamp
        );

        bytes32 slotKey = _slotKey(tickLower, tickUpper);
        slotToTokenId[slotKey] = tokenId;
    }

    function _increaseLiquidity(
        uint256 tokenId,
        uint256 liquidity,
        uint128 amount0Max,
        uint128 amount1Max
    ) internal {
        bytes memory actions = abi.encodePacked(
            uint8(Actions.INCREASE_LIQUIDITY),
            uint8(Actions.CLOSE_CURRENCY),
            uint8(Actions.CLOSE_CURRENCY),
            uint8(Actions.SWEEP),
            uint8(Actions.SWEEP)
        );
        bytes[] memory params = new bytes[](5);
        params[0] = abi.encode(tokenId, liquidity, amount0Max, amount1Max, "");
        params[1] = abi.encode(address(0));
        params[2] = abi.encode(USDC);
        params[3] = abi.encode(address(0), address(this));
        params[4] = abi.encode(USDC, address(this));

        IERC20(USDC).forceApprove(address(positionManager), type(uint256).max);

        positionManager.modifyLiquidities{value: address(this).balance}(
            abi.encode(actions, params), block.timestamp
        );
    }

    function _decreaseLiquidity(
        uint256 tokenId,
        uint128 liquidityToRemove
    ) internal {
        bytes memory actions = abi.encodePacked(
            uint8(Actions.DECREASE_LIQUIDITY),
            uint8(Actions.CLOSE_CURRENCY),
            uint8(Actions.CLOSE_CURRENCY),
            uint8(Actions.SWEEP)
        );
        bytes[] memory params = new bytes[](4);
        params[0] = abi.encode(tokenId, liquidityToRemove, uint128(0), uint128(0), "");
        params[1] = abi.encode(address(0));
        params[2] = abi.encode(USDC);
        params[3] = abi.encode(address(0), address(this));

        positionManager.modifyLiquidities{value: address(this).balance}(
            abi.encode(actions, params), block.timestamp
        );
    }

    function _getCurrentLiquidity(
        uint256 tokenId,
        int24 tickLower,
        int24 tickUpper
    ) internal view returns (uint128 liquidity) {
        // v4 position key: keccak256(owner, tickLower, tickUpper, salt)
        bytes32 positionId = keccak256(
            abi.encodePacked(
                address(positionManager),
                tickLower,
                tickUpper,
                bytes32(tokenId)
            )
        );
        (liquidity,,) = poolManager.getPositionInfo(
            Config.poolId(),
            positionId
        );
    }

    receive() external payable {}
}