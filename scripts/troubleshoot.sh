#!/bin/bash

echo "🔍 RivexFi Protocol Troubleshooting..."

echo "📁 Checking directory structure..."
ls -la lib/

echo "📦 Checking OpenZeppelin Contracts..."
if [ -d "lib/openzeppelin-contracts" ]; then
    echo "✅ openzeppelin-contracts directory exists"
    ls -la lib/openzeppelin-contracts/contracts/token/ERC20/ | head -10
else
    echo "❌ openzeppelin-contracts directory missing"
fi

echo "📦 Checking OpenZeppelin Contracts Upgradeable..."
if [ -d "lib/openzeppelin-contracts-upgradeable" ]; then
    echo "✅ openzeppelin-contracts-upgradeable directory exists"
    ls -la lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/ | head -10
else
    echo "❌ openzeppelin-contracts-upgradeable directory missing"
fi

echo "📦 Checking Chainlink..."
if [ -d "lib/chainlink" ]; then
    echo "✅ chainlink directory exists"
else
    echo "❌ chainlink directory missing"
fi

echo "🔧 Checking remappings..."
forge remappings

echo "🏗️ Attempting to build..."
forge build --force

if [ $? -eq 0 ]; then
    echo "✅ Build successful!"
else
    echo "❌ Build failed. Check the errors above."
fi
