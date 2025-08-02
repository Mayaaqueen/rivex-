// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/**
 * @title wRivexETH - Wrapped RivexFi ETH Token
 * @notice This contract represents wrapped ETH with 1:1 backing ratio, similar to WETH
 * @dev Upgradeable ERC20 token that wraps/unwraps ETH with access control and pausable functionality using Transparent Proxy
 */
contract wRivexETH is 
    Initializable,
    ERC20Upgradeable,
    ERC20PermitUpgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable
{
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    event Deposit(address indexed user, uint256 amount);
    event Withdrawal(address indexed user, uint256 amount);
    event ETHWithdrawn(address indexed owner, uint256 amount);
    event LiquidityAdded(address indexed owner, uint256 amount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the wRivexETH token contract
     * @dev Sets up ERC20, Permit, AccessControl, and Pausable functionality
     * @param initialOwner The address that will receive all admin roles
     * 
     * Success: Contract is initialized with proper roles and token metadata
     * Revert: If called more than once (already initialized)
     */
    function initialize(address initialOwner) public initializer {
        __ERC20_init("Wrapped RivexFi ETH", "wRivexETH");
        __ERC20Permit_init("Wrapped RivexFi ETH");
        __AccessControl_init();
        __Pausable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, initialOwner);
        _grantRole(MINTER_ROLE, initialOwner);
        _grantRole(BURNER_ROLE, initialOwner);
        _grantRole(PAUSER_ROLE, initialOwner);
    }

    /**
     * @notice Mints new wRivexETH tokens to a specified address
     * @dev Only addresses with MINTER_ROLE can call this function
     * @param to The address that will receive the minted tokens
     * @param amount The amount of tokens to mint (in wei)
     * 
     * Success: New tokens are minted and added to recipient's balance
     * Revert: If caller doesn't have MINTER_ROLE or contract is paused
     */
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    /**
     * @notice Burns tokens from the caller's balance
     * @dev Anyone can burn their own tokens
     * @param amount The amount of tokens to burn (in wei)
     * 
     * Success: Tokens are burned and removed from caller's balance
     * Revert: If caller has insufficient balance or contract is paused
     */
    function burn(uint256 amount) external {
        _burn(_msgSender(), amount);
    }

    /**
     * @notice Burns tokens from a specified account
     * @dev Only addresses with BURNER_ROLE can call this function
     * @param account The address from which tokens will be burned
     * @param amount The amount of tokens to burn (in wei)
     * 
     * Success: Tokens are burned from the specified account
     * Revert: If caller doesn't have BURNER_ROLE, account has insufficient balance, or contract is paused
     */
    function burnFrom(address account, uint256 amount) external onlyRole(BURNER_ROLE) {
        _burn(account, amount);
    }

    /**
     * @notice Pauses all token transfers and operations
     * @dev Only addresses with PAUSER_ROLE can call this function
     * 
     * Success: Contract is paused, all transfers are blocked
     * Revert: If caller doesn't have PAUSER_ROLE or contract is already paused
     */
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /**
     * @notice Unpauses the contract, allowing transfers and operations
     * @dev Only addresses with PAUSER_ROLE can call this function
     * 
     * Success: Contract is unpaused, transfers are allowed again
     * Revert: If caller doesn't have PAUSER_ROLE or contract is not paused
     */
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /**
     * @notice Internal function to handle token transfers with pause check
     * @dev OpenZeppelin v5.4.0 uses _update function for all transfer logic
     * @param from The address sending tokens
     * @param to The address receiving tokens
     * @param value The amount of tokens being transferred
     * 
     * Success: Tokens are transferred when contract is not paused
     * Revert: If contract is paused
     */
    function _update(address from, address to, uint256 value)
        internal
        override
        whenNotPaused
    {
        super._update(from, to, value);
    }

    /**
     * @notice Deposits ETH and mints equivalent wRivexETH tokens
     * @dev Converts ETH to wRivexETH at 1:1 ratio
     * 
     * Success: ETH is deposited and equivalent wRivexETH tokens are minted to sender
     * Revert: If no ETH sent or contract is paused
     */
    function deposit() external payable whenNotPaused {
        require(msg.value > 0, "wRivexETH: No ETH sent");
        _mint(msg.sender, msg.value);
        emit Deposit(msg.sender, msg.value);
    }

    /**
     * @notice Withdraws ETH by burning wRivexETH tokens
     * @dev Burns wRivexETH tokens and sends equivalent ETH to user
     * @param amount Amount of wRivexETH tokens to burn for ETH
     * 
     * Success: wRivexETH tokens are burned and equivalent ETH is sent to user
     * Revert: If insufficient balance, insufficient contract ETH, or contract is paused
     */
    function withdraw(uint256 amount) external whenNotPaused {
        require(amount > 0, "wRivexETH: Invalid amount");
        require(balanceOf(msg.sender) >= amount, "wRivexETH: Insufficient balance");
        require(address(this).balance >= amount, "wRivexETH: Insufficient ETH in contract");
        
        _burn(msg.sender, amount);
        
        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "wRivexETH: ETH transfer failed");
        
        emit Withdrawal(msg.sender, amount);
    }

    /**
     * @notice Allows owner to withdraw ETH for pool management and cleanup
     * @dev Only owner can withdraw ETH for liquidity management purposes
     * @param amount Amount of ETH to withdraw
     * 
     * Success: ETH is transferred to owner for pool management
     * Revert: If caller is not owner, insufficient balance, or transfer fails
     */
    function withdrawETH(uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(amount <= address(this).balance, "wRivexETH: Insufficient ETH balance");
        
        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "wRivexETH: ETH transfer failed");
        
        emit ETHWithdrawn(msg.sender, amount);
    }

    /**
     * @notice Allows owner to add liquidity to the pool
     * @dev Owner can add ETH to ensure sufficient liquidity for withdrawals
     * 
     * Success: ETH is added to contract balance for liquidity
     * Revert: If caller is not owner or no ETH sent
     */
    function addLiquidity() external payable onlyRole(DEFAULT_ADMIN_ROLE) {
        require(msg.value > 0, "wRivexETH: No ETH sent");
        emit LiquidityAdded(msg.sender, msg.value);
    }

    /**
     * @notice Fallback function to handle direct ETH deposits
     * @dev Automatically wraps ETH sent to contract into wRivexETH
     * 
     * Success: ETH is wrapped into wRivexETH tokens for sender
     * Revert: If contract is paused
     */
    receive() external payable {
        if (msg.value > 0) {
            _mint(msg.sender, msg.value);
            emit Deposit(msg.sender, msg.value);
        }
    }

    /**
     * @notice Gets the total ETH balance held by the contract
     * @return The contract's ETH balance
     * 
     * Success: Always returns current ETH balance
     * Revert: Never reverts
     */
    function getETHBalance() external view returns (uint256) {
        return address(this).balance;
    }
}
