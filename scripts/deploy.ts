import { ethers } from 'hardhat';

async function main() {
    const { chainId, name } = await ethers.provider.getNetwork();
    const [signer] = await ethers.getSigners();

    console.log(`Deploying from account address ${signer.address}`);

    console.log(`Deploying on ${name} chainId: ${chainId}`);

    const AaveFold = await ethers.getContractFactory('AaveFold', signer);

    const foldContract = await AaveFold.deploy();
    console.log(`Wind Contract deployed at : ${foldContract.address}`);
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
