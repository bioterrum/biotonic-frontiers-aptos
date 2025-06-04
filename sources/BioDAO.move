module 0xBF::bio_dao {
    /* ============================================
       Imports
    ============================================ */
    use aptos_framework::coin;
    use aptos_framework::event;
    use aptos_framework::table;
    use aptos_framework::timestamp;
    use std::signer;
    use std::string;

    /* ============================================
       Error codes
    ============================================ */
    const E_NOT_MEMBER: u64       = 0;
    const E_VOTING_CLOSED: u64    = 1;
    const E_ALREADY_VOTED: u64    = 2;
    const E_EXEC_NOT_READY: u64   = 3;
    const E_ALREADY_EXECUTED: u64 = 4;

    /* ============================================
       DAO state
    ============================================ */
    struct Dao<phantom CoinType> has key {
        name: string::String,
        uri: string::String,
        quorum_bps: u16,
        majority_bps: u16,
        voting_period_sec: u64,
        timelock_sec: u64,
        next_proposal_id: u64,
        proposals: table::Table<u64, Proposal<CoinType>>,
        votes: table::Table<VoteKey, VoteRecord>,
    }

    struct MemberBadge has key {
        dao_addr: address
    }

    struct Proposal<phantom CoinType> has store, drop {
        proposer: address,
        created_at: u64,
        execute_after: u64,
        yes_weight: u128,
        no_weight: u128,
        title: string::String,
        action: vector<u8>,
        executed: bool,
    }

    struct VoteKey has copy, drop, store {
        id: u64,
        voter: address
    }

    struct VoteRecord has drop, store {
        weight: u128,
        in_favor: bool
    }

    #[event]
    struct MemberEvent has drop, store {
        member: address,
        joined: bool
    }

    #[event]
    struct ProposalEvent has drop, store {
        id: u64,
        proposer: address
    }

    #[event]
    struct VoteEvent has drop, store {
        id: u64,
        voter: address,
        weight: u128,
        in_favor: bool
    }

    #[event]
    struct ExecuteEvent has drop, store {
        id: u64,
        success: bool
    }

    /* ============================================
       Initialization
    ============================================ */
    public entry fun initialize<CoinType: store + key>(
        creator: &signer,
        name: string::String,
        uri: string::String,
        quorum_bps: u16,
        majority_bps: u16,
        voting_period_sec: u64,
        timelock_sec: u64
    ) {
        let dao = Dao<CoinType> {
            name,
            uri,
            quorum_bps,
            majority_bps,
            voting_period_sec,
            timelock_sec,
            next_proposal_id: 0,
            proposals: table::new<u64, Proposal<CoinType>>(),
            votes: table::new<VoteKey, VoteRecord>(),
        };
        move_to(creator, dao);

        internal_join(creator, signer::address_of(creator));
        event::emit(MemberEvent { member: signer::address_of(creator), joined: true });
    }

    /* ============================================
       Membership
    ============================================ */
    public entry fun join<CoinType: store + key>(
        new_member: &signer,
        dao_addr: address
    ) {
        assert!(exists<Dao<CoinType>>(dao_addr), E_NOT_MEMBER);
        assert!(!exists<MemberBadge>(signer::address_of(new_member)), E_NOT_MEMBER);
        internal_join(new_member, dao_addr);
        event::emit(MemberEvent { member: signer::address_of(new_member), joined: true });
    }

    fun internal_join(member: &signer, dao_addr: address) {
        move_to(member, MemberBadge { dao_addr });
    }

    #[view]
    fun is_member(dao_addr: address, addr: address): bool acquires MemberBadge {
        exists<MemberBadge>(addr) && borrow_global<MemberBadge>(addr).dao_addr == dao_addr
    }

    /* ============================================
       Proposals
    ============================================ */
    public entry fun create_proposal<CoinType: store + key>(
        proposer: &signer,
        dao_addr: address,
        title: string::String,
        action_blob: vector<u8>
    ) acquires Dao, MemberBadge {
        assert!(is_member(dao_addr, signer::address_of(proposer)), E_NOT_MEMBER);

        let dao_ref = borrow_global_mut<Dao<CoinType>>(dao_addr);
        let id = dao_ref.next_proposal_id;
        dao_ref.next_proposal_id = id + 1;

        let now = timestamp::now_seconds();
        let exec_after = now + dao_ref.voting_period_sec + dao_ref.timelock_sec;

        table::add(
            &mut dao_ref.proposals,
            id,
            Proposal<CoinType> {
                proposer: signer::address_of(proposer),
                created_at: now,
                execute_after: exec_after,
                yes_weight: 0,
                no_weight: 0,
                title,
                action: action_blob,
                executed: false,
            }
        );
        event::emit(ProposalEvent { id, proposer: signer::address_of(proposer) });
    }

    /* ============================================
       Voting
    ============================================ */
    public entry fun vote<CoinType: store + key>(
        voter: &signer,
        dao_addr: address,
        id: u64,
        in_favor: bool,
        stake: u64
    ) acquires Dao, MemberBadge {
        assert!(is_member(dao_addr, signer::address_of(voter)), E_NOT_MEMBER);

        let dao_ref = borrow_global_mut<Dao<CoinType>>(dao_addr);
        let prop_ref = table::borrow_mut(&mut dao_ref.proposals, id);

        let now = timestamp::now_seconds();
        assert!(now < prop_ref.created_at + dao_ref.voting_period_sec, E_VOTING_CLOSED);

        let key = VoteKey { id, voter: signer::address_of(voter) };
        assert!(!table::contains(&dao_ref.votes, key), E_ALREADY_VOTED);

        let weight: u128 = 1u128 + (stake as u128);

        if (stake > 0) {
            coin::transfer<CoinType>(voter, dao_addr, stake);
        };

        if (in_favor) {
            prop_ref.yes_weight = prop_ref.yes_weight + weight;
        } else {
            prop_ref.no_weight = prop_ref.no_weight + weight;
        };

        table::add(&mut dao_ref.votes, key, VoteRecord { weight, in_favor });
        event::emit(VoteEvent { id, voter: signer::address_of(voter), weight, in_favor });
    }

    /* ============================================
       Execution
    ============================================ */
    public entry fun execute<CoinType: store + key>(
        dao_addr: address,
        id: u64
    ) acquires Dao {
        let dao_ref = borrow_global_mut<Dao<CoinType>>(dao_addr);
        let prop_ref = table::borrow_mut(&mut dao_ref.proposals, id);

        assert!(!prop_ref.executed, E_ALREADY_EXECUTED);
        assert!(timestamp::now_seconds() >= prop_ref.execute_after, E_EXEC_NOT_READY);

        let total = prop_ref.yes_weight + prop_ref.no_weight;
        let quorum_ok   = total * 10000u128 >= (dao_ref.quorum_bps as u128) * total;
        let majority_ok = prop_ref.yes_weight * 10000u128 >= (dao_ref.majority_bps as u128) * total;

        let success = quorum_ok && majority_ok;
        prop_ref.executed = true;

        event::emit(ExecuteEvent { id, success });
        // optional: trigger dispatch from action blob
    }

    /* ============================================
       Treasury
    ============================================ */
    public entry fun treasury_withdraw<CoinType: store + key>(
        dao_acc: &signer,
        recipient: address,
        amount: u64
    ) acquires Dao {
        let _dao = borrow_global<Dao<CoinType>>(signer::address_of(dao_acc));
        let coins = coin::withdraw<CoinType>(dao_acc, amount);
        coin::deposit<CoinType>(recipient, coins);
    }
}
