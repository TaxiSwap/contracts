// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "./interfaces/ITokenMessenger.sol";
import "./interfaces/ITaxiSwapMessenger.sol";
import "./RescueContract.sol";

/// @title A bridge messenger contract for transferring tokens with a tip mechanism
/// @dev This contract allows tokens to be sent across domains with an additional tip fee deducted from the transfer amount.
/// @notice This contract should be used with a corresponding CCTP token messenger and USDC token
contract TaxiSwapMessenger is AccessControl, Pausable, ITaxiSwapMessenger, RescueContract {
    bytes32 public constant ORACLE_ROLE = keccak256("ORACLE_ROLE");
    IERC20 public token;
    ITokenMessenger public tokenMessenger;
    mapping(uint32 => uint256) private tipAmountsByDomain;
    uint256 public defaultTipAmount = 950_000; // Default tip amount
    mapping(uint32 => bool) public allowedDomains;



    /// @dev Sets up the TaxiSwapMessenger with necessary addresses and defaults
    /// @param _token The address of the USDC token contract to be used for transfers and tips
    /// @param _tokenMessenger The address of the CCTP contract that handles the cross-domain token transfer
    constructor(
        address _token,
        address _tokenMessenger,
        address _owner,
        address _oracle,
        uint32[] memory _allowedDomains
    ) {
        _grantRole(DEFAULT_ADMIN_ROLE, _owner);
        _grantRole(ORACLE_ROLE, _owner);
        _grantRole(ORACLE_ROLE, _oracle);
        token = IERC20(_token);
        tokenMessenger = ITokenMessenger(_tokenMessenger);
        for (uint256 i = 0; i < _allowedDomains.length; i++) {
            allowedDomains[_allowedDomains[i]] = true;
        }
    }

    /// @notice Adds a domain to the list of allowed domains
    /// @param _domain The domain to allow
    function allowDomain(uint32 _domain) external onlyRole(DEFAULT_ADMIN_ROLE) {
        allowedDomains[_domain] = true;
    }

    /// @notice Removes a domain from the list of allowed domains
    /// @param _domain The domain to disallow
    function disallowDomain(uint32 _domain) external onlyRole(DEFAULT_ADMIN_ROLE) {
        allowedDomains[_domain] = false;
    }

    function pause() public onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() public onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /// @notice Sets the default tip amount required for processing the token transfer
    /// @dev This function can only be called by the owner of the contract.
    /// @param _defaultTipAmount The new tip amount in tokens
    function setDefaultTipAmount(uint256 _defaultTipAmount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        defaultTipAmount = _defaultTipAmount;
    }

    /// @notice Sets the tip amount required for processing the token transfer for a specific domain
    /// @dev This function can only be called by the owner of the contract.
    /// @param _domain The domain for which the tip amount is being set
    /// @param _tipAmount The new tip amount in tokens for the specified domain
    function setTipAmountForDomain(uint32 _domain, uint256 _tipAmount) external onlyRole(ORACLE_ROLE) {
        tipAmountsByDomain[_domain] = _tipAmount;
    }

    /// @notice Updates tip amounts for multiple domains
    /// @dev This function can only be called by the oracle.
    /// @param _domains An array of domain IDs for which the tip amounts are being updated
    /// @param _tipAmounts An array of new tip amounts for the specified domains
    function updateTipAmountsForDomains(uint32[] calldata _domains, uint256[] calldata _tipAmounts)
        external
        onlyRole(ORACLE_ROLE)
    {
        require(_domains.length == _tipAmounts.length, "Mismatched arrays length");

        for (uint256 i = 0; i < _domains.length; i++) {
            tipAmountsByDomain[_domains[i]] = _tipAmounts[i];
        }
    }

    function getTipAmount(uint32 _destinationDomain) external view returns (uint256) {
        return tipAmountsByDomain[_destinationDomain] > 0 ? tipAmountsByDomain[_destinationDomain] : defaultTipAmount;
    }

    /// @notice Processes a token transfer across domains with a tip deducted
    /// @dev Transfers the tip amount to the contract treasury and the remaining amount to the tokenMessenger for further processing.
    /// @param _amount The total amount of tokens to be transferred, including the tip
    /// @param _destinationDomain The domain where the tokens will be minted
    /// @param _mintRecipient The address on the destination domain to receive the minted tokens
    /// @param _burnToken The address of the token to burn on the source domain
    function sendMessage(uint256 _amount, uint32 _destinationDomain, bytes32 _mintRecipient, address _burnToken)
        external
    {
        require(!paused(), "Contract is paused");
        require(allowedDomains[_destinationDomain], "Destination domain not allowed");

        uint256 tipAmount =
            tipAmountsByDomain[_destinationDomain] > 0 ? tipAmountsByDomain[_destinationDomain] : defaultTipAmount;

        require(_amount > tipAmount, "Amount must be greater than the tip amount");

        // Transfer the tip amount to this contract's treasury
        require(token.transferFrom(msg.sender, address(this), tipAmount), "Tip transfer failed");

        // Calculate the remaining amount after deducting the tip
        uint256 remainingAmount = _amount - tipAmount;

        // Ensure the contract has enough allowance to transfer the remaining amount
        require(token.transferFrom(msg.sender, address(this), remainingAmount), "Transfer to contract failed");

        // Approve the tokenMessenger to spend the token on behalf of this contract
        token.approve(address(tokenMessenger), remainingAmount);

        // Call the predefined contract's depositForBurn method with the remaining amount
        uint64 nonce = tokenMessenger.depositForBurn(remainingAmount, _destinationDomain, _mintRecipient, _burnToken);

        // Emit the event after successful depositForBurn call
        emit DepositForBurnCalled(nonce, remainingAmount, _destinationDomain, _mintRecipient, _burnToken);
    }

    /// @notice Allows the owner to withdraw accumulated tip amounts
    /// @dev Withdraws all the tokens held by the contract to the owner's address.
    function withdrawTips() external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 balance = token.balanceOf(address(this));
        require(token.transfer(msg.sender, balance), "Withdrawal failed");
    }

    /// @notice Withdraws ETH from the contract to a specified address.
    /// @dev Calls the internal _withdrawETH function from RescueContract with onlyOwner modifier for access control.
    /// @param _to The address to which the ETH will be sent.
    /// @param _amount The amount of ETH to withdraw in wei.
    function withdrawETH(address payable _to, uint256 _amount) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _withdrawETH(_to, _amount);
    }

    /// @notice Withdraws ERC-20 tokens from the contract to a specified address.
    /// @dev Calls the internal _withdrawTokens function from RescueContract with onlyOwner modifier for access control.
    /// @param _tokenAddress The address of the ERC-20 token contract.
    /// @param _to The address to which the tokens will be sent.
    /// @param _amount The amount of tokens to withdraw.
    function withdrawTokens(address _tokenAddress, address _to, uint256 _amount) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _withdrawTokens(_tokenAddress, _to, _amount);
    }

    /// @notice Executes an arbitrary call to another contract or address with ETH value.
    /// @dev Calls the internal _executeCall function from RescueContract with onlyOwner modifier for access control.
    /// @param _to The address to call.
    /// @param _value The amount of ETH to send with the call, in wei.
    /// @param _data The calldata to send with the call.
    /// @return success Indicates whether the call was successful.
    /// @return result The return data from the call.
    function executeCall(address _to, uint256 _value, bytes calldata _data)
        public
        onlyRole(DEFAULT_ADMIN_ROLE)
        returns (bool, bytes memory)
    {
        return _executeCall(_to, _value, _data);
    }
}
