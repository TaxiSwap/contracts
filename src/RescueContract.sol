// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract RescueContract {
    // Internal function to withdraw ETH
    function _withdrawETH(address payable _to, uint256 _amount) internal {
        require(address(this).balance >= _amount, "Insufficient balance");
        _to.transfer(_amount);
    }

    // Internal function to withdraw ERC-20 tokens
    function _withdrawTokens(address _tokenAddress, address _to, uint256 _amount) internal {
        require(IERC20(_tokenAddress).balanceOf(address(this)) >= _amount, "Insufficient token balance");
        IERC20(_tokenAddress).transfer(_to, _amount);
    }

    // Internal function to execute arbitrary calls
    function _executeCall(address _to, uint256 _value, bytes memory _data) internal returns (bool, bytes memory) {
        (bool success, bytes memory result) = _to.call{value: _value}(_data);
        require(success, "Call failed");
        return (success, result);
    }

    // Allow contract to receive ETH
    receive() external payable {}
}
