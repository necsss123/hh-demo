import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";
// @ts-ignore
import { ethers } from "hardhat";

import {
  networkConfig,
  developmentChains,
  BLOCK_CONFIRMATIONS,
} from "../helper-hardhat-config";

// 0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0
const deployStakingMiningV2: DeployFunction = async function (
  hre: HardhatRuntimeEnvironment
) {
  // @ts-ignore
  const { deployments, getNamedAccounts, network } = hre;
  const { deploy, log } = deployments;
  const { deployer } = await getNamedAccounts();
  const chainId = network.config.chainId;

  //   let icefrog, icefrogAddr;

  if (chainId == 31337) {
    const waitBlockConfirmations = developmentChains.includes(network.name)
      ? 1
      : BLOCK_CONFIRMATIONS;

    // icefrog = await ethers.getContractAt(
    //   "IceFrog",
    //   (await deployments.get("IceFrog")).address
    // );

    // icefrogAddr = icefrog.target;
    const START_TIMESTAMP_DELTA = 600;
    const startTimestamp =
      (await ethers.provider.getBlock("latest")).timestamp +
      START_TIMESTAMP_DELTA;

    const args: any[] = [
      networkConfig[31337]["lptoken"],
      networkConfig[31337]["_rewardPerSecond"],
      startTimestamp,
    ];

    const feeData = await ethers.provider.getFeeData();

    const stakingMining = await deploy("StakingMiningV2", {
      from: deployer,
      log: true,
      args: args,
      waitConfirmations: waitBlockConfirmations,
      gasPrice: feeData.gasPrice?.toString(),
    });
  } else {
  }
};

export default deployStakingMiningV2;

deployStakingMiningV2.tags = ["all", "stakingv2"];
