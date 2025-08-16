import {
  waitForPXE,
  createPXEClient,
  AccountWallet,
  Contract,
  AztecAddress,
} from "@aztec/aztec.js";
import {
  CounterContract,
  CounterContractArtifact,
} from "../artifacts/Counter.js";
import {
  Fr,
  getContractClassFromArtifact,
  PublicKeys
} from '@aztec/aztec.js';
import { getDefaultInitializer } from '@aztec/stdlib/abi';
import {
  computeInitializationHash,
  computeContractAddressFromInstance,
  computeSaltedInitializationHash
} from '@aztec/stdlib/contract';

export const createPXE = async (id: number = 0) => {
  const { BASE_PXE_URL = `http://localhost` } = process.env;
  const url = `${BASE_PXE_URL}:${8080 + id}`;
  const pxe = createPXEClient(url);
  await waitForPXE(pxe);
  return pxe;
};

export const setupSandbox = async () => {
  return createPXE();
};

/**
 * Deploys the Counter contract.
 * @param deployer - The wallet to deploy the contract with.
 * @param owner - The address of the owner of the contract.
 * @returns A deployed contract instance.
 */
export async function deployCounter(
  deployer: AccountWallet,
  owner: AztecAddress,
): Promise<CounterContract> {
  const contract = await Contract.deploy(
    deployer,
    CounterContractArtifact,
    [owner],
    "constructor", // not actually needed since it's the default constructor
  )
    .send()
    .deployed();
  return contract as CounterContract;
}

/**
 * Deploys the Counter contract.
 * @param publicKeys - The public keys to use for the contract.
 * @param deployer - The wallet to deploy the contract with.
 * @param owner - The address of the owner of the contract.
 * @param salt - The salt to use for the contract address. If not provided, a random salt will be used.
 * @returns A deployed contract instance.
 */
export async function deployCounterWithPublicKeysAndSalt(
  publicKeys: PublicKeys,
  deployer: AccountWallet,
  owner: AztecAddress,
  salt: Fr = Fr.random(),
): Promise<CounterContract> {
  const contract = await Contract.deployWithPublicKeys(
    publicKeys,
    deployer,
    CounterContractArtifact,
    [owner],
    "constructor",
  )
    .send({ contractAddressSalt: salt })
    .deployed();
  return contract as CounterContract;
}

/**
 * Predicts the contract address for a given artifact and constructor arguments.
 * @param artifact - The contract artifact.
 * @param constructorArgs - The arguments to pass to the constructor.
 * @param deployer - The address of the deployer.
 * @param salt - The salt to use for the contract address. If not provided, a random salt will be used.
 * @param publicKeys - The public keys to use for the contract.
 * @returns The predicted contract address.
 */
export async function deriveContractAddress(
  artifact: any,
  constructorArgs: any,
  deployer: AztecAddress = AztecAddress.ZERO,
  salt: Fr = Fr.random(),
  publicKeys: PublicKeys,
) {
  if (!publicKeys) {
    publicKeys = await PublicKeys.random();
  }

  const contractClass = await getContractClassFromArtifact(artifact);
  const contractorClassId = contractClass.id;
  const constructorArtifact = getDefaultInitializer(artifact);
  const initializationHash = await computeInitializationHash(constructorArtifact, constructorArgs);
  const saltedInitializationHash = await computeSaltedInitializationHash({
    initializationHash,
    salt,
    deployer,
  });

  const address = await computeContractAddressFromInstance({
    originalContractClassId: contractorClassId,
    saltedInitializationHash: saltedInitializationHash,
    publicKeys: publicKeys
  });

  return { address, initializationHash, saltedInitializationHash, contractorClassId };
}