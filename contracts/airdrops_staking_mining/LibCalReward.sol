// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library CalculatingRewards {
    function getPendingRewards(
        uint256 _amount,
        uint256 _accERC20PerShare,
        uint256 _rewardDebt
    ) internal pure returns (uint256) {
        return (_amount * _accERC20PerShare) / 1e36 - _rewardDebt;
    }

    function updateRewardDebt(
        uint256 _amount,
        uint256 _accERC20PerShare
    ) internal pure returns (uint256) {
        // 为了保持用户奖励计算的连续性，如果不这么做，新增的质押部分奖励会被错误计算为已领取，导致用户领取的奖励不足
        return (_amount * _accERC20PerShare) / 1e36;
    }

    function updateAccERC20PerShare(
        uint256 oldAccERC20PerShare,
        uint256 totalAmountOfRewardsDuringTheDuration,
        uint256 amountOfStakeInThePool
    ) internal pure returns (uint256) {
        return
            oldAccERC20PerShare +
            (totalAmountOfRewardsDuringTheDuration * 1e36) /
            amountOfStakeInThePool;
    }
}
