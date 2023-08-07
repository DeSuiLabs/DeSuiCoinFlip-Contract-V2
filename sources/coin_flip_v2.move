module desui_labs::coin_flip_v2 {

    use std::vector;
    use std::option::{Self, Option};
    use std::type_name::{Self, TypeName};
    use sui::coin::{Self, Coin};
    use sui::object::{Self, UID, ID};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::bls12381::bls12381_min_pk_verify;
    use sui::hash::blake2b256;
    use sui::vec_set::{Self, VecSet};
    use sui::kiosk::{Self, Kiosk};
    use sui::sui::SUI;
    use sui::event;

    // Constants
    const FEE_PRECISION: u128 = 1_000_000;

    // Errors
    const EInvalidStakeValue: u64 = 0;
    const EInvalidGuess: u64 = 1;
    const EInvalidBlsSig: u64 = 2;
    const EFundValueMismatch: u64 = 3;
    const EKioskItemNotFound: u64 = 4;

    // Objects
    struct House<phantom T> has key {
        id: UID,
        dealer: address,
        pub_key: vector<u8>,
        fee_rate: u128,
        valid_stake_values: VecSet<u64>,
    }

    struct Game<phantom T> has key {
        id: UID,
        stake: Coin<T>,
        guess: u8,
        dealer: address,
        player: address,
        seed: vector<u8>,
        pub_key: vector<u8>,
        fee_rate: u128,
    }

    struct Partnership<phantom P> has key {
        id: UID,
        fee_rate: u128,
    }

    struct AdminCap has key {
        id: UID,
    }

    // Events
    struct NewGame<phantom T> has copy, drop {
        game_id: ID,
        player: address,
        guess: u8,
        stake_value: u64,
        partnership_type: Option<TypeName>,
    }

    struct Outcome<phantom T> has copy, drop {
        game_id: ID,
        player: address,
        player_won: bool,
        pnl: u64,
    }

    fun init(ctx: &mut TxContext) {
        let admin_cap = AdminCap { id: object::new(ctx) };
        transfer::transfer(admin_cap, tx_context::sender(ctx));
    }

    public entry fun create_house<T>(
        _cap: &AdminCap,
        dealer: address,
        pub_key: vector<u8>,
        fee_rate: u128,
        valid_stake_amounts_vec: vector<u64>,
        ctx: &mut TxContext,
    ) {
        let id = object::new(ctx);
        let idx: u64 = 0;
        let length = vector::length(&valid_stake_amounts_vec);
        let valid_stake_values = vec_set::empty();
        while (idx < length) {
            let amount = *vector::borrow(&valid_stake_amounts_vec, idx);
            vec_set::insert(&mut valid_stake_values, amount);
            idx = idx + 1;
        };
        transfer::freeze_object(House<T> {
            id,
            dealer,
            pub_key,
            fee_rate,
            valid_stake_values,
        });
    }

    public entry fun create_partnership<P>(
        _cap: &AdminCap,
        fee_rate: u128,
        ctx: &mut TxContext,
    ) {
        transfer::freeze_object(Partnership<P> {
            id: object::new(ctx),
            fee_rate,
        });
    }

    public entry fun start_game<T>(
        house: &House<T>,
        guess: u8,
        seed: vector<u8>,
        stake: Coin<T>,
        ctx: &mut TxContext,
    ) {
        let fee_rate = house.fee_rate;
        transfer::transfer(
            new_game(house, guess, seed, stake, fee_rate, option::none(), ctx),
            house.dealer
        );
    }

    public entry fun start_game_with_parternship<T, P: key>(
        house: &House<T>,
        guess: u8,
        seed: vector<u8>,
        stake: Coin<T>,
        partnership: &Partnership<P>,
        _proof: &P,
        ctx: &mut TxContext,
    ) {
        let fee_rate = min_u128(house.fee_rate, partnership.fee_rate);
        let partnership_type = option::some(type_name::get<P>());
        transfer::transfer(
            new_game(house, guess, seed, stake, fee_rate, partnership_type, ctx),
            house.dealer
        );
    }

    public entry fun start_game_with_kiosk<T, P: key + store>(
        house: &House<T>,
        guess: u8,
        seed: vector<u8>,
        stake: Coin<T>,
        partnership: &Partnership<P>,
        kiosk: &Kiosk,
        item: ID,
        ctx: &mut TxContext,
    ) {
        let fee_rate = min_u128(house.fee_rate, partnership.fee_rate);
        let partnership_type = option::some(type_name::get<P>());
        assert!(
            kiosk::has_item_with_type<P>(kiosk, item),
            EKioskItemNotFound,
        );
        transfer::transfer(
            new_game(house, guess, seed, stake, fee_rate, partnership_type, ctx),
            house.dealer
        );
    }

    public entry fun settle<T>(
        game: Game<T>,
        fund: Coin<T>,
        bls_sig: vector<u8>,
        ctx: &mut TxContext,
    ) {
        let Game { id, stake, guess, dealer, player, seed, pub_key, fee_rate } = game;
        let game_id = object::uid_to_inner(&id);
        let msg_vec = object::uid_to_bytes(&id);
        vector::append(&mut msg_vec, seed);
        assert!(
            bls12381_min_pk_verify(
                &bls_sig, &pub_key, &msg_vec,
            ),
            EInvalidBlsSig
        );
        let stake_value = coin::value(&stake);
        assert!(
            coin::value(&fund) == stake_value,
            EFundValueMismatch,
        );
        object::delete(id);

        let hashed_beacon = blake2b256(&bls_sig);
        let first_byte = *vector::borrow(&hashed_beacon, 0);
        let player_won: bool = (guess == first_byte % 2);

        let pnl: u64 = if(player_won) {
            let fee_value = compute_fee_amount(stake_value, fee_rate);
            let fee_coin = coin::split(&mut stake, fee_value, ctx);
            transfer::public_transfer(fee_coin, dealer);
            coin::join(&mut stake, fund);
            transfer::public_transfer(stake, player);
            stake_value - fee_value
        } else {
            transfer::public_transfer(stake, dealer);
            transfer::public_transfer(fund, dealer);
            stake_value
        };

        event::emit(Outcome<T> {
            game_id,
            player,
            player_won,
            pnl,
        });
    }

    fun new_game<T>(
        house: &House<T>,
        guess: u8,
        seed: vector<u8>,
        stake: Coin<T>,
        fee_rate: u128,
        partnership_type: Option<TypeName>,
        ctx: &mut TxContext,
    ): Game<T> {
        // Ensure that guess is either 0 or 1
        assert!(guess == 1 || guess == 0, EInvalidGuess);
        // Ensure the stake amount is valid
        let stake_value = coin::value(&stake);
        assert!(vec_set::contains(
            &house.valid_stake_values,
            &stake_value,
        ), EInvalidStakeValue);

        let id = object::new(ctx);
        let player = tx_context::sender(ctx);
        event::emit(NewGame<T> {
            game_id: object::uid_to_inner(&id),
            player,
            guess,
            stake_value,
            partnership_type,
        });

        Game<T> {
            id,
            stake,
            guess,
            dealer: house.dealer,
            player,
            seed,
            pub_key: house.pub_key,
            fee_rate,
        }
    }

    fun compute_fee_amount(amount: u64, fee_rate: u128): u64 {
        (((amount as u128) * fee_rate / FEE_PRECISION) as u64)
    }
    
    fun min_u128(x: u128, y: u128): u128 {
        if (x <= y) { x } else { y }
    }
}