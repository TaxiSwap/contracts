// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "../src/TaxiSwapMessenger.sol";
import "../src/interfaces/ITaxiSwapMessenger.sol";
import "../src/interfaces/ITokenMessenger.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract TaxiSwapMessengerTest is Test {
    TaxiSwapMessenger public taxiSwapMessenger;
    IERC20 public token;
    address public whaleTokenHolder;
    address public tokenMessenger;
    uint256 public initialBalance = 100000e6; // 1000 USDC with 6  decimals
    address public owner = address(0xCAFEBABE);
    address public oracle = address(0x04AC1E);
    uint32[] initialAllowedDomains = [0, 1, 2, 3, 6, 7];

    // Event declaration
    event DepositForBurnCalled(
        uint64 indexed nonce,
        uint256 amount,
        uint32 indexed destinationDomain,
        bytes32 indexed mintRecipient,
        address burnToken
    );

    event DepositForBurn(
        uint64 indexed nonce,
        address indexed burnToken,
        uint256 amount,
        address indexed depositor,
        bytes32 mintRecipient,
        uint32 destinationDomain,
        bytes32 destinationTokenMessenger,
        bytes32 destinationCaller
    );

    function setUp() public {
        // Read environment variables
        // Ensure the test account has enough tokens for testing
        token = IERC20(address(bytes20(vm.envBytes("TOKEN_ADDRESS"))));
        tokenMessenger = address(bytes20(vm.envBytes("TOKEN_MESSENGER_ADDRESS")));
        whaleTokenHolder = vm.envAddress("WHALE_TOKEN_HOLDER");

        taxiSwapMessenger = new TaxiSwapMessenger(address(token), tokenMessenger, owner, oracle, initialAllowedDomains);

        vm.prank(whaleTokenHolder);
        token.approve(address(taxiSwapMessenger), initialBalance);
    }

    function testSendMessage() public {
        uint256 amount = 1000e6; // 6 decimals
        uint32 destinationDomain = 1;
        bytes32 mintRecipient = bytes32(uint256(uint160(whaleTokenHolder)));
        address burnToken = address(token);

        uint256 initialWhaleBalance = token.balanceOf(whaleTokenHolder);
        uint256 initialContractBalance = token.balanceOf(address(taxiSwapMessenger));

        uint256 actualRecievedAmount = amount - taxiSwapMessenger.getTipAmount(destinationDomain);

        // Expected parameters for the DepositForBurn event
        bytes32 destinationTokenMessenger = 0x0; // Dummy placeholder as it will be unckecked
        bytes32 destinationCaller = 0x0; // Dummy placeholder as it will be unckecked
        uint64 expectedNonce = 1; // Dummy placeholder as it will be unckecked

        vm.expectEmit(false, true, true, false, address(tokenMessenger)); // do not check data
        emit DepositForBurn(
            expectedNonce,
            burnToken,
            actualRecievedAmount,
            address(taxiSwapMessenger),
            mintRecipient,
            destinationDomain,
            destinationTokenMessenger,
            destinationCaller
        );

        vm.expectEmit(false, true, true, true, address(taxiSwapMessenger));
        emit DepositForBurnCalled(expectedNonce, actualRecievedAmount, destinationDomain, mintRecipient, burnToken);

        vm.prank(whaleTokenHolder);
        taxiSwapMessenger.sendMessage(amount, destinationDomain, mintRecipient, burnToken);

        uint256 finalWhaleBalance = token.balanceOf(whaleTokenHolder);
        uint256 finalContractBalance = token.balanceOf(address(taxiSwapMessenger));

        // Balance checks
        assertEq(initialWhaleBalance - finalWhaleBalance, amount, "Incorrect whale balance after transfers");
        assertEq(
            finalContractBalance - initialContractBalance,
            taxiSwapMessenger.getTipAmount(destinationDomain),
            "Incorrect contract balance after transfers"
        );
    }

    function testOracleCanChangeTips() public {
        uint256 domain1TipAmount = 5000; // Tip amount for domain 1
        uint256 domain2TipAmount = 15000; // Tip amount for domain 2
        vm.startPrank(oracle);
        taxiSwapMessenger.setTipAmountForDomain(1, domain1TipAmount);
        taxiSwapMessenger.setTipAmountForDomain(2, domain2TipAmount);
        vm.stopPrank();

        assertEq(taxiSwapMessenger.getTipAmount(1), domain1TipAmount, "Domain 1 tip amount not set");
        assertEq(taxiSwapMessenger.getTipAmount(2), domain2TipAmount, "Domain 2 tip amount not set");
    }

    function testUpdateMultipleTipAmountsForDomains() public {
        uint32[] memory domains = new uint32[](2);
        domains[0] = 1;
        domains[1] = 2;

        uint256[] memory tipAmounts = new uint256[](2);
        tipAmounts[0] = 1000;
        tipAmounts[1] = 2000;

        vm.prank(oracle);
        taxiSwapMessenger.updateTipAmountsForDomains(domains, tipAmounts);

        assertEq(
            taxiSwapMessenger.getTipAmount(domains[0]),
            tipAmounts[0],
            "Tip amount for domain 1 did not update correctly"
        );
        assertEq(
            taxiSwapMessenger.getTipAmount(domains[1]),
            tipAmounts[1],
            "Tip amount for domain 2 did not update correctly"
        );
    }

    function testFailNonOracleToUpdateMultipleTipAmountsForDomains() public {
        address nonOracle = address(0xdeadbeef);
        uint32[] memory domains = new uint32[](2);
        domains[0] = 1;
        domains[1] = 2;

        uint256[] memory tipAmounts = new uint256[](2);
        tipAmounts[0] = 1000;
        tipAmounts[1] = 2000;

        vm.prank(nonOracle);
        taxiSwapMessenger.updateTipAmountsForDomains(domains, tipAmounts);
    }

    function testSendMessageWithVariableTipAmount() public {
        uint256 domain1TipAmount = 5000; // Tip amount for domain 1
        uint256 domain2TipAmount = 15000; // Tip amount for domain 2
        vm.startPrank(oracle);
        taxiSwapMessenger.setTipAmountForDomain(1, domain1TipAmount);
        taxiSwapMessenger.setTipAmountForDomain(2, domain2TipAmount);
        vm.stopPrank();

        // Send a message for domain 1 and verify the tip amount is correctly used
        uint256 amountForDomain1 = 10000e6; // 10 USDC with 6 decimals, for example
        uint32 destinationDomain1 = 1;
        bytes32 mintRecipient1 = bytes32(uint256(uint160(whaleTokenHolder)));
        address burnToken1 = address(token);

        // Domain 1 tip
        vm.prank(whaleTokenHolder);
        taxiSwapMessenger.sendMessage(amountForDomain1, destinationDomain1, mintRecipient1, burnToken1);

        uint256 taxiSwapMessengerBalance1 = token.balanceOf(address(taxiSwapMessenger));
        assertEq(taxiSwapMessengerBalance1, domain1TipAmount, "Not correct tip amount 1 transfered");

        // Send a message for domain 2 and verify the tip amount is correctly used
        uint256 amountForDomain2 = 1000e6; // 1 USDC with 6 decimals, for example
        uint32 destinationDomain2 = 2;
        bytes32 mintRecipient2 = bytes32(uint256(uint160(whaleTokenHolder)));
        address burnToken2 = address(token);

        // Domain 2 tip
        vm.prank(whaleTokenHolder);
        taxiSwapMessenger.sendMessage(amountForDomain2, destinationDomain2, mintRecipient2, burnToken2);

        uint256 taxiSwapMessengerBalance2 = token.balanceOf(address(taxiSwapMessenger));
        assertEq(
            taxiSwapMessengerBalance2,
            taxiSwapMessengerBalance1 + domain2TipAmount,
            "Not correct tip amount 2 transfered"
        );
    }

    function testSendMessageWhenAmountLessThanOrEqualToTipForDomainShouldFail() public {
        uint32 testDomain = 1;
        uint256 testTipAmount = 5000;
        vm.prank(owner);
        taxiSwapMessenger.setTipAmountForDomain(testDomain, testTipAmount);

        uint256 insufficientAmount = testTipAmount; // This should trigger failure
        bytes32 mintRecipient = bytes32(uint256(uint160(whaleTokenHolder)));
        address burnToken = address(token);

        vm.startPrank(whaleTokenHolder);
        token.approve(address(taxiSwapMessenger), insufficientAmount);
        vm.expectRevert("Amount must be greater than the tip amount");
        taxiSwapMessenger.sendMessage(insufficientAmount, testDomain, mintRecipient, burnToken);
        vm.stopPrank();
    }

    function testSendMessageNotAllowedDomain() public {
        uint256 amount = 1000e6; // Assuming 6 decimals
        uint32 destinationDomain = 15; // A domain not in the allowed list
        bytes32 mintRecipient = bytes32(uint256(uint160(whaleTokenHolder)));
        address burnToken = address(token);

        // Expect the transaction to revert due to the domain not being allowed
        vm.expectRevert("Destination domain not allowed");
        vm.prank(whaleTokenHolder);
        taxiSwapMessenger.sendMessage(amount, destinationDomain, mintRecipient, burnToken);

        // Since the transaction is expected to revert, there's no need to check post-conditions
    }

    function testCannotSendMessageWhenPaused() public {
        uint256 amount = 1000e6;
        uint32 destinationDomain = 1;
        bytes32 mintRecipient = bytes32(uint256(uint160(whaleTokenHolder)));
        address burnToken = address(token);

        // Test when paused
        vm.prank(owner);
        taxiSwapMessenger.pause();

        vm.prank(whaleTokenHolder);
        vm.expectRevert("Contract is paused");
        taxiSwapMessenger.sendMessage(amount, destinationDomain, mintRecipient, burnToken);

        // Test the same action when unpaused
        vm.prank(owner);
        taxiSwapMessenger.unpause();

        vm.prank(whaleTokenHolder);
        taxiSwapMessenger.sendMessage(amount, destinationDomain, mintRecipient, burnToken);
    }

    function testChangedDefaultTipAmount() public {
        uint256 newTipAmount = 20000; // Example new tip amount
        vm.prank(owner);
        taxiSwapMessenger.setDefaultTipAmount(newTipAmount);
        assertEq(taxiSwapMessenger.defaultTipAmount(), newTipAmount, "Tip amount did not update correctly");
    }

    function testChangeAdmin() public {
        address newAdmin = address(0x01);
        vm.startPrank(owner);
        taxiSwapMessenger.grantRole(taxiSwapMessenger.DEFAULT_ADMIN_ROLE(), newAdmin);
        assertEq(taxiSwapMessenger.hasRole(taxiSwapMessenger.DEFAULT_ADMIN_ROLE(), newAdmin), true, "Role Not Granted");
        vm.stopPrank();
        vm.startPrank(newAdmin);
        taxiSwapMessenger.revokeRole(taxiSwapMessenger.DEFAULT_ADMIN_ROLE(), owner);
        assertEq(taxiSwapMessenger.hasRole(taxiSwapMessenger.DEFAULT_ADMIN_ROLE(), owner), false, "Role Not revoked");
        vm.stopPrank();
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
        token.approve(address(taxiSwapMessenger), depositAmount1 + depositAmount2);

        // Send message for first deposit
        vm.prank(whaleTokenHolder);
        taxiSwapMessenger.sendMessage(depositAmount1, destinationDomain, mintRecipient, burnToken);

        // Send message for deposit
        vm.prank(whaleTokenHolder);
        taxiSwapMessenger.sendMessage(depositAmount2, destinationDomain, mintRecipient, burnToken);

        // Calculate expected tips accumulated
        uint256 expectedTips = taxiSwapMessenger.defaultTipAmount() * 2; // Since two deposits were made

        // Check balances before withdrawal
        uint256 ownerBalanceBefore = token.balanceOf(owner);
        uint256 contractBalanceBefore = token.balanceOf(address(taxiSwapMessenger));
        assertEq(contractBalanceBefore, expectedTips, "Contract should have exactly the accumulated tips");

        // Withdraw tips
        vm.prank(owner);
        taxiSwapMessenger.withdrawTips();

        // Check balances after withdrawal
        uint256 ownerBalanceAfter = token.balanceOf(owner);
        uint256 contractBalanceAfter = token.balanceOf(address(taxiSwapMessenger));

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
        taxiSwapMessenger.setDefaultTipAmount(30000); // This should fail
    }

    function testFailAddAdminNonAdmin() public {
        vm.prank(address(0x2)); // An address that is not the owner
        taxiSwapMessenger.grantRole(taxiSwapMessenger.DEFAULT_ADMIN_ROLE(), address(0x2)); // This should fail
    }

    function testNonAdminCannotWithdrawTips() public {
        // Setup a new address that is not the owner
        address nonOwner = address(0xdead);

        // Attempt to withdraw tips as a non-owner
        bytes4 selector = bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)"));
        vm.expectRevert(abi.encodeWithSelector(selector, address(nonOwner), taxiSwapMessenger.DEFAULT_ADMIN_ROLE()));
        vm.prank(nonOwner); // Simulate the call coming from the non-owner address
        taxiSwapMessenger.withdrawTips();
    }

    function testDepositAmountShouldBeLargerThanTip() public {
        // Test for amount exactly equal to tip amount
        uint256 equalTipAmount = taxiSwapMessenger.defaultTipAmount();
        uint32 destinationDomain = 1;
        bytes32 mintRecipient = bytes32(uint256(uint160(whaleTokenHolder)));
        address burnToken = address(token);

        vm.startPrank(whaleTokenHolder);

        // Ensure the whale token holder approves the contract to spend the tokens
        token.approve(address(taxiSwapMessenger), equalTipAmount);
        // Expect the contract to revert because the amount is not greater than the tip amount
        vm.expectRevert("Amount must be greater than the tip amount");
        // Attempt to make a deposit with an amount exactly equal to the tip amount
        taxiSwapMessenger.sendMessage(equalTipAmount, destinationDomain, mintRecipient, burnToken);

        // Test for amount less than tip amount
        uint256 lessThanTipAmount = taxiSwapMessenger.defaultTipAmount() - 1; // Less than tip amount by 1
        // Ensure the whale token holder approves the contract to spend the lesser amount
        token.approve(address(taxiSwapMessenger), lessThanTipAmount);
        // Expect the contract to revert again due to the amount being less than the tip amount
        vm.expectRevert("Amount must be greater than the tip amount");
        // Attempt to make a deposit with an amount less than the tip amount
        taxiSwapMessenger.sendMessage(lessThanTipAmount, destinationDomain, mintRecipient, burnToken);

        // Deposit with an amount larger than the tip amount should succeed
        token.approve(address(taxiSwapMessenger), equalTipAmount + 1);
        taxiSwapMessenger.sendMessage(equalTipAmount + 1, destinationDomain, mintRecipient, burnToken);

        vm.stopPrank();
    }

    function testAllowDomain() public {
        uint32 testDomain = 8;
        vm.prank(owner);
        taxiSwapMessenger.allowDomain(testDomain);

        bool isAllowed = taxiSwapMessenger.allowedDomains(testDomain);
        assertTrue(isAllowed, "Domain should be allowed.");
    }

    function testDisallowDomain() public {
        uint32 testDomain = 8;
        // First, allow the domain to then disallow it
        vm.prank(owner);
        taxiSwapMessenger.allowDomain(testDomain);

        vm.prank(owner);
        taxiSwapMessenger.disallowDomain(testDomain);

        bool isAllowed = taxiSwapMessenger.allowedDomains(testDomain);
        assertFalse(isAllowed, "Domain should be disallowed.");
    }

    function testNonOwnerCannotAllowDomain() public {
        uint32 testDomain = 8;
        address nonOwner = address(0xDeaDBeef);
        vm.startPrank(nonOwner);
        bytes4 selector = bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)"));
        vm.expectRevert(abi.encodeWithSelector(selector, address(nonOwner), taxiSwapMessenger.DEFAULT_ADMIN_ROLE()));
        taxiSwapMessenger.allowDomain(testDomain);
        vm.stopPrank();
    }

    function testNonOwnerCannotDisallowDomain() public {
        uint32 testDomain = 8;
        address nonOwner = address(0xdeadbeef);
        // Assume domain is already allowed for this test
        vm.prank(owner);
        taxiSwapMessenger.allowDomain(testDomain);

        vm.startPrank(nonOwner);
        bytes4 selector = bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)"));
        vm.expectRevert(abi.encodeWithSelector(selector, address(nonOwner), taxiSwapMessenger.DEFAULT_ADMIN_ROLE()));
        taxiSwapMessenger.disallowDomain(testDomain);
        vm.stopPrank();
    }
}
