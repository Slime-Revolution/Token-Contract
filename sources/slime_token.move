module slime::slime_token {
    use aptos_framework::fungible_asset::{Self, MintRef, TransferRef, BurnRef, FungibleAsset, FungibleStore};
    use aptos_framework::object::{Self, Object};
    use aptos_framework::primary_fungible_store;

    use std::string;
    use std::option;
    use std::signer;
    use std::vector;
    use slime::global_state;
    friend slime::token_vesting;
    friend slime::staking_escrow;

    const TOKEN_NAME: vector<u8> = b"Slime Revolution Coin";
    const TOKEN_SYMBOL: vector<u8> = b"SRC";
    const TOKEN_DECIMALS: u8 = 8;
    const TOKEN_URI: vector<u8> = b"SLIME";
    const PROJECT_URI: vector<u8> = b"https://slime.com/";

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    /// Fungible asset refs used to manage the AMNIS token.
    struct SlimeToken has key {
        burn_ref: BurnRef,
        mint_ref: MintRef,
        transfer_ref: TransferRef,
    }

    /// Deploy the SLIME token.
    public entry fun initialize() {
        if (is_initialized()) {
            return
        };
        let slime_token_metadata = &object::create_named_object(&global_state::config_signer(), TOKEN_NAME);
        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            slime_token_metadata,
            option::none(),
            string::utf8(TOKEN_NAME),
            string::utf8(TOKEN_SYMBOL),
            TOKEN_DECIMALS,
            string::utf8(TOKEN_URI),
            string::utf8(PROJECT_URI),
        );
        let slime_token = &object::generate_signer(slime_token_metadata);
        move_to(slime_token, SlimeToken {
            burn_ref: fungible_asset::generate_burn_ref(slime_token_metadata),
            mint_ref: fungible_asset::generate_mint_ref(slime_token_metadata),
            transfer_ref: fungible_asset::generate_transfer_ref(slime_token_metadata),
        });
        global_state::add_address(string::utf8(TOKEN_NAME), signer::address_of(slime_token));
    }

    #[view]
    public fun is_initialized(): bool {
        global_state::address_exists(string::utf8(TOKEN_NAME))
    }

    #[view]
    /// Return $SLIME token address.
    public fun token_address(): address {
        object::create_object_address(&global_state::config_address(), TOKEN_NAME)
    }

    #[view]
    /// Return the $SLIME token metadata object.
    public fun token(): Object<SlimeToken> {
        object::address_to_object(token_address())
    }

    #[view]
    /// Return the total supply of $SLIME tokens.
    public fun total_supply(): u128 {
        option::get_with_default(&fungible_asset::supply(token()), 0)
    }

    #[view]
    /// Return the total supply of $SLIME tokens.
    public fun balance(user: address): u64 {
        primary_fungible_store::balance(user, token())
    }

    /// Called by the minter module to mint weekly emissions.
    public(friend) fun mint(amount: u64): FungibleAsset acquires SlimeToken {
        fungible_asset::mint(&unchecked_token_refs().mint_ref, amount)
    }

    public(friend) fun burn(slime_tokens: FungibleAsset) acquires SlimeToken {
        fungible_asset::burn(&unchecked_token_refs().burn_ref, slime_tokens);
    }

    /// For depositing $SLIME into a fungible asset store. This can be the gSRC token, which cannot be deposited
    /// into normally as it's frozen (no owner transfers).
    public(friend) fun deposit<T: key>(store: Object<T>, slime_tokens: FungibleAsset) acquires SlimeToken {
        fungible_asset::deposit_with_ref(&unchecked_token_refs().transfer_ref, store, slime_tokens);
    }

    /// For withdrawing $SLIME from a gNFT.
    public(friend) fun withdraw<T: key>(store: Object<T>, amount: u64): FungibleAsset acquires SlimeToken {
        fungible_asset::withdraw_with_ref(&unchecked_token_refs().transfer_ref, store, amount)
    }

    /// For 1 freeze_store $SLIME from a object.
    public(friend) fun freeze_store<T: key>(store: Object<T>) acquires SlimeToken {
        fungible_asset::set_frozen_flag(&unchecked_token_refs().transfer_ref, store, true)
    }

    /// For many freeze_stores $SLIME from a object.
    public(friend) fun freeze_stores<T: key>(stores: vector<Object<T>>) acquires SlimeToken {
        vector::for_each(stores, |store| {
            fungible_asset::set_frozen_flag(&unchecked_token_refs().transfer_ref, store, true)
        });
    }

    /// For 1 unfreeze_store $SLIME from a object.
    public(friend) fun unfreeze_store<T: key>(store: Object<T>) acquires SlimeToken {
        fungible_asset::set_frozen_flag(&unchecked_token_refs().transfer_ref, store, false)
    }

    /// For many freeze_stores $SLIME from a object.
    public(friend) fun unfreeze_stores<T: key>(stores: vector<Object<T>>) acquires SlimeToken {
        vector::for_each(stores, |store| {
            fungible_asset::set_frozen_flag(&unchecked_token_refs().transfer_ref, store, false)
        });
    }

    /// For extracting $SLIME from the gSRC token when owner withdraws after the lockup has expired.
    public(friend) fun transfer<T: key>(
        from: Object<T>,
        to: Object<FungibleStore>,
        amount: u64,
    ) acquires SlimeToken {
        let from = object::convert(from);
        let transfer_ref = &unchecked_token_refs().transfer_ref;
        fungible_asset::transfer_with_ref(transfer_ref, from, to, amount);
    }

    /// Used to lock $SLIME in when creating voting escrows.
    public(friend) fun disable_transfer<T: key>(slime_store: Object<T>) acquires SlimeToken {
        let transfer_ref = &unchecked_token_refs().transfer_ref;
        fungible_asset::set_frozen_flag(transfer_ref, slime_store, true);
    }

    inline fun unchecked_token_refs(): &SlimeToken {
        borrow_global<SlimeToken>(token_address())
    }

    #[test_only]
    public fun test_mint(amount: u64): FungibleAsset acquires SlimeToken {
        mint(amount)
    }

    #[test_only]
    public fun test_burn(tokens: FungibleAsset) acquires SlimeToken {
        if (fungible_asset::amount(&tokens) == 0) {
            fungible_asset::destroy_zero(tokens);
        } else {
            burn(tokens);
        };
    }

    #[test_only]
    public fun init_for_test() {
        initialize();
    }
}
