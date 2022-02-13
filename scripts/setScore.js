const { ethers } = require("hardhat")
const { BigNumber } = require("ethers")
const { parseEther, parseUnits, formatEther, hexDataSlice } = require('ethers/lib/utils');
require('dotenv').config();

// harmony URL provider
const URL = process.env.HARMONY_MAINNET;
let provider = new ethers.providers.StaticJsonRpcProvider(URL, 1666600000);

// signer
const deployer = (new ethers.Wallet(process.env.PRIVATE_KEY_DEPLOYER)).connect(provider);

let heroScoreAddress = "0xE2fBADf6F4B2e9f2754f69e5Ef5d8d2A49722494";

async function setScores() {
	const heroScore = await ethers.getContractAt("HeroScore", heroScoreAddress);
	
	console.log("hey")
	await (await heroScore.connect(deployer).changeParameters(
		{
	    	A_mnr: parseEther("0.10"),
	    	A_grd: parseEther("0.104"),
	    	A_fsh: parseEther("0.102"),
	    	A_frg: parseEther("0.104"),
	    	B_mnr: parseEther("2.3"),
	    	B_no_mnr: parseEther("0.10"),
	    }
	)).wait();
	
	console.log("DONE")
}

setScores();