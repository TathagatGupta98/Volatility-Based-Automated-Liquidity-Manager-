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


    function getEthUsdPrice() returns (uint256 p_actual) {
        uint265 sqrtPriceX96 = poolManager.getSlot0(poolId);
        uint265 p_raw = (sqrtPriceX96 * sqrtPriceX96) / 2**96;
        uint256 p_actual = p_raw * (10**12);
    }
}
