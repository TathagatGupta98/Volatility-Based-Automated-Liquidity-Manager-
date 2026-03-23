// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {FullMath} from "v4-core/src/libraries/FullMath.sol";

contract ProbePoolPrice is Script {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    IPoolManager constant poolManager = IPoolManager(0xE03A1074c86CFeDd5C142C4F04F1a1536e203543);
    address constant USDC = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238;
    address constant WETH = 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14;

    function quote(address base, uint24 fee, int24 spacing) internal view returns (uint256 priceRaw, int24 tick) {
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(base),
            currency1: Currency.wrap(USDC),
            fee: fee,
            tickSpacing: spacing,
            hooks: IHooks(address(0))
        });

        (uint160 sqrtPriceX96, int24 t, , ) = poolManager.getSlot0(key.toId());
        tick = t;
        if (sqrtPriceX96 == 0) return (0, tick);

        uint256 priceX96 = FullMath.mulDiv(uint256(sqrtPriceX96), uint256(sqrtPriceX96), 1 << 96);
        priceRaw = FullMath.mulDiv(priceX96, 1e18, 1 << 96);
    }

    function run() external view {
        uint24[4] memory fees = [uint24(100), 500, 3000, 10000];
        int24[4] memory spacings = [int24(1), 10, 60, 200];
        address[2] memory bases = [address(0), WETH];

        console.log("Probing base/USDC pools (raw USDC for 1 base, 6 decimals):");
        for (uint256 b = 0; b < bases.length; b++) {
            console.log("base:", bases[b]);
            for (uint256 i = 0; i < fees.length; i++) {
                for (uint256 j = 0; j < spacings.length; j++) {
                    (uint256 p, int24 t) = quote(bases[b], fees[i], spacings[j]);
                    console.log("fee:", uint256(fees[i]));
                    console.log("spacing:", int256(spacings[j]));
                    console.log("tick:", int256(t));
                    console.log("priceRaw:", p);
                }
            }
        }
    }
}
