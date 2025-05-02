-include .env.local

.PHONY: all test deploy

build :; forge build

test :; forge test

install :; forge install OpenZeppelin/openzeppelin-contracts-upgradeable@v4.8.3 --no-commit && forge install OpenZeppelin/openzeppelin-contracts@v4.8.3 --no-commit && forge install onchain-id/solidity --no-commit && forge install erc3643/erc3643 --no-commit && forge install foundry-rs/forge-std --no-commit

