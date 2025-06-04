address bioshard {
module BioShard {
    use aptos_framework::coin;
    use aptos_framework::coin::{MintCapability, BurnCapability};
    use aptos_framework::signer;
    use std::string::utf8;

    /// Admin treasury address
    const ADMIN: address = @bioshard;

    /// Metadata
    const NAME:   vector<u8> = b"BioShard";
    const SYMBOL: vector<u8> = b"BIO";
    const DECIMALS: u8 = 6;

    struct Caps has key {
        mint: MintCapability<BioShard>,
        burn: BurnCapability<BioShard>,
    }

    struct BioShard has store, drop {}

    /// One shot initializer (idempotent thanks to `exists` guard).
    public entry fun init(admin: &signer, initial: u64) {
        assert!(signer::address_of(admin) == ADMIN, 0);
        assert!(!exists<Caps>(ADMIN), 1);

        let (burn, freeze, mint) = coin::initialize<BioShard>(
            admin,
            utf8(NAME),
            utf8(SYMBOL),
            DECIMALS,
            /* monitor_supply */ false,
        );
        // Freeze cap unused destroy immediately.
        coin::destroy_freeze_cap<BioShard>(freeze);

        // Register admin store then mint
        coin::register<BioShard>(admin);
        let coins = coin::mint<BioShard>(initial, &mint);
        coin::deposit<BioShard>(ADMIN, coins);

        move_to<Caps>(admin, Caps { mint, burn });
    }

    /// Faucet devnet only (guarded by ADMIN check)
    public entry fun faucet(admin: &signer, to: address, amount: u64) acquires Caps {
        assert!(signer::address_of(admin) == ADMIN, 2);
        let caps = borrow_global<Caps>(ADMIN);
        let coins = coin::mint<BioShard>(amount, &caps.mint);
        coin::deposit<BioShard>(to, coins);
    }

    /// Burn caller balance (self service)
    public entry fun burn_my_balance(caller: &signer, amt: u64) acquires Caps {
        let caps = borrow_global<Caps>(ADMIN);
        let coins = coin::withdraw<BioShard>(caller, amt);
        coin::burn<BioShard>(coins, &caps.burn);
    }
}
}