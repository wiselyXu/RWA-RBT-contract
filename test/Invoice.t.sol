// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Test, console} from "forge-std/Test.sol";
import {Invoice} from "../src/Invoice.sol";
import {Vault} from "../src/Vault.sol";
import {RBT} from "../src/RBT.sol";
import {DeployInvoice} from "../script/Deploy.s.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract InvoiceTest is Test {
    Invoice public invoice;
    Vault public vault;
    RBT public rbt;
    HelperConfig public config;
    address public owner;
    address public payee;
    address public payer;
    address public buyer;
    address public stableToken;

    event SharePurchased(
        string indexed batchId,
        address indexed buyer,
        uint256 amount,
        uint256 timestamp
    );

    function setUp() public {
        payee = makeAddr("payee");
        payer = makeAddr("payer");
        buyer = makeAddr("buyer");
        stableToken = makeAddr("stableToken");

        // 使用部署脚本部署合约
        DeployInvoice deployer = new DeployInvoice();
        (invoice, vault, rbt, config) = deployer.run();

        uint256 deployerKey = config.getActiveNetworkConfig().deployerKey;
        owner = vm.addr(deployerKey);
    }

    function test_CreateInvoice() public {
        vm.startPrank(payee);

        // 准备票据数据
        Invoice.InvoiceData[] memory invoices = new Invoice.InvoiceData[](1);
        invoices[0] = Invoice.InvoiceData({
            invoiceNumber: "INV001",
            payee: payee,
            payer: payer,
            amount: 1000,
            ipfsHash: "QmHash1",
            contractHash: "QmHash2",
            timestamp: 0,
            dueDate: block.timestamp + 30 days,
            tokenBatch: "",
            isCleared: false,
            isValid: false
        });

        // 创建票据
        invoice.batchCreateInvoices(invoices);

        // 验证票据信息
        Invoice.InvoiceData memory result = invoice.getInvoice("INV001");
        assertEq(result.invoiceNumber, "INV001");
        assertEq(result.payee, payee);
        assertEq(result.payer, payer);
        assertEq(result.amount, 1000);
        assertEq(result.isValid, true);
        assertEq(result.timestamp, block.timestamp);

        vm.stopPrank();
    }

    function test_CreateTokenBatch() public {
        vm.startPrank(payee);

        // 先创建票据
        Invoice.InvoiceData[] memory invoices = new Invoice.InvoiceData[](2);
        invoices[0] = Invoice.InvoiceData({
            invoiceNumber: "INV001",
            payee: payee,
            payer: payer,
            amount: 1000,
            ipfsHash: "QmHash1",
            contractHash: "QmHash2",
            timestamp: 0,
            dueDate: block.timestamp + 30 days,
            tokenBatch: "",
            isCleared: false,
            isValid: false
        });
        invoices[1] = Invoice.InvoiceData({
            invoiceNumber: "INV002",
            payee: payee,
            payer: payer,
            amount: 2000,
            ipfsHash: "QmHash3",
            contractHash: "QmHash4",
            timestamp: 0,
            dueDate: block.timestamp + 30 days,
            tokenBatch: "",
            isCleared: false,
            isValid: false
        });
        invoice.batchCreateInvoices(invoices);

        // 创建批次
        string[] memory invoiceNumbers = new string[](2);
        invoiceNumbers[0] = "INV001";
        invoiceNumbers[1] = "INV002";

        invoice.createTokenBatch(
            "BATCH001",
            invoiceNumbers,
            stableToken,
            6, // 最短6个月
            12, // 最长12个月
            500 // 5% 年化利率
        );

        // 验证批次信息
        Invoice.InvoiceTokenBatch memory batch = invoice.getTokenBatch(
            "BATCH001"
        );
        assertEq(batch.batchId, "BATCH001");
        assertEq(batch.payee, payee);
        assertEq(batch.payer, payer);
        assertEq(batch.totalAmount, 3000);
        assertEq(batch.isSigned, true);
        assertEq(batch.isIssued, false);

        vm.stopPrank();
    }

    function test_ConfirmTokenBatch() public {
        // 先创建票据和批次
        test_CreateTokenBatch();

        // 债务人确认发行
        vm.startPrank(payer);
        invoice.confirmTokenBatchIssue("BATCH001");

        // 验证批次状态
        Invoice.InvoiceTokenBatch memory batch = invoice.getTokenBatch(
            "BATCH001"
        );
        assertEq(batch.isIssued, true);

        vm.stopPrank();
    }

    function test_PurchaseShares() public {
        // 先确认发行
        test_ConfirmTokenBatch();

        // 设置稳定币余额
        vm.mockCall(
            stableToken,
            abi.encodeWithSelector(IERC20.balanceOf.selector, buyer),
            abi.encode(1000)
        );
        vm.mockCall(
            stableToken,
            abi.encodeWithSelector(
                IERC20.transferFrom.selector,
                buyer,
                payee,
                500
            ),
            abi.encode(true)
        );
        vm.mockCall(
            stableToken,
            abi.encodeWithSelector(
                IERC20.transferFrom.selector,
                buyer,
                address(vault),
                500
            ),
            abi.encode(true)
        );

        // 设置事件期望
        vm.expectEmit(true, true, true, true);
        emit SharePurchased("BATCH001", buyer, 1000, block.timestamp);

        // 购买份额
        vm.startPrank(buyer);
        invoice.purchaseShares("BATCH001", 1000);
        vm.stopPrank();
    }

    function test_QueryInvoices() public {
        // 先创建票据和批次
        test_CreateTokenBatch();

        // 按批次查询
        Invoice.QueryParams memory params = Invoice.QueryParams({
            batchId: "BATCH001",
            payer: address(0),
            payee: address(0),
            invoiceNumber: "",
            checkValid: true
        });
        Invoice.QueryResult memory result = invoice.queryInvoices(params);
        assertEq(result.total, 2);
        assertEq(result.invoices[0].invoiceNumber, "INV001");
        assertEq(result.invoices[1].invoiceNumber, "INV002");

        // 按债务人查询
        params = Invoice.QueryParams({
            batchId: "",
            payer: payer,
            payee: address(0),
            invoiceNumber: "",
            checkValid: true
        });
        result = invoice.queryInvoices(params);
        assertEq(result.total, 2);
        assertEq(result.invoices[0].invoiceNumber, "INV001");
        assertEq(result.invoices[1].invoiceNumber, "INV002");

        // 按债权人查询
        params = Invoice.QueryParams({
            batchId: "",
            payer: address(0),
            payee: payee,
            invoiceNumber: "",
            checkValid: true
        });
        result = invoice.queryInvoices(params);
        assertEq(result.total, 2);
        assertEq(result.invoices[0].invoiceNumber, "INV001");
        assertEq(result.invoices[1].invoiceNumber, "INV002");

        // 按票据编号查询
        params = Invoice.QueryParams({
            batchId: "",
            payer: address(0),
            payee: address(0),
            invoiceNumber: "INV001",
            checkValid: true
        });
        result = invoice.queryInvoices(params);
        assertEq(result.total, 1);
        assertEq(result.invoices[0].invoiceNumber, "INV001");
    }

    function test_InvalidateInvoice() public {
        // 先创建票据
        test_CreateInvoice();

        // 作废票据
        vm.startPrank(owner);
        invoice.invalidateInvoice("INV001");

        // 验证票据状态
        Invoice.InvoiceData memory result = invoice.getInvoice("INV001", false);
        assertEq(result.isValid, false);

        vm.stopPrank();
    }

    function test_PauseUnpause() public {
        vm.startPrank(owner);

        // 暂停合约
        invoice.pause();
        assertEq(invoice.paused(), true);

        // 恢复合约
        invoice.unpause();
        assertEq(invoice.paused(), false);

        vm.stopPrank();
    }
}
