const { expect } = require("chai");
const { ethers } = require("hardhat");
const { erc20Abi } = require("./abi/erc20");
const { hexAbi } = require("./abi/hex");
const { hsimAbi } = require("./abi/hsim")
const { hsiAbi } = require("./abi/hsi");

describe("Icosa", function () {
  let hex
  let hedron;
  let hsim
  let icosa;

  let sa;
  let oa;

  const millionHex  = ethers.BigNumber.from("100000000000000");
  const billionHdrn = ethers.BigNumber.from("1000000000000000000");
  
  it("Should pass 'We Are All the SA' sanity checks", async function () {
    const Icosa = await ethers.getContractFactory("Icosa");
    icosa = await Icosa.deploy();
    await icosa.deployed();

    hex    = await ethers.getContractAt(hexAbi, '0x2b591e99afE9f32eAA6214f7B7629768c40Eeb39');
    hedron = await ethers.getContractAt(erc20Abi, '0x3819f64f282bf135d62168C1e513280dAF905e06');
    hsim   = await ethers.getContractAt(hsimAbi, '0x8BD3d1472A656e312E94fB1BbdD599B8C51D18e3');

    // impersonate Hedron SA
    await hre.network.provider.request({
      method: "hardhat_impersonateAccount",
      params: ["0x9d73ced2e36c89e5d167151809eee218a189f801"],
    });

    // give SA some ETH
    await network.provider.send("hardhat_setBalance", [
      "0x9d73ced2e36c89e5d167151809eee218a189f801",
      "0x3635C9ADC5DEA00000",
    ]);

    sa = await ethers.getSigner("0x9d73ced2e36c89e5d167151809eee218a189f801");


    // impersonate HEX OA
    await hre.network.provider.request({
      method: "hardhat_impersonateAccount",
      params: ["0x9A6a414D6F3497c05E3b1De90520765fA1E07c03"],
    });

    // give OA some ETH
    await network.provider.send("hardhat_setBalance", [
      "0x9A6a414D6F3497c05E3b1De90520765fA1E07c03",
      "0x3635C9ADC5DEA00000",
    ]);

    oa = await ethers.getSigner("0x9A6a414D6F3497c05E3b1De90520765fA1E07c03");

    // test WAATSA entry
    await hedron.connect(sa).approve(icosa.address, billionHdrn);
    let stakePointsExpected = await icosa.connect(sa).callStatic.nftStakeStart(billionHdrn, hedron.address)
    await icosa.connect(sa).nftStakeStart(billionHdrn, hedron.address);
    let stake = await icosa.nftStakes(1);
    expect(stake.stakePoints).equals(stakePointsExpected);

    // ending on the same day should result in no payout.
    await ethers.provider.send('evm_mine');
    expect(await icosa.connect(sa).callStatic.nftStakeEnd(1)).equals(0);

    // ending one day later should result in a payout.
    await network.provider.send("evm_increaseTime", [86400]);
    await ethers.provider.send('evm_mine');
    let payoutDay1 = await icosa.connect(sa).callStatic.nftStakeEnd(1);
    expect(payoutDay1).gt(0);

    // ending two days later should result in roughly double day1 payout
    await network.provider.send("evm_increaseTime", [86400])
    await ethers.provider.send('evm_mine');
    expect(await icosa.connect(sa).callStatic.nftStakeEnd(1)).to.be.closeTo(payoutDay1.mul(2), 1);

    // end the stake move to last day of WAATSA, start a new one.
    await icosa.connect(sa).nftStakeEnd(1);
    await network.provider.send("evm_increaseTime", [950400])
    await ethers.provider.send('evm_mine');
    await hedron.connect(sa).approve(icosa.address, billionHdrn);
    await icosa.connect(sa).nftStakeStart(billionHdrn, hedron.address);

    // ending on the same day should result in no payout.
    await ethers.provider.send('evm_mine');
    expect(await icosa.connect(sa).callStatic.nftStakeEnd(2)).equals(0);

    // test other cryptos
    await icosa.connect(sa).nftStakeStart(ethers.utils.parseEther("1.0"), '0x0000000000000000000000000000000000000000', {
      value: ethers.utils.parseEther("1.0")
    });

    // ending one day served should be greater than one day payout due to time skip of 12 days seed liquidity / burning.
    await network.provider.send("evm_increaseTime", [86400])
    await ethers.provider.send('evm_mine');
    expect(await icosa.connect(sa).callStatic.nftStakeEnd(2)).gt(payoutDay1);
    
    await icosa.connect(sa).nftStakeEnd(2);
    await icosa.connect(sa).nftStakeEnd(3);
  });

  it("Should pass Hedron staking sanity checks", async function () {

    // test HDRN entry
    await hedron.connect(sa).approve(icosa.address, billionHdrn);
    let stakePointsExpected = await icosa.connect(sa).callStatic.hdrnStakeStart(billionHdrn);
    await icosa.connect(sa).hdrnStakeStart(billionHdrn);
    let stake = await icosa.hdrnStakes(sa.address);
    expect(stake.stakePoints).equals(stakePointsExpected);

    // trying to make another stake should fail
    await expect(icosa.connect(sa).hdrnStakeStart(billionHdrn)).to.be.revertedWith("ICSA: Stake already exists");

    // ending on the same day should result in no payout.
    await ethers.provider.send('evm_mine');
    let result = await icosa.connect(sa).callStatic.hdrnStakeEnd();
    expect(result[0]).equals(0);

    // ending one day later should result in a payout.
    await network.provider.send("evm_increaseTime", [86400]);
    await ethers.provider.send('evm_mine');
    let payoutDay1 = await icosa.connect(sa).callStatic.hdrnStakeEnd();
    expect(payoutDay1[0]).gt(0);

    // ending two days later should be more than day 1 payout
    await network.provider.send("evm_increaseTime", [86400])
    await ethers.provider.send('evm_mine');
    result = await icosa.connect(sa).callStatic.hdrnStakeEnd()
    expect(result[0]).gt(payoutDay1[0]);

    // end the stake, start a new one, check penalties, then end.
    await icosa.connect(sa).hdrnStakeEnd();
    await hedron.connect(sa).approve(icosa.address, billionHdrn);
    await icosa.connect(sa).hdrnStakeStart(billionHdrn);
    await network.provider.send("evm_increaseTime", [7603200])
    await ethers.provider.send('evm_mine');
    result = await icosa.connect(sa).callStatic.hdrnStakeEnd()
    await network.provider.send("evm_increaseTime", [86400])
    await ethers.provider.send('evm_mine');
    let newResult = await icosa.connect(sa).callStatic.hdrnStakeEnd();
    expect (result[0]).lt(newResult[0]);
    expect (result[1]).gt(newResult[1]);
    expect (result[2].mul(100000).div(result[0].add(result[2]))).gt(newResult[2].mul(100000).div(newResult[0].add(newResult[2])));
    result = newResult;
    await network.provider.send("evm_increaseTime", [86400])
    await ethers.provider.send('evm_mine');
    newResult = await icosa.connect(sa).callStatic.hdrnStakeEnd();
    expect (result[0]).lt(newResult[0]);
    expect (result[1]).gt(newResult[1]);
    expect (result[2].mul(100000).div(result[0].add(result[2]))).gt(newResult[2].mul(100000).div(newResult[0].add(newResult[2])));
    result = newResult

    // add capital and check penalties again, end stake.
    await hedron.connect(sa).approve(icosa.address, billionHdrn);
    await icosa.connect(sa).hdrnStakeAddCapital(billionHdrn);
    newResult = await icosa.connect(sa).callStatic.hdrnStakeEnd();
    expect (result[0]).gt(newResult[0]);
    expect (result[1]).lt(newResult[1]);
    expect (result[2].mul(100000).div(result[0].add(result[2]))).lt(newResult[2].mul(100000).div(newResult[0].add(newResult[2])));
    result = newResult;
    await network.provider.send("evm_increaseTime", [86400])
    await ethers.provider.send('evm_mine');
    newResult = await icosa.connect(sa).callStatic.hdrnStakeEnd();
    expect (result[0]).lt(newResult[0]);
    expect (result[1]).gt(newResult[1]);
    expect (result[2].mul(100000).div(result[0].add(result[2]))).gt(newResult[2].mul(100000).div(newResult[0].add(newResult[2])));
    await icosa.connect(sa).hdrnStakeEnd();

    // double end should fail
    await expect(icosa.connect(sa).hdrnStakeEnd()).to.be.revertedWith("ICSA: Stake does not exist");
  });

  it("Should pass HSI buy-back sanity checks", async function () {

    // create HSI
    await hex.connect(oa).approve(hsim.address, millionHex);
    await hsim.connect(oa).hexStakeStart(millionHex, 5555);
    let hsiAddress = await hsim.hsiLists(oa.address, 0);
    let tokenId = await hsim.connect(oa).callStatic.hexStakeTokenize(0, hsiAddress);
    await hsim.connect(oa).hexStakeTokenize(0, hsiAddress);

    // send HSI to Icosa
    await hsim.connect(oa).approve(icosa.address, tokenId);
    let amount = await icosa.connect(oa).callStatic.hexStakeSell(tokenId);
    let preSellHDRN = await hedron.balanceOf(icosa.address);
    await icosa.connect(oa).hexStakeSell(tokenId);
    let actual = await icosa.balanceOf(oa.address);
    expect(amount).equals(actual);
    let postSaleHDRN = await hedron.balanceOf(icosa.address);
    let saleHDRN = postSaleHDRN - preSellHDRN;
    let hsi = await ethers.getContractAt(hsiAbi, hsiAddress);
    let share = await hsi.share();
    let hexglobals = await hex.globals();
    let borrowable = share.stake.stakeShares * share.stake.stakedDays;
    let icsa = borrowable / hexglobals.shareRate;
    let saleICSA = saleHDRN / hexglobals.shareRate;
    expect(Math.floor(icsa)).equals(Math.floor(saleICSA));
  });

  it("Should pass Icosa staking sanity checks", async function () {

    // test ICSA entry
    let balance = await icosa.balanceOf(sa.address);
    let stakePointsExpected = await icosa.connect(sa).callStatic.icsaStakeStart(balance);
    await icosa.connect(sa).icsaStakeStart(balance);
    let stake = await icosa.icsaStakes(sa.address);
    expect(stake.stakePoints).equals(stakePointsExpected);

    // trying to make another stake should fail
    await expect(icosa.connect(sa).icsaStakeStart(balance)).to.be.revertedWith("ICSA: Stake already exists");

    // ending on the same day should result in no payout.
    await ethers.provider.send('evm_mine');
    let result = await icosa.connect(sa).callStatic.icsaStakeEnd();
    expect(result[0]).equals(0);

    // ending one day later should result in a payout.
    await network.provider.send("evm_increaseTime", [86400]);
    await ethers.provider.send('evm_mine');
    let payoutDay1 = await icosa.connect(sa).callStatic.icsaStakeEnd();
    expect(payoutDay1[0]).gt(0);

    // ending two days later should be more than day 1 payout
    await network.provider.send("evm_increaseTime", [86400])
    await ethers.provider.send('evm_mine');
    result = await icosa.connect(sa).callStatic.icsaStakeEnd()
    expect(result[0]).gt(payoutDay1[0]);

    // end the stake, start a new one, check penalties, then end.
    await icosa.connect(sa).icsaStakeEnd();
    balance = await icosa.balanceOf(sa.address);
    await icosa.connect(sa).icsaStakeStart(Math.floor(balance / 2));
    await network.provider.send("evm_increaseTime", [7603200])
    await ethers.provider.send('evm_mine');
    result = await icosa.connect(sa).callStatic.icsaStakeEnd()
    await network.provider.send("evm_increaseTime", [86400])
    await ethers.provider.send('evm_mine');
    let newResult = await icosa.connect(sa).callStatic.icsaStakeEnd();
    expect (result[0]).lt(newResult[0]);
    expect (result[1]).lt(newResult[1]);
    expect (result[2]).gt(newResult[2]);
    expect (result[3].mul(100000).div(result[0].add(result[3]))).gt(newResult[3].mul(100000).div(newResult[0].add(newResult[3])));
    expect (result[4].mul(100000).div(result[1].add(result[4]))).gt(newResult[4].mul(100000).div(newResult[1].add(newResult[4])));
    result = newResult;
    await network.provider.send("evm_increaseTime", [86400])
    await ethers.provider.send('evm_mine');
    newResult = await icosa.connect(sa).callStatic.icsaStakeEnd();
    expect (result[0]).lt(newResult[0]);
    expect (result[1]).lt(newResult[1]);
    expect (result[2]).gt(newResult[2]);
    expect (result[3].mul(100000).div(result[0].add(result[3]))).gt(newResult[3].mul(100000).div(newResult[0].add(newResult[3])));
    expect (result[4].mul(100000).div(result[1].add(result[4]))).gt(newResult[4].mul(100000).div(newResult[1].add(newResult[4])));
    result = newResult

    // add capital and check penalties again, end stake.
    await icosa.connect(sa).icsaStakeAddCapital(Math.floor(balance / 2));
    newResult = await icosa.connect(sa).callStatic.icsaStakeEnd();
    expect (result[0]).gt(newResult[0]);
    expect (result[1]).gt(newResult[1]);
    expect (result[2]).lt(newResult[2]);
    expect (result[3].mul(100000).div(result[0].add(result[3]))).lt(newResult[3].mul(100000).div(newResult[0].add(newResult[3])));
    expect (result[4].mul(100000).div(result[1].add(result[4]))).lt(newResult[4].mul(100000).div(newResult[1].add(newResult[4])));
    result = newResult;
    await network.provider.send("evm_increaseTime", [86400])
    await ethers.provider.send('evm_mine');
    newResult = await icosa.connect(sa).callStatic.icsaStakeEnd();
    expect (result[0]).lt(newResult[0]);
    expect (result[1]).lt(newResult[1]);
    expect (result[2]).gt(newResult[2]);
    expect (result[3].mul(100000).div(result[0].add(result[3]))).gt(newResult[3].mul(100000).div(newResult[0].add(newResult[3])));
    expect (result[4].mul(100000).div(result[1].add(result[4]))).gt(newResult[4].mul(100000).div(newResult[1].add(newResult[4])));
    await icosa.connect(sa).icsaStakeEnd();

    // double end should fail
    await expect(icosa.connect(sa).icsaStakeEnd()).to.be.revertedWith("ICSA: Stake does not exist");

    await network.provider.send("evm_increaseTime", [86400])
    await ethers.provider.send('evm_mine');

    await icosa.connect(sa).approve(oa.address, 0);

    currentDay = await icosa.currentDay();
    expect (await icosa.hdrnPoolPoints(currentDay)).equals(0);
    expect (await icosa.icsaPoolPoints(currentDay)).equals(0);
    expect (await icosa.nftPoolPoints(currentDay)).equals(0);
  });
});
