# RivexFi Upgradeable Lending Protocol

A comprehensive DeFi lending protocol with liquid staking capabilities, built on Base Network using upgradeable smart contracts.

## 🚀 Features

- **Upgradeable Architecture**: All contracts use UUPS proxy pattern for seamless upgrades
- **Lending Protocol**: Supply and borrow assets with dynamic interest rates
- **Liquid Staking**: Stake ETH and receive wRivexETH tokens with rewards
- **Governance Token**: RIVEX token with voting capabilities and permit functionality
- **Price Oracle**: Chainlink integration for real-time price feeds
- **Access Control**: Role-based permissions for secure operations

## 📋 Contracts

### Core Contracts
- `RivexTokenUpgradeable.sol` - Governance token with voting and permit
- `wRivexETH.sol` - Wrapped ETH token for liquid staking
- `LiquidStaking.sol` - Liquid staking protocol with rewards
- `RivexLendingUpgradeable.sol` - Main lending protocol
- `PriceOracleUpgradeable.sol` - Chainlink price oracle integration

### Deployment Scripts
- `DeployUpgradeable.s.sol` - Initial deployment script
- `Upgrade.s.sol` - Contract upgrade script
- `deploy-upgradeable.sh` - Bash deployment script

## 🛠️ Setup

### Prerequisites
- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Node.js and npm

### Installation

1. **Install dependencies:**
\`\`\`bash
forge install OpenZeppelin/openzeppelin-contracts@v5.0.0 --no-commit
forge install OpenZeppelin/openzeppelin-contracts-upgradeable@v5.0.0 --no-commit
forge install smartcontractkit/chainlink@v2.9.0 --no-commit
\`\`\`

2. **Compile contracts:**
\`\`\`bash
forge build
\`\`\`

3. **Run tests:**
\`\`\`bash
forge test
\`\`\`

## 🚀 Deployment

### Environment Variables
Create a `.env` file:
\`\`\`bash
PRIVATE_KEY=your_private_key
BASESCAN_API_KEY=your_basescan_api_key
\`\`\`

### Deploy to Base Network
\`\`\`bash
# Deploy all contracts
npm run deploy

# Or deploy manually
forge script script/DeployUpgradeable.s.sol:DeployUpgradeableScript --rpc-url base --broadcast --verify
\`\`\`

### Upgrade Contracts
\`\`\`bash
# Set proxy addresses in .env
RIVEX_TOKEN_PROXY=0x...
PRICE_ORACLE_PROXY=0x...
WRIVEXETH_PROXY=0x...
LIQUID_STAKING_PROXY=0x...
RIVEX_LENDING_PROXY=0x...

# Run upgrade
npm run upgrade
\`\`\`

## 📊 Usage

### Liquid Staking
1. **Stake ETH**: Send ETH to LiquidStaking contract or call `stake()`
2. **Receive wRivexETH**: Get liquid staking tokens representing your stake
3. **Earn Rewards**: Automatic reward distribution increases exchange rate
4. **Unstake**: Call `unstake()` to redeem ETH (minus fee)

### Lending Protocol
1. **Supply Assets**: Call `supplyETH()` or `supply()` with tokens
2. **Borrow Assets**: Call `borrowETH()` or `borrow()` against collateral
3. **Repay Debt**: Call `repayETH()` or `repay()` to reduce debt
4. **Earn Interest**: Suppliers earn interest from borrowers

### Governance
1. **Delegate Votes**: Use `delegate()` to participate in governance
2. **Create Proposals**: Submit governance proposals
3. **Vote**: Use voting power to decide on protocol changes

## 🔒 Security

- **Access Control**: Role-based permissions for all critical functions
- **Pausable**: Emergency pause functionality for all contracts
- **Upgradeable**: UUPS proxy pattern with proper authorization
- **Oracle Security**: Price feed validation and staleness checks
- **Liquidation**: Automated liquidation for unhealthy positions

## 📈 Interest Rate Model

- **Base Rate**: 2% APY
- **Utilization Kink**: 80%
- **Multiplier**: 10% slope before kink
- **Jump Multiplier**: 109% slope after kink

## 🏛️ Governance

- **RIVEX Token**: ERC20 with voting capabilities
- **Roles**: Admin, Minter, Pauser, Burner, Upgrader
- **Timelock**: Recommended for production deployments

## 📄 License

MIT License - see LICENSE file for details.

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests
5. Submit a pull request

## 📞 Support

For questions and support, please open an issue on GitHub.
