import { assert, expect } from "chai";
// @ts-ignore
import { network, deployments, ethers } from "hardhat";
import { developmentChains, networkConfig } from "../../helper-hardhat-config";
import { Airdrop, IceFrog, StakingMining } from "../../typechain-types";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";

developmentChains.includes(network.name)
  ? describe("StakingMining Unit Tests", () => {
      let icefrogDeployer: IceFrog, icefrogUser: IceFrog;
      let airdropDeployer: Airdrop, airdropUser: Airdrop;
      let stakingMiningDeployer: StakingMining,
        stakingMiningUser: StakingMining;
      let icefrogAddr: string, airdropAddr: string, stakingMiningAddr: string;
      let accounts: HardhatEthersSigner[];
      let deployer: HardhatEthersSigner, user: HardhatEthersSigner;
      let deployerBalance: bigint, userBalance: bigint, rewardPerSec: bigint;

      const ALLOC_POINT = 100;
      const TOKENS_TO_FUND = 3600000000000000000000n; // 3600 * 10 ** 18
      const DEFAULT_DEPOSIT = 80000000000000000000n; // 80 * 10 ** 18

      const chainId = network.config.chainId!;

      beforeEach(async () => {
        // console.log("beforeEach is running...");
        accounts = await ethers.getSigners();
        deployer = accounts[0];
        user = accounts[1];
        await deployments.fixture(["all"]);
        icefrogDeployer = await ethers.getContractAt(
          "IceFrog",
          (await deployments.get("IceFrog")).address,
          deployer
        );
        airdropDeployer = await ethers.getContractAt(
          "Airdrop",
          (await deployments.get("Airdrop")).address,
          deployer
        );
        // const stakingMiningProxyAdmin = await ethers.getContractAt(
        //   "StakingMiningProxyAdmin",
        //   (await deployments.get("StakingMiningProxyAdmin")).address,
        //   deployer
        // );
        // const stakingMiningImp =
        //   await stakingMiningProxyAdmin.getProxyImplementation(
        //     (await deployments.get("StakingMining_Proxy")).address
        //   );
        // stakingMiningDeployer = await ethers.getContractAt(
        //   "StakingMining",
        //   stakingMiningImp,
        //   deployer
        // );
        stakingMiningDeployer = await ethers.getContractAt(
          "StakingMining",
          (await deployments.get("StakingMining_Proxy")).address,
          deployer
        );
        icefrogAddr = icefrogDeployer.target as string;
        airdropAddr = airdropDeployer.target as string;
        stakingMiningAddr = stakingMiningDeployer.target as string;
        await icefrogDeployer.transfer(airdropAddr, ethers.parseEther("1000"));
        airdropUser = airdropDeployer.connect(user);
        await airdropUser.withdrawTokens();
        deployerBalance = await icefrogDeployer.balanceOf(deployer.address);
        userBalance = await icefrogDeployer.balanceOf(user.address);
        rewardPerSec = await stakingMiningDeployer.getRewardPerSec();
        // console.log(`deployerBalance: ${deployerBalance.toString()}`);
        // console.log(`userBalance: ${userBalance.toString()}`);
      });

      describe("init", () => {
        it("initializes the StakingMining correctly", async () => {
          const rewardToken = await stakingMiningDeployer.getRewardToken();
          const totalRewards = await stakingMiningDeployer.getTotalRewards();
          const poolLength = await stakingMiningDeployer.getPoolNum();
          const owner = await stakingMiningDeployer.owner();
          assert.equal(
            rewardPerSec.toString(),
            networkConfig[chainId]["_rewardPerSecond"]!.toString()
          );
          assert.equal(rewardToken, networkConfig[chainId]["lptoken"]);
          assert.equal(totalRewards, 0n);
          assert.equal(poolLength, 0n);
          assert.equal(owner, deployer.address);
        });
        it("should add a pool successfully", async () => {
          await stakingMiningDeployer.add(ALLOC_POINT, icefrogAddr, false);
          const poolLength = await stakingMiningDeployer.getPoolNum();
          const totalAllocPoint =
            await stakingMiningDeployer.getTotalAllocPoint();
          assert.equal(poolLength, 1n);
          assert.equal(totalAllocPoint, BigInt(ALLOC_POINT));
        });
        it("should add a pool successfully with mass update", async () => {
          await stakingMiningDeployer.add(ALLOC_POINT, icefrogAddr, true);
          const poolLength = await stakingMiningDeployer.getPoolNum();
          const totalAllocPoint =
            await stakingMiningDeployer.getTotalAllocPoint();
          assert.equal(poolLength, 1n);
          assert.equal(totalAllocPoint, BigInt(ALLOC_POINT));
        });
      });

      describe("fund", () => {
        it("should fund successfully", async () => {
          const deployerBalanceBefore = await icefrogDeployer.balanceOf(
            deployer.address
          );
          const startTimestamp =
            await stakingMiningDeployer.getStartTimestamp();

          await icefrogDeployer.approve(stakingMiningAddr, TOKENS_TO_FUND);
          await stakingMiningDeployer.add(ALLOC_POINT, icefrogAddr, false);
          await stakingMiningDeployer.fund(TOKENS_TO_FUND);

          const deployerBalanceAfter = await icefrogDeployer.balanceOf(
            deployer.address
          );
          const stakingMiningBalanceAfter =
            await icefrogDeployer.balanceOf(stakingMiningAddr);
          const endTimestampAfter =
            await stakingMiningDeployer.getEndTimestamp();
          const totalRewards = await stakingMiningDeployer.getTotalRewards();

          assert.equal(
            deployerBalanceAfter + TOKENS_TO_FUND,
            deployerBalanceBefore
          );

          assert.equal(stakingMiningBalanceAfter, TOKENS_TO_FUND);

          assert.equal(totalRewards, TOKENS_TO_FUND);

          assert.equal(
            endTimestampAfter,
            startTimestamp + TOKENS_TO_FUND / rewardPerSec
          );
        });

        it("should not fund after end date", async () => {
          const START_TIMESTAMP_DELTA = 600;
          await icefrogDeployer.approve(stakingMiningAddr, TOKENS_TO_FUND);

          await ethers.provider.send("evm_increaseTime", [
            START_TIMESTAMP_DELTA,
          ]);
          await ethers.provider.send("evm_mine", []);

          await expect(
            stakingMiningDeployer.fund(TOKENS_TO_FUND)
            // @ts-ignore
          ).to.be.revertedWithCustomError(
            stakingMiningDeployer,
            "StakingMining__MiningIsOver"
          );
        });

        it("should not fund if token was not approved", async () => {
          await expect(
            stakingMiningDeployer.fund(TOKENS_TO_FUND)
            // @ts-ignore
          ).to.be.revertedWith("ERC20: insufficient allowance");
        });
      });

      describe("deposit", () => {
        it("should return user amount deposited in pool", async () => {
          icefrogUser = icefrogDeployer.connect(user);
          icefrogUser.approve(stakingMiningAddr, BigInt(100 * 10 ** 18));
          await stakingMiningDeployer.add(ALLOC_POINT, icefrogAddr, false);
          stakingMiningUser = stakingMiningDeployer.connect(user);
          await stakingMiningUser.deposit(0, DEFAULT_DEPOSIT);

          const userDeposited = await stakingMiningUser.getDeposited(
            0,
            user.address
          );
          const deployerDeposited = await stakingMiningDeployer.getDeposited(
            0,
            deployer.address
          );
          assert.equal(userDeposited, DEFAULT_DEPOSIT);
          assert.equal(deployerDeposited, 0n);
        });

        it("should deposit LP tokens in pool if user is already deposited in this pool", async () => {
          icefrogUser = icefrogDeployer.connect(user);
          icefrogUser.approve(stakingMiningAddr, BigInt(100 * 10 ** 18));
          await stakingMiningDeployer.add(ALLOC_POINT, icefrogAddr, false);
          stakingMiningUser = stakingMiningDeployer.connect(user);
          await stakingMiningUser.deposit(0, DEFAULT_DEPOSIT);
          await icefrogDeployer.approve(
            stakingMiningAddr,
            BigInt(100 * 10 ** 18)
          );
          await stakingMiningDeployer.deposit(0, BigInt(79 * 10 ** 18));

          const pool = await stakingMiningDeployer.getPoolInfo(0);
          assert.equal(pool.totalDeposits, BigInt(159 * 10 ** 18));
        });
      });

      describe("pendingReward", () => {
        it("should return 0 if user deposited but staking not started", async () => {
          icefrogUser = icefrogDeployer.connect(user);
          icefrogUser.approve(stakingMiningAddr, BigInt(100 * 10 ** 18));
          await stakingMiningDeployer.add(ALLOC_POINT, icefrogAddr, false);
          stakingMiningUser = stakingMiningDeployer.connect(user);
          await stakingMiningUser.deposit(0, DEFAULT_DEPOSIT);

          const userPendingReward = await stakingMiningUser.getPendingReward(
            0,
            user.address
          );
          assert.equal(userPendingReward, 0n);
        });

        it("should return 0 if staking started but user didn't deposit", async () => {
          const START_TIMESTAMP_DELTA = 600;
          stakingMiningUser = stakingMiningDeployer.connect(user);

          await icefrogDeployer.approve(stakingMiningAddr, TOKENS_TO_FUND);
          await stakingMiningDeployer.add(ALLOC_POINT, icefrogAddr, false);
          await stakingMiningDeployer.fund(TOKENS_TO_FUND);
          await ethers.provider.send("evm_increaseTime", [
            START_TIMESTAMP_DELTA,
          ]);
          await ethers.provider.send("evm_mine", []);

          const userPendingReward = await stakingMiningUser.getPendingReward(
            0,
            user.address
          );

          assert.equal(userPendingReward, 0n);
        });

        it("should return user's pending amount if staking started and user deposited", async () => {
          const START_TIMESTAMP_DELTA = 600;
          icefrogUser = icefrogDeployer.connect(user);
          icefrogUser.approve(stakingMiningAddr, BigInt(100 * 10 ** 18));
          stakingMiningUser = stakingMiningDeployer.connect(user);
          const startTimestamp =
            await stakingMiningDeployer.getStartTimestamp();

          await icefrogDeployer.approve(stakingMiningAddr, TOKENS_TO_FUND);
          await stakingMiningDeployer.add(ALLOC_POINT, icefrogAddr, false);
          await stakingMiningDeployer.fund(TOKENS_TO_FUND);
          await stakingMiningUser.deposit(0, DEFAULT_DEPOSIT);

          await ethers.provider.send("evm_increaseTime", [
            START_TIMESTAMP_DELTA + 900,
          ]);
          await ethers.provider.send("evm_mine", []);

          const userPendingReward = await stakingMiningUser.getPendingReward(
            0,
            user.address
          );

          const currentTimestamp = BigInt(
            (await ethers.provider.getBlock("latest")).timestamp
          );
          const duration = currentTimestamp - startTimestamp;
          const totalRewards = rewardPerSec * duration;
          const poolRewards = totalRewards * BigInt(ALLOC_POINT / ALLOC_POINT); // 池子0的ALLOC_POINT和总的ALLOC_POINT之比
          const poolRewardsPerShare =
            (poolRewards * BigInt(1e36)) / DEFAULT_DEPOSIT; // 11350000000000000481474234195103868518
          // const poolRewardsPerShare = poolRewards / DEFAULT_DEPOSIT;  11
          // console.log(`poolRewards: ${poolRewards}`);
          // console.log(`poolRewardsPerShare: ${poolRewardsPerShare}`);

          assert.equal(
            userPendingReward,
            (poolRewardsPerShare * DEFAULT_DEPOSIT) / BigInt(1e36) + 1n // 加的1n是对误差进行修正
          );
        });
      });

      describe("withdraw", () => {
        it("should withdraw user's deposit", async () => {
          icefrogUser = icefrogDeployer.connect(user);
          icefrogUser.approve(stakingMiningAddr, BigInt(100 * 10 ** 18));
          await stakingMiningDeployer.add(ALLOC_POINT, icefrogAddr, false);
          stakingMiningUser = stakingMiningDeployer.connect(user);
          await stakingMiningUser.deposit(0, DEFAULT_DEPOSIT);

          const poolBefore = await stakingMiningUser.getPoolInfo(0);
          const userBalanceBefore = await icefrogUser.balanceOf(user.address);
          // console.log(`${poolBefore.totalDeposits}`, `${userBalanceBefore}`);

          await stakingMiningUser.withdraw(0, poolBefore.totalDeposits);

          const poolAfter = await stakingMiningUser.getPoolInfo(0);
          const userBalanceAfter = await icefrogUser.balanceOf(user.address);

          assert.equal(userBalanceAfter, userBalanceBefore + DEFAULT_DEPOSIT);
          assert.equal(poolAfter.totalDeposits, 0n);
        });

        it("should emit Withdraw event", async () => {
          icefrogUser = icefrogDeployer.connect(user);
          icefrogUser.approve(stakingMiningAddr, BigInt(100 * 10 ** 18));
          await stakingMiningDeployer.add(ALLOC_POINT, icefrogAddr, false);
          stakingMiningUser = stakingMiningDeployer.connect(user);
          await stakingMiningUser.deposit(0, DEFAULT_DEPOSIT);

          await expect(stakingMiningUser.withdraw(0, DEFAULT_DEPOSIT))
            // @ts-ignore
            .to.emit(stakingMiningUser, "Withdraw")
            .withArgs(user.address, 0, DEFAULT_DEPOSIT);
        });
      });
    })
  : describe.skip;
