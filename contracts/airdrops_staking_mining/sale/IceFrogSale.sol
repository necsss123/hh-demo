// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./SalesFactory.sol";
import "../StakingMining.sol";
import "@chainlink/contracts/node_modules/@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@chainlink/contracts/node_modules/@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@chainlink/contracts/node_modules/@openzeppelin/contracts/security/ReentrancyGuard.sol";

error IceFrogSale__OnlyCallBySaleOwner();
error IceFrogSale__OnlyCallByAdmin();
error IceFrogSale__InvaildSalesFactoryAddr();
error IceFrogSale__TheLengthsOfBothArrsMustBeZero();
error IceFrogSale__TheLengthsOfTheTwoArrsAreInconsistent();
error IceFrogSale__PleaseCallTheSetSaleParamsFuncFirst();
error IceFrogSale__MaximalShiftIs30Days();
error IceFrogSale__InvalidShiftTimeRange();
error IceFrogSale__ThisFuncCanOnlyBeCalledOnce();
error IceFrogSale__SaleIsAlreadyExisted();
error IceFrogSale__SaleIsNotExisted();
error IceFrogSale__SaleOwnerAddrCanNotBeEmpty();
error IceFrogSale__InvalidInputParams();
error IceFrogSale__CanNotBeLessThan100();
error IceFrogSale__TokenAddrMustBeEmpty();
error IceFrogSale__RegistrationTimeHasBeenSet();
error IceFrogSale__InvalidRegistrationTimeRange();
error IceFrogSale__RegistrationEndNeedsToBeLessThanSaleEnd();
error IceFrogSale__SaleStartTimeHasBeenSet();
error IceFrogSale__SaleStartTimeShouldBeGreaterThanRegEndTime();
error IceFrogSale__SaleStartTimeShouldBeLessThanSaleEndTime();
error IceFrogSale__SaleStartTimeShouldBeGreaterThanCurrentTime();
error IceFrogSale__NonRegistrationTime();
error IceFrogSale__InvalidSignature();
error IceFrogSale__DuplicateRegistrationIsNotAllowed();
error IceFrogSale__InvalidPrice();
error IceFrogSale__SaleAlreadyStarted();
error IceFrogSale__SaleStartTimeShouldBeLessThanEndTime();
error IceFrogSale__InvalidNumOfParticipants();
error IceFrogSale__ExceededTheMaximumAmountOfParticipation();
error IceFrogSale__NotRegisteredForTheSale();
error IceFrogSale__SignatureVerificationFailed();
error IceFrogSale__NotInTheSaleTimeRange();
error IceFrogSale__CanOnlyParticipateInOneSale();
error IceFrogSale__CannotBeCalledByContracts();
error IceFrogSale__InvalidETHAmount();
error IceFrogSale__TokensHaveNotYetBeenUnlocked();
error IceFrogSale__PortionIdIsOutOfUnlockRange();
error IceFrogSale__TokensHaveBeenWithdrawn();
error IceFrogSale__PortionHasNotBeenUnlocked();
error IceFrogSale__TransferFailed();
error IceFrogSale__TheSaleHasNotEndedYet();
error IceFrogSale__CanOnlyWithdrawTheEarningsOnce();
error IceFrogSale__CanOnlyWithdrawTheLeftoverOnce();

contract IceFrogSale is ReentrancyGuard {
    using ECDSA for bytes32;
    using SafeERC20 for IERC20;

    struct Sale {
        IERC20 token; // 正在被出售的代币
        bool isCreated; // 是否创建了对应的Sale
        bool earningsWithdrawn; // 收益是否被提取
        bool leftoverWithdrawn; // 剩余的是否撤回
        //  bool tokensDeposited; // 代币是否存入
        address saleOwner; // 项目方(卖家)地址
        uint256 tokenPriceInETH; // 代币的ETH价格
        uint256 amountOfTokensToSell; // 出售的代币数量
        uint256 totalTokensSold; // 已出售的代币总量
        uint256 totalETHRaised; // 筹集的ETH总额
        uint256 saleStart; // 售卖开始时间
        uint256 saleEnd; // 售卖结束时间
        uint256 tokensUnlockTime; // 代币可被提取时间
        uint256 maxParticipation; // 最大参与金额
    }

    struct Participation {
        uint256 amountBought; // 购买数量
        uint256 amountETHPaid; // 支付的ETH总额
        uint256 timeParticipated; // 参与时间
        bool[] isPortionWithdrawn; // 已提取的部分(按比例)
    }

    struct Registration {
        uint256 registrationTimeStarts; // 注册开始时间
        uint256 registrationTimeEnds; // 注册结束时间
        uint256 numberOfRegistrants; // 注册人数
    }

    StakingMining private immutable i_stakingMining;
    SalesFactory private immutable i_salesFactory;

    Sale public sale;
    Registration public registration;
    uint256 public numberOfParticipants; // 参与购买的投资者数量
    mapping(address => Participation) public userToParticipation; // userAccount -> Participation
    mapping(address => bool) public isRegistered; // userAccount -> 是否注册
    mapping(address => bool) public isParticipated; // userAccount -> 是否参与过

    uint256[] public vestingPortionsUnlockTime; // 存储各阶段解锁时间点
    uint256[] public vestingPercentPerPortion; // 存储各阶段解锁的代币比例(百分比)
    uint256 public portionVestingPrecision; // 解锁比例的精度，用于确保解锁比例的数值能支持小数
    uint256 public maxVestingTimeShift; // 允许的最大解锁时间调整范围
    mapping(bytes32 => bool) private hasBeenCalled; // function -> 是否被调用过

    modifier onlySaleOwner() {
        if (msg.sender != sale.saleOwner) {
            revert IceFrogSale__OnlyCallBySaleOwner();
        }
        _;
    }

    modifier onlyOwner() {
        if (msg.sender != i_salesFactory.owner()) {
            revert IceFrogSale__OnlyCallByAdmin();
        }
        _;
    }

    modifier onlyOnce(bytes32 funcId) {
        if (hasBeenCalled[funcId]) {
            revert IceFrogSale__ThisFuncCanOnlyBeCalledOnce();
        }
        hasBeenCalled[funcId] = true;
        _;
    }

    // Events
    event TokensSold(address user, uint256 amount);
    event UserRegistered(address user);
    event TokenPriceSet(uint256 newPrice);
    event MaxParticipationSet(uint256 maxParticipation);
    event TokensWithdrawn(address user, uint256 amount);
    event SaleCreated(
        address saleOwner,
        uint256 tokenPriceInETH,
        uint256 amountOfTokensToSell,
        uint256 saleEnd
    );
    event StartTimeSet(uint256 startTime);
    event RegistrationTimeSet(
        uint256 registrationTimeStarts,
        uint256 registrationTimeEnds
    );

    constructor(address _stakingMining) {
        if (_stakingMining == address(0)) {
            revert IceFrogSale__InvaildSalesFactoryAddr();
        }

        i_salesFactory = SalesFactory(msg.sender);
        i_stakingMining = StakingMining(_stakingMining);
    }

    function setVestingParams(
        uint256[] memory _unlockingTimes,
        uint256[] memory _percents,
        uint256 _maxVestingTimeShift
    ) external onlyOwner {
        if (
            vestingPercentPerPortion.length != 0 ||
            vestingPortionsUnlockTime.length != 0
        ) {
            revert IceFrogSale__TheLengthsOfBothArrsMustBeZero();
        }

        if (_unlockingTimes.length != _percents.length) {
            revert IceFrogSale__TheLengthsOfTheTwoArrsAreInconsistent();
        }

        // 确保setSaleParams函数被先调用
        if (portionVestingPrecision == 0) {
            revert IceFrogSale__PleaseCallTheSetSaleParamsFuncFirst();
        }

        if (_maxVestingTimeShift > 30 days) {
            revert IceFrogSale__MaximalShiftIs30Days();
        }
        maxVestingTimeShift = _maxVestingTimeShift;

        uint256 sum;

        for (uint256 i = 0; i < _unlockingTimes.length; i++) {
            vestingPortionsUnlockTime.push(_unlockingTimes[i]);
            vestingPercentPerPortion.push(_percents[i]);
            sum += _percents[i];
        }

        assert(sum == portionVestingPrecision);
    }

    function shiftVestingUnlockingTimes(
        uint256 timeToShift
    ) external onlyOwner onlyOnce(keccak256("shiftVestingUnlockingTimes")) {
        if (timeToShift <= 0 || timeToShift >= maxVestingTimeShift) {
            revert IceFrogSale__InvalidShiftTimeRange();
        }

        for (uint256 i = 0; i < vestingPortionsUnlockTime.length; i++) {
            vestingPortionsUnlockTime[i] =
                vestingPortionsUnlockTime[i] +
                timeToShift;
        }
    }

    function setSaleParams(
        address _token,
        address _saleOwner,
        uint256 _tokenPriceInETH,
        uint256 _amountOfTokensToSell,
        uint256 _saleEnd,
        uint256 _tokensUnlockTime,
        uint256 _portionVestingPrecision,
        uint256 _maxParticipation
    ) external onlyOwner {
        if (sale.isCreated) {
            revert IceFrogSale__SaleIsAlreadyExisted();
        }

        if (_saleOwner == address(0)) {
            revert IceFrogSale__SaleOwnerAddrCanNotBeEmpty();
        }

        if (
            _tokenPriceInETH == 0 ||
            _amountOfTokensToSell == 0 ||
            _saleEnd <= block.timestamp ||
            _tokensUnlockTime <= block.timestamp ||
            _maxParticipation <= 0
        ) {
            revert IceFrogSale__InvalidInputParams();
        }

        if (_portionVestingPrecision < 100) {
            revert IceFrogSale__CanNotBeLessThan100();
        }

        sale.token = IERC20(_token);
        sale.isCreated = true;
        sale.saleOwner = _saleOwner;
        sale.tokenPriceInETH = _tokenPriceInETH;
        sale.amountOfTokensToSell = _amountOfTokensToSell;
        sale.saleEnd = _saleEnd;
        sale.tokensUnlockTime = _tokensUnlockTime;
        sale.maxParticipation = _maxParticipation;

        portionVestingPrecision = _portionVestingPrecision;

        emit SaleCreated(
            sale.saleOwner,
            sale.tokenPriceInETH,
            sale.amountOfTokensToSell,
            sale.saleEnd
        );
    }

    // 追溯设置销售代币地址的功能，只能在初始合同创建完成后调用一次，为在售卖启动时没有代币的团队设置。
    function setSaleToken(
        address saleToken
    ) external onlyOwner onlyOnce(keccak256("setSaleToken")) {
        if (address(sale.token) != address(0)) {
            revert IceFrogSale__TokenAddrMustBeEmpty();
        }
        sale.token = IERC20(saleToken);
    }

    // 投资者参与售卖注册时间设置
    function setRegistrationTime(
        uint256 _registrationTimeStarts,
        uint256 _registrationTimeEnds
    ) external onlyOwner {
        if (!sale.isCreated) {
            revert IceFrogSale__SaleIsNotExisted();
        }

        if (registration.registrationTimeStarts != 0) {
            revert IceFrogSale__RegistrationTimeHasBeenSet();
        }

        if (
            _registrationTimeStarts < block.timestamp ||
            _registrationTimeEnds <= _registrationTimeStarts
        ) {
            revert IceFrogSale__InvalidRegistrationTimeRange();
        }

        if (_registrationTimeEnds >= sale.saleEnd) {
            revert IceFrogSale__RegistrationEndNeedsToBeLessThanSaleEnd();
        }

        // if (sale.saleStart > 0) {
        //     if (_registrationTimeEnds >= sale.saleStart) {
        //         revert IceFrogSale__RegistrationEndNeedsToBeLessThanSaleStart();
        //     }
        // }

        registration.registrationTimeStarts = _registrationTimeStarts;
        registration.registrationTimeEnds = _registrationTimeEnds;

        emit RegistrationTimeSet(
            registration.registrationTimeStarts,
            registration.registrationTimeEnds
        );
    }

    function setSaleStart(uint256 starTime) external onlyOwner {
        if (!sale.isCreated) {
            revert IceFrogSale__SaleIsNotExisted();
        }

        if (sale.saleStart != 0) {
            revert IceFrogSale__SaleStartTimeHasBeenSet();
        }

        if (starTime <= registration.registrationTimeEnds) {
            revert IceFrogSale__SaleStartTimeShouldBeGreaterThanRegEndTime();
        }

        if (starTime >= sale.saleEnd) {
            revert IceFrogSale__SaleStartTimeShouldBeLessThanSaleEndTime();
        }

        if (starTime < block.timestamp) {
            revert IceFrogSale__SaleStartTimeShouldBeGreaterThanCurrentTime();
        }

        sale.saleStart = starTime;

        emit StartTimeSet(sale.saleStart);
    }

    // 投资者注册参与售卖
    function registerForSale(bytes memory signature, uint256 poolId) external {
        if (
            block.timestamp < registration.registrationTimeStarts ||
            block.timestamp > registration.registrationTimeEnds
        ) {
            revert IceFrogSale__NonRegistrationTime();
        }

        if (!checkRegistrationSignature(signature, msg.sender)) {
            revert IceFrogSale__InvalidSignature();
        }

        if (isRegistered[msg.sender]) {
            revert IceFrogSale__DuplicateRegistrationIsNotAllowed();
        }

        isRegistered[msg.sender] = true;

        // 设置用户质押在流动性池里代币的解锁时间
        i_stakingMining.setTokensUnlockTime(poolId, msg.sender, sale.saleEnd);

        registration.numberOfRegistrants++;

        emit UserRegistered(msg.sender);
    }

    // 在销售前更新代币价格以匹配最接近的美元的期望汇率，这将在销售期间每 N 分钟通过预言机更新一次。
    function updateTokenPriceInETH(uint256 price) external onlyOwner {
        if (price <= 0) {
            revert IceFrogSale__InvalidPrice();
        }
        sale.tokenPriceInETH = price;
        emit TokenPriceSet(price);
    }

    // 延迟售卖开始时间
    function postponeSale(uint256 timeToShift) external onlyOwner {
        if (block.timestamp >= sale.saleStart) {
            revert IceFrogSale__SaleAlreadyStarted();
        }
        sale.saleStart = sale.saleStart + timeToShift;

        if (sale.saleStart + timeToShift >= sale.saleEnd) {
            revert IceFrogSale__SaleStartTimeShouldBeLessThanEndTime();
        }
    }

    // 延长注册期限
    function extendRegistrationPeriod(uint256 timeToAdd) external onlyOwner {
        if (registration.registrationTimeEnds + timeToAdd >= sale.saleStart) {
            revert IceFrogSale__SaleStartTimeShouldBeGreaterThanRegEndTime();
        }

        registration.registrationTimeEnds =
            registration.registrationTimeEnds +
            timeToAdd;
    }

    // 售卖开始前设置投资者参与的最大金额
    function setCap(uint256 cap) external onlyOwner {
        if (block.timestamp >= sale.saleStart) {
            revert IceFrogSale__SaleAlreadyStarted();
        }
        if (cap <= 0) {
            revert IceFrogSale__InvalidNumOfParticipants();
        }

        sale.maxParticipation = cap;

        emit MaxParticipationSet(sale.maxParticipation);
    }

    // 项目方存入代币，只允许调用一次
    function depositTokens()
        external
        onlySaleOwner
        onlyOnce(keccak256("depositTokens"))
    {
        sale.token.safeTransferFrom(
            msg.sender,
            address(this),
            sale.amountOfTokensToSell
        );
    }

    // 投资者参与售卖活动购买代币
    function participate(
        bytes memory signature,
        uint256 amount
    ) external payable {
        if (amount <= 0) {
            revert IceFrogSale__InvalidETHAmount();
        }

        if (amount > sale.maxParticipation) {
            revert IceFrogSale__ExceededTheMaximumAmountOfParticipation();
        }

        if (!isRegistered[msg.sender]) {
            revert IceFrogSale__NotRegisteredForTheSale();
        }

        if (!checkParticipationSignature(signature, msg.sender, amount)) {
            revert IceFrogSale__SignatureVerificationFailed();
        }

        if (
            block.timestamp < sale.saleStart || block.timestamp >= sale.saleEnd
        ) {
            revert IceFrogSale__NotInTheSaleTimeRange();
        }

        if (isParticipated[msg.sender]) {
            revert IceFrogSale__CanOnlyParticipateInOneSale();
        }

        if (msg.sender != tx.origin) {
            revert IceFrogSale__CannotBeCalledByContracts();
        }

        uint256 amountOfTokensBuying = (msg.value * 1e18) /
            sale.tokenPriceInETH;

        sale.totalTokensSold = sale.totalTokensSold + amountOfTokensBuying;

        sale.totalETHRaised = sale.totalETHRaised + msg.value;

        // 该数组用来表示在代币不同比例的解锁阶段，投资者是否提取了代币
        bool[] memory _isPortionWithdrawn = new bool[](
            vestingPortionsUnlockTime.length
        );

        Participation memory p = Participation({
            amountBought: amountOfTokensBuying,
            amountETHPaid: msg.value,
            timeParticipated: block.timestamp,
            isPortionWithdrawn: _isPortionWithdrawn
        });

        userToParticipation[msg.sender] = p;

        isParticipated[msg.sender] = true;

        numberOfParticipants++;

        emit TokensSold(msg.sender, amountOfTokensBuying);
    }

    function withdrawTokens(uint256 portionId) external {
        if (block.timestamp < sale.tokensUnlockTime) {
            revert IceFrogSale__TokensHaveNotYetBeenUnlocked();
        }

        if (portionId >= vestingPercentPerPortion.length) {
            revert IceFrogSale__PortionIdIsOutOfUnlockRange();
        }

        Participation storage p = userToParticipation[msg.sender];

        if (p.isPortionWithdrawn[portionId]) {
            revert IceFrogSale__TokensHaveBeenWithdrawn();
        }

        if (vestingPortionsUnlockTime[portionId] > block.timestamp) {
            revert IceFrogSale__PortionHasNotBeenUnlocked();
        }

        p.isPortionWithdrawn[portionId] = true;
        uint256 amountWithdrawing = p.amountBought *
            (vestingPercentPerPortion[portionId] / portionVestingPrecision);

        if (amountWithdrawing > 0) {
            sale.token.safeTransfer(msg.sender, amountWithdrawing);
            emit TokensWithdrawn(msg.sender, amountWithdrawing);
        }
    }

    // 投资者一次性提取多个部分未锁定的项目代币
    function withdrawMultiplePortions(uint256[] calldata portionIds) external {
        uint256 totalToWithdraw = 0;

        Participation storage p = userToParticipation[msg.sender];

        for (uint i = 0; i < portionIds.length; i++) {
            uint256 portionId = portionIds[i];

            if (portionId >= vestingPercentPerPortion.length) {
                revert IceFrogSale__PortionIdIsOutOfUnlockRange();
            }

            if (p.isPortionWithdrawn[portionId]) {
                revert IceFrogSale__TokensHaveBeenWithdrawn();
            }

            if (vestingPortionsUnlockTime[portionId] > block.timestamp) {
                revert IceFrogSale__PortionHasNotBeenUnlocked();
            }

            p.isPortionWithdrawn[portionId] = true;
            uint256 amountWithdrawing = p.amountBought *
                (vestingPercentPerPortion[portionId] / portionVestingPrecision);
            totalToWithdraw = totalToWithdraw + amountWithdrawing;
        }

        if (totalToWithdraw > 0) {
            sale.token.safeTransfer(msg.sender, totalToWithdraw);
            emit TokensWithdrawn(msg.sender, totalToWithdraw);
        }
    }

    // 项目方提取出售代币所获得的ETH收益
    function withdrawEarnings() private {
        if (block.timestamp < sale.saleEnd) {
            revert IceFrogSale__TheSaleHasNotEndedYet();
        }

        if (sale.earningsWithdrawn) {
            revert IceFrogSale__CanOnlyWithdrawTheEarningsOnce();
        }
        sale.earningsWithdrawn = true;

        uint256 totalProfit = sale.totalETHRaised;

        (bool success, ) = msg.sender.call{value: totalProfit}("");

        if (!success) {
            revert IceFrogSale__TransferFailed();
        }
    }

    // 项目方提取没有被售出的代币
    function withdrawLeftover() private {
        if (block.timestamp < sale.saleEnd) {
            revert IceFrogSale__TheSaleHasNotEndedYet();
        }

        if (sale.leftoverWithdrawn) {
            revert IceFrogSale__CanOnlyWithdrawTheLeftoverOnce();
        }

        sale.leftoverWithdrawn = true;

        uint256 leftover = sale.amountOfTokensToSell - sale.totalTokensSold;

        if (leftover > 0) {
            sale.token.safeTransfer(msg.sender, leftover);
        }
    }

    function withdrawEarningsAndLeftover() external onlySaleOwner {
        withdrawEarnings();
        withdrawLeftover();
    }

    function withdrawEarningsExternal() external onlySaleOwner {
        withdrawEarnings();
    }

    function withdrawLeftoverExternal() external onlySaleOwner {
        withdrawLeftover();
    }

    // 检查用户注册签名是否由管理员签署
    function checkRegistrationSignature(
        bytes memory signature,
        address user
    ) public view returns (bool) {
        bytes32 hash = keccak256(abi.encodePacked(user, address(this)));
        bytes32 messageHash = hash.toEthSignedMessageHash();

        return i_salesFactory.owner() == messageHash.recover(signature);
    }

    // 检查参与售卖的用户签名是否由管理员签署
    function checkParticipationSignature(
        bytes memory signature,
        address user,
        uint256 amount
    ) public view returns (bool) {
        bytes32 hash = keccak256(abi.encodePacked(user, amount, address(this)));
        bytes32 messageHash = hash.toEthSignedMessageHash();
        return i_salesFactory.owner() == messageHash.recover(signature);
    }

    function getParticipation(
        address _user
    ) external view returns (uint256, uint256, uint256, bool[] memory) {
        Participation memory p = userToParticipation[_user];
        return (
            p.amountBought,
            p.amountETHPaid,
            p.timeParticipated,
            p.isPortionWithdrawn
        );
    }

    function getNumberOfRegisteredUsers() external view returns (uint256) {
        return registration.numberOfRegistrants;
    }

    function getVestingInfo()
        external
        view
        returns (uint256[] memory, uint256[] memory)
    {
        return (vestingPortionsUnlockTime, vestingPercentPerPortion);
    }

    receive() external payable {}
}
