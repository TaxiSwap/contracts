// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import "../src/ChainGasCostManager.sol";
import "../src/GasPriceOracle.sol";

contract ChainGasCostManagerTest is Test {
    ChainGasCostManager chainGasCostManager;
    GasPriceOracle gasPriceOracle;

    address owner = address(0x1);
    address oracleAddress = address(0x2);

    function setUp() public {
        // Deploy GasPriceOracle with the owner and oracle roles
        gasPriceOracle = new GasPriceOracle(owner, oracleAddress);

        // Deploy ChainGasCostManager with the GasPriceOracle's address
        chainGasCostManager = new ChainGasCostManager(address(gasPriceOracle), owner);

        // Setup initial conditions if necessary, e.g., adding chain data in GasPriceOracle
    }

    function testSetRequiredGas() public {
        // Test setting required gas for a chain
        uint256 chainId = 1;
        uint256 gasAmount = 21000;

        vm.prank(owner);
        chainGasCostManager.setRequiredGas(chainId, gasAmount);

        assertEq(chainGasCostManager.chainRequiredGas(chainId), gasAmount);
    }

    function testSetMultipleRequiredGas() public {
        // Test setting multiple required gas amounts
        uint256[] memory chainIds = new uint256[](2);
        uint256[] memory gasAmounts = new uint256[](2);
        chainIds[0] = 1;
        gasAmounts[0] = 21000;
        chainIds[1] = 2;
        gasAmounts[1] = 30000;

        vm.prank(owner);
        chainGasCostManager.setMultipleRequiredGas(chainIds, gasAmounts);

        for (uint256 i = 0; i < chainIds.length; i++) {
            assertEq(chainGasCostManager.chainRequiredGas(chainIds[i]), gasAmounts[i]);
        }
    }

    function testGetTransactionCostInNative() public {
        // Setup required gas for a chain
        uint256 chainId = 1;
        uint256 gasAmount = 21000;
        vm.prank(owner);
        chainGasCostManager.setRequiredGas(chainId, gasAmount);

        // Setup price in oracle
        uint256 gasPrice = 100;
        uint256 usdConversionRate = 2000000;
        vm.prank(oracleAddress);
        gasPriceOracle.addChainData(1, gasPrice, usdConversionRate);

        // Act
        address anyUser = address(0x3);
        vm.prank(anyUser);
        assertEq(chainGasCostManager.getTransactionCostInNative(1), gasPrice * gasAmount);
    }

    function testGetTransactionCostInUSD() public {
        // Setup required gas for a chain
        uint256 chainId = 1;
        uint256 gasAmount = 21000;
        vm.prank(owner);
        chainGasCostManager.setRequiredGas(chainId, gasAmount);

        // Setup price in oracle
        uint256 gasPrice = 100;
        uint256 usdConversionRate = 2000000;
        vm.prank(oracleAddress);
        gasPriceOracle.addChainData(1, gasPrice, usdConversionRate);

        // Act
        address anyUser = address(0x3);
        vm.prank(anyUser);
        assertEq(chainGasCostManager.getTransactionCostInUSD(1), (gasAmount * gasPrice * usdConversionRate) / 1e6);
    }
}
