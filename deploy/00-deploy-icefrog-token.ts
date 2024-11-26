import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";
// @ts-ignore
import { ethers } from "hardhat";

import {
  developmentChains,
  BLOCK_CONFIRMATIONS,
} from "../helper-hardhat-config";

const INIT_SUPPLY = ethers.parseEther("10000");

const deployIceFrog: DeployFunction = async function (
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

    const icefrogToken = await deploy("IceFrog", {
      from: deployer,
      args: [INIT_SUPPLY],
      log: true,
      waitConfirmations: waitBlockConfirmations,
      gasPrice: feeData.gasPrice?.toString(),
    });
  } else {
  }
};

export default deployIceFrog;

deployIceFrog.tags = ["all", "icefrog"];
