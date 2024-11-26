// @ts-ignore
import { ethers } from "hardhat";

export interface networkConfigItem {
  lptoken?: string;
  _rewardPerSecond?: bigint;
  // _startTimestamp?: bigint;
}

export interface networkConfigInfo {
  [key: number]: networkConfigItem;
}

export const networkConfig: networkConfigInfo = {
  31337: {
    lptoken: "0x5FbDB2315678afecb367f032d93F642f64180aa3",
    _rewardPerSecond: ethers.parseEther("1"),
    // _startTimestamp: BigInt(1731949944), // 这里设置时间需要比现实时间戳大10分钟，否则会revert
  },
  11155111: {},
};

export const developmentChains = ["hardhat", "localhost"];

export const BLOCK_CONFIRMATIONS = 6;
