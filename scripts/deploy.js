const { ethers } = require("hardhat");

async function main() {
  const Icosa = await ethers.getContractFactory("Icosa");
  const icsoa = await icosa.deploy();
  await icosa.deployed()

  console.log("Icosa deployed to:", icsoa.address);
  console.log("WAATSA deployed to:", await icosa.waatsa());
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });