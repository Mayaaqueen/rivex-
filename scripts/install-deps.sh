#!/bin/bash

echo "🔧 Installing Foundry dependencies for RivexFi Transparent Proxy Protocol..."

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
    echo "✅ OpenZeppelin Contracts v5.4.0 installed"
else
    echo "❌ OpenZeppelin Contracts installation failed"
    exit 1
fi

if [ -d "lib/openzeppelin-contracts-upgradeable" ]; then
    echo "✅ OpenZeppelin Contracts Upgradeable v5.4.0 installed"
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

# Check specific files for Transparent Proxy
echo "🔍 Checking Transparent Proxy specific files..."

if [ -f "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol" ]; then
    echo "✅ TransparentUpgradeableProxy.sol found"
else
    echo "❌ TransparentUpgradeableProxy.sol not found"
fi

if [ -f "lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol" ]; then
    echo "✅ ProxyAdmin.sol found"
else
    echo "❌ ProxyAdmin.sol not found"
fi

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

echo "🎉 All dependencies for Transparent Proxy pattern installed successfully!"
echo "📝 Run 'forge build' to compile contracts"
echo "🧪 Run 'forge test' to run tests"
