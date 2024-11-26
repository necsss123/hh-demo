// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@chainlink/contracts/node_modules/@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@chainlink/contracts/node_modules/@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@chainlink/contracts/node_modules/@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "./sale/SalesFactory.sol";
import "./LibCalReward.sol";

contract StakingMiningV2 is OwnableUpgradeable {
    using SafeERC20 for IERC20;

    IERC20 private erc20;
    uint256 private rewardPerSecond;
    uint256 private startTimestamp;
    SalesFactory private salesFactory;
    uint256 private endTimestamp;

    /* Functions */
    function init(
        IERC20 _erc20,
        uint256 _rewardPerSecond,
        uint256 _startTimestamp,
        address _salesFactory
    ) public reinitializer(2) {
        __Ownable_init();
        erc20 = _erc20;
        rewardPerSecond = _rewardPerSecond;
        startTimestamp = _startTimestamp;
        endTimestamp = _startTimestamp;
        salesFactory = SalesFactory(_salesFactory);
    }

    function version() external pure returns (uint256) {
        return 2;
    }
}
