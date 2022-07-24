const { ethers } = require("hardhat");

async function main() {
  const Icosa = await ethers.getContractFactory("Icosa");
  const icosa = await Icosa.deploy();
  await icosa.deployed()

  console.log("Icosa deployed to:", icosa.address);
  console.log("WAATSA deployed to:", await icosa.waatsa());
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });