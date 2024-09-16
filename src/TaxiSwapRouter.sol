// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {CurrencySettler} from "@uniswap/v4-core/test/utils/CurrencySettler.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {BalanceDeltaLibrary, BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {IERC20Minimal} from "v4-core/interfaces/external/IERC20Minimal.sol";
import {TransientStateLibrary} from "v4-core/libraries/TransientStateLibrary.sol";

import {IAxelarGateway} from "@axelar-network/axelar-cgp-solidity/contracts/interfaces/IAxelarGateway.sol";
import {AxelarExecutable} from "@axelar-network/axelar-gmp-sdk-solidity/contracts/executable/AxelarExecutable.sol";
import {IAxelarGasService} from "@axelar-network/axelar-cgp-solidity/contracts/interfaces/IAxelarGasService.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ITokenMessenger} from "./interfaces/ITokenMessenger.sol";
import {
    StringToAddress, AddressToString
} from "@axelar-network/axelar-gmp-sdk-solidity/contracts/libs/AddressString.sol";

/// @title TaxiSwapRouter
/// @notice A contract for cross-chain token swaps using Uniswap V4, Axelar, and Circle's CCTP
/// @dev This contract facilitates swaps between chains, handling the complexities of cross-chain messaging and token transfers
contract TaxiSwapRouter is AxelarExecutable, Ownable {
    using CurrencyLibrary for Currency;
    using CurrencySettler for Currency;
    using TransientStateLibrary for IPoolManager;
    using BalanceDeltaLibrary for BalanceDelta;

    /// @notice The Uniswap V4 pool manager
    IPoolManager public immutable manager;

    /// @notice The USDC token contract
    IERC20 public usdc;
    /// @notice The Circle Token Messenger contract for CCTP
    ITokenMessenger public tokenMessenger;
    /// @notice The Axelar Gas Service contract
    IAxelarGasService immutable gasReceiver;

    /// @notice A nonce used to generate unique trace IDs for cross-chain transactions
    uint256 public nonce;

    /// @notice Mapping of chain names to Circle destination domain numbers
    mapping(string => uint32) public circleDestinationDomains;
    /// @notice Mapping of Circle domain numbers to Axelar chain names
    mapping(uint32 => string) public axelarDestinationChain;
    /// @notice Mapping of destination chain numbers to sibling contract addresses
    mapping(uint32 => address) public siblings;

    /// @notice Mapping of source token addresses to destination token addresses for each chain
    mapping(address => mapping(uint32 => address)) tokenAddressToDestinationTokenAddress;

    /// @notice Struct to hold callback data for the unlock function
    struct CallbackData {
        address sender;
        SwapAndBridgeSettings settings;
        PoolKey key;
        IPoolManager.SwapParams params;
        bytes hookData;
    }

    /// @notice Settings for swap and bridge operations
    struct SwapAndBridgeSettings {
        address recipientAddress;
        address destinationToken;
        uint32 destinationChain;
    }

    error InvalidTrade();
    error InsufficientInput();
    error TradeFailed();
    error CallerNotManager();
    error TokenCannotBeBridged();
    error SwapNotToUSDC();

    /// @notice Emitted when a swap is successful
    /// @param traceId The unique identifier for the swap
    /// @param amount The amount of tokens swapped
    /// @param recipient The address receiving the swapped tokens
    event SwapSuccess(uint256 indexed traceId, uint256 amount, address recipient);

    /// @notice Emitted when a swap fails
    /// @param traceId The unique identifier for the failed swap
    /// @param amount The amount of tokens to be refunded
    /// @param refundAddress The address to receive the refund
    event SwapFailed(bytes32 indexed traceId, uint256 amount, address refundAddress);

    /// @notice Emitted when a swap is pending cross-chain execution
    /// @param nonce The unique nonce for the swap
    /// @param payloadHash The hash of the cross-chain payload
    /// @param amount The amount of tokens being swapped
    /// @param destinationChain The destination chain ID
    /// @param recipient The address to receive the swapped tokens on the destination chain
    event SwapPending(
        uint256 indexed nonce, bytes32 indexed payloadHash, uint256 amount, uint32 destinationChain, address recipient
    );

    /// @notice Constructor for the TaxiSwapRouter contract
    /// @param manager_ The address of the Uniswap V4 pool manager
    /// @param usdc_ The address of the USDC token contract
    /// @param gasReceiver_ The address of the Axelar Gas Service contract
    /// @param gateway_ The address of the Axelar Gateway contract
    /// @param tokenMessenger_ The address of the Circle Token Messenger contract
    constructor(IPoolManager manager_, address usdc_, address gasReceiver_, address gateway_, address tokenMessenger_)
        Ownable(msg.sender)
        AxelarExecutable(gateway_)
    {
        manager = manager_;
        usdc = IERC20(usdc_);
        tokenMessenger = ITokenMessenger(tokenMessenger_);
        gasReceiver = IAxelarGasService(gasReceiver_);

        circleDestinationDomains["ethereum"] = 0;
        axelarDestinationChain[0] = "ethereum";
        circleDestinationDomains["avalanche"] = 1;
        axelarDestinationChain[1] = "avalanche";
        circleDestinationDomains["optimism"] = 2;
        axelarDestinationChain[2] = "optimism";
        circleDestinationDomains["arbitrum"] = 3;
        axelarDestinationChain[3] = "arbitrum";
        circleDestinationDomains["base"] = 6;
        axelarDestinationChain[6] = "base";
        circleDestinationDomains["polygon"] = 7;
        axelarDestinationChain[7] = "polygon";
    }

    /// @notice Modifier to check if the destination chain is valid
    /// @param destinationChain The ID of the destination chain
    modifier isValidChain(uint32 destinationChain) {
        require(siblings[destinationChain] != address(0), "Invalid chain");
        _;
    }

    /// @notice Swaps tokens to USDC and sends them via CCTP to another chain
    /// @param key The Uniswap V4 pool key for the swap
    /// @param params The swap parameters
    /// @param settings The settings for the swap and bridge operation
    /// @param destinationSettings The settings for the destination chain swap
    /// @param destinationKey The pool key for the destination chain swap
    /// @param destinationParams The swap parameters for the destination chain
    /// @param hookData Additional data for the swap hook
    /// @param destinationHookData Additional data for the destination chain swap hook
    /// @return delta The balance delta resulting from the swap
    function swapToUSDCSendViaCCTP(
        PoolKey memory key,
        IPoolManager.SwapParams memory params,
        SwapAndBridgeSettings memory settings,
        SwapAndBridgeSettings memory destinationSettings,
        PoolKey memory destinationKey,
        IPoolManager.SwapParams memory destinationParams,
        bytes memory hookData,
        bytes memory destinationHookData
    ) external payable returns (BalanceDelta delta) {
        Currency l1TokenToBridge = params.zeroForOne ? key.currency1 : key.currency0;
        Currency l2TokenToBridge = params.zeroForOne ? key.currency0 : key.currency1;

        if (Currency.unwrap(l2TokenToBridge) != address(usdc)) revert SwapNotToUSDC();

        if (!l1TokenToBridge.isAddressZero()) {
            address destinationToken =
                tokenAddressToDestinationTokenAddress[Currency.unwrap(l1TokenToBridge)][settings.destinationChain];
            if (destinationToken == address(0)) revert TokenCannotBeBridged();
        }

        // Unlock the pool manager which will trigger a callback
        delta = abi.decode(
            manager.unlock(abi.encode(CallbackData(msg.sender, settings, key, params, hookData))), (BalanceDelta)
        );

        uint256 amount = uint256(int256(params.zeroForOne ? delta.amount0() : delta.amount1()));

        _sendViaCCTP(amount, settings.destinationChain);

        // increment the nonce to use it as a trace ID
        ++nonce;

        // encode the payload to send to the sibling contract
        bytes memory payload =
            abi.encode(amount, nonce, destinationKey, destinationParams, destinationHookData, destinationSettings);

        // Pay gas to AxelarGasReceiver contract with native token to execute the sibling contract at the destination chain
        _payGasAndCallContract(settings.destinationChain, payload, msg.value);

        emit SwapPending(nonce, keccak256(payload), amount, settings.destinationChain, settings.recipientAddress);
    }

    /// @notice Callback function for the Uniswap V4 pool manager unlock
    /// @param rawData The encoded callback data
    /// @return The encoded balance delta
    function unlockCallback(bytes calldata rawData) external returns (bytes memory) {
        if (msg.sender != address(manager)) revert CallerNotManager();
        CallbackData memory data = abi.decode(rawData, (CallbackData));

        // Call swap on the PM
        BalanceDelta delta = manager.swap(data.key, data.params, data.hookData);

        int256 deltaAfter0 = manager.currencyDelta(address(this), data.key.currency0);
        int256 deltaAfter1 = manager.currencyDelta(address(this), data.key.currency1);

        if (deltaAfter0 < 0) {
            data.key.currency0.settle(manager, data.sender, uint256(-deltaAfter0), false);
        }

        if (deltaAfter1 < 0) {
            data.key.currency1.settle(manager, data.sender, uint256(-deltaAfter1), false);
        }

        if (deltaAfter0 > 0) {
            _take(data.key.currency0, uint256(deltaAfter0));
        }

        if (deltaAfter1 > 0) {
            _take(data.key.currency1, uint256(deltaAfter1));
        }

        return abi.encode(delta);
    }

    /// @notice Internal function to take tokens from the pool manager
    /// @param currency The currency to take
    /// @param amount The amount to take
    function _take(Currency currency, uint256 amount) internal {
        currency.take(manager, address(this), amount, false);
    }

    /// @notice Internal function to send USDC via CCTP
    /// @param amount The amount of USDC to send
    /// @param destinationChain The destination chain ID
    function _sendViaCCTP(uint256 amount, uint32 destinationChain) private isValidChain(destinationChain) {
        IERC20(address(usdc)).approve(address(tokenMessenger), amount);

        // deposit to burn usdc and to receive it on our sibling on the other side
        tokenMessenger.depositForBurn(
            amount, destinationChain, bytes32(uint256(uint160(siblings[destinationChain]))), address(usdc)
        );
    }

    /// @notice Internal function to pay gas and call the contract on the destination chain
    /// @param destinationChain The destination chain ID
    /// @param payload The payload to send
    /// @param fee The gas fee to pay
    function _payGasAndCallContract(uint32 destinationChain, bytes memory payload, uint256 fee) private {
        gasReceiver.payNativeGasForContractCall{value: fee}(
            address(this),
            axelarDestinationChain[destinationChain],
            AddressToString.toString(this.siblings(destinationChain)),
            payload,
            msg.sender
        );
        // Send all information to AxelarGateway contract.
        gateway.callContract(
            axelarDestinationChain[destinationChain], AddressToString.toString(this.siblings(destinationChain)), payload
        );
    }

    /// @notice Internal function to refund tokens in case of a failed swap
    /// @param traceId The unique identifier for the failed swap
    /// @param amount The amount to refund
    /// @param recipient The address to receive the refund
    function _refund(bytes32 traceId, uint256 amount, address recipient) internal {
        SafeERC20.safeTransfer(IERC20(address(usdc)), recipient, amount);
        emit SwapFailed(traceId, amount, recipient);
    }

    /// @notice Internal function called by Axelar Executor service to execute the cross-chain swap
    /// @param payload The payload containing swap details
    function _execute(string calldata, /*sourceChain*/ string calldata, /*sourceAddress*/ bytes calldata payload)
        internal
        override
    {
        // Decode payload
        (
            uint256 amount_,
            uint256 nonce_,
            PoolKey memory destinationKey,
            IPoolManager.SwapParams memory destinationParams,
            bytes memory destinationHookData,
            SwapAndBridgeSettings memory destinationSettings
        ) = abi.decode(payload, (uint256, uint256, PoolKey, IPoolManager.SwapParams, bytes, SwapAndBridgeSettings));

        _swapUSDCToToken(destinationKey, destinationParams, destinationSettings, destinationHookData);

        // Emit success event so that our application can be notified.
        emit SwapSuccess(nonce_, amount_, destinationSettings.recipientAddress);
    }

    /// @notice Internal function to swap USDC to the destination token
    /// @param key The Uniswap V4 pool key for the swap
    /// @param params The swap parameters
    /// @param settings The settings for the swap operation
    /// @param hookData Additional data for the swap hook
    /// @return delta The balance delta resulting from the swap
    function _swapUSDCToToken(
        PoolKey memory key,
        IPoolManager.SwapParams memory params,
        SwapAndBridgeSettings memory settings,
        bytes memory hookData
    ) internal returns (BalanceDelta delta) {
        Currency l1TokenToBridge = params.zeroForOne ? key.currency1 : key.currency0;

        if (!l1TokenToBridge.isAddressZero()) {
            address l2Token = settings.destinationToken;
            if (l2Token == address(0)) revert TokenCannotBeBridged();
        }

        // Unlock the pool manager which will trigger a callback
        delta = abi.decode(
            manager.unlock(abi.encode(CallbackData(msg.sender, settings, key, params, hookData))), (BalanceDelta)
        );
    }

    /// @notice Allows the contract to receive ETH
    receive() external payable {}

    // =============
    // == Helpers ==
    // =============

    /// @notice Adds a mapping for token addresses between chains
    /// @dev This function can only be called by the contract owner
    /// @param l1Token The address of the token on the source chain
    /// @param destinationChain The ID of the destination chain
    /// @param l2Token The address of the corresponding token on the destination chain
    function addTokenAddressToDestinationTokenAddress(address l1Token, uint32 destinationChain, address l2Token)
        external
        onlyOwner
    {
        tokenAddressToDestinationTokenAddress[l1Token][destinationChain] = l2Token;
    }

    /// @notice Sets the address of the sibling contract on another chain
    /// @dev This function can only be called by the contract owner
    /// @param chain_ The ID of the chain where the sibling contract is deployed
    /// @param address_ The address of the sibling contract on the specified chain
    function addSibling(uint32 chain_, address address_) external onlyOwner {
        siblings[chain_] = address_;
    }
}
