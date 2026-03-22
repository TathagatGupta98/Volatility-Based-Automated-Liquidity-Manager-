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
    /**
     * @notice Initializes the `ShareAccounting` contract by forwarding constants to `VaultStorage`.
     * @dev Constructor sets up pool manager, position manager, permit2 and addresses used by the vault.
     */
    constructor() VaultStorage(
        Config.POOL_MANAGER_ADDRESS,
        Config.POSITION_MANAGER_ADDRESS,
        Config.PERMIT2_ADDRESS,              
        Config.USDC_ADDRESS,
        Config.poolKey(),
        Config.TICK_SPACING * 10,     // slotWidthTicks — 10 tick spacings per slot
        6e17                          // ewmaAlpha — 0.6 in WAD, moderately reactive
    ) {}


    /**
     * @notice Returns the current ETH/USDC price from the pool slot0 observation.
     * @dev Reads `sqrtPriceX96` and converts to a 1e18-scaled USDC price.
     * @return p_actual The current ETH price denominated in USDC (scaled to 1e18 where applicable).
     */
    function getEthUsdcPrice() public view returns (uint256 p_actual) {
        (uint160 sqrtPriceX96, , , ) = poolManager.getSlot0(Config.poolId());

        uint265 p_raw = (uint256(sqrtPriceX96) * uint256(sqrtPriceX96)) / 2**96;
        p_actual = p_raw * 1e12;
    }

    /**
     * @notice Computes the combined USDC value of provided ETH and USDC amounts.
     * @dev Uses `getEthUsdcPrice()` to convert ETH to USDC and sums the amounts.
     * @param ethAmount Amount of ETH (in wei) to convert to USDC.
     * @param usdcAmount Amount of USDC (in base units) to include in the total.
     * @return totalValueUsdc Total value expressed in USDC base units.
     */
    function computeDepositValueUsdc(uint256 ethAmount, uint256 usdcAmount) internal view returns(uint256 totalValueUsdc){
        uint256 ethPriceUsdc = getEthUsdcPrice();
        uint256 ethAmountInUsdc = (ethAmount * getEthUsdcPrice) / ETH_DECIMALS;
        totalValueUsdc = usdcAmount + ethAmountInUsdc;
    }

    /**
     * @notice Calculates the number of shares to mint for a given deposit value.
     * @dev If the vault is uninitialized this call will set `initialized` and mint shares using WAD scaling.
     * @param depositValueUsd Deposit value denominated in USDC base units.
     * @param currentNavUsdc Current net asset value of the vault in USDC base units.
     * @return sharesToMint Number of shares to mint for the deposit.
     */
    function computeSharesForDeposit(uint256 depositValueUsd, uint256 currentNavUsdc) internal view returns (uint256 sharesToMint){
        if(initialized){
            sharesToMint = (depositValueUsd * totalShares) / currentNavUsdc;
        }
        else{
            initialized = true;
            sharesToMint = (depositValueUsd * WAD)/USDC_DECIMALS;    
        } 
    }

    /**
     * @notice Computes token amounts to return when burning a given number of shares.
     * @dev Pro-rates `currentTotalEth` and `currentTotalUsdc` by `sharesToBurn / totalShares`.
     * @param sharesToBurn Number of shares being burned.
     * @param currentTotalEth Current total ETH balance of the vault (in wei).
     * @param currentTotalUsdc Current total USDC balance of the vault (in base units).
     * @return ethToReturn Amount of ETH to return (in wei).
     * @return usdcToReturn Amount of USDC to return (in base units).
     */
    function computeTokensForShares(
        uint256 sharesToBurn, 
        uint256 currentTotalEth, 
        uint256 currentTotalUsdc
    ) internal view returns(uint256 ethToReturn, uint256 usdcToReturn){

        ethToReturn  = (sharesToBurn * currentTotalEth)  / totalShares;
        usdcToReturn = (sharesToBurn * currentTotalUsdc) / totalShares;
    }

    /**
     * @notice Validates a deposit against vault constraints.
     * @dev Reverts with `ZeroDeposit`, `BelowMinimumDeposit`, or `VaultPaused` when checks fail.
     * @param ethAmount Amount of ETH (in wei) included in the deposit.
     * @param usdcAmount Amount of USDC (in base units) included in the deposit.
     * @param depositValueUsdc Computed deposit value expressed in USDC base units.
     */
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
