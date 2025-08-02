#!/bin/bash

# Deploy script for RivexFi Lending Protocol on Base Network

echo "🚀 Deploying RivexFi Lending Protocol to Base Network..."

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
echo "🌐 Deploying to Base mainnet..."
forge script script/Deploy.s.sol:DeployScript --rpc-url base --broadcast --verify

if [ $? -eq 0 ]; then
    echo "✅ Deployment successful!"
    echo "📋 Check the deployment addresses in the broadcast folder"
else
    echo "❌ Deployment failed"
    exit 1
fi

echo "🎉 RivexFi Lending Protocol deployed successfully!"
