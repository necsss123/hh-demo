import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";
// @ts-ignore
import { ethers } from "hardhat";

import {
  networkConfig,
  developmentChains,
  BLOCK_CONFIRMATIONS,
} from "../helper-hardhat-config";

const deploySalesFactory: DeployFunction = async function (
  hre: HardhatRuntimeEnvironment
) {
  // @ts-ignore
  const { deployments, getNamedAccounts, network } = hre;
  const { deploy, log } = deployments;
  const { deployer } = await getNamedAccounts();
  const chainId = network.config.chainId;

  if (chainId == 31337) {
    const waitBlockConfirmations = developmentChains.includes(network.name)
      ? 1
      : BLOCK_CONFIRMATIONS;

    const feeData = await ethers.provider.getFeeData();

    const stakingMining = await ethers.getContractAt(
      "StakingMining",
      (await deployments.get("StakingMining_Proxy")).address
    );

    const salesFactory = await deploy("SalesFactory", {
      from: deployer,
      log: true,
      args: [stakingMining.target],
      waitConfirmations: waitBlockConfirmations,
      gasPrice: feeData.gasPrice?.toString(),
    });

    // 对StakingMining合约进行初始化操作
    const salesFactoryInstance = await ethers.getContractAt(
      "SalesFactory",
      (await deployments.get("SalesFactory")).address
    );

    const START_TIMESTAMP_DELTA = 600;
    const startTimestamp =
      (await ethers.provider.getBlock("latest")).timestamp +
      START_TIMESTAMP_DELTA;

    const lptoken = networkConfig[31337]["lptoken"];
    const rewardPerSecond = networkConfig[31337]["_rewardPerSecond"];

    const initTx = await stakingMining.init(
      lptoken,
      rewardPerSecond,
      startTimestamp,
      salesFactoryInstance.target
    );

    await initTx.wait(1);
  } else {
  }
};

export default deploySalesFactory;

deploySalesFactory.tags = ["all", "sales_factory"];
