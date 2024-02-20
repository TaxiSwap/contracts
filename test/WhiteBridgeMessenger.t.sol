// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/WhiteBridgeMessenger.sol";
import "../src/interfaces/IWhiteBridgeMessenger.sol";
import "../src/interfaces/ITokenMessenger.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract WhiteBridgeMessengerTest is Test {
    WhiteBridgeMessenger public whiteBridgeMessenger;
    IERC20 public token;
    address public whaleTokenHolder;
    address public tokenMessenger;
    uint256 public initialBalance = 100000e6; // 1000 USDC with 6  decimals

    // Event declaration
    event DepositForBurnCalled(
        uint64 indexed nonce,
        uint256 amount,
        uint32 indexed destinationDomain,
        bytes32 indexed mintRecipient,
        address burnToken
    );

    function setUp() public {
        // Read environment variables
        // Ensure the test account has enough tokens for testing
        token = IERC20(address(bytes20(vm.envBytes("TOKEN_ADDRESS"))));
        tokenMessenger = address(bytes20(vm.envBytes("TOKEN_MESSENGER_ADDRESS")));
        whaleTokenHolder = vm.envAddress("WHALE_TOKEN_HOLDER");

        whiteBridgeMessenger = new WhiteBridgeMessenger(address(token), tokenMessenger);

        vm.prank(whaleTokenHolder);
        token.approve(address(whiteBridgeMessenger), initialBalance);
    }

    function testProcessToken() public {
        uint256 amount = 1000e6; // 6 decimals
        uint32 destinationDomain = 1;
        bytes32 mintRecipient = bytes32(uint256(uint160(whaleTokenHolder)));
        address burnToken = address(token);

        uint256 initialWhaleBalance = token.balanceOf(whaleTokenHolder);
        uint256 initialContractBalance = token.balanceOf(address(whiteBridgeMessenger));

        uint256 actualRecievedAmount = amount - whiteBridgeMessenger.tipAmount();

        // Expected parameters for the DepositForBurn event
        bytes32 destinationTokenMessenger = 0x0; // Dummy placeholder as it will be unckecked
        bytes32 destinationCaller = 0x0; // Dummy placeholder as it will be unckecked
        uint64 expectedNonce = 1; // Dummy placeholder as it will be unckecked

        vm.expectEmit(false, true, true, false, address(tokenMessenger)); // do not check data
        emit DepositForBurn(
            expectedNonce,
            burnToken,
            actualRecievedAmount,
            address(whiteBridgeMessenger),
            mintRecipient,
            destinationDomain,
            destinationTokenMessenger,
            destinationCaller
        );

        vm.expectEmit(false, true, true, true, address(whiteBridgeMessenger));
        emit DepositForBurnCalled(expectedNonce, actualRecievedAmount, destinationDomain, mintRecipient, burnToken);

        vm.prank(whaleTokenHolder);
        whiteBridgeMessenger.processToken(amount, destinationDomain, mintRecipient, burnToken);

        uint256 finalWhaleBalance = token.balanceOf(whaleTokenHolder);
        uint256 finalContractBalance = token.balanceOf(address(whiteBridgeMessenger));

        // Balance checks
        assertEq(initialWhaleBalance - finalWhaleBalance, amount, "Incorrect whale balance after transfers");
        assertEq(
            finalContractBalance - initialContractBalance,
            whiteBridgeMessenger.tipAmount(),
            "Incorrect contract balance after transfers"
        );
    }

    function testChangeTipAmount() public {
        uint256 newTipAmount = 20000; // Example new tip amount
        whiteBridgeMessenger.setTipAmount(newTipAmount);
        assertEq(whiteBridgeMessenger.tipAmount(), newTipAmount, "Tip amount did not update correctly");
    }

    function testChangeOwner() public {
        address newOwner = address(0x01);
        whiteBridgeMessenger.transferOwnership(newOwner);
        assertEq(whiteBridgeMessenger.owner(), newOwner, "Ownership did not transfer correctly");
    }
}
