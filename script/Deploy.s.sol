// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Script, console} from "forge-std/Script.sol";
import {Invoice} from "../src/Invoice.sol";
import {Vault} from "../src/Vault.sol";
import {RBT} from "../src/RBT.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployInvoice is Script {
    struct DeployResult {
        Invoice invoice;
        Vault vault;
        RBT rbt;
        HelperConfig config;
    }

    function deployVault() internal returns (Vault) {
        Vault vaultImplementation = new Vault();
        bytes memory vaultInitData = abi.encodeWithSelector(
            Vault.initialize.selector
        );
        ERC1967Proxy vaultProxy = new ERC1967Proxy(
            address(vaultImplementation),
            vaultInitData
        );
        return Vault(payable(address(vaultProxy)));
    }

    function deployRBT() internal returns (RBT) {
        RBT rbtImplementation = new RBT();
        bytes memory rbtInitData = abi.encodeWithSelector(
            RBT.initialize.selector
        );
        ERC1967Proxy rbtProxy = new ERC1967Proxy(
            address(rbtImplementation),
            rbtInitData
        );
        return RBT(address(rbtProxy));
    }

    function deployInvoice(Vault vault, RBT rbt) internal returns (Invoice) {
        Invoice implementation = new Invoice();
        bytes memory initData = abi.encodeWithSelector(
            Invoice.initialize.selector,
            address(vault),
            address(rbt)
        );
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            initData
        );
        return Invoice(address(proxy));
    }

    function run() external returns (Invoice, Vault, RBT, HelperConfig) {
        HelperConfig config = new HelperConfig();
        HelperConfig.NetworkConfig memory networkConfig = config
            .getActiveNetworkConfig();
        uint256 deployerKey = networkConfig.deployerKey;

        vm.startBroadcast(deployerKey);

        // 部署合约
        Vault vault = deployVault();
        RBT rbt = deployRBT();
        Invoice invoice = deployInvoice(vault, rbt);

        // 设置 RBT 的 Invoice 地址
        rbt.setInvoiceAddress(address(invoice));

        // 设置 Vault 的所有者为 Invoice 合约
        vault.transferOwnership(address(invoice));

        // 验证合约初始化
        require(address(vault) != address(0), "Vault not initialized");
        require(address(rbt) != address(0), "RBT not initialized");
        require(
            invoice.vaultAddress() == address(vault),
            "Invoice vault address mismatch"
        );
        require( 
            invoice.rbtAddress() == address(rbt),
            "Invoice RBT address mismatch"
        );
        require(vault.owner() == address(invoice), "Vault owner mismatch");

        vm.stopBroadcast();

        // 返回合约实例
        return (invoice, vault, rbt, config);
    }
}
