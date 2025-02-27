#[test_only]
module slime::test_helper {
    use std::option;
    use std::string;
    use aptos_framework::account;
    use aptos_framework::stake;
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::coin::Coin;
    use aptos_framework::fungible_asset;
    use aptos_framework::fungible_asset::FungibleAsset;
    use aptos_framework::object;
    use aptos_framework::primary_fungible_store;
    use aptos_framework::timestamp;
    use slime::staking_escrow;
    use slime::token_vesting;
    use slime::slime_token;
    use slime::global_state;

    const ONE_APT: u64 = 100000000;

    public fun setup() {
        timestamp::set_time_has_started_for_testing(&account::create_signer_for_test(@0x1));
        stake::initialize_for_test(&account::create_signer_for_test(@0x1));
        &account::create_signer_for_test(@0xcafe);
        &account::create_signer_for_test(@0xcafe2);
        global_state::init_for_test(deployer());
        slime_token::initialize();
        token_vesting::initialize();
        staking_escrow::initialize();
    }

    public fun mint_apt(apt_amount: u64): Coin<AptosCoin> {
        stake::mint_coins(apt_amount * ONE_APT)
    }

    public inline fun deployer(): &signer {
        &account::create_signer_for_test(@0xcafe)
    }

    public fun create_fungible_asset_and_mint(name: vector<u8>, decimals:  u8, amount: u64): FungibleAsset {
        let token_metadata = &object::create_named_object(deployer(), name);
        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            token_metadata,
            option::none(),
            string::utf8(name),
            string::utf8(name),
            decimals,
            string::utf8(b""),
            string::utf8(b""),
        );
        let mint_ref = &fungible_asset::generate_mint_ref(token_metadata);
        fungible_asset::mint(mint_ref, amount)
    }
}