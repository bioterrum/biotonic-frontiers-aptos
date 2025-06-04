address prototype {
module PrototypeUnit {
    use aptos_framework::signer;
    use aptos_framework::object;
    use aptos_framework::object::Object;
    use aptos_token_objects::collection;
    use aptos_token_objects::token;
    use aptos_token_objects::token::Token;
    use aptos_token_objects::royalty;
    use std::string::utf8;
    use std::option;

    const ADMIN: address = @prototype;

    const NAME: vector<u8> = b"PrototypeUnit";
    const DESC: vector<u8> = b"Early test NFTs minted during Sprint 9";
    const URI:  vector<u8> = b"https://biotonic.bioterrum.com/nft/prototype/";

    /// Initialise collection (unlimited supply, zero royalty)
    public entry fun init(admin: &signer) {
        assert!(signer::address_of(admin) == ADMIN, 0);
        collection::create_unlimited_collection(
            admin,
            utf8(DESC),
            utf8(NAME),
            option::none<royalty::Royalty>(),
            utf8(URI),
        );
    }

    /// Bulk mint identical NFTs and airdrop to `to`.
    public entry fun mint(admin: &signer, to: address, count: u64) {
        assert!(signer::address_of(admin) == ADMIN, 1);
        let i = 0u64;
        while (i < count) {
            let ctor = token::create_named_token(
                admin,
                utf8(NAME),
                utf8(DESC),
                utf8(NAME),
                option::none<royalty::Royalty>(),
                utf8(URI),
            );
            let obj: Object<Token> = object::object_from_constructor_ref<Token>(&ctor);
            object::transfer(admin, obj, to);
            i = i + 1;
        }
    }
}
}