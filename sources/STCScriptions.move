module STCScriptionAdmin::STCScriptions {
    use STCScriptionAdmin::STCScriptionsCalc;

    use StarcoinFramework::Account;
    use StarcoinFramework::Errors;
    use StarcoinFramework::EventUtil;
    use StarcoinFramework::Option;
    use StarcoinFramework::STC::STC;
    use StarcoinFramework::Signer;
    use StarcoinFramework::String;
    use StarcoinFramework::Table;
    use StarcoinFramework::Timestamp;
    use StarcoinFramework::Token;

    const ERR_NO_PRIVILEGE: u64 = 1001;
    const ERR_INIT_REPEATE: u64 = 1002;
    const ERR_NOT_INITIALIZE: u64 = 1003;
    const ERR_INSCRIPTION_ID_NOT_EXISTS: u64 = 1004;
    const ERR_TICK_ID_NOT_EXISTS: u64 = 1005;
    const ERR_NOT_READY: u64 = 1006;
    const ERR_OUT_OF_SUPPLY: u64 = 1007;
    const ERR_NOT_ACCEPTED: u64 = 1008;

    struct TickConfig has key, store {
        current_version: u64,
        next_tick_id: u64,
        next_inscription_id: u64
    }

    struct TickDeploy has key, store {
        version: u64,
        deployed_ticks: Table::Table<u64, TickInfo<STC>>,
    }

    struct TickInfo<phantom T: store> has store {
        tick_id: u64,
        tick_name: String::String,
        start_time: u64,
        duration: u64,
        total_trans: u128,
        total_supply: u128,
        total_mint: u128,
    }

    struct InscriptionContainer has key, store {
        inscriptions: Table::Table<u64, Inscription<STC>>
    }

    struct Inscription<phantom T: store> has store {
        inscription_id: u64,
        tick_id: u64,
        tick_amount: u128,
        tick_address: address,
        token: Token::Token<T>,
        meta_data: Option::Option<TickMetaData>,
    }

    struct TickMetaData has store, drop {
        /// The metadata content type, eg: image/png, image/jpeg, it is optional
        content_type: String::String,
        /// The metadata content
        content: vector<u8>,
    }

    ////////////////////////////////////////////////////////////
    /// Events

    struct TickDeployEvent has store, drop {
        tick_name: vector<u8>,
        total_supply: u128,
        start_time: u64,
        end_time: u64
    }

    struct TickMintEvent has store, drop {
        tick_id: u64,
        tick_name: vector<u8>,
        amount: u128,
        token_amount: u128,
        tick_address: address,
    }

    struct TickBurnEvent has store, drop {
        tick_id: u64,
        inscription_id: u64,
        tick_address: address,
        tick_amount: u128,
        token_amount: u128,
    }

    struct TickTransferEvent has store, drop {
        tick_id: u64,
        inscription_id: u64,
        tick_address: address,
        to_account: address,
    }

    public fun init_genesis(sender: &signer, current_version: u64) {
        assert!(has_privilege(sender), Errors::invalid_argument(ERR_NO_PRIVILEGE));
        assert!(exists<TickConfig>(@STCScriptionAdmin), Errors::invalid_argument(ERR_INIT_REPEATE));
        move_to(sender, TickConfig {
            current_version,
            next_inscription_id: 0,
            next_tick_id: 0,
        });

        EventUtil::init_event<TickMintEvent>(sender);
        EventUtil::init_event<TickDeployEvent>(sender);
        EventUtil::init_event<TickBurnEvent>(sender);
        EventUtil::init_event<TickTransferEvent>(sender);
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

        assert!(!exists<InscriptionContainer>(Signer::address_of(sender)), Errors::already_published(ERR_INIT_REPEATE));
        move_to(sender, InscriptionContainer {
            inscriptions: Table::new()
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
        locked_amount: u128,
        content_type: Option::Option<String::String>,
        content: Option::Option<vector<u8>>,
    ) acquires InscriptionContainer, TickConfig, TickDeploy {
        let mint_amount = STCScriptionsCalc::cal_mint_amount(locked_amount);
        assert!(exists<TickConfig>(@STCScriptionAdmin), Errors::not_published(ERR_NOT_INITIALIZE));
        let tick_config = borrow_global_mut<TickConfig>(@STCScriptionAdmin);

        let be_stake_token = Account::withdraw<STC>(sender, locked_amount);
        let meta_data = if (Option::is_some(&content_type) && Option::is_some(&content)) {
            Option::some<TickMetaData>(TickMetaData {
                content_type: Option::destroy_some(content_type),
                content: Option::destroy_some(content),
            })
        } else {
            Option::none<TickMetaData>()
        };

        let sender_addr = Signer::address_of(sender);
        let container = borrow_global_mut<InscriptionContainer>(sender_addr);
        let inscription_id = tick_config.next_inscription_id;
        Table::add(&mut container.inscriptions, inscription_id, Inscription<STC> {
            inscription_id,
            tick_id,
            tick_address,
            tick_amount: mint_amount,
            token: be_stake_token,
            meta_data,
        });
        tick_config.next_inscription_id = inscription_id + 1;

        let tick_deploy = borrow_global_mut<TickDeploy>(tick_address);
        assert!(
            Table::contains(&mut tick_deploy.deployed_ticks, tick_id),
            Errors::not_published(ERR_TICK_ID_NOT_EXISTS)
        );

        // Check Whether started
        let now = Timestamp::now_seconds();
        let tick_info = Table::borrow_mut(&mut tick_deploy.deployed_ticks, tick_id);
        assert!(
            tick_info.start_time >= now && tick_info.start_time + tick_info.duration < now,
            Errors::invalid_state(ERR_NOT_READY)
        );

        assert!(tick_info.total_mint + mint_amount < tick_info.total_supply, Errors::limit_exceeded(ERR_OUT_OF_SUPPLY));

        // Increase total mint amount
        tick_info.total_mint = tick_info.total_mint + mint_amount;

        // Emit a mint event
        EventUtil::emit_event(@STCScriptionAdmin, TickMintEvent {
            tick_id,
            tick_address,
            tick_name: *String::bytes(&tick_info.tick_name),
            amount: mint_amount,
            token_amount: locked_amount,
        });
    }

    /// Burn from Inscription Container
    public fun burn(sender: &signer, inscription_id: u64) acquires InscriptionContainer, TickDeploy {
        let sender_addr = Signer::address_of(sender);
        let (tick_id, inscription_id, tick_address, tick_amount, token, _meta_data, ) = takeout_inscription_and_unwrap(
            sender_addr,
            inscription_id
        );

        // Decrease total mint
        let tick_deploy = borrow_global_mut<TickDeploy>(tick_address);
        let tick_info = Table::borrow_mut(&mut tick_deploy.deployed_ticks, tick_id);
        tick_info.total_mint = tick_info.total_mint - tick_amount;

        // Emit a burn event
        EventUtil::emit_event(@STCScriptionAdmin, TickBurnEvent {
            tick_id,
            inscription_id,
            tick_address,
            tick_amount,
            token_amount: Token::value(&token),
        });

        Account::deposit(sender_addr, token);
    }


    public fun transfer(sender: &signer, acceptor: address, inscription_id: u64) acquires InscriptionContainer {
        let sender_addr = Signer::address_of(sender);
        let inscription = takeout_inscription(
            sender_addr,
            inscription_id
        );

        let tick_address = inscription.tick_address;
        let tick_id = inscription.tick_id;

        assert!(has_accepted(acceptor), Errors::invalid_state(ERR_NOT_ACCEPTED));
        let container = borrow_global_mut<InscriptionContainer>(acceptor);
        Table::add(&mut container.inscriptions, inscription.tick_id, inscription);

        // Emit a transfer event
        EventUtil::emit_event(@STCScriptionAdmin, TickTransferEvent {
            tick_id,
            inscription_id,
            tick_address,
            to_account: acceptor,
        });
    }

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
        }
    }

    fun takeout_inscription(
        account: address,
        inscription_id: u64
    ): Inscription<STC> acquires InscriptionContainer {
        assert!(exists<InscriptionContainer>(account), Errors::not_published(ERR_NOT_INITIALIZE));

        let container = borrow_global_mut<InscriptionContainer>(account);
        assert!(
            Table::contains(&container.inscriptions, inscription_id),
            Errors::not_published(ERR_INSCRIPTION_ID_NOT_EXISTS)
        );
        Table::remove(&mut container.inscriptions, inscription_id)
    }

    fun takeout_inscription_and_unwrap(
        account: address,
        inscription_id: u64
    ): (u64, u64, address, u128, Token::Token<STC>, Option::Option<TickMetaData>) acquires InscriptionContainer {
        let Inscription<STC> {
            tick_id,
            inscription_id,
            tick_address,
            tick_amount,
            token,
            meta_data,
        } = takeout_inscription(account, inscription_id);
        (tick_id, inscription_id, tick_address, tick_amount, token, meta_data)
    }

    fun has_privilege(sender: &signer): bool {
        Signer::address_of(sender) == @STCScriptionAdmin
    }

    fun has_accepted(account: address): bool {
        exists<InscriptionContainer>(account) && exists<TickDeploy>(account)
    }
}
