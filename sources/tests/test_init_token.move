#[test_only]
module slime::test_init_token {
    use std::signer;
    use aptos_framework::primary_fungible_store;
    use slime::slime_token;
    use slime::test_helper;
    const INIT_TREASURY_AMOUNT: u64 =   1_000_000_000 * 100_000_000;
    const INIT_COMMUNITY_REWARDS_AMOUNT: u64 =   300_000_000 * 100_000_000;
    const INIT_PLAYER_REWARDS_AMOUNT: u64 =   300_000_000 * 100_000_000;
    const INIT_TEAM_AMOUNT: u64 = 120_000_000 * 100_000_000;
    const INIT_PRIVATE_AMOUNT: u64 = 160_000_000 * 100_000_000;
    const INIT_LIQUIDITY_AMOUNT: u64 =   100_000_000 * 100_000_000;
    const INIT_AIRDROP_AMOUNT: u64 = 20_000_000 * 100_000_000;
    #[test(recipient = @0xdead)]
    fun test_e2e(recipient: &signer) {
        test_helper::setup();
        let token_minted = slime_token::test_mint(100000);
        primary_fungible_store::deposit(signer::address_of(recipient), token_minted);
        assert!(
            (slime_token::total_supply() as u64) == 100000 + INIT_AIRDROP_AMOUNT + INIT_TEAM_AMOUNT +
                INIT_COMMUNITY_REWARDS_AMOUNT + INIT_LIQUIDITY_AMOUNT + INIT_PLAYER_REWARDS_AMOUNT + INIT_TREASURY_AMOUNT +
                INIT_PRIVATE_AMOUNT,
            0);
        assert!(primary_fungible_store::balance(signer::address_of(recipient), slime_token::token()) == 100000, 1);
    }
}
