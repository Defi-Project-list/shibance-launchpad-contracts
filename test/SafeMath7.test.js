const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("SafeMath7", function () {
  it("xWOOF", async function () {
    const [...addrs] = await ethers.getSigners();
    const SafeMath7 = await ethers.getContractFactory("SafeMath7");

    this.safeMath7 = await SafeMath7.deploy();
    await this.safeMath7.deployed();

    const ret = await this.safeMath7.pow7(10000, 10);
    expect(ret.toString()).to.equal('12479');
  });
});