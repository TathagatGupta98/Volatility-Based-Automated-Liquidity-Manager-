// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// internal & private view & pure functions
// external & public view & pure functions

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/* --------------------------------- imports -------------------------------- */
import {VaultStorage} from "./VaultStorage.sol";
import {Config} from "../helpers/config.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {FullMath} from "v4-core/src/libraries/FullMath.sol";

/* -------------------------------------------------------------------------- */
/*                                  contract                                  */
/* -------------------------------------------------------------------------- */
contract ShareAccounting is VaultStorage{

    using StateLibrary for IPoolManager;

/* ------------------------------- constructor ------------------------------ */
    constructor() VaultStorage(
        Config.POOL_MANAGER_ADDRESS,
        Config.POSITION_MANAGER_ADDRESS,
        Config.PERMIT2_ADDRESS,              
        Config.USDC_ADDRESS,
        Config.poolKey(),
        Config.TICK_SPACING * 10,     // slotWidthTicks — 10 tick spacings per slot
        6e17                          // ewmaAlpha — 0.6 in WAD, moderately reactive
    ) {}


    function getEthUsdcPrice() public view returns (uint256 p_actual) {
        (uint160 sqrtPriceX96, , , ) = poolManager.getSlot0(Config.poolId());

        uint265 p_raw = (uint256(sqrtPriceX96) * uint256(sqrtPriceX96)) / 2**96;
        p_actual = p_raw * 1e12;
    }

    function computeDepositValueUsdc(uint256 ethAmount, uint256 usdcAmount) internal view returns(uint256 totalValueUsdc){
        uint256 ethPriceUsdc = getEthUsdcPrice();
        uint256 ethAmountInUsdc = (ethAmount * getEthUsdcPrice) / ETH_DECIMALS;
        totalValueUsdc = usdcAmount + ethAmountInUsdc;
    }

    function computeSharesForDeposit(uint256 depositValueUsd, uint256 currentNavUsdc) internal view returns (uint256 sharesToMint){
        if(initialized){
            sharesToMint = (depositValueUsd * totalShares) / currentNavUsdc;
        }
        else{
            initialized = true;
            sharesToMint = (depositValueUsd * WAD)/USDC_DECIMALS;    
        } 
    }

    function computeTokensForShares(
        uint256 sharesToBurn, 
        uint256 currentTotalEth, 
        uint256 currentTotalUsdc
    ) internal view returns(uint256 ethToReturn, uint256 usdcToReturn){

        ethToReturn  = (sharesToBurn * currentTotalEth)  / totalShares;
        usdcToReturn = (sharesToBurn * currentTotalUsdc) / totalShares;
    }

    function validateDeposit(
        uint256 ethAmount,
        uint256 usdcAmount,
        uint256 depositValueUsdc
    ) internal view {
        if (ethAmount == 0 && usdcAmount == 0) revert ZeroDeposit();
        if (depositValueUsdc < MIN_DEPOSIT_USDC)
            revert BelowMinimumDeposit(depositValueUsdc, MIN_DEPOSIT_USDC);
        if (paused) revert VaultPaused();
    }

}
