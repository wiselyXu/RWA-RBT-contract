// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IVault {
    function deposit(address token, uint256 amount) external payable;

    function withdraw(address token, address to, uint256 amount) external;
}
