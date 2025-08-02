#!/bin/bash

# Deploy script for RivexFi Upgradeable Lending Protocol with Liquid Staking on Base Network

echo "🚀 Deploying RivexFi Upgradeable Lending Protocol with Liquid Staking to Base Network..."

# Check if required environment variables are set
if [ -z "$PRIVATE_KEY" ]; then
    echo "❌ Error: PRIVATE_KEY environment variable is not set"
    exit 1
fi

if [ -z "$BASESCAN_API_KEY" ]; then
    echo "⚠️  Warning: BASESCAN_API_KEY not set, contract verification will be skipped"
fi

# Install dependencies
echo "📦 Installing dependencies..."
forge install OpenZeppelin/openzeppelin-contracts@v5.0.0 --no-commit
forge install OpenZeppelin/openzeppelin-contracts-upgradeable@v5.0.0 --no-commit
forge install smartcontractkit/chainlink@v2.9.0 --no-commit

# Compile contracts
echo "🔨 Compiling contracts..."
forge build

if [ $? -ne 0 ]; then
    echo "❌ Compilation failed"
    exit 1
fi

# Run tests
echo "🧪 Running tests..."
forge test

if [ $? -ne 0 ]; then
    echo "❌ Tests failed"
    exit 1
fi

# Deploy to Base mainnet
echo "🌐 Deploying upgradeable contracts to Base mainnet..."
forge script script/DeployUpgradeable.s.sol:DeployUpgradeableScript --rpc-url base --broadcast --verify

if [ $? -eq 0 ]; then
    echo "✅ Deployment successful!"
    echo "📋 Check the deployment addresses in the broadcast folder"
else
    echo "❌ Deployment failed"
    exit 1
fi

echo "🎉 RivexFi Upgradeable Lending Protocol with Liquid Staking deployed successfully!"
echo "📝 Features deployed:"
echo "   - Upgradeable RivexFi Token (RIVEX) with governance"
echo "   - Wrapped RivexFi ETH (wRivexETH) with 1:1 backing"
echo "   - Liquid Staking Protocol with rewards"
echo "   - Upgradeable Lending Protocol"
echo "   - Chainlink Price Oracle integration"
echo "   - All contracts are upgradeable via UUPS proxy pattern"
