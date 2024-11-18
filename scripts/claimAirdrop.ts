// @ts-ignore
import { ethers, network, deployments, Contract } from "hardhat";

export async function claimAirdrop(airdropToken: Contract) {
  const airdrop = await ethers.getContractAt(
    "Airdrop",
    (await deployments.get("Airdrop")).address
  );

  let airdropAddr = airdrop.target;

  const txTransfer = await airdropToken.transfer(
    airdropAddr,
    ethers.parseEther("1000")
  );

  await txTransfer.wait(1);

  const balance = await airdropToken.balanceOf(airdropAddr);

  console.log(
    "Airdrop balance of IceFrog token: ",
    ethers.formatEther(balance)
  );

  const txClaim = await airdrop.withdrawTokens();
  await txClaim.wait(1);

  const balanceAfter = await airdropToken.balanceOf(airdropAddr);

  console.log(
    "Airdrop balance of IceFrog token after withdrawTokens:",
    ethers.formatEther(balanceAfter)
  );
}
