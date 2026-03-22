//SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IPoolManager} from "../../lib/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "../../lib/v4-core/src/types/PoolKey.sol";
import {PoolId  PoolIdLibrary} from "../../lib/v4-core/src/types/PoolId.sol";
import {Currency} from "../../lib/v4-core/src/types/Currency.sol";
import {StateLibrary} from "../../lib/v4-core/src/libraries/StateLibrary.sol";
import {IPositionManager} from "../../lib/v4-periphery/src/interfaces/IPositionManager.sol";
import {Actions}          from "../../lib/v4-periphery/src/libraries/Actions.sol";
import {IERC20}    from "../../lib/v4-core/lib/openzeppelincontracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../../lib/v4-core/lib/openzeppelincontracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {PositionTracker} from "./PositionTracker.sol";
import {liquidityDistributor} from "./LiquidityDistributor.sol";
import {NavCalculator} from "../libraries/NavCalculator.sol";

contract PoolInteractor {
    using SafeERC20     for IERC20;
    using PoolIdLibrary for PoolKey;
    using StateLibrary  for IPoolManager;

    IPositionManager public immutable positionManager;
    IPoolManager     public immutable poolManager;
    IPermit2         public immutable permit2;
    PositionTracker  public immutable positionTracker;
    LiquidityDistributor public immutable liquidityDistributor;
    address public immutable token0;
    address public immutable token1;

    Poolkey internal immutable poolKey = Config.poolKey();
    PoolId internal immutable poolId = Config.poolId();

    struct Slot {
        int256 lowerTick;
        int256 upperTick;
    }

    Slot[] public targetSlots;

    mapping (Slot => uint256) public SlotToTokenId;

    struct SlotPlan{
        int256 lowerTick;
        int256 upperTick;
        uint256 liquidityAmount;
    }

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
        int256   tickLower;
        int256   tickUpper;
    }

    SlotPlan[] public slotPlan;

/* -------------------------------------------------------------------------- */
/*                             Aradhya's functions                            */
/* -------------------------------------------------------------------------- */

    function checkLiquiditySlotsAndHasMintTokenId() public view returns(){
        (, int24 currentTick,,) = StateLibrary.getSlot0(Config.poolManager, Config.poolId());

        currentTickLowerBound = (currentTick / Config.TICK_SPACING) * Config.TICK_SPACING;

        uint8 volatilityIndex = Config.volatility_index;
        if (volatilityIndex == Config.HIGH_VOLATILITY) {
            uint8 numOfSlots = 7;
        }
        else if (volatilityIndex == Config.MEDIUM_VOLATILITY) {
            uint8 numOfSlots = 5;
        }
        else {
            uint8 numOfSlots = 3;
        }
        targetSlots = new Slot[](numOfSlots);
        for (uint256 i = 0; i < numOfSlots; i++) {
            targetSlots[i] = Slot({
                lowerTick: int256(currentTickLowerBound + (int256((int256(i) - (int256(numOfSlots) - 1) / 2) * int256(Config.TICK_SPACING)))),
                upperTick: int256(currentTickLowerBound + (int256((int256(i) - (int256(numOfSlots) - 1) / 2 + 1) * int256(Config.TICK_SPACING))))
            });
            if (SlotToTokenId[targetSlots[i]] == 0) {
                _mint(poolKey, int24(targetSlots[i].lowerTick), int24(targetSlots[i].upperTick), 0);
            }
        }
    }

    
/* -------------------------------------------------------------------------- */
/*                             internal functions                             */
/* -------------------------------------------------------------------------- */
    function _mint(
        PoolKey calldata key,
        int24 tickLower,
        int24 tickUpper,
        uint256 liquidity
    ) internal {
        bytes memory actions = abi.encodePacked(
            uint8(Actions.MINT_POSITION),
            uint8(Actions.SETTLE_PAIR),
            uint8(Actions.SWEEP)
        );
        bytes[] memory params = new bytes[](3);
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

        params[2] = abi.encode(address(0), address(this));

        uint256 tokenId = Config.positionManager.nextTokenId();

        Config.positionManager.modifyLiquidities{value: address(this).balance}(
            abi.encode(actions, params), block.timestamp
        );

        Slot memory s = Slot({
            lowerTick: tickLower,
            upperTick: tickUpper
        });
        SlotToTokenId[s] = tokenId;
    }

    function _increaseLiquidity(
        uint256 tokenId,
        uint256 liquidity,
        uint128 amount0Max,
        uint128 amount1Max
    ) internal payable {
        bytes memory actions = abi.encodePacked(
            uint8(Actions.INCREASE_LIQUIDITY),
            uint8(Actions.CLOSE_CURRENCY),
            uint8(Actions.CLOSE_CURRENCY),
            uint8(Actions.SWEEP)
        );
        bytes[] memory params = new bytes[](4);

        // INCREASE_LIQUIDITY params
        params[0] = abi.encode(
            tokenId,
            liquidity,
            amount0Max,
            amount1Max,
            // hook data
            ""
        );

        // CLOSE_CURRENCY params
        // currency 0
        params[1] = abi.encode(address(0), USDC);

        // CLOSE_CURRENCY params
        // currency 1
        params[2] = abi.encode(USDC);

        // SWEEP params
        // currency, address to
        params[3] = abi.encode(address(0), address(this));

        Config.positionManager.modifyLiquidities{value: address(this).balance}(
            abi.encode(actions, params), block.timestamp
        );
    }

/* -------------------------------------------------------------------------- */
/*                            uttkarsh ke functions                           */
/* -------------------------------------------------------------------------- */

    function decideActions(SlotPlan[] calldata plans) internal  returns (SlotDecision[] memory decisions){
        uint256 newSlotsCount = plans.length;
        uint256 currentSlotsCount = positionTracker.slotCount();

        decisions = new SlotDecision[](newSlotsCount);

        for (uint256 i = 0 ; i < newSlotsCount ; i++){
            SlotPlan calldata plan = plans[i];
            PositionTracker.SlotState memory stored = positionTracker.getSlotState(i);

            SlotDecision memory d;
            d.tickLower = plan.lowerTick;
            d.tickUpper = plan.upperTick;
            d.targetLiq = uint128(plan.liquidityAmount);
            
            
            if(stored.tokenId == 0){
                d.action = Action.MINT;
                d.tokenId = 0;
                d.currentLiq = 0;
            }

            else if (stored.lowerTick != plan.lowerTick || stored.upperTick != plan.upperTick){
                d.action = Action.RESTAKE;
                d.tokenId = stored.tokenId;
                d.currentLiq = _getCurrentLiquidity(stored.tokenId, stored.lowerTick, stored.upperTick);
            }
            else {
                uint256 current = _getCurrentLiquidity(stored.tokenId, plan.tickLower, plan.tickUpper);
                d.tokenId    = stored.tokenId;
                d.currentLiq = current;

                if (current == 0) {
                    d.action = Action.REACTIVATE;
                } else if (plan.liquidityAmount > current) {
                    d.action = Action.INCREASE;
                } else if (plan.amount < current) {
                    d.action = Action.DECREASE;
                } else {
                    d.action = Action.SKIP;
                }
            }

            decisions[i] = d;
        }
        for (uint256 i = newSlotsCount; i < currentSlotsCount; i++) {
            PositionTracker.SlotState memory stored = positionTracker.getSlotState(i);
            if (!stored.hasLiquidity) continue;

            SlotDecision memory d;
            d.action     = Action.DECREASE_TO_ZERO;
            d.tokenId    = stored.tokenId;
            d.currentLiq = _getCurrentLiquidity(stored.tokenId, stored.tickLower, stored.tickUpper);
            d.targetLiq  = 0;
            d.tickLower  = stored.tickLower;
            d.tickUpper  = stored.tickUpper;
            decisions[idx++] = d;
        }

    }

    function _getCurrentLiquidity(uint256 tokenId, int256 tickLower, int256 tickUpper) internal view returns (uint128 liquidity){
        PoolId poolId = poolKey.toId();

        liquidity = poolManager.getPositionLiquidity(
            poolId,
            address(positionManager),
            tickLower,
            tickUpper,
            bytes32(tokenId)
        );
    }
}