module slime::token_vesting {
    use std::signer;
    use std::string;
    use std::vector;
    use aptos_std::math64;
    use aptos_std::smart_table;
    use aptos_framework::object::{Object, ExtendRef};
    use aptos_std::smart_table::SmartTable;
    use aptos_framework::event;
    use aptos_framework::fungible_asset;
    use aptos_framework::fungible_asset::FungibleStore;
    use aptos_framework::object;
    use aptos_framework::primary_fungible_store;
    use aptos_framework::timestamp;
    use slime::global_state;
    use slime::slime_token;

    const TOKEN_VESTING_NAME: vector<u8> = b"token_vesting";
    const TREASURY_NAME: vector<u8> = b"TREASURY";
    const COMMUNITY_NAME: vector<u8> = b"COMMUNITY";
    const PLAYER_REWARDS_NAME: vector<u8> = b"PLAYER_REWARDS";
    const TEAM_NAME: vector<u8> = b"TEAM";
    const PRIVATE_NAME: vector<u8> = b"PRIVATE";
    const LIQUIDITY_NAME: vector<u8> = b"LIQUIDITY";
    const AIRDROP_NAME: vector<u8> = b"AIRDROP";
    const TREASURY_INDEX:u8 = 0;
    const COMMUNITY_INDEX:u8 = 1;
    const PLAYER_REWARDS_INDEX:u8 = 2;
    const TEAM_INDEX:u8 = 3;
    const PRIVATE_INDEX:u8 = 4;
    const LIQUIDITY_INDEX:u8 = 5;
    const AIRDROP_INDEX:u8 = 6;

    /// Not authorized to perform this action
    const ENOT_AUTHORIZED: u64 = 0;
    /// Not vesting info not exist
    const ENOT_VESTING_INFO_NOT_EXIST: u64 = 1;
    /// Not Already added claimer
    const ENOT_ALREADY_ADD: u64 = 2;
    /// Not Allocations completely vested
    const ENOT_COMPLETELY_VESTED: u64 = 3;
    /// Not startTime and endTime not match
    const ENOT_DATA_MISS_MATCH: u64 = 4;
    /// Not Beneficiary must not be address zero
    const ENOT_BENEFICAIARY_MUST_NOT_ZERO: u64 = 5;
    /// Not vesting is running now
    const ENOT_VESTING_RUNNING: u64 = 6;

    // 1B * 1e8
    const APT: u64 = 1_00_000_000;
    const INIT_TREASURY_AMOUNT: u64 =   1_000_000_000 * 100_000_000;
    const INIT_COMMUNITY_REWARDS_AMOUNT: u64 =   300_000_000 * 100_000_000;
    const INIT_PLAYER_REWARDS_AMOUNT: u64 =   300_000_000 * 100_000_000;
    const INIT_TEAM_AMOUNT: u64 = 120_000_000 * 100_000_000;
    const INIT_PRIVATE_AMOUNT: u64 = 160_000_000 * 100_000_000;
    const INIT_LIQUIDITY_AMOUNT: u64 =   100_000_000 * 100_000_000;
    const INIT_AIRDROP_AMOUNT: u64 = 20_000_000 * 100_000_000;
    const ONE_DAY:u64 = 86400;

    /// store claimer info
    struct ClaimerInfo has key, store, copy, drop{
        allocated: u64,
        claimed: u64,
        is_refund: bool
    }

    /// Stores vesting info of a vesting.
    struct VestingInfo has key, store {
        stores: Object<FungibleStore>,
        extendRef: ExtendRef,
        claimers: SmartTable<address, ClaimerInfo>,
        start: u64,
        end: u64,
        periods: u64,
        total_periods_num: u64,
        tge_time: u64,
        tge_ratio: u64,
        tge_denom: u64,
    }

    /// Stores vesting configs
    struct VestingConfigs has key, store {
        treasury: VestingInfo,
        community: VestingInfo,
        player_rewards: VestingInfo,
        team: VestingInfo,
        private: VestingInfo,
        liquidity: VestingInfo,
        airdrop: VestingInfo,
    }

    #[event]
    struct Claim has drop, store {
        claimer: address,
        amount: u64,
        timestamp: u64
    }

    #[event]
    struct AddClaimers has drop, store {
        claimers: vector<address>,
        allocates: vector<u64>,
        timestamp: u64
    }

    #[event]
    struct RemoveClaimer has drop, store {
        claimers: address,
        claim_info: ClaimerInfo,
        timestamp: u64
    }

    #[event]
    struct CollectToken has drop, store {
        admin: address,
        amount: u64,
        timestamp: u64
    }

    /// Deploy the AMNIS token.
    public entry fun initialize() {
        if (is_initialized()) {
            return
        };
        let metadata = slime_token::token();
        let treasury_constructor_ref = &object::create_named_object(&global_state::config_signer(), TREASURY_NAME);
        let treasury_stores = fungible_asset::create_store(treasury_constructor_ref, metadata);
        let treasury_tokens = slime_token::mint(INIT_TREASURY_AMOUNT);
        fungible_asset::deposit(treasury_stores, treasury_tokens);
        let public_extendRef = object::generate_extend_ref(treasury_constructor_ref);
        let treasury_vesting = VestingInfo {
            stores: treasury_stores,
            extendRef: public_extendRef,
            claimers: smart_table::new(),
            start: 0,
            end: 0,
            periods: 0,
            total_periods_num: 2000,
            tge_time: 0,
            tge_ratio: 0,
            tge_denom: 100,
        };
        let player_rewards_constructor_ref = &object::create_named_object(&global_state::config_signer(), PLAYER_REWARDS_NAME);
        let player_rewards_stores = fungible_asset::create_store(player_rewards_constructor_ref, metadata);
        let player_rewards_tokens = slime_token::mint(INIT_PLAYER_REWARDS_AMOUNT);
        fungible_asset::deposit(player_rewards_stores, player_rewards_tokens);
        let player_rewards_extendRef = object::generate_extend_ref(player_rewards_constructor_ref);
        let player_rewards_vesting = VestingInfo {
            stores: player_rewards_stores,
            extendRef: player_rewards_extendRef,
            claimers: smart_table::new(),
            start: 0,
            end: 0,
            periods: ONE_DAY,
            total_periods_num: 1980,
            tge_time: 0,
            tge_ratio: 1,
            tge_denom: 100,
        };
        let private_constructor_ref = &object::create_named_object(&global_state::config_signer(), PRIVATE_NAME);
        let private_stores = fungible_asset::create_store(private_constructor_ref, metadata);
        let private_tokens = slime_token::mint(INIT_PRIVATE_AMOUNT);
        fungible_asset::deposit(private_stores, private_tokens);
        let private_extendRef = object::generate_extend_ref(private_constructor_ref);
        let private_vesting = VestingInfo {
            stores: private_stores,
            extendRef: private_extendRef,
            claimers: smart_table::new(),
            start: 0,
            end: 0,
            periods: ONE_DAY,
            total_periods_num: 900,
            tge_time: 0,
            tge_ratio: 10,
            tge_denom: 100,
        };
        let liquidity_constructor_ref = &object::create_named_object(&global_state::config_signer(), LIQUIDITY_NAME);
        let liquidity_stores = fungible_asset::create_store(liquidity_constructor_ref, metadata);
        let liquidity_tokens = slime_token::mint(INIT_LIQUIDITY_AMOUNT);
        fungible_asset::deposit(liquidity_stores, liquidity_tokens);
        let liquidity_extendRef = object::generate_extend_ref(liquidity_constructor_ref);
        let liquidity_vesting = VestingInfo {
            stores: liquidity_stores,
            extendRef: liquidity_extendRef,
            claimers: smart_table::new(),
            start: 0,
            end: 0,
            periods: 0,
            total_periods_num: 0,
            tge_time: 0,
            tge_ratio: 100,
            tge_denom: 100,
        };
        let community_constructor_ref = &object::create_named_object(&global_state::config_signer(), COMMUNITY_NAME);
        let community_stores = fungible_asset::create_store(community_constructor_ref, metadata);
        let community_tokens = slime_token::mint(INIT_COMMUNITY_REWARDS_AMOUNT);
        fungible_asset::deposit(community_stores, community_tokens);
        let community_extendRef = object::generate_extend_ref(community_constructor_ref);
        let community_vesting = VestingInfo {
            stores: community_stores,
            extendRef: community_extendRef,
            claimers: smart_table::new(),
            start: 0,
            end: 0,
            periods: 0,
            total_periods_num: 2000,
            tge_time: 0,
            tge_ratio: 0,
            tge_denom: 100,
        };
        let team_constructor_ref = &object::create_named_object(&global_state::config_signer(), TEAM_NAME);
        let team_stores = fungible_asset::create_store(team_constructor_ref, metadata);
        let team_tokens = slime_token::mint(INIT_TEAM_AMOUNT);
        fungible_asset::deposit(team_stores, team_tokens);
        let team_extendRef = object::generate_extend_ref(team_constructor_ref);
        let team_vesting = VestingInfo {
            stores: team_stores,
            extendRef: team_extendRef,
            claimers: smart_table::new(),
            start: 0,
            end: 0,
            periods: ONE_DAY,
            total_periods_num: 2000,
            tge_time: 0,
            tge_ratio: 0,
            tge_denom: 100,
        };
        let airdrop_constructor_ref = &object::create_named_object(&global_state::config_signer(), AIRDROP_NAME);
        let airdrop_stores = fungible_asset::create_store(airdrop_constructor_ref, metadata);
        let airdrop_tokens = slime_token::mint(INIT_AIRDROP_AMOUNT);
        fungible_asset::deposit(airdrop_stores, airdrop_tokens);
        let airdrop_extendRef = object::generate_extend_ref(airdrop_constructor_ref);
        let airdrop_vesting = VestingInfo {
            stores: airdrop_stores,
            extendRef: airdrop_extendRef,
            claimers: smart_table::new(),
            start: 0,
            end: 0,
            periods: ONE_DAY,
            total_periods_num: 900,
            tge_time: 0,
            tge_ratio: 10,
            tge_denom: 100,
        };
        move_to(&global_state::config_signer(), VestingConfigs {
            treasury: treasury_vesting,
            community: community_vesting,
            player_rewards: player_rewards_vesting,
            team: team_vesting,
            private: private_vesting,
            liquidity: liquidity_vesting,
            airdrop: airdrop_vesting,
        });

        global_state::add_address(string::utf8(TOKEN_VESTING_NAME), signer::address_of(&global_state::config_signer()));
    }

    #[view]
    public fun is_initialized(): bool {
        global_state::address_exists(string::utf8(TOKEN_VESTING_NAME))
    }

    #[view]
    public fun get_total_allocated(beneficiary: address, vesting_index: u8): u64 acquires VestingConfigs {
        let claimer_info = get_claimer_info(beneficiary, get_vesting_info_mut(vesting_index, get_vesting_configs_mut()));
        claimer_info.allocated
    }

    #[view]
    public fun get_total_claimed(user: address, vesting_index: u8): u64 acquires VestingConfigs {
        let vesting_info = get_vesting_info_mut(vesting_index, get_vesting_configs_mut());
        let claimer_info =
            get_claimer_info(user, vesting_info);
        claimer_info.claimed
    }

    #[view]
    public fun get_avaiable_token(claimer_address: address, vesting_index: u8): u64 acquires VestingConfigs {
        let vesting_configs = get_vesting_configs_mut();
        let vesting_info = get_vesting_info_mut(vesting_index, vesting_configs);
        let claimer_info =
            get_claimer_info(claimer_address, vesting_info);
        if (!(claimer_info.allocated > 0) || claimer_info.is_refund) {
            return 0
        };
        let tgeAmount = math64::mul_div(claimer_info.allocated, vesting_info.tge_ratio, vesting_info.tge_denom);
        let total: &mut u64 = &mut 0;
        let current_time = timestamp::now_seconds();
        if (current_time > vesting_info.tge_time) {
            total = &mut (*total + tgeAmount);
        };
        if (current_time < vesting_info.end && current_time > vesting_info.start) {
            let num_periods = (current_time - vesting_info.start) / vesting_info.periods + 1;
            total = &mut (*total + math64::mul_div(claimer_info.allocated - tgeAmount, num_periods, vesting_info.total_periods_num));
        } else if (current_time >= vesting_info.end) {
            total = &mut claimer_info.allocated;
        };
        total = &mut (*total - claimer_info.claimed);
        *total
    }

    public entry fun set_policies_entry(
        admin: &signer,
        new_start: u64,
        new_end: u64,
        new_periods: u64,
        new_tge_time: u64,
        new_tge_ratio: u64,
        new_tge_denom: u64,
        vesting_index: u8
    ) acquires VestingConfigs {
        let vesting_info = get_vesting_info_mut(vesting_index,get_vesting_configs_mut());
        if (vesting_index == AIRDROP_INDEX || vesting_index == PRIVATE_INDEX) {
            assert!(signer::address_of(admin) == global_state::operator(), ENOT_AUTHORIZED);
        } else {
            assert!(signer::address_of(admin) == global_state::governance(), ENOT_AUTHORIZED);
        };
        set_policies(new_start, new_end, new_periods, new_tge_time, new_tge_ratio, new_tge_denom, vesting_info);
    }

     fun set_policies(
        new_start: u64,
        new_end: u64,
        new_periods: u64,
        new_tge_time: u64,
        new_tge_ratio: u64,
        new_tge_denom: u64,
        vesting_info: &mut VestingInfo
    ) {
        assert!((new_end - new_start) % new_periods == 0, ENOT_DATA_MISS_MATCH);
        assert!(new_end > new_start, ENOT_DATA_MISS_MATCH);
        vesting_info.start = new_start;
        vesting_info.end = new_end;
        vesting_info.periods = new_periods;
        vesting_info.tge_time = new_tge_time;
        vesting_info.tge_ratio = new_tge_ratio;
        vesting_info.tge_denom = new_tge_denom;
        vesting_info.total_periods_num = (new_end - new_start) / new_periods;
    }

    public entry fun add_claimer_entry(
        admin: &signer,
        vesting_index: u8,
        claimer: address,
        allocated: u64
    ) acquires VestingConfigs {
        add_claimer(admin, vesting_index, claimer, allocated);
    }

    public fun add_claimer(admin: &signer, vesting_index: u8, claimer: address, allocated: u64) acquires VestingConfigs {
        let vesting_info = get_vesting_info_mut(vesting_index, get_vesting_configs_mut());
        if (vesting_index == AIRDROP_INDEX || vesting_index == PRIVATE_INDEX) {
            assert!(signer::address_of(admin) == global_state::operator(), ENOT_AUTHORIZED);
        } else {
            assert!(signer::address_of(admin) == global_state::governance(), ENOT_AUTHORIZED);
        };
        let claimer_info = get_safe_claimer_info_mut(claimer, vesting_info);
        assert!(claimer_info.allocated == 0, ENOT_ALREADY_ADD);
        smart_table::upsert(&mut vesting_info.claimers, claimer, ClaimerInfo {
            allocated,
            claimed: 0,
            is_refund: false
        });
    }

    public entry fun add_claimers_entry(
        admin: &signer,
        vesting_index: u8,
        claimers: vector<address>,
        allocates: vector<u64>
    ) acquires VestingConfigs {
        add_claimers(admin, vesting_index, claimers, allocates);
    }

    public fun add_claimers(
        admin: &signer,
        vesting_index: u8,
        claimers: vector<address>,
        allocates: vector<u64>
    ) acquires VestingConfigs {
        let vesting_info = get_vesting_info_mut(vesting_index, get_vesting_configs_mut());
        if (vesting_index == AIRDROP_INDEX || vesting_index == PRIVATE_INDEX) {
            assert!(signer::address_of(admin) == global_state::operator(), ENOT_AUTHORIZED);
        } else {
            assert!(signer::address_of(admin) == global_state::governance(), ENOT_AUTHORIZED);
        };
        vector::zip(claimers, allocates, | claimer, allocate|{
            let claimer_info = get_safe_claimer_info_mut(claimer, vesting_info);
            assert!(claimer_info.allocated == 0, ENOT_ALREADY_ADD);
            assert!(allocate > 0, ENOT_BENEFICAIARY_MUST_NOT_ZERO);
            smart_table::upsert(&mut vesting_info.claimers, claimer, ClaimerInfo {
                allocated: allocate,
                claimed: 0,
                is_refund: false
            });
        });
        event::emit(AddClaimers {
            claimers,
            allocates,
            timestamp: timestamp::now_seconds()
        });
    }

    public entry fun claim_entry(claimer: &signer, vesting_index: u8) acquires VestingConfigs {
        claim(claimer, vesting_index);
    }

    public fun claim(claimer: &signer, vesting_index: u8) acquires VestingConfigs {
        let claimer_address = signer::address_of(claimer);
        let vesting_configs = get_vesting_configs_mut();
        let vesting_info = get_vesting_info_mut(vesting_index, vesting_configs);
        let claimer_info = get_safe_claimer_info_mut(claimer_address, vesting_info);
        assert!(claimer_info.allocated > 0, ENOT_ALREADY_ADD);
        let tgeAmount = math64::mul_div(claimer_info.allocated, vesting_info.tge_ratio, vesting_info.tge_denom);
        let total: &mut u64 = &mut 0;
        let current_time = timestamp::now_seconds();
        if (current_time > vesting_info.tge_time) {
            total = &mut (*total + tgeAmount);
        };
        if (current_time < vesting_info.end && current_time > vesting_info.start) {
            let num_periods = (current_time - vesting_info.start) / vesting_info.periods + 1;
            total = &mut (*total + math64::mul_div(claimer_info.allocated - tgeAmount, num_periods, vesting_info.total_periods_num));
        } else if (current_time >= vesting_info.end) {
            total = &mut claimer_info.allocated;
        };
        total = &mut (*total - claimer_info.claimed);
        assert!(*total > 0, ENOT_COMPLETELY_VESTED);
        claimer_info.claimed = claimer_info.claimed + *total;
        let extend_ref = &vesting_info.extendRef;
        let signer = object::generate_signer_for_extending(extend_ref);
        let ami_tokens = fungible_asset::withdraw(&signer, vesting_info.stores, *total);
        primary_fungible_store::deposit(claimer_address, ami_tokens);

        event::emit(Claim {
            claimer: claimer_address,
            amount: *total,
            timestamp: current_time
        });
    }

    public entry fun remove_claimer_entry(
        admin: &signer,
        vesting_index: u8,
        claimer: address
    ) acquires VestingConfigs {
        remove_claimer(admin, vesting_index, claimer);
    }

    public fun remove_claimer(admin: &signer, vesting_index: u8, claimer: address) acquires VestingConfigs {
        let vesting_info = get_vesting_info_mut(vesting_index, get_vesting_configs_mut());
        if (vesting_index == AIRDROP_INDEX || vesting_index == PRIVATE_INDEX) {
            assert!(signer::address_of(admin) == global_state::operator(), ENOT_AUTHORIZED);
        } else {
            assert!(signer::address_of(admin) == global_state::governance(), ENOT_AUTHORIZED);
        };
        let claimer_info = get_safe_claimer_info_mut(claimer, vesting_info);
        claimer_info.allocated = 0;
        event::emit(RemoveClaimer {
            claimers: claimer,
            claim_info: *claimer_info,
            timestamp: timestamp::now_seconds()
        });
    }

    public entry fun collect(admin: &signer, vesting_index: u8, recipient: address) acquires VestingConfigs {
        let vesting_info = get_vesting_info_mut(vesting_index, get_vesting_configs_mut());
        assert!(vesting_info.end < timestamp::now_seconds(), ENOT_VESTING_RUNNING);
        if (vesting_index == AIRDROP_INDEX || vesting_index == PRIVATE_INDEX) {
            assert!(signer::address_of(admin) == global_state::operator(), ENOT_AUTHORIZED);
        } else {
            assert!(signer::address_of(admin) == global_state::governance(), ENOT_AUTHORIZED);
        };
        assert!(fungible_asset::balance(vesting_info.stores) > 0, ENOT_COMPLETELY_VESTED);
        let extend_ref = &vesting_info.extendRef;
        let signer = object::generate_signer_for_extending(extend_ref);
        let ami_amount = fungible_asset::balance(vesting_info.stores);
        let ami_tokens = fungible_asset::withdraw(&signer, vesting_info.stores, ami_amount);
        primary_fungible_store::deposit(recipient, ami_tokens);
        event::emit(CollectToken {
            admin: signer::address_of(admin),
            amount: ami_amount,
            timestamp: timestamp::now_seconds()
        });
    }

    inline fun get_claimer_info(
        claimer: address,
        vesting_info: &mut VestingInfo
    ): ClaimerInfo {
        *smart_table::borrow_with_default(&mut vesting_info.claimers, claimer, &ClaimerInfo{
            allocated: 0,
            claimed: 0,
            is_refund: false
        })
    }

    inline fun get_vesting_info_mut(
        vesting_index: u8,
        vesting_configs: &mut VestingConfigs
    ): &mut VestingInfo {
        if (vesting_index == TREASURY_INDEX) {
            &mut vesting_configs.treasury
        } else if (vesting_index == PRIVATE_INDEX) {
            &mut vesting_configs.private
        } else if (vesting_index == LIQUIDITY_INDEX) {
            &mut vesting_configs.liquidity
        } else if (vesting_index == COMMUNITY_INDEX) {
            &mut vesting_configs.community
        } else if (vesting_index == TEAM_INDEX) {
            &mut vesting_configs.team
        } else if (vesting_index == AIRDROP_INDEX) {
            &mut vesting_configs.airdrop
        } else {
            assert!(false, ENOT_VESTING_INFO_NOT_EXIST);
            &mut vesting_configs.private
        }
    }

    inline fun get_vesting_configs_mut(): &mut VestingConfigs {
        borrow_global_mut<VestingConfigs>(signer::address_of(&global_state::config_signer()))
    }

    inline fun get_safe_claimer_info_mut(
        claimer: address,
        vesting_info: &mut VestingInfo
    ): &mut ClaimerInfo {
        smart_table::borrow_mut_with_default(&mut vesting_info.claimers, claimer, ClaimerInfo {
            allocated: 0,
            claimed: 0,
            is_refund: false
        })
    }
    #[test_only]
    public fun init_for_test() {
        initialize();
    }
}
