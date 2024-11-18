// @ts-ignore
import { ethers, deployments } from "hardhat";

async function main() {
  const stakingMiningProxyAdmin = await ethers.getContractAt(
    "StakingMiningProxyAdmin",
    (await deployments.get("StakingMiningProxyAdmin")).address
  );

  const proxyStakingMining = await ethers.getContractAt(
    "StakingMining",
    (await deployments.get("StakingMining")).address
  );

  const versionV1 = await proxyStakingMining.version();

  console.log(versionV1);

  const StakingMiningV2 = await ethers.getContractAt(
    "StakingMiningV2",
    (await deployments.get("StakingMiningV2")).address
  );

  const upgradeTx = await stakingMiningProxyAdmin.upgrade(
    proxyStakingMining.target,
    StakingMiningV2.target
  );

  await upgradeTx.wait(1);

  const proxyStakingMiningV2 = await ethers.getContractAt(
    "StakingMiningV2",
    proxyStakingMining.target
  );

  const versionV2 = await proxyStakingMiningV2.version();

  console.log(versionV2);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
