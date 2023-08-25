#[test_only]
module desui_labs::test_utils {
    use sui::address;
    use sui::balance;
    use sui::coin::{Self, Coin};
    use sui::tx_context::TxContext;
    use sui::test_random::{Self, Random};
    use sui::test_scenario::{Self as ts, Scenario};
    use sui::test_utils::create_one_time_witness;
    use desui_labs::coin_flip_v2::{Self as cf, AdminCap, COIN_FLIP_V2};

    const DEV: address = @0xde1;

    struct PlayerGenerator has store, drop {
        random: Random,
        min_stake_amount: u64,
        max_stake_amount: u64,
    }

    public fun setup_house<T>(
        init_pool_amount: u64,
        fee_rate: u128,
        min_stake_amount: u64,
        max_stake_amount: u64,
    ): Scenario {
        let scenario_val = ts::begin(dev());
        let scenario = &mut scenario_val;
        {
            let otw = create_one_time_witness<COIN_FLIP_V2>();
            cf::init_for_testing(otw, ts::ctx(scenario));
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

    public fun setup_partnership<P>(
        scenario: &mut Scenario,
        fee_rate: u128,
    ) {
        ts::next_tx(scenario, dev());
        {
            let admin_cap = ts::take_from_sender<AdminCap>(scenario);
            cf::create_partnership<P>(&admin_cap, fee_rate, ts::ctx(scenario));
            ts::return_to_sender(scenario, admin_cap);
        };        
    }

    public fun new_player_generator(
        seed: vector<u8>,
        min_stake_amount: u64,
        max_stake_amount: u64,
    ): PlayerGenerator {
        PlayerGenerator {
            random: test_random::new(seed),
            min_stake_amount,
            max_stake_amount,
        }
    }

    public fun gen_player_and_stake<T>(
        generator: &mut PlayerGenerator,
        ctx: &mut TxContext,
    ): (address, Coin<T>) {
        let random = &mut generator.random;
        let player = address::from_u256(test_random::next_u256(random));
        let stake_amount_diff = generator.max_stake_amount - generator.min_stake_amount;
        let stake = balance::create_for_testing<T>(
            generator.min_stake_amount +
            test_random::next_u64(random) % stake_amount_diff
        );
        let stake = coin::from_balance(stake, ctx);
        (player, stake)
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
