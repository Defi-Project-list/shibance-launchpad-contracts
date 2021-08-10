const Migrations = artifacts.require("Migrations");
const DogesonRouter = artifacts.require("DogesonRouter");
const DogesonRouter01 = artifacts.require("DogesonRouter01");

// module.exports = function (deployer) {
//   deployer.deploy(Migrations);
// };

module.exports = function (deployer, network, accounts) {
  deployer.deploy(DogesonRouter, process.env.DOGESON_FACTORY_CONTRACT, process.env.WBNB_CONTRACT);
  // deployer.deploy(DogesonRouter01, process.env.DOGESON_FACTORY_CONTRACT, process.env.WBNB_CONTRACT);
};