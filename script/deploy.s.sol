// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Importing Forge standard library's Script module
import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/TaxiSwapMessenger.sol";

/// @title DeployTaxiSwapMessenger
/// @notice This script is used for deterministically deploying the
/// TaxiSwapMessenger contract accross different chains.
/// @dev Run this script with the following command:
///      forge script script/deploy.s.sol:DeployTaxiSwapMessenger \
///      --rpc-url $RPC_URL --etherscan-api-key $ETHERSCAN_API_KEY \
///      --broadcast --verify -vvvv
/// It requires the RPC_URL,ETHERSCAN_API_KEY, VERIFIER_URL, PRIVATE_KEY, TOKEN_ADDRESS, OWNER and TOKEN_MESSENGER_ADDRESS  to be set as environment variables.
contract DeployTaxiSwapMessenger is Script {
    uint32[] initialAllowedDomains = [0, 1, 2, 3, 6, 7];
    /// @notice Main function that executes the deployment process
    /// @dev This function reads the private key from environment variables,
    ///      as also the token and token messenger addresses
    ///      initializes broadcasting, and deploys the TaxiSwapMessenger contract.
    ///      It also handles the broadcast stoppage after deployment.

    function run() public {
        address token = vm.envAddress("TOKEN_ADDRESS");
        address tokenMessenger = vm.envAddress("TOKEN_MESSENGER_ADDRESS");
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address owner = vm.envAddress("OWNER");
        address oracle = vm.envAddress("ORACLE");
        // Setting a bytes32 salt for deterministic deployment.
        // It can also be the version number.
        bytes32 versionSalt = bytes32("0");

        // Starting the broadcast transaction process with the provided private key
        vm.startBroadcast(privateKey);
        // Deploying the TaxiSwapMessenger contract with specified deployment salt
        new TaxiSwapMessenger{salt: versionSalt}(token, tokenMessenger, owner, oracle, initialAllowedDomains);

        // Stopping the broadcast process
        vm.stopBroadcast();
    }
}
