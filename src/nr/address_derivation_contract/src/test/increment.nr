use crate::{AddressDerivation, test::utils};

#[test]
unconstrained fn nsk_apps_assertion() {
    let (env, contract_address, user) = utils::setup_contract(false);

    env.impersonate(user);
    AddressDerivation::at(contract_address).assert_nsk_app(contract_address).call(&mut env.private());
}
