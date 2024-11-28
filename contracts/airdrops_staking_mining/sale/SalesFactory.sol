// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import "@chainlink/contracts/node_modules/@openzeppelin/contracts/access/Ownable.sol";
import "./IceFrogSale.sol";

error SalesFactory__WrongInput();

contract SalesFactory is Ownable {
    address private immutable i_stakingMining;

    mapping(address => bool) public isSaleCreatedThroughFactory;
    // mapping(address => address) public saleOwnerToSale;
    // mapping(address => address) public tokenToSale;

    address[] private allSales;

    event SaleDeployed(address saleContract);

    // event SaleOwnerAndTokenSetInFactory(
    //     address sale,
    //     address saleOwner,
    //     address saleToken
    // );

    constructor(address _stakingMining) {
        i_stakingMining = _stakingMining;
    }

    function deploySale() external onlyOwner {
        IceFrogSale sale = new IceFrogSale(i_stakingMining);
        isSaleCreatedThroughFactory[address(sale)] = true;
        allSales.push(address(sale));

        emit SaleDeployed(address(sale));
    }

    // 获得部署的Sale合约数量
    function getNumberOfSalesDeployed() external view returns (uint) {
        return allSales.length;
    }

    // 获得最后一个部署的Sale合约地址
    function getLastDeployedSale() external view returns (address) {
        //
        if (allSales.length > 0) {
            return allSales[allSales.length - 1];
        }
        return address(0);
    }

    // 获得与索引对应Sale合约地址
    function getAllSales(
        uint startIndex,
        uint endIndex
    ) external view returns (address[] memory) {
        if (endIndex <= startIndex) {
            revert SalesFactory__WrongInput();
        }

        address[] memory sales = new address[](endIndex - startIndex);
        uint index = 0;

        for (uint256 i = startIndex; i < endIndex; i++) {
            sales[index] = allSales[i];
            index++;
        }

        return sales;
    }

    function getStakingMiningAddr() external view returns (address) {
        return i_stakingMining;
    }
}
