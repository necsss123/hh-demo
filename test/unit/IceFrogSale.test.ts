import { assert, expect } from "chai";
// @ts-ignore
import { network, deployments, ethers } from "hardhat";
import { developmentChains, networkConfig } from "../../helper-hardhat-config";
import {
  SalesFactory,
  StakingMining,
  IceFrogSale,
  IceFrog,
} from "../../typechain-types";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import { ecsign, hashPersonalMessage, toBuffer } from "ethereumjs-util";
import { keccak256, solidityPacked } from "ethers";
import "dotenv/config";

// yarn hardhat test test/unit/IceFrogSale.test.ts
developmentChains.includes(network.name)
  ? describe("IceFrogSale Unit Tests", () => {
      let salesFactoryDeployer: SalesFactory;
      let icefrogDeployer: IceFrog;
      let stakingMiningDeployer: StakingMining;
      let icefrogSaleFactory: IceFrogSale, icefrogSaleDeployer: IceFrogSale;
      let accounts: HardhatEthersSigner[];
      let deployer: HardhatEthersSigner,
        userProjectParty: HardhatEthersSigner,
        userInvestor: HardhatEthersSigner;
      let deployTx: ethers.provider.ContractTransactionResponse;
      let tokenAddr: string;
      const tokenPriceInETH = 100000000000n; // 10 ** 11
      const amountOfTokensToSell = 3000000000000000000000n; // 3000 * 10 ** 18
      const maxParticipation = 10000000000000000000000000n; // 10000000 * 10 ** 18

      const PORTION_VESTING_PRECISION = 100;
      const REGISTRATION_TIME_STARTS_DELTA = 10;
      const REGISTRATION_TIME_ENDS_DELTA = 40;
      const SALE_START_DELTA = 50;

      const chainId = network.config.chainId!;

      const deployerPrivateKey = process.env.DEPLOYER_PRIVATE_KEY as string;

      function signRegistration(
        userAddr: string,
        contractAddr: string,
        privateKey: Buffer
      ) {
        // 相当于keccak256(abi.encodePacked(user, address(this)))
        const digest = keccak256(
          solidityPacked(["address", "address"], [userAddr, contractAddr])
        );

        const bufferDigest = toBuffer(digest);

        return generateSignature(bufferDigest, privateKey);
      }

      // function signParticipation(
      //   userAddr: string,
      //   amount: bigint,
      //   contractAddr: string,
      //   privateKey: Buffer
      // ) {
      //   const digest = keccak256(
      //     solidityPacked(
      //       ["address", "uint256", "address"],
      //       [userAddr, amount, contractAddr]
      //     )
      //   );

      //   return generateSignature(toBuffer(digest), privateKey);
      // }

      function generateSignature(digest: Buffer, privateKey: Buffer): Buffer {
        // 前缀 "\x19Ethereum Signed Message:\n32"
        // 参考 https://github.com/OpenZeppelin/openzeppelin-contracts/issues/890
        const prefixedHash = hashPersonalMessage(digest);

        // 签名消息
        const { v, r, s } = ecsign(prefixedHash, privateKey);

        // 按以下顺序连接 r(32)、s(32)、v(1) 来生成签名
        // 参考 https://github.com/OpenZeppelin/openzeppelin-contracts/blob/76fe1548aee183dfcc395364f0745fe153a56141/contracts/ECRecovery.sol#L39-L43
        const vb = Buffer.from([v]);
        const signature = Buffer.concat([r, s, vb]);

        return signature;
      }

      beforeEach(async () => {
        ///console.log("beforeEach...");
        accounts = await ethers.getSigners();
        deployer = accounts[0];
        userProjectParty = accounts[1];
        userInvestor = accounts[2];
        await deployments.fixture(["all"]);

        icefrogDeployer = await ethers.getContractAt(
          "IceFrog",
          (await deployments.get("IceFrog")).address,
          deployer
        );

        stakingMiningDeployer = await ethers.getContractAt(
          "StakingMining",
          (await deployments.get("StakingMining")).address,
          deployer
        );

        salesFactoryDeployer = await ethers.getContractAt(
          "SalesFactory",
          (await deployments.get("SalesFactory")).address,
          deployer
        );

        icefrogSaleFactory = await ethers.getContractFactory("IceFrogSale");
        deployTx = await salesFactoryDeployer.deploySale();
        icefrogSaleDeployer = icefrogSaleFactory.attach(
          await salesFactoryDeployer.getLastDeployedSale()
        ) as IceFrogSale;

        tokenAddr = icefrogDeployer.target as string;
      });

      // describe("constructor", () => {
      //   it("the contract owner is the SalesFactory deployer", async () => {
      //     const receipt = await ethers.provider.getTransactionReceipt(
      //       deployTx.hash
      //     );
      //     const icefrogSaleDeployerAddr = receipt.from;
      //     assert.equal(icefrogSaleDeployerAddr, deployer.address);
      //   });
      //   it("initializes the icefrog sale correctly", async () => {
      //     const salesFactoryAddr = await icefrogSaleDeployer.getSalesFactory();
      //     const stakingMiningAddr =
      //       await icefrogSaleDeployer.getStakingMining();
      //     assert.equal(salesFactoryAddr, salesFactoryDeployer.target);
      //     assert.equal(stakingMiningAddr, stakingMiningDeployer.target);
      //   });
      // });

      // describe("setSaleParams", () => {
      //   it("should set the sale parameters", async () => {
      //     const timestamp = (await ethers.provider.getBlock("latest"))
      //       .timestamp;

      //     const saleOwner = deployer.address;

      //     const saleEnd = timestamp + 100;
      //     const tokensUnlockTime = timestamp + 150;

      //     await icefrogSaleDeployer.setSaleParams(
      //       tokenAddr,
      //       saleOwner,
      //       tokenPriceInETH,
      //       amountOfTokensToSell,
      //       saleEnd,
      //       tokensUnlockTime,
      //       PORTION_VESTING_PRECISION,
      //       maxParticipation
      //     );

      //     const sale = await icefrogSaleDeployer.sale();

      //     assert.equal(sale.token, tokenAddr);
      //     assert.equal(sale.isCreated, true);
      //     assert.equal(sale.saleOwner, deployer.address);
      //     assert.equal(sale.tokenPriceInETH, tokenPriceInETH);
      //     assert.equal(sale.amountOfTokensToSell, amountOfTokensToSell);
      //     assert.equal(sale.saleEnd, saleEnd);
      //     assert.equal(sale.tokensUnlockTime, tokensUnlockTime);
      //     assert.equal(sale.maxParticipation, maxParticipation);
      //   });

      //   it("should not allow non-deployer to set sale parameters", async () => {
      //     const icefrogSaleUserPj =
      //       icefrogSaleDeployer.connect(userProjectParty);

      //     const timestamp = (await ethers.provider.getBlock("latest"))
      //       .timestamp;
      //     const saleEnd = timestamp + 100;
      //     const tokensUnlockTime = timestamp + 150;
      //     await expect(
      //       icefrogSaleUserPj.setSaleParams(
      //         tokenAddr,
      //         userProjectParty.address,
      //         tokenPriceInETH,
      //         amountOfTokensToSell,
      //         saleEnd,
      //         tokensUnlockTime,
      //         PORTION_VESTING_PRECISION,
      //         maxParticipation
      //       )
      //       // @ts-ignore
      //     ).to.be.revertedWithCustomError(
      //       icefrogSaleUserPj,
      //       "IceFrogSale__OnlyCallByAdmin"
      //     );
      //   });

      //   it("should emit SaleCreated event when parameters are set", async () => {
      //     const timestamp = (await ethers.provider.getBlock("latest"))
      //       .timestamp;
      //     const saleEnd = timestamp + 100;
      //     const tokensUnlockTime = timestamp + 150;

      //     await expect(
      //       icefrogSaleDeployer.setSaleParams(
      //         tokenAddr,
      //         deployer.address,
      //         tokenPriceInETH,
      //         amountOfTokensToSell,
      //         saleEnd,
      //         tokensUnlockTime,
      //         PORTION_VESTING_PRECISION,
      //         maxParticipation
      //       )
      //     )
      //       // @ts-ignore
      //       .to.emit(icefrogSaleDeployer, "SaleCreated")
      //       .withArgs(
      //         deployer.address,
      //         tokenPriceInETH,
      //         amountOfTokensToSell,
      //         saleEnd
      //       );
      //   });

      //   it("should not set sale parameters if sale is already created", async () => {
      //     const timestamp = (await ethers.provider.getBlock("latest"))
      //       .timestamp;
      //     const saleEnd = timestamp + 100;
      //     const tokensUnlockTime = timestamp + 150;

      //     await icefrogSaleDeployer.setSaleParams(
      //       tokenAddr,
      //       userProjectParty.address,
      //       tokenPriceInETH,
      //       amountOfTokensToSell,
      //       saleEnd,
      //       tokensUnlockTime,
      //       PORTION_VESTING_PRECISION,
      //       maxParticipation
      //     );

      //     await expect(
      //       icefrogSaleDeployer.setSaleParams(
      //         tokenAddr,
      //         deployer.address,
      //         tokenPriceInETH,
      //         amountOfTokensToSell,
      //         saleEnd,
      //         tokensUnlockTime,
      //         PORTION_VESTING_PRECISION,
      //         maxParticipation
      //       )
      //       // @ts-ignore
      //     ).to.be.revertedWithCustomError(
      //       icefrogSaleDeployer,
      //       "IceFrogSale__SaleIsAlreadyExisted"
      //     );
      //   });
      // });

      // describe("setRegistrationTime", () => {
      //   it("should set the registration time", async () => {
      //     const timestamp = (await ethers.provider.getBlock("latest"))
      //       .timestamp;

      //     const saleEnd = timestamp + 100;
      //     const tokensUnlockTime = timestamp + 150;

      //     await icefrogSaleDeployer.setSaleParams(
      //       tokenAddr,
      //       deployer.address,
      //       tokenPriceInETH,
      //       amountOfTokensToSell,
      //       saleEnd,
      //       tokensUnlockTime,
      //       PORTION_VESTING_PRECISION,
      //       maxParticipation
      //     );

      //     const registrationTimeStarts =
      //       timestamp + REGISTRATION_TIME_STARTS_DELTA;
      //     const registrationTimeEnds = timestamp + REGISTRATION_TIME_ENDS_DELTA;

      //     await icefrogSaleDeployer.setRegistrationTime(
      //       registrationTimeStarts,
      //       registrationTimeEnds
      //     );

      //     const reg = await icefrogSaleDeployer.getRegistration();

      //     assert.equal(reg.registrationTimeStarts, registrationTimeStarts);
      //     assert.equal(reg.registrationTimeEnds, registrationTimeEnds);
      //   });

      //   it("should emit RegistrationTimeSet when setting registration time", async () => {
      //     const timestamp = (await ethers.provider.getBlock("latest"))
      //       .timestamp;

      //     const saleEnd = timestamp + 100;
      //     const tokensUnlockTime = timestamp + 150;

      //     await icefrogSaleDeployer.setSaleParams(
      //       tokenAddr,
      //       deployer.address,
      //       tokenPriceInETH,
      //       amountOfTokensToSell,
      //       saleEnd,
      //       tokensUnlockTime,
      //       PORTION_VESTING_PRECISION,
      //       maxParticipation
      //     );

      //     const registrationTimeStarts =
      //       timestamp + REGISTRATION_TIME_STARTS_DELTA;
      //     const registrationTimeEnds = timestamp + REGISTRATION_TIME_ENDS_DELTA;

      //     await expect(
      //       icefrogSaleDeployer.setRegistrationTime(
      //         registrationTimeStarts,
      //         registrationTimeEnds
      //       )
      //     )
      //       // @ts-ignore
      //       .to.emit(icefrogSaleDeployer, "RegistrationTimeSet")
      //       .withArgs(registrationTimeStarts, registrationTimeEnds);

      //     // await icefrogSaleDeployer.setRegistrationTime(
      //     //   registrationTimeStarts,
      //     //   registrationTimeEnds
      //     // );

      //     // const reg = await icefrogSaleDeployer.getRegistration();

      //     // assert.equal(reg.registrationTimeStarts, registrationTimeStarts);
      //     // assert.equal(reg.registrationTimeEnds, registrationTimeEnds);
      //   });

      //   it("should not set registration times twice", async () => {
      //     const timestamp = (await ethers.provider.getBlock("latest"))
      //       .timestamp;

      //     const saleEnd = timestamp + 100;
      //     const tokensUnlockTime = timestamp + 150;

      //     await icefrogSaleDeployer.setSaleParams(
      //       tokenAddr,
      //       deployer.address,
      //       tokenPriceInETH,
      //       amountOfTokensToSell,
      //       saleEnd,
      //       tokensUnlockTime,
      //       PORTION_VESTING_PRECISION,
      //       maxParticipation
      //     );

      //     const registrationTimeStarts =
      //       timestamp + REGISTRATION_TIME_STARTS_DELTA;
      //     const registrationTimeEnds = timestamp + REGISTRATION_TIME_ENDS_DELTA;

      //     await icefrogSaleDeployer.setRegistrationTime(
      //       registrationTimeStarts,
      //       registrationTimeEnds
      //     );

      //     await expect(
      //       icefrogSaleDeployer.setRegistrationTime(
      //         registrationTimeStarts,
      //         registrationTimeEnds
      //       )
      //       // @ts-ignore
      //     ).to.be.revertedWithCustomError(
      //       icefrogSaleDeployer,
      //       "IceFrogSale__ThisFuncCanOnlyBeCalledOnce"
      //     );
      //   });
      // });

      // describe("depositTokens", () => {
      //   it("should allow sale owner to deposit tokens", async () => {
      //     const timestamp = (await ethers.provider.getBlock("latest"))
      //       .timestamp;

      //     const saleEnd = timestamp + 100;
      //     const tokensUnlockTime = timestamp + 150;

      //     await icefrogSaleDeployer.setSaleParams(
      //       tokenAddr,
      //       userProjectParty.address,
      //       tokenPriceInETH,
      //       amountOfTokensToSell,
      //       saleEnd,
      //       tokensUnlockTime,
      //       PORTION_VESTING_PRECISION,
      //       maxParticipation
      //     );

      //     const registrationTimeStarts =
      //       timestamp + REGISTRATION_TIME_STARTS_DELTA;
      //     const registrationTimeEnds = timestamp + REGISTRATION_TIME_ENDS_DELTA;

      //     await icefrogSaleDeployer.setRegistrationTime(
      //       registrationTimeStarts,
      //       registrationTimeEnds
      //     );

      //     const saleStartTime = timestamp + SALE_START_DELTA;
      //     await icefrogSaleDeployer.setSaleStart(saleStartTime);

      //     await icefrogDeployer.transfer(
      //       userProjectParty.address,
      //       5000000000000000000000n // 5000 * 10 ** 18
      //     );
      //     const icefrogUserPj = icefrogDeployer.connect(userProjectParty);

      //     await icefrogUserPj.approve(
      //       icefrogSaleDeployer.target,
      //       amountOfTokensToSell
      //     );

      //     const icefrogSaleUserPj =
      //       icefrogSaleDeployer.connect(userProjectParty);

      //     await icefrogSaleUserPj.depositTokens();

      //     const balance = await icefrogUserPj.balanceOf(
      //       icefrogSaleUserPj.target
      //     );

      //     assert(balance, amountOfTokensToSell.toString());
      //   });
      //   it("should not allow non-sale owner to deposit tokens", async () => {
      //     const timestamp = (await ethers.provider.getBlock("latest"))
      //       .timestamp;

      //     const saleEnd = timestamp + 100;
      //     const tokensUnlockTime = timestamp + 150;

      //     await icefrogSaleDeployer.setSaleParams(
      //       tokenAddr,
      //       userProjectParty.address,
      //       tokenPriceInETH,
      //       amountOfTokensToSell,
      //       saleEnd,
      //       tokensUnlockTime,
      //       PORTION_VESTING_PRECISION,
      //       maxParticipation
      //     );

      //     const registrationTimeStarts =
      //       timestamp + REGISTRATION_TIME_STARTS_DELTA;
      //     const registrationTimeEnds = timestamp + REGISTRATION_TIME_ENDS_DELTA;

      //     await icefrogSaleDeployer.setRegistrationTime(
      //       registrationTimeStarts,
      //       registrationTimeEnds
      //     );

      //     const saleStartTime = timestamp + SALE_START_DELTA;
      //     await icefrogSaleDeployer.setSaleStart(saleStartTime);

      //     await icefrogDeployer.approve(
      //       icefrogSaleDeployer.target,
      //       amountOfTokensToSell
      //     );

      //     await expect(
      //       icefrogSaleDeployer.depositTokens()
      //       // @ts-ignore
      //     ).to.be.revertedWithCustomError(
      //       icefrogSaleDeployer,
      //       "IceFrogSale__OnlyCallBySaleOwner"
      //     );
      //   });
      // });

      describe("registerForSale", () => {
        it("should register for sale", async () => {
          const timestamp = (await ethers.provider.getBlock("latest"))
            .timestamp;

          const saleEnd = timestamp + 100;
          const tokensUnlockTime = timestamp + 150;

          await icefrogSaleDeployer.setSaleParams(
            tokenAddr,
            userProjectParty.address,
            tokenPriceInETH,
            amountOfTokensToSell,
            saleEnd,
            tokensUnlockTime,
            PORTION_VESTING_PRECISION,
            maxParticipation
          );

          const registrationTimeStarts =
            timestamp + REGISTRATION_TIME_STARTS_DELTA;
          const registrationTimeEnds = timestamp + REGISTRATION_TIME_ENDS_DELTA;

          await icefrogSaleDeployer.setRegistrationTime(
            registrationTimeStarts,
            registrationTimeEnds
          );

          const saleStartTime = timestamp + SALE_START_DELTA;
          await icefrogSaleDeployer.setSaleStart(saleStartTime);

          assert.equal(
            await icefrogSaleDeployer.getNumberOfRegisteredUsers(),
            0n
          );

          // console.log(`deployer: ${deployer.address}`);
          // console.log(`userInvestor: ${userInvestor.address}`);

          const privateKey = Buffer.from(deployerPrivateKey.slice(2), "hex");
          const sig = signRegistration(
            userInvestor.address,
            icefrogSaleDeployer.target as string,
            privateKey
          );

          await ethers.provider.send("evm_increaseTime", [10]);
          await ethers.provider.send("evm_mine", []);

          const icefrogSaleUserInvestor =
            icefrogSaleDeployer.connect(userInvestor);
          await icefrogSaleUserInvestor.registerForSale(sig, 0);
          assert.equal(
            await icefrogSaleUserInvestor.getNumberOfRegisteredUsers(),
            1n
          );
        });
        // it("should not register after registration ends", async () => {
        //   const timestamp = (await ethers.provider.getBlock("latest"))
        //     .timestamp;

        //   const saleEnd = timestamp + 100;
        //   const tokensUnlockTime = timestamp + 150;

        //   await icefrogSaleDeployer.setSaleParams(
        //     tokenAddr,
        //     userProjectParty.address,
        //     tokenPriceInETH,
        //     amountOfTokensToSell,
        //     saleEnd,
        //     tokensUnlockTime,
        //     PORTION_VESTING_PRECISION,
        //     maxParticipation
        //   );

        //   const registrationTimeStarts =
        //     timestamp + REGISTRATION_TIME_STARTS_DELTA;
        //   const registrationTimeEnds = timestamp + REGISTRATION_TIME_ENDS_DELTA;

        //   await icefrogSaleDeployer.setRegistrationTime(
        //     registrationTimeStarts,
        //     registrationTimeEnds
        //   );

        //   const saleStartTime = timestamp + SALE_START_DELTA;
        //   await icefrogSaleDeployer.setSaleStart(saleStartTime);

        //   assert.equal(
        //     await icefrogSaleDeployer.getNumberOfRegisteredUsers(),
        //     0n
        //   );

        //   const privateKey = Buffer.from(deployerPrivateKey.slice(2), "hex");
        //   const sig = signRegistration(
        //     userInvestor.address,
        //     icefrogSaleDeployer.target as string,
        //     privateKey
        //   );

        //   await ethers.provider.send("evm_increaseTime", [41]);
        //   await ethers.provider.send("evm_mine", []);

        //   const icefrogSaleUserInvestor =
        //     icefrogSaleDeployer.connect(userInvestor);
        //   await expect(
        //     icefrogSaleUserInvestor.registerForSale(sig, 0)
        //     // @ts-ignore
        //   ).to.be.revertedWithCustomError(
        //     icefrogSaleUserInvestor,
        //     "IceFrogSale__NonRegistrationTime"
        //   );
        // });
      });

      // describe("check participation signature", () => {
      //   it("should succeed for valid signature", async () => {
      //     const privateKey = Buffer.from(deployerPrivateKey.slice(2), "hex");
      //     const sig = signParticipation(
      //       userInvestor.address,
      //       100n,
      //       icefrogSaleDeployer.target as string,
      //       privateKey
      //     );
      //     assert.equal(
      //       await icefrogSaleDeployer.checkParticipationSignature(
      //         sig,
      //         userInvestor.address,
      //         100
      //       ),
      //       true
      //     );
      //   });
      //   it("should fail if signature is for a different user", async () => {
      //     const privateKey = Buffer.from(deployerPrivateKey.slice(2), "hex");
      //     const sig = signParticipation(
      //       userInvestor.address,
      //       100n,
      //       icefrogSaleDeployer.target as string,
      //       privateKey
      //     );
      //     assert.equal(
      //       await icefrogSaleDeployer.checkParticipationSignature(
      //         sig,
      //         userProjectParty.address,
      //         100
      //       ),
      //       false
      //     );
      //   });
      // });
    })
  : describe.skip;
