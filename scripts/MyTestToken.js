const { ethers } = require("hardhat");

async function main() {
  // Hardhat always runs the compile task when running scripts with its command
  // line interface.
  //
  // If this script is run directly using `node` you may want to call compile
  // manually to make sure everything is compiled
  // await hre.run('compile');

  // We get the contract to deploy
  const MyTestToken = await ethers.getContractFactory("MyTestToken");
  const myTestToken = await MyTestToken.deploy(1000);

  await myTestToken.deployed(10000);

  await myTestToken.functions.mint(100000);

  console.log("MyTestToken deployed to:", myTestToken.address);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
