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
    function setTipAmount(uint256 _tipAmount) external;

    function processToken(uint256 _amount, uint32 _destinationDomain, bytes32 _mintRecipient, address _burnToken)
        external;

    function withdrawTips() external;

    // Getters
    function token() external view returns (IERC20);

    function tokenMessenger() external view returns (ITokenMessenger);

    function tipAmount() external view returns (uint256);
}
