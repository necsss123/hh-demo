// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import "@chainlink/contracts/node_modules/@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract IceFrog is ERC20 {
    constructor(uint256 initialSupply) ERC20("IceFrog", "IF") {
        _mint(msg.sender, initialSupply);
    }
}
