// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./LibCalReward.sol";

error StakingMining__MiningIsOver();
error StakingMining__AmountNotEnough();

contract StakingMining is Ownable {
    using SafeERC20 for IERC20;

    struct User {
        uint256 amount; // 用户提供的LP token数量
        uint256 rewardDebt; // 用户已领取的奖励

        //  这里进行一些复杂的计算，基本上，在任何时间点，用户有权获得但尚未分配的 ERC20 奖励为：
        //  pendingReward = (user.amount * pool.accERC20PerShare) - user.rewardDebt

        // 每当用户将 LP 代币存入或提取到池中时，会发生以下情况：
        // 1. 该池的accERC20PerShare（lastRewardBlock）更新
        // 2. 用户将收到待领取奖励
        // 3. 用户存入的LP token amount更新
        // 4. 用户已获得奖励 rewardDebt 更新
    }

    struct Pool {
        IERC20 lpToken;
        uint256 allocPoint; // 该池子的分配点数. 和该池子每单位时间分配的 ERC20 数量
        uint256 lastRewardTimestamp; // 最后一次分发奖励的时间
        uint256 accERC20PerShare; // 每个LP token的累积奖励 ，乘上1e36.
        uint256 totalDeposits; // 该池子质押的LP token总量
    }

    /* State Variables */
    IERC20 private immutable i_erc20; // 奖励用ERC20
    uint256 private immutable i_rewardPerSecond; // 每秒奖励的ERC20代币
    uint256 private immutable i_startTimestamp; // 质押奖励开始时间

    uint256 private s_paidOut; // 作为奖励支付的 ERC20 总额
    uint256 private s_totalRewards; // 新增总奖励
    Pool[] private s_pool;
    mapping(uint256 => mapping(address => User)) private s_user; // poolId => (userAccount => User)
    uint256 private s_totalAllocPoint; // 总分配点数，即所有池中所有分配点数的总和
    uint256 private s_endTimestamp; // 质押奖励结束时间

    /* Events */
    event Deposit(address indexed user, uint256 indexed poolId, uint256 amount);
    event Withdraw(
        address indexed user,
        uint256 indexed poolId,
        uint256 amount
    );
    event EmergencyWithdraw(
        address indexed user,
        uint256 indexed poolId,
        uint256 amount
    );

    /* Functions */
    constructor(
        IERC20 _erc20,
        uint256 _rewardPerSecond,
        uint256 _startTimestamp
    ) {
        i_erc20 = _erc20;
        i_rewardPerSecond = _rewardPerSecond;
        i_startTimestamp = _startTimestamp;
        s_endTimestamp = _startTimestamp;
    }

    // 资助，延长挖矿活动的持续时间
    function fund(uint256 _amount) public {
        if (block.timestamp >= s_endTimestamp) {
            revert StakingMining__MiningIsOver();
        }

        i_erc20.safeTransferFrom(address(msg.sender), address(this), _amount);
        s_endTimestamp += _amount / i_rewardPerSecond;
        s_totalRewards = s_totalRewards + _amount;
    }

    // 添加新的LP token池。只有合约所有者才能调用
    // 请勿多次添加相同的LP代币。如果这样做，奖励会变得混乱
    function add(
        uint256 _allocPoint,
        IERC20 _lpToken,
        bool _withUpdate
    ) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardTimestamp = block.timestamp > i_startTimestamp
            ? block.timestamp
            : i_startTimestamp;

        s_totalAllocPoint = s_totalAllocPoint + _allocPoint;

        s_pool.push(
            Pool({
                lpToken: _lpToken,
                allocPoint: _allocPoint,
                lastRewardTimestamp: lastRewardTimestamp,
                accERC20PerShare: 0,
                totalDeposits: 0
            })
        );
    }

    // 更新某个池子的 allocPoint
    function set(
        uint256 _poolId,
        uint256 _allocPoint,
        bool _withUpdate
    ) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }

        s_totalAllocPoint =
            s_totalAllocPoint -
            s_pool[_poolId].allocPoint +
            _allocPoint;
        s_pool[_poolId].allocPoint = _allocPoint;
    }

    //批量更新所有池子的奖励变量，可能造成大量gas支出！
    function massUpdatePools() public {
        uint256 length = s_pool.length;
        for (uint256 poolId = 0; poolId < length; ++poolId) {
            updatePool(poolId);
        }
    }

    // 更新给定池的奖励变量以保持最新
    function updatePool(uint256 _pid) public {
        Pool storage poolInfo = s_pool[_pid];

        uint256 lastTimestamp = block.timestamp < s_endTimestamp
            ? block.timestamp
            : s_endTimestamp;

        if (lastTimestamp <= poolInfo.lastRewardTimestamp) {
            return;
        }
        uint256 lpSupply = poolInfo.totalDeposits;

        if (lpSupply == 0) {
            poolInfo.lastRewardTimestamp = lastTimestamp;
            return;
        }

        uint256 stakingDuration = lastTimestamp - poolInfo.lastRewardTimestamp;
        uint256 erc20Reward = (stakingDuration * i_rewardPerSecond) *
            (poolInfo.allocPoint / s_totalAllocPoint);

        poolInfo.accERC20PerShare = CalculatingRewards.updateAccERC20PerShare(
            poolInfo.accERC20PerShare,
            erc20Reward,
            lpSupply
        );

        poolInfo.lastRewardTimestamp = block.timestamp;
    }

    // 向池子中存入LP token
    function deposit(uint256 _poolId, uint256 _amount) public {
        Pool storage poolInfo = s_pool[_poolId];
        User storage userInfo = s_user[_poolId][msg.sender];

        updatePool(_poolId);

        if (userInfo.amount > 0) {
            uint256 pendingRewards = CalculatingRewards.getPendingRewards(
                userInfo.amount,
                poolInfo.accERC20PerShare,
                userInfo.rewardDebt
            );

            i_erc20.transfer(msg.sender, pendingRewards);

            s_paidOut += pendingRewards;
        }

        poolInfo.lpToken.safeTransferFrom(
            address(msg.sender),
            address(this),
            _amount
        );
        poolInfo.totalDeposits = poolInfo.totalDeposits + _amount;

        userInfo.amount = userInfo.amount + _amount;

        userInfo.rewardDebt = CalculatingRewards.updateRewardDebt(
            userInfo.amount,
            poolInfo.accERC20PerShare
        );

        emit Deposit(msg.sender, _poolId, _amount);
    }

    // 撤回池子中的质押和奖励，包含2个功能，收取奖励，撤回质押
    function withdraw(uint256 _poolId, uint256 _amount) public {
        Pool storage poolInfo = s_pool[_poolId];
        User storage userInfo = s_user[_poolId][msg.sender];

        if (userInfo.amount < _amount) {
            revert StakingMining__AmountNotEnough();
        }

        updatePool(_poolId);

        uint256 pendingRewards = CalculatingRewards.getPendingRewards(
            userInfo.amount,
            poolInfo.accERC20PerShare,
            userInfo.rewardDebt
        );

        i_erc20.transfer(msg.sender, pendingRewards);

        s_paidOut += pendingRewards;

        userInfo.amount = userInfo.amount - _amount;

        userInfo.rewardDebt = CalculatingRewards.updateRewardDebt(
            userInfo.amount,
            poolInfo.accERC20PerShare
        );

        // 撤回流动性
        poolInfo.lpToken.safeTransfer(address(msg.sender), _amount);
        poolInfo.totalDeposits = poolInfo.totalDeposits - _amount;

        emit Withdraw(msg.sender, _poolId, _amount);
    }

    // 紧急提款不考虑奖励
    function emergencyWithdraw(uint256 _poolId) public {
        Pool storage poolInfo = s_pool[_poolId];
        User storage userInfo = s_user[_poolId][msg.sender];
        poolInfo.lpToken.safeTransfer(address(msg.sender), userInfo.amount);
        poolInfo.totalDeposits = poolInfo.totalDeposits - userInfo.amount;
        emit EmergencyWithdraw(msg.sender, _poolId, userInfo.amount);
        userInfo.amount = 0;
        userInfo.rewardDebt = 0;
    }

    function version() external pure returns (uint256) {
        return 1;
    }

    function getRewardPerSec() external view returns (uint256) {
        return i_rewardPerSecond;
    }

    function getRewardToken() external view returns (IERC20) {
        return i_erc20;
    }

    function getTotalRewards() external view returns (uint256) {
        return s_totalRewards;
    }

    function getTotalAllocPoint() external view returns (uint256) {
        return s_totalAllocPoint;
    }

    function getStartTimestamp() external view returns (uint256) {
        return i_startTimestamp;
    }

    function getEndTimestamp() external view returns (uint256) {
        return s_endTimestamp;
    }

    function getPoolInfo(uint256 poolId) external view returns (Pool memory) {
        return s_pool[poolId];
    }

    // Lp池子数量
    function poolLength() external view returns (uint256) {
        return s_pool.length;
    }

    function deposited(
        uint256 _poolId,
        address _user
    ) external view returns (uint256) {
        User storage userInfo = s_user[_poolId][_user];
        return userInfo.amount;
    }

    // 查看用户待领取的奖励
    function pendingReward(
        uint256 _poolId,
        address _user
    ) external view returns (uint256) {
        Pool storage poolInfo = s_pool[_poolId];
        User storage userInfo = s_user[_poolId][_user];

        uint256 accERC20PerShare = poolInfo.accERC20PerShare;

        uint256 lpSupply = poolInfo.totalDeposits;

        if (block.timestamp > poolInfo.lastRewardTimestamp && lpSupply != 0) {
            uint256 lastTimestamp = block.timestamp < s_endTimestamp
                ? block.timestamp
                : s_endTimestamp;
            uint256 timestampToCompare = poolInfo.lastRewardTimestamp <
                s_endTimestamp
                ? poolInfo.lastRewardTimestamp
                : s_endTimestamp;
            uint256 stakingDuration = lastTimestamp - timestampToCompare; // 上次领取奖励时间与现在时间的间隔
            uint256 erc20Reward = (stakingDuration * i_rewardPerSecond) * // 该pool在这段时间内产生的奖励
                (poolInfo.allocPoint / s_totalAllocPoint);

            // 这里只计算当前user可能的奖励，并不会池子状态，也就是pool.accERC20PerShare进行修改
            accERC20PerShare = CalculatingRewards.updateAccERC20PerShare(
                accERC20PerShare,
                erc20Reward,
                lpSupply
            );
        }

        uint256 pendingRewards = CalculatingRewards.getPendingRewards(
            userInfo.amount,
            accERC20PerShare,
            userInfo.rewardDebt
        );

        return pendingRewards;
    }

    // 查看所有质押产生的未领取奖励
    function totalPending() external view returns (uint256) {
        if (block.timestamp <= i_startTimestamp) {
            return 0;
        }

        uint256 lastTimestamp = block.timestamp < s_endTimestamp
            ? block.timestamp
            : s_endTimestamp;

        uint256 stakingDuration = lastTimestamp - i_startTimestamp; // 质押活动的持续时间
        return i_rewardPerSecond * stakingDuration - s_paidOut;
    }
}
