// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {VaultIntegration} from "../src/VaultIntegration.sol";
import {PositionTracker} from "../src/pool/PositionTracker.sol";
import {PoolInteractor} from "../src/pool/PoolInteractor.sol";

contract ConfigureEngine is Script {
    function run() external {
        address payable vaultAddress = payable(vm.envAddress("VAULT_ADDRESS"));
        uint256 rebalanceLiquidity = vm.envUint("REBALANCE_LIQUIDITY");
        uint256 upkeepInterval = vm.envUint("UPKEEP_INTERVAL");

        vm.startBroadcast();

        PositionTracker tracker = new PositionTracker();
        PoolInteractor interactor = new PoolInteractor(address(tracker), vaultAddress);
        tracker.initialize(address(interactor));

        VaultIntegration vault = VaultIntegration(vaultAddress);
        vault.configureModules(address(interactor), address(tracker), rebalanceLiquidity, upkeepInterval);

        vm.stopBroadcast();

        console.log("Engine configured for vault:", vaultAddress);
        console.log("PositionTracker:", address(tracker));
        console.log("PoolInteractor:", address(interactor));
        console.log("RebalanceLiquidity:", rebalanceLiquidity);
        console.log("UpkeepInterval:", upkeepInterval);
    }
}
