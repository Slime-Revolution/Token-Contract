#[test_only]
module slime::test_global_state {
    use std::signer;
    use slime::global_state;
    use slime::test_helper;

    const ONE_APT: u64 = 100000000;
    #[test(deployer = @0xcafe, operator = @0xcafe2)]
    public fun test_e2e(deployer: &signer, operator: &signer) {
        test_helper::setup();
        let deployer_address = signer::address_of(deployer);
        let operator_address = signer::address_of(operator);
        assert!(global_state::operator() == deployer_address, 0);
        assert!(global_state::governance() == deployer_address, 1);
        global_state::update_operator(deployer, signer::address_of(operator));
        assert!(global_state::operator() == operator_address, 2);
        assert!(global_state::governance() == deployer_address, 3);
        global_state::update_governance(deployer, signer::address_of(operator));
        assert!(global_state::governance() == operator_address, 4);
        assert!(global_state::operator() == operator_address, 5);
    }

    #[test(deployer=@0xcafe, operator = @0xcafe2)]
    #[expected_failure(abort_code = 101, location=global_state)]
    public entry fun test_set_operator_fail_by_auth(deployer: &signer, operator: &signer) {
        test_helper::setup();
        let deployer_address = signer::address_of(deployer);
        assert!(global_state::operator() == deployer_address, 0);
        assert!(global_state::governance() == deployer_address, 1);
        global_state::update_operator(operator, signer::address_of(operator));
    }

    #[test(deployer=@0xcafe, operator = @0xcafe2)]
    #[expected_failure(abort_code = 101, location=global_state)]
    public entry fun test_set_governance_fail_by_auth(deployer: &signer, operator: &signer) {
        test_helper::setup();
        let deployer_address = signer::address_of(deployer);
        assert!(global_state::operator() == deployer_address, 0);
        assert!(global_state::governance() == deployer_address, 1);
        global_state::update_governance(operator, signer::address_of(operator));
    }
}