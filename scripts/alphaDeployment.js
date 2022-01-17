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

// ======================================

async function deployHeroScore() {
	const HeroScoreFactory = await ethers.getContractFactory('HeroScore');
	const heroScore = await HeroScoreFactory.connect(deployer).deploy();
	console.log("heroScore.address = ", heroScore.address);
	return heroScore;
}

// governance = deployer for now
async function deployGovToken() {
	const GovTokenFactory = await ethers.getContractFactory('GovToken');
	const govToken = await GovTokenFactory.connect(deployer).deploy(deployer.address);
	console.log("govToken.address = ", govToken.address);
	return govToken;
}

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

// ======================================

async function deployAndSetAll() {
	let heroScore, govToken, base, questerMain, migrationFactory;
	
	base = await deployBranchBase();
	heroScore = await deployHeroScore();
	govToken = await deployGovToken();
	questerMain = await deployMain(govToken.address, base.address);
	migrationFactory = await deployMigrationEscrow(questerMain.address);
	
	// set stuff
	
	// main can mint govtoken
	await (await govToken.connect(deployer).setMinter(questerMain.address, true)).wait();
	
	// change parameters in heroScore
	await (await heroScore.connect(deployer).changeParameters(
		{
	    	A_mnr: parseEther("0.01"),
	    	A_grd: parseEther("0.01"),
	    	A_fsh: parseEther("0.01"),
	    	A_frg: parseEther("0.01"),
	    	B_mnr: parseEther("1"),
	    	B_no_mnr: parseEther("0.01"),
	    }
	)).wait();
	
	// set stuff in main
	await (await questerMain.connect(deployer).changeBot(bot.address)).wait();
	await (await questerMain.connect(deployer).changeHeroScore(heroScore.address)).wait();
	await (await questerMain.connect(deployer).changeEscrowFactory(migrationFactory.address)).wait();
	for (let i=0; i<10; i++) {
		const name = "SG_branch3_" + i;
		const receipt = await (await questerMain.connect(bot).createBranch(name)).wait();
		console.log("receipt == ", receipt);
	}
}

deployAndSetAll();