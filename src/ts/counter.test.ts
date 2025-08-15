import {
  CounterContract,
  CounterContractArtifact,
} from "../artifacts/Counter.js";
import {
  AccountWallet,
  CompleteAddress,
  PXE,
  AccountWalletWithSecretKey,
  Fr,
} from "@aztec/aztec.js";
import {
  deployCounterWithPublicKeysAndSalt,
  setupSandbox,
  predictContractAddress
} from "./utils.js";
import { getInitialTestAccountsWallets } from "@aztec/accounts/testing";
import { describe, it, expect, beforeAll, beforeEach } from "vitest";
import { deriveKeys } from '@aztec/stdlib/keys';
import { count } from "console";

describe("Counter Contract", () => {
  let pxe: PXE;
  let wallets: AccountWalletWithSecretKey[] = [];
  let accounts: CompleteAddress[] = [];

  let alice: AccountWallet;
  let bob: AccountWallet;
  let carl: AccountWallet;

  let counter: CounterContract;
  let keys: any;
  let salt: Fr;

  beforeAll(async () => {
    pxe = await setupSandbox();

    wallets = await getInitialTestAccountsWallets(pxe);
    accounts = wallets.map((w) => w.getCompleteAddress());

    alice = wallets[0];
    bob = wallets[1];
    carl = wallets[2];

    // Keys and salt are used to deploy and derive the contract address
    // Derive keys for the contract with deterministic value
    keys = await deriveKeys(new Fr(1));
    console.log(keys);
  });

  beforeEach(async () => {
    // Using a random salt for each test run to avoid Existing nullifier error
    salt = Fr.random();

    // Deploy the Counter contract with the public keys
    counter = await deployCounterWithPublicKeysAndSalt(
      keys.publicKeys,
      alice,
      alice.getAddress(),
      salt
    );
  });

  it("Deploy and predicted address match", async () => {
    const { address } = await predictContractAddress(
      CounterContractArtifact,
      [alice.getAddress()],
      alice.getAddress(),
      salt,
      keys.publicKeys,
    );

    console.log("Deployed address:  ", counter.address.toString());
    console.log("Predicted address: ", address.toString());

    expect(counter.address.toString()).toBe(address.toString());
  });

  it("Computing masterNullifierPublicKey should match", async () => {
    const output = await counter.methods.private_to_public_keys(new Fr(keys.masterNullifierSecretKey)).simulate();
    
    // Master Nullifier Public Key X and Y
    const mnpkx = new Fr(output.x);
    const mnpky = new Fr(output.y);

    console.log("Master Nullifier Public Key X: ", mnpkx);
    console.log("Public Keys X:                 ", new Fr(keys.publicKeys.masterNullifierPublicKey.x));
    console.log("Master Nullifier Public Key Y: ", mnpky);
    console.log("Public Keys Y:                 ", keys.publicKeys.masterNullifierPublicKey.y);

    expect(mnpkx.toString()).toBe(keys.publicKeys.masterNullifierPublicKey.x.toString());
    expect(mnpky.toString()).toBe(keys.publicKeys.masterNullifierPublicKey.y.toString());
  });
});
