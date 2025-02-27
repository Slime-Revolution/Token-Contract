#[test_only]
module slime::test_vesting_token {
    use std::signer;
    use aptos_framework::aptos_account;
    use aptos_framework::primary_fungible_store;
    use aptos_framework::timestamp;
    use slime::global_state;
    use slime::slime_token;
    use slime::token_vesting;
    use slime::test_helper;

    const ONE_APT: u64 = 100000000;
    const DAY: u64 = 86400;
    const MONTH: u64 = 30 * 86400;

    const TREASURY_INDEX:u8 = 0;
    const COMMUNITY_INDEX:u8 = 1;
    const PLAYER_REWARDS_INDEX:u8 = 2;
    const TEAM_INDEX:u8 = 3;
    const PRIVATE_INDEX:u8 = 4;
    const LIQUIDITY_INDEX:u8 = 5;
    const AIRDROP_INDEX:u8 = 6;

    const APT: u64 = 1_00_000_000;
    const INIT_TREASURY_AMOUNT: u64 =   1_000_000_000 * 100_000_000;
    const INIT_COMMUNITY_REWARDS_AMOUNT: u64 =   300_000_000 * 100_000_000;
    const INIT_PLAYER_REWARDS_AMOUNT: u64 =   300_000_000 * 100_000_000;
    const INIT_TEAM_AMOUNT: u64 = 120_000_000 * 100_000_000;
    const INIT_PRIVATE_AMOUNT: u64 = 160_000_000 * 100_000_000;
    const INIT_LIQUIDITY_AMOUNT: u64 =   100_000_000 * 100_000_000;
    const INIT_AIRDROP_AMOUNT: u64 = 20_000_000 * 100_000_000;


    #[test(deployer = @0xcafe, operator = @0xcafe2, claimer1 = @0x543, claimer2 = @0x523)]
    public entry fun test_e2e(deployer: &signer, operator: &signer, claimer1: &signer, claimer2: &signer) {
        let deployer_address = signer::address_of(deployer);
        let operator_address = signer::address_of(operator);
        let _deployer_address = signer::address_of(deployer);
        let claimer1_address = signer::address_of(claimer1);
        let claimer2_address = signer::address_of(claimer2);
        test_helper::setup();
        let apt_coins = test_helper::mint_apt(100);
        aptos_account::deposit_coins(operator_address, apt_coins);

        // Add reward, set policies
        let start = timestamp::now_seconds() + 1 * MONTH;
        let end = start + 12 * MONTH;
        let periods = 3 * MONTH;
        let tge_time = timestamp::now_seconds();
        let tge_ratio = 10;
        let tge_denom = 100;
        global_state::update_operator(deployer, operator_address);
        token_vesting::set_policies_entry(operator, start, end, periods, tge_time, tge_ratio, tge_denom, PRIVATE_INDEX);
        let claimer1_allo = 10 * ONE_APT;
        let claimer2_allo = 12 * ONE_APT;
        let allocates = vector[claimer1_allo, claimer2_allo];
        let claimers = vector[claimer1_address, claimer2_address];
        token_vesting::add_claimers(operator, PRIVATE_INDEX, claimers, allocates);
        // TGE time
        timestamp::fast_forward_seconds(1);
        token_vesting::claim(claimer1, PRIVATE_INDEX);
        let claimer1_balance_tge = primary_fungible_store::balance(claimer1_address, slime_token::token());
        assert!(claimer1_balance_tge == claimer1_allo * tge_ratio / tge_denom, 1);
        token_vesting::claim(claimer2, PRIVATE_INDEX);
        let claimer2_balance_tge = primary_fungible_store::balance(claimer2_address, slime_token::token());
        assert!(claimer2_balance_tge == claimer2_allo * tge_ratio / tge_denom, 1);

        // vesting time 1
        timestamp::fast_forward_seconds(1 * MONTH);
        token_vesting::claim(claimer1, PRIVATE_INDEX);
        let claimer1_balance_vest1 = primary_fungible_store::balance(claimer1_address, slime_token::token());
        assert!(
            claimer1_balance_vest1 == claimer1_balance_tge + ((claimer1_allo - claimer1_balance_tge) * ((timestamp::now_seconds() - start) / periods + 1) / ((end - start) / periods)),
            1
        );
        token_vesting::claim(claimer2, PRIVATE_INDEX);
        let claimer2_balance_vest1 = primary_fungible_store::balance(claimer2_address, slime_token::token());
        assert!(
            claimer2_balance_vest1 == claimer2_balance_tge + ((claimer2_allo - claimer2_balance_tge) * ((timestamp::now_seconds() - start) / periods + 1) / ((end - start) / periods)),
            1
        );

        // vesting time 2
        timestamp::fast_forward_seconds(3 * MONTH);
        token_vesting::claim(claimer1, PRIVATE_INDEX);
        let claimer1_balance_vest2 = primary_fungible_store::balance(claimer1_address, slime_token::token());
        assert!(
            claimer1_balance_vest2 == claimer1_balance_tge + ((claimer1_allo - claimer1_balance_tge) * ((timestamp::now_seconds() - start) / periods + 1) / ((end - start) / periods)),
            1
        );

        // vesting final
        timestamp::fast_forward_seconds(9 * MONTH);
        token_vesting::claim(claimer1, PRIVATE_INDEX);
        let claimer1_balance_vest_last = primary_fungible_store::balance(claimer1_address, slime_token::token());
        assert!(
            claimer1_balance_vest_last == claimer1_allo,
            1
        );
        token_vesting::claim(claimer2, PRIVATE_INDEX);
        let claimer2_balance_vest_last = primary_fungible_store::balance(claimer2_address, slime_token::token());
        assert!(
            claimer2_balance_vest_last == claimer2_allo,
            1
        );
        timestamp::fast_forward_seconds(3 * MONTH + 1);
        global_state::update_operator(deployer, deployer_address);
        token_vesting::collect(deployer, PRIVATE_INDEX, deployer_address);
        let deployer_balance = primary_fungible_store::balance(deployer_address, slime_token::token());
        assert!(deployer_balance == INIT_PRIVATE_AMOUNT - claimer1_allo - claimer2_allo, 1);
        timestamp::fast_forward_seconds(1);
    }

    #[test(deployer=@0xcafe, operator = @0xcafe2, claimer1 = @0x543, _claimer2 = @0x523)]
    #[expected_failure(abort_code = 0, location=token_vesting)]
    public entry fun test_set_policy_fail_by_auth(deployer: &signer, operator: &signer, claimer1: &signer, _claimer2: &signer) {
        let operator_address = signer::address_of(operator);
        let _deployer_address = signer::address_of(deployer);
        test_helper::setup();
        let apt_coins = test_helper::mint_apt(100);
        aptos_account::deposit_coins(operator_address, apt_coins);

        // Add reward, set policies
        let start = timestamp::now_seconds() + 1 * MONTH;
        let end = start + 12 * MONTH;
        let periods = 3 * MONTH;
        let tge_time = timestamp::now_seconds();
        let tge_ratio = 10;
        let tge_denom = 100;
        token_vesting::set_policies_entry(claimer1, start, end, periods, tge_time, tge_ratio, tge_denom, PRIVATE_INDEX);
    }

    #[test(deployer=@0xcafe, operator = @0xcafe2, claimer1 = @0x543, claimer2 = @0x523)]
    #[expected_failure(abort_code = 0, location=token_vesting)]
    public entry fun test_add_claimers_fail_by_auth(deployer: &signer, operator: &signer, claimer1: &signer, claimer2: &signer) {
        let operator_address = signer::address_of(operator);
        let _deployer_address = signer::address_of(deployer);
        let claimer1_address = signer::address_of(claimer1);
        let claimer2_address = signer::address_of(claimer2);
        test_helper::setup();
        let apt_coins = test_helper::mint_apt(100);
        aptos_account::deposit_coins(operator_address, apt_coins);

        // Add reward, set policies
        let start = timestamp::now_seconds() + 1 * MONTH;
        let end = start + 12 * MONTH;
        let periods = 3 * MONTH;
        let tge_time = timestamp::now_seconds();
        let tge_ratio = 10;
        let tge_denom = 100;
        token_vesting::set_policies_entry(deployer, start, end, periods, tge_time, tge_ratio, tge_denom, PRIVATE_INDEX);
        let claimer1_allo = 10 * ONE_APT;
        let claimer2_allo = 12 * ONE_APT;
        let allocates = vector[claimer1_allo, claimer2_allo];
        let claimers = vector[claimer1_address, claimer2_address];
        token_vesting::add_claimers(claimer1, PRIVATE_INDEX, claimers, allocates);
    }

    #[test(deployer=@0xcafe, operator = @0xcafe2, claimer1 = @0x543, _claimer2 = @0x523)]
    #[expected_failure(abort_code = 0, location=token_vesting)]
    public entry fun test_add_claimer_fail_by_auth(deployer: &signer, operator: &signer, claimer1: &signer, _claimer2: &signer) {
        let operator_address = signer::address_of(operator);
        let _deployer_address = signer::address_of(deployer);
        let claimer1_address = signer::address_of(claimer1);
        test_helper::setup();
        let apt_coins = test_helper::mint_apt(100);
        aptos_account::deposit_coins(operator_address, apt_coins);

        // Add reward, set policies
        let start = timestamp::now_seconds() + 1 * MONTH;
        let end = start + 12 * MONTH;
        let periods = 3 * MONTH;
        let tge_time = timestamp::now_seconds();
        let tge_ratio = 10;
        let tge_denom = 100;
        token_vesting::set_policies_entry(operator, start, end, periods, tge_time, tge_ratio, tge_denom, PRIVATE_INDEX);
        let claimer1_allo = 10 * ONE_APT;
        token_vesting::add_claimer(claimer1, PRIVATE_INDEX, claimer1_address, claimer1_allo);
    }

    #[test(deployer=@0xcafe, operator = @0xcafe2, claimer1 = @0x543, claimer2 = @0x523)]
    #[expected_failure(abort_code = 0, location=token_vesting)]
    public entry fun test_withdraw_reward_fail_by_auth(deployer: &signer, operator: &signer, claimer1: &signer, claimer2: &signer) {
        let operator_address = signer::address_of(operator);
        let _deployer_address = signer::address_of(deployer);
        let claimer1_address = signer::address_of(claimer1);
        let claimer2_address = signer::address_of(claimer2);
        test_helper::setup();
        let apt_coins = test_helper::mint_apt(100);
        aptos_account::deposit_coins(operator_address, apt_coins);

        // Add reward, set policies
        let start = timestamp::now_seconds() + 1 * MONTH;
        let end = start + 12 * MONTH;
        let periods = 3 * MONTH;
        let tge_time = timestamp::now_seconds();
        let tge_ratio = 10;
        let tge_denom = 100;
        global_state::update_operator(deployer, operator_address);
        token_vesting::set_policies_entry(operator, start, end, periods, tge_time, tge_ratio, tge_denom, PRIVATE_INDEX);
        let claimer1_allo = 10 * ONE_APT;
        let claimer2_allo = 12 * ONE_APT;
        let allocates = vector[claimer1_allo, claimer2_allo];
        let claimers = vector[claimer1_address, claimer2_address];
        token_vesting::add_claimers(operator, PRIVATE_INDEX, claimers, allocates);
        // TGE time
        timestamp::fast_forward_seconds(1);
        token_vesting::claim(claimer1, PRIVATE_INDEX);
        let claimer1_balance_tge = primary_fungible_store::balance(claimer1_address, slime_token::token());
        assert!(claimer1_balance_tge == claimer1_allo * tge_ratio / tge_denom, 1);
        token_vesting::claim(claimer2, PRIVATE_INDEX);
        let claimer2_balance_tge = primary_fungible_store::balance(claimer2_address, slime_token::token());
        assert!(claimer2_balance_tge == claimer2_allo * tge_ratio / tge_denom, 1);

        // vesting time 1
        timestamp::fast_forward_seconds(1 * MONTH);
        token_vesting::claim(claimer1, PRIVATE_INDEX);
        let claimer1_balance_vest1 = primary_fungible_store::balance(claimer1_address, slime_token::token());
        assert!(
            claimer1_balance_vest1 == claimer1_balance_tge + ((claimer1_allo - claimer1_balance_tge) * ((timestamp::now_seconds() - start) / periods + 1) / ((end - start) / periods)),
            1
        );
        token_vesting::claim(claimer2, PRIVATE_INDEX);
        let claimer2_balance_vest1 = primary_fungible_store::balance(claimer2_address, slime_token::token());
        assert!(
            claimer2_balance_vest1 == claimer2_balance_tge + ((claimer2_allo - claimer2_balance_tge) * ((timestamp::now_seconds() - start) / periods + 1) / ((end - start) / periods)),
            1
        );

        // vesting time 2
        timestamp::fast_forward_seconds(3 * MONTH);
        token_vesting::claim(claimer1, PRIVATE_INDEX);
        let claimer1_balance_vest2 = primary_fungible_store::balance(claimer1_address, slime_token::token());
        assert!(
            claimer1_balance_vest2 == claimer1_balance_tge + ((claimer1_allo - claimer1_balance_tge) * ((timestamp::now_seconds() - start) / periods + 1) / ((end - start) / periods)),
            1
        );

        // vesting final
        timestamp::fast_forward_seconds(9 * MONTH);
        token_vesting::claim(claimer1, PRIVATE_INDEX);
        let claimer1_balance_vest_last = primary_fungible_store::balance(claimer1_address, slime_token::token());
        assert!(
            claimer1_balance_vest_last == claimer1_allo,
            1
        );
        token_vesting::claim(claimer2, PRIVATE_INDEX);
        let claimer2_balance_vest_last = primary_fungible_store::balance(claimer2_address, slime_token::token());
        assert!(
            claimer2_balance_vest_last == claimer2_allo,
            1
        );
        token_vesting::collect(claimer1, PRIVATE_INDEX, claimer1_address);
    }

    #[test(deployer=@0xcafe, operator = @0xcafe2, claimer1 = @0x543, claimer2 = @0x523)]
    #[expected_failure(abort_code = 0, location=token_vesting)]
    public entry fun test_remove_claimer_fail_by_auth(deployer: &signer, operator: &signer, claimer1: &signer, claimer2: &signer) {
        let operator_address = signer::address_of(operator);
        let _deployer_address = signer::address_of(deployer);
        let claimer1_address = signer::address_of(claimer1);
        let claimer2_address = signer::address_of(claimer2);
        test_helper::setup();
        let apt_coins = test_helper::mint_apt(100);
        aptos_account::deposit_coins(operator_address, apt_coins);

        // Add reward, set policies
        let start = timestamp::now_seconds() + 1 * MONTH;
        let end = start + 12 * MONTH;
        let periods = 3 * MONTH;
        let tge_time = timestamp::now_seconds();
        let tge_ratio = 10;
        let tge_denom = 100;
        global_state::update_operator(deployer, operator_address);
        token_vesting::set_policies_entry(operator, start, end, periods, tge_time, tge_ratio, tge_denom, PRIVATE_INDEX);
        let claimer1_allo = 10 * ONE_APT;
        let claimer2_allo = 12 * ONE_APT;
        let allocates = vector[claimer1_allo, claimer2_allo];
        let claimers = vector[claimer1_address, claimer2_address];
        token_vesting::add_claimers(operator, PRIVATE_INDEX, claimers, allocates);
        token_vesting::remove_claimer(claimer1,  PRIVATE_INDEX, claimer1_address);
    }

    #[test(deployer=@0xcafe, operator = @0xcafe2, claimer1 = @0x543, claimer2 = @0x523)]
    #[expected_failure(abort_code = 3, location=token_vesting)]
    public entry fun test_claim_fail_by_time(deployer: &signer, operator: &signer, claimer1: &signer, claimer2: &signer) {
        let operator_address = signer::address_of(operator);
        let _deployer_address = signer::address_of(deployer);
        let claimer1_address = signer::address_of(claimer1);
        let claimer2_address = signer::address_of(claimer2);
        test_helper::setup();
        let apt_coins = test_helper::mint_apt(100);
        aptos_account::deposit_coins(operator_address, apt_coins);

        // Add reward, set policies
        let start = timestamp::now_seconds() + 1 * MONTH;
        let end = start + 12 * MONTH;
        let periods = 3 * MONTH;
        let tge_time = timestamp::now_seconds();
        let tge_ratio = 10;
        let tge_denom = 100;
        global_state::update_operator(deployer, operator_address);
        token_vesting::set_policies_entry(operator, start, end, periods, tge_time, tge_ratio, tge_denom, PRIVATE_INDEX);
        let claimer1_allo = 10 * ONE_APT;
        let claimer2_allo = 12 * ONE_APT;
        let allocates = vector[claimer1_allo, claimer2_allo];
        let claimers = vector[claimer1_address, claimer2_address];
        token_vesting::add_claimers(operator, PRIVATE_INDEX, claimers, allocates);

        // TGE time
        token_vesting::claim(claimer1, PRIVATE_INDEX);
    }

    #[test(deployer=@0xcafe, operator = @0xcafe2, claimer1 = @0x543, claimer2 = @0x523)]
    #[expected_failure(abort_code = 2, location=token_vesting)]
    public entry fun test_claim_fail_by_claimer(deployer: &signer, operator: &signer, claimer1: &signer, claimer2: &signer) {
        let operator_address = signer::address_of(operator);
        let _deployer_address = signer::address_of(deployer);
        let claimer1_address = signer::address_of(claimer1);
        test_helper::setup();
        let apt_coins = test_helper::mint_apt(100);
        aptos_account::deposit_coins(operator_address, apt_coins);

        // Add reward, set policies
        let start = timestamp::now_seconds() + 1 * MONTH;
        let end = start + 12 * MONTH;
        let periods = 3 * MONTH;
        let tge_time = timestamp::now_seconds();
        let tge_ratio = 10;
        let tge_denom = 100;
        global_state::update_operator(deployer, operator_address);
        token_vesting::set_policies_entry(operator, start, end, periods, tge_time, tge_ratio, tge_denom, PRIVATE_INDEX);
        let claimer1_allo = 10 * ONE_APT;
        let allocates = vector[claimer1_allo];
        let claimers = vector[claimer1_address];
        token_vesting::add_claimers(operator, PRIVATE_INDEX, claimers, allocates);

        // TGE time
        timestamp::fast_forward_seconds(1);
        token_vesting::claim(claimer1, PRIVATE_INDEX);
        let claimer1_balance_tge = primary_fungible_store::balance(claimer1_address, slime_token::token());
        assert!(claimer1_balance_tge == claimer1_allo * tge_ratio / tge_denom, 1);
        token_vesting::claim(claimer2, PRIVATE_INDEX);
    }

    #[test(deployer=@0xcafe, operator = @0xcafe2, claimer1 = @0x543, claimer2 = @0x523)]
    #[expected_failure(abort_code = 3, location=token_vesting)]
    public entry fun test_claim_fail_by_claimer_claimed(deployer: &signer, operator: &signer, claimer1: &signer, claimer2: &signer) {
        let operator_address = signer::address_of(operator);
        let _deployer_address = signer::address_of(deployer);
        let claimer1_address = signer::address_of(claimer1);
        let claimer2_address = signer::address_of(claimer2);
        test_helper::setup();
        let apt_coins = test_helper::mint_apt(100);
        aptos_account::deposit_coins(operator_address, apt_coins);

        // Add reward, set policies
        let start = timestamp::now_seconds() + 1 * MONTH;
        let end = start + 12 * MONTH;
        let periods = 3 * MONTH;
        let tge_time = timestamp::now_seconds();
        let tge_ratio = 10;
        let tge_denom = 100;
        global_state::update_operator(deployer, operator_address);
        token_vesting::set_policies_entry(operator, start, end, periods, tge_time, tge_ratio, tge_denom, PRIVATE_INDEX);
        let claimer1_allo = 10 * ONE_APT;
        let claimer2_allo = 12 * ONE_APT;
        let allocates = vector[claimer1_allo, claimer2_allo];
        let claimers = vector[claimer1_address, claimer2_address];
        token_vesting::add_claimers(operator, PRIVATE_INDEX, claimers, allocates);

        // TGE time
        timestamp::fast_forward_seconds(1);
        token_vesting::claim(claimer1, PRIVATE_INDEX);
        let claimer1_balance_tge = primary_fungible_store::balance(claimer1_address, slime_token::token());
        assert!(claimer1_balance_tge == claimer1_allo * tge_ratio / tge_denom, 1);
        token_vesting::claim(claimer2, PRIVATE_INDEX);
        let claimer2_balance_tge = primary_fungible_store::balance(claimer2_address, slime_token::token());
        assert!(claimer2_balance_tge == claimer2_allo * tge_ratio / tge_denom, 1);
        token_vesting::claim_entry(claimer1, PRIVATE_INDEX);
    }

    #[test(deployer=@0xcafe, operator = @0xcafe2, claimer1 = @0x543, claimer2 = @0x523)]
    #[expected_failure(abort_code = 6, location=token_vesting)]
    public entry fun test_collect_fail_by_time(deployer: &signer, operator: &signer, claimer1: &signer, claimer2: &signer) {
        let deployer_address = signer::address_of(deployer);
        let operator_address = signer::address_of(operator);
        let _deployer_address = signer::address_of(deployer);
        let claimer1_address = signer::address_of(claimer1);
        let claimer2_address = signer::address_of(claimer2);
        test_helper::setup();
        let apt_coins = test_helper::mint_apt(100);
        aptos_account::deposit_coins(operator_address, apt_coins);

        // Add reward, set policies
        let start = timestamp::now_seconds() + 1 * MONTH;
        let end = start + 12 * MONTH;
        let periods = 3 * MONTH;
        let tge_time = timestamp::now_seconds();
        let tge_ratio = 10;
        let tge_denom = 100;
        global_state::update_operator(deployer, operator_address);
        token_vesting::set_policies_entry(operator, start, end, periods, tge_time, tge_ratio, tge_denom, PRIVATE_INDEX);
        let claimer1_allo = 10 * ONE_APT;
        let claimer2_allo = 12 * ONE_APT;
        let allocates = vector[claimer1_allo, claimer2_allo];
        let claimers = vector[claimer1_address, claimer2_address];
        token_vesting::add_claimers(operator, PRIVATE_INDEX, claimers, allocates);
        // TGE time
        timestamp::fast_forward_seconds(1);
        token_vesting::claim(claimer1, PRIVATE_INDEX);
        let claimer1_balance_tge = primary_fungible_store::balance(claimer1_address, slime_token::token());
        assert!(claimer1_balance_tge == claimer1_allo * tge_ratio / tge_denom, 1);
        token_vesting::claim(claimer2, PRIVATE_INDEX);
        let claimer2_balance_tge = primary_fungible_store::balance(claimer2_address, slime_token::token());
        assert!(claimer2_balance_tge == claimer2_allo * tge_ratio / tge_denom, 1);

        // vesting time 1
        timestamp::fast_forward_seconds(1 * MONTH);
        token_vesting::claim(claimer1, PRIVATE_INDEX);
        let claimer1_balance_vest1 = primary_fungible_store::balance(claimer1_address, slime_token::token());
        assert!(
            claimer1_balance_vest1 == claimer1_balance_tge + ((claimer1_allo - claimer1_balance_tge) * ((timestamp::now_seconds() - start) / periods + 1) / ((end - start) / periods)),
            1
        );
        token_vesting::claim(claimer2, PRIVATE_INDEX);
        let claimer2_balance_vest1 = primary_fungible_store::balance(claimer2_address, slime_token::token());
        assert!(
            claimer2_balance_vest1 == claimer2_balance_tge + ((claimer2_allo - claimer2_balance_tge) * ((timestamp::now_seconds() - start) / periods + 1) / ((end - start) / periods)),
            1
        );

        // vesting time 2
        timestamp::fast_forward_seconds(3 * MONTH);
        token_vesting::claim(claimer1, PRIVATE_INDEX);
        let claimer1_balance_vest2 = primary_fungible_store::balance(claimer1_address, slime_token::token());
        assert!(
            claimer1_balance_vest2 == claimer1_balance_tge + ((claimer1_allo - claimer1_balance_tge) * ((timestamp::now_seconds() - start) / periods + 1) / ((end - start) / periods)),
            1
        );
        token_vesting::collect(deployer, PRIVATE_INDEX, deployer_address);
    }
}