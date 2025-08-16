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
        protocol_types::{
            public_keys::{PublicKeys, NpkM, IvpkM, OvpkM, TpkM},
            contract_class_id::ContractClassId,
            address::salted_initialization_hash::SaltedInitializationHash,
            traits::FromField,
            traits::ToField,
        },
    };

    use std::{
        embedded_curve_ops::{EmbeddedCurveScalar, fixed_base_scalar_mul},
    };

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
    */

    /** =========================================================
    * ========================= PRIVATE =========================
    * ======================================================== */

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
}
