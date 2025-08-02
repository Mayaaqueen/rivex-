#!/bin/bash

echo "🔧 Installing Foundry dependencies for RivexFi Protocol..."

# Remove existing lib directory to start fresh
rm -rf lib/

# Initialize git submodules
git submodule update --init --recursive

# Install OpenZeppelin Contracts v5.4.0
echo "📦 Installing OpenZeppelin Contracts v5.4.0..."
forge install OpenZeppelin/openzeppelin-contracts@v5.4.0 --no-commit

# Install OpenZeppelin Contracts Upgradeable v5.4.0
echo "📦 Installing OpenZeppelin Contracts Upgradeable v5.4.0..."
forge install OpenZeppelin/openzeppelin-contracts-upgradeable@v5.4.0 --no-commit

# Install Chainlink contracts
echo "📦 Installing Chainlink contracts..."
forge install smartcontractkit/chainlink@v2.9.0 --no-commit

# Verify installations
echo "✅ Verifying installations..."

if [ -d "lib/openzeppelin-contracts" ]; then
    echo "✅ OpenZeppelin Contracts installed"
else
    echo "❌ OpenZeppelin Contracts installation failed"
    exit 1
fi

if [ -d "lib/openzeppelin-contracts-upgradeable" ]; then
    echo "✅ OpenZeppelin Contracts Upgradeable installed"
else
    echo "❌ OpenZeppelin Contracts Upgradeable installation failed"
    exit 1
fi

if [ -d "lib/chainlink" ]; then
    echo "✅ Chainlink contracts installed"
else
    echo "❌ Chainlink contracts installation failed"
    exit 1
fi

# Check specific files
echo "🔍 Checking specific contract files..."

if [ -f "lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/IERC20Upgradeable.sol" ]; then
    echo "✅ IERC20Upgradeable.sol found"
else
    echo "❌ IERC20Upgradeable.sol not found"
fi

if [ -f "lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol" ]; then
    echo "✅ SafeERC20Upgradeable.sol found"
else
    echo "❌ SafeERC20Upgradeable.sol not found"
fi

echo "🎉 All dependencies installed successfully!"
echo "📝 Run 'forge build' to compile contracts"
