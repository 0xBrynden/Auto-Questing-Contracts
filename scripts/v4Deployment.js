const { ethers } = require("hardhat")
const { BigNumber } = require("ethers")
const { parseEther, parseUnits, formatEther, hexDataSlice } = require('ethers/lib/utils');
require('dotenv').config();

// harmony URL provider
const URL = process.env.HARMONY_MAINNET;
const provider = new ethers.providers.StaticJsonRpcProvider(URL, 1666600000);

// signer
const deployer = (new ethers.Wallet(process.env.PRIVATE_KEY_DEPLOYER)).connect(provider);
const bot = (new ethers.Wallet(process.env.PRIVATE_KEY_BOT)).connect(provider);

// ======================================

async function deployMigrationEscrow(questerMainAddress) {
	const MigEscrFactoryFactory = await ethers.getContractFactory('MigrationEscrowFactory');
	const migrationFactory = await MigEscrFactoryFactory.connect(deployer).deploy(questerMainAddress);
	console.log("migrationFactory.address = ", migrationFactory.address);
	return migrationFactory;
}

async function deployMain(govTokenAddress, baseAddress) {
	const MainFactory = await ethers.getContractFactory('QuesterMain');
	const main = await MainFactory.connect(deployer).deploy(govTokenAddress, baseAddress);
	console.log("main.address = ", main.address);
	return main;
}

async function deployBranchBase() {
	const BaseBranch = await ethers.getContractFactory('QuesterBranch');
	const base = await BaseBranch.connect(deployer).deploy();
	console.log("base.address = ", base.address);
	return base;
}

async function deployBurnedOwner() {
	const BurnedOwner = await ethers.getContractFactory('BurnedOwner');
	const burnedOwner = await BurnedOwner.connect(deployer).deploy();
	console.log("burnedOwner.address = ", burnedOwner.address);
	return burnedOwner;
}

// ======================================

async function deployAndSetAll() {
	
	let base = await deployBranchBase();
	let heroScoreAddr = '0xE2fBADf6F4B2e9f2754f69e5Ef5d8d2A49722494';
	let govToken = await ethers.getContractAt("GovToken", '0x85d63e6C02E3275C5429B3491BaB5d5594D85f12');
	let questerMain = await deployMain(govToken.address, base.address);
	let migrationFactory = await deployMigrationEscrow(questerMain.address);
	
	// set stuff
	
	// main can mint govtoken
	await (await govToken.connect(deployer).setMinter(questerMain.address, true)).wait();
	
	// set stuff in main
	await (await questerMain.connect(deployer).changeBot(bot.address)).wait();
	await (await questerMain.connect(deployer).changeHeroScore(heroScoreAddr)).wait();
	await (await questerMain.connect(deployer).changeEscrowFactory(migrationFactory.address)).wait();
	for (let i=0; i<10; i++) {
		const name = "SG_branch4_" + i;
		const receipt = await (await questerMain.connect(bot).createBranch(name)).wait();
		console.log("receipt == ", receipt);
	}
}

//deployAndSetAll();

// remember to move locked tokens before!
// also any other tokens !!!
async function moveOutFromV3() {
	let oldQuesterMain = await ethers.getContractAt("QuesterMain", '0xD8c9802cedb63C827B797bf5EA18eb7aE7adC160');
	
	// burn bot
	const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000"
	await (await oldQuesterMain.connect(deployer).changeBot(ZERO_ADDRESS)).wait();
	
	// pause - not needed (blocks claiming)
	// await (await oldQuesterMain.connect(deployer).setPaused(true)).wait();
	
	// burn ownership
	const burnedOwner = await deployBurnedOwner();
	await (await oldQuesterMain.connect(deployer).proposeOwnership(burnedOwner.address)).wait();
	await (await burnedOwner.connect(deployer).acceptOwnership(oldQuesterMain.address)).wait();
	console.log("Burned governance in Old Main Quester");
}

//moveOutFromV3()