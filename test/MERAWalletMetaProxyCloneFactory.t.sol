// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Test} from "forge-std/Test.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {BaseMERAWallet} from "../src/BaseMERAWallet.sol";
import {IBaseMERAWalletErrors} from "../src/interfaces/IBaseMERAWalletErrors.sol";
import {MERAWalletLoginRegistry} from "../src/MERAWalletLoginRegistry.sol";
import {MERALoginSignatureVerifier} from "../src/MERALoginSignatureVerifier.sol";
import {MERAWalletMetaProxyCloneFactory} from "../src/MERAWalletMetaProxyCloneFactory.sol";
import {MERAWalletTypes} from "../src/types/MERAWalletTypes.sol";

contract Mock1271Authorizer is IERC1271 {
    address internal immutable SIGNER;

    constructor(address signer) {
        SIGNER = signer;
    }

    function isValidSignature(bytes32 hash, bytes memory signature) external view returns (bytes4) {
        return ECDSA.recover(hash, signature) == SIGNER ? IERC1271.isValidSignature.selector : bytes4(0xffffffff);
    }
}

contract MERAWalletMetaProxyCloneFactoryTest is Test {
    BaseMERAWallet internal implementation;
    MERAWalletLoginRegistry internal registry;
    MERAWalletMetaProxyCloneFactory internal factory;

    address internal owner = address(0xAD111);
    address internal primary = address(0xA11CE);
    address internal backup = address(0xB0B);
    address internal emergency = address(0xE911);
    address internal signer = primary;
    address internal guardian = address(0xCAFE);
    bytes32 internal secret = keccak256("secret");
    uint256 internal authorizerPk = 0xA11CE123;
    address internal authorizer;

    function setUp() public {
        authorizer = vm.addr(authorizerPk);
        implementation = new BaseMERAWallet(address(1), address(2), address(3), address(0), address(0));
        registry = new MERAWalletLoginRegistry(owner, false);
        factory = new MERAWalletMetaProxyCloneFactory(address(implementation), address(registry));

        vm.prank(owner);
        registry.addFactory(address(factory));
    }

    /// @dev Short logins: free + IMERALoginAuthorizationVerifier, no pre-commit.
    function _authRegistryAndFactory()
        internal
        returns (MERAWalletLoginRegistry reg, MERAWalletMetaProxyCloneFactory fac)
    {
        reg = new MERAWalletLoginRegistry(owner, true);
        fac = new MERAWalletMetaProxyCloneFactory(address(implementation), address(reg));
        vm.prank(owner);
        reg.addFactory(address(fac));
    }

    function _params() internal view returns (MERAWalletTypes.WalletInitParams memory p) {
        p = MERAWalletTypes.WalletInitParams({
            initialPrimary: primary,
            initialBackup: backup,
            initialEmergency: emergency,
            initialSigner: signer,
            initialGuardian: guardian
        });
    }

    function _commit(string memory login, MERAWalletTypes.WalletInitParams memory p)
        internal
        returns (address predicted)
    {
        predicted = factory.predictWallet(login, p);
        registry.commit(registry.makeCommitment(login, predicted, address(factory), secret, 0, keccak256("")));
        vm.warp(block.timestamp + registry.MIN_COMMITMENT_AGE());
    }

    function _deployCommitted(string memory login, MERAWalletTypes.WalletInitParams memory p)
        internal
        returns (address wallet)
    {
        _commit(login, p);
        wallet = factory.deployWallet{value: registry.priceOf(login)}(login, p, secret, 0, "");
    }

    function _commitWithReferrer(
        string memory login,
        MERAWalletTypes.WalletInitParams memory p,
        string memory referrerLogin
    ) internal returns (address predicted) {
        predicted = factory.predictWallet(login, p);
        registry.commit(
            registry.makeCommitment(login, predicted, address(factory), secret, 0, keccak256(""), referrerLogin)
        );
        vm.warp(block.timestamp + registry.MIN_COMMITMENT_AGE());
    }

    function _deployCommittedWithReferrer(
        string memory login,
        MERAWalletTypes.WalletInitParams memory p,
        string memory referrerLogin
    ) internal returns (address wallet) {
        _commitWithReferrer(login, p, referrerLogin);
        wallet = factory.deployWallet{value: registry.priceOf(login)}(login, p, secret, 0, "", referrerLogin);
    }

    function _signAuthorization(
        MERALoginSignatureVerifier verifier,
        string memory login,
        address wallet,
        uint256 deadline
    ) internal view returns (bytes memory) {
        return _signAuthorization(registry, factory, verifier, login, wallet, deadline);
    }

    function _signAuthorization(
        MERAWalletLoginRegistry reg,
        MERAWalletMetaProxyCloneFactory fac,
        MERALoginSignatureVerifier verifier,
        string memory login,
        address wallet,
        uint256 deadline
    ) internal view returns (bytes memory) {
        bytes32 digest = verifier.hashAuthorization(
            address(reg), address(fac), keccak256(bytes(login)), wallet, deadline
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(authorizerPk, digest);
        return abi.encodePacked(r, s, v);
    }

    function test_predict_matches_openzeppelin_prediction() public view {
        string memory login = "alice";
        MERAWalletTypes.WalletInitParams memory p = _params();
        bytes32 salt = keccak256(bytes(login));
        bytes memory args = abi.encode(p);

        address expected =
            Clones.predictDeterministicAddressWithImmutableArgs(address(implementation), args, salt, address(factory));

        assertEq(factory.predictWallet(login, p), expected);
    }

    function test_predict_changes_when_params_change_for_same_login() public view {
        string memory login = "alice";
        MERAWalletTypes.WalletInitParams memory p1 = _params();
        MERAWalletTypes.WalletInitParams memory p2 = _params();
        p2.initialBackup = address(0xBEEF);

        assertTrue(factory.predictWallet(login, p1) != factory.predictWallet(login, p2));
    }

    function test_deploy_registers_wallet_initializes_roles_and_matches_predict() public {
        string memory login = "bob";
        MERAWalletTypes.WalletInitParams memory p = _params();
        address predicted = factory.predictWallet(login, p);

        _commit(login, p);
        vm.expectEmit(true, false, false, true);
        emit MERAWalletMetaProxyCloneFactory.WalletDeployed(keccak256(bytes(login)), login, predicted);
        address deployed = factory.deployWallet{value: registry.priceOf(login)}(login, p, secret, 0, "");

        assertEq(deployed, predicted);
        assertEq(registry.walletOf(login), deployed);
        assertEq(registry.walletByLoginHash(keccak256(bytes(login))), deployed);
        assertEq(registry.loginHashByWallet(deployed), keccak256(bytes(login)));
        assertEq(registry.loginOf(deployed), login);

        BaseMERAWallet wallet = BaseMERAWallet(payable(deployed));
        assertEq(wallet.primary(), primary);
        assertEq(wallet.backup(), backup);
        assertEq(wallet.emergency(), emergency);
        assertEq(wallet.eip1271Signer(), signer);
        assertEq(wallet.guardian(), guardian);
        assertTrue(wallet.isLifeController(emergency));
        assertEq(wallet.lastLifeHeartbeatAt(), block.timestamp);
    }

    function test_deploy_with_referrer_records_referral_and_getters() public {
        MERAWalletTypes.WalletInitParams memory p = _params();
        _deployCommitted("alice", p);
        address bobWallet = _deployCommittedWithReferrer("bob", p, "alice");
        bytes32 bobLoginHash = keccak256(bytes("bob"));
        bytes32 aliceLoginHash = keccak256(bytes("alice"));

        assertEq(registry.walletOf("bob"), bobWallet);
        assertEq(registry.referrerLoginHashByLoginHash(bobLoginHash), aliceLoginHash);
        assertEq(registry.referrerLoginHashOf("bob"), aliceLoginHash);
        assertEq(registry.referrerLoginOf("bob"), "alice");
    }

    function test_deploy_without_referrer_records_zero_referral() public {
        MERAWalletTypes.WalletInitParams memory p = _params();
        _deployCommitted("alice", p);

        assertEq(registry.referrerLoginHashByLoginHash(keccak256(bytes("alice"))), bytes32(0));
        assertEq(registry.referrerLoginHashOf("alice"), bytes32(0));
        assertEq(registry.referrerLoginOf("alice"), "");
    }

    function test_deploy_with_unknown_referrer_reverts() public {
        MERAWalletTypes.WalletInitParams memory p = _params();
        string memory login = "bob";
        _commitWithReferrer(login, p, "alice");

        uint256 price = registry.priceOf(login);
        vm.expectRevert(MERAWalletLoginRegistry.ReferrerLoginNotRegistered.selector);
        factory.deployWallet{value: price}(login, p, secret, 0, "", "alice");
    }

    function test_deploy_with_self_referrer_reverts() public {
        MERAWalletTypes.WalletInitParams memory p = _params();
        string memory login = "alice";
        _commitWithReferrer(login, p, login);

        uint256 price = registry.priceOf(login);
        vm.expectRevert(MERAWalletLoginRegistry.SelfReferral.selector);
        factory.deployWallet{value: price}(login, p, secret, 0, "", login);
    }

    function test_deploy_with_different_referrer_than_commitment_reverts() public {
        MERAWalletTypes.WalletInitParams memory p = _params();
        _deployCommitted("alice", p);
        _deployCommitted("carol", p);
        string memory login = "bob";
        _commitWithReferrer(login, p, "alice");

        uint256 price = registry.priceOf(login);
        vm.expectRevert(MERAWalletLoginRegistry.CommitmentNotFound.selector);
        factory.deployWallet{value: price}(login, p, secret, 0, "", "carol");
    }

    function test_registry_migration_keeps_historical_referral_attribution() public {
        MERAWalletTypes.WalletInitParams memory p = _params();
        _deployCommitted("alice", p);
        address bobWallet = _deployCommittedWithReferrer("bob", p, "alice");
        address carolWallet = _deployCommitted("carol", p);

        vm.prank(bobWallet);
        registry.requestLoginMigration("bob", "carol", carolWallet);
        vm.prank(carolWallet);
        registry.confirmLoginMigration("bob");

        assertEq(registry.walletOf("bob"), carolWallet);
        assertEq(registry.walletOf("carol"), bobWallet);
        assertEq(registry.referrerLoginHashByLoginHash(keccak256(bytes("bob"))), keccak256(bytes("alice")));
        assertEq(registry.referrerLoginOf("bob"), "alice");
        assertEq(registry.referrerLoginHashByLoginHash(keccak256(bytes("carol"))), bytes32(0));
    }

    function test_deploy_twice_same_login_reverts() public {
        string memory login = "carol";
        MERAWalletTypes.WalletInitParams memory p = _params();
        _deployCommitted(login, p);

        uint256 price = registry.priceOf(login);
        vm.expectRevert(MERAWalletMetaProxyCloneFactory.LoginAlreadyRegistered.selector);
        factory.deployWallet{value: price}(login, p, secret, 0, "");
    }

    function test_registry_migrates_login_to_new_wallet_after_confirmation() public {
        string memory login = "carol";
        string memory newLogin = "carol-new";
        MERAWalletTypes.WalletInitParams memory p = _params();
        address deployed = _deployCommitted(login, p);
        address newWallet = _deployCommitted(newLogin, p);

        vm.prank(deployed);
        registry.requestLoginMigration(login, newLogin, newWallet);
        vm.expectEmit(true, true, true, true);
        emit MERAWalletLoginRegistry.LoginTransferred(keccak256(bytes(login)), login, deployed, newWallet);
        vm.prank(newWallet);
        registry.confirmLoginMigration(login);

        assertEq(registry.walletOf(login), newWallet);
        assertEq(registry.walletOf(newLogin), deployed);
        assertEq(registry.loginHashByWallet(deployed), keccak256(bytes(newLogin)));
        assertEq(registry.loginHashByWallet(newWallet), keccak256(bytes(login)));
        assertEq(registry.loginOf(deployed), newLogin);
        assertEq(registry.loginOf(newWallet), login);
    }

    function test_registry_migration_request_reverts_when_not_current_wallet() public {
        string memory login = "carol";
        string memory newLogin = "carol-new";
        MERAWalletTypes.WalletInitParams memory p = _params();
        _deployCommitted(login, p);
        address newWallet = _deployCommitted(newLogin, p);

        vm.expectRevert(MERAWalletLoginRegistry.LoginNotOwned.selector);
        registry.requestLoginMigration(login, newLogin, newWallet);
    }

    function test_registry_migration_confirm_reverts_without_pending_request() public {
        string memory login = "carol";
        string memory newLogin = "carol-new";
        MERAWalletTypes.WalletInitParams memory p = _params();
        _deployCommitted(login, p);
        address newWallet = _deployCommitted(newLogin, p);

        vm.prank(newWallet);
        vm.expectRevert(MERAWalletLoginRegistry.LoginMigrationNotFound.selector);
        registry.confirmLoginMigration(login);
    }

    function test_registry_migration_confirm_reverts_from_wrong_wallet() public {
        string memory login = "carol";
        string memory newLogin = "carol-new";
        MERAWalletTypes.WalletInitParams memory p = _params();
        address deployed = _deployCommitted(login, p);
        address newWallet = _deployCommitted(newLogin, p);

        vm.prank(deployed);
        registry.requestLoginMigration(login, newLogin, newWallet);

        vm.prank(address(0x123456));
        vm.expectRevert(MERAWalletLoginRegistry.LoginMigrationNotConfirmingWallet.selector);
        registry.confirmLoginMigration(login);
    }

    function test_registry_migration_reverts_when_guardian_emergency_differ() public {
        string memory oldLogin = "mig-old";
        string memory newLogin = "mig-new";
        MERAWalletTypes.WalletInitParams memory pOld = _params();
        MERAWalletTypes.WalletInitParams memory pNew = _params();
        pNew.initialGuardian = address(0xBEEF01);

        address oldWallet = _deployCommitted(oldLogin, pOld);
        address newWallet = _deployCommitted(newLogin, pNew);

        vm.prank(oldWallet);
        vm.expectRevert(MERAWalletLoginRegistry.LoginMigrationGuardianEmergencyMismatch.selector);
        registry.requestLoginMigration(oldLogin, newLogin, newWallet);
    }

    function test_registry_only_factory_can_register_login() public {
        uint256 price = registry.priceOf("mallory");
        vm.expectRevert(MERAWalletLoginRegistry.UnauthorizedFactory.selector);
        registry.registerLogin{value: price}("mallory", address(0x123456), secret, 0, "");
    }

    function test_registry_owner_controls_factories() public {
        address otherFactory = address(0xFAc70);

        vm.expectRevert();
        registry.addFactory(otherFactory);

        vm.prank(owner);
        registry.addFactory(otherFactory);

        assertTrue(registry.isFactory(otherFactory));
    }

    function test_empty_login_reverts() public {
        MERAWalletTypes.WalletInitParams memory p = _params();
        vm.expectRevert(MERAWalletLoginRegistry.EmptyLogin.selector);
        factory.deployWallet("", p, secret, 0, "");
    }

    /// @dev Empty login is rejected in the registry; counterfactual prediction still works for off-chain tooling.
    function test_predict_empty_login_matches_openzeppelin_prediction() public view {
        MERAWalletTypes.WalletInitParams memory p = _params();
        bytes32 salt = keccak256(bytes(""));
        bytes memory args = abi.encode(p);
        address expected =
            Clones.predictDeterministicAddressWithImmutableArgs(address(implementation), args, salt, address(factory));
        assertEq(factory.predictWallet("", p), expected);
    }

    function test_registry_walletOf_empty_returns_zero() public view {
        assertEq(registry.walletOf(""), address(0));
    }

    function test_underpay_reverts() public {
        MERAWalletTypes.WalletInitParams memory p = _params();
        string memory login = "dave";
        _commit(login, p);
        uint256 price = registry.priceOf(login);
        vm.expectRevert(MERAWalletLoginRegistry.InvalidPayment.selector);
        factory.deployWallet{value: price - 1 wei}(login, p, secret, 0, "");
    }

    function test_overpay_reverts() public {
        MERAWalletTypes.WalletInitParams memory p = _params();
        string memory login = "dave";
        _commit(login, p);
        uint256 price = registry.priceOf(login);
        vm.expectRevert(MERAWalletLoginRegistry.InvalidPayment.selector);
        factory.deployWallet{value: price + 1 wei}(login, p, secret, 0, "");
    }

    function test_initialize_twice_reverts() public {
        MERAWalletTypes.WalletInitParams memory p = _params();
        address deployed = _deployCommitted("erin", p);

        vm.expectRevert(IBaseMERAWalletErrors.AlreadyInitialized.selector);
        BaseMERAWallet(payable(deployed)).initializeFromImmutableArgs();
    }

    function test_constructor_reverts_for_implementation_without_code() public {
        vm.expectRevert(MERAWalletMetaProxyCloneFactory.WalletImplementationNotDeployed.selector);
        new MERAWalletMetaProxyCloneFactory(address(0x1234), address(registry));
    }

    function test_constructor_reverts_for_registry_without_code() public {
        vm.expectRevert(MERAWalletMetaProxyCloneFactory.LoginRegistryNotDeployed.selector);
        new MERAWalletMetaProxyCloneFactory(address(implementation), address(0x1234));
    }

    function test_registry_prices_short_logins_and_makes_long_logins_free() public view {
        assertEq(registry.priceOf("abc"), 500 ether);
        assertEq(registry.priceOf("abcd"), 50 ether);
        assertEq(registry.priceOf("abcde"), 5 ether);
        assertEq(registry.priceOf("abcdefgh"), 0.005 ether);
        assertEq(registry.priceOf("abcdefghi"), 0.0005 ether);
        assertEq(registry.priceOf("abcdefghij"), 0);
    }

    function test_setBaseLoginPrice_owner_updates_within_bounds() public {
        vm.prank(owner);
        registry.setBaseLoginPrice(0.001 ether);
        assertEq(registry.baseLoginPrice(), 0.001 ether);
        assertEq(registry.priceOf("abcdefghi"), 0.001 ether);
        assertEq(registry.priceOf("abc"), 1000 ether);
    }

    function test_setBaseLoginPrice_reverts_below_min() public {
        uint256 tooLow = registry.MIN_BASE_LOGIN_PRICE() - 1;
        vm.prank(owner);
        vm.expectRevert(MERAWalletLoginRegistry.InvalidBaseLoginPrice.selector);
        registry.setBaseLoginPrice(tooLow);
    }

    function test_setBaseLoginPrice_reverts_above_max() public {
        uint256 tooHigh = registry.MAX_BASE_LOGIN_PRICE() + 1;
        vm.prank(owner);
        vm.expectRevert(MERAWalletLoginRegistry.InvalidBaseLoginPrice.selector);
        registry.setBaseLoginPrice(tooHigh);
    }

    function test_setLoginPriceMultiplier_owner_updates_within_bounds() public {
        vm.prank(owner);
        registry.setLoginPriceMultiplier(2);
        assertEq(registry.loginPriceMultiplier(), 2);
        assertEq(registry.priceOf("abc"), registry.baseLoginPrice() * (2 ** 6));
    }

    function test_setLoginPriceMultiplier_reverts_below_min() public {
        vm.prank(owner);
        vm.expectRevert(MERAWalletLoginRegistry.InvalidLoginPriceMultiplier.selector);
        registry.setLoginPriceMultiplier(1);
    }

    function test_setLoginPriceMultiplier_reverts_above_max() public {
        vm.prank(owner);
        vm.expectRevert(MERAWalletLoginRegistry.InvalidLoginPriceMultiplier.selector);
        registry.setLoginPriceMultiplier(11);
    }

    function test_setLoginPriceMultiplier_reverts_not_owner() public {
        vm.prank(primary);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, primary));
        registry.setLoginPriceMultiplier(5);
    }

    function test_setBaseLoginPrice_reverts_not_owner() public {
        vm.prank(primary);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, primary));
        registry.setBaseLoginPrice(0.01 ether);
    }

    /// @dev Paid registrations accumulate ETH on the registry; owner can withdraw the full balance.
    function test_withdraw_owner_receives_full_balance() public {
        MERAWalletTypes.WalletInitParams memory p = _params();
        _deployCommitted("abcdefghi", p);
        _deployCommitted("jklmnopqr", p);

        uint256 price = registry.priceOf("abcdefghi");
        uint256 total = price * 2;
        assertEq(address(registry).balance, total);

        uint256 ownerBalBefore = owner.balance;
        vm.expectEmit(true, false, false, true);
        emit MERAWalletLoginRegistry.EthWithdrawn(owner, total);
        vm.prank(owner);
        registry.withdraw();

        assertEq(address(registry).balance, 0);
        assertEq(owner.balance, ownerBalBefore + total);
    }

    function test_withdraw_reverts_when_balance_zero() public {
        vm.prank(owner);
        vm.expectRevert(MERAWalletLoginRegistry.NothingToWithdraw.selector);
        registry.withdraw();
    }

    function test_withdraw_reverts_not_owner() public {
        vm.prank(primary);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, primary));
        registry.withdraw();
    }

    function test_registry_accepts_ensip15_ascii_subset() public view {
        assertEq(registry.validateLogin("abc"), keccak256(bytes("abc")));
        assertEq(registry.validateLogin("abc123"), keccak256(bytes("abc123")));
        assertEq(registry.validateLogin("abc-def"), keccak256(bytes("abc-def")));
        assertEq(registry.validateLogin("a-b"), keccak256(bytes("a-b")));
    }

    function test_registry_rejects_invalid_login_characters_and_shapes() public {
        vm.expectRevert(MERAWalletLoginRegistry.InvalidLoginLength.selector);
        registry.validateLogin("ab");
        vm.expectRevert(MERAWalletLoginRegistry.InvalidLoginLength.selector);
        registry.priceOf("ab");
        vm.expectRevert(MERAWalletLoginRegistry.InvalidLoginLength.selector);
        registry.validateLogin("abcdefghijklmnopqrstuvwxyz1234567");
        vm.expectRevert(MERAWalletLoginRegistry.InvalidLoginCharacter.selector);
        registry.validateLogin("Alice");
        vm.expectRevert(MERAWalletLoginRegistry.InvalidLoginCharacter.selector);
        registry.validateLogin(unicode"алиса");
        vm.expectRevert(MERAWalletLoginRegistry.InvalidLoginCharacter.selector);
        registry.validateLogin("alice.eth");
        vm.expectRevert(MERAWalletLoginRegistry.InvalidLoginCharacter.selector);
        registry.validateLogin("ab_cd");
        vm.expectRevert(MERAWalletLoginRegistry.InvalidHyphen.selector);
        registry.validateLogin("ab--cd");
        vm.expectRevert(MERAWalletLoginRegistry.InvalidHyphen.selector);
        registry.validateLogin("-abc");
        vm.expectRevert(MERAWalletLoginRegistry.InvalidHyphen.selector);
        registry.validateLogin("abc-");
        vm.expectRevert(MERAWalletLoginRegistry.InvalidHyphen.selector);
        registry.validateLogin("a--bc");
    }

    function test_register_without_commit_reverts() public {
        MERAWalletTypes.WalletInitParams memory p = _params();
        uint256 price = registry.priceOf("dave");
        vm.expectRevert(MERAWalletLoginRegistry.CommitmentNotFound.selector);
        factory.deployWallet{value: price}("dave", p, secret, 0, "");
    }

    function test_reveal_before_minimum_age_reverts() public {
        MERAWalletTypes.WalletInitParams memory p = _params();
        string memory login = "dave";
        address predicted = factory.predictWallet(login, p);
        registry.commit(registry.makeCommitment(login, predicted, address(factory), secret, 0, keccak256("")));

        uint256 price = registry.priceOf(login);
        vm.expectRevert(MERAWalletLoginRegistry.CommitmentTooNew.selector);
        factory.deployWallet{value: price}(login, p, secret, 0, "");
    }

    function test_reveal_after_maximum_age_reverts() public {
        MERAWalletTypes.WalletInitParams memory p = _params();
        string memory login = "dave";
        address predicted = factory.predictWallet(login, p);
        registry.commit(registry.makeCommitment(login, predicted, address(factory), secret, 0, keccak256("")));
        vm.warp(block.timestamp + registry.MAX_COMMITMENT_AGE() + 1);

        uint256 price = registry.priceOf(login);
        vm.expectRevert(MERAWalletLoginRegistry.CommitmentExpired.selector);
        factory.deployWallet{value: price}(login, p, secret, 0, "");
    }

    function test_wrong_secret_reverts() public {
        MERAWalletTypes.WalletInitParams memory p = _params();
        string memory login = "dave";
        address predicted = factory.predictWallet(login, p);
        registry.commit(registry.makeCommitment(login, predicted, address(factory), secret, 0, keccak256("")));
        vm.warp(block.timestamp + registry.MIN_COMMITMENT_AGE());

        uint256 price = registry.priceOf(login);
        vm.expectRevert(MERAWalletLoginRegistry.CommitmentNotFound.selector);
        factory.deployWallet{value: price}(login, p, keccak256("wrong"), 0, "");
    }

    function test_commitment_is_deleted_after_successful_registration() public {
        MERAWalletTypes.WalletInitParams memory p = _params();
        string memory login = "dave";
        bytes32 commitment =
            registry.makeCommitment(login, factory.predictWallet(login, p), address(factory), secret, 0, keccak256(""));
        registry.commit(commitment);
        vm.warp(block.timestamp + registry.MIN_COMMITMENT_AGE());
        factory.deployWallet{value: registry.priceOf(login)}(login, p, secret, 0, "");

        assertEq(registry.commitments(commitment), 0);
    }

    function test_l2_mode_requires_valid_authorization() public {
        (MERAWalletLoginRegistry reg, MERAWalletMetaProxyCloneFactory fac) = _authRegistryAndFactory();
        MERALoginSignatureVerifier verifier = new MERALoginSignatureVerifier(authorizer);
        vm.prank(owner);
        reg.setAuthorizationVerifier(address(verifier));

        MERAWalletTypes.WalletInitParams memory p = _params();
        string memory login = "dave";
        address predicted = fac.predictWallet(login, p);
        uint256 deadline = block.timestamp + 15 minutes;
        bytes memory authorization = _signAuthorization(reg, fac, verifier, login, predicted, deadline);

        address deployed = fac.deployWallet(login, p, secret, deadline, authorization);
        assertEq(deployed, predicted);
    }

    function test_l2_mode_rejects_missing_authorization() public {
        (MERAWalletLoginRegistry reg, MERAWalletMetaProxyCloneFactory fac) = _authRegistryAndFactory();
        MERALoginSignatureVerifier verifier = new MERALoginSignatureVerifier(authorizer);
        vm.prank(owner);
        reg.setAuthorizationVerifier(address(verifier));

        MERAWalletTypes.WalletInitParams memory p = _params();
        string memory login = "dave";

        vm.expectRevert(MERALoginSignatureVerifier.InvalidAuthorization.selector);
        fac.deployWallet(login, p, secret, 0, "");
    }

    function test_l2_mode_rejects_expired_authorization() public {
        (MERAWalletLoginRegistry reg, MERAWalletMetaProxyCloneFactory fac) = _authRegistryAndFactory();
        MERALoginSignatureVerifier verifier = new MERALoginSignatureVerifier(authorizer);
        vm.prank(owner);
        reg.setAuthorizationVerifier(address(verifier));

        MERAWalletTypes.WalletInitParams memory p = _params();
        string memory login = "dave";
        address predicted = fac.predictWallet(login, p);
        uint256 deadline = block.timestamp + 30 seconds;
        bytes memory authorization = _signAuthorization(reg, fac, verifier, login, predicted, deadline);
        vm.warp(block.timestamp + 45 seconds);

        vm.expectRevert(MERALoginSignatureVerifier.AuthorizationExpired.selector);
        fac.deployWallet(login, p, secret, deadline, authorization);
    }

    function test_l2_mode_accepts_eip1271_authorizer() public {
        (MERAWalletLoginRegistry reg, MERAWalletMetaProxyCloneFactory fac) = _authRegistryAndFactory();
        Mock1271Authorizer mockAuthorizer = new Mock1271Authorizer(authorizer);
        MERALoginSignatureVerifier verifier = new MERALoginSignatureVerifier(address(mockAuthorizer));
        vm.prank(owner);
        reg.setAuthorizationVerifier(address(verifier));

        MERAWalletTypes.WalletInitParams memory p = _params();
        string memory login = "dave";
        address predicted = fac.predictWallet(login, p);
        uint256 deadline = block.timestamp + 15 minutes;
        bytes memory authorization = _signAuthorization(reg, fac, verifier, login, predicted, deadline);

        address deployed = fac.deployWallet(login, p, secret, deadline, authorization);
        assertEq(deployed, predicted);
    }

    function test_deploy_long_login_without_commit_or_payment() public {
        MERAWalletTypes.WalletInitParams memory p = _params();
        string memory login = "abcdefghij";
        address predicted = factory.predictWallet(login, p);

        vm.expectEmit(true, false, false, true);
        emit MERAWalletMetaProxyCloneFactory.WalletDeployed(keccak256(bytes(login)), login, predicted);
        address deployed = factory.deployWallet(login, p, secret, 0, "");

        assertEq(deployed, predicted);
        assertEq(registry.walletOf(login), deployed);
    }

    function test_paid_mode_skips_authorization_verifier_even_when_set() public {
        MERALoginSignatureVerifier verifier = new MERALoginSignatureVerifier(authorizer);
        vm.prank(owner);
        registry.setAuthorizationVerifier(address(verifier));

        MERAWalletTypes.WalletInitParams memory p = _params();
        string memory login = "dave";
        _commit(login, p);

        address deployed = factory.deployWallet{value: registry.priceOf(login)}(login, p, secret, 0, "");
        assertEq(deployed, factory.predictWallet(login, p));
    }

    function test_short_login_authorization_mode_reverts_without_verifier() public {
        (, MERAWalletMetaProxyCloneFactory fac) = _authRegistryAndFactory();
        MERAWalletTypes.WalletInitParams memory p = _params();
        string memory login = "dave";

        vm.expectRevert(MERAWalletLoginRegistry.AuthorizationVerifierNotSet.selector);
        fac.deployWallet(login, p, secret, 0, "");
    }

    function test_short_login_authorization_mode_rejects_nonzero_value() public {
        (MERAWalletLoginRegistry reg, MERAWalletMetaProxyCloneFactory fac) = _authRegistryAndFactory();
        MERALoginSignatureVerifier verifier = new MERALoginSignatureVerifier(authorizer);
        vm.prank(owner);
        reg.setAuthorizationVerifier(address(verifier));

        MERAWalletTypes.WalletInitParams memory p = _params();
        string memory login = "dave";
        address predicted = fac.predictWallet(login, p);
        uint256 deadline = block.timestamp + 15 minutes;
        bytes memory authorization = _signAuthorization(reg, fac, verifier, login, predicted, deadline);

        vm.expectRevert(MERAWalletLoginRegistry.InvalidPayment.selector);
        fac.deployWallet{value: 1 wei}(login, p, secret, deadline, authorization);
    }
}
