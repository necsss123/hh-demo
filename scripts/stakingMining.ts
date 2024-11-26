import { claimAirdrop } from "./claimAirdrop";
// @ts-ignore
import { ethers, network, deployments } from "hardhat";
import { networkConfig } from "../helper-hardhat-config";

async function main() {
  const icefrog = await ethers.getContractAt(
    "IceFrog",
    networkConfig[network.config!.chainId!].lptoken!
  );

  const stakingMining = await ethers.getContractAt(
    "StakingMining",
    (await deployments.get("StakingMining_Proxy")).address
  );

  await claimAirdrop(icefrog);

  const txApprove = await icefrog.approve(
    stakingMining.target,
    ethers.parseEther("600")
  );

  txApprove.wait(1);

  const txFund = await stakingMining.fund(ethers.parseEther("600"));

  txFund.wait(1);

  await stakingMining.add(100, icefrog.target, true);

  let poolNum = await stakingMining.getPoolNum();

  console.log(`funded and LP token added,the num of pool is ${poolNum}`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

// 测试向空投合约转移1000个Icefrog，并领取空投。测试向质押挖矿合约添加1个流动性池
// yarn hardhat run scripts/stakingMining.ts --network localhost
