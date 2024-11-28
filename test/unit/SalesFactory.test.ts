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

// yarn hardhat test test/unit/SalesFactory.test.ts
developmentChains.includes(network.name)
  ? describe("SalesFactory Unit Tests", () => {
      let salesFactoryDeployer: SalesFactory;
      let icefrogDeployer: IceFrog;
      let stakingMiningDeployer: StakingMining;
      let icefrogSaleFactory: IceFrogSale;
      let accounts: HardhatEthersSigner[];
      let deployer: HardhatEthersSigner;

      const chainId = network.config.chainId!;

      beforeEach(async () => {
        accounts = await ethers.getSigners();
        deployer = accounts[0];
        await deployments.fixture(["all"]);

        salesFactoryDeployer = await ethers.getContractAt(
          "SalesFactory",
          (await deployments.get("SalesFactory")).address,
          deployer
        );
      });

      describe("constructor", () => {
        it("the contract owner is the deployer", async () => {
          const owner = await salesFactoryDeployer.owner();
          assert.equal(owner, deployer.address);
        });
        it("should set staking mining contract", async () => {
          stakingMiningDeployer = await ethers.getContractAt(
            "StakingMining",
            (await deployments.get("StakingMining_Proxy")).address,
            deployer
          );
          const stakingMiningAddr =
            await salesFactoryDeployer.getStakingMiningAddr();
          assert.equal(stakingMiningAddr, stakingMiningDeployer.target);
        });
      });

      describe("deploySale", () => {
        it("should deploy sale", async () => {
          await salesFactoryDeployer.deploySale();
          const saleNum = await salesFactoryDeployer.getNumberOfSalesDeployed();
          const saleAddr = await salesFactoryDeployer.getLastDeployedSale();
          assert.equal(saleNum, 1n);
          assert.equal(
            await salesFactoryDeployer.isSaleCreatedThroughFactory(saleAddr),
            true
          );
        });
        it("should emit SaleDeployed event", async () => {
          await expect(salesFactoryDeployer.deploySale())
            // @ts-ignore
            .to.emit(salesFactoryDeployer, "SaleDeployed");
        });
      });

      describe("set sale params", () => {
        it("should set sale owner and token", async () => {
          icefrogSaleFactory = await ethers.getContractFactory("IceFrogSale");
          await salesFactoryDeployer.deploySale();
          const icefrogSale = icefrogSaleFactory.attach(
            await salesFactoryDeployer.getLastDeployedSale()
          ) as IceFrogSale;

          icefrogDeployer = await ethers.getContractAt(
            "IceFrog",
            (await deployments.get("IceFrog")).address,
            deployer
          );

          const timestamp = (await ethers.provider.getBlock("latest"))
            .timestamp;

          await icefrogSale.setSaleParams(
            icefrogDeployer.target,
            deployer.address,
            10,
            10,
            timestamp + 100,
            timestamp + 10,
            100,
            1000000
          );
          const sale = await icefrogSale.sale();

          assert.equal(sale.saleOwner, deployer.address);
          assert.equal(sale.token, icefrogDeployer.target);
        });
      });
    })
  : describe.skip;
