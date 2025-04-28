// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Script} from "forge-std/Script.sol";

contract HelperConfig is Script {
    struct NetworkConfig {
        uint256 deployerKey;
    }

    NetworkConfig internal activeNetworkConfig;
    uint256 public constant PHAROS_TESTNET_CHAIN_ID = 50002;
    uint256 public constant ARBITRUM_SEPOLIA_CHAIN_ID = 421614;
    uint256 public constant MANTLE_TESTNET_CHAIN_ID = 5003;
    uint256 public constant DEFAULT_ANVIL_KEY =
        0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    // TODO: 等主网上线后添加
    // uint256 public constant PHAROS_MAINNET_CHAIN_ID;

    constructor() {
        if (block.chainid == PHAROS_TESTNET_CHAIN_ID) {
            activeNetworkConfig = getPharosTestnetConfig();
        } else if (block.chainid == ARBITRUM_SEPOLIA_CHAIN_ID) {
            activeNetworkConfig = getArbitrumSepoliaConfig();
        } else if (block.chainid == MANTLE_TESTNET_CHAIN_ID) {
            activeNetworkConfig = getMantleTestnetConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilConfig();
        }
    }

    function getPharosTestnetConfig()
        public
        view
        returns (NetworkConfig memory)
    {
        return NetworkConfig({deployerKey: vm.envUint("PRIVATE_KEY")});
    }

    function getArbitrumSepoliaConfig()
        public
        view
        returns (NetworkConfig memory)
    {
        return NetworkConfig({deployerKey: vm.envUint("PRIVATE_KEY")});
    }

    function getMantleTestnetConfig()
        public
        view
        returns (NetworkConfig memory)
    {
        return NetworkConfig({deployerKey: vm.envUint("PRIVATE_KEY")});
    }

    function getOrCreateAnvilConfig()
        public
        pure
        returns (NetworkConfig memory)
    {
        // 使用环境变量中的私钥对应的地址
        return NetworkConfig({deployerKey: DEFAULT_ANVIL_KEY});
    }

    function getActiveNetworkConfig()
        public
        view
        returns (NetworkConfig memory)
    {
        return activeNetworkConfig;
    }
}
