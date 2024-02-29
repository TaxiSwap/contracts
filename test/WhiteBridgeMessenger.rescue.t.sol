// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
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

    error OwnableUnauthorizedAccount(address account);

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

    function testWithdrawEth() public {
        // Arrange: Simulate sending ETH to the contract
        uint256 depositAmount = 1 ether;
        // This simulates sending ETH directly to the contract's address
        payable(address(whiteBridgeMessenger)).transfer(depositAmount);
        // initial owner balance
        uint256 initialOwnerBalance = address(owner).balance;

        // Assert: Check the contract's balance to ensure it received the ETH
        assertEq(address(whiteBridgeMessenger).balance, depositAmount, "Contract did not receive ETH");

        // Act: Withdraw ETH by the owner
        vm.prank(owner);
        whiteBridgeMessenger.withdrawETH(payable(owner), depositAmount);

        // Assert: Check balances after withdrawal
        assertEq(address(whiteBridgeMessenger).balance, 0, "ETH not withdrawn from contract");
        assertEq(address(owner).balance, initialOwnerBalance + 1 ether, "ETH not reached owner");
    }

    function testNotOwnerCannotWithdrawEth() public {
        address thief = address(0xdeadbeef);
        // Arrange: Simulate sending ETH to the contract
        uint256 depositAmount = 1 ether;
        // This simulates sending ETH directly to the contract's address
        payable(address(whiteBridgeMessenger)).transfer(depositAmount);
        // Sending ETH also to thief for thief
        payable(address(thief)).transfer(depositAmount);
        // initial thief balance
        uint256 initialThiefBalance = address(thief).balance;

        // Assert: Check the contract's balance to ensure it received the ETH
        assertEq(address(whiteBridgeMessenger).balance, depositAmount, "Contract did not receive ETH");

        // Act: Withdraw ETH by the owner
        bytes4 selector = bytes4(keccak256("OwnableUnauthorizedAccount(address)"));
        vm.expectRevert(abi.encodeWithSelector(selector, address(thief)));
        vm.prank(thief);
        whiteBridgeMessenger.withdrawETH(payable(thief), depositAmount);

        // Assert: Check balances after withdrawal
        assertEq(address(whiteBridgeMessenger).balance, 1 ether, "ETH not withdrawn from contract");
        assertLe(address(thief).balance, initialThiefBalance, "ETH not reduced");
    }

    function testWithdrawTokens() public {
        // Arrange: Transfer some tokens to the contract from the whaleTokenHolder
        uint256 depositAmount = 1000e6; // Example token amount with 6 decimals
        vm.prank(whaleTokenHolder);
        token.transfer(address(whiteBridgeMessenger), depositAmount);
        // initial owner balance
        uint256 initialOwnerBalance = token.balanceOf(address(owner));

        // Assert: Check the contract's token balance to ensure it received the tokens
        assertEq(token.balanceOf(address(whiteBridgeMessenger)), depositAmount, "Contract did not receive tokens");

        // Act: Withdraw tokens by the owner
        vm.prank(owner);
        whiteBridgeMessenger.withdrawTokens(address(token), owner, depositAmount);

        // Assert: Check balances after withdrawal
        assertEq(token.balanceOf(address(whiteBridgeMessenger)), 0, "Tokens not withdrawn from contract");
        assertEq(token.balanceOf(owner), initialOwnerBalance + depositAmount, "Tokens not received by owner");
    }

    function testNotOwnerCannotWithdrawTokens() public {
        address nonOwner = address(0xdeadbeef);
        uint256 depositAmount = 1000e6; // Example token amount with 6 decimals

        // Arrange: Transfer some tokens to the contract from the whaleTokenHolder
        vm.prank(whaleTokenHolder);
        token.transfer(address(whiteBridgeMessenger), depositAmount);

        // Simulate giving some tokens to the nonOwner for the purpose of this test
        vm.prank(whaleTokenHolder);
        token.transfer(nonOwner, depositAmount);

        // initial nonOwner token balance
        uint256 initialNonOwnerBalance = token.balanceOf(nonOwner);

        // Assert: Check the contract's token balance to ensure it received the tokens
        assertEq(token.balanceOf(address(whiteBridgeMessenger)), depositAmount, "Contract did not receive tokens");

        // Act & Assert: Attempt to withdraw tokens by a non-owner should revert
        bytes4 selector = bytes4(keccak256("OwnableUnauthorizedAccount(address)"));
        vm.expectRevert(abi.encodeWithSelector(selector, nonOwner));
        vm.prank(nonOwner);
        whiteBridgeMessenger.withdrawTokens(address(token), nonOwner, depositAmount);

        // Assert: Check balances after failed withdrawal attempt
        assertEq(token.balanceOf(address(whiteBridgeMessenger)), depositAmount, "Tokens were withdrawn from contract");
        assertEq(token.balanceOf(nonOwner), initialNonOwnerBalance, "Non-owner's token balance should not change");
    }

    function testTokenApprovalUsingExecuteCall() public {
        // Arrange: Setup initial conditions
        uint256 tokenAmount = 1000 * 1e6; // Adjust based on token decimals
        vm.prank(whaleTokenHolder);
        token.transfer(address(whiteBridgeMessenger), tokenAmount);
        assertEq(token.balanceOf(address(whiteBridgeMessenger)), tokenAmount, "Initial token transfer failed");

        address spender = address(0x1);
        uint256 approveAmount = 500 * 1e18; // Amount to approve

        // Act: Construct the approve call data
        bytes memory data = abi.encodeWithSignature("approve(address,uint256)", spender, approveAmount);

        // Execute the approval from the contract to the spender
        vm.prank(owner);
        (bool success,) = whiteBridgeMessenger.executeCall(address(token), 0, data);

        // Assert: Check the approval was successful
        assertTrue(success, "executeCall failed");
        assertEq(token.allowance(address(whiteBridgeMessenger), spender), approveAmount, "Approval amount incorrect");
    }

    function testTokenApprovalUsingExecuteCallRevertsForNonOwner() public {
        // Arrange: Setup initial conditions
        uint256 tokenAmount = 1000 * 1e6; // Adjust based on token decimals
        vm.prank(whaleTokenHolder);
        token.transfer(address(whiteBridgeMessenger), tokenAmount);
        assertEq(token.balanceOf(address(whiteBridgeMessenger)), tokenAmount, "Initial token transfer failed");

        address nonOwner = address(0xDeadBeef); // A non-owner address
        address spender = address(0x1);
        uint256 approveAmount = 500 * 1e18; // Amount to approve

        // Act: Construct the approve call data
        bytes memory data = abi.encodeWithSignature("approve(address,uint256)", spender, approveAmount);

        // Expect the transaction to revert for non-owner
        bytes4 selector = bytes4(keccak256("OwnableUnauthorizedAccount(address)"));
        vm.expectRevert(abi.encodeWithSelector(selector, nonOwner));

        // Attempt to execute the approval from a non-owner
        vm.prank(nonOwner);
        whiteBridgeMessenger.executeCall(address(token), 0, data);

        // Assert: The allowance should not change since the call should revert
        assertEq(token.allowance(address(whiteBridgeMessenger), spender), 0, "Approval should not occur");
    }
}
