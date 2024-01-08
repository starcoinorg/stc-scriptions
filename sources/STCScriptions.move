module STCScriptionAdmin::STCScriptions {
    use StarcoinFramework::NFT::Metadata;
    use StarcoinFramework::Vector;
    use StarcoinFramework::Errors;
    use StarcoinFramework::Option;
    use StarcoinFramework::STC::STC;
    use StarcoinFramework::Signer;
    use StarcoinFramework::String;
    use StarcoinFramework::Table;
    use StarcoinFramework::Token;
    use StarcoinFramework::Account;

    use STCScriptionAdmin::STCScriptionsCalc;

    const ERR_NO_PRIVILEGE: u64 = 1001;
    const ERR_INIT_REPEATE: u64 = 1002;
    const ERR_NOT_INITIALIZE: u64 = 1003;

    struct TickConfig has key, store {
        current_version: u64,
        next_tick_id: u64,
        next_inscription_id: u64
    }

    struct TickDeploy has key, store {
        version: u64,
        deployed_ticks: Table::Table<u64, TickInfo<STC>>,
    }

    struct TickInfo<phantom T: store> has key, store {
        tick_id: u64,
        tick_name: String::String,
        start_time: u64,
        duration: u64,
        total_trans: u128,
        total_supply: u128,
        total_mint: u64,
        next_inscription_id: u64,
    }

    struct STCScriptContainer has key, store {
        inscriptions: vector<Inscription<STC>>
    }

    struct Inscription<phantom T: store> {
        inscription_id: u64,
        tick_id: u64,
        token: Token::Token<T>,
        meta_data: Option::Option<TickMetaData>,
    }

    struct TickMetaData {
        /// The metadata content type, eg: image/png, image/jpeg, it is optional
        content_type: String::String,
        /// The metadata content
        content: vector<u8>,
    }

    ////////////////////////////////////////////////////////////
    /// Events
    struct TickMintEvent {
        tick_name: String::String,
        amount: u64,
    }

    public fun init_genesis(sender: &signer, current_version: u64) {
        assert!(has_privilege(sender), Errors::invalid_argument(ERR_NO_PRIVILEGE));
        assert!(exists<TickConfig>(@STCScriptionAdmin), Errors::invalid_argument(ERR_INIT_REPEATE));
        move_to(sender, TickConfig {
            current_version,
            next_inscription_id: 0,
            next_tick_id: 0,
        });
    }

    /// There must accept the `TickDeploy` struct before the user deploy a new tick
    public fun accept(sender: &signer) acquires TickConfig {
        assert!(exists<TickConfig>(@STCScriptionAdmin), Errors::not_published(ERR_NOT_INITIALIZE));
        let sender_addr = Signer::address_of(sender);

        let config = borrow_global<TickConfig>(@STCScriptionAdmin);
        assert!(!exists<TickConfig>(sender_addr), Errors::not_published(ERR_INIT_REPEATE));
        move_to(sender, TickDeploy {
            version: config.current_version,
            deployed_ticks: Table::new(),
        });

        assert!(!exists<STCScriptContainer>(Signer::address_of(sender)), Errors::not_published(ERR_INIT_REPEATE));
        move_to(sender, STCScriptContainer {
            inscriptions: Vector::empty<Inscription<STC>>()
        });
    }

    // Every one can deploy the Tick for inscription
    public fun deploy(
        sender: &signer,
        name: String::String,
        start_time: u64,
        duration: u64,
        total_supply: u128
    ) acquires TickDeploy, TickConfig {
        let sender_addr = Signer::address_of(sender);
        assert!(exists<TickDeploy>(sender_addr), Errors::not_published(ERR_NOT_INITIALIZE));
        assert!(exists<TickConfig>(@STCScriptionAdmin), Errors::not_published(ERR_NOT_INITIALIZE));

        let tick_deploy = borrow_global_mut<TickDeploy>(sender_addr);
        let tick_config = borrow_global_mut<TickConfig>(@STCScriptionAdmin);

        let tick_id = tick_config.next_tick_id;
        let new_tick_info = new_deploy_tick_info<STC>(
            tick_id,
            name,
            start_time,
            duration,
            total_supply
        );
        Table::add(&mut tick_deploy.deployed_ticks, tick_id, new_tick_info);
        tick_config.next_tick_id = tick_id + 1;
    }


    /// TODO: Mint can be extend to other token type
    public fun mint(
        sender: &signer,
        tick_address: address,
        tick_id: u64,
        lock_amount: u128,
        content_type: Option::Option<String::String>,
        content: Option::Option<vector<u8>>,
    ) acquires STCScriptContainer, TickConfig {
        let amount = STCScriptionsCalc::cal_mint_amount(lock_amount);
        assert!(exists<TickConfig>(@STCScriptionAdmin), Errors::not_published(ERR_NOT_INITIALIZE));
        let tick_config = borrow_global_mut<TickConfig>(@STCScriptionAdmin);

        let be_stake_token = Account::withdraw<STC>(sender, amount);
        let meta_data = if (Option::is_some(&content_type) && Option::is_some(&content)) {
            Option::some<TickMetaData>(TickMetaData {
                content_type: Option::destroy_some(content_type),
                content: Option::destroy_some(content),
            })
        } else {
            Option::none<TickMetaData>()
        };

        let container = borrow_global_mut<STCScriptContainer>(tick_address);
        let inscription_id = tick_config.next_inscription_id;
        Vector::push_back(&mut container.inscriptions, Inscription<STC> {
            inscription_id,
            tick_id,
            token: be_stake_token,
            meta_data,
        });
        tick_config.next_inscription_id = inscription_id + 1;
    }

    public fun burn(sender: &signer, scription_id: u64) {}

    public fun transfer(sender: &signer, acceptor: address, inscription_id: u64) {}

    ////////////////////////////////////////////////////
    /// Internal functions
    ///
    fun new_deploy_tick_info<T: store>(
        tick_id: u64,
        tick_name: String::String,
        start_time: u64,
        duration: u64,
        total_supply: u128
    ): TickInfo<T> {
        TickInfo<T> {
            tick_id,
            tick_name,
            start_time,
            duration,
            total_supply,
            total_mint: 0,
            total_trans: 0,
            next_inscription_id: 0,
        }
    }

    fun has_privilege(sender: &signer): bool {
        Signer::address_of(sender) == @STCScriptionAdmin
    }

    // fun gen_next_deploy_id(account_addr: address, advance: bool) : u64 {
    //     assert!(!exists<TickDeploy>(account_addr), Errors::not_published(ERR_NOT_INITIALIZE));
    //     let  borrow_global_mut<TickDeploy>()
    // }
}
