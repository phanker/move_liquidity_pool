module lp_account::liquidity_pool {
    //==============================================================================================
    // Dependencies
    //==============================================================================================
    use std::type_info;
    use aptos_framework::event;
    use aptos_framework::option;

    use aptos_framework::account;
    use aptos_framework::math128;
    use aptos_framework::timestamp;
    use std::string::{Self, String};

    use aptos_framework::resource_account;
    use aptos_framework::coin::{Self, Coin};
    use aptos_std::comparator::{Self};

    // seed for module's resource account
    const SEED: vector<u8> = b"lp account";
    const ECodeForAllErrors: u64 = 77482993;

    /*
        LP coin struct
    */
    struct LPCoin<phantom CoinA, phantom CoinB> has key, store {}

    /*
        Liquidity pool resource that holds the liquidity pool's state. To be stored in the module's
        resource account
    */
    struct LiquidityPool<phantom CoinA, phantom CoinB> has key {
        // coin reserve of the CoinA coin - holds the pool's CoinA coins
        coin_a_reserve: Coin<CoinA>,
        // coin reserve of the CoinB coin - holds the pool's CoinB coins
        coin_b_reserve: Coin<CoinB>,
        // mint cap of the specific pool's LP token
        lp_coin_mint_cap: coin::MintCapability<LPCoin<CoinA, CoinB>>,
        // burn cap of the specific pool's LP token
        lp_coin_burn_cap: coin::BurnCapability<LPCoin<CoinA, CoinB>>
    }

    /*
        Module's state resource to hold module metadata and events. To be stored in the module's
        resource account.
    */
    struct State has key {
        // signer cap of the module's resource account
        signer_cap: account::SignerCapability,
        // events
        create_liquidity_pool_events: event::EventHandle<CreateLiquidityPoolEvent>,
        supply_liquidity_events: event::EventHandle<SupplyLiquidityEvent>,
        remove_liquidity_events: event::EventHandle<RemoveLiquidityEvent>,
        swap_events: event::EventHandle<SwapEvent>
    }

    /*
        Event to be emitted when a liquidity pool is created
    */
    struct CreateLiquidityPoolEvent has store, drop {
        // name of the first coin in the liquidity pool
        coin_a: String,
        // name of the second coin in the liquidity pool
        coin_b: String,
        // name of the liquidity pool's LP coin
        lp_coin: String,
        // timestamp of when the event was emitted
        creation_timestamp_seconds: u64
    }

    /*
        Event to be emitted when a liquidity pool is supplied with liquidity
    */
    struct SupplyLiquidityEvent has store, drop {
        // name of the first coin in the liquidity pool
        coin_a: String,
        // name of the second coin in the liquidity pool
        coin_b: String,
        // amount of the first coin being supplied
        amount_a: u64,
        // amount of the second coin being supplied
        amount_b: u64,
        // amount of LP coins being minted
        lp_amount: u64,
        // timestamp of when the event was emitted
        creation_timestamp_seconds: u64
    }

    /*
        Event to be emitted when a liquidity pool is removed of liquidity
    */
    struct RemoveLiquidityEvent has store, drop {
        // name of the first coin in the liquidity pool
        coin_a: String,
        // name of the second coin in the liquidity pool
        coin_b: String,
        // amount of LP coins being burned
        lp_amount: u64,
        // amount of the first coin being removed
        amount_a: u64,
        // amount of the second coin being removed
        amount_b: u64,
        // timestamp of when the event was emitted
        creation_timestamp_seconds: u64
    }

    /*
        Event to be emitted when a liquidity pool is swapped
    */
    struct SwapEvent has store, drop {
        // name of the first coin in the liquidity pool
        coin_a: String,
        // name of the second coin in the liquidity pool
        coin_b: String,
        // amount of the first coin being swapped in
        amount_coin_a_in: u64,
        // amount of the first coin being swapped out
        amount_coin_a_out: u64,
        // amount of the second coin being swapped in
        amount_coin_b_in: u64,
        // amount of the second coin being swapped out
        amount_coin_b_out: u64,
        // timestamp of when the event was emitted
        creation_timestamp_seconds: u64
    }

    //==============================================================================================
    // Functions
    //==============================================================================================

    /*
        Initializes the module by retrieving the module's resource account signer, and creating and
        moving the module's state resource
        @param admin - signer representing the admin of this module
    */

    fun init_module(admin: &signer) {
        let overmind = @mine;
        let signer_cap = resource_account::retrieve_resource_account_cap(admin, overmind);
        let create_liquidity_pool_events = account::new_event_handle<CreateLiquidityPoolEvent>(admin);
        let supply_liquidity_events = account::new_event_handle<SupplyLiquidityEvent>(admin);
        let remove_liquidity_events = account::new_event_handle<RemoveLiquidityEvent>(admin);
        let swap_events = account::new_event_handle<SwapEvent>(admin);
        let state = State { signer_cap, create_liquidity_pool_events, supply_liquidity_events, remove_liquidity_events, swap_events };
        move_to(admin, state);
    }

    /*
		Creates a liquidity pool for CoinA and CoinB. Aborts if the liquidity pool already exists,
        if CoinA or CoinB does not exist, or if CoinA and CoinB are not sorted or are equal.
        @type_param CoinA - the type of the first coin for the liquidity pool
        @type_param CoinB - the type of the second coin for the liquidity pool
    */
    public entry fun create_liquidity_pool<CoinA, CoinB>() acquires State {
        let state = borrow_global_mut<State>(@lp_account);
        let signer_cap = &state.signer_cap;
        let lpSigner = account::create_signer_with_capability(signer_cap);
        assert!(!exists<LiquidityPool<CoinA, CoinB>>(std::signer::address_of(&lpSigner)), ECodeForAllErrors);

        assert!(coin::is_coin_initialized<CoinA>(), ECodeForAllErrors);
        assert!(coin::is_coin_initialized<CoinB>(), ECodeForAllErrors);
        let coin_a_type = type_info::type_name<CoinA>();
        let coin_b_type = type_info::type_name<CoinB>();

        assert!(comparator::is_smaller_than(&(comparator::compare(&coin_a_type, &coin_b_type))), ECodeForAllErrors);


        let coin_symbol = string::utf8(b"");
        let coin_name = string::utf8(b"");
        let coin_a_symbol = coin::symbol<CoinA>();
        let coin_b_symbol = coin::symbol<CoinB>();
        let separator = string::utf8(b"-");
        string::append(&mut coin_name, string::utf8(b"\""));
        if (string::length(&coin_a_symbol) > 4) {
            // string::utf8(b"\"TC1\"-\"TC2\" LP token");
            let sub = string::sub_string(&coin_a_symbol, 0, 4);
            string::append(&mut coin_symbol, sub);
        }else {
            string::append(&mut coin_symbol, coin_a_symbol);
        };

        string::append(&mut coin_name, coin_a_symbol);
        string::append(&mut coin_name, string::utf8(b"\"-\""));

        string::append(&mut coin_symbol, separator);


        if (string::length(&coin_b_symbol) > 4) {
            let sub = string::sub_string(&coin_b_symbol, 0, 4);
            string::append(&mut coin_symbol, sub);
        }else {
            string::append(&mut coin_symbol, coin_b_symbol);
        };
        string::append(&mut coin_name, coin_b_symbol);
        string::append(&mut coin_name, string::utf8(b"\" LP token"));

        //initialize lpcoin
        let (burn_cap, free_cap, mint_cap) = coin::initialize<LPCoin<CoinA, CoinB>>(&lpSigner,
            coin_name,
            coin_symbol,
            8,
            true
        );
        coin::destroy_freeze_cap(free_cap);
        let lqPoll = LiquidityPool<CoinA, CoinB> {
            coin_a_reserve: coin::zero(),
            coin_b_reserve: coin::zero(),
            lp_coin_mint_cap: mint_cap,
            lp_coin_burn_cap: burn_cap,
        };
        move_to(&lpSigner, lqPoll);
        coin::register<LPCoin<CoinA, CoinB>>(&lpSigner);
        event::emit_event<CreateLiquidityPoolEvent>(
            &mut state.create_liquidity_pool_events,
            CreateLiquidityPoolEvent {
                // name of the first coin in the liquidity pool
                coin_a: coin::name<CoinA>(),
                // name of the second coin in the liquidity pool
                coin_b: coin::name<CoinB>(),
                // name of the liquidity pool's LP coin
                lp_coin: coin::name<LPCoin<CoinA, CoinB>>(),
                // timestamp of when the event was emitted
                creation_timestamp_seconds: timestamp::now_seconds()
            }
        );
    }

    /*
		Supplies a liquidity pool with coins in exchange for liquidity pool coins. Aborts if the
        coin types are not sorted or are equal, if the liquidity pool does not exist, or if the
        liquidity is not above 0 and the minimum liquidity (for the initial liquidity)
        @type_param CoinA - the type of the first coin for the liquidity pool
        @type_param CoinB - the type of the second coin for the liquidity pool
		@param coin_a - coins that match the first coin in the liquidity pool
		@param coin_b - coins that match the second coin in the liquidity pool
		@return - liquidity coins from the pool being supplied
    */
    public fun supply_liquidity<CoinA, CoinB>(
        coin_a: Coin<CoinA>,
        coin_b: Coin<CoinB>
    ): Coin<LPCoin<CoinA, CoinB>> acquires State, LiquidityPool {
        let coin_a_type = type_info::type_name<CoinA>();
        let coin_b_type = type_info::type_name<CoinB>();
        //sort
        assert!(comparator::is_smaller_than(&(comparator::compare(&coin_a_type, &coin_b_type))), ECodeForAllErrors);
        //equal
        assert!(!(comparator::is_equal(&(comparator::compare(&coin_a_type, &coin_b_type)))), ECodeForAllErrors);

        assert!(exists<LiquidityPool<CoinA, CoinB>>(@lp_account), ECodeForAllErrors);
        let coin_a_amount = ((coin::value(&coin_a)) as u128);
        let coin_b_amount = ((coin::value(&coin_b)) as u128);
        assert!((coin_a_amount > 0 && coin_b_amount > 0), ECodeForAllErrors);
        let lp_pool = borrow_global_mut<LiquidityPool<CoinA, CoinB>>(@lp_account);
        let coin_a_reserve_amount = coin::value(&lp_pool.coin_a_reserve);
        let coin_b_reserve_amount = coin::value(&lp_pool.coin_b_reserve);
        let minimum_liquidity = 1000;
        // Math:
        // When performing liquidity pool math calculations, values are cast to u128 to avoid overflow.
        //     In production, it is best to check that the result of the math calculation is not too big
        // before casting back down to u64.
        let lp_coin: Coin<LPCoin<CoinA, CoinB>> ;
        let lp_amount;
        if (coin_a_reserve_amount == 0 && coin_b_reserve_amount == 0) {
            // Once added liquidity
            let sqrt = math128::sqrt(coin_a_amount * coin_b_amount);
            assert!(sqrt > minimum_liquidity, ECodeForAllErrors);
            let minimum_liquidity_coin = coin::mint((minimum_liquidity as u64), &lp_pool.lp_coin_mint_cap);
            lp_coin = coin::mint(((sqrt - minimum_liquidity) as u64), &lp_pool.lp_coin_mint_cap);
            coin::deposit(@lp_account, minimum_liquidity_coin);
            lp_amount = sqrt;
        }else {
            // min(amount_coin_a * lp_coins_total_supply / amount_coin_a_reserve,
            //     amount_coin_b * lp_coins_total_supply / amount_coin_b_reserve)
            let total_supply_option = coin::supply<LPCoin<CoinA, CoinB>>();
            let lp_coins_total_supply = option::extract(&mut total_supply_option);
            let a_quot = (coin_a_amount * (lp_coins_total_supply * 1_000_000 / (coin_a_reserve_amount as u128))) / 1_000_000;
            let b_quot = (coin_b_amount * (lp_coins_total_supply * 1_000_000 / (coin_b_reserve_amount as u128))) / 1_000_000;
            let quot = math128::min(a_quot, b_quot);
            lp_coin = coin::mint((quot as u64), &lp_pool.lp_coin_mint_cap);
            lp_amount = quot;
        };

        coin::merge(&mut lp_pool.coin_a_reserve, coin_a);
        coin::merge(&mut lp_pool.coin_b_reserve, coin_b);

        let state = borrow_global_mut<State>(@lp_account);
        event::emit_event<SupplyLiquidityEvent>(
            &mut state.supply_liquidity_events,
            SupplyLiquidityEvent {
                // name of the first coin in the liquidity pool
                coin_a: coin::name<CoinA>(),
                // name of the second coin in the liquidity pool
                coin_b: coin::name<CoinB>(),
                // amount of the first coin being supplied
                amount_a: (coin_a_amount as u64),
                // amount of the second coin being supplied
                amount_b: (coin_b_amount as u64),
                // amount of LP coins being minted
                lp_amount: (lp_amount as u64),
                // timestamp of when the event was emitted
                creation_timestamp_seconds: timestamp::now_seconds()
            }
        );
        lp_coin
    }

    /*
		Removes liquidity from a pool for a cost of liquidity coins. Aborts if the amounts of coins
        to return are not above 0.
        @type_param CoinA - the type of the first coin for the liquidity pool
        @type_param CoinB - the type of the second coin for the liquidity pool
		@param lp_coins - liquidity coins from the pool being supplied
		@return - the two coins being removed from the liquidity pool
    */
    public fun remove_liquidity<CoinA, CoinB>(
        lp_coins_to_redeem: Coin<LPCoin<CoinA, CoinB>>
    ): (Coin<CoinA>, Coin<CoinB>) acquires State, LiquidityPool {
        let amount_lp_coins = coin::value(&lp_coins_to_redeem);
        assert!(amount_lp_coins > 0, ECodeForAllErrors);

        let lp_pool = borrow_global_mut<LiquidityPool<CoinA, CoinB>>(@lp_account);


        let amount_coin_a_reserve = coin::value(&lp_pool.coin_a_reserve);
        let amount_coin_b_reserve = coin::value(&lp_pool.coin_b_reserve);
        let lp_coins_total_supply_option = coin::supply<LPCoin<CoinA, CoinB>>();

        let lp_coins_total_supply = option::extract(&mut lp_coins_total_supply_option);

        let amount_coin_a = (amount_lp_coins as u128) * (((amount_coin_a_reserve * 1_000_000 as u128) / lp_coins_total_supply)) / 1_000_000;
        let amount_coin_b = (amount_lp_coins as u128) * (((amount_coin_b_reserve * 1_000_000 as u128) / lp_coins_total_supply)) / 1_000_000;

        //burn
        coin::burn(lp_coins_to_redeem, &lp_pool.lp_coin_burn_cap);

        let coin_a_return = coin::extract(&mut lp_pool.coin_a_reserve, (amount_coin_a as u64));
        let coin_b_return = coin::extract(&mut lp_pool.coin_b_reserve, (amount_coin_b as u64));

        let state = borrow_global_mut<State>(@lp_account);


        event::emit_event<RemoveLiquidityEvent>(&mut state.remove_liquidity_events, RemoveLiquidityEvent {
            // name of the first coin in the liquidity pool
            coin_a: coin::name<CoinA>(),
            // name of the second coin in the liquidity pool
            coin_b: coin::name<CoinB>(),
            // amount of LP coins being burned
            lp_amount: amount_lp_coins,
            // amount of the first coin being removed
            amount_a: (amount_coin_a as u64),
            // amount of the second coin being removed
            amount_b: (amount_coin_b as u64),
            // timestamp of when the event was emitted
            creation_timestamp_seconds: timestamp::now_seconds()
        });

        (coin_a_return, coin_b_return)
    }

    /*
		Swaps coin in a liquidity pool. Can swap both ways at the same time. Aborts if the coin
        types are not sorted or are equal, if the liquidity pool does not exist, if the new LP k
        value is less than the old LP k value, or if the amount of coins being swapped in is not
        above 0.
        @type_param CoinA - the type of the first coin for the liquidity pool
        @type_param CoinB - the type of the second coin for the liquidity pool
		@param coin_a_in: the coins representing the CoinA being swapped into the pool
		@param amount_coin_a_out: the expected amount of CoinA being swapped out of the pool
		@param coin_b_in: the coins representing the CoinB being swapped into the pool
		@param amount_coin_b_out: the expected amount of CoinB being swapped out of the pool
		@return - the two coins being swapped out of the liquidity pool
    */
    public fun swap<CoinA, CoinB>(
        coin_a_in: Coin<CoinA>,
        amount_coin_a_out: u64,
        coin_b_in: Coin<CoinB>,
        amount_coin_b_out: u64
    ): (Coin<CoinA>, Coin<CoinB>) acquires State, LiquidityPool {
        let coin_a_type = type_info::type_name<CoinA>();
        let coin_b_type = type_info::type_name<CoinB>();
        //sort
        assert!(comparator::is_smaller_than(&(comparator::compare(&coin_a_type, &coin_b_type))), ECodeForAllErrors);
        //equal
        assert!(!(comparator::is_equal(&(comparator::compare(&coin_a_type, &coin_b_type)))), ECodeForAllErrors);

        assert!(exists<LiquidityPool<CoinA, CoinB>>(@lp_account), ECodeForAllErrors);

        let coin_a_in_amount = coin::value(&coin_a_in);
        let coin_b_in_amount = coin::value(&coin_b_in);
        assert!(
            (coin_a_in_amount == 0 && coin_b_in_amount > 0) || (coin_a_in_amount > 0 && coin_b_in_amount == 0) || (coin_a_in_amount > 0 && coin_b_in_amount > 0),
            ECodeForAllErrors
        );

        let lp_pool = borrow_global_mut<LiquidityPool<CoinA, CoinB>>(@lp_account);

        let amount_coin_a_reserve = coin::value(&lp_pool.coin_a_reserve);
        let amount_coin_b_reserve = coin::value(&lp_pool.coin_b_reserve);
        assert!(amount_coin_a_out <= amount_coin_a_reserve, ECodeForAllErrors);
        assert!(amount_coin_b_out <= amount_coin_b_reserve, ECodeForAllErrors);


        let old_k = amount_coin_a_reserve * amount_coin_b_reserve ;
        let new_k = (amount_coin_a_reserve - amount_coin_a_out + coin_a_in_amount) * (amount_coin_b_reserve - amount_coin_b_out + coin_b_in_amount);
        assert!(new_k >= old_k, ECodeForAllErrors);

        coin::merge(&mut lp_pool.coin_a_reserve, coin_a_in);
        let coin_b_return = coin::extract(&mut lp_pool.coin_b_reserve, amount_coin_b_out);

        coin::merge(&mut lp_pool.coin_b_reserve, coin_b_in);
        let coin_a_return = coin::extract(&mut lp_pool.coin_a_reserve, amount_coin_a_out);

        let state = borrow_global_mut<State>(@lp_account);
        event::emit_event<SwapEvent>(&mut state.swap_events, SwapEvent {
            // name of the first coin in the liquidity pool
            coin_a: coin::name<CoinA>(),
            // name of the second coin in the liquidity pool
            coin_b: coin::name<CoinB>(),
            // amount of the first coin being swapped in
            amount_coin_a_in: coin_a_in_amount,
            // amount of the first coin being swapped out
            amount_coin_a_out,
            // amount of the second coin being swapped in
            amount_coin_b_in: coin_b_in_amount,
            // amount of the second coin being swapped out
            amount_coin_b_out,
            // timestamp of when the event was emitted
            creation_timestamp_seconds: timestamp::now_seconds()
        });

        (coin_a_return, coin_b_return)
    }

}
