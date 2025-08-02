// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20VotesUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title RivexTokenUpgradeable - RivexFi Governance Token
 * @notice ERC20 token with governance features, permit functionality, and access control
 * @dev Upgradeable token with voting capabilities and role-based permissions
 */
contract RivexTokenUpgradeable is 
    Initializable,
    ERC20Upgradeable,
    ERC20PermitUpgradeable,
    ERC20VotesUpgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable
{
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    uint256 public constant MAX_SUPPLY = 1_000_000_000 * 10**18; // 1 billion tokens

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the RivexFi token contract
     * @dev Sets up ERC20, Permit, Votes, AccessControl, Pausable, and UUPS functionality
     * @param admin The address that will receive all admin roles and initial token supply
     * 
     * Success: Contract is initialized with proper roles, token metadata, and initial supply minted to admin
     * Revert: If called more than once (already initialized)
     */
    function initialize(address admin) public initializer {
        __ERC20_init("RivexFi", "RIVEX");
        __ERC20Permit_init("RivexFi");
        __ERC20Votes_init();
        __AccessControl_init();
        __Pausable_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);
        _grantRole(BURNER_ROLE, admin);
        _grantRole(UPGRADER_ROLE, admin);
        
        // Mint initial supply to admin
        _mint(admin, MAX_SUPPLY);
    }

    /**
     * @notice Mints new RIVEX tokens to a specified address
     * @dev Only addresses with MINTER_ROLE can call this function, respects max supply limit
     * @param to The address that will receive the minted tokens
     * @param amount The amount of tokens to mint (in wei)
     * 
     * Success: New tokens are minted and added to recipient's balance
     * Revert: If caller doesn't have MINTER_ROLE, would exceed max supply, or contract is paused
     */
    function mint(address to, uint256 amount) public onlyRole(MINTER_ROLE) {
        require(totalSupply() + amount <= MAX_SUPPLY, "RivexToken: Max supply exceeded");
        _mint(to, amount);
    }

    /**
     * @notice Burns tokens from the caller's balance
     * @dev Anyone can burn their own tokens, reduces total supply
     * @param amount The amount of tokens to burn (in wei)
     * 
     * Success: Tokens are burned and removed from caller's balance, total supply decreases
     * Revert: If caller has insufficient balance or contract is paused
     */
    function burn(uint256 amount) public {
        _burn(_msgSender(), amount);
    }

    /**
     * @notice Burns tokens from a specified account
     * @dev Only addresses with BURNER_ROLE can call this function
     * @param account The address from which tokens will be burned
     * @param amount The amount of tokens to burn (in wei)
     * 
     * Success: Tokens are burned from the specified account, total supply decreases
     * Revert: If caller doesn't have BURNER_ROLE, account has insufficient balance, or contract is paused
     */
    function burnFrom(address account, uint256 amount) public onlyRole(BURNER_ROLE) {
        _burn(account, amount);
    }

    /**
     * @notice Pauses all token transfers and operations
     * @dev Only addresses with PAUSER_ROLE can call this function
     * 
     * Success: Contract is paused, all transfers and operations are blocked
     * Revert: If caller doesn't have PAUSER_ROLE or contract is already paused
     */
    function pause() public onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /**
     * @notice Unpauses the contract, allowing transfers and operations
     * @dev Only addresses with PAUSER_ROLE can call this function
     * 
     * Success: Contract is unpaused, transfers and operations are allowed again
     * Revert: If caller doesn't have PAUSER_ROLE or contract is not paused
     */
    function unpause() public onlyRole(PAUSER_ROLE) {
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
     * @notice Internal function to handle token transfers with pause check and voting power updates
     * @dev Overrides ERC20 and ERC20Votes _beforeTokenTransfer to include pause functionality
     * @param from The address sending tokens
     * @param to The address receiving tokens
     * @param amount The amount of tokens being transferred
     * 
     * Success: Tokens are transferred and voting power is updated when contract is not paused
     * Revert: If contract is paused
     */
    function _beforeTokenTransfer(address from, address to, uint256 amount)
        internal
        override
        whenNotPaused
    {
        super._beforeTokenTransfer(from, to, amount);
    }

    /**
     * @notice Internal function to handle token transfers with voting power updates
     * @dev Overrides ERC20 and ERC20Votes _afterTokenTransfer
     * @param from The address sending tokens
     * @param to The address receiving tokens
     * @param amount The amount of tokens being transferred
     * 
     * Success: Tokens are transferred and voting power is updated
     */
    function _afterTokenTransfer(address from, address to, uint256 amount)
        internal
        override(ERC20Upgradeable, ERC20VotesUpgradeable)
    {
        super._afterTokenTransfer(from, to, amount);
    }

    /**
     * @notice Internal function to handle minting with voting power updates
     * @dev Overrides ERC20 and ERC20Votes _mint
     * @param account The address receiving tokens
     * @param amount The amount of tokens being minted
     * 
     * Success: Tokens are minted and voting power is updated
     */
    function _mint(address account, uint256 amount)
        internal
        override(ERC20Upgradeable, ERC20VotesUpgradeable)
    {
        super._mint(account, amount);
    }

    /**
     * @notice Internal function to handle burning with voting power updates
     * @dev Overrides ERC20 and ERC20Votes _burn
     * @param account The address from which tokens are being burned
     * @param amount The amount of tokens being burned
     * 
     * Success: Tokens are burned and voting power is updated
     */
    function _burn(address account, uint256 amount)
        internal
        override(ERC20Upgradeable, ERC20VotesUpgradeable)
    {
        super._burn(account, amount);
    }

    /**
     * @notice Returns the current nonce for a given owner for permit functionality
     * @dev Resolves conflict between ERC20Permit implementations
     * @param owner The address to get the nonce for
     * @return The current nonce value
     * 
     * Success: Always returns the current nonce
     * Revert: Never reverts
     */
    function nonces(address owner)
        public
        view
        override(ERC20PermitUpgradeable)
        returns (uint256)
    {
        return super.nonces(owner);
    }
}
