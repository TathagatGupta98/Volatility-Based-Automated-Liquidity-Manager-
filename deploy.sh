#!/bin/bash

##############################################
# VaultIntegration Simple Deployment Script
# Usage: ./deploy.sh <RPC_URL> <PRIVATE_KEY>
# Or set environment variables:
#   export RPC_URL=<your_rpc_url>
#   export PRIVATE_KEY=<your_private_key>
#   ./deploy.sh
##############################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get RPC_URL and PRIVATE_KEY from arguments or environment
RPC_URL="${1:-$RPC_URL}"
PRIVATE_KEY="${2:-$PRIVATE_KEY}"

# Validate inputs
if [ -z "$RPC_URL" ]; then
    echo -e "${RED}❌ Error: RPC_URL not provided${NC}"
    echo "Usage: ./deploy.sh <RPC_URL> <PRIVATE_KEY>"
    echo "Or set environment variables:"
    echo "  export RPC_URL=<your_rpc_url>"
    echo "  export PRIVATE_KEY=<your_private_key>"
    exit 1
fi

if [ -z "$PRIVATE_KEY" ]; then
    echo -e "${RED}❌ Error: PRIVATE_KEY not provided${NC}"
    echo "Usage: ./deploy.sh <RPC_URL> <PRIVATE_KEY>"
    echo "Or set environment variables:"
    echo "  export RPC_URL=<your_rpc_url>"
    echo "  export PRIVATE_KEY=<your_private_key>"
    exit 1
fi

# Change to logic directory
cd "$(dirname "$0")/logic" || exit 1

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}VaultIntegration Deployment Script${NC}"
echo -e "${BLUE}========================================${NC}\n"

# Check if forge is installed
if ! command -v forge &> /dev/null; then
    echo -e "${RED}❌ Error: Foundry (forge) is not installed${NC}"
    echo "Install from: https://book.getfoundry.sh/getting-started/installation.html"
    exit 1
fi

echo -e "${YELLOW}⏳ Compiling contracts...${NC}"
forge build

echo -e "${GREEN}✅ Compilation successful${NC}\n"

echo -e "${YELLOW}⏳ Deploying VaultIntegration...${NC}"
echo -e "${BLUE}RPC URL: ${RPC_URL}${NC}\n"

# Deploy using forge script
forge script script/DeployVault.s.sol:DeployVault \
    --rpc-url "$RPC_URL" \
    --private-key "$PRIVATE_KEY" \
    --broadcast \
    --verify

echo -e "\n${GREEN}✅ Deployment complete!${NC}\n"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Next Steps${NC}"
echo -e "${BLUE}========================================${NC}\n"

echo "1. Deploy PoolInteractor and PositionTracker contracts"
echo "2. Call configureModules() to link components:"
echo -e "   ${YELLOW}vault.configureModules(${NC}"
echo -e "       poolInteractorAddress,${NC}"
echo -e "       positionTrackerAddress,${NC}"
echo -e "       rebalanceLiquidityAmount,  // e.g., 1000000${NC}"
echo -e "       automationInterval         // e.g., 300${NC}"
echo -e "   );${NC}"
echo "3. Call setSelfAsPoolUpdater() to enable automation"
echo "4. Register vault with Chainlink Automation"
echo "5. Users can start depositing ETH/USDC"
echo ""
echo -e "${BLUE}Query Vault Status:${NC}"
echo "  forge script script/DeployVault.s.sol:GetVaultStatus --rpc-url <RPC_URL>"
echo ""
echo -e "${BLUE}========================================\n${NC}"
