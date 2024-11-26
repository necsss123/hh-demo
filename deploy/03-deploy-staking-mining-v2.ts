import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";
// @ts-ignore
import { ethers } from "hardhat";

import {
  networkConfig,
  developmentChains,
  BLOCK_CONFIRMATIONS,
} from "../helper-hardhat-config";

const deployStakingMiningV2: DeployFunction = async function (
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

    const args: any[] = [];

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
