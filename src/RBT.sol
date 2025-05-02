// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Token} from "@erc3643/contracts/token/Token.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/draft-IERC20Permit.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

/**
 * @title RBT
 * @dev 应收账款支持代币 (Receivable Backed Token)
 */
contract RBT is
    OwnableUpgradeable,
    UUPSUpgradeable,
    Token,
    IERC20Permit,
    EIP712
{
    using ECDSA for bytes32;

    // 合约地址
    address public invoiceAddress;

    // EIP2612相关
    mapping(address => uint256) private _nonces;
    bytes32 private constant _PERMIT_TYPEHASH =
        keccak256(
            "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
        );

    // 事件
    event TokensMinted(address indexed to, uint256 amount);
    event TokensBurned(address indexed from, uint256 amount);
    event InvoiceAddressSet(address indexed invoice);
    event DebugInfo(
        address owner,
        address spender,
        uint256 value,
        uint256 nonce,
        uint256 deadline,
        bytes32 structHash,
        bytes32 hash,
        address signer
    );

    // 错误
    error RBT__InvalidAmount();
    error RBT__Unauthorized();
    error RBT__InvalidInvoiceAddress();
    error RBT__InvalidSignature();
    error RBT__ExpiredSignature();

    // 修饰器
    modifier onlyInvoice() {
        if (msg.sender != invoiceAddress) revert RBT__Unauthorized();
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() EIP712("RBT", "1") {
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
     * @dev 实现EIP2612的permit函数
     */
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public virtual override {
        if (block.timestamp > deadline) revert RBT__ExpiredSignature();

        bytes32 structHash = keccak256(
            abi.encode(
                _PERMIT_TYPEHASH,
                owner,
                spender,
                value,
                _useNonce(owner),
                deadline
            )
        );

        bytes32 hash = _hashTypedDataV4(structHash);

        address signer = hash.recover(v, r, s);

        // 调试信息
        emit DebugInfo(
            owner,
            spender,
            value,
            _nonces[owner],
            deadline,
            structHash,
            hash,
            signer
        );

        if (signer != owner) revert RBT__InvalidSignature();

        _approve(owner, spender, value);
    }

    /**
     * @dev 获取nonce
     */
    function nonces(
        address owner
    ) public view virtual override returns (uint256) {
        return _nonces[owner];
    }

    /**
     * @dev 获取domain separator
     */
    function DOMAIN_SEPARATOR() external view override returns (bytes32) {
        return _domainSeparatorV4();
    }

    /**
     * @dev 使用nonce
     */
    function _useNonce(
        address owner
    ) internal virtual returns (uint256 current) {
        current = _nonces[owner];
        _nonces[owner]++;
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
