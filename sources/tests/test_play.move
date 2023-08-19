#[test_only]
module desui_labs::test_play {
    use std::vector;
    use sui::sui::SUI;
    use sui::coin::Coin;
    use sui::address;
    use sui::test_scenario as ts;
    use desui_labs::coin_flip_v2::{Self as cf, House};
    use desui_labs::test_utils::{setup_house, setup_players, dev};

    #[test]
    fun test_play() {
        let min_stake_amount: u64 = 1_000_000_000; // 1 SUI
        let max_stake_amount: u64 = 50_000_000_000; // 50 SUI
        let init_pool_amount: u64 = 100 * max_stake_amount;
        let fee_rate = 10_000; // 1%

        let scenario_val = setup_house<SUI>(
            init_pool_amount,
            fee_rate,
            min_stake_amount,
            max_stake_amount,
        );
        let scenario = &mut scenario_val;
        let player_count: u64 = 300;
        let players = setup_players<SUI>(
            scenario,
            player_count,
            min_stake_amount,
            max_stake_amount,
        );

        let idx: u64 = 0;
        while(idx < player_count) {
            let player = *vector::borrow(&players, idx);
            let seed = address::to_bytes(player);
            // start a game
            ts::next_tx(scenario, player);
            {
                let house = ts::take_shared<House<SUI>>(scenario);
                let stake = ts::take_from_sender<Coin<SUI>>(scenario);
                cf::start_game(&mut house, 0, seed, stake, ts::ctx(scenario));
                ts::return_shared(house);
            };

            // settle
            ts::next_tx(scenario, dev());
            {
                let house = ts::take_shared<House<SUI>>(scenario);
                assert!(cf::is_unsettled(&house, player), 0);
                vector::push_back(&mut seed, ((idx % 256) as u8));
                cf::settle_for_testing(&mut house, player, seed, ts::ctx(scenario));
                ts::return_shared(house);
            };

            // check if settled
            ts::next_tx(scenario, dev());
            {
                let house = ts::take_shared<House<SUI>>(scenario);
                assert!(!cf::is_unsettled(&house, player), 0);
                std::debug::print(&cf::house_pool_balance(&house));
                ts::return_shared(house);
            };
            idx = idx + 1;
        };

        ts::next_tx(scenario, dev());
        {
            let house = ts::take_shared<House<SUI>>(scenario);
            std::debug::print(&house);
            ts::return_shared(house);
        };

        ts::end(scenario_val);
    }
}
