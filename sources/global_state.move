module slime::global_state {
    use std::signer;
    use std::string::String;
    use aptos_std::smart_table;
    use aptos_std::smart_table::SmartTable;
    use aptos_framework::account;
    use aptos_framework::object::{Self, ExtendRef, Object};
    friend slime::slime_token;
    friend slime::token_vesting;
    friend slime::staking_escrow;

    const GLOBAL_STATE_NAME: vector<u8> = b"slime::global_state";
    // Unauthorized access
    const UNAUTHORIZED: u64 = 101;

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct AdministrativeData has key {
        governance: address,
        operator: address,
    }

    /// Stores permission config such as SignerCapability for controlling the resource account.
    struct PermissionConfig has key {
        /// Track the addresses created by the modules in this package.
        addresses: SmartTable<String, address>,
    }

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct GlobalState has key {
        extend_ref: ExtendRef
    }

    fun init_module(src: &signer) {
        let global_state = &object::create_named_object(src, GLOBAL_STATE_NAME);
        let global_state_signer = &object::generate_signer(global_state);
        account::create_account_if_does_not_exist(signer::address_of(global_state_signer));
        move_to(global_state_signer, PermissionConfig {
            addresses: smart_table::new<String, address>(),
        });
        move_to(global_state_signer, GlobalState {
            extend_ref: object::generate_extend_ref(global_state)
        });
        move_to(global_state_signer, AdministrativeData {
            operator: @deployer,
            governance: @deployer,
        });
    }

    #[view]
    public fun operator(): address acquires AdministrativeData {
        safe_admin_data().operator
    }

    #[view]
    public fun governance(): address acquires AdministrativeData {
        safe_admin_data().governance
    }

    #[view]
    public fun object(): Object<GlobalState> {
        object::address_to_object(config_address())
    }

    #[view]
    public fun config_address(): address {
        object::create_object_address(&@slime, GLOBAL_STATE_NAME)
    }

    public(friend) fun config_signer(): signer acquires GlobalState {
        object::generate_signer_for_extending(&borrow_global<GlobalState>(config_address()).extend_ref)
    }

    /// Can be called by friended modules to keep track of a system address.
    public(friend) fun add_address(name: String, object: address) acquires PermissionConfig {
        smart_table::add(&mut unchecked_mut_permission_config().addresses, name, object);
    }

    public fun address_exists(name: String): bool acquires PermissionConfig {
        smart_table::contains(&safe_permission_config().addresses, name)
    }

    public fun get_address(name: String): address acquires PermissionConfig {
        *smart_table::borrow(&safe_permission_config().addresses, name)
    }

    public entry fun update_operator(governor: &signer, new_operator: address) acquires AdministrativeData {
        only_governance(governor);
        unchecked_mut_admin_data().operator = new_operator;
    }

    public entry fun update_governance(
        governance: &signer,
        new_governance: address,
    ) acquires AdministrativeData {
        only_governance(governance);
        unchecked_mut_admin_data().governance = new_governance;
    }

    public(friend) fun only_operator(src: &signer) acquires AdministrativeData {
        assert!(signer::address_of(src) == operator(), UNAUTHORIZED);
    }

    public(friend) fun only_governance(src: &signer) acquires AdministrativeData {
        assert!(signer::address_of(src) == governance(), UNAUTHORIZED);
    }

    inline fun safe_admin_data(): &AdministrativeData acquires AdministrativeData {
        borrow_global<AdministrativeData>(config_address())
    }

    inline fun unchecked_mut_admin_data(): &mut AdministrativeData acquires AdministrativeData {
        borrow_global_mut<AdministrativeData>(config_address())
    }

    inline fun safe_permission_config(): &PermissionConfig acquires PermissionConfig {
        borrow_global<PermissionConfig>(config_address())
    }

    inline fun unchecked_mut_permission_config(): &mut PermissionConfig acquires PermissionConfig {
        borrow_global_mut<PermissionConfig>(config_address())
    }

    #[test_only]
    public fun initialize_for_test(deployer: &signer) {
        let deployer_addr = signer::address_of(deployer);
        if (!exists<PermissionConfig>(deployer_addr)) {
            aptos_framework::timestamp::set_time_has_started_for_testing(&account::create_signer_for_test(@0x1));

            account::create_account_for_test(deployer_addr);
            move_to(deployer, PermissionConfig {
                addresses: smart_table::new<String, address>(),
            });
        };
    }


    #[test_only]
    public fun init_for_test(deployer: &signer) {
        init_module(deployer);
    }
}
