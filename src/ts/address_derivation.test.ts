import {
  AddressDerivationContract,
  AddressDerivationContractArtifact,
} from "../artifacts/AddressDerivation.js";
import {
  AccountWallet,
  CompleteAddress,
  PXE,
  AccountWalletWithSecretKey,
  Fr,
  PublicKeys,
  GrumpkinScalar,
} from "@aztec/aztec.js";
import {
  deployAddressDerivationWithPublicKeysAndSalt,
  setupSandbox,
  deriveContractAddress
} from "./utils.js";
import { getInitialTestAccountsWallets } from "@aztec/accounts/testing";
import { describe, it, expect, beforeAll, beforeEach } from "vitest";
import { deriveKeys } from '@aztec/stdlib/keys';

describe("AddressDerivation Contract", () => {
  let pxe: PXE;
  let wallets: AccountWalletWithSecretKey[] = [];
  let accounts: CompleteAddress[] = [];

  let alice: AccountWallet;
  let bob: AccountWallet;
  let carl: AccountWallet;

  let addressDerivation: AddressDerivationContract;
  let keys: {
    masterNullifierSecretKey: GrumpkinScalar;
    masterIncomingViewingSecretKey: GrumpkinScalar;
    masterOutgoingViewingSecretKey: GrumpkinScalar;
    masterTaggingSecretKey: GrumpkinScalar;
    publicKeys: PublicKeys;
  };
  let salt: Fr;

  beforeAll(async () => {
    pxe = await setupSandbox();

    wallets = await getInitialTestAccountsWallets(pxe);
    accounts = wallets.map((w) => w.getCompleteAddress());

    alice = wallets[0];
    bob = wallets[1];
    carl = wallets[2];

    // Derive keys for the contract with a deterministic value
    keys = await deriveKeys(Fr.ONE);
  });

  beforeEach(async () => {
    // Using a random salt for each test run to avoid Existing nullifier error
    salt = Fr.random();

    // Deploy the AddressDerivation contract with the public keys
    addressDerivation = await deployAddressDerivationWithPublicKeysAndSalt(
      keys.publicKeys,
      alice,
      alice.getAddress(),
      salt
    );
  });

  it("Circuit derives address from secret keys correctly", async () => {
    const { address, saltedInitializationHash, contractClassId } = await deriveContractAddress(
      AddressDerivationContractArtifact,
      [],
      alice.getAddress(),
      salt,
      keys.publicKeys,
    );

    const secretKeyDerivated = await addressDerivation.methods.compute_address_from_secret_keys(
      contractClassId.toField(),
      saltedInitializationHash,
      new Fr(keys.masterNullifierSecretKey.toBigInt()),
      new Fr(keys.masterIncomingViewingSecretKey.toBigInt()),
      new Fr(keys.masterOutgoingViewingSecretKey.toBigInt()),
      new Fr(keys.masterTaggingSecretKey.toBigInt()),
    ).simulate();

    expect(secretKeyDerivated.toString()).toBe(addressDerivation.address.toString());
    expect(secretKeyDerivated.toString()).toBe(address.toString());
  });

  it("Circuit derives address from secret keys and init hash correctly", async () => {
    const { address, initializationHash, contractClassId } = await deriveContractAddress(
      AddressDerivationContractArtifact,
      [],
      alice.getAddress(),
      salt,
      keys.publicKeys,
    );

    const skAndInitHashDerivated = await addressDerivation.methods.compute_address_from_secret_keys_and_init_hash(
      contractClassId.toField(),
      salt,
      initializationHash,
      alice.getAddress(),
      new Fr(keys.masterNullifierSecretKey.toBigInt()),
      new Fr(keys.masterIncomingViewingSecretKey.toBigInt()),
      new Fr(keys.masterOutgoingViewingSecretKey.toBigInt()),
      new Fr(keys.masterTaggingSecretKey.toBigInt()),
    ).simulate();

    expect(skAndInitHashDerivated.toString()).toBe(addressDerivation.address.toString());
    expect(skAndInitHashDerivated.toString()).toBe(address.toString());
  });

  it("Both derivation methods should produce the same address", async () => {
    const { address, initializationHash, saltedInitializationHash, contractClassId } = await deriveContractAddress(
      AddressDerivationContractArtifact,
      [],
      alice.getAddress(),
      salt,
      keys.publicKeys,
    );

    const secretKeyDerivated = await addressDerivation.methods.compute_address_from_secret_keys(
      contractClassId.toField(),
      saltedInitializationHash,
      new Fr(keys.masterNullifierSecretKey.toBigInt()),
      new Fr(keys.masterIncomingViewingSecretKey.toBigInt()),
      new Fr(keys.masterOutgoingViewingSecretKey.toBigInt()),
      new Fr(keys.masterTaggingSecretKey.toBigInt()),
    ).simulate();

    const skAndInitHashDerivated = await addressDerivation.methods.compute_address_from_secret_keys_and_init_hash(
      contractClassId.toField(),
      salt,
      initializationHash,
      alice.getAddress(),
      new Fr(keys.masterNullifierSecretKey.toBigInt()),
      new Fr(keys.masterIncomingViewingSecretKey.toBigInt()),
      new Fr(keys.masterOutgoingViewingSecretKey.toBigInt()),
      new Fr(keys.masterTaggingSecretKey.toBigInt()),
    ).simulate();

    expect(secretKeyDerivated.toString()).toBe(addressDerivation.address.toString());
    expect(secretKeyDerivated.toString()).toBe(address.toString());
    expect(secretKeyDerivated.toString()).toBe(skAndInitHashDerivated.toString());
  });
 
  it("Secret to public key conversion should match", async () => {
    const publicKeys = await addressDerivation.methods.secrets_to_public_keys(
      new Fr(keys.masterNullifierSecretKey.toBigInt()),
      new Fr(keys.masterIncomingViewingSecretKey.toBigInt()),
      new Fr(keys.masterOutgoingViewingSecretKey.toBigInt()),
      new Fr(keys.masterTaggingSecretKey.toBigInt())
    ).simulate();

    expect(new Fr(publicKeys.npk_m.inner.x).toString()).toBe(keys.publicKeys.masterNullifierPublicKey.x.toString());
    expect(new Fr(publicKeys.npk_m.inner.y).toString()).toBe(keys.publicKeys.masterNullifierPublicKey.y.toString());
    expect(new Fr(publicKeys.ivpk_m.inner.x).toString()).toBe(keys.publicKeys.masterIncomingViewingPublicKey.x.toString());
    expect(new Fr(publicKeys.ivpk_m.inner.y).toString()).toBe(keys.publicKeys.masterIncomingViewingPublicKey.y.toString());
    expect(new Fr(publicKeys.ovpk_m.inner.x).toString()).toBe(keys.publicKeys.masterOutgoingViewingPublicKey.x.toString());
    expect(new Fr(publicKeys.ovpk_m.inner.y).toString()).toBe(keys.publicKeys.masterOutgoingViewingPublicKey.y.toString());
    expect(new Fr(publicKeys.tpk_m.inner.x).toString()).toBe(keys.publicKeys.masterTaggingPublicKey.x.toString());
    expect(new Fr(publicKeys.tpk_m.inner.y).toString()).toBe(keys.publicKeys.masterTaggingPublicKey.y.toString());
  });
});
