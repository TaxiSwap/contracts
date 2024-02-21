// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/ITokenMessenger.sol";
import "./interfaces/IWhiteBridgeMessenger.sol";

/// @title A bridge messenger contract for transferring tokens with a tip mechanism
/// @dev This contract allows tokens to be sent across domains with an additional tip fee deducted from the transfer amount.
/// @notice This contract should be used with a corresponding CCTP token messenger and USDC token
contract WhiteBridgeMessenger is Ownable, IWhiteBridgeMessenger {
    IERC20 public token;
    ITokenMessenger public tokenMessenger;
    mapping(uint32 => uint256) private tipAmountsByDomain;
    uint256 public defaultTipAmount = 10_000; // Default tip amount

    /// @dev Sets up the WhiteBridgeMessenger with necessary addresses and defaults
    /// @param _token The address of the USDC token contract to be used for transfers and tips
    /// @param _tokenMessenger The address of the CCTP contract that handles the cross-domain token transfer
    constructor(address _token, address _tokenMessenger) Ownable(msg.sender) {
        token = IERC20(_token);
        tokenMessenger = ITokenMessenger(_tokenMessenger);
    }

    /// @notice Sets the default tip amount required for processing the token transfer
    /// @dev This function can only be called by the owner of the contract.
    /// @param _defaultTipAmount The new tip amount in tokens
    function setDefaultTipAmount(uint256 _defaultTipAmount) external onlyOwner {
        defaultTipAmount = _defaultTipAmount;
    }

    /// @notice Sets the tip amount required for processing the token transfer for a specific domain
    /// @dev This function can only be called by the owner of the contract.
    /// @param _domain The domain for which the tip amount is being set
    /// @param _tipAmount The new tip amount in tokens for the specified domain
    function setTipAmountForDomain(uint32 _domain, uint256 _tipAmount) external onlyOwner {
        tipAmountsByDomain[_domain] = _tipAmount;
    }

    function getTipAmount(uint32 _destinationDomain) external view returns (uint256) {
        return tipAmountsByDomain[_destinationDomain] > 0 ? tipAmountsByDomain[_destinationDomain] : defaultTipAmount;
    }

    /// @notice Processes a token transfer across domains with a tip deducted
    /// @dev Transfers the tip amount to the contract treasury and the remaining amount to the tokenMessenger for further processing.
    /// @param _amount The total amount of tokens to be transferred, including the tip
    /// @param _destinationDomain The domain where the tokens will be minted
    /// @param _mintRecipient The address on the destination domain to receive the minted tokens
    /// @param _burnToken The address of the token to burn on the source domain
    function processToken(uint256 _amount, uint32 _destinationDomain, bytes32 _mintRecipient, address _burnToken)
        external
    {
        uint256 tipAmount =
            tipAmountsByDomain[_destinationDomain] > 0 ? tipAmountsByDomain[_destinationDomain] : defaultTipAmount;

        require(_amount > tipAmount, "Amount must be greater than the tip amount");

        // Transfer the tip amount to this contract's treasury
        require(token.transferFrom(msg.sender, address(this), tipAmount), "Tip transfer failed");

        // Calculate the remaining amount after deducting the tip
        uint256 remainingAmount = _amount - tipAmount;

        // Ensure the contract has enough allowance to transfer the remaining amount
        require(token.transferFrom(msg.sender, address(this), remainingAmount), "Transfer to contract failed");

        // Approve the tokenMessenger to spend the token on behalf of this contract
        token.approve(address(tokenMessenger), remainingAmount);

        // Call the predefined contract's depositForBurn method with the remaining amount
        uint64 nonce = tokenMessenger.depositForBurn(remainingAmount, _destinationDomain, _mintRecipient, _burnToken);

        // Emit the event after successful depositForBurn call
        emit DepositForBurnCalled(nonce, remainingAmount, _destinationDomain, _mintRecipient, _burnToken);
    }

    /// @notice Allows the owner to withdraw accumulated tip amounts
    /// @dev Withdraws all the tokens held by the contract to the owner's address.
    function withdrawTips() external onlyOwner {
        uint256 balance = token.balanceOf(address(this));
        require(token.transfer(owner(), balance), "Withdrawal failed");
    }
}
