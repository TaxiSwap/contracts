import os
import sys
import subprocess
from datetime import datetime

def load_env(network_name):
    """
    Load environment variables from a file.
    
    Parameters:
    - network_name: The name of the network (e.g., 'mainnet', 'rinkeby') for which to load the configuration.
    
    The function expects a file named `.env.<network_name>` in the current directory with environment variables.
    Each line in the file should be in the format `KEY=VALUE` and as `.env.example`.
    """
    env_file = f".env.{network_name}"
    if not os.path.exists(env_file):
        print(f"Configuration file for {network_name} does not exist.")
        sys.exit(1)

    with open(env_file) as f:
        for line in f:
            if "=" in line:
                key, value = line.strip().split("=", 1)
                os.environ[key] = value

def deploy_contract(network_name):
    """
    Deploy the contract using Foundry and log the output to the .deployment_logs folder.
    
    Parameters:
    - network_name: The name of the network (e.g., 'mainnet', 'rinkeby') where the contract will be deployed.

    This function constructs a forge command using environment variables set by `load_env`,
    executes the command, and logs the deployment output and errors (if any) to a file in `.deployment_logs`.
    """

    print(f"Starting deployment to {network_name}")
    cmd = [
        "forge", "script", "script/deploy.s.sol:DeployTaxiSwapMessenger",
        "--rpc-url", os.getenv("RPC_URL"),
        "--etherscan-api-key", os.getenv("ETHERSCAN_API_KEY"),
        "--verifier-url", os.getenv("VERIFIER_URL"),
        "--broadcast", "--verify", "-vvvv"
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)

    # Check if .deployment_logs exists, if not create it
    log_dir = ".deployment_logs"
    if not os.path.exists(log_dir):
        os.makedirs(log_dir)

    # Log file name with network name and current date
    log_file_name = f"{log_dir}/deployment_log_{network_name}_{datetime.now().strftime('%Y-%m-%d_%H-%M-%S')}.txt"
    with open(log_file_name, "w") as log_file:
        log_file.write(f"Deployment Date: {datetime.now()}\n")
        log_file.write(f"Network: {network_name}\n")
        log_file.write("Deployment Output:\n")
        log_file.write(result.stdout)
        if result.stderr:
            log_file.write("\nErrors:\n")
            log_file.write(result.stderr)

    print(f"Deployment output and logs written to {log_file_name}")

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python deploy.py <network_name>")
        sys.exit(1)

    network_name = sys.argv[1]
    load_env(network_name)  # Load the environment variables for the specified network
    deploy_contract(network_name)  # Deploy the contract and log the output
