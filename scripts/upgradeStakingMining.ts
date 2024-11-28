// @ts-ignore
import { ethers, deployments } from "hardhat";

// 测试合约的升级
// yarn hardhat run scripts/upgradeStakingMining.ts --network localhost
async function main() {
  const stakingMiningProxyAdmin = await ethers.getContractAt(
    "StakingMiningProxyAdmin",
    (await deployments.get("StakingMiningProxyAdmin")).address
  );

  const proxyStakingMining = await ethers.getContractAt(
    "StakingMining",
    (await deployments.get("StakingMining_Proxy")).address
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
    // @ts-ignore
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
