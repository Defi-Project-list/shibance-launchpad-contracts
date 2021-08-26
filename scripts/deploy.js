// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
const hre = require("hardhat");

async function main() {
  const WOOF = '0x43eef5BA4899431F7F9D855E9C5Ed06016c8227b';
  const DoggyPound = '0xCBc317eFa8f0b18683C6c1b9e1842BcaCbC46f36';

  const MasterBoi = '0x5559C8a6267b0b1bcDe0005a44db0B1546711B76';

  const Admin = '0xD3b5134fef18b69e1ddB986338F2F80CD043a1AF';
  const Treasury = '0xD3b5134fef18b69e1ddB986338F2F80CD043a1AF';

  const xWoofForBasic = 1;
  const xWoofForPremium = 2;
  const xWoofForElite = 3;
  const xWoofForRoyal = 4;
  const xWoofForDivine = 5;

  // deploy IDOVault
  const IDOVault = await hre.ethers.getContractFactory("IDOVault");
  const idoVault = await IDOVault.deploy(WOOF, DoggyPound, MasterBoi, Admin, Treasury);
  await idoVault.deployed()
  console.log("IDOVault deployed to:", idoVault.address);

  // deploy IDOMaster
  const IDOMaster = await hre.ethers.getContractFactory("IDOMaster");
  const idoMaster = await IDOMaster.deploy(
    Admin,
    idoVault.address,
    xWoofForBasic,
    xWoofForPremium,
    xWoofForElite,
    xWoofForRoyal,
    xWoofForDivine);
  await idoMaster.deployed()
  console.log("IDOMaster deployed to:", idoMaster.address);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
