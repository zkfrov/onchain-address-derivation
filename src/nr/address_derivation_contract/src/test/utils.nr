use crate::AddressDerivation;
use aztec::{
    prelude::AztecAddress, protocol_types::contract_instance::ContractInstance,
    test::helpers::test_environment::TestEnvironment,
};

pub unconstrained fn setup_contract(
    with_account_contracts: bool,
) -> (&mut TestEnvironment, AztecAddress, AztecAddress) {
    // Setup env, generate keys
    let mut env = TestEnvironment::new();
    let user = if with_account_contracts {
        let user = env.create_account_contract(1);
        user
    } else {
        let user = env.create_account(1);
        user
    };

    let acontract = deploy_contract(&mut env);

    (&mut env, acontract.to_address(), user)
}

pub unconstrained fn deploy_contract(
    env: &mut TestEnvironment
) -> ContractInstance {
    // TODO: implement a way to incorporate the salt in the deployment, now it is enforced by the test environment
    let secret = 1;
    let contract_instance = env
        .deploy_with_public_keys("./@address_derivation_contract", "AddressDerivation", secret)
        .without_initializer();
    env.advance_block_by(1);

    contract_instance
}
