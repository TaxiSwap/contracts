// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/ITokenMessenger.sol";
import "./interfaces/IWhiteBridgeMessenger.sol";

contract WhiteBridgeMessenger is Ownable, IWhiteBridgeMessenger {
    IERC20 public token;
    ITokenMessenger public tokenMessenger;
    uint256 public tipAmount = 10_000; // Tip amount of 0.01 for a token with 6 decimals

    constructor(address _token, address _tokenMessenger) Ownable(msg.sender) {
        token = IERC20(_token);
        tokenMessenger = ITokenMessenger(_tokenMessenger);
    }

    function setTipAmount(uint256 _tipAmount) external onlyOwner {
        tipAmount = _tipAmount;
    }

    function processToken(uint256 _amount, uint32 _destinationDomain, bytes32 _mintRecipient, address _burnToken)
        external
    {
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

    function withdrawTips() external onlyOwner {
        uint256 balance = token.balanceOf(address(this));
        require(token.transfer(owner(), balance), "Withdrawal failed");
    }
}
