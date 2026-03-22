// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";

library Config {
    using PoolIdLibrary for PoolKey;

    uint256 public constant HIGH_VOLATILITY = 3;

    uint256 public constant LOW_VOLATILITY = 1;

    uint256 public constant MEDIUM_VOLATILITY = 2;

    uint256 public constant LN_10001_SCALED = 99995000499987500;

    address public constant POOL_MANAGER_ADDRESS =
        0xE03A1074c86CFeDd5C142C4F04F1a1536e203543;

    IPoolManager public constant poolManager =
        IPoolManager(POOL_MANAGER_ADDRESS);

    address public constant POSITION_MANAGER_ADDRESS =
        0x429ba70129df741B2Ca2a85BC3A2a3328e5c09b4;

    IPositionManager public constant positionManager =
        IPositionManager(POSITION_MANAGER_ADDRESS);

    int24 public constant TICK_SPACING = 60;

    uint24 public constant SWAP_FEES = 3000;

    uint256 LAMBDA = 943,874,312,221,817,000;

    uint256 ONE_MINUS_LAMBDA = 56,125,687,778,183,000; 

    uint256 LNSQ_1E18 = 9,999,000,150; 

    uint256 Tmin = 5 minutes;

    uint256 N_year = 105120; 

    address public constant USDC_ADDRESS =
        0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238;

    function poolKey() internal pure returns (PoolKey memory) {
        return
            PoolKey({
                currency0: Currency.wrap(address(0)),
                currency1: Currency.wrap(USDC_ADDRESS),
                fee: SWAP_FEES,
                tickSpacing: TICK_SPACING,
                hooks: IHooks(address(0))
            });
    }

    function poolId() internal pure returns (PoolId) {
        return poolKey().toId();
    }
}
