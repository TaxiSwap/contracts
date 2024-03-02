// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IGasPriceOracle {
    function getTransactionGasCostInNativeToken(uint256 otherChainId, uint256 gasAmount) external view returns (uint256);
    function getTransactionGasCostInUSD(uint256 otherChainId, uint256 gasAmount) external view returns (uint256);
    function updateGasPrice(uint256 _chainId, uint256 _gasPrice) external;
    function updateUsdConversionRate(uint256 _chainId, uint256 _usdConversionRate) external;
}
