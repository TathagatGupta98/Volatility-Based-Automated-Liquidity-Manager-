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
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IChainlinkAggregatorV3} from "../interfaces/IChainlinkAggregatorV3.sol";

/* -------------------------------------------------------------------------- */
/*                                  contract                                  */
/* -------------------------------------------------------------------------- */
abstract contract ShareAccounting is VaultStorage{

    using StateLibrary for IPoolManager;

    /**
     * @notice Returns the current ETH/USDC price from the pool slot0 observation.
     * @dev Reads `sqrtPriceX96` and converts to a 1e18-scaled USDC price.
     * @return p_actual The current ETH price denominated in USDC (scaled to 1e18 where applicable).
     */
    function getEthUsdcPrice() public view returns (uint256 p_actual) {
        uint256 poolPrice = _poolEthUsdcPrice();
        uint256 oraclePrice = _oracleEthUsdcPrice();

        if (oraclePrice == 0) return poolPrice;
        if (poolPrice == 0) return oraclePrice;

        uint256 diff = poolPrice > oraclePrice ? poolPrice - oraclePrice : oraclePrice - poolPrice;
        if (diff * 10_000 > oraclePrice * Config.MAX_POOL_ORACLE_DEVIATION_BPS) {
            return oraclePrice;
        }

        return poolPrice;
    }

    function _poolEthUsdcPrice() internal view returns (uint256) {
        (uint160 sqrtPriceX96, , , ) = poolManager.getSlot0(Config.poolId());
        uint256 priceX96 = FullMath.mulDiv(uint256(sqrtPriceX96), uint256(sqrtPriceX96), 1 << 96);
        return FullMath.mulDiv(priceX96, ETH_DECIMALS, 1 << 96);
    }

    function _oracleEthUsdcPrice() internal view returns (uint256) {
        IChainlinkAggregatorV3 feed = IChainlinkAggregatorV3(Config.CHAINLINK_ETH_USD_FEED);
        (, int256 answer, , uint256 updatedAt, ) = feed.latestRoundData();

        if (answer <= 0) return 0;
        if (updatedAt == 0) return 0;
        if (updatedAt + Config.ORACLE_STALE_THRESHOLD < block.timestamp) return 0;

        uint256 unsignedAnswer = uint256(answer);
        uint8 feedDecimals = feed.decimals();

        if (feedDecimals == 6) return unsignedAnswer;
        if (feedDecimals > 6) return unsignedAnswer / (10 ** (feedDecimals - 6));
        return unsignedAnswer * (10 ** (6 - feedDecimals));
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
        uint256 ethAmountInUsdc = FullMath.mulDiv(ethAmount, ethPriceUsdc, ETH_DECIMALS);
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
        if (!initialized) {
            // Bootstrapping: scale by WAD
            sharesToMint = FullMath.mulDiv(depositValueUsd, WAD, USDC_DECIMALS);
        } else {
            sharesToMint = FullMath.mulDiv(depositValueUsd, totalShares, currentNavUsdc);
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
        ethToReturn  = FullMath.mulDiv(sharesToBurn, currentTotalEth, totalShares);
        usdcToReturn = FullMath.mulDiv(sharesToBurn, currentTotalUsdc, totalShares);
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
