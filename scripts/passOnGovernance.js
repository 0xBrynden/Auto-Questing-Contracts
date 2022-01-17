const { ethers } = require("hardhat")
const { BigNumber } = require("ethers")
const { parseEther, parseUnits, formatEther, hexDataSlice } = require('ethers/lib/utils');
require('dotenv').config();

// harmony URL provider
const URL = process.env.HARMONY_MAINNET;
const provider = new ethers.providers.JsonRpcProvider(URL);

// signer
const deployer = (new ethers.Wallet(process.env.PRIVATE_KEY_DEPLOYER)).connect(provider);
const bot = (new ethers.Wallet(process.env.PRIVATE_KEY_BOT)).connect(provider);

// constants
const delay = 86400 + 1   // for the timelock

// addresses (TODO)
let heroScoreAddress;
let govTokenAddress;
let questerMainAddress;
let migrationFactoryAddress;
// for part2 (TODO)
let governanceAddress;

async function main_pt1() {
    // deploy timelock
    const Timelock = await ethers.getContractFactory('Timelock');
    const timelock = await Timelock.connect(deployer).deploy(deployer.address, delay)
    console.log("timelock.address = ", timelock.address)
    
    // deploy governance
    const Governace = await ethers.getContractFactory('Governance');
    const governance = await Governace.connect(deployer).deploy(
        timelock.address,
        govTokenAddress,
        deployer.address,
    );
    console.log("governance.address = ", governance.address)
    
    // change timelock admin to be governance
    await (await timelock.connect(deployer).setPendingAdmin(governance.address)).wait()
    console.log("setPendingAdmin done.")
    await (await governance.connect(deployer).__acceptAdmin()).wait()
    console.log("__acceptAdmin done.")
    
    // change governance quorum
    // do nothing -- it's ok to be zero at the start
    
    // change proposal threshold
    await (await governance.connect(deployer).setProposalThreshold(parseEther('10000'))).wait()
    console.log("setProposalThreshold done.")
    
    // set stuff
    
    // change govToken governance
    const govToken = await ethers.getContractAt("GovToken", govTokenAddress);
    await (await govToken.connect(deployer).changeGovernance(timelock.address)).wait();
    
    // change questerMain governance
    const questerMain = await ethers.getContractAt("QuesterMain", questerMainAddress);
    await (await questerMain.connect(deployer).proposeOwnership(timelock.address)).wait();
    // ... timelock needs to `acceptOwnership()`
    
    // make proposal
    const calldata = questerMain.interface.encodeFunctionData("acceptOwnership", [])
    const tx = await governance.connect(deployer).propose(
        [questerMain.address],
        [0],
        [""], // signature inside calldata
        [calldata],
        "Accept Ownership"
    )
    await tx.wait();
}

// queue after voting period
async function main_pt2() {
    const governance = await ethers.getContractAt("Governace", governanceAddress);
    const tx = await governance.connect(deployer).queue(1);  // assuming first proposal
    await tx.wait();
}

// execute after timelock
async function main_pt3() {
    const governance = await ethers.getContractAt("Governace", governanceAddress);
    const tx = await governance.connect(deployer).execute(1);  // idem
    await tx.wait();
}

//main_pt1();
//main_pt2();
//main_pt3();