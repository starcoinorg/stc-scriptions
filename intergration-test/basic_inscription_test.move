//# init -n test --public-keys STCScriptionAdmin=0x0d72dea203271daae212302f0d02ee96ffe5e10e6f099d0b20551d19d12e2ac5

//# faucet --addr STCScriptionAdmin --amount 10000000000000000

//# faucet --addr alice --amount 10000000000000000

//# block --author 0x1 --timestamp 10000000


//# run --signers STCScriptionAdmin
script {
    use StarcoinFramework::String;
    use StarcoinFramework::Timestamp::now_seconds;
    use STCScriptionAdmin::STCScriptions;

    fun genesis_initialize_and_deploy(signer: signer) {
        STCScriptions::init_genesis(&signer, 1);

        let now_seconds = now_seconds();
        STCScriptions::deploy(&signer, String::utf8(b"STC"), now_seconds, 86400, 100000000);
    }
}
// check: EXECUTED

//# run --signers alice
script {
    use StarcoinFramework::String;
    use StarcoinFramework::Option;
    use STCScriptionAdmin::STCScriptions;

    fun alice_mint(signer: signer) {
        STCScriptions::mint(
            &signer,
            @STCScriptionAdmin,
            1,
            10000,
            Option::some(String::utf8(b"applications/text")),
            Option::some(b"Hello inscriptions")
        );
    }
}
// check: EXECUTED