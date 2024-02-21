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
    address public owner = address(0xCAFEBABE);

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

        whiteBridgeMessenger = new WhiteBridgeMessenger(address(token), tokenMessenger, owner);

        vm.prank(whaleTokenHolder);
        token.approve(address(whiteBridgeMessenger), initialBalance);
    }

    function testSendMessage() public {
        uint256 amount = 1000e6; // 6 decimals
        uint32 destinationDomain = 1;
        bytes32 mintRecipient = bytes32(uint256(uint160(whaleTokenHolder)));
        address burnToken = address(token);

        uint256 initialWhaleBalance = token.balanceOf(whaleTokenHolder);
        uint256 initialContractBalance = token.balanceOf(address(whiteBridgeMessenger));

        uint256 actualRecievedAmount = amount - whiteBridgeMessenger.getTipAmount(destinationDomain);

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
        whiteBridgeMessenger.sendMessage(amount, destinationDomain, mintRecipient, burnToken);

        uint256 finalWhaleBalance = token.balanceOf(whaleTokenHolder);
        uint256 finalContractBalance = token.balanceOf(address(whiteBridgeMessenger));

        // Balance checks
        assertEq(initialWhaleBalance - finalWhaleBalance, amount, "Incorrect whale balance after transfers");
        assertEq(
            finalContractBalance - initialContractBalance,
            whiteBridgeMessenger.getTipAmount(destinationDomain),
            "Incorrect contract balance after transfers"
        );
    }

    function testSendMessageWithVariableTips() public {
        uint256 domain1TipAmount = 5000; // Tip amount for domain 1
        uint256 domain2TipAmount = 15000; // Tip amount for domain 2
        vm.startPrank(owner);
        whiteBridgeMessenger.setTipAmountForDomain(1, domain1TipAmount);
        whiteBridgeMessenger.setTipAmountForDomain(2, domain2TipAmount);
        vm.stopPrank();

        // Send a message for domain 1 and verify the tip amount is correctly used
        uint256 amountForDomain1 = 10000e6; // 10 USDC with 6 decimals, for example
        uint32 destinationDomain1 = 1;
        bytes32 mintRecipient1 = bytes32(uint256(uint160(whaleTokenHolder)));
        address burnToken1 = address(token);

        // Domain 1 tip
        vm.prank(whaleTokenHolder);
        whiteBridgeMessenger.sendMessage(amountForDomain1, destinationDomain1, mintRecipient1, burnToken1);

        uint256 whiteBridgeMessengerBalance1 = token.balanceOf(address(whiteBridgeMessenger));
        assertEq(whiteBridgeMessengerBalance1, domain1TipAmount, "Not correct tip amount 1 transfered");

        // Send a message for domain 2 and verify the tip amount is correctly used
        uint256 amountForDomain2 = 1000e6; // 1 USDC with 6 decimals, for example
        uint32 destinationDomain2 = 2;
        bytes32 mintRecipient2 = bytes32(uint256(uint160(whaleTokenHolder)));
        address burnToken2 = address(token);

        // Domain 2 tip
        vm.prank(whaleTokenHolder);
        whiteBridgeMessenger.sendMessage(amountForDomain2, destinationDomain2, mintRecipient2, burnToken2);

        uint256 whiteBridgeMessengerBalance2 = token.balanceOf(address(whiteBridgeMessenger));
        assertEq(
            whiteBridgeMessengerBalance2,
            whiteBridgeMessengerBalance1 + domain2TipAmount,
            "Not correct tip amount 2 transfered"
        );
    }

    function testSendMessageWhenAmountLessThanOrEqualToTipForDomainShouldFail() public {
        uint32 testDomain = 1;
        uint256 testTipAmount = 5000;
        vm.prank(owner);
        whiteBridgeMessenger.setTipAmountForDomain(testDomain, testTipAmount);

        uint256 insufficientAmount = testTipAmount; // This should trigger failure
        bytes32 mintRecipient = bytes32(uint256(uint160(whaleTokenHolder)));
        address burnToken = address(token);

        vm.startPrank(whaleTokenHolder);
        token.approve(address(whiteBridgeMessenger), insufficientAmount);
        vm.expectRevert("Amount must be greater than the tip amount");
        whiteBridgeMessenger.sendMessage(insufficientAmount, testDomain, mintRecipient, burnToken);
        vm.stopPrank();
    }

    function testChangedDefaultTipAmount() public {
        uint256 newTipAmount = 20000; // Example new tip amount
        vm.prank(owner);
        whiteBridgeMessenger.setDefaultTipAmount(newTipAmount);
        assertEq(whiteBridgeMessenger.defaultTipAmount(), newTipAmount, "Tip amount did not update correctly");
    }

    function testChangeOwner() public {
        address newOwner = address(0x01);
        vm.prank(owner);
        whiteBridgeMessenger.transferOwnership(newOwner);
        assertEq(whiteBridgeMessenger.owner(), newOwner, "Ownership did not transfer correctly");
    }

    function testWithdrawTipsWithDeposits() public {
        // Assume initial setup has been done in setUp()

        // Simulate a couple of deposits to accumulate tips
        uint256 depositAmount1 = 1000e6; // First deposit amount with 6 decimals
        uint256 depositAmount2 = 2000e6; // Second deposit amount with 6 decimals
        uint32 destinationDomain = 1;
        bytes32 mintRecipient = bytes32(uint256(uint160(whaleTokenHolder)));
        address burnToken = address(token);

        // Make sure the whale token holder approves the contract to spend tokens
        vm.prank(whaleTokenHolder);
        token.approve(address(whiteBridgeMessenger), depositAmount1 + depositAmount2);

        // Send message for first deposit
        vm.prank(whaleTokenHolder);
        whiteBridgeMessenger.sendMessage(depositAmount1, destinationDomain, mintRecipient, burnToken);

        // Send message for deposit
        vm.prank(whaleTokenHolder);
        whiteBridgeMessenger.sendMessage(depositAmount2, destinationDomain, mintRecipient, burnToken);

        // Calculate expected tips accumulated
        uint256 expectedTips = whiteBridgeMessenger.defaultTipAmount() * 2; // Since two deposits were made

        // Check balances before withdrawal
        uint256 ownerBalanceBefore = token.balanceOf(owner);
        uint256 contractBalanceBefore = token.balanceOf(address(whiteBridgeMessenger));
        assertEq(contractBalanceBefore, expectedTips, "Contract should have exactly the accumulated tips");

        // Withdraw tips
        vm.prank(owner);
        whiteBridgeMessenger.withdrawTips();

        // Check balances after withdrawal
        uint256 ownerBalanceAfter = token.balanceOf(owner);
        uint256 contractBalanceAfter = token.balanceOf(address(whiteBridgeMessenger));

        // Assertions
        assertEq(contractBalanceAfter, 0, "Contract should have 0 balance after tips withdrawal");
        assertEq(
            ownerBalanceAfter - ownerBalanceBefore,
            expectedTips,
            "Owner should receive the exact amount of accumulated tips"
        );
    }

    function testFailChangeTipAmountNonOwner() public {
        vm.prank(address(0x2)); // An address that is not the owner
        whiteBridgeMessenger.setDefaultTipAmount(30000); // This should fail
    }

    function testFailChangeOwnerNonOwner() public {
        vm.prank(address(0x2)); // An address that is not the owner
        whiteBridgeMessenger.transferOwnership(address(0x3)); // This should fail
    }

    function testFailWithdrawTipsNonOwner() public {
        // Setup a new address that is not the owner
        address nonOwner = address(0xdead);

        // Attempt to withdraw tips as a non-owner
        vm.expectRevert("Ownable: caller is not the owner"); // Adjust the revert message based on your contract's implementation
        vm.prank(nonOwner); // Simulate the call coming from the non-owner address
        whiteBridgeMessenger.withdrawTips();
    }

    function testDepositAmountShouldBeLargerThanTip() public {
        // Test for amount exactly equal to tip amount
        uint256 equalTipAmount = whiteBridgeMessenger.defaultTipAmount();
        uint32 destinationDomain = 1;
        bytes32 mintRecipient = bytes32(uint256(uint160(whaleTokenHolder)));
        address burnToken = address(token);

        vm.startPrank(whaleTokenHolder);

        // Ensure the whale token holder approves the contract to spend the tokens
        token.approve(address(whiteBridgeMessenger), equalTipAmount);
        // Expect the contract to revert because the amount is not greater than the tip amount
        vm.expectRevert("Amount must be greater than the tip amount");
        // Attempt to make a deposit with an amount exactly equal to the tip amount
        whiteBridgeMessenger.sendMessage(equalTipAmount, destinationDomain, mintRecipient, burnToken);

        // Test for amount less than tip amount
        uint256 lessThanTipAmount = whiteBridgeMessenger.defaultTipAmount() - 1; // Less than tip amount by 1
        // Ensure the whale token holder approves the contract to spend the lesser amount
        token.approve(address(whiteBridgeMessenger), lessThanTipAmount);
        // Expect the contract to revert again due to the amount being less than the tip amount
        vm.expectRevert("Amount must be greater than the tip amount");
        // Attempt to make a deposit with an amount less than the tip amount
        whiteBridgeMessenger.sendMessage(lessThanTipAmount, destinationDomain, mintRecipient, burnToken);

        // Deposit with an amount larger than the tip amount should succeed
        token.approve(address(whiteBridgeMessenger), equalTipAmount + 1);
        whiteBridgeMessenger.sendMessage(equalTipAmount + 1, destinationDomain, mintRecipient, burnToken);

        vm.stopPrank();
    }
}
