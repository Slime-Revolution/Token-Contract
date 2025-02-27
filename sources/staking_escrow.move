/// This module defines a struct storing the metadata of the block and new block events.
module slime::staking_escrow {
    use std::option;
    use std::signer;
    use std::string;
    use aptos_std::math128;
    use aptos_std::smart_table;
    use aptos_std::smart_table::SmartTable;
    use aptos_std::smart_vector;
    use aptos_std::smart_vector::SmartVector;
    use aptos_std::string_utils;
    use aptos_framework::event;
    use aptos_framework::fungible_asset;
    use aptos_framework::fungible_asset::{FungibleAsset, Metadata};
    use aptos_framework::object;
    use aptos_framework::object::{DeleteRef, Object, TransferRef};
    use aptos_framework::primary_fungible_store;
    use aptos_token_objects::collection;
    use aptos_token_objects::royalty::Royalty;
    use aptos_token_objects::token;
    use aptos_token_objects::token::BurnRef;
    use slime::global_state;
    use slime::epoch;
    use slime::slime_token;
    const COLLECTION_NAME: vector<u8> = b"Slime Staking Tokens";
    const COLLECTION_DESC: vector<u8> = b"Slime Staking Tokens";
    const TOKEN_NAME: vector<u8> = b"gSRC";
    const TOKEN_DESC: vector<u8> = b"NFT representing staking power in Slime corresponding to $SRC locked up";
    // TODO: Tweak in mainnet
    const SLIME_URI: vector<u8> = b"https://aptos.slimerevolution.com/static/media/";
    const MIN_LOCKUP_EPOCHS: u64 = 2; // 2 weeks
    const MAX_LOCKUP_EPOCHS: u64 = 208; // 2 years (52 weeks = 1 year)

    const REBASE_POOL: vector<u8> = b"REBASE_POOL";

    /// Only $SRC are accepted.
    const EONLY_SLIME_ACCEPTED: u64 = 1;
    /// The given lockup period is shorter than the minimum allowed.
    const ELOCKUP_TOO_SHORT: u64 = 2;
    /// The given lockup period is longer than the maximum allowed.
    const ELOCKUP_TOO_LONG: u64 = 3;
    /// The given token is not owned by the given signer.
    const ENOT_VE_TOKEN_OWNER: u64 = 4;
    /// The lockup period for the given token has not expired yet.
    const ELOCKUP_HAS_NOT_EXPIRED: u64 = 5;
    /// Either locked amount or lockup duration or both has to increase.
    const EINVALID_LOCKUP_CHANGE: u64 = 6;
    /// The new lockup period has to be strictly longer than the old one.
    const ELOCKUP_MUST_BE_EXTENDED: u64 = 7;
    /// The amount to lockup must be more than zero.
    const EINVALID_AMOUNT: u64 = 8;
    /// Voting power and total supply can only be looked up upto a certain number of epochs in the past.
    const ECANNOT_LOOK_UP_PAST_VOTING_POWER: u64 = 9;
    /// Cannot add to an expired lockup. Need to extend_lockup first.
    const ELOCKUP_EXPIRED: u64 = 10;
    /// Cannot add a rebase to the current epoch.
    const ECANNOT_ADD_REBASE_TO_CURRENT_EPOCH: u64 = 11;
    /// Total Amounts $SRC not valid.
    const ETOTAL_SRC_NOT_VALID: u64 = 12;
    /// Rebase amount still exists, claim it first.
    const EREBASE_STILL_EXISTS: u64 = 13;

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct GSRCToken has key {
        locked_amount: u64,
        end_epoch: u64,
        start_epoch: u64,
        // Snapshots of previous locked amount and duration.
        // For now, this will only have two snapshots corresponding to the last two epochs where the gSRC NFT is
        // created or has its amount or duration updated.
        // This allows for quickly querying a gSRC NFT's voting power at epochs from the first snapshot on.
        snapshots: SmartVector<TokenSnapshot>,
        // The next epoch where the gSRC NFT is eligible for a rebase.
        next_rebase_epoch: u64,
    }

    struct TokenSnapshot has drop, store {
        epoch: u64,
        locked_amount: u64,
        end_epoch: u64,
    }

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    /// Separate struct in the same resource group as VeSlimeToken to isolate administrative capabilities.
    struct GSRCTokenRefs has key {
        burn_ref: BurnRef,
        transfer_ref: TransferRef,
    }

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct GSRCDeleteRef has key {
        delete_ref: DeleteRef,
    }

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct GSrcCollection has key {
        // This is the total voting power across all gSRC NFTs, multiplied by max_lockup_epochs to minimize
        // rounding error.
        // Total voting power is computed for each epoch until the maximum number of epochs allowed from the last
        // user's lockup update. If there's no value, the supply is zero because all lockups have already expired.
        // We store this as a SmartTable to optimize gas.
        unscaled_total_voting_power_per_epoch: SmartTable<u64, u128>,
        // Amount of rewards added for locked token, organized by epoch added.
        rewards: SmartTable<u64, u64>,
    }

    #[event]
    struct CreateLockEvent has drop, store {
        owner: address,
        amount: u64,
        lockup_end_epoch: u64,
        ve_token: Object<GSRCToken>
    }

    #[event]
    struct ExtendLockupEvent has drop, store {
        owner: address,
        old_lockup_end_epoch: u64,
        new_lockup_end_epoch: u64,
        ve_token: Object<GSRCToken>
    }

    #[event]
    struct IncreaseAmountEvent has drop, store {
        owner: address,
        old_amount: u64,
        new_amount: u64,
        ve_token: Object<GSRCToken>
    }

    #[event]
    struct WithdrawEvent has drop, store {
        owner: address,
        amount: u64,
        ve_token: Object<GSRCToken>
    }

    public entry fun initialize() {
        if (is_initialized()) {
            return
        };
        // Create the voting escrow NFT collection.
        // TODO: Consider fancy levels/images for locks based on durations and amounts?
        let collection_data = GSrcCollection {
            unscaled_total_voting_power_per_epoch: smart_table::new<u64, u128>(),
            rewards: smart_table::new(),
        };
        let collection_construct_ref = &collection::create_unlimited_collection(
            &global_state::config_signer(),
            string::utf8(COLLECTION_DESC),
            string::utf8(COLLECTION_NAME),
            // No royalty.
            option::none<Royalty>(),
            string::utf8(SLIME_URI),
        );

        // Make the collection a $SRC store to store the rebase rewards.
        fungible_asset::create_store(collection_construct_ref, slime_token::token());

        let collection_signer = &object::generate_signer(collection_construct_ref);
        move_to(collection_signer, collection_data);

        global_state::add_address(string::utf8(COLLECTION_NAME), signer::address_of(collection_signer));

    }

    #[view]
    public fun is_initialized(): bool {
        global_state::address_exists(string::utf8(COLLECTION_NAME))
    }

    #[view]
    public fun locked_amount(token: Object<GSRCToken>): u64 acquires GSRCToken {
        safe_ve_token(&token).locked_amount
    }

    #[view]
    public fun voting_escrow_collection(): address {
        global_state::get_address(string::utf8(COLLECTION_NAME))
    }

    #[view]
    public fun get_voting_power(token: Object<GSRCToken>): u64 acquires GSRCToken {
        get_voting_power_at_epoch(token, epoch::now())
    }

    #[view]
    public fun get_voting_power_at_epoch(ve_token: Object<GSRCToken>, epoch: u64): u64 acquires GSRCToken {
        let token_data = safe_ve_token(&ve_token);
        let (locked_amount, lockup_end_epoch, lockup_start_epoch) = if (epoch == epoch::now()) {
            (token_data.locked_amount, token_data.end_epoch, token_data.start_epoch)
        } else {
            // Do a linear scan for now since the number of snapshots is limited. We can consider a binary search in
            // the future if needed.
            let snapshots = &token_data.snapshots;
            let i = smart_vector::length(snapshots);
            while (i > 0 && smart_vector::borrow(snapshots, i - 1).epoch > epoch) {
                i = i - 1;
            };
            assert!(i > 0, ECANNOT_LOOK_UP_PAST_VOTING_POWER);
            let snapshot = smart_vector::borrow(snapshots, i - 1);
            (snapshot.locked_amount, snapshot.end_epoch, snapshot.epoch)
        };

        if (lockup_end_epoch <= epoch) {
            0
        } else {
            locked_amount * (lockup_end_epoch - lockup_start_epoch) / MAX_LOCKUP_EPOCHS
        }
    }

    #[view]
    public fun total_staking_power(): u128 acquires GSrcCollection {
        total_staking_power_at(epoch::now())
    }

    #[view]
    public fun total_staking_power_at(epoch: u64): u128 acquires GSrcCollection {
        let total_staking_power_per_epoch = &safe_ve_collection().unscaled_total_voting_power_per_epoch;
        total_staking_power_at_internal(total_staking_power_per_epoch, epoch)
    }

    #[view]
    public fun remaining_lockup_epochs(ve_token: Object<GSRCToken>): u64 acquires GSRCToken {
        let end_epoch = get_lockup_expiration_epoch(ve_token);
        let current_epoch = epoch::now();
        if (end_epoch <= current_epoch) {
            0
        } else {
            end_epoch - current_epoch
        }
    }

    #[view]
    public fun get_lockup_expiration_epoch(ve_token: Object<GSRCToken>): u64 acquires GSRCToken {
        safe_ve_token(&ve_token).end_epoch
    }

    #[view]
    public fun get_lockup_expiration_time(ve_token: Object<GSRCToken>): u64 acquires GSRCToken {
        epoch::to_seconds(get_lockup_expiration_epoch(ve_token))
    }

    #[view]
    public fun nft_exists(ve_token: address): bool {
        exists<GSRCToken>(ve_token)
    }

    #[view]
    public fun max_lockup_epochs(): u64 {
        MAX_LOCKUP_EPOCHS
    }

    #[view]
    public fun claimable_rebase(ve_token: Object<GSRCToken>): u64 acquires GSrcCollection, GSRCToken {
        claimable_rewards_internal(ve_token)
    }

    /// Mint a gSRC NFT and lock $SRC from the owner's primary store.
    public entry fun create_lock_entry(owner: &signer, amount: u64, lockup_epochs: u64) acquires GSrcCollection {
        create_lock(owner, amount, lockup_epochs);
    }

    public entry fun create_lock_for(
        owner: &signer,
        amount: u64,
        lockup_epochs: u64,
        recipient: address,
    ) acquires GSrcCollection {
        let slime_tokens = primary_fungible_store::withdraw(owner, slime_token::token(), amount);
        create_lock_with(slime_tokens, lockup_epochs, recipient);
    }

    public fun create_lock(
        owner: &signer,
        amount: u64,
        lockup_epochs: u64,
    ): Object<GSRCToken> acquires GSrcCollection {
        let slime_tokens = primary_fungible_store::withdraw(owner, slime_token::token(), amount);
        create_lock_with(slime_tokens, lockup_epochs, signer::address_of(owner))
    }

    /// Mint a gSRC NFT with the given $SRC and return a reference to it.
    public fun create_lock_with(
        tokens: FungibleAsset,
        lockup_epochs: u64,
        recipient: address,
    ): Object<GSRCToken> acquires GSrcCollection {
        let amount = fungible_asset::amount(&tokens);
        assert!(amount > 0, EINVALID_AMOUNT);

        validate_lockup_epochs(lockup_epochs);
        let slime_token_obj = slime_token::token();
        assert!(
            fungible_asset::asset_metadata(&tokens) == object::convert(slime_token_obj),
            EONLY_SLIME_ACCEPTED,
        );

        // Mint a new gSRC NFT for the lock.
        let slime_signer = &global_state::config_signer();
        let ve_token = &token::create_from_account(
            slime_signer,
            string::utf8(COLLECTION_NAME),
            string::utf8(TOKEN_DESC),
            string::utf8(TOKEN_NAME),
            // No royalty.
            option::none<Royalty>(),
            string::utf8(SLIME_URI),
        );
        let ve_token_signer = &object::generate_signer(ve_token);
        let lockup_end_epoch = epoch::now() + lockup_epochs;
        let token_data = GSRCToken {
            locked_amount: amount,
            start_epoch: epoch::now(),
            end_epoch: lockup_end_epoch,
            snapshots: smart_vector::new(),
            next_rebase_epoch: epoch::now(),
        };
        update_snapshots(&mut token_data, amount, lockup_end_epoch);
        move_to(ve_token_signer, token_data);
        move_to(ve_token_signer, GSRCTokenRefs {
            burn_ref: token::generate_burn_ref(ve_token),
            transfer_ref: object::generate_transfer_ref(ve_token),
        });
        move_to(ve_token_signer, GSRCDeleteRef {
            delete_ref: object::generate_delete_ref(ve_token),
        });

        // Turn the gSRC NFT into a fungible store so we can store the locked up $SRC there.
        let ve_token_ref = fungible_asset::create_store(ve_token, slime_token_obj);
        fungible_asset::deposit(ve_token_ref, tokens);
        // Disable owner transfers of the stored $SRC so it cannot be moved until the lockup has expired.
        // This also prevents anyone from sending more $SRC into the gSRC NFT without going through the flow
        // here.
        slime_token::disable_transfer(ve_token_ref);

        // Transfer the gSRC token to the specified recipient.
        object::transfer(slime_signer, ve_token_ref, recipient);
        let mutator_ref = token::generate_mutator_ref(ve_token);
        let ve_token = object::object_from_constructor_ref(ve_token);
        let base_uri = string::utf8(SLIME_URI);
        string::append(&mut base_uri, string_utils::to_string(&object::object_address(&ve_token)));
        token::set_uri(&mutator_ref, base_uri);
        event::emit(CreateLockEvent { owner: recipient, amount, lockup_end_epoch, ve_token });

        // Has to called for every function that modifies amount or lockup duration of any gSRC NFT.
        // Always at the end of a function so we don't forget.
        // Old amount is 0 because this is a new lockup.
        update_manifested_total_supply(0, 0, amount, lockup_end_epoch, epoch::now());
        ve_token
    }

    public entry fun create_reward_pool(admin: &signer, token: Object<Metadata>) {
        global_state::only_governance(admin);
        primary_fungible_store::ensure_primary_store_exists(voting_escrow_collection(), token);
    }

    public entry fun add_rewards_exact_epoch(admin: &signer, amount: u64, token: Object<Metadata>, epoch: u64) acquires GSrcCollection {
        assert!(amount > 0, EINVALID_AMOUNT);
        let rewards_token = primary_fungible_store::withdraw(admin, token, amount);
        let collection_data = unchecked_mut_ve_collection();
        smart_table::add(&mut collection_data.rewards, epoch, amount);
        primary_fungible_store::deposit(global_state::config_address(), rewards_token);
    }

    public entry fun add_rewards(admin: &signer, amount: u64, token: Object<Metadata>) acquires GSrcCollection {
        let current_epoch = epoch::now();
        assert!(amount > 0, EINVALID_AMOUNT);
        let rewards_token = primary_fungible_store::withdraw(admin, token, amount);
        let collection_data = unchecked_mut_ve_collection();
        smart_table::add(&mut collection_data.rewards, current_epoch, amount);
        primary_fungible_store::deposit(global_state::config_address(), rewards_token);
    }

    /// Claim all rebase rewards for a given token. The rewards will be added to the lock.
    public entry fun claim_reward(
        owner: &signer,
        ve_token: Object<GSRCToken>,
        token: Object<Metadata>
    ) acquires GSrcCollection, GSRCToken {
        assert!(object::is_owner(ve_token, signer::address_of(owner)), ENOT_VE_TOKEN_OWNER);
        let rewards_claimable = claimable_rewards_internal(ve_token);
        if(rewards_claimable > 0){
            let reward = primary_fungible_store::withdraw(&global_state::config_signer(), token, rewards_claimable);
            primary_fungible_store::deposit(signer::address_of(owner), reward);
            unchecked_mut_ve_token(&ve_token).next_rebase_epoch = epoch::now();
        }
    }

    fun claimable_rewards_internal(ve_token: Object<GSRCToken>): u64 acquires GSrcCollection, GSRCToken {
        let collection_data = safe_ve_collection();
        let epoch = safe_ve_token(&ve_token).next_rebase_epoch;
        let rewards = 0;
        while (epoch < epoch::now()) {
            let total_rewards_amount =
                (*smart_table::borrow_with_default(&collection_data.rewards, epoch, &0) as u128);
            if (total_rewards_amount > 0) {
                let voting_power = (get_voting_power_at_epoch(ve_token, epoch) as u128);
                let total_voting_power =
                    total_staking_power_at_internal(&collection_data.unscaled_total_voting_power_per_epoch, epoch);
                rewards = rewards + math128::mul_div(voting_power, total_rewards_amount, total_voting_power);
            };
            epoch = epoch + 1;
        };
        (rewards as u64)
    }

    /// Can be called by owner to deposit more $SRC into a gSRC NFT.
    public entry fun increase_amount_entry(
        owner: &signer,
        ve_token: Object<GSRCToken>,
        amount: u64,
    ) acquires GSRCToken, GSrcCollection {
        let slime_tokens = primary_fungible_store::withdraw(owner, slime_token::token(), amount);
        increase_amount(owner, ve_token, slime_tokens);
    }

    /// Can be called by owner to deposit more $SRC into a gSRC NFT.
    public fun increase_amount(
        owner: &signer,
        ve_token: Object<GSRCToken>,
        src_tokens: FungibleAsset,
    ) acquires GSRCToken, GSrcCollection {
        assert!(object::is_owner(ve_token, signer::address_of(owner)), ENOT_VE_TOKEN_OWNER);
        increase_amount_internal(ve_token, src_tokens);
    }

    /// Increase the lockup duration of a gSRC NFT by the given number of epochs. The new effective new lockup
    /// end epoch would be current epoch + lockup epochs from now.
    /// This can also be called for a gSRC NFT that has already expired to re-lock it.
    public entry fun extend_lockup(
        owner: &signer,
        ve_token: Object<GSRCToken>,
        lockup_epochs_from_now: u64,
    ) acquires GSrcCollection, GSRCToken {
        // New lockup duration still needs to be within [min, max] allowed.
        validate_lockup_epochs(lockup_epochs_from_now);
        // Can only be called by owner.
        let ve_token_data = owner_only_mut_ve_token(owner, ve_token);
        let old_lockup_end_epoch = ve_token_data.end_epoch;
        let new_lockup_end_epoch = epoch::now() + lockup_epochs_from_now;
        // Lockup must be extended so new duration should be strictly larger than the old one.
        assert!(new_lockup_end_epoch > old_lockup_end_epoch, ELOCKUP_MUST_BE_EXTENDED);
        ve_token_data.end_epoch = new_lockup_end_epoch;
        // Amount didn't change.
        let locked_amount = ve_token_data.locked_amount;

        event::emit(
            ExtendLockupEvent { owner: signer::address_of(owner), old_lockup_end_epoch, new_lockup_end_epoch, ve_token },
        );

        // Have to be called for every function that modifies amount or lockup duration of any gSRC NFT.
        // Always at the end of a function so we don't forget.
        update_snapshots(ve_token_data, locked_amount, new_lockup_end_epoch);
        update_manifested_total_supply(locked_amount, old_lockup_end_epoch, locked_amount, new_lockup_end_epoch, ve_token_data.start_epoch);
    }

    /// Can only be called by owner toithdraw $SRC from an expired gSRC NFT and deposit into their primary store.
    public entry fun withdraw_entry(
        owner: &signer,
        ve_token: Object<GSRCToken>,
    ) acquires GSRCToken, GSRCTokenRefs, GSRCDeleteRef {
        let assets = withdraw(owner, ve_token);
        primary_fungible_store::deposit(signer::address_of(owner), assets);
    }

    /// Can only be called by owner toithdraw $SRC from an expired gSRC NFT.
    public fun withdraw(
        owner: &signer,
        ve_token: Object<GSRCToken>,
    ): FungibleAsset acquires GSRCToken, GSRCTokenRefs, GSRCDeleteRef {
        // Extract the unlocked $SRC and burn the ve token.
        let tokens = slime_token::withdraw(ve_token, fungible_asset::balance(ve_token));
        let GSRCToken { locked_amount: _, start_epoch: _, end_epoch, snapshots, next_rebase_epoch: _ } =
            owner_only_destruct_token(owner, ve_token);

        // Delete all snapshots.
        destroy_snapshots(snapshots);

        event::emit(
            WithdrawEvent { owner: signer::address_of(owner), amount: fungible_asset::amount(&tokens), ve_token },
        );

        // This would fail if the lockup has not expired yet.
        assert!(end_epoch <= epoch::now(), ELOCKUP_HAS_NOT_EXPIRED);
        tokens
        // Withdraw doesn't need to update total voting power because this lockup should not have any effect on any
        // epochs, including the current one, as it has already expired.
    }

    fun increase_amount_internal(
        ve_token: Object<GSRCToken>,
        tokens: FungibleAsset,
    ) acquires GSRCToken, GSrcCollection {
        // This allows anyone to add to an existing lock.
        let ve_token_data = unchecked_mut_ve_token(&ve_token);
        assert!(ve_token_data.end_epoch > epoch::now(), ELOCKUP_EXPIRED);
        let amount = fungible_asset::amount(&tokens);
        assert!(amount > 0, EINVALID_AMOUNT);
        let old_amount = ve_token_data.locked_amount;
        let new_amount = old_amount + amount;
        ve_token_data.locked_amount = new_amount;
        slime_token::deposit(ve_token, tokens);

        event::emit(
            IncreaseAmountEvent { owner: object::owner(ve_token), old_amount, new_amount, ve_token },
        );

        // Has to called for every function that modifies amount or lockup duration of any gSRC nft.
        // Always at the end of a function so we don't forget.
        let end_epoch = ve_token_data.end_epoch;
        update_snapshots(ve_token_data, new_amount, end_epoch);
        update_manifested_total_supply(old_amount, end_epoch, new_amount, end_epoch, ve_token_data.start_epoch);
    }

    fun update_snapshots(token_data: &mut GSRCToken, locked_amount: u64, end_epoch: u64) {
        let snapshots = &mut token_data.snapshots;
        let epoch = epoch::now();
        let num_snapshots = smart_vector::length(snapshots);
        if (num_snapshots == 0 || smart_vector::borrow(snapshots, num_snapshots - 1).epoch < epoch) {
            smart_vector::push_back(snapshots, TokenSnapshot { locked_amount, end_epoch, epoch });
        } else {
            let last_snapshot = smart_vector::borrow_mut(snapshots, num_snapshots - 1);
            last_snapshot.locked_amount = locked_amount;
            last_snapshot.end_epoch = end_epoch;
        };
    }

    fun destroy_snapshots(snapshots: SmartVector<TokenSnapshot>) {
        let i = 0;
        let len = smart_vector::length(&snapshots);
        while (i < len) {
            smart_vector::pop_back(&mut snapshots);
            i = i + 1;
        };
        smart_vector::destroy_empty(snapshots);
    }

    fun update_manifested_total_supply(
        old_amount: u64,
        old_lockup_end_epoch: u64,
        new_amount: u64,
        new_lockup_end_epoch: u64,
        start_epoch: u64,
    ) acquires GSrcCollection {
        assert!(
            new_amount > old_amount || new_lockup_end_epoch > old_lockup_end_epoch,
            EINVALID_LOCKUP_CHANGE,
        );

        // We only need to update the total supply starting from the current epoch since the total voting powers of
        // past epochs are already set in stone.
        let curr_epoch = epoch::now();
        let total_voting_power_per_epoch = &mut unchecked_mut_ve_collection().unscaled_total_voting_power_per_epoch;
        while (curr_epoch < new_lockup_end_epoch) {
            // Old epoch delta can be zero if there was no previous lockup (old_amount = 0) or lockup has expired.
            let old_epoch_delta = if (old_amount == 0 || old_lockup_end_epoch <= curr_epoch || old_lockup_end_epoch <= start_epoch) {
                0
            } else {
                old_amount * (old_lockup_end_epoch - start_epoch)
            };
            let new_epoch_delta = new_amount * (new_lockup_end_epoch - start_epoch);
            // This cannot underflow due to the assertion that either the amount or the lockup duration or both must
            // increase.
            let voting_power_delta = ((new_epoch_delta - old_epoch_delta) as u128);
            if (smart_table::contains(total_voting_power_per_epoch, curr_epoch)) {
                let total_voting_power = smart_table::borrow_mut(total_voting_power_per_epoch, curr_epoch);
                *total_voting_power = *total_voting_power + voting_power_delta;
            } else {
                smart_table::add(total_voting_power_per_epoch, curr_epoch, voting_power_delta);
            };
            curr_epoch = curr_epoch + 1;
        }
    }

    inline fun total_staking_power_at_internal(total_voting_power_per_epoch: &SmartTable<u64, u128>, epoch: u64): u128 {
        if (!smart_table::contains(total_voting_power_per_epoch, epoch)) {
            0
        } else {
            let unscaled_voting_power = *smart_table::borrow(total_voting_power_per_epoch, epoch);
            unscaled_voting_power / (MAX_LOCKUP_EPOCHS as u128)
        }
    }

    inline fun owner_only_destruct_token(
        owner: &signer,
        ve_token: Object<GSRCToken>,
    ): GSRCToken acquires GSRCToken, GSRCTokenRefs, GSRCDeleteRef {
        assert!(object::is_owner(ve_token, signer::address_of(owner)), ENOT_VE_TOKEN_OWNER);
        let ve_token_addr = object::object_address(&ve_token);
        let token_data = move_from<GSRCToken>(ve_token_addr);

        // Delete the fungible store first.
        // Since delete_ref is recently added, older gSRC NFTs might not have it. In which case, we can't delete the
        // fungible store.
        if (exists<GSRCDeleteRef>(ve_token_addr)) {
            let GSRCDeleteRef { delete_ref } = move_from<GSRCDeleteRef>(ve_token_addr);
            fungible_asset::remove_store(&delete_ref);
        };

        // Burn the token and delete the object.
        let GSRCTokenRefs { burn_ref, transfer_ref: _ } = move_from<GSRCTokenRefs>(ve_token_addr);
        token::burn(burn_ref);
        token_data
    }

    inline fun owner_only_mut_ve_token(
        owner: &signer,
        ve_token: Object<GSRCToken>,
    ): &mut GSRCToken acquires GSRCToken {
        assert!(object::is_owner(ve_token, signer::address_of(owner)), ENOT_VE_TOKEN_OWNER);
        unchecked_mut_ve_token(&ve_token)
    }

    inline fun safe_ve_token(ve_token: &Object<GSRCToken>): &GSRCToken acquires GSRCToken {
        borrow_global<GSRCToken>(object::object_address(ve_token))
    }

    inline fun safe_ve_collection(): &GSrcCollection acquires GSrcCollection {
        borrow_global<GSrcCollection>(voting_escrow_collection())
    }

    inline fun unchecked_mut_ve_token(ve_token: &Object<GSRCToken>): &mut GSRCToken acquires GSRCToken {
        borrow_global_mut<GSRCToken>(object::object_address(ve_token))
    }

    inline fun unchecked_mut_ve_collection(): &mut GSrcCollection acquires GSrcCollection {
        borrow_global_mut<GSrcCollection>(voting_escrow_collection())
    }

    inline fun validate_lockup_epochs(lockup_epochs: u64) {
        assert!(lockup_epochs >= MIN_LOCKUP_EPOCHS, ELOCKUP_TOO_SHORT);
        assert!(lockup_epochs <= MAX_LOCKUP_EPOCHS, ELOCKUP_TOO_LONG);
    }
}
