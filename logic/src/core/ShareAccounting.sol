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


/* -------------------------------------------------------------------------- */
/*                                  contract                                  */
/* -------------------------------------------------------------------------- */
contract ShareAccounting is VaultStorage{


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


    function getEthUsdcPrice() returns (uint256 p_actual) {
        uint265 sqrtPriceX96 = poolManager.getSlot0(poolId);
        uint265 p_raw = (sqrtPriceX96 * sqrtPriceX96) / 2**96;
        p_actual = p_raw * (10**12);
    }

    function computeDepositValueUsdc(uint256 ethAmount, uint256 usdcAmount) returns(uint256 totalValueUsdc){
        uint256 ethPriceUsdc = getEthUsdcPrice();
        uint256 ethAmountInUsdc = (ethAmount * getEthUsdcPrice)/ETH_DECIMALS;
        totalValueUsdc = usdcAmount + ethAmountInUsdc;
    }

    function computeSharesForDeposit(uint256 depositValueUsd, uint256 currentNavUsdc) returns (uint256 sharesToMint){
        if(initialized){
            sharesToMint = (depositValueUsd * totalShares) / currentNavUsdc;
        }
        else{
            sharesToMint = (depositValueUsd * WAD)/USDC_DECIMALS;    
        } 
    }
    function computeTokensForShares(
        uint256 shareToBurn, 
        uint256 currentTotalEth, 
        uint256 currentTotalUsdc
    ) returns(uint256 ethToReturn, uint256 usdcToReturn){
        ethToReturn  = (sharesToBurn * currentTotalEth)  / totalShares;
        usdcToReturn = (sharesToBurn * currentTotalUsdc) / totalShares;
    }

}
