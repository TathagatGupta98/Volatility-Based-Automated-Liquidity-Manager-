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
import {NavCalculator} from "../libraries/NavCalculator.sol";
import {ShareAccounting} from "./ShareAccounting.sol";
import {VaultStorage} from "./VaultStorage.sol";
import {Config} from "../helpers/config.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {FullMath} from "v4-core/src/libraries/FullMath.sol";
import {SafeCast} from "v4-core/src/libraries/SafeCast.sol";

/* ------------------------------- constructor ------------------------------ */
contract DepositManager is ShareAccounting, NavCalculator{
    using SafeCast for uint256;
    /**
     * @notice Deploys `DepositManager` and forwards configuration to `VaultStorage`.
     */
    constructor() VaultStorage(
        Config.POOL_MANAGER_ADDRESS,
        Config.POSITION_MANAGER_ADDRESS,
        Config.PERMIT2_ADDRESS,              
        Config.USDC_ADDRESS,
        Config.poolKey(),
        uint24(Config.TICK_SPACING) * 10,
        6e17                          
    ) {}

/* -------------------------------- mofifiers -------------------------------- */
    /**
     * @notice Ensures the vault is not paused.
     */
    modifier whenNotPaused {
        if(paused == false){
            _;
        }
        else{
            revert VaultPaused();
        }
    }

/* -------------------------------- Functions ------------------------------- */

    /**
     * @notice Deposit ETH (msg.value) and/or USDC into the vault and mint corresponding shares.
     * @param usdcAmount Amount of USDC to deposit (in USDC base units).
     */
    function deposit(uint256 usdcAmount) external payable whenNotPaused {
        uint256 depositValueUsdc = computeDepositValueUsdc(msg.value, usdcAmount);
        validateDeposit(msg.value, usdcAmount, depositValueUsdc);

        (, , uint256 preNavUsdc) = computeNav();

        if (usdcAmount > 0) {
            permit2.transferFrom(
                msg.sender,
                address(this),
                usdcAmount.toUint160(),
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
            User storage user = users[idx];
            user.ethDeposited     += msg.value;
            user.usdcDeposited    += usdcAmount;
            user.sharesOwned      += sharesToMint;
            user.depositTimestamp  = block.timestamp;
            user.isActive          = true;
        }

        // Update vault state
        totalShares += sharesToMint;
        idleEth += msg.value;
        idleUsdc += usdcAmount;
        totalEthDeposited += msg.value;
        totalUsdcDeposited += usdcAmount;

        uint256 ethPriceUsdc     = getEthUsdcPrice();
        uint256 idleEthInUsdc    = FullMath.mulDiv(idleEth, ethPriceUsdc, ETH_DECIMALS);
        uint256 totalIdleInUsdc  = idleEthInUsdc + idleUsdc;
        uint256 upperBoundUsdc = FullMath.mulDiv(
            preNavUsdc,
            BUFFER_UPPER_BOUND,
            WAD
        );
        if (totalIdleInUsdc > upperBoundUsdc) {
            emit BufferDeployed(idleEth, idleUsdc, idleEth, idleUsdc);
        }
        emit Deposited(msg.sender, msg.value, usdcAmount, sharesToMint, preNavUsdc);
    }

    /**
     * @notice Burn vault shares to withdraw proportional ETH and USDC from the buffer.
     * @param sharesToBurn Number of shares to burn for withdrawal.
     */
    function withdraw(uint256 sharesToBurn) external {
        if (sharesToBurn == 0) revert ZeroShares();
        uint256 idx = userIndex[msg.sender];
        if (idx == 0) revert InsufficientShares(sharesToBurn, 0); //never deposited
        User storage user = users[idx];
        if (user.sharesOwned < sharesToBurn) {
            revert InsufficientShares(sharesToBurn, user.sharesOwned);
        }
        (uint256 totalEth, uint256 totalUsdc, uint256 navUsdc) = computeNav();
        (uint256 ethOwed, uint256 usdcOwed) = computeTokensForShares(sharesToBurn, totalEth, totalUsdc);
        if (idleEth < ethOwed || idleUsdc < usdcOwed) revert BufferEmpty();
        user.sharesOwned -= sharesToBurn;
        if (user.sharesOwned == 0) {
            user.isActive = false;
        }
        idleEth  -= ethOwed;
        idleUsdc -= usdcOwed;
        totalShares -= sharesToBurn;
        if (usdcOwed > 0) {
            bool usdcSuccess = IERC20(USDC).transfer(msg.sender, usdcOwed);
            if (!usdcSuccess) revert NativeTransferFailed();
        }
        if (ethOwed > 0) {
            (bool ethSuccess, ) = msg.sender.call{value: ethOwed}("");
            if (!ethSuccess) revert NativeTransferFailed();
        }
        emit Withdrawal(msg.sender, sharesToBurn, ethOwed, usdcOwed, navUsdc);
    }
}
