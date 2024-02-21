// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./ITokenMessenger.sol";

interface IWhiteBridgeMessenger {
    // Event declaration
    event DepositForBurnCalled(
        uint64 indexed nonce,
        uint256 amount,
        uint32 indexed destinationDomain,
        bytes32 indexed mintRecipient,
        address burnToken
    );

    // Functions

    /// @notice Sets the default tip amount required for processing the token transfer
    /// @param _defaultTipAmount The new default tip amount in tokens
    function setDefaultTipAmount(uint256 _defaultTipAmount) external;

    /// @notice Sets the tip amount for a specific domain
    /// @param _domain The domain for which the tip amount is being set
    /// @param _tipAmount The tip amount in tokens for the specified domain
    function setTipAmountForDomain(uint32 _domain, uint256 _tipAmount) external;

    /// @notice Retrieves the tip amount for a specified domain, defaulting if not set
    /// @param _destinationDomain The domain to retrieve the tip amount for
    /// @return The tip amount for the domain
    function getTipAmount(uint32 _destinationDomain) external view returns (uint256);

    /// @notice Processes a token transfer across domains with a tip deducted
    /// @param _amount The total amount of tokens to be transferred, including the tip
    /// @param _destinationDomain The domain where the tokens will be minted
    /// @param _mintRecipient The address on the destination domain to receive the minted tokens
    /// @param _burnToken The address of the token to burn on the source domain
    function sendMessage(uint256 _amount, uint32 _destinationDomain, bytes32 _mintRecipient, address _burnToken)
        external;

    function withdrawTips() external;

    // Getters
    function token() external view returns (IERC20);

    function tokenMessenger() external view returns (ITokenMessenger);
}
