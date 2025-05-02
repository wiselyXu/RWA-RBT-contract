// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Script, console} from "forge-std/Script.sol";
import {Invoice} from "../src/Invoice.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract UpgradeInvoice is Script {
    function run() external {
        // 获取配置
        HelperConfig config = new HelperConfig();
        uint256 deployerKey = config.getActiveNetworkConfig().deployerKey;

        // 获取代理合约地址
        address proxyAddress = vm.envAddress("INVOICE_PROXY_ADDRESS_MANTLE");
        require(proxyAddress != address(0), "Invalid proxy address");

        // 开始广播
        vm.startBroadcast(deployerKey);

        // 部署新的实现合约
        Invoice newImplementation = new Invoice();
        console.log(
            "New implementation deployed at:",
            address(newImplementation)
        );

        // 升级代理合约
        Invoice proxy = Invoice(payable(proxyAddress));
        proxy.upgradeTo(address(newImplementation));
        console.log("Proxy upgraded to new implementation");

        // 验证升级
        require(proxy.vaultAddress() != address(0), "Upgrade failed");
        console.log("Upgrade verified");

        vm.stopBroadcast();
    }
}
