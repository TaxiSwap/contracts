## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

-   **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
-   **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
-   **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
-   **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

Copy the `.env` example and fill it with your data:
```shell
cp .env.example .env
```
Activate you environment variables, run a network fork with anvil and run the tests:

```shell
$ source .env
$ anvil --fork-url $RPC_URL --fork-block-number $FORK_BLOCK_NUMBER
$ forge test --fork-url=http://localhost:8545
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

Set the RPC_URL,ETHERSCAN_API_KEY, VERIFIER_URL, PRIVATE_KEY, TOKEN_ADDRESS, OWNER and TOKEN_MESSENGER_ADDRESS  environment variables before running it.

```shell
$ source .env
```

```shell
$ forge script script/deploy.s.sol:DeployWhiteBridgeMessenger \
--rpc-url $RPC_URL --etherscan-api-key $ETHERSCAN_API_KEY \
--broadcast --verify -vvvv
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
