// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title RivexDEXAggregator - Multi-DEX Aggregator for Optimal Swaps
 * @notice Aggregates liquidity from multiple DEXs to find best swap routes and execute trades
 * @dev Upgradeable contract with multicall functionality and multi-swap order execution using Transparent Proxy
 */
contract RivexDEXAggregator is 
    Initializable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable
{
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    struct SwapOrder {
        address target;          // DEX contract address
        bytes callData;         // Encoded function call data
        uint256 value;          // ETH value to send
    }

    struct MultiSwapParams {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 minAmountOut;
        SwapOrder[] orders;
        uint256 deadline;
    }

    struct Call {
        address target;
        bytes callData;
        uint256 value;
    }

    mapping(address => bool) public authorizedDEXs;
    mapping(address => bool) public authorizedTokens;
    
    uint256 public feeRate; // Fee in basis points (100 = 1%)
    address public feeRecipient;
    
    event SwapExecuted(
        address indexed user,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut
    );
    
    event MultiSwapExecuted(
        address indexed user,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 totalAmountIn,
        uint256 totalAmountOut,
        uint256 ordersCount
    );
    
    event MulticallExecuted(
        address indexed user,
        uint256 callsCount,
        bool[] results
    );
    
    event DEXAuthorized(address indexed dex, bool authorized);
    event TokenAuthorized(address indexed token, bool authorized);
    event FeeUpdated(uint256 newFeeRate, address newFeeRecipient);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the DEX Aggregator contract
     * @dev Sets up roles, fee parameters, and initial authorized contracts
     * @param initialOwner Address that will receive admin roles
     * @param _feeRate Initial fee rate in basis points
     * @param _feeRecipient Address to receive collected fees
     * 
     * Success: Contract is initialized with proper roles and parameters
     * Revert: If called more than once or with invalid parameters
     */
    function initialize(
        address initialOwner,
        uint256 _feeRate,
        address _feeRecipient
    ) public initializer {
        __AccessControl_init();
        __ReentrancyGuard_init();
        __Pausable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, initialOwner);
        _grantRole(ADMIN_ROLE, initialOwner);
        _grantRole(OPERATOR_ROLE, initialOwner);
        
        feeRate = _feeRate;
        feeRecipient = _feeRecipient;
    }

    /**
     * @notice Executes a single swap order on specified DEX
     * @dev Performs token swap through external DEX contract with fee collection
     * @param tokenIn Address of input token
     * @param tokenOut Address of output token
     * @param amountIn Amount of input tokens
     * @param minAmountOut Minimum acceptable output amount
     * @param target DEX contract address
     * @param callData Encoded swap function call
     * @param deadline Transaction deadline timestamp
     * 
     * Success: Swap is executed and tokens are transferred to user minus fees
     * Revert: If DEX not authorized, insufficient balance, slippage exceeded, or deadline passed
     */
    function singleSwap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address target,
        bytes calldata callData,
        uint256 deadline
    ) external payable nonReentrant whenNotPaused {
        require(block.timestamp <= deadline, "RivexDEX: Deadline exceeded");
        require(authorizedDEXs[target], "RivexDEX: DEX not authorized");
        require(amountIn > 0, "RivexDEX: Invalid amount");

        uint256 balanceBefore;
        
        // Handle ETH or ERC20 input
        if (tokenIn == address(0)) {
            require(msg.value >= amountIn, "RivexDEX: Insufficient ETH");
        } else {
            require(IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn), "RivexDEX: Transfer failed");
            require(IERC20(tokenIn).approve(target, amountIn), "RivexDEX: Approval failed");
        }

        // Get balance before swap
        if (tokenOut == address(0)) {
            balanceBefore = address(this).balance;
        } else {
            balanceBefore = IERC20(tokenOut).balanceOf(address(this));
        }

        // Execute swap
        (bool success, ) = target.call{value: tokenIn == address(0) ? amountIn : 0}(callData);
        require(success, "RivexDEX: Swap failed");

        // Calculate output amount
        uint256 amountOut;
        if (tokenOut == address(0)) {
            amountOut = address(this).balance - balanceBefore;
        } else {
            amountOut = IERC20(tokenOut).balanceOf(address(this)) - balanceBefore;
        }

        require(amountOut >= minAmountOut, "RivexDEX: Insufficient output");

        // Collect fee and transfer to user
        uint256 fee = (amountOut * feeRate) / 10000;
        uint256 userAmount = amountOut - fee;

        if (tokenOut == address(0)) {
            if (fee > 0) {
                (bool feeSuccess, ) = payable(feeRecipient).call{value: fee}("");
                require(feeSuccess, "RivexDEX: Fee transfer failed");
            }
            (bool userSuccess, ) = payable(msg.sender).call{value: userAmount}("");
            require(userSuccess, "RivexDEX: User transfer failed");
        } else {
            if (fee > 0) {
                require(IERC20(tokenOut).transfer(feeRecipient, fee), "RivexDEX: Fee transfer failed");
            }
            require(IERC20(tokenOut).transfer(msg.sender, userAmount), "RivexDEX: User transfer failed");
        }

        emit SwapExecuted(msg.sender, tokenIn, tokenOut, amountIn, userAmount);
    }

    /**
     * @notice Executes multiple swap orders for optimal routing
     * @dev Splits trade across multiple DEXs to minimize slippage and maximize output
     * @param params MultiSwapParams struct containing all swap parameters
     * 
     * Success: All swaps are executed and total output meets minimum requirement
     * Revert: If any swap fails, total output insufficient, or deadline passed
     */
    function multiSwapOrder(MultiSwapParams calldata params) external payable nonReentrant whenNotPaused {
        require(block.timestamp <= params.deadline, "RivexDEX: Deadline exceeded");
        require(params.orders.length > 0, "RivexDEX: No orders provided");
        require(params.amountIn > 0, "RivexDEX: Invalid amount");

        uint256 totalAmountOut = 0;
        uint256 balanceBefore;

        // Handle input token transfer
        if (params.tokenIn == address(0)) {
            require(msg.value >= params.amountIn, "RivexDEX: Insufficient ETH");
        } else {
            require(IERC20(params.tokenIn).transferFrom(msg.sender, address(this), params.amountIn), "RivexDEX: Transfer failed");
        }

        // Get initial balance
        if (params.tokenOut == address(0)) {
            balanceBefore = address(this).balance;
        } else {
            balanceBefore = IERC20(params.tokenOut).balanceOf(address(this));
        }

        // Execute all swap orders
        for (uint256 i = 0; i < params.orders.length; i++) {
            SwapOrder memory order = params.orders[i];
            require(authorizedDEXs[order.target], "RivexDEX: DEX not authorized");

            // Approve tokens if needed
            if (params.tokenIn != address(0)) {
                require(IERC20(params.tokenIn).approve(order.target, order.value), "RivexDEX: Approval failed");
            }

            (bool success, ) = order.target.call{value: order.value}(order.callData);
            require(success, "RivexDEX: Order execution failed");
        }

        // Calculate total output
        if (params.tokenOut == address(0)) {
            totalAmountOut = address(this).balance - balanceBefore;
        } else {
            totalAmountOut = IERC20(params.tokenOut).balanceOf(address(this)) - balanceBefore;
        }

        require(totalAmountOut >= params.minAmountOut, "RivexDEX: Insufficient total output");

        // Collect fee and transfer to user
        uint256 fee = (totalAmountOut * feeRate) / 10000;
        uint256 userAmount = totalAmountOut - fee;

        if (params.tokenOut == address(0)) {
            if (fee > 0) {
                (bool feeSuccess, ) = payable(feeRecipient).call{value: fee}("");
                require(feeSuccess, "RivexDEX: Fee transfer failed");
            }
            (bool userSuccess, ) = payable(msg.sender).call{value: userAmount}("");
            require(userSuccess, "RivexDEX: User transfer failed");
        } else {
            if (fee > 0) {
                require(IERC20(params.tokenOut).transfer(feeRecipient, fee), "RivexDEX: Fee transfer failed");
            }
            require(IERC20(params.tokenOut).transfer(msg.sender, userAmount), "RivexDEX: User transfer failed");
        }

        emit MultiSwapExecuted(msg.sender, params.tokenIn, params.tokenOut, params.amountIn, userAmount, params.orders.length);
    }

    /**
     * @notice Executes multiple arbitrary calls in a single transaction
     * @dev Allows batching multiple operations with different targets and call data
     * @param calls Array of Call structs containing target addresses and call data
     * @return results Array of success/failure results for each call
     * 
     * Success: All calls are attempted and results are returned
     * Revert: If contract is paused or caller lacks OPERATOR_ROLE
     */
    function multicall(Call[] calldata calls) external payable nonReentrant whenNotPaused onlyRole(OPERATOR_ROLE) returns (bool[] memory results) {
        results = new bool[](calls.length);
        
        for (uint256 i = 0; i < calls.length; i++) {
            Call memory call = calls[i];
            (bool success, ) = call.target.call{value: call.value}(call.callData);
            results[i] = success;
        }

        emit MulticallExecuted(msg.sender, calls.length, results);
        return results;
    }

    /**
     * @notice Executes multiple calls and requires all to succeed
     * @dev Similar to multicall but reverts if any call fails
     * @param calls Array of Call structs containing target addresses and call data
     * @return returnData Array of return data from each successful call
     * 
     * Success: All calls succeed and return data is collected
     * Revert: If any call fails, contract is paused, or caller lacks OPERATOR_ROLE
     */
    function multicallStrict(Call[] calldata calls) external payable nonReentrant whenNotPaused onlyRole(OPERATOR_ROLE) returns (bytes[] memory returnData) {
        returnData = new bytes[](calls.length);
        
        for (uint256 i = 0; i < calls.length; i++) {
            Call memory call = calls[i];
            (bool success, bytes memory data) = call.target.call{value: call.value}(call.callData);
            require(success, "RivexDEX: Multicall failed");
            returnData[i] = data;
        }

        bool[] memory results = new bool[](calls.length);
        for (uint256 i = 0; i < calls.length; i++) {
            results[i] = true;
        }

        emit MulticallExecuted(msg.sender, calls.length, results);
        return returnData;
    }

    /**
     * @notice Authorizes or deauthorizes a DEX contract
     * @dev Only admin can manage authorized DEX list
     * @param dex Address of the DEX contract
     * @param authorized Whether the DEX should be authorized
     * 
     * Success: DEX authorization status is updated
     * Revert: If caller is not admin
     */
    function setDEXAuthorization(address dex, bool authorized) external onlyRole(ADMIN_ROLE) {
        authorizedDEXs[dex] = authorized;
        emit DEXAuthorized(dex, authorized);
    }

    /**
     * @notice Authorizes or deauthorizes a token for trading
     * @dev Only admin can manage authorized token list
     * @param token Address of the token contract
     * @param authorized Whether the token should be authorized
     * 
     * Success: Token authorization status is updated
     * Revert: If caller is not admin
     */
    function setTokenAuthorization(address token, bool authorized) external onlyRole(ADMIN_ROLE) {
        authorizedTokens[token] = authorized;
        emit TokenAuthorized(token, authorized);
    }

    /**
     * @notice Updates fee rate and recipient
     * @dev Only admin can modify fee parameters
     * @param _feeRate New fee rate in basis points (max 1000 = 10%)
     * @param _feeRecipient New fee recipient address
     * 
     * Success: Fee parameters are updated
     * Revert: If caller is not admin or fee rate exceeds maximum
     */
    function setFeeParams(uint256 _feeRate, address _feeRecipient) external onlyRole(ADMIN_ROLE) {
        require(_feeRate <= 1000, "RivexDEX: Fee rate too high"); // Max 10%
        require(_feeRecipient != address(0), "RivexDEX: Invalid fee recipient");
        
        feeRate = _feeRate;
        feeRecipient = _feeRecipient;
        
        emit FeeUpdated(_feeRate, _feeRecipient);
    }

    /**
     * @notice Emergency function to recover stuck tokens
     * @dev Only admin can recover tokens in emergency situations
     * @param token Address of token to recover (address(0) for ETH)
     * @param amount Amount to recover
     * 
     * Success: Tokens are transferred to admin
     * Revert: If caller is not admin, insufficient balance, or transfer fails
     */
    function emergencyRecover(address token, uint256 amount) external onlyRole(ADMIN_ROLE) {
        if (token == address(0)) {
            require(amount <= address(this).balance, "RivexDEX: Insufficient ETH balance");
            (bool success, ) = payable(msg.sender).call{value: amount}("");
            require(success, "RivexDEX: ETH transfer failed");
        } else {
            require(amount <= IERC20(token).balanceOf(address(this)), "RivexDEX: Insufficient token balance");
            require(IERC20(token).transfer(msg.sender, amount), "RivexDEX: Token transfer failed");
        }
    }

    /**
     * @notice Pauses the contract, stopping all operations
     * @dev Only admin can pause the contract
     * 
     * Success: Contract is paused
     * Revert: If caller is not admin or contract is already paused
     */
    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    /**
     * @notice Unpauses the contract, resuming all operations
     * @dev Only admin can unpause the contract
     * 
     * Success: Contract is unpaused
     * Revert: If caller is not admin or contract is not paused
     */
    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    /**
     * @notice Gets the contract's balance for a specific token
     * @param token Token address (address(0) for ETH)
     * @return Token balance held by the contract
     * 
     * Success: Always returns current balance
     * Revert: Never reverts
     */
    function getBalance(address token) external view returns (uint256) {
        if (token == address(0)) {
            return address(this).balance;
        } else {
            return IERC20(token).balanceOf(address(this));
        }
    }

    /**
     * @notice Checks if a DEX is authorized
     * @param dex DEX contract address
     * @return Whether the DEX is authorized
     * 
     * Success: Always returns authorization status
     * Revert: Never reverts
     */
    function isDEXAuthorized(address dex) external view returns (bool) {
        return authorizedDEXs[dex];
    }

    /**
     * @notice Checks if a token is authorized
     * @param token Token contract address
     * @return Whether the token is authorized
     * 
     * Success: Always returns authorization status
     * Revert: Never reverts
     */
    function isTokenAuthorized(address token) external view returns (bool) {
        return authorizedTokens[token];
    }

    /**
     * @notice Fallback function to receive ETH
     * @dev Allows contract to receive ETH for swaps and operations
     * 
     * Success: ETH is received by the contract
     * Revert: Never reverts
     */
    receive() external payable {}
}
