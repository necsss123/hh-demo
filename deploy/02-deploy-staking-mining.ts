import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";
// @ts-ignore
import { ethers } from "hardhat";

import {
  //  networkConfig,
  developmentChains,
  BLOCK_CONFIRMATIONS,
} from "../helper-hardhat-config";

const deployStakingMining: DeployFunction = async function (
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

    // const START_TIMESTAMP_DELTA = 600;
    // const startTimestamp =
    //   (await ethers.provider.getBlock("latest")).timestamp +
    //   START_TIMESTAMP_DELTA;

    const args: any[] = [];

    const feeData = await ethers.provider.getFeeData();

    const stakingMining = await deploy("StakingMining", {
      from: deployer,
      log: true,
      args: args,
      waitConfirmations: waitBlockConfirmations,
      gasPrice: feeData.gasPrice?.toString(),
      proxy: {
        proxyContract: "OpenZeppelinTransparentProxy",
        viaAdminContract: {
          name: "StakingMiningProxyAdmin",
          artifact: "StakingMiningProxyAdmin",
        },
      },
    });
  } else {
  }
};

export default deployStakingMining;

deployStakingMining.tags = ["all", "staking"];
