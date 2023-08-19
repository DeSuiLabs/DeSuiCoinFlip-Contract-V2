#[test_only]
module desui_labs::test_play_buck {
    use std::vector;
    use sui::coin::Coin;
    use sui::address;
    use sui::test_scenario as ts;
    use desui_labs::coin_flip_v2::{Self as cf, House};
    use desui_labs::test_utils::{setup_house, setup_players, dev};
    use bucket_protocol::buck::BUCK;

    #[test]
    fun test_play_using_buck() {
        let min_stake_amount: u64 = 1_000_000_000; // 1 BUCK
        let max_stake_amount: u64 = 25_000_000_000; // 25 BUCK
        let init_pool_amount: u64 = 100 * max_stake_amount;
        let fee_rate: u128 = 10_000; // 1%
        let player_count: u64 = 8_000;

        let scenario_val = setup_house<BUCK>(
            init_pool_amount,
            fee_rate,
            min_stake_amount,
            max_stake_amount,
        );
        let scenario = &mut scenario_val;
        let players = setup_players<BUCK>(
            scenario,
            player_count,
            min_stake_amount,
            max_stake_amount,
            b"CoinFlip V2 x Bucket Protocol",
        );

        let idx: u64 = 0;
        while(idx < player_count) {
            let player = vector::pop_back(&mut players);
            let seed = address::to_bytes(player);
            // start a game
            ts::next_tx(scenario, player);
            {
                let house = ts::take_shared<House<BUCK>>(scenario);
                let stake = ts::take_from_sender<Coin<BUCK>>(scenario);
                let guess = ((idx % 2) as u8);
                cf::start_game(&mut house, guess, seed, stake, ts::ctx(scenario));
                ts::return_shared(house);
            };

            // settle
            ts::next_tx(scenario, dev());
            {
                let house = ts::take_shared<House<BUCK>>(scenario);
                assert!(cf::is_unsettled(&house, player), 0);
                let bls_sig = address::to_bytes(address::from_u256(address::to_u256(player) - (idx as u256)));
                cf::settle_for_testing(&mut house, player, bls_sig, ts::ctx(scenario));
                ts::return_shared(house);
            };

            // check if settled
            ts::next_tx(scenario, dev());
            {
                // let coin_id = ts::most_recent_id_for_address<Coin<BUCK>>(player);
                // if (std::option::is_some(&coin_id)) {
                //     let coin_id = std::option::destroy_some(coin_id);
                //     let reward = ts::take_from_address_by_id<Coin<BUCK>>(scenario, player, coin_id);
                //     std::debug::print(&reward);
                //     ts::return_to_address(player, reward);
                // };
                let house = ts::take_shared<House<BUCK>>(scenario);
                assert!(!cf::is_unsettled(&house, player), 0);
                std::debug::print(&cf::house_pool_balance(&house));
                ts::return_shared(house);
            };
            idx = idx + 1;
        };

        ts::next_tx(scenario, dev());
        {
            let house = ts::take_shared<House<BUCK>>(scenario);
            std::debug::print(&house);
            ts::return_shared(house);
        };

        ts::end(scenario_val);
    }
}
