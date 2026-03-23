// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {VaultIntegration} from "../src/VaultIntegration.sol";

/**
 * @title DeployVault Script
 * @notice Simple deployment script for the complete VaultIntegration protocol
 * @dev Run with: forge script script/DeployVault.s.sol:DeployVault --rpc-url <RPC_URL> --broadcast
 */
contract DeployVault is Script {
    
    /**
     * @notice Deploy the VaultIntegration contract
     * @dev This is the main entry point for the deployment script
     */
    function run() public {
        // Start broadcasting transactions
        vm.startBroadcast();

        // Deploy VaultIntegration (all-in-one vault contract)
        VaultIntegration vault = new VaultIntegration();
        
        // Stop broadcasting
        vm.stopBroadcast();

        // Log deployment info
        console.log("\n========================================");
        console.log("VaultIntegration Deployment Complete");
        console.log("========================================");
        console.log("Vault Address:", address(vault));
        console.log("Deployed by:", msg.sender);
        console.log("Block number:", block.number);
        console.log("\n--- Next Steps ---");
        console.log("1. Deploy PoolInteractor contract");
        console.log("2. Deploy PositionTracker contract");
        console.log("3. Call configureModules() to link components:");
        console.log("   vault.configureModules(");
        console.log("       poolInteractorAddress,");
        console.log("       positionTrackerAddress,");
        console.log("       rebalanceLiquidityAmount,  // e.g., 1000000");
        console.log("       automationInterval         // e.g., 300 seconds");
        console.log("   );");
        console.log("4. Set vault as pool updater:");
        console.log("   vault.setSelfAsPoolUpdater();");
        console.log("5. Register with Chainlink Automation:");
        console.log("   - Use vault address");
        console.log("   - Set checkUpkeep() as the upkeep function");
        console.log("6. Users can now deposit ETH/USDC");
        console.log("========================================\n");
    }

    /**
     * @notice Alternative deployment with configuration (requires parameters)
     * @dev This function remains callable but run() is the default entry point
     */
    function deployAndConfigure(
        address poolInteractorAddress,
        address positionTrackerAddress,
        uint256 rebalanceLiduidityAmount,
        uint256 automationInterval
    ) public returns (VaultIntegration) {
        vm.startBroadcast();

        // Deploy vault
        VaultIntegration vault = new VaultIntegration();

        // Configure modules in one call
        vault.configureModules(
            poolInteractorAddress,
            positionTrackerAddress,
            rebalanceLiduidityAmount,
            automationInterval
        );

        // Set this vault as the volatility updater for the pool
        vault.setSelfAsPoolUpdater();

        vm.stopBroadcast();

        console.log("VaultIntegration deployed and configured at:", address(vault));
        return vault;
    }
}
