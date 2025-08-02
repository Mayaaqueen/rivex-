#!/bin/bash

# Deploy script for RivexFi Transparent Upgradeable Lending Protocol with Liquid Staking on Base Network

echo "🚀 Deploying RivexFi Transparent Upgradeable Lending Protocol with Liquid Staking to Base Network..."

# Check if required environment variables are set
if [ -z "$PRIVATE_KEY" ]; then
    echo "❌ Error: PRIVATE_KEY environment variable is not set"
    exit 1
fi

if [ -z "$BASESCAN_API_KEY" ]; then
    echo "⚠️  Warning: BASESCAN_API_KEY not set, contract verification will be skipped"
fi

# Install dependencies for OpenZeppelin v5.4.0
echo "📦 Installing dependencies..."

# Clean previous installations
rm -rf lib/ cache/ out/

# Install dependencies
forge install OpenZeppelin/openzeppelin-contracts@v5.4.0 --no-commit
forge install OpenZeppelin/openzeppelin-contracts-upgradeable@v5.4.0 --no-commit
forge install smartcontractkit/chainlink@v2.9.0 --no-commit

# Update submodules
git submodule update --init --recursive

# Verify critical files exist
if [ ! -f "lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/IERC20Upgradeable.sol" ]; then
    echo "❌ Critical OpenZeppelin files missing. Please run: npm run install-deps"
    exit 1
fi

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

# Deploy to Base mainnet using Transparent Proxy
echo "🌐 Deploying Transparent Upgradeable contracts to Base mainnet..."
forge script script/DeployTransparent.s.sol:DeployTransparentScript --rpc-url base --broadcast --verify

if [ $? -eq 0 ]; then
    echo "✅ Deployment successful!"
    echo "📋 Check the deployment addresses in the broadcast folder"
else
    echo "❌ Deployment failed"
    exit 1
fi

echo "🎉 RivexFi Transparent Upgradeable Lending Protocol with Liquid Staking deployed successfully!"
echo "📝 Features deployed:"
echo "   - Transparent Upgradeable RivexFi Token (RIVEX) with governance"
echo "   - Transparent Upgradeable Wrapped RivexFi ETH (wRivexETH) with 1:1 backing"
echo "   - Transparent Upgradeable Liquid Staking Protocol with rewards"
echo "   - Transparent Upgradeable Lending Protocol"
echo "   - Transparent Upgradeable Chainlink Price Oracle integration"
echo "   - All contracts are upgradeable via Transparent Proxy pattern"
echo "   - Compatible with OpenZeppelin v5.4.0"
echo "   - ProxyAdmin contract for secure upgrades"
