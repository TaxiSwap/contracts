// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Importing Forge standard library's Script module
import "forge-std/Script.sol";
import "forge-std/console.sol";
// Importing the WhiteBridgeMessenger contract
import "../src/WhiteBridgeMessenger.sol";

/// @title DeployWhiteBridgeMessenger
/// @notice This script is used for deterministically deploying the
/// WhiteBridgeMessenger contract accross different chains.
/// @dev Run this script with the following command:
///      forge script script/deploy.s.sol:DeployWhiteBridgeMessenger \
///      --rpc-url $RPC_URL --etherscan-api-key $ETHERSCAN_API_KEY \
///      --broadcast --verify -vvvv
/// It requires the RPC_URL,ETHERSCAN_API_KEY, VERIFIER_URL, PRIVATE_KEY, TOKEN_ADDRESS, OWNER and TOKEN_MESSENGER_ADDRESS  to be set as environment variables.
contract DeployWhiteBridgeMessenger is Script {
    /// @notice Main function that executes the deployment process
    /// @dev This function reads the private key from environment variables,
    ///      as also the token and token messenger addresses
    ///      initializes broadcasting, and deploys the WhiteBridgeMessenger contract.
    ///      It also handles the broadcast stoppage after deployment.

    function run() public {
        address token = vm.envAddress("TOKEN_ADDRESS");
        address tokenMessenger = vm.envAddress("TOKEN_MESSENGER_ADDRESS");
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address owner = vm.envAddress("OWNER");
        // Setting a bytes32 salt for deterministic deployment.
        // It can also be the version number.
        bytes32 versionSalt = bytes32("0");

        // Starting the broadcast transaction process with the provided private key
        vm.startBroadcast(privateKey);
        // Deploying the WhiteBridgeMessenger contract with specified deployment salt
        new WhiteBridgeMessenger{salt: versionSalt}(token, tokenMessenger, owner);

        // Stopping the broadcast process
        vm.stopBroadcast();
    }
}
