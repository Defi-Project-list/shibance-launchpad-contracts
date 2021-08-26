const IDOVault = artifacts.require("IDOVault");
const IDOMaster = artifacts.require("IDOMaster");

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

module.exports = async function (deployer, network, accounts) {
  console.log('WOOF=', WOOF);
  console.log('DoggyPound=', DoggyPound);
  console.log('MasterBoi=', MasterBoi);
  console.log('Admin=', Admin);
  console.log('Treasury=', Treasury);

  await deployer.deploy(IDOVault, WOOF, DoggyPound, MasterBoi, Admin, Treasury);
  const idoVault = await IDOVault.deployed();
  console.log('Deployed IDOVault=', idoVault.address);

  await deployer.deploy(IDOMaster,
    Admin,
    idoVault.address,
    xWoofForBasic,
    xWoofForPremium,
    xWoofForElite,
    xWoofForRoyal,
    xWoofForDivine);
  const idoMaster = await IDOMaster.deployed();
  console.log('Deployed IDOMaster=', idoMaster.address);
};