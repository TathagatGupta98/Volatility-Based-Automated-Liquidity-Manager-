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
        int24   tickLower;
        int24   tickUpper;
}

    SlotPlan[] public slotPlan;


    function rebalance(SlotPlan[] calldata plans ) external {

        //checkv2approval

        //snapshot of the next tokenId
        uint256 mintNextTokenId = positionManager.nextTokenId();

        SlotDecision[] memory decisions= decideActions(plans);

    }

    function decideActions(SlotPlan[] calldata plans) internal  returns (SlotDecision[] memory decisions){}
         