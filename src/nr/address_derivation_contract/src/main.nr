use aztec::macros::aztec;
pub mod test;

#[aztec]
pub contract AddressDerivation {
    // aztec library imports
    use aztec::{
        macros::{functions::{initializer, internal, private, public}, storage::storage},
        prelude::{AztecAddress, PublicImmutable, PublicMutable},
        oracle::{
            key_validation_request::get_key_validation_request,
            keys::get_public_keys_and_partial_address,
        },
        keys::constants::{NULLIFIER_INDEX, OUTGOING_INDEX},
        protocol_types::{
            public_keys::{PublicKeys, NpkM, IvpkM, OvpkM, TpkM, PublicKeysHash},
            contract_class_id::ContractClassId,
            address::salted_initialization_hash::SaltedInitializationHash,
            traits::{FromField, ToField, Hash},
        },
    };

    use std::{
        embedded_curve_ops::{EmbeddedCurveScalar, fixed_base_scalar_mul},
    };

    /** ==========================================================
     * ======================== CONTEXT ==========================
     * ======================================================== */
    /*

    Key derivation (1):
    secret (Field) -> sha512(secret, GeneratorIndex.NSK_M) -> nskM * Curve.generator -> NpkM (PublicKey)
    secret (Field) -> sha512(secret, GeneratorIndex.IVSK_M) -> ivskM * Curve.generator -> IvpkM (PublicKey)
    secret (Field) -> sha512(secret, GeneratorIndex.OVSK_M) -> ovskM * Curve.generator -> OvpkM (PublicKey)
    secret (Field) -> sha512(secret, GeneratorIndex.TSK_M) -> tskM * Curve.generator -> TpkM (PublicKey)

    Deriving from the initial secret incurs in a cost of 4 sha512 calls, which is expensive in Noir and not intended to happen (2).
    Besides, the sha512 implementation has not been reviewed nor audited yet (3).

    Sources:

    (1) https://github.com/AztecProtocol/aztec-packages/blob/next/yarn-project/stdlib/src/keys/derivation.ts
    (2) https://github.com/AztecProtocol/aztec-packages/blob/cb2a2fa78f30f196339ca044448e415c6a9b45cc/yarn-project/stdlib/src/keys/derivation.ts#L95
    (3) https://github.com/noir-lang/sha512


    Additional notes:

    The master secret keys are not intended to be managed by contracts, that's why only app siloed secret keys can be fetched from a contract on a kernel level.    

    https://github.com/AztecProtocol/aztec-packages/blob/cb2a2fa78f30f196339ca044448e415c6a9b45cc/noir-projects/aztec-nr/aztec/src/context/private_context.nr#L808-L815

    /// However, because contracts cannot be trusted with a user's master
    /// nullifier secret key (because we don't know which contracts are honest
    /// or malicious), the PXE refuses to provide any master secret keys to
    /// any app smart contract function. This means app functions are unable to
    /// prove that the derivation of an app-siloed nullifier secret key has been
    /// computed correctly. Instead, an app function can request to the kernel
    /// (via `request_nsk_app`) that it validates the siloed derivation, since
    /// the kernel has been vetted to not leak any master secret keys.

    */

    /** =========================================================
    * ========================= PRIVATE =========================
    * ======================================================== */

    /// @notice Checks if the secret keys are valid for the address.
    /// @param account The address to check.
    /// @param nsk_m Master Nullifier Secret Key
    /// @param ivsk_m Incoming Viewing Key
    /// @param ovsk_m Outgoing Viewing Key
    /// @param tsk_m Transaction Secret Key
    /// @return True if the secret keys are valid, false otherwise.
    #[private]
    fn check_secret_keys_are_valid_for_address(
        account: AztecAddress,
        nsk_m: Field,
        ivsk_m: Field,
        ovsk_m: Field,
        tsk_m: Field
    ) {
        let fetched_public_keys = _get_public_keys(account);
        let computed_public_keys = _secrets_to_public_keys(nsk_m, ivsk_m, ovsk_m, tsk_m);
        assert_eq(fetched_public_keys, computed_public_keys, "Public keys do not match");
    }

    /// @notice Computes the contract address from the contract class ID, salted initialization hash, and secret keys.
    /// @param contract_class_id The ID of the contract class.
    /// @param salted_initialization_hash The salted initialization hash.
    /// @param nsk_m Master Nullifier Secret Key
    /// @param ivsk_m Incoming Viewing Key
    /// @param ovsk_m Outgoing Viewing Key
    /// @param tsk_m Transaction Secret Key
    /// @return The derived Aztec address.
    #[private]
    fn compute_address_from_secret_keys(
        contract_class_id: Field,
        salted_initialization_hash: Field,
        nsk_m: Field,
        ivsk_m: Field,
        ovsk_m: Field,
        tsk_m: Field
    ) -> AztecAddress {
        _compute_address_from_secret_keys(
            contract_class_id,
            salted_initialization_hash,
            nsk_m,
            ivsk_m,
            ovsk_m,
            tsk_m
        )
    }

    /// @notice Computes the contract address from the contract class ID, salt, initialization hash, deployer address, and secret keys.
    /// @param contract_class_id The ID of the contract class.
    /// @param salt The salt used in the address computation.
    /// @param initialization_hash The initialization hash.
    /// @param deployer The address of the deployer.
    /// @param nsk_m Master Nullifier Secret Key
    /// @param ivsk_m Incoming Viewing Key
    /// @param ovsk_m Outgoing Viewing Key
    /// @param tsk_m Transaction Secret Key
    /// @return The derived Aztec address.
    #[private]
    fn compute_address_from_secret_keys_and_init_hash(
        contract_class_id: Field,
        salt: Field,
        initialization_hash: Field,
        deployer: AztecAddress,
        nsk_m: Field,
        ivsk_m: Field,
        ovsk_m: Field,
        tsk_m: Field
    ) -> AztecAddress {
        let salted_initialization_hash: SaltedInitializationHash = SaltedInitializationHash::compute(
            salt,
            initialization_hash,
            deployer,
        );

        _compute_address_from_secret_keys(
            contract_class_id,
            salted_initialization_hash.to_field(),
            nsk_m,
            ivsk_m,
            ovsk_m,
            tsk_m
        )
    }

    /// @notice Used for testing purposes.
    /// @notice Derives public keys from secret keys.
    /// @param nsk_m Master Nullifier Secret Key
    /// @param ivsk_m Incoming Viewing Key
    /// @param ovsk_m Outgoing Viewing Key
    /// @param tsk_m Transaction Secret Key
    /// @return PublicKeys containing the derived public keys.
    #[private]
    fn secrets_to_public_keys(
        nsk_m: Field,
        ivsk_m: Field,
        ovsk_m: Field,
        tsk_m: Field,
    ) -> PublicKeys {
        _secrets_to_public_keys(
            nsk_m,
            ivsk_m,
            ovsk_m,
            tsk_m,
        )
    }

    /// @notice Used for testing purposes.
    /// @notice Gets the public keys for an address.
    /// @param account The address to get the public keys for.
    /// @return The public keys for the address.
    #[private]
    fn get_public_keys(
        account: AztecAddress,
    ) -> PublicKeys {
        _get_public_keys(account)
    }

    /// @notice Used for testing purposes.
    /// @notice Gets the hash of the master nullifier secret key.
    /// @param account The address to get the hash of the master nullifier secret key for.
    /// @return The hash of the master nullifier secret key.
    #[private]
    fn assert_nsk_app(account: AztecAddress) {
        let public_keys: PublicKeys = _get_public_keys(account);
        let nsk_app: Field = context.request_sk_app(public_keys.npk_m.hash().to_field(), NULLIFIER_INDEX);
        let nsk_app_direct: Field = context.request_nsk_app(public_keys.npk_m.hash().to_field());
        assert_eq(nsk_app, nsk_app_direct, "Public keys do not match");
    }

    /** ==========================================================
     * ================= DERIVATION LIBRARIES ====================
     * ======================================================== */

    /// @notice Computes the contract address from the contract class ID, salted initialization hash, and secret keys.
    /// @param contract_class_id The ID of the contract class.
    /// @param salted_initialization_hash The salted initialization hash.
    /// @param nsk_m Master Nullifier Secret Key
    /// @param ivsk_m Incoming Viewing Key
    /// @param ovsk_m Outgoing Viewing Key
    /// @param tsk_m Transaction Secret Key
    /// @return The derived Aztec address.
    #[contract_library_method]
    fn _compute_address_from_secret_keys(
        contract_class_id: Field,
        salted_initialization_hash: Field,
        nsk_m: Field,
        ivsk_m: Field,
        ovsk_m: Field,
        tsk_m: Field
    ) -> AztecAddress {
        let cci = ContractClassId::from_field(contract_class_id);
        let sih = SaltedInitializationHash::from_field(salted_initialization_hash);

        let public_keys: PublicKeys = _secrets_to_public_keys(
            nsk_m,
            ivsk_m,
            ovsk_m,
            tsk_m
        );

        let address = AztecAddress::compute_from_class_id(
            cci,
            sih,
            public_keys,
        );

        address
    }

    /// @notice Derives public keys from secret keys.
    /// @param nsk_m Master Nullifier Secret Key
    /// @param ivsk_m Incoming Viewing Key
    /// @param ovsk_m Outgoing Viewing Key
    /// @param tsk_m Transaction Secret Key
    /// @return PublicKeys containing the derived public keys.
    #[contract_library_method]
    fn _secrets_to_public_keys(
        nsk_m: Field,
        ivsk_m: Field,
        ovsk_m: Field,
        tsk_m: Field,
    ) -> PublicKeys {
        let npk_m = fixed_base_scalar_mul(EmbeddedCurveScalar::from_field(nsk_m));
        let ivpk_m = fixed_base_scalar_mul(EmbeddedCurveScalar::from_field(ivsk_m));
        let ovpk_m = fixed_base_scalar_mul(EmbeddedCurveScalar::from_field(ovsk_m));
        let tpk_m = fixed_base_scalar_mul(EmbeddedCurveScalar::from_field(tsk_m));

        PublicKeys {
            npk_m: NpkM { inner: npk_m },
            ivpk_m: IvpkM { inner: ivpk_m },
            ovpk_m: OvpkM { inner: ovpk_m },
            tpk_m: TpkM { inner: tpk_m },
        }
    }

    /// @notice Gets the public keys for an address.
    /// @param account The address to get the public keys for.
    /// @return The public keys for the address.
    #[contract_library_method]
    fn _get_public_keys(account: AztecAddress) -> PublicKeys {
        // Safety: Public keys are constrained by showing their inclusion in the address's preimage.
        let (public_keys, partial_address) = unsafe { get_public_keys_and_partial_address(account) };
        assert_eq(
            account,
            AztecAddress::compute(public_keys, partial_address),
            "Invalid public keys hint for address",
        );

        public_keys
    }
}
