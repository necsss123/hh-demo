// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

error OpToken__InvalidTime();
error OpToken__TransferFailed();

contract OptionToken is ERC20, Ownable {
    using SafeERC20 for IERC20;

    address public daiToken; // 使用该币购买期权Token
    uint public settlementTime;
    uint public constant during = 1 days; // 在行权日期前后1天以内都可以行权
    uint price;

    // 期权Token和所有人的初始化
    constructor(address dai) ERC20("OptToken", "OPT") {
        daiToken = dai; // 存入Dai地址，用Dai兑换ETH
        price = 5000; // 行权价
        settlementTime = block.timestamp + 30 days; // 行权日期在30天后
    }

    function mint() external payable onlyOwner {
        _mint(msg.sender, msg.value); // 转入ETH铸造期权token
    }

    // 行权方法
    function settlement(uint amount) external {
        // 检查是否在行权日期范围内
        if (
            block.timestamp < settlementTime ||
            block.timestamp >= settlementTime + during
        ) {
            revert OpToken__InvalidTime();
        }

        _burn(msg.sender, amount); // 行权需要先把期权token销毁

        uint needDaiAmount = price * amount;

        // 转移行权资金,把你用来购买标的资产的Dai，转到合约里
        IERC20(daiToken).safeTransferFrom(
            msg.sender,
            address(this),
            needDaiAmount
        );

        // 把标的资产ETH转给你
        safeTransferETH(msg.sender, amount);
    }

    function safeTransferETH(address to, uint256 value) internal {
        (bool success, ) = to.call{value: value}("");

        if (!success) {
            revert OpToken__TransferFailed();
        }
    }

    // 到了行权日期销毁行权token
    function burnAll() external onlyOwner {
        require(block.timestamp >= settlementTime + during, "not end");
        uint usdcAmount = IERC20(daiToken).balanceOf(address(this));

        IERC20(daiToken).safeTransfer(msg.sender, usdcAmount);

        selfdestruct(payable(msg.sender)); // 销毁合约
    }
}
