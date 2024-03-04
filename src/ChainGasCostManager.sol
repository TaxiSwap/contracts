// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./GasPriceOracle.sol";

contract ChainGasCostManager is Ownable {
    GasPriceOracle public oracle;

    // Mapping of chain ID to required gas amount for receiving a message
    mapping(uint256 => uint256) public chainRequiredGas;

    constructor(address _oracleAddress, address _owner) Ownable(_owner) {
        oracle = GasPriceOracle(_oracleAddress);
    }

    function setRequiredGas(uint256 chainId, uint256 gasAmount) external onlyOwner {
        chainRequiredGas[chainId] = gasAmount;
    }

    function setMultipleRequiredGas(uint256[] calldata chainIds, uint256[] calldata gasAmounts) external onlyOwner {
        require(chainIds.length == gasAmounts.length, "Input arrays must have the same length");
        for (uint256 i = 0; i < chainIds.length; i++) {
            chainRequiredGas[chainIds[i]] = gasAmounts[i];
        }
    }

    function getTransactionCostInNative(uint256 chainId) external view returns (uint256) {
        require(chainRequiredGas[chainId] != 0, "No gas amount set for chain");
        uint256 gasAmount = chainRequiredGas[chainId];
        return oracle.getTransactionGasCostInNativeToken(chainId, gasAmount);
    }

    function getTransactionCostInUSD(uint256 chainId) external view returns (uint256) {
        require(chainRequiredGas[chainId] != 0, "No gas amount set for chain");
        uint256 gasAmount = chainRequiredGas[chainId];
        return oracle.getTransactionGasCostInUSD(chainId, gasAmount);
    }
}
