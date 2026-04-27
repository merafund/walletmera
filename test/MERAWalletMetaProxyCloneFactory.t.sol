// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {BaseMERAWallet} from "../src/BaseMERAWallet.sol";
import {IBaseMERAWalletErrors} from "../src/interfaces/IBaseMERAWalletErrors.sol";
import {MERAWalletLoginRegistry} from "../src/MERAWalletLoginRegistry.sol";
import {MERAWalletMetaProxyCloneFactory} from "../src/MERAWalletMetaProxyCloneFactory.sol";
import {MERAWalletTypes} from "../src/types/MERAWalletTypes.sol";

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

    function setUp() public {
        implementation = new BaseMERAWallet(address(1), address(2), address(3), address(0), address(0));
        registry = new MERAWalletLoginRegistry(owner);
        factory = new MERAWalletMetaProxyCloneFactory(address(implementation), address(registry));

        vm.prank(owner);
        registry.setFactory(address(factory), true);
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

        vm.expectEmit(true, true, true, true);
        emit MERAWalletMetaProxyCloneFactory.WalletDeployed(keccak256(bytes(login)), login, predicted);

        address deployed = factory.deployWallet(login, p);

        assertEq(deployed, predicted);
        assertEq(factory.walletOf(login), deployed);
        assertEq(factory.walletByLoginHash(keccak256(bytes(login))), deployed);
        assertEq(registry.walletOf(login), deployed);
        assertEq(registry.loginHashByWallet(deployed), keccak256(bytes(login)));
        assertEq(registry.loginOf(deployed), login);

        BaseMERAWallet wallet = BaseMERAWallet(payable(deployed));
        assertEq(wallet.primary(), primary);
        assertEq(wallet.backup(), backup);
        assertEq(wallet.emergency(), emergency);
        assertEq(wallet.eip1271Signer(), signer);
        assertEq(wallet.GUARDIAN(), guardian);
        assertTrue(wallet.isLifeController(emergency));
        assertEq(wallet.lastLifeHeartbeatAt(), block.timestamp);
    }

    function test_deploy_twice_same_login_reverts() public {
        string memory login = "carol";
        MERAWalletTypes.WalletInitParams memory p = _params();
        factory.deployWallet(login, p);

        vm.expectRevert(MERAWalletMetaProxyCloneFactory.LoginAlreadyRegistered.selector);
        factory.deployWallet(login, p);
    }

    function test_registry_transfer_login_to_new_address() public {
        string memory login = "carol";
        MERAWalletTypes.WalletInitParams memory p = _params();
        address deployed = factory.deployWallet(login, p);
        address newWallet = address(0x123456);

        vm.expectEmit(true, true, true, true);
        emit MERAWalletLoginRegistry.LoginTransferred(keccak256(bytes(login)), login, deployed, newWallet);

        vm.prank(deployed);
        registry.transferLogin(login, newWallet);

        assertEq(registry.walletOf(login), newWallet);
        assertEq(registry.loginHashByWallet(deployed), bytes32(0));
        assertEq(registry.loginHashByWallet(newWallet), keccak256(bytes(login)));
        assertEq(registry.loginOf(newWallet), login);
    }

    function test_registry_transfer_reverts_when_not_current_wallet() public {
        string memory login = "carol";
        MERAWalletTypes.WalletInitParams memory p = _params();
        factory.deployWallet(login, p);

        vm.expectRevert(MERAWalletLoginRegistry.LoginNotOwned.selector);
        registry.transferLogin(login, address(0x123456));
    }

    function test_registry_only_factory_can_register_login() public {
        vm.expectRevert(MERAWalletLoginRegistry.UnauthorizedFactory.selector);
        registry.registerLogin("mallory", address(0x123456));
    }

    function test_registry_owner_controls_factories() public {
        address otherFactory = address(0xFAc70);

        vm.expectRevert();
        registry.setFactory(otherFactory, true);

        vm.prank(owner);
        registry.setFactory(otherFactory, true);

        assertTrue(registry.isFactory(otherFactory));
    }

    function test_empty_login_reverts() public {
        MERAWalletTypes.WalletInitParams memory p = _params();
        vm.expectRevert(MERAWalletMetaProxyCloneFactory.EmptyLogin.selector);
        factory.deployWallet("", p);
    }

    function test_predict_empty_login_reverts() public {
        MERAWalletTypes.WalletInitParams memory p = _params();
        vm.expectRevert(MERAWalletMetaProxyCloneFactory.EmptyLogin.selector);
        factory.predictWallet("", p);
    }

    function test_walletOf_empty_returns_zero() public view {
        assertEq(factory.walletOf(""), address(0));
    }

    function test_non_zero_value_reverts() public {
        MERAWalletTypes.WalletInitParams memory p = _params();
        vm.expectRevert(MERAWalletMetaProxyCloneFactory.NonZeroValue.selector);
        factory.deployWallet{value: 1 wei}("dave", p);
    }

    function test_initialize_twice_reverts() public {
        MERAWalletTypes.WalletInitParams memory p = _params();
        address deployed = factory.deployWallet("erin", p);

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
}
