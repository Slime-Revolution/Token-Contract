module slime::epoch {
    use aptos_framework::timestamp;

    #[view]
    public fun now(): u64 {
        to_epoch(timestamp::now_seconds())
    }

    public inline fun duration(): u64 {
        // Equal to EPOCH_DURATION. Inline functions cannot use constants defined in their module.
        // 604800 // 7 days
        // 86400 // 1 day TODO: change in mainnet
        3600 // 1 hours TODO: change in mainnet
    }

    public inline fun to_epoch(timestamp_secs: u64): u64 {
        // Equal to EPOCH_DURATION. Inline functions cannot use constants defined in their module.
        timestamp_secs / duration()
    }

    public inline fun to_seconds(epoch: u64): u64 {
        // Equal to EPOCH_DURATION. Inline functions cannot use constants defined in their module.
        epoch * duration()
    }

    #[test_only]
    public fun fast_forward(epochs: u64) {
        aptos_framework::timestamp::fast_forward_seconds(epochs * duration());
    }
}
