// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IRBT {
    function mintToken(address to, uint256 amount) external;

    function burnToken(address from, uint256 amount) external;

    function nonces(address owner) external view returns (uint256);

    function DOMAIN_SEPARATOR() external view returns (bytes32);
}
