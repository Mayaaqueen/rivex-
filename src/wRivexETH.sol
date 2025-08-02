// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title wRivexETH - Wrapped RivexFi ETH Token
 * @notice This contract represents wrapped ETH with 1:1 backing ratio
 * @dev Upgradeable ERC20 token with access control and pausable functionality
 */
contract wRivexETH is 
    Initializable,
    ERC20Upgradeable,
    ERC20PermitUpgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable
{
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the wRivexETH token contract
     * @dev Sets up ERC20, Permit, AccessControl, Pausable, and UUPS functionality
     * @param admin The address that will receive all admin roles
     * 
     * Success: Contract is initialized with proper roles and token metadata
     * Revert: If called more than once (already initialized)
     */
    function initialize(address admin) public initializer {
        __ERC20_init("Wrapped RivexFi ETH", "wRivexETH");
        __ERC20Permit_init("Wrapped RivexFi ETH");
        __AccessControl_init();
        __Pausable_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, admin);
        _grantRole(BURNER_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);
        _grantRole(UPGRADER_ROLE, admin);
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
     * @notice Authorizes contract upgrades
     * @dev Only addresses with UPGRADER_ROLE can authorize upgrades
     * @param newImplementation The address of the new implementation contract
     * 
     * Success: Upgrade is authorized
     * Revert: If caller doesn't have UPGRADER_ROLE
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}

    /**
     * @notice Internal function to handle token transfers with pause check
     * @dev Overrides ERC20 _beforeTokenTransfer to include pause functionality
     * @param from The address sending tokens
     * @param to The address receiving tokens
     * @param value The amount of tokens being transferred
     * 
     * Success: Tokens are transferred when contract is not paused
     * Revert: If contract is paused
     */
    function _beforeTokenTransfer(address from, address to, uint256 value)
        internal
        override
        whenNotPaused
    {
        super._beforeTokenTransfer(from, to, value);
    }
}
