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
import {ShareAccounting} from "./ShareAccounting.sol";
import {NavCalculator} from "../libraries/NavCalculator.sol";
import {Config} from "../helpers/config.sol";

/* ------------------------------- constructor ------------------------------ */
contract DepositManager is ShareAccounting, NavCalculator{
    constructor() VaultStorage(
        Config.POOL_MANAGER_ADDRESS,
        Config.POSITION_MANAGER_ADDRESS,
        Config.PERMIT2_ADDRESS,              
        Config.USDC_ADDRESS,
        Config.poolKey(),
        Config.TICK_SPACING * 10,     
        6e17                          
    ) {}

/* -------------------------------- mofifiers -------------------------------- */
    modifier whenNotPaused {
        if(paused == false){
            _;
        }
        else{
            revert 
        }
    }
    modifier validUser {
        if(usersIndex[msg.sender] != 0){
            _;
        }
        else
        {
            revert 
        }
    }
/* -------------------------------- Functions ------------------------------- */




}
