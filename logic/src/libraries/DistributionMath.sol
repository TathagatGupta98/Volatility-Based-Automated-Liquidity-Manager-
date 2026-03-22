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

       if( numberOfSlots == 0){
          revert WeigthsArrayLengthZero();
       }

       if(!ValidateWeights(weights)){
          revert SumweightsNotEqual100();
       }

       weightedLiquidity = new uint256[](numberOfSlots);

       for (uint256 i = 0; i < numberOfSlots; i++){
          weightedLiquidity[i] = (totalLiquidity * weights[i]) / 100;
       }

       uint256 dust = calculateDust(totalLiquidity, weightedLiquidity);

       weightedLiquidity[numberOfSlots/2] = weightedLiquidity[numberOfSlots/2] + dust;     
    }  


     /**
      * @dev Validates that the sum of weights equals 100
      * @param weights An array of weights to be validated
      * @return isValid A boolean indicating whether the weights are valid
      */
    function ValidateWeights(uint256[] calldata weights) internal pure returns (bool isValid) {
        uint256 totalWeight = 0;
        for (uint256 i =0 ; i < weights.length ; i++){
          totalWeight += weights[i];
        }
        isValid = (totalWeight == 100);
    }

     /**
      * @dev Calculates the dust amount after distribution
      * @param totalLiquidity The total liquidity that was distributed
      * @param weightedLiquidity An array of liquidity amounts that were distributed
      * @return dust The remaining liquidity that was not distributed due to rounding
      */
    function calculateDust(uint256 totalLiquidity, uint256[] memory weightedLiquidity) internal pure returns (uint256 dust) {
        uint256 distributedAmount = 0;
        for( uint256 i=0 ; i < weightedLiquidity.length; i++){
          distributedAmount += weightedLiquidity[i];
        }
        dust = totalLiquidity - distributedAmount;
    }
}