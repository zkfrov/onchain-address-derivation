use aztec::macros::aztec;
pub mod test;

#[aztec]
pub contract Counter {
    // aztec library imports
    use aztec::{
        macros::{functions::{initializer, internal, private, public}, storage::storage},
        prelude::{AztecAddress, PublicImmutable, PublicMutable},
        oracle::{
            key_validation_request::get_key_validation_request,
            keys::get_public_keys_and_partial_address,
            debug_log::{ debug_log },
        },
        protocol_types::{public_keys::PublicKeys},
    };

    use std::{
        embedded_curve_ops::{EmbeddedCurveScalar, fixed_base_scalar_mul, EmbeddedCurvePoint},
        ops::Add,
    };

    // @param owner The address of the owner
    // @param counter A numerical value
    #[storage]
    struct Storage<Context> {
        owner: PublicImmutable<AztecAddress, Context>,
        counter: PublicMutable<u128, Context>,
    }

    /// @dev Initialize the contract
    /// @param owner The address of the owner
    #[public]
    #[initializer]
    fn constructor(owner: AztecAddress) {
        storage.owner.initialize(owner);
    }

    /// @dev Retrieves the owner of the contract
    /// @return The owner of the contract
    #[public]
    fn get_owner() -> AztecAddress {
        storage.owner.read()
    }

    /// @dev Increments the counter
    #[private]
    fn increment() {
        Counter::at(context.this_address()).increment_internal().enqueue(&mut context);
    }

    /// @dev Retrieves the counter value
    /// @return The current counter value
    #[public]
    fn get_counter() -> u128 {
        storage.counter.read()
    }

    /// @dev Increments the counter
    #[public]
    #[internal]
    fn increment_internal() {
        let current_value = storage.counter.read();
        storage.counter.write(current_value + 1);
    }

    #[contract_library_method]
    fn get_public_keys(account: AztecAddress) -> PublicKeys {
        // Safety: Public keys are constrained by showing their inclusion in the address's preimage.
        let (public_keys, partial_address) = unsafe { get_public_keys_and_partial_address(account) };
        assert_eq(
            account,
            AztecAddress::compute(public_keys, partial_address),
            "Invalid public keys hint for address",
        );

        public_keys
    }

    #[private]
    fn get_self_public_keys() -> PublicKeys {
        let account = context.this_address();
        get_public_keys(account)
    }

    #[private]
    fn private_to_public_keys(sk: Field) -> EmbeddedCurvePoint {
        // let masterNullifierSecretKey = 0x1c46232974b84af1ea0f3f8e02d68b205fa0fd765839bdd298d270c6f4d87190;
        fixed_base_scalar_mul(EmbeddedCurveScalar::from_field(sk))
    }

    // TODO consume all secret keys to derive public keys
    // #[private]
    // fn secret_to_public_keys(
    //     secret_keys: [Field; 4]
    // ) -> PublicKeys {
    //     let address_point = fixed_base_scalar_mul(secret_keys[0]);
    //     address_point.add(public_keys.ivpk_m.to_point())
    // }

    // TODO
    // https://github.com/AztecProtocol/aztec-packages/blob/79f7691fab59e3771825fced685bfbfe7b3617f5/noir-projects/noir-protocol-circuits/crates/types/src/address/aztec_address.nr
    // #[private]
    // fn derive_address_from_public_keys(
    //     contract_class_id: ContractClassId,
    //     salted_initialization_hash: SaltedInitializationHash,
    //     public_keys: PublicKeys,
    //     // salt: Field, // not needed, as it is part of the initialization hash
    // ) -> AztecAddress {
    //     AztecAddress::compute_from_class_id(
    //         contract_class_id,
    //         salted_initialization_hash,
    //         public_keys,
    //     )
    // }
}
