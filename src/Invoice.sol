// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// Vault 接口
interface IVault {
    function deposit(address token, uint256 amount) external;
}

// RBT Token 接口
interface IRBT {
    function mintToken(address to, uint256 amount) external;
}

/**
 * @title Invoice
 * @dev 票据管理智能合约 (UUPS可升级版本)
 */
contract Invoice is
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable
{
    using SafeERC20 for IERC20;

    // 合约地址
    address public vaultAddress;
    address public rbtAddress;

    // 票据结构
    struct InvoiceData {
        string invoiceNumber; // 票据编号
        address payee; // 债权人地址
        address payer; // 债务人地址
        uint256 amount; // 金额
        string ipfsHash; // 票据图片IPFS哈希
        string contractHash; // 合同图片IPFS哈希
        uint256 timestamp; // 登记日期
        uint256 dueDate; // 到期日
        string tokenBatch; // token批次编码
        bool isCleared; // 是否已清算
        bool isValid; // 是否有效
    }

    // 票据映射: 票据编号 => 票据数据
    mapping(string => InvoiceData) public invoices;

    // 地址对应的票据编号数组
    mapping(address => string[]) public payeeInvoices;
    // 存储债务人的所有票据
    mapping(address => string[]) private payerInvoices;

    // 票据打包批次结构
    struct InvoiceTokenBatch {
        string batchId; // 批次ID
        address payee; // 债权人地址
        address payer; // 债务人地址
        address stableToken; // 还款稳定币地址
        uint256 minTerm; // 最短期限(月)
        uint256 maxTerm; // 最长期限(月)
        uint256 interestRate; // 年化利率
        uint256 totalAmount; // 发行总额
        uint256 issueDate; // 发行日期
        bool isSigned; // 是否已签名
        bool isIssued; // 是否已发行
        string[] invoiceNumbers; // 包含的票据编号
    }

    // 批次映射
    mapping(string => InvoiceTokenBatch) public tokenBatches;
    // 用户地址 => 批次ID数组
    mapping(address => string[]) public userBatches;

    // 版本号
    uint256 public version;

    // 事件
    event InvoiceCreated(
        string indexed invoiceNumber,
        address indexed payee,
        address indexed payer,
        uint256 amount,
        string ipfsHash,
        string contractHash,
        uint256 dueDate,
        uint256 timestamp
    );

    event InvoiceInvalidated(string indexed invoiceNumber);
    event ContractUpgraded(uint256 version);
    event TokenBatchCreated(
        string indexed batchId,
        address indexed payee,
        address indexed payer,
        uint256 totalAmount,
        uint256 minTerm,
        uint256 maxTerm,
        uint256 interestRate
    );
    event TokenBatchIssued(string indexed batchId);
    event SharePurchased(
        string indexed batchId,
        address indexed buyer,
        uint256 amount,
        uint256 timestamp
    );

    // 错误
    error Invoice__InvalidInvoiceNumber();
    error Invoice__InvoiceAlreadyExists();
    error Invoice__InvoiceNotFound();
    error Invoice__Unauthorized();
    error Invoice__InvalidAmount();
    error Invoice__InvalidDueDate();
    error Invoice__EmptyBatch();
    error Invoice__InvalidBatchId();
    error Invoice__BatchAlreadyExists();
    error Invoice__BatchNotFound();
    error Invoice__InvalidTerm();
    error Invoice__InvalidInterestRate();
    error Invoice__InvalidInvoices();
    error Invoice__UnauthorizedPayer();
    error Invoice__BatchAlreadyIssued();
    error Invoice__InvalidVaultAddress();
    error Invoice__InvalidRBTAddress();
    error Invoice__BatchNotIssued();
    error Invoice__InsufficientBalance();
    error Invoice__TransferFailed();

    // 查询结果结构
    struct QueryResult {
        InvoiceData[] invoices;
        uint256 total;
    }

    // 查询参数结构
    struct QueryParams {
        string batchId; // 批次ID
        address payer; // 债务人地址
        address payee; // 债权人地址
        string invoiceNumber; // 票据编号
        bool checkValid; // 是否检查有效性
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev 初始化函数，替代constructor
     * @param _vaultAddress Vault 合约地址
     * @param _rbtAddress RBT Token 合约地址
     */
    function initialize(
        address _vaultAddress,
        address _rbtAddress
    ) public initializer {
        if (_vaultAddress == address(0)) revert Invoice__InvalidVaultAddress();
        if (_rbtAddress == address(0)) revert Invoice__InvalidRBTAddress();

        __Ownable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        __UUPSUpgradeable_init();

        vaultAddress = _vaultAddress;
        rbtAddress = _rbtAddress;
        version = 1;
    }

    /**
     * @dev 批量创建票据
     * @param _invoices 票据数据数组
     */
    function batchCreateInvoices(
        InvoiceData[] calldata _invoices
    ) external whenNotPaused nonReentrant {
        uint256 length = _invoices.length;
        if (length == 0) revert Invoice__EmptyBatch();

        for (uint256 i = 0; i < length; i++) {
            InvoiceData memory invoice = _invoices[i];

            // 验证输入
            if (bytes(invoice.invoiceNumber).length == 0)
                revert Invoice__InvalidInvoiceNumber();
            if (invoice.amount == 0) revert Invoice__InvalidAmount();
            if (invoices[invoice.invoiceNumber].isValid)
                revert Invoice__InvoiceAlreadyExists();
            if (invoice.dueDate <= block.timestamp)
                revert Invoice__InvalidDueDate();

            // 设置时间戳和有效性
            invoice.timestamp = block.timestamp;
            invoice.isValid = true;
            invoice.isCleared = false; // 默认未清算

            // 存储票据
            invoices[invoice.invoiceNumber] = invoice;
            payeeInvoices[invoice.payee].push(invoice.invoiceNumber);
            payerInvoices[invoice.payer].push(invoice.invoiceNumber);

            // 触发事件
            emit InvoiceCreated(
                invoice.invoiceNumber,
                invoice.payee,
                invoice.payer,
                invoice.amount,
                invoice.ipfsHash,
                invoice.contractHash,
                invoice.dueDate,
                invoice.timestamp
            );
        }
    }

    /**
     * @dev 创建票据打包批次
     * @param _batchId 批次ID
     * @param _invoiceNumbers 票据编号数组
     * @param _stableToken 稳定币地址
     * @param _minTerm 最短期限(月)
     * @param _maxTerm 最长期限(月)
     * @param _interestRate 年化利率
     */
    function createTokenBatch(
        string calldata _batchId,
        string[] calldata _invoiceNumbers,
        address _stableToken,
        uint256 _minTerm,
        uint256 _maxTerm,
        uint256 _interestRate
    ) external whenNotPaused nonReentrant {
        if (bytes(_batchId).length == 0) revert Invoice__InvalidBatchId();
        if (tokenBatches[_batchId].isSigned)
            revert Invoice__BatchAlreadyExists();
        if (_minTerm == 0 || _maxTerm == 0 || _minTerm > _maxTerm)
            revert Invoice__InvalidTerm();
        if (_interestRate == 0) revert Invoice__InvalidInterestRate();
        if (_invoiceNumbers.length == 0) revert Invoice__InvalidInvoices();

        uint256 totalAmount = 0;
        address payee = address(0);
        address payer = address(0);

        // 验证所有票据并计算总额
        for (uint256 i = 0; i < _invoiceNumbers.length; i++) {
            InvoiceData memory invoice = invoices[_invoiceNumbers[i]];
            if (!invoice.isValid) revert Invoice__InvalidInvoices();

            // 验证所有票据的债权人和债务人是否相同
            if (i == 0) {
                payee = invoice.payee;
                payer = invoice.payer;
            } else {
                if (invoice.payee != payee || invoice.payer != payer) {
                    revert Invoice__InvalidInvoices();
                }
            }

            totalAmount += invoice.amount;
        }

        // 创建批次
        InvoiceTokenBatch memory batch = InvoiceTokenBatch({
            batchId: _batchId,
            payee: payee,
            payer: payer,
            stableToken: _stableToken,
            minTerm: _minTerm,
            maxTerm: _maxTerm,
            interestRate: _interestRate,
            totalAmount: totalAmount,
            issueDate: block.timestamp,
            isSigned: true, // 默认已授权
            isIssued: false,
            invoiceNumbers: _invoiceNumbers
        });

        tokenBatches[_batchId] = batch;
        userBatches[payee].push(_batchId);

        emit TokenBatchCreated(
            _batchId,
            payee,
            payer,
            totalAmount,
            _minTerm,
            _maxTerm,
            _interestRate
        );
    }

    /**
     * @dev 确认发行票据打包批次
     * @param _batchId 批次ID
     */
    function confirmTokenBatchIssue(
        string calldata _batchId
    ) external whenNotPaused nonReentrant {
        InvoiceTokenBatch storage batch = tokenBatches[_batchId];
        if (!batch.isSigned) revert Invoice__BatchNotFound();
        if (batch.isIssued) revert Invoice__BatchAlreadyIssued();
        if (msg.sender != batch.payer) revert Invoice__UnauthorizedPayer();

        batch.isIssued = true;
        emit TokenBatchIssued(_batchId);
    }

    /**
     * @dev 购买份额
     * @param _batchId 批次ID
     * @param _amount 购买数量
     */
    function purchaseShares(
        string calldata _batchId,
        uint256 _amount
    ) external whenNotPaused nonReentrant {
        InvoiceTokenBatch memory batch = tokenBatches[_batchId];

        // 验证批次状态
        if (!batch.isIssued) revert Invoice__BatchNotIssued();

        // 获取稳定币合约
        IERC20 stableToken = IERC20(batch.stableToken);

        // 验证用户余额
        if (stableToken.balanceOf(msg.sender) < _amount) {
            revert Invoice__InsufficientBalance();
        }

        // 计算分配金额
        uint256 payeeAmount = _amount / 2;
        uint256 vaultAmount = _amount - payeeAmount;

        // 转移稳定币
        stableToken.safeTransferFrom(msg.sender, batch.payee, payeeAmount);
        stableToken.safeTransferFrom(msg.sender, vaultAddress, vaultAmount);

        // 铸造 RBT Token
        IRBT(rbtAddress).mintToken(msg.sender, _amount);

        emit SharePurchased(_batchId, msg.sender, _amount, block.timestamp);
    }

    /**
     * @dev 获取批次信息
     * @param _batchId 批次ID
     */
    function getTokenBatch(
        string calldata _batchId
    ) external view returns (InvoiceTokenBatch memory) {
        return tokenBatches[_batchId];
    }

    /**
     * @dev 获取用户的所有批次ID
     * @param _user 用户地址
     */
    function getUserBatches(
        address _user
    ) external view returns (string[] memory) {
        return userBatches[_user];
    }

    /**
     * @dev 获取票据信息
     * @param _invoiceNumber 票据编号
     * @param _checkValid 是否检查有效性
     */
    function getInvoice(
        string calldata _invoiceNumber,
        bool _checkValid
    ) external view returns (InvoiceData memory) {
        InvoiceData memory invoice = invoices[_invoiceNumber];
        if (_checkValid && !invoice.isValid) revert Invoice__InvoiceNotFound();
        return invoice;
    }

    /**
     * @dev 获取票据信息（向后兼容）
     * @param _invoiceNumber 票据编号
     */
    function getInvoice(
        string calldata _invoiceNumber
    ) external view returns (InvoiceData memory) {
        return this.getInvoice(_invoiceNumber, true);
    }

    /**
     * @dev 获取用户的所有票据编号
     * @param _user 用户地址
     */
    function getPayeeInvoices(
        address _user
    ) external view returns (string[] memory) {
        return payeeInvoices[_user];
    }

    /**
     * @dev 作废票据
     * @param _invoiceNumber 票据编号
     */
    function invalidateInvoice(
        string calldata _invoiceNumber
    ) external onlyOwner {
        if (!invoices[_invoiceNumber].isValid)
            revert Invoice__InvoiceNotFound();
        invoices[_invoiceNumber].isValid = false;
        emit InvoiceInvalidated(_invoiceNumber);
    }

    /**
     * @dev 暂停合约
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev 恢复合约
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @dev 实现UUPS的_authorizeUpgrade函数
     */
    function _authorizeUpgrade(
        address /* newImplementation */
    ) internal override onlyOwner {
        version += 1;
        emit ContractUpgraded(version);
    }

    /**
     * @dev 查询票据
     * @param params 查询参数
     */
    function queryInvoices(
        QueryParams calldata params
    ) external view returns (QueryResult memory) {
        // 如果指定了票据编号，直接返回该票据
        if (bytes(params.invoiceNumber).length > 0) {
            InvoiceData memory invoice = invoices[params.invoiceNumber];
            if (invoice.isValid || !params.checkValid) {
                InvoiceData[] memory result = new InvoiceData[](1);
                result[0] = invoice;
                return QueryResult({invoices: result, total: 1});
            }
            return QueryResult({invoices: new InvoiceData[](0), total: 0});
        }

        // 如果指定了批次ID，返回该批次的所有票据
        if (bytes(params.batchId).length > 0) {
            InvoiceTokenBatch memory batch = tokenBatches[params.batchId];
            InvoiceData[] memory result = new InvoiceData[](
                batch.invoiceNumbers.length
            );
            uint256 count = 0;
            for (uint256 i = 0; i < batch.invoiceNumbers.length; i++) {
                InvoiceData memory invoice = invoices[batch.invoiceNumbers[i]];
                if (invoice.isValid || !params.checkValid) {
                    result[count] = invoice;
                    count++;
                }
            }
            InvoiceData[] memory trimmedResult = new InvoiceData[](count);
            for (uint256 i = 0; i < count; i++) {
                trimmedResult[i] = result[i];
            }
            return QueryResult({invoices: trimmedResult, total: count});
        }

        // 如果指定了债权人或债务人，返回对应的票据
        if (params.payee != address(0) || params.payer != address(0)) {
            string[] storage invoiceNumbers;
            if (params.payee != address(0)) {
                invoiceNumbers = payeeInvoices[params.payee];
            } else {
                invoiceNumbers = payerInvoices[params.payer];
            }

            InvoiceData[] memory result = new InvoiceData[](
                invoiceNumbers.length
            );
            uint256 count = 0;
            for (uint256 i = 0; i < invoiceNumbers.length; i++) {
                InvoiceData memory invoice = invoices[invoiceNumbers[i]];
                if (invoice.isValid || !params.checkValid) {
                    result[count] = invoice;
                    count++;
                }
            }
            InvoiceData[] memory trimmedResult = new InvoiceData[](count);
            for (uint256 i = 0; i < count; i++) {
                trimmedResult[i] = result[i];
            }
            return QueryResult({invoices: trimmedResult, total: count});
        }

        // 如果没有指定任何条件，返回空结果
        return QueryResult({invoices: new InvoiceData[](0), total: 0});
    }
}
