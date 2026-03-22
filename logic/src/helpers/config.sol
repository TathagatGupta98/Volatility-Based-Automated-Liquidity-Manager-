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

    uint256 public constant LAMBDA = 943_874_312_221_817_000;

    uint256 public constant ONE_MINUS_LAMBDA = 56_125_687_778_183_000;

    uint256 public constant LNSQ_1E18 = 9_999_000_150;

    uint256 public constant TMIN = 5 minutes;

    uint256 public constant N_YEAR = 105120;

    address public constant USDC_ADDRESS =
        0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238;

    address public constant PERMIT2_ADDRESS = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

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

    uint8 public volatility_index = LOW_VOLATILITY;
}
