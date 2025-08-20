import { type AccountWallet, type PXE, createPXEClient, Fr, getContractClassFromArtifact } from "@aztec/aztec.js";
import { getInitialTestAccountsWallets } from "@aztec/accounts/testing";
import { deriveKeys } from '@aztec/stdlib/keys';

// Import types from benchmark package
import {
  Benchmark,
  type BenchmarkContext,
  type BenchmarkedInteraction,
} from "@defi-wonderland/aztec-benchmark";

import { AddressDerivationContract, AddressDerivationContractArtifact } from "../src/artifacts/AddressDerivation.js";
import { deployAddressDerivationWithPublicKeysAndSalt, deriveContractAddress } from "../src/ts/utils.js";

// Extend the BenchmarkContext from the new package
interface AddressDerivationBenchmarkContext extends BenchmarkContext {
  pxe: PXE;
  deployer: AccountWallet;
  accounts: AccountWallet[];
  addressDerivationContract: AddressDerivationContract;
  contractClassId: Fr;
  saltedInitializationHash: Fr;
  keys: any;
  initializationHash: Fr;
  salt: Fr;
}

// Use export default class extending Benchmark
export default class AddressDerivationBenchmark extends Benchmark {
  /**
   * Sets up the benchmark environment for the AddressDerivationContract.
   * Creates PXE client, gets accounts, and deploys the contract.
   */
  async setup(): Promise<AddressDerivationBenchmarkContext> {
    const { BASE_PXE_URL = "http://localhost" } = process.env;
    const pxe = createPXEClient(`${BASE_PXE_URL}:8080`);
    const accounts = await getInitialTestAccountsWallets(pxe);
    const deployer = accounts[0]!;

    const sk = Fr.ONE;
    const keys = await deriveKeys(sk);
    const salt = Fr.random();



    const { address, initializationHash, saltedInitializationHash, contractClassId } = await deriveContractAddress(
      AddressDerivationContractArtifact,
      [],
      deployer.getAddress(),
      salt,
      keys.publicKeys,
    );

    const deployedAddressDerivationContract = await deployAddressDerivationWithPublicKeysAndSalt(
      keys.publicKeys,
      deployer,
      deployer.getAddress(),
      salt
    );

    const addressDerivationContract = await AddressDerivationContract.at(
      deployedAddressDerivationContract.address,
      deployer,
    );

    const partialAddress = await deployedAddressDerivationContract.partialAddress;
    pxe.registerAccount(sk, partialAddress);
    
    return { pxe, deployer, accounts, addressDerivationContract, contractClassId, saltedInitializationHash, keys, initializationHash, salt };
  }

  /**
   * Returns the list of AddressDerivationContract methods to be benchmarked.
   */
  getMethods(context: AddressDerivationBenchmarkContext): BenchmarkedInteraction[] {
    const { addressDerivationContract, accounts, contractClassId, saltedInitializationHash, keys, initializationHash, salt } = context;
    const [alice] = accounts;

    const methods = [
      addressDerivationContract.withWallet(alice).methods.compute_address_from_secret_keys(
        contractClassId.toField(),
        saltedInitializationHash,
        new Fr(keys.masterNullifierSecretKey.toBigInt()),
        new Fr(keys.masterIncomingViewingSecretKey.toBigInt()),
        new Fr(keys.masterOutgoingViewingSecretKey.toBigInt()),
        new Fr(keys.masterTaggingSecretKey.toBigInt()),
      ),
      addressDerivationContract.withWallet(alice).methods.compute_address_from_secret_keys_and_init_hash(
        contractClassId.toField(),
        salt,
        initializationHash,
        alice.getAddress(),
        new Fr(keys.masterNullifierSecretKey.toBigInt()),
        new Fr(keys.masterIncomingViewingSecretKey.toBigInt()),
        new Fr(keys.masterOutgoingViewingSecretKey.toBigInt()),
        new Fr(keys.masterTaggingSecretKey.toBigInt()),
      ),
      addressDerivationContract.withWallet(alice).methods.check_secret_keys_are_valid_for_address(
        addressDerivationContract.address,
        new Fr(keys.masterNullifierSecretKey.toBigInt()),
        new Fr(keys.masterIncomingViewingSecretKey.toBigInt()),
        new Fr(keys.masterOutgoingViewingSecretKey.toBigInt()),
        new Fr(keys.masterTaggingSecretKey.toBigInt()),
      ),
    ] as BenchmarkedInteraction[];

    return methods.filter(Boolean);
  }
}
