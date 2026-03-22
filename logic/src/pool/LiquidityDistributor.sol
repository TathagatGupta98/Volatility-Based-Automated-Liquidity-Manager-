//SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "../libraries/DistributionMath.sol";

contract LiquidityDistributor {
    uint256 public totalLiquidity;
    uint256 public currentTick;
    uint256 public volatilityIndex;

    constructor(uint256 _totalLiquidity, uint256 _currentTick, uint256 _volatilityIndex) {
        totalLiquidity = _totalLiquidity;
        currentTick = _currentTick;
        volatilityIndex = _volatilityIndex;
    }
}
