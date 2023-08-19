#[test_only]
module desui_labs::test_utils {
    use std::vector;
    use sui::address;
    use sui::balance;
    use sui::coin;
    use sui::transfer;
    use sui::test_random;
    use sui::test_scenario::{Self as ts, Scenario};
    use desui_labs::coin_flip_v2::{Self as cf, AdminCap};

    const DEV: address = @0xde1;

    public fun setup_house<T>(
        init_pool_amount: u64,
        fee_rate: u128,
        min_stake_amount: u64,
        max_stake_amount: u64,
    ): Scenario {
        let scenario_val = ts::begin(dev());
        let scenario = &mut scenario_val;
        {
            cf::init_for_testing(ts::ctx(scenario));
        };

        ts::next_tx(scenario, dev());
        {
            let init_pool = balance::create_for_testing<T>(init_pool_amount);
            let init_pool = coin::from_balance(init_pool, ts::ctx(scenario));
            let admin_cap = ts::take_from_sender<AdminCap>(scenario);
            cf::create_house(&admin_cap, b"", fee_rate, min_stake_amount, max_stake_amount, init_pool, ts::ctx(scenario));
            ts::return_to_sender(scenario, admin_cap);
        };

        scenario_val
    }

    public fun setup_players<T>(
        scenario: &mut Scenario,
        player_count: u64,
        min_stake_amount: u64,
        max_stake_amount: u64,
    ): vector<address> {
        let player_seed = b"CoinFlip V2";
        vector::push_back(&mut player_seed, ((player_count % 256) as u8));
        let stake_amount_diff = max_stake_amount - min_stake_amount;
        let rang = test_random::new(player_seed);
        let rangr = &mut rang;

        let players = vector<address>[];
        let idx: u64 = 0;
        while (idx <= player_count) {
            let player = address::from_u256(test_random::next_u256(rangr));
            ts::next_tx(scenario, player);
            {
                let stake_amount = min_stake_amount + test_random::next_u64(rangr) % stake_amount_diff;
                let stake = balance::create_for_testing<T>(stake_amount);
                let stake = coin::from_balance(stake, ts::ctx(scenario));
                transfer::public_transfer(stake, player);
            };
            vector::push_back(&mut players, player);
            idx = idx + 1;
        };

        players
    }

    public fun dev(): address { DEV }
}

#[test_only]
module bucket_protocol::buck {
    use std::option;
    use sui::coin;
    use sui::tx_context::TxContext;
    use sui::transfer;
    use sui::url;

    struct BUCK has drop {}

    fun init(otw: BUCK, ctx: &mut TxContext) {
        let (buck_treasury_cap, buck_metadata) = coin::create_currency(
            otw,
            9,
            b"BUCK",
            b"Bucket USD",
            b"the stablecoin minted through bucketprotocol.io",
            option::some(url::new_unsafe_from_bytes(
                b"https://ipfs.io/ipfs/QmYH4seo7K9CiFqHGDmhbZmzewHEapAhN9aqLRA7af2vMW"),
            ),
            ctx,
        );
        transfer::public_freeze_object(buck_treasury_cap);
        transfer::public_freeze_object(buck_metadata);
    }
}

#[test_only]
module desui_labs::dlab {
    use sui::object::{Self, UID};
    use sui::tx_context::TxContext;
    use sui::transfer;

    struct Dlab has key, store {
        id: UID,
    }

    public fun mint(ctx: &mut TxContext): Dlab {
        Dlab { id: object::new(ctx) }
    }

    public entry fun mint_to(recipient: address, ctx: &mut TxContext) {
        transfer::transfer(mint(ctx), recipient);
    }
}