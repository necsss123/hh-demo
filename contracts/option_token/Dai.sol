// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// 发行Dai用来购买标的资产ETH
contract Dai is ERC20 {
    constructor() ERC20("Dai", "Dai") {
        _mint(msg.sender, 10000000e18);
    }
}
