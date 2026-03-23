#!/usr/bin/env node

/**
 * @title VaultIntegration Deployment Script
 * @notice Simple deployment script using ethers.js
 * @dev Run with: node deploy.js
 * 
 * USAGE:
 * 1. Set RPC_URL environment variable: export RPC_URL=<your_rpc_url>
 * 2. Set PRIVATE_KEY environment variable: export PRIVATE_KEY=<your_private_key>
 * 3. Run: node deploy.js
 */

const ethers = require('ethers');
const fs = require('fs');
const path = require('path');

// Load environment variables
require('dotenv').config();

const RPC_URL = process.env.RPC_URL || 'http://localhost:8545';
const PRIVATE_KEY = process.env.PRIVATE_KEY;

if (!PRIVATE_KEY) {
    console.error('❌ Error: PRIVATE_KEY environment variable not set');
    console.error('Please set: export PRIVATE_KEY=<your_private_key>');
    process.exit(1);
}

async function deployVault() {
    console.log('\n========================================');
    console.log('VaultIntegration Deployment Script');
    console.log('========================================\n');

    try {
        // Connect to network
        const provider = new ethers.JsonRpcProvider(RPC_URL);
        const signer = new ethers.Wallet(PRIVATE_KEY, provider);
        const signerAddress = signer.address;

        console.log(`📍 Network RPC: ${RPC_URL}`);
        console.log(`🔐 Deployer Address: ${signerAddress}`);

        // Get account balance
        const balance = await provider.getBalance(signerAddress);
        const balanceInEth = ethers.formatEther(balance);
        console.log(`💰 Account Balance: ${balanceInEth} ETH\n`);

        if (balance === 0n) {
            console.error('❌ Error: Account has no balance. Please fund the account.');
            process.exit(1);
        }

        // Load contract ABI and bytecode
        // In a real scenario, you would compile and get the ABI/bytecode from build artifacts
        console.log('⏳ Loading contract artifacts...');

        // For now, we'll show the deployment structure
        // In production, you would load from compiled artifacts (e.g., forge build output)
        const vaultIntegrationPath = path.join(__dirname, '../src/VaultIntegration.sol');
        
        if (!fs.existsSync(vaultIntegrationPath)) {
            console.error(`❌ Error: Could not find ${vaultIntegrationPath}`);
            console.error('Please ensure the contract is at the expected path');
            process.exit(1);
        }

        console.log(`✅ Found VaultIntegration.sol`);

        // Deploy using ethers ContractFactory (requires compiled ABI/bytecode)
        console.log('\n⏳ Compiling contracts...');
        console.log('(Note: In production, use pre-compiled artifacts from forge build)\n');

        // For demonstration, show the deployment pattern
        console.log('📋 Deployment Pattern:');
        console.log('--------------------');
        console.log(`
// Load compiled contract
const vaultABI = require('./artifacts/VaultIntegration.json').abi;
const vaultBytecode = require('./artifacts/VaultIntegration.json').bytecode;

// Create factory
const factory = new ethers.ContractFactory(vaultABI, vaultBytecode, signer);

// Deploy
const vault = await factory.deploy();
await vault.waitForDeployment();

const deployedAddress = await vault.getAddress();
console.log('Vault deployed at:', deployedAddress);
        `);

        console.log('\n========================================');
        console.log('Deployment Instructions');
        console.log('========================================\n');

        console.log('QUICK START:');
        console.log('1️⃣  Compile contracts with Foundry:');
        console.log('   forge build\n');

        console.log('2️⃣  Deploy with Foundry (Recommended):');
        console.log('   forge script script/DeployVault.s.sol:DeployVault \\');
        console.log('   --rpc-url $RPC_URL \\');
        console.log('   --private-key $PRIVATE_KEY \\');
        console.log('   --broadcast\n');

        console.log('3️⃣  OR Deploy with Hardhat:');
        console.log('   npx hardhat run scripts/deploy.js --network <network>\n');

        console.log('POST-DEPLOYMENT CONFIGURATION:');
        console.log('───────────────────────────────────');
        console.log('Once vault is deployed at address <VAULT_ADDRESS>:\n');

        console.log('1. Deploy supporting contracts:');
        console.log('   - PoolInteractor');
        console.log('   - PositionTracker\n');

        console.log('2. Configure vault (from PoolInteractor/PositionTracker addresses):');
        console.log(`
const vault = new ethers.Contract('<VAULT_ADDRESS>', vaultABI, signer);
const tx = await vault.configureModules(
    poolInteractorAddress,      // Address of PoolInteractor
    positionTrackerAddress,     // Address of PositionTracker
    ethers.parseEther('1000'),  // Rebalance liquidity (e.g., 1000 tokens)
    300                         // Automation interval (e.g., 300 seconds)
);
await tx.wait();
console.log('✅ Vault configured');
        `);

        console.log('3. Set vault as pool updater:');
        console.log(`
const tx2 = await vault.setSelfAsPoolUpdater();
await tx2.wait();
console.log('✅ Vault set as pool updater');
        `);

        console.log('\n4. Register with Chainlink Automation:');
        console.log('   - Go to automation.chain.link');
        console.log('   - Create new upkeep');
        console.log(`   - Contract address: <VAULT_ADDRESS>`);
        console.log('   - Check function: checkUpkeep\n');

        console.log('5. Users can now interact:');
        console.log(`
const vault = new ethers.Contract('<VAULT_ADDRESS>', vaultABI, userSigner);

// Deposit 1000 USDC + 1 ETH
const tx = await vault.userDeposit(
    ethers.parseUnits('1000', 6), // 1000 USDC (6 decimals)
    { value: ethers.parseEther('1') }
);
await tx.wait();
console.log('✅ Deposit complete, user shares minted');

// Check share balance
const balance = await vault.getUserShareBalance(userAddress);
console.log('User shares:', balance.sharesOwned.toString());

// Withdraw (burn shares)
const tx2 = await vault.userWithdraw(sharesToBurn);
await tx2.wait();
console.log('✅ Withdrawal complete');
        `);

        console.log('\n========================================');
        console.log('Useful Query Functions');
        console.log('========================================\n');

        console.log('Check vault health:');
        console.log('  const health = await vault.getProtocolHealthStatus();');
        console.log('  console.log("Vault Ready:", health.vaultIsReady);\n');

        console.log('Get complete status:');
        console.log('  const status = await vault.getCompleteProtocolStatus();');
        console.log('  console.log("Total NAV:", status.totalVaultNav.toString());\n');

        console.log('Check if rebalance needed:');
        console.log('  const {shouldRebalance} = await vault.previewShouldRebalanceNow();');
        console.log('  console.log("Needs rebalance:", shouldRebalance);\n');

        console.log('Get user shares:');
        console.log('  const {sharesOwned} = await vault.getUserShareBalance(userAddress);');
        console.log('  console.log("User shares:", sharesOwned.toString());\n');

        console.log('========================================\n');

    } catch (error) {
        console.error('❌ Deployment failed:', error.message);
        console.error(error);
        process.exit(1);
    }
}

// Run deployment
deployVault().catch((error) => {
    console.error('❌ Fatal error:', error);
    process.exit(1);
});
