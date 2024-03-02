// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "./interfaces/IGasPriceOracle.sol";

contract GasPriceOracle is AccessControl, IGasPriceOracle{
    bytes32 public constant ORACLE_ROLE = keccak256("ORACLE_ROLE");

    struct ChainData {
        uint256 gasPrice; // Gas price in the native currency of the chain
        uint256 usdConversionRate; // Conversion rate to USD
    }

    // Mapping from chain ID to its data
    mapping(uint256 => ChainData) public chainData;

    constructor(address defaultAdmin, address oracle) {
        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(ORACLE_ROLE, oracle);
    }

    // Function to add or update chain data
    function addChainData(uint256 _chainId, uint256 _gasPrice, uint256 _usdConversionRate)
        public
        onlyRole(ORACLE_ROLE)
    {
        chainData[_chainId] = ChainData(_gasPrice, _usdConversionRate);
    }

    // Function to get transaction gas cost in the native token
    function getTransactionGasCostInNativeToken(uint256 otherChainId, uint256 gasAmount)
        external
        view
        returns (uint256)
    {
        ChainData memory data = chainData[otherChainId];
        require(data.gasPrice > 0, "Chain data not available");
        return gasAmount * data.gasPrice;
    }

    // Function to get transaction gas cost in USD
    function getTransactionGasCostInUSD(uint256 otherChainId, uint256 gasAmount) external view returns (uint256) {
        ChainData memory data = chainData[otherChainId];
        require(data.gasPrice > 0 && data.usdConversionRate > 0, "Chain data not available");

        // Calculate the cost in native token first
        uint256 costInNative = gasAmount * data.gasPrice;

        // Convert the cost to USD, adjusting for the 6 decimals in usdConversionRate
        // Since usdConversionRate is with 6 decimals, we multiply by the costInNative and then divide by 10^6
        return (costInNative * data.usdConversionRate) / 1e6;
    }

    // Function to update gas price for a specific chain
    function updateGasPrice(uint256 _chainId, uint256 _gasPrice) public onlyRole(ORACLE_ROLE) {
        ChainData storage data = chainData[_chainId];
        require(data.gasPrice != 0, "Chain data not initialized");
        data.gasPrice = _gasPrice;
    }

    // Function to update USD conversion rate for a specific chain
    function updateUsdConversionRate(uint256 _chainId, uint256 _usdConversionRate) public onlyRole(ORACLE_ROLE) {
        ChainData storage data = chainData[_chainId];
        require(data.usdConversionRate != 0, "Chain data not initialized");
        data.usdConversionRate = _usdConversionRate;
    }
}
