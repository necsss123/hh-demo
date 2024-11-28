import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";
// @ts-ignore
import { ethers } from "hardhat";

import {
  developmentChains,
  BLOCK_CONFIRMATIONS,
} from "../helper-hardhat-config";

const deployAirdrop: DeployFunction = async function (
  hre: HardhatRuntimeEnvironment
) {
  // @ts-ignore
  const { deployments, getNamedAccounts, network } = hre;
  const { deploy, log } = deployments;
  const { deployer } = await getNamedAccounts();
  const chainId = network.config.chainId;

  let icefrog, icefrogAddr;

  if (chainId == 31337) {
    const waitBlockConfirmations = developmentChains.includes(network.name)
      ? 1
      : BLOCK_CONFIRMATIONS;

    icefrog = await ethers.getContractAt(
      "IceFrog",
      (await deployments.get("IceFrog")).address
    );

    icefrogAddr = icefrog.target;

    const feeData = await ethers.provider.getFeeData();

    const airdrop = await deploy("Airdrop", {
      from: deployer,
      log: true,
      args: [icefrogAddr],
      waitConfirmations: waitBlockConfirmations,
      gasPrice: feeData.gasPrice?.toString(),
    });
  } else {
  }
};

export default deployAirdrop;
deployAirdrop.tags = ["all", "airdrop"];
