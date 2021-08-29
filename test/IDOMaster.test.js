const { time } = require('@openzeppelin/test-helpers');
const { expect } = require('chai');
const { ethers } = require("hardhat");

describe('IDOMaster', () => {

  let admin;
  let big;
  let small;
  let addrs;

  beforeEach(async () => {
    [admin, big, small, ...addrs] = await ethers.getSigners();

    const WoofToken = await ethers.getContractFactory("WoofToken", admin);
    const DoggyPound = await ethers.getContractFactory("DoggyPound", admin);
    const IDOVault = await ethers.getContractFactory("IDOVault", admin);
    const MasterBoi = await ethers.getContractFactory("MasterBoi", admin);
    const BUSD = await ethers.getContractFactory("MockERC20", admin);
    const PAPER = await ethers.getContractFactory("MockERC20", small);
    const IDOMaster = await ethers.getContractFactory("IDOMaster", admin);

    this.woof = await WoofToken.deploy();
    await this.woof.deployed();
    this.busd = await BUSD.deploy("BUSD", "BUSD", 1000000);
    this.paper = await PAPER.connect(small).deploy("PAPER", "PAPER", 1000000);

    await this.woof.mint(admin.address, 1000000);
    await this.woof.mint(big.address, 1000000);
    await this.woof.mint(small.address, 1000000);

    await this.busd.transfer(big.address, 1000000);

    this.doggyPound = await DoggyPound.deploy(this.woof.address);
    await this.doggyPound.deployed();

    this.masterBoi = await MasterBoi.deploy(
      this.woof.address,
      this.doggyPound.address,
      admin.address,
      1000,
      10,
      0 // multiplier
    );
    await this.masterBoi.deployed();
    await this.woof.connect(admin).transferOwnership(this.masterBoi.address);
    await this.doggyPound.connect(admin).transferOwnership(this.masterBoi.address);

    this.idoVault = await IDOVault.deploy(
      this.woof.address,
      this.doggyPound.address,
      this.masterBoi.address,
      admin.address,
      admin.address
    );
    await this.idoVault.deployed();

    this.idoMaster = await IDOMaster.deploy(
      admin.address,
      this.idoVault.address,
      15, // xWoofForBasic
      25, // xWoofForPremium
      35, // xWoofForElite
      45, // xWoofForRoyal
      55  // xWoofForDivine
    );
    await this.idoMaster.deployed();
  });

  it("add/updateProject", async () => {
    await this.paper.connect(small).transfer(this.idoMaster.address, 10000);

    const totalSupply = await this.busd.totalSupply();
    // add project
    await this.idoMaster.addProject(
      admin.address,
      this.paper.address,
      this.busd.address,
      0,
      10000,
      1000
    )
    const idoProjectAddr = await this.idoMaster.project(1);
    const IDOProject = await ethers.getContractFactory("IDOProject");
    const idoProject = IDOProject.attach(idoProjectAddr);
    const balances = await idoProject.getProjectBalance();
    expect(balances[0]).to.equal(10000); // total supply
    expect(balances[1]).to.equal(0); // total claimed

    let blockcNumber = await ethers.provider.getBlockNumber();
    let block = await ethers.provider.getBlock(blockcNumber);
    let blockTimestamp = block.timestamp;

    const snapshotTime = blockTimestamp + 10; // add 10 seconds
    const userContributionTime = snapshotTime + 10; // add 10 seconds
    const overflowTime1 = userContributionTime + 10; // add 10 seconds
    const overflowTime2 = overflowTime1 + 10; // add 10 seconds
    const generalSaleTime = overflowTime2 + 10; // add 10 seconds
    const distributionTime = generalSaleTime + 10; // add 10 seconds

    // update project
    await this.idoMaster.updateProject(
      1,
      this.busd.address,
      0,
      100,
      1000,
      1,
      snapshotTime,
      userContributionTime,
      overflowTime1,
      overflowTime2,
      generalSaleTime,
      distributionTime
    );

    const times = await idoProject.getProjectTimes();

    expect(times[0]).to.equal(snapshotTime);
    expect(times[1]).to.equal(userContributionTime);
    expect(times[2]).to.equal(overflowTime1);
    expect(times[3]).to.equal(overflowTime2);
    expect(times[4]).to.equal(generalSaleTime);
    expect(times[5]).to.equal(distributionTime);
  });
})
