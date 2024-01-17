//# init -n test --public-keys STCScriptionAdmin=0x0d72dea203271daae212302f0d02ee96ffe5e10e6f099d0b20551d19d12e2ac5

//# faucet --addr STCScriptionAdmin --amount 10000000000000000

//# faucet --addr alice --amount 10000000000000000

//# faucet --addr bob --amount 10000000000000000

//# block --author 0x1 --timestamp 10000000


//# run --signers STCScriptionAdmin
script {
    use StarcoinFramework::String;
    use StarcoinFramework::Timestamp;
    use STCScriptionAdmin::STCScriptions;

    fun genesis_initialize_and_deploy(signer: signer) {
        STCScriptions::init_genesis(&signer, 1);

        let input_total_supply = 100000000;
        let now_seconds = Timestamp::now_seconds();
        STCScriptions::accept(&signer);
        STCScriptions::deploy(&signer, String::utf8(b"STC"), now_seconds, 86400, input_total_supply);
        let (name, output_total_supply, minted_amount) = STCScriptions::view_deployed_tick(@STCScriptionAdmin, 1);

        // Check deployed information
        assert!(name == b"STC", 1001);
        assert!(output_total_supply == input_total_supply, 1002);
        assert!(minted_amount == 0, 1003);
    }
}
// check: EXECUTED

//# run --signers alice
script {
    use StarcoinFramework::Signer;
    use StarcoinFramework::String;
    use StarcoinFramework::Option;
    use STCScriptionAdmin::STCScriptions;

    fun alice_mint(sender: signer) {
        STCScriptions::accept(&sender);

        STCScriptions::mint(
            &sender,
            @STCScriptionAdmin,
            1,
            10000,
            Option::some(String::utf8(b"applications/text")),
            Option::some(b"Hello STC inscriptions")
        );
        let sender_addr = Signer::address_of(&sender);

        // Check minted inscriptions
        let (
            tick_id,
            tick_name,
            tick_amount,
            lock_token_amount,
            meta_type,
            meta_content
        ) = STCScriptions::view_inscription(sender_addr, 1);

        let inscription_count = STCScriptions::get_inscription_minted_count(sender_addr);

        // Check mint information
        assert!(tick_id == 1, 1011);
        assert!(tick_name == b"STC", 1012);
        assert!(tick_amount == 10000, 1013);
        assert!(lock_token_amount == 10000, 1014);
        assert!(meta_type == b"applications/text", 1014);
        assert!(meta_content == b"Hello STC inscriptions", 1015);
        assert!(inscription_count == 1, 1016);
    }
}
// check: EXECUTED


//# run --signers bob
script {
    use STCScriptionAdmin::STCScriptions;

    fun bob_accept(sender: signer) {
        STCScriptions::accept(&sender);
    }
}
// check: EXECUTED

//# run --signers alice
script {
    use StarcoinFramework::Signer;
    use STCScriptionAdmin::STCScriptions;

    fun alice_transfer_to_bob(sender: signer) {
        STCScriptions::transfer(&sender, @bob, 1);
        assert!(
            STCScriptions::get_inscription_minted_count(Signer::address_of(&sender)) == 0,
            1020
        );
    }
}
// check: EXECUTED

//# run --signers bob
script {
    use StarcoinFramework::Signer;
    use STCScriptionAdmin::STCScriptions;

    fun alice_burn(sender: signer) {
        STCScriptions::burn(&sender, 1);
        assert!(
            STCScriptions::get_inscription_minted_count(Signer::address_of(&sender)) == 0,
            1030
        );
    }
}
// check: EXECUTED
