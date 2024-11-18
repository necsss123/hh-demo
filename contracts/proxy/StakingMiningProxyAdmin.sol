// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

contract StakingMiningProxyAdmin is ProxyAdmin {
    constructor(address /* owner */) ProxyAdmin() {}
}
