// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "../src/GasPriceOracle.sol"; // Adjust the path according to your project structure

contract GasPriceOracleTest is Test {
    GasPriceOracle oracle;
    address defaultAdmin = address(1);
    address oracleAddress = address(2);
    uint256 chainId = 1; // Example chain ID
    uint256 gasPrice = 100; // Example gas price
    uint256 usdConversionRate = 2000000; // Example USD conversion rate with 6 decimals
    uint256 gasAmount = 10000; // Example gas amount for transactions

    function setUp() public {
        oracle = new GasPriceOracle(defaultAdmin, oracleAddress);
        vm.prank(oracleAddress);
        oracle.addChainData(chainId, gasPrice, usdConversionRate);
    }

    function testGetTransactionGasCostInNativeToken() public {
        uint256 expectedCost = gasAmount * gasPrice;
        uint256 actualCost = oracle.getTransactionGasCostInNativeToken(chainId, gasAmount);
        assertEq(actualCost, expectedCost, "The calculated gas cost in native token does not match the expected value");
    }

    function testGetTransactionGasCostInUSD() public {
        uint256 expectedCostInUSD = (gasAmount * gasPrice * usdConversionRate) / 1e6;
        uint256 actualCostInUSD = oracle.getTransactionGasCostInUSD(chainId, gasAmount);
        assertEq(actualCostInUSD, expectedCostInUSD, "The calculated gas cost in USD does not match the expected value");
    }

    function testFailAddChainDataWithoutOracleRole() public {
        vm.prank(defaultAdmin); // Simulate call from someone other than the oracle
        oracle.addChainData(2, 150, 3000000); // This should fail since defaultAdmin does not have ORACLE_ROLE
    }

    function testFailUnauthorizedRoleAssignment() public {
        address unauthorizedUser = address(3);
        vm.prank(unauthorizedUser); // Simulate call from an unauthorized user
        oracle.grantRole(oracle.ORACLE_ROLE(), unauthorizedUser); // Attempt to grant ORACLE_ROLE
    }

    function testUpdateGasPrice() public {
        uint256 newGasPrice = 200; // New gas price to update
        vm.prank(oracleAddress);
        oracle.updateGasPrice(chainId, newGasPrice);

        // Verify the update
        (uint256 updatedGasPrice, uint256 unchangedUsdConversionRate) = oracle.chainData(chainId);
        assertEq(updatedGasPrice, newGasPrice, "Gas price did not update correctly");
        assertEq(unchangedUsdConversionRate, usdConversionRate, "Usd conversion rate did not stayed unchanged");
    }

    function testUpdateUsdConversionRate() public {
        uint256 newUsdConversionRate = 3000000; // New USD conversion rate to update
        vm.prank(oracleAddress);
        oracle.updateUsdConversionRate(chainId, newUsdConversionRate);

        // Verify the update
        (uint256 unchangedGasPrice, uint256 updatedUsdConversionRate) = oracle.chainData(chainId);
        assertEq(updatedUsdConversionRate, newUsdConversionRate, "USD conversion rate did not update correctly");
        assertEq(unchangedGasPrice, gasPrice, "Gas price did not stayed unchanged");
    }

    function testFailUnauthorizedGasPriceUpdate() public {
        uint256 unauthorizedNewGasPrice = 250;
        vm.prank(address(3)); // An unauthorized address
        oracle.updateGasPrice(chainId, unauthorizedNewGasPrice); // Should revert
    }

    function testFailUnauthorizedUsdConversionRateUpdate() public {
        uint256 unauthorizedNewUsdConversionRate = 4000000;
        vm.prank(address(3)); // An unauthorized address
        oracle.updateUsdConversionRate(chainId, unauthorizedNewUsdConversionRate); // Should revert
    }

    function testRevertOnReadUninitializedChainData() public {
        uint256 uninitializedChainId = 999; // Assuming this chain ID has not been initialized

        // Attempt to read gas price for an uninitialized chain ID
        vm.expectRevert("Chain data not available");
        oracle.getTransactionGasCostInNativeToken(uninitializedChainId, 10000); // Using arbitrary gas amount

        // Attempt to read USD conversion rate for an uninitialized chain ID
        vm.expectRevert("Chain data not available");
        oracle.getTransactionGasCostInUSD(uninitializedChainId, 10000); // Using arbitrary gas amount
    }
}
