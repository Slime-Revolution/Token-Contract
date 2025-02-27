#[test_only]
module slime::test_staking_escrow {
    use std::signer;
    use aptos_framework::fungible_asset;
    use aptos_framework::primary_fungible_store;
    use slime::epoch;
    use slime::staking_escrow;
    use slime::slime_token;
    use slime::test_helper;
    const INIT_TREASURY_AMOUNT: u64 =   1_000_000_000 * 100_000_000;
    const INIT_COMMUNITY_REWARDS_AMOUNT: u64 =   300_000_000 * 100_000_000;
    const INIT_PLAYER_REWARDS_AMOUNT: u64 =   300_000_000 * 100_000_000;
    const INIT_TEAM_AMOUNT: u64 = 120_000_000 * 100_000_000;
    const INIT_PRIVATE_AMOUNT: u64 = 160_000_000 * 100_000_000;
    const INIT_LIQUIDITY_AMOUNT: u64 =   100_000_000 * 100_000_000;
    const INIT_AIRDROP_AMOUNT: u64 = 20_000_000 * 100_000_000;
    #[test(admin = @0xcafe, recipient = @0xdead)]
    fun test_e2e(recipient: &signer, admin: &signer) {
        test_helper::setup();
        epoch::fast_forward(2);
        let token_minted = slime_token::test_mint(100000);
        primary_fungible_store::deposit(signer::address_of(recipient), token_minted);
        assert!(
            (slime_token::total_supply() as u64) == 100000 + INIT_AIRDROP_AMOUNT + INIT_TEAM_AMOUNT +
                INIT_COMMUNITY_REWARDS_AMOUNT + INIT_LIQUIDITY_AMOUNT + INIT_PLAYER_REWARDS_AMOUNT + INIT_TREASURY_AMOUNT +
                INIT_PRIVATE_AMOUNT,
            0);
        assert!(primary_fungible_store::balance(signer::address_of(recipient), slime_token::token()) == 100000, 1);
        let token_fa = test_helper::create_fungible_asset_and_mint(b"usdt", 8, 100000);
        let token_metadata = fungible_asset::metadata_from_asset(&token_fa);
        primary_fungible_store::deposit(signer::address_of(admin), token_fa);
        let nft = staking_escrow::create_lock(recipient, 1000, 104);
        let nft2 = staking_escrow::create_lock(recipient, 1000, 104);
        epoch::fast_forward(2);
        staking_escrow::add_rewards(admin, 1000, token_metadata);
        staking_escrow::add_rewards_exact_epoch(admin, 1000, token_metadata, epoch::now() - 1);
        let total_staking_power = staking_escrow::total_staking_power();
        assert!(total_staking_power == 1000, 0);
        let reward = staking_escrow::claimable_rebase(nft);
        assert!(reward == 500, 0);
        let reward = staking_escrow::claimable_rebase(nft2);
        assert!(reward == 500, 0);
        epoch::fast_forward( 1);
        let reward = staking_escrow::claimable_rebase(nft);
        assert!(reward == 1000, 0);
        let reward = staking_escrow::claimable_rebase(nft2);
        assert!(reward == 1000, 0);
        staking_escrow::claim_reward(recipient, nft, token_metadata);
        let usdt_balance = primary_fungible_store::balance(signer::address_of(recipient), token_metadata);
        assert!(usdt_balance == 1000, 0);
        staking_escrow::claim_reward(recipient, nft2, token_metadata);
        let usdt_balance_2 = primary_fungible_store::balance(signer::address_of(recipient), token_metadata);
        assert!(usdt_balance_2 == 2000, 0);
    }
}
