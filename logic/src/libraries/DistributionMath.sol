//SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
  * @title DistributionMath
  * @dev Library for distributing liquidity based on weights
 */
library DistributionMath {

    /**
     * @dev Distributes total liquidity based on provided weights
     * @param totalLiquidity The total liquidity to be distributed
     * @param weights An array of weights corresponding to each distribution
     * @return weightedLiquidity An array of liquidity amounts corresponding to each weight
     */
    function Distribute(uint256 totalLiquidity , uint256[] calldata weights) internal pure returns (uint256[] memory weightedLiquidity) {
       uint256 numberOfSlots = weights.length;

       weightedLiquidity = new uint256[](numberOfSlots);

       for (uint256 i = 0; i < numberOfSlots; i++){
          weightedLiquidity[i] = (totalLiquidity * weights[i]) / 100;
       }


    }  
}