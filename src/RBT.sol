// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Token} from "@erc3643/contracts/token/Token.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title RBT
 * @dev 应收账款支持代币 (Receivable Backed Token)
 */
contract RBT is OwnableUpgradeable, UUPSUpgradeable, Token {
    // 合约地址
    address public invoiceAddress;

    // 事件
    event TokensMinted(address indexed to, uint256 amount);
    event TokensBurned(address indexed from, uint256 amount);
    event InvoiceAddressSet(address indexed invoice);

    // 错误
    error RBT__InvalidAmount();
    error RBT__Unauthorized();
    error RBT__InvalidInvoiceAddress();

    // 修饰器
    modifier onlyInvoice() {
        if (msg.sender != invoiceAddress) revert RBT__Unauthorized();
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev 初始化函数
     */
    function initialize() public initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();
    }

    /**
     * @dev 设置 Invoice 合约地址
     * @param _invoiceAddress Invoice 合约地址
     */
    function setInvoiceAddress(address _invoiceAddress) external onlyOwner {
        if (_invoiceAddress == address(0)) revert RBT__InvalidInvoiceAddress();
        invoiceAddress = _invoiceAddress;
        emit InvoiceAddressSet(_invoiceAddress);
    }

    /**
     * @dev 铸造代币
     * @param to 接收地址
     * @param amount 数量
     */
    function mintToken(
        address to,
        uint256 amount
    ) public onlyInvoice whenNotPaused {
        if (amount == 0) revert RBT__InvalidAmount();
        _mint(to, amount);
        emit TokensMinted(to, amount);
    }

    /**
     * @dev 销毁代币
     * @param from 来源地址
     * @param amount 数量
     */
    function burnToken(
        address from,
        uint256 amount
    ) public onlyInvoice whenNotPaused {
        if (amount == 0) revert RBT__InvalidAmount();
        _burn(from, amount);
        emit TokensBurned(from, amount);
    }

    /**
     * @dev 实现UUPS的_authorizeUpgrade函数
     */
    function _authorizeUpgrade(
        address /* newImplementation */
    ) internal override onlyOwner {
        // 版本升级逻辑
    }
}
