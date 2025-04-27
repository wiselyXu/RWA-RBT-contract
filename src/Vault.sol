// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title Vault
 * @dev 保险库合约，用于存放用户的稳定币
 */
contract Vault is OwnableUpgradeable, UUPSUpgradeable {
    using SafeERC20 for IERC20;

    // 事件
    event Deposited(
        address indexed token,
        address indexed from,
        uint256 amount
    );
    event Withdrawn(address indexed token, address indexed to, uint256 amount);

    // 错误
    error Vault__InvalidAmount();
    error Vault__TransferFailed();

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
     * @dev 存入代币
     * @param token 代币地址
     * @param amount 数量
     */
    function deposit(address token, uint256 amount) external {
        if (amount == 0) revert Vault__InvalidAmount();

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        emit Deposited(token, msg.sender, amount);
    }

    /**
     * @dev 提取代币
     * @param token 代币地址
     * @param to 接收地址
     * @param amount 数量
     */
    function withdraw(
        address token,
        address to,
        uint256 amount
    ) external onlyOwner {
        if (amount == 0) revert Vault__InvalidAmount();

        IERC20(token).safeTransfer(to, amount);
        emit Withdrawn(token, to, amount);
    }

    /**
     * @dev 实现UUPS的_authorizeUpgrade函数
     */
    function _authorizeUpgrade(
        address /* newImplementation */
    ) internal override onlyOwner {}
}
