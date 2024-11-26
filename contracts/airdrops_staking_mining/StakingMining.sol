// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@chainlink/contracts/node_modules/@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@chainlink/contracts/node_modules/@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@chainlink/contracts/node_modules/@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "./sale/SalesFactory.sol";
import "./LibCalReward.sol";

error StakingMining__MiningIsOver();
error StakingMining__AmountNotEnough();
error StakingMining__SaleNotCreated();
error StakingMining__SalesFactoryNotSet();
error StakingMining__TokenNotUnlocked();

contract StakingMining is OwnableUpgradeable {
    using SafeERC20 for IERC20;

    struct User {
        uint256 amount; // 用户提供的LP token数量
        uint256 rewardDebt; // 用户已领取的奖励
        uint256 tokensUnlockTime; // 限制用户的代币何时可以解锁提取
        address[] salesRegistered; // 记录了用户参与过的所有销售活动

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
    IERC20 private erc20; // 奖励用ERC20
    uint256 private rewardPerSecond; // 每秒奖励的ERC20代币
    uint256 private startTimestamp; // 质押奖励开始时间
    SalesFactory private salesFactory;
    uint256 private paidOut; // 作为奖励支付的 ERC20 总额
    uint256 private totalRewards; // 新增总奖励
    Pool[] private poolArr;
    mapping(uint256 => mapping(address => User)) private userMap; // poolId => (userAccount => User)
    uint256 private totalAllocPoint; // 总分配点数，即所有池中所有分配点数的总和
    uint256 private endTimestamp; // 质押奖励结束时间

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

    event CompoundedEarnings(
        address indexed user,
        uint256 indexed pid,
        uint256 amountAdded,
        uint256 totalDeposited
    );

    modifier onlyVerifiedSales() {
        if (!salesFactory.isSaleCreatedThroughFactory(msg.sender)) {
            // 这里是个函数，SalesFactory中只有mapping
            revert StakingMining__SaleNotCreated();
        }
        _;
    }

    /* Functions */
    function init(
        IERC20 _erc20,
        uint256 _rewardPerSecond,
        uint256 _startTimestamp,
        address _salesFactory
    ) public initializer {
        __Ownable_init();
        erc20 = _erc20;
        rewardPerSecond = _rewardPerSecond;
        startTimestamp = _startTimestamp;
        endTimestamp = _startTimestamp;
        salesFactory = SalesFactory(_salesFactory);
    }

    // 资助，延长挖矿活动的持续时间
    function fund(uint256 _amount) public {
        if (block.timestamp >= endTimestamp) {
            revert StakingMining__MiningIsOver();
        }

        erc20.safeTransferFrom(address(msg.sender), address(this), _amount);
        endTimestamp += _amount / rewardPerSecond;
        totalRewards = totalRewards + _amount;
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
        uint256 lastRewardTimestamp = block.timestamp > startTimestamp
            ? block.timestamp
            : startTimestamp;

        totalAllocPoint = totalAllocPoint + _allocPoint;

        poolArr.push(
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

        totalAllocPoint =
            totalAllocPoint -
            poolArr[_poolId].allocPoint +
            _allocPoint;
        poolArr[_poolId].allocPoint = _allocPoint;
    }

    //批量更新所有池子的奖励变量，可能造成大量gas支出！
    function massUpdatePools() public {
        uint256 length = poolArr.length;
        for (uint256 poolId = 0; poolId < length; ++poolId) {
            updatePool(poolId);
        }
    }

    // 更新给定池的奖励变量以保持最新
    function updatePool(uint256 _pid) public {
        Pool storage poolInfo = poolArr[_pid];

        uint256 lastTimestamp = block.timestamp < endTimestamp
            ? block.timestamp
            : endTimestamp;

        if (lastTimestamp <= poolInfo.lastRewardTimestamp) {
            return;
        }
        uint256 lpSupply = poolInfo.totalDeposits;

        if (lpSupply == 0) {
            poolInfo.lastRewardTimestamp = lastTimestamp;
            return;
        }

        uint256 stakingDuration = lastTimestamp - poolInfo.lastRewardTimestamp;
        uint256 erc20Reward = (stakingDuration * rewardPerSecond) *
            (poolInfo.allocPoint / totalAllocPoint);

        poolInfo.accERC20PerShare = CalculatingRewards.updateAccERC20PerShare(
            poolInfo.accERC20PerShare,
            erc20Reward,
            lpSupply
        );

        poolInfo.lastRewardTimestamp = block.timestamp;
    }

    // 向池子中存入LP token
    function deposit(uint256 _poolId, uint256 _amount) public {
        Pool storage poolInfo = poolArr[_poolId];
        User storage userInfo = userMap[_poolId][msg.sender];

        updatePool(_poolId);

        if (userInfo.amount > 0) {
            uint256 pendingRewards = CalculatingRewards.getPendingRewards(
                userInfo.amount,
                poolInfo.accERC20PerShare,
                userInfo.rewardDebt
            );

            erc20.transfer(msg.sender, pendingRewards);

            paidOut += pendingRewards;
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
        Pool storage poolInfo = poolArr[_poolId];
        User storage userInfo = userMap[_poolId][msg.sender];

        if (userInfo.amount < _amount) {
            revert StakingMining__AmountNotEnough();
        }

        updatePool(_poolId);

        uint256 pendingRewards = CalculatingRewards.getPendingRewards(
            userInfo.amount,
            poolInfo.accERC20PerShare,
            userInfo.rewardDebt
        );

        erc20.transfer(msg.sender, pendingRewards);

        paidOut += pendingRewards;

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
        Pool storage poolInfo = poolArr[_poolId];
        User storage userInfo = userMap[_poolId][msg.sender];
        poolInfo.lpToken.safeTransfer(address(msg.sender), userInfo.amount);
        poolInfo.totalDeposits = poolInfo.totalDeposits - userInfo.amount;
        emit EmergencyWithdraw(msg.sender, _poolId, userInfo.amount);
        userInfo.amount = 0;
        userInfo.rewardDebt = 0;
    }

    function compound(uint256 _poolId) public {
        Pool storage poolInfo = poolArr[_poolId];
        User storage userInfo = userMap[_poolId][msg.sender];
        assert(userInfo.amount >= 0);

        updatePool(_poolId);

        uint256 pendingAmount = CalculatingRewards.getPendingRewards(
            userInfo.amount,
            poolInfo.accERC20PerShare,
            userInfo.rewardDebt
        );

        userInfo.amount = userInfo.amount + pendingAmount;

        userInfo.rewardDebt = CalculatingRewards.updateRewardDebt(
            userInfo.amount,
            poolInfo.accERC20PerShare
        );

        poolInfo.totalDeposits = poolInfo.totalDeposits + pendingAmount;
        emit CompoundedEarnings(
            msg.sender,
            _poolId,
            pendingAmount,
            userInfo.amount
        );
    }

    function setSalesFactory(address _salesFactory) external onlyOwner {
        if (_salesFactory == address(0)) {
            revert StakingMining__SalesFactoryNotSet();
        }

        salesFactory = SalesFactory(_salesFactory);
    }

    function setTokensUnlockTime(
        uint256 _poolId,
        address _user,
        uint256 _tokensUnlockTime
    ) external onlyVerifiedSales {
        User storage userInfo = userMap[_poolId][_user];
        // 需要代币处于解锁状态
        if (userInfo.tokensUnlockTime > block.timestamp) {
            revert StakingMining__TokenNotUnlocked();
        }
        userInfo.tokensUnlockTime = _tokensUnlockTime;
        // msg.sender是代币对应的sale合约地址
        userInfo.salesRegistered.push(msg.sender);
    }

    function version() external pure returns (uint256) {
        return 1;
    }

    function getRewardPerSec() external view returns (uint256) {
        return rewardPerSecond;
    }

    function getRewardToken() external view returns (IERC20) {
        return erc20;
    }

    function getTotalRewards() external view returns (uint256) {
        return totalRewards;
    }

    function getTotalAllocPoint() external view returns (uint256) {
        return totalAllocPoint;
    }

    function getStartTimestamp() external view returns (uint256) {
        return startTimestamp;
    }

    function getEndTimestamp() external view returns (uint256) {
        return endTimestamp;
    }

    function getPoolInfo(uint256 poolId) external view returns (Pool memory) {
        return poolArr[poolId];
    }

    function getPendingAndDepositedForUsers(
        address[] memory users,
        uint poolId
    ) external view returns (uint256[] memory, uint256[] memory) {
        uint256[] memory deposits = new uint256[](users.length);
        uint256[] memory earnings = new uint256[](users.length);

        // 获取给定用户的存款和收益
        for (uint i = 0; i < users.length; i++) {
            deposits[i] = getDeposited(poolId, users[i]);
            earnings[i] = getPendingReward(poolId, users[i]);
        }

        return (deposits, earnings);
    }

    // Lp池子数量
    function getPoolNum() external view returns (uint256) {
        return poolArr.length;
    }

    function getDeposited(
        uint256 _poolId,
        address _user
    ) public view returns (uint256) {
        User storage userInfo = userMap[_poolId][_user];
        return userInfo.amount;
    }

    // 查看用户待领取的奖励
    function getPendingReward(
        uint256 _poolId,
        address _user
    ) public view returns (uint256) {
        Pool storage poolInfo = poolArr[_poolId];
        User storage userInfo = userMap[_poolId][_user];

        uint256 accERC20PerShare = poolInfo.accERC20PerShare;

        uint256 lpSupply = poolInfo.totalDeposits;

        if (block.timestamp > poolInfo.lastRewardTimestamp && lpSupply != 0) {
            uint256 lastTimestamp = block.timestamp < endTimestamp
                ? block.timestamp
                : endTimestamp;
            uint256 timestampToCompare = poolInfo.lastRewardTimestamp <
                endTimestamp
                ? poolInfo.lastRewardTimestamp
                : endTimestamp;
            uint256 stakingDuration = lastTimestamp - timestampToCompare; // 上次领取奖励时间与现在时间的间隔
            uint256 erc20Reward = (stakingDuration * rewardPerSecond) * // 该pool在这段时间内产生的奖励
                (poolInfo.allocPoint / totalAllocPoint);

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
    function getTotalPending() external view returns (uint256) {
        if (block.timestamp <= startTimestamp) {
            return 0;
        }

        uint256 lastTimestamp = block.timestamp < endTimestamp
            ? block.timestamp
            : endTimestamp;

        uint256 stakingDuration = lastTimestamp - startTimestamp; // 质押活动的持续时间
        return rewardPerSecond * stakingDuration - paidOut;
    }
}
