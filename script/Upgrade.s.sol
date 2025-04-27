// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import {Invoice} from "../src/Invoice.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract UpgradeInvoice is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address proxyAddress = vm.envAddress("PROXY_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);

        // 1. 部署新的实现合约
        Invoice newImplementation = new Invoice();

        // 2. 升级到新实现
        UUPSUpgradeable proxy = UUPSUpgradeable(proxyAddress);
        proxy.upgradeToAndCall(
            address(newImplementation),
            "" // 如果新版本需要初始化，这里可以传入初始化数据
        );

        vm.stopBroadcast();

        console.log(
            "New implementation deployed to:",
            address(newImplementation)
        );
        console.log("Proxy upgraded at:", proxyAddress);
    }
}
