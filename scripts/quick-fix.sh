#!/bin/bash

echo "🚀 Quick Fix for RivexFi Protocol Compilation Issues..."

# Clean everything
echo "🧹 Cleaning previous installations..."
rm -rf lib/ cache/ out/

# Reinstall forge dependencies
echo "📦 Reinstalling dependencies..."
forge install

# Install specific versions
forge install OpenZeppelin/openzeppelin-contracts@v5.4.0 --no-commit
forge install OpenZeppelin/openzeppelin-contracts-upgradeable@v5.4.0 --no-commit
forge install smartcontractkit/chainlink@v2.9.0 --no-commit

# Update git modules
git submodule update --init --recursive

# Build with force
echo "🏗️ Building contracts..."
forge build --force

if [ $? -eq 0 ]; then
    echo "✅ Quick fix successful! Contracts compiled."
    echo "🧪 Running tests..."
    forge test
else
    echo "❌ Quick fix failed. Run troubleshoot script for more details."
    echo "💡 Try running: npm run troubleshoot"
fi
