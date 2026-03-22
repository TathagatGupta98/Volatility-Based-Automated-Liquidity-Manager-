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
import {NavCalculator} from "./NavCalculator.sol";
import {ShareAccounting} from "./ShareAccounting.sol";
import {VaultStorage} from "./VaultStorage.sol";
import {Config} from "../helpers/Config.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {FullMath} from "v4-core/src/libraries/FullMath.sol";

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
            revert VaultPaused();
        }
    }

/* -------------------------------- Functions ------------------------------- */
    function deposit(uint256 usdcAmount) external payable whenNotPaused{
        uint256 depositValueUsdc = computeDepositValueUsdc(msg.value, usdcAmount);
        validateDeposit(msg.value, usdcAmount, depositValueUsdc);

        (uint256 preTotalEth, uint256 preTotalUsdc, uint256 preNavUsdc) = NavCalculator.computeNav();

        if (usdcAmount > 0) {
            permit2.transferFrom(
                msg.sender,
                address(this),
                uint160(usdcAmount),
                USDC
            );
        }

        uint256 sharesToMint = computeSharesForDeposit(depositValueUsdc, preNavUsdc);
        
        if (!initialized) {
            totalShares += INITIAL_DEAD_SHARES;
            initialized  = true;
        }

        uint256 idx = userIndex[msg.sender];

        if (idx == 0) {
            users.push(User({
                ethDeposited:     msg.value,
                usdcDeposited:    usdcAmount,
                sharesOwned:      sharesToMint,
                depositTimestamp: block.timestamp,
                isActive:         true
            }));

            userIndex[msg.sender] = users.length - 1;
            
        } else {
            UserInfo storage user = users[idx];
            user.ethDeposited     += msg.value;
            user.usdcDeposited    += usdcAmount;
            user.sharesOwned      += sharesToMint;
            user.depositTimestamp  = block.timestamp;
            user.isActive          = true;
        } 



}
