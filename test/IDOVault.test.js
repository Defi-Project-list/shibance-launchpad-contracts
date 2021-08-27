const { time } = require('@openzeppelin/test-helpers');
const { assert, expect } = require('chai');
const { ethers } = require("hardhat");

describe('IDOVault', () => {

  let whale;
  let big;
  let small;
  let addrs;

  beforeEach(async () => {
    [whale, big, small, ...addrs] = await ethers.getSigners();

    const WoofToken = await ethers.getContractFactory("WoofToken", whale);
    const DoggyPound = await ethers.getContractFactory("DoggyPound", whale);
    const IDOVault = await ethers.getContractFactory("IDOVault", whale);
    const MasterBoi = await ethers.getContractFactory("MasterBoi", whale);

    this.woof = await WoofToken.deploy();
    await this.woof.deployed();

    await this.woof.mint(whale.address, 1000000);
    await this.woof.mint(big.address, 1000000);
    await this.woof.mint(small.address, 1000000);

    this.doggyPound = await DoggyPound.deploy(this.woof.address);
    await this.doggyPound.deployed();

    this.masterBoi = await MasterBoi.deploy(
      this.woof.address,
      this.doggyPound.address,
      whale.address,
      1000,
      10,
      0 // multiplier
    );
    await this.masterBoi.deployed();
    await this.woof.connect(whale).transferOwnership(this.masterBoi.address);
    await this.doggyPound.connect(whale).transferOwnership(this.masterBoi.address);

    this.idoVault = await IDOVault.deploy(
      this.woof.address,
      this.doggyPound.address,
      this.masterBoi.address,
      whale.address,
      whale.address
    );
    await this.idoVault.deployed();
  });

  it("stake/check locking", async () => {
    /// stake
    await this.woof.connect(big).approve(this.idoVault.address, 10);
    await this.idoVault.connect(big).stake(10, 10); // stake & lock 10 busd, 10 seconds

    // idoVault will have empty balance
    expect(await this.woof.balanceOf(this.idoVault.address)).to.equal(0);
    // masterBoi will have an balance
    expect(await this.woof.balanceOf(big.address)).to.equal(1000000 - 10);
    expect(await this.woof.balanceOf(this.masterBoi.address)).to.equal(10);

    /// try unstake for locked staking
    await expect(this.idoVault.connect(big).unstakeAll()).
      to.be.revertedWith('Not available for locked staking');
  });

  it("stake/unstake", async () => {
    /// stake
    await this.woof.connect(big).approve(this.idoVault.address, 10);
    await this.idoVault.connect(big).stake(10, 10); // stake & lock 10 busd, 10 seconds

    // idoVault will have empty balance
    expect(await this.woof.balanceOf(this.idoVault.address)).to.equal(0);
    // masterBoi will have an balance
    expect(await this.woof.balanceOf(big.address)).to.equal(1000000 - 10);
    expect(await this.woof.balanceOf(this.masterBoi.address)).to.equal(10);

    expect((await this.idoVault.connect(big).getStakeAmount()).toString()).to.equal('10000000000000000000'); // 10* 10**18

    console.log('listing userinfo');
    const {
      shares, xWOOF, lastDepositedTime, cakeAtLastUserAction, lockTime, unlockTime
    } = await this.idoVault.getUserInfo(big.address);

    /// pass 10 seconds
    await ethers.provider.send('evm_increaseTime', [10]);
    await ethers.provider.send('evm_mine');

    /// unstake
    await this.idoVault.connect(big).unstake(shares);

    expect(await this.woof.balanceOf(big.address)).to.equal(1000000);
    expect(await this.woof.balanceOf(this.idoVault.address)).to.equal(0);
    expect(await this.woof.balanceOf(this.masterBoi.address)).to.equal(0);
  });

  it('restake', async () => {
    /// stake
    await this.woof.connect(big).approve(this.idoVault.address, 10);
    await this.idoVault.connect(big).stake(10, 30); // 30 seconds
    // idoVault will have empty balance
    expect(await this.woof.balanceOf(this.idoVault.address)).to.equal(0);
    // masterBoi will have an balance
    expect(await this.woof.balanceOf(big.address)).to.equal(1000000 - 10);
    expect(await this.woof.balanceOf(this.masterBoi.address)).to.equal(10);

    /// pass 20 seconds
    await ethers.provider.send('evm_increaseTime', [20]);
    await ethers.provider.send('evm_mine');
    
    /// restake
    await this.idoVault.connect(big).restake(20);
    {
      const {
        unlockTime
      } = await this.idoVault.getUserInfo(big.address);
  
      let blockcNumber = await ethers.provider.getBlockNumber();
      let block = await ethers.provider.getBlock(blockcNumber);
  
      expect(unlockTime).to.equal(block.timestamp + 20);
    }

    /// pass 10 seconds
    await ethers.provider.send('evm_increaseTime', [10]);
    await ethers.provider.send('evm_mine');
    
    {
      const {
        unlockTime
      } = await this.idoVault.getUserInfo(big.address);
      
      let blockcNumber = await ethers.provider.getBlockNumber();
      let block = await ethers.provider.getBlock(blockcNumber);
  
      expect(unlockTime).to.equal(block.timestamp + 10); 
    }

    /// try unstake for locked staking
    await expect(this.idoVault.connect(big).unstakeAll()).
      to.be.revertedWith('Not available for locked staking');

    /// pass 10 seconds
    await ethers.provider.send('evm_increaseTime', [10]);
    await ethers.provider.send('evm_mine');

    {
      const {
        shares, xWOOF, lastDepositedTime, cakeAtLastUserAction, lockTime, unlockTime
      } = await this.idoVault.getUserInfo(big.address);
  
      /// unstake
      await this.idoVault.connect(big).unstake(shares);
  
      expect(await this.woof.balanceOf(big.address)).to.equal(1000000);
      expect(await this.woof.balanceOf(this.idoVault.address)).to.equal(0);
      expect(await this.woof.balanceOf(this.masterBoi.address)).to.equal(0);
    }
  });
})
