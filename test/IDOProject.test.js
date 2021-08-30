const { time } = require('@openzeppelin/test-helpers');
const { expect } = require('chai');
const { ethers } = require("hardhat");

describe('IDOProject', () => {

  let admin;
  let big;
  let small;
  let tiny;
  let dog;
  let cat;
  let addrs;

  beforeEach(async () => {
    [admin, big, small, tiny, dog, cat, ...addrs] = await ethers.getSigners();

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
    this.paper = await PAPER.connect(tiny).deploy("PAPER", "PAPER", 1000000);

    await this.woof.mint(admin.address, 1000000);
    await this.woof.mint(big.address, 1000000);
    await this.woof.mint(small.address, 1000000);
    await this.woof.mint(tiny.address, 1000000);
    await this.woof.mint(dog.address, 1000000);
    await this.woof.mint(cat.address, 1000000);

    await this.busd.transfer(big.address, 100000);
    await this.busd.transfer(small.address, 100000);

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
    
    /// add/update project
    await this.paper.connect(tiny).transfer(this.idoMaster.address, 10000);

    await this.busd.totalSupply();
    // add project
    await this.idoMaster.addProject(
      this.paper.address,
      this.busd.address,
      0,
      10000,
      1000,
      tiny.address,
    );
    const idoProjectAddr = await this.idoMaster.project(1);
    const IDOProject = await ethers.getContractFactory("IDOProject");
    this.idoProject = IDOProject.attach(idoProjectAddr);

    const balances = await this.idoProject.getProjectBalance();
    expect(balances[0]).to.equal(10000); // total supply
    expect(balances[1]).to.equal(0); // total claimed

    let blockNumber = await ethers.provider.getBlockNumber();
    let block = await ethers.provider.getBlock(blockNumber);
    let blockTimestamp = block.timestamp;

    const snapshotTime = blockTimestamp + 100; // add 100 seconds
    const userContributionTime = snapshotTime + 100; // add 100 seconds
    const overflowTime1 = userContributionTime + 100; // add 100 seconds
    const overflowTime2 = overflowTime1 + 100; // add 100 seconds
    const generalSaleTime = overflowTime2 + 100; // add 100 seconds
    const distributionTime = generalSaleTime + 100; // add 100 seconds

    // update project
    await this.idoMaster.updateProject(
      1, // pid
      this.busd.address, // contribution token
      0, // contributionTokenDecimal
      100, // minContributionAmount
      1000, // softCaps
      1, // ratePerContributionToken
      snapshotTime,
      userContributionTime,
      overflowTime1,
      overflowTime2,
      generalSaleTime,
      distributionTime
    );

    const times = await this.idoProject.getProjectTimes();

    expect(times[0]).to.equal(snapshotTime);
    expect(times[1]).to.equal(userContributionTime);
    expect(times[2]).to.equal(overflowTime1);
    expect(times[3]).to.equal(overflowTime2);
    expect(times[4]).to.equal(generalSaleTime);
    expect(times[5]).to.equal(distributionTime);
  });

  it("takeSnapshotAndAllocate", async() => {
    // stake
    await this.woof.connect(big).approve(this.idoVault.address, 10);
    await this.idoVault.connect(big).stake(10, 100);

    await this.woof.connect(small).approve(this.idoVault.address, 20);
    await this.idoVault.connect(small).stake(20, 100);

    await this.woof.connect(tiny).approve(this.idoVault.address, 30);
    await this.idoVault.connect(tiny).stake(30, 100);

    await this.woof.connect(dog).approve(this.idoVault.address, 40);
    await this.idoVault.connect(dog).stake(40, 100);

    await this.woof.connect(cat).approve(this.idoVault.address, 50);
    await this.idoVault.connect(cat).stake(50, 100);
    
    // pass to snapshot time
    await ethers.provider.send('evm_increaseTime', [100]);
    await ethers.provider.send('evm_mine');

    await this.idoProject.connect(admin).takeSnapshotAndAllocate(
      [
        2000, // 20%
        2000, // 20%
        2000, // 20%
        2000, // 20%
        2000  // 20%
      ]
    );

    let userInfo = await this.idoProject.getUserInfo(big.address);
    expect(userInfo[0]).to.equal(0); // snapshotAmount

    userInfo = await this.idoProject.getUserInfo(small.address);
    expect(userInfo[0]).to.equal(2000); // snapshotAmount

    userInfo = await this.idoProject.getUserInfo(tiny.address);
    expect(userInfo[0]).to.equal(2000); // snapshotAmount

    userInfo = await this.idoProject.getUserInfo(dog.address);
    expect(userInfo[0]).to.equal(2000); // snapshotAmount

    userInfo = await this.idoProject.getUserInfo(cat.address);
    expect(userInfo[0]).to.equal(2000); // snapshotAmount
  });

  it("kyc user", async() => {
    // stake
    await this.woof.connect(big).approve(this.idoVault.address, 30);
    await this.idoVault.connect(big).stake(30, 100);

    // pass to contribution time
    await ethers.provider.send('evm_increaseTime', [200]);
    await ethers.provider.send('evm_mine');

    await this.busd.connect(big).approve(this.idoProject.address, 200);
    await expect(this.idoProject.connect(big).contributeProject(200)).
      to.be.revertedWith('Only for KYC user');
  });

  it("contribute/returnback", async() => {
    // stake
    await this.woof.connect(big).approve(this.idoVault.address, 30);
    await this.idoVault.connect(big).stake(30, 100);

    // pass to snapshot time & take snapshot
    await ethers.provider.send('evm_increaseTime', [100]);
    await ethers.provider.send('evm_mine');

    await this.idoProject.connect(admin).takeSnapshotAndAllocate(
      [
        2000, // 20%
        2000, // 20%
        2000, // 20%
        2000, // 20%
        2000  // 20%
      ]
    );

    // only can contribute after contribution time
    expect(await this.busd.balanceOf(big.address)).to.equal(100000);
    await this.busd.connect(big).approve(this.idoProject.address, 200);
    await expect(this.idoProject.connect(big).contributeProject(200)).
      to.be.revertedWith('Not a contribution time');
    expect(await this.busd.balanceOf(big.address)).to.equal(100000);

    // pass to contribution time
    await ethers.provider.send('evm_increaseTime', [100]);
    await ethers.provider.send('evm_mine');

    // contribute
    await this.idoProject.connect(big).contributeProject(200);
    expect(await this.busd.balanceOf(big.address)).to.equal(100000 - 200);
    expect(await this.busd.balanceOf(this.idoProject.address)).to.equal(200);

    // pass to next phase
    await ethers.provider.send('evm_increaseTime', [100]);
    await ethers.provider.send('evm_mine');

    // only can claim or return back after distribution time
    await expect(this.idoProject.connect(big).returnBack()).
    to.be.revertedWith('Now is not distribution time');
    await expect(this.idoProject.connect(big).claimTokens()).
    to.be.revertedWith('Now is not distribution time');

    // pass to distribution time
    await ethers.provider.send('evm_increaseTime', [400]);
    await ethers.provider.send('evm_mine');

    // not complete softCaps, all contributions will be returned back
    await expect(this.idoProject.connect(big).claimTokens()).
    to.be.revertedWith('Canceled project');
    await this.idoProject.connect(big).returnBack();
    expect(await this.busd.balanceOf(big.address)).to.equal(100000);
    expect(await this.busd.balanceOf(this.idoProject.address)).to.equal(0);
  });

  it("contribute/claim", async() => {
    // stake
    await this.woof.connect(big).approve(this.idoVault.address, 30);
    await this.idoVault.connect(big).stake(30, 100);
    await this.woof.connect(small).approve(this.idoVault.address, 40);
    await this.idoVault.connect(small).stake(40, 100);

    // pass to snapshot time & take snapshot
    await ethers.provider.send('evm_increaseTime', [100]);
    await ethers.provider.send('evm_mine');

    await this.idoProject.connect(admin).takeSnapshotAndAllocate(
      [
        2000, // 20%
        2000, // 20%
        2000, // 20%
        2000, // 20%
        2000  // 20%
      ]
    );
    
    let userInfo = await this.idoProject.getUserInfo(big.address);
    expect(userInfo[0]).to.equal(2000); // snapshotAmount

    userInfo = await this.idoProject.getUserInfo(small.address);
    expect(userInfo[0]).to.equal(2000); // snapshotAmount

    // pass to contribution time
    await ethers.provider.send('evm_increaseTime', [100]);
    await ethers.provider.send('evm_mine');

    // contribute
    await this.busd.connect(big).approve(this.idoProject.address, 600);
    await this.idoProject.connect(big).contributeProject(600);
    expect(await this.busd.balanceOf(big.address)).to.equal(100000 - 600);
    expect(await this.busd.balanceOf(this.idoProject.address)).to.equal(600);
    await this.busd.connect(small).approve(this.idoProject.address, 400);
    await this.idoProject.connect(small).contributeProject(400);
    expect(await this.busd.balanceOf(small.address)).to.equal(100000 - 400);
    expect(await this.busd.balanceOf(this.idoProject.address)).to.equal(1000);

    // pass to distribution time
    await ethers.provider.send('evm_increaseTime', [400]);
    await ethers.provider.send('evm_mine');

    // claim tokens
    await this.idoProject.connect(big).claimTokens();
    await expect(this.idoProject.connect(big).returnBack()).
    to.be.revertedWith('Not a canceled project');
    expect(await this.busd.balanceOf(this.idoProject.address)).to.equal(1000);
    await this.idoProject.connect(small).claimTokens();

    // settlement with project developer
    await this.idoProject.connect(admin).settlement();
    expect(await this.busd.balanceOf(this.idoProject.address)).to.equal(0);
    expect(await this.busd.balanceOf(tiny.address)).to.equal(1000);

    // maximum buyable amount is snapshotAmount, but maximum claimable amount belongs to contribution amount
    expect(await this.paper.balanceOf(big.address)).to.equal(600);
    expect(await this.paper.balanceOf(small.address)).to.equal(400);
  });
})
