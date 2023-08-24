#[test_only]
module desui_labs::test_default {
    use sui::coin::{Self, Coin};
    use sui::address;
    use sui::sui::SUI;
    use sui::test_scenario as ts;
    use desui_labs::coin_flip_v2::{Self as cf, House, AdminCap};
    use desui_labs::test_utils as tu;
    use bucket_protocol::buck::BUCK;

    #[test]
    fun test_play_using_sui() {
        let min_stake_amount: u64 = 1_000_000_000; // 1 SUI
        let max_stake_amount: u64 = 50_000_000_000; // 50 SUI
        let init_pool_amount: u64 = 100 * max_stake_amount;
        let fee_rate: u128 = 10_000; // 1%
        let player_count: u64 = 8_000;

        let scenario_val = tu::setup_house<SUI>(
            init_pool_amount,
            fee_rate,
            min_stake_amount,
            max_stake_amount,
        );
        let scenario = &mut scenario_val;
        let player_generator = tu::new_player_generator(
            b"CoinFlip V2 Default",
            min_stake_amount,
            max_stake_amount,
        );

        // players start games and dev settle them
        let idx: u64 = 0;
        while(idx < player_count) {
            let (player, stake) = tu::gen_player_and_stake<SUI>(
                &mut player_generator,
                ts::ctx(scenario)
            );
            let stake_amount = coin::value(&stake);
            let seed = address::to_bytes(player);
            // start a game
            ts::next_tx(scenario, player);
            let (game_id, pool_balance, treasury_balance) = {
                let house = ts::take_shared<House<SUI>>(scenario);
                let pool_balance = cf::house_pool_balance(&house);
                let treasury_balance = cf::house_treasury_balance(&house);
                let guess = ((idx % 2) as u8);
                let game_id = cf::start_game(&mut house, guess, seed, stake, ts::ctx(scenario));
                ts::return_shared(house);
                (game_id, pool_balance, treasury_balance)
            };

            // settle
            ts::next_tx(scenario, tu::dev());
            let player_won = {
                let house = ts::take_shared<House<SUI>>(scenario);
                assert!(cf::game_exists(&house, game_id), 0);
                let game = cf::borrow_game(&house, game_id);
                assert!(cf::game_guess(game) == ((idx % 2) as u8), 0);
                assert!(cf::game_seed(game) == address::to_bytes(player), 0);
                assert!(cf::game_stake_amount(game) == 2*stake_amount, 0);
                assert!(cf::game_fee_rate(game) == fee_rate, 0);
                assert!(cf::house_pool_balance(&house) == pool_balance - stake_amount, 0);
                let bls_sig = address::to_bytes(address::from_u256(address::to_u256(player) - (idx as u256)));
                let player_won = cf::settle_for_testing(&mut house, game_id, bls_sig, ts::ctx(scenario));
                ts::return_shared(house);
                player_won
            };

            // check after settlement
            ts::next_tx(scenario, tu::dev());
            {
                let house = ts::take_shared<House<SUI>>(scenario);
                assert!(!cf::game_exists(&house, game_id), 0);
                let pool_balance_after = cf::house_pool_balance(&house);
                let treasury_balance_after = cf::house_treasury_balance(&house);
                let fee_amount = ((((2*stake_amount) as u128) * fee_rate / 1_000_000u128) as u64);
                if (player_won) {
                    assert!(pool_balance_after == pool_balance - stake_amount, 0);
                    assert!(treasury_balance_after == treasury_balance + fee_amount, 0);
                } else {
                    assert!(pool_balance_after == pool_balance + stake_amount, 0);
                };
                std::debug::print(&cf::house_pool_balance(&house));
                ts::return_shared(house);
                let coin_id = ts::most_recent_id_for_address<Coin<SUI>>(player);
                if (std::option::is_some(&coin_id)) {
                    let coin_id = std::option::destroy_some(coin_id);
                    let reward = ts::take_from_address_by_id<Coin<SUI>>(scenario, player, coin_id);
                    assert!(coin::value(&reward) == 2*stake_amount - fee_amount, 0);
                    ts::return_to_address(player, reward);
                };
            };
            idx = idx + 1;
        };

        // claim SUI from treasury
        let recipient: address = @0xcafe;
        ts::next_tx(scenario, tu::dev());
        let treasury_balance = {
            let house = ts::take_shared<House<SUI>>(scenario);
            std::debug::print(&house);
            let admin_cap = ts::take_from_sender<AdminCap>(scenario);
            let treasury_balance = cf::house_treasury_balance(&house);
            cf::claim(&admin_cap, &mut house, recipient, ts::ctx(scenario));
            ts::return_shared(house);
            ts::return_to_sender(scenario, admin_cap);
            treasury_balance
        };

        // check after claiming
        ts::next_tx(scenario, tu::dev());
        {
            let house = ts::take_shared<House<SUI>>(scenario);
            assert!(cf::house_treasury_balance(&house) == 0, 0);
            ts::return_shared(house);
            let coin_id = ts::most_recent_id_for_address<Coin<SUI>>(recipient);
            assert!(std::option::is_some(&coin_id), 0);
            let coin_id = std::option::destroy_some(coin_id);
            let profit = ts::take_from_address_by_id<Coin<SUI>>(scenario, recipient, coin_id);
            assert!(coin::value(&profit) == treasury_balance, 0);
            ts::return_to_address(recipient, profit);
        };
        
        ts::end(scenario_val);
    }

    #[test]
    fun test_play_using_buck() {
        let min_stake_amount: u64 = 1_000_000_000; // 1 BUCK
        let max_stake_amount: u64 = 25_000_000_000; // 25 BUCK
        let init_pool_amount: u64 = 100 * max_stake_amount;
        let fee_rate: u128 = 4_000; // 0.4%
        let player_count: u64 = 8_000;

        let scenario_val = tu::setup_house<BUCK>(
            init_pool_amount,
            fee_rate,
            min_stake_amount,
            max_stake_amount,
        );
        let scenario = &mut scenario_val;
        let player_generator = tu::new_player_generator(
            b"CoinFlip V2 x Bucket",
            min_stake_amount,
            max_stake_amount,
        );

        let idx: u64 = 0;
        while(idx < player_count) {
            let (player, stake) = tu::gen_player_and_stake<BUCK>(
                &mut player_generator,
                ts::ctx(scenario)
            );
            let stake_amount = coin::value(&stake);
            let seed = address::to_bytes(player);
            // start a game
            ts::next_tx(scenario, player);
            let (game_id, pool_balance, treasury_balance) = {
                let house = ts::take_shared<House<BUCK>>(scenario);
                let pool_balance = cf::house_pool_balance(&house);
                let treasury_balance = cf::house_treasury_balance(&house);
                let guess = ((idx % 2) as u8);
                let game_id = cf::start_game(&mut house, guess, seed, stake, ts::ctx(scenario));
                ts::return_shared(house);
                (game_id, pool_balance, treasury_balance)
            };

            // settle
            ts::next_tx(scenario, tu::dev());
            let player_won = {
                let house = ts::take_shared<House<BUCK>>(scenario);
                assert!(cf::game_exists(&house, game_id), 0);
                let game = cf::borrow_game(&house, game_id);
                assert!(cf::game_guess(game) == ((idx % 2) as u8), 0);
                assert!(cf::game_seed(game) == address::to_bytes(player), 0);
                assert!(cf::game_stake_amount(game) == 2*stake_amount, 0);
                assert!(cf::game_fee_rate(game) == fee_rate, 0);
                assert!(cf::house_pool_balance(&house) == pool_balance - stake_amount, 0);
                let bls_sig = address::to_bytes(address::from_u256(address::to_u256(player) - (idx as u256)));
                let player_won = cf::settle_for_testing(&mut house, game_id, bls_sig, ts::ctx(scenario));
                ts::return_shared(house);
                player_won
            };

            // check after settlement
            ts::next_tx(scenario, tu::dev());
            {
                let house = ts::take_shared<House<BUCK>>(scenario);
                assert!(!cf::game_exists(&house, game_id), 0);
                let pool_balance_after = cf::house_pool_balance(&house);
                let treasury_balance_after = cf::house_treasury_balance(&house);
                let fee_amount = ((((2*stake_amount) as u128) * fee_rate / 1_000_000u128) as u64);
                if (player_won) {
                    assert!(pool_balance_after == pool_balance - stake_amount, 0);
                    assert!(treasury_balance_after == treasury_balance + fee_amount, 0);
                } else {
                    assert!(pool_balance_after == pool_balance + stake_amount, 0);
                };
                std::debug::print(&cf::house_pool_balance(&house));
                ts::return_shared(house);
                let coin_id = ts::most_recent_id_for_address<Coin<BUCK>>(player);
                if (std::option::is_some(&coin_id)) {
                    let coin_id = std::option::destroy_some(coin_id);
                    let reward = ts::take_from_address_by_id<Coin<BUCK>>(scenario, player, coin_id);
                    assert!(coin::value(&reward) == 2*stake_amount - fee_amount, 0);
                    ts::return_to_address(player, reward);
                };
            };
            idx = idx + 1;
        };

        // claim SUI from treasury
        let recipient: address = @0xcafe;
        ts::next_tx(scenario, tu::dev());
        let treasury_balance = {
            let house = ts::take_shared<House<BUCK>>(scenario);
            std::debug::print(&house);
            let admin_cap = ts::take_from_sender<AdminCap>(scenario);
            let treasury_balance = cf::house_treasury_balance(&house);
            cf::claim(&admin_cap, &mut house, recipient, ts::ctx(scenario));
            ts::return_shared(house);
            ts::return_to_sender(scenario, admin_cap);
            treasury_balance
        };

        // check after claiming
        ts::next_tx(scenario, tu::dev());
        {
            let house = ts::take_shared<House<BUCK>>(scenario);
            assert!(cf::house_treasury_balance(&house) == 0, 0);
            ts::return_shared(house);
            let coin_id = ts::most_recent_id_for_address<Coin<BUCK>>(recipient);
            assert!(std::option::is_some(&coin_id), 0);
            let coin_id = std::option::destroy_some(coin_id);
            let profit = ts::take_from_address_by_id<Coin<BUCK>>(scenario, recipient, coin_id);
            assert!(coin::value(&profit) == treasury_balance, 0);
            ts::return_to_address(recipient, profit);
        };

        ts::end(scenario_val);
    }
}
