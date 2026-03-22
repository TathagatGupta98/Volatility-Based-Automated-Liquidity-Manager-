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

    PoolKey public poolKey;

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


    function rebalance(SlotPlan[] calldata plans ) external {

        //checkv2approval

        //snapshot of the next tokenId
        uint256 mintNextTokenId = positionManager.nextTokenId();

        SlotDecision[] memory decisions= decideActions(plans);

    }

    function decideActions(SlotPlan[] calldata plans) internal  returns (SlotDecision[] memory decisions){
        uint256 newSlotsCount = plans.length;
        uint256 currentSlotsCount = positionTracker.slotCount();
        uint256 memory orphanslots = 0;

        for (uint256 i = newSlotsCount; i < currentSlotsCount; i++){
            if(positionTracker.hasLiquidity(i))orphanslots++;
        }

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
                } else if (plan.amount > current) {
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