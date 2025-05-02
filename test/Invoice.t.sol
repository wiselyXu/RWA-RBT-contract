// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Test, console} from "forge-std/Test.sol";
import {Invoice} from "../src/Invoice.sol";
import {Vault} from "../src/Vault.sol";
import {RBT} from "../src/RBT.sol";
import {DeployInvoice} from "../script/Deploy.s.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/draft-IERC20Permit.sol";
import {IRBT} from "../src/interfaces/IRBT.sol";
import {IVault} from "../src/interfaces/IVault.sol";

contract InvoiceTest is Test {
    Invoice public invoice;
    Vault public vault;
    RBT public rbt;
    HelperConfig public config;
    address public owner;
    address public payee;
    address public payer;
    address public buyer;
    uint256 public buyerKey;
    address public stableToken;
    address public rbtAddress;

    event SharePurchased(
        string indexed batchId,
        address indexed buyer,
        uint256 amount,
        uint256 timestamp
    );

    event NativeInvoiceRepaid(
        string indexed batchId,
        address indexed payer,
        uint256 amount,
        uint256 timestamp
    );

    event InvoiceRepaid(
        string indexed batchId,
        address indexed payer,
        uint256 amount,
        uint256 timestamp
    );

    event InvestorWithdrawn(
        address indexed investor,
        uint256 amount,
        address token,
        uint256 timestamp
    );

    function setUp() public {
        payee = makeAddr("payee");
        payer = makeAddr("payer");
        (buyer, buyerKey) = makeAddrAndKey("buyer");
        stableToken = makeAddr("stableToken");

        // 使用部署脚本部署合约
        DeployInvoice deployer = new DeployInvoice();
        (invoice, vault, rbt, config) = deployer.run();

        rbtAddress = address(rbt);
        uint256 deployerKey = config.getActiveNetworkConfig().deployerKey;
        owner = vm.addr(deployerKey);
    }

    // 创建票据的辅助函数
    function createInvoice(
        string memory invoiceNumber,
        uint256 amount,
        uint256 dueDate
    ) internal {
        vm.startPrank(payee);

        // 准备票据数据
        Invoice.InvoiceData[] memory invoices = new Invoice.InvoiceData[](1);
        invoices[0] = Invoice.InvoiceData({
            invoiceNumber: invoiceNumber,
            payee: payee,
            payer: payer,
            amount: amount,
            ipfsHash: "QmHash1",
            contractHash: "QmHash2",
            timestamp: 0,
            dueDate: dueDate,
            tokenBatch: "",
            isCleared: false,
            isValid: false
        });

        // 创建票据
        invoice.batchCreateInvoices(invoices);

        // 验证票据信息
        Invoice.InvoiceData memory result = invoice.getInvoice(invoiceNumber);
        assertEq(result.invoiceNumber, invoiceNumber);
        assertEq(result.payee, payee);
        assertEq(result.payer, payer);
        assertEq(result.amount, amount);
        assertEq(result.isValid, true);
        assertEq(result.timestamp, block.timestamp);

        vm.stopPrank();
    }

    // 创建批次的辅助函数
    function createTokenBatch(
        string memory batchId,
        string[] memory invoiceNumbers,
        address /* stableToken */,
        uint256 minTerm,
        uint256 maxTerm,
        uint256 interestRate
    ) internal {
        vm.startPrank(payee);

        // 创建批次
        invoice.createTokenBatch(
            batchId,
            invoiceNumbers,
            stableToken,
            minTerm,
            maxTerm,
            interestRate
        );

        // 验证批次信息
        Invoice.InvoiceTokenBatch memory batch = invoice.getTokenBatch(batchId);
        assertEq(batch.batchId, batchId);
        assertEq(batch.payee, payee);
        assertEq(batch.payer, payer);
        assertEq(batch.isSigned, true);
        assertEq(batch.isIssued, false);

        vm.stopPrank();
    }

    function test_CreateInvoice() public {
        createInvoice("INV001", 1000, block.timestamp + 30 days);
    }

    function test_CreateTokenBatch() public {
        // 先创建票据
        createInvoice("INV001", 1000, block.timestamp + 30 days);
        createInvoice("INV002", 2000, block.timestamp + 30 days);

        // 创建批次
        string[] memory invoiceNumbers = new string[](2);
        invoiceNumbers[0] = "INV001";
        invoiceNumbers[1] = "INV002";

        createTokenBatch(
            "BATCH001",
            invoiceNumbers,
            stableToken,
            6, // 最短6个月
            12, // 最长12个月
            500 // 5% 年化利率
        );
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

        // 空参数查询（返回所有票据）
        params = Invoice.QueryParams({
            batchId: "",
            payer: address(0),
            payee: address(0),
            invoiceNumber: "",
            checkValid: true
        });
        result = invoice.queryInvoices(params);
        assertEq(result.total, 2);
        assertEq(result.invoices[0].invoiceNumber, "INV001");
        assertEq(result.invoices[1].invoiceNumber, "INV002");

        // 测试无效票据查询
        vm.startPrank(owner);
        invoice.invalidateInvoice("INV001");
        vm.stopPrank();

        // 检查有效性查询
        params = Invoice.QueryParams({
            batchId: "",
            payer: address(0),
            payee: address(0),
            invoiceNumber: "",
            checkValid: true
        });
        result = invoice.queryInvoices(params);
        assertEq(result.total, 1);
        assertEq(result.invoices[0].invoiceNumber, "INV002");

        // 不检查有效性查询
        params = Invoice.QueryParams({
            batchId: "",
            payer: address(0),
            payee: address(0),
            invoiceNumber: "",
            checkValid: false
        });
        result = invoice.queryInvoices(params);
        assertEq(result.total, 2);
        assertEq(result.invoices[0].invoiceNumber, "INV001");
        assertEq(result.invoices[1].invoiceNumber, "INV002");
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

    function testPurchaseSharesWithNativeToken() public {
        // 创建票据和批次
        string memory invoiceNumber = "INV-001";
        string memory batchId = "BATCH-001";
        uint256 totalAmount = 100 ether;

        // 创建票据
        createInvoice(invoiceNumber, totalAmount, block.timestamp + 30 days);

        // 创建批次
        string[] memory invoiceNumbers = new string[](1);
        invoiceNumbers[0] = invoiceNumber;
        createTokenBatch(
            batchId,
            invoiceNumbers,
            address(0), // 使用原生代币
            1, // minTerm
            12, // maxTerm
            500 // interestRate (5%)
        );

        // 确认发行
        vm.startPrank(payer);
        invoice.confirmTokenBatchIssue(batchId);
        vm.stopPrank();

        // 投资人使用原生代币购买份额
        uint256 purchaseAmount = 50 ether;
        vm.deal(buyer, purchaseAmount);
        vm.startPrank(buyer);
        invoice.purchaseSharesWithNativeToken{value: purchaseAmount}(batchId);
        vm.stopPrank();

        // 验证投资人余额
        assertEq(buyer.balance, 0);
        assertEq(payee.balance, purchaseAmount);

        // 验证已售出金额
        assertEq(invoice.getBatchSoldAmount(batchId), purchaseAmount);

        // 验证 RBT Token 余额
        assertEq(rbt.balanceOf(buyer), purchaseAmount);
    }

    function testPurchaseSharesWithNativeTokenRevertsIfBatchNotIssued() public {
        string memory batchId = "BATCH-001";
        uint256 purchaseAmount = 50 ether;
        vm.deal(buyer, purchaseAmount);
        vm.startPrank(buyer);
        vm.expectRevert(Invoice.Invoice__BatchNotIssued.selector);
        invoice.purchaseSharesWithNativeToken{value: purchaseAmount}(batchId);
        vm.stopPrank();
    }

    function testPurchaseSharesWithNativeTokenRevertsIfAmountZero() public {
        string memory invoiceNumber = "INV-001";
        string memory batchId = "BATCH-001";
        uint256 totalAmount = 100 ether;

        // 创建票据
        createInvoice(invoiceNumber, totalAmount, block.timestamp + 30 days);

        // 创建批次
        string[] memory invoiceNumbers = new string[](1);
        invoiceNumbers[0] = invoiceNumber;
        createTokenBatch(
            batchId,
            invoiceNumbers,
            address(0), // 使用原生代币
            1, // minTerm
            12, // maxTerm
            500 // interestRate (5%)
        );

        // 确认发行
        vm.startPrank(payer);
        invoice.confirmTokenBatchIssue(batchId);
        vm.stopPrank();

        vm.deal(buyer, 1 ether);
        vm.startPrank(buyer);
        vm.expectRevert(Invoice.Invoice__InvalidAmount.selector);
        invoice.purchaseSharesWithNativeToken{value: 0}(batchId);
        vm.stopPrank();
    }

    function testPurchaseSharesWithNativeTokenRevertsIfInsufficientBalance()
        public
    {
        string memory invoiceNumber = "INV-001";
        string memory batchId = "BATCH-001";
        uint256 totalAmount = 100 ether;

        // 创建票据
        createInvoice(invoiceNumber, totalAmount, block.timestamp + 30 days);

        // 创建批次
        string[] memory invoiceNumbers = new string[](1);
        invoiceNumbers[0] = invoiceNumber;
        createTokenBatch(
            batchId,
            invoiceNumbers,
            address(0), // 使用原生代币
            1, // minTerm
            12, // maxTerm
            500 // interestRate (5%)
        );

        // 确认发行
        vm.startPrank(payer);
        invoice.confirmTokenBatchIssue(batchId);
        vm.stopPrank();

        uint256 purchaseAmount = 150 ether;
        vm.deal(buyer, purchaseAmount);
        vm.startPrank(buyer);
        vm.expectRevert(Invoice.Invoice__InsufficientBalance.selector);
        invoice.purchaseSharesWithNativeToken{value: purchaseAmount}(batchId);
        vm.stopPrank();
    }

    function testRepayInvoice() public {
        // 先创建票据和批次
        test_CreateTokenBatch();

        // 设置稳定币余额
        vm.mockCall(
            stableToken,
            abi.encodeWithSelector(IERC20.balanceOf.selector, payer),
            abi.encode(1000)
        );
        vm.mockCall(
            stableToken,
            abi.encodeWithSelector(
                IERC20.transferFrom.selector,
                payer,
                address(vault),
                1000
            ),
            abi.encode(true)
        );

        // 设置事件期望
        vm.expectEmit(true, true, true, true);
        emit InvoiceRepaid("BATCH001", payer, 1000, block.timestamp);

        // 债务人还款
        vm.startPrank(payer);
        invoice.repayInvoice("BATCH001", 1000);
        vm.stopPrank();
    }

    function testRepayInvoiceWithNativeToken() public {
        // 创建票据和批次
        string memory invoiceNumber = "INV-001";
        string memory batchId = "BATCH-001";
        uint256 totalAmount = 100 ether;

        // 创建票据
        createInvoice(invoiceNumber, totalAmount, block.timestamp + 30 days);

        // 创建批次
        string[] memory invoiceNumbers = new string[](1);
        invoiceNumbers[0] = invoiceNumber;
        createTokenBatch(
            batchId,
            invoiceNumbers,
            address(0), // 使用原生代币
            1, // minTerm
            12, // maxTerm
            500 // interestRate (5%)
        );

        // 设置事件期望
        vm.expectEmit(true, true, true, true);
        emit NativeInvoiceRepaid(batchId, payer, 50 ether, block.timestamp);

        // 债务人还款
        vm.deal(payer, 50 ether);
        vm.startPrank(payer);
        invoice.repayInvoiceWithNativeToken{value: 50 ether}(batchId);
        vm.stopPrank();

        // 验证余额
        assertEq(payer.balance, 0);
        assertEq(address(vault).balance, 50 ether);
    }

    function testRepayInvoiceRevertsIfUnauthorized() public {
        // 先创建票据和批次
        test_CreateTokenBatch();

        // 非债务人尝试还款
        vm.startPrank(buyer);
        vm.expectRevert(Invoice.Invoice__UnauthorizedRepayment.selector);
        invoice.repayInvoice("BATCH001", 1000);
        vm.stopPrank();
    }

    function testRepayInvoiceWithNativeTokenRevertsIfUnauthorized() public {
        // 先创建票据和批次
        string memory invoiceNumber = "INV-001";
        string memory batchId = "BATCH-001";
        uint256 totalAmount = 100 ether;

        // 创建票据
        createInvoice(invoiceNumber, totalAmount, block.timestamp + 30 days);

        // 创建批次
        string[] memory invoiceNumbers = new string[](1);
        invoiceNumbers[0] = invoiceNumber;
        createTokenBatch(
            batchId,
            invoiceNumbers,
            address(0), // 使用原生代币
            1, // minTerm
            12, // maxTerm
            500 // interestRate (5%)
        );

        // 非债务人尝试还款
        vm.deal(buyer, 50 ether);
        vm.startPrank(buyer);
        vm.expectRevert(Invoice.Invoice__UnauthorizedRepayment.selector);
        invoice.repayInvoiceWithNativeToken{value: 50 ether}(batchId);
        vm.stopPrank();
    }

    function testRepayInvoiceRevertsIfAmountZero() public {
        // 先创建票据和批次
        test_CreateTokenBatch();

        // 债务人尝试还款金额为0
        vm.startPrank(payer);
        vm.expectRevert(Invoice.Invoice__InvalidAmount.selector);
        invoice.repayInvoice("BATCH001", 0);
        vm.stopPrank();
    }

    function testRepayInvoiceWithNativeTokenRevertsIfAmountZero() public {
        // 先创建票据和批次
        string memory invoiceNumber = "INV-001";
        string memory batchId = "BATCH-001";
        uint256 totalAmount = 100 ether;

        // 创建票据
        createInvoice(invoiceNumber, totalAmount, block.timestamp + 30 days);

        // 创建批次
        string[] memory invoiceNumbers = new string[](1);
        invoiceNumbers[0] = invoiceNumber;
        createTokenBatch(
            batchId,
            invoiceNumbers,
            address(0), // 使用原生代币
            1, // minTerm
            12, // maxTerm
            500 // interestRate (5%)
        );

        // 债务人尝试还款金额为0
        vm.startPrank(payer);
        vm.expectRevert(Invoice.Invoice__InvalidAmount.selector);
        invoice.repayInvoiceWithNativeToken{value: 0}(batchId);
        vm.stopPrank();
    }

    // 生成EIP 2612签名的辅助函数
    function getPermitSignature(
        address sender,
        address spender,
        uint256 value,
        uint256 deadline,
        uint256 privateKey
    ) internal returns (uint8 v, bytes32 r, bytes32 s) {
        // 初始化nonce
        vm.mockCall(
            rbtAddress,
            abi.encodeWithSelector(IERC20Permit.nonces.selector, sender),
            abi.encode(0)
        );

        // 初始化DOMAIN_SEPARATOR
        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256(
                    "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                ),
                keccak256("RBT"),
                keccak256("1"),
                block.chainid,
                rbtAddress
            )
        );
        vm.mockCall(
            rbtAddress,
            abi.encodeWithSelector(IERC20Permit.DOMAIN_SEPARATOR.selector),
            abi.encode(domainSeparator)
        );

        // 获取nonce
        uint256 nonce = IRBT(rbtAddress).nonces(sender);

        // 计算struct hash
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256(
                    "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
                ),
                sender,
                spender,
                value,
                nonce,
                deadline
            )
        );

        // 计算最终hash
        bytes32 digest = keccak256(
            abi.encodePacked(
                bytes1(0x19),
                bytes1(0x01),
                domainSeparator,
                structHash
            )
        );

        // 确保使用正确的私钥
        require(
            vm.addr(privateKey) == sender,
            "Private key does not match sender address"
        );

        // 生成签名
        (v, r, s) = vm.sign(privateKey, digest);

        // 调整v值
        if (v < 27) {
            v += 27;
        }
    }

    function testWithdrawWithPermit() public {
        // 先创建票据和批次
        test_CreateTokenBatch();

        // 设置RBT余额
        vm.mockCall(
            rbtAddress,
            abi.encodeWithSelector(IERC20Permit.permit.selector),
            abi.encode(true)
        );
        vm.mockCall(
            rbtAddress,
            abi.encodeWithSelector(IRBT.burnToken.selector),
            abi.encode(true)
        );

        // 设置稳定币余额
        vm.mockCall(
            stableToken,
            abi.encodeWithSelector(IERC20.transferFrom.selector),
            abi.encode(true)
        );

        // 设置事件期望
        vm.expectEmit(true, true, true, true);
        emit InvestorWithdrawn(buyer, 1000, stableToken, block.timestamp);

        // 生成签名
        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = getPermitSignature(
            buyer,
            address(invoice),
            1000,
            deadline,
            buyerKey
        );

        // 投资人取款
        vm.startPrank(buyer);
        invoice.withdrawWithPermit(
            1000, // amount
            stableToken, // token
            deadline, // deadline
            v, // v
            r, // r
            s // s
        );
        vm.stopPrank();
    }

    function testWithdrawWithPermitNativeToken() public {
        // 先创建票据和批次
        test_CreateTokenBatch();

        // 设置RBT余额
        vm.mockCall(
            rbtAddress,
            abi.encodeWithSelector(IERC20Permit.permit.selector),
            abi.encode(true)
        );
        vm.mockCall(
            rbtAddress,
            abi.encodeWithSelector(IRBT.burnToken.selector),
            abi.encode(true)
        );

        // 设置Vault余额
        vm.deal(address(vault), 1000);

        // 设置事件期望
        vm.expectEmit(true, true, true, true);
        emit InvestorWithdrawn(buyer, 1000, address(0), block.timestamp);

        // 生成签名
        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = getPermitSignature(
            buyer,
            address(invoice),
            1000,
            deadline,
            buyerKey
        );

        // 投资人取款
        vm.startPrank(buyer);
        invoice.withdrawWithPermit(
            1000, // amount
            address(0), // native token
            deadline, // deadline
            v, // v
            r, // r
            s // s
        );
        vm.stopPrank();

        // 验证余额
        assertEq(buyer.balance, 1000);
        assertEq(address(vault).balance, 0);
    }

    function testWithdrawWithPermitRevertsIfAmountZero() public {
        vm.startPrank(buyer);
        vm.expectRevert(Invoice.InvalidAmount.selector);
        invoice.withdrawWithPermit(
            0, // amount
            stableToken, // token
            block.timestamp + 1 hours, // deadline
            27, // v
            bytes32(0), // r
            bytes32(0) // s
        );
        vm.stopPrank();
    }

    function testWithdrawWithPermitRevertsIfInvalidInvestor() public {
        vm.startPrank(address(0));
        vm.expectRevert(Invoice.InvalidInvestor.selector);
        invoice.withdrawWithPermit(
            1000, // amount
            stableToken, // token
            block.timestamp + 1 hours, // deadline
            27, // v
            bytes32(0), // r
            bytes32(0) // s
        );
        vm.stopPrank();
    }

    function testWithdrawWithPermitRevertsIfSignatureExpired() public {
        vm.startPrank(buyer);
        vm.expectRevert(Invoice.SignatureExpired.selector);
        invoice.withdrawWithPermit(
            1000, // amount
            stableToken, // token
            block.timestamp - 1, // expired deadline
            27, // v
            bytes32(0), // r
            bytes32(0) // s
        );
        vm.stopPrank();
    }

    function testWithdraw() public {
        // 先创建票据和批次
        test_CreateTokenBatch();

        // 设置RBT余额
        vm.mockCall(
            rbtAddress,
            abi.encodeWithSelector(IRBT.burnToken.selector),
            abi.encode(true)
        );

        // 设置稳定币余额
        vm.mockCall(
            stableToken,
            abi.encodeWithSelector(IERC20.transferFrom.selector),
            abi.encode(true)
        );

        // 设置事件期望
        vm.expectEmit(true, true, true, true);
        emit InvestorWithdrawn(buyer, 1000, stableToken, block.timestamp);

        // 投资人取款
        vm.startPrank(buyer);
        invoice.withdraw(1000, stableToken);
        vm.stopPrank();
    }

    function testWithdrawNativeToken() public {
        // 先创建票据和批次
        test_CreateTokenBatch();

        // 设置RBT余额
        vm.mockCall(
            rbtAddress,
            abi.encodeWithSelector(IRBT.burnToken.selector),
            abi.encode(true)
        );

        // 设置Vault余额
        vm.deal(address(vault), 1000);

        // 设置事件期望
        vm.expectEmit(true, true, true, true);
        emit InvestorWithdrawn(buyer, 1000, address(0), block.timestamp);

        // 投资人取款
        vm.startPrank(buyer);
        invoice.withdraw(1000, address(0));
        vm.stopPrank();

        // 验证余额
        assertEq(buyer.balance, 1000);
        assertEq(address(vault).balance, 0);
    }

    function testWithdrawRevertsIfAmountZero() public {
        vm.startPrank(buyer);
        vm.expectRevert(Invoice.InvalidAmount.selector);
        invoice.withdraw(0, stableToken);
        vm.stopPrank();
    }

    function testWithdrawRevertsIfInvalidInvestor() public {
        vm.startPrank(address(0));
        vm.expectRevert(Invoice.InvalidInvestor.selector);
        invoice.withdraw(1000, stableToken);
        vm.stopPrank();
    }
}
