// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {MERAWalletCreate2Factory} from "../src/MERAWalletCreate2Factory.sol";
import {MERAWalletConstants} from "../src/constants/MERAWalletConstants.sol";
import {MERAWalletLoginRegistry} from "../src/MERAWalletLoginRegistry.sol";
import {MERAWalletTypes} from "../src/types/MERAWalletTypes.sol";
import {BaseMERAWallet} from "../src/BaseMERAWallet.sol";

contract MERAWalletCreate2FactoryTest is Test {
    /// @dev Runtime bytecode of the Nick deterministic CREATE2 proxy at `MERAWalletConstants.DETERMINISTIC_CREATE2_DEPLOYER` (Ethereum mainnet `eth_getCode`).
    bytes internal constant NICK_CREATE2_PROXY_RUNTIME_CODE =
        hex"7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe03601600081602082378035828234f58015156039578182fd5b8082525050506014600cf3";

    MERAWalletCreate2Factory internal factory;
    MERAWalletLoginRegistry internal registry;

    address internal owner = address(0xAD111);
    address internal primary = address(0xA11CE);
    address internal backup = address(0xB0B);
    address internal emergency = address(0xE911);

    function setUp() public {
        vm.etch(MERAWalletConstants.DETERMINISTIC_CREATE2_DEPLOYER, NICK_CREATE2_PROXY_RUNTIME_CODE);
        registry = new MERAWalletLoginRegistry(owner);
        factory = new MERAWalletCreate2Factory(address(registry));

        vm.prank(owner);
        registry.setFactory(address(factory), true);
    }

    function _params() internal view returns (MERAWalletTypes.WalletInitParams memory p) {
        p = MERAWalletTypes.WalletInitParams({
            initialPrimary: primary,
            initialBackup: backup,
            initialEmergency: emergency,
            initialSigner: address(0),
            initialGuardian: address(0)
        });
    }

    function test_predict_matches_vm_computeCreate2Address() public view {
        string memory login = "alice";
        MERAWalletTypes.WalletInitParams memory p = _params();
        bytes32 salt = keccak256(bytes(login));
        bytes memory initCode = abi.encodePacked(
            type(BaseMERAWallet).creationCode,
            abi.encode(p.initialPrimary, p.initialBackup, p.initialEmergency, p.initialSigner, p.initialGuardian)
        );
        bytes32 initHash = keccak256(initCode);
        address expected = vm.computeCreate2Address(salt, initHash, MERAWalletConstants.DETERMINISTIC_CREATE2_DEPLOYER);
        assertEq(factory.predictWallet(login, p), expected);
    }

    function test_deploy_registers_wallet_and_matches_predict() public {
        string memory login = "bob";
        MERAWalletTypes.WalletInitParams memory p = _params();
        address predicted = factory.predictWallet(login, p);

        vm.expectEmit(true, true, true, true);
        emit MERAWalletCreate2Factory.WalletDeployed(keccak256(bytes(login)), login, predicted);

        address deployed = factory.deployWallet(login, p);
        assertEq(deployed, predicted);
        assertEq(factory.walletOf(login), deployed);
        assertEq(factory.walletByLoginHash(keccak256(bytes(login))), deployed);
        assertEq(registry.walletOf(login), deployed);
        assertEq(registry.loginOf(deployed), login);
        assertEq(BaseMERAWallet(payable(deployed)).primary(), primary);
    }

    function test_transfer_login_to_new_address() public {
        string memory login = "bob";
        MERAWalletTypes.WalletInitParams memory p = _params();
        address deployed = factory.deployWallet(login, p);
        address newWallet = address(0x123456);

        vm.prank(deployed);
        registry.transferLogin(login, newWallet);

        assertEq(registry.walletOf(login), newWallet);
        assertEq(registry.loginHashByWallet(deployed), bytes32(0));
        assertEq(registry.loginOf(newWallet), login);
    }

    function test_deploy_twice_same_login_reverts() public {
        string memory login = "carol";
        MERAWalletTypes.WalletInitParams memory p = _params();
        factory.deployWallet(login, p);
        vm.expectRevert(MERAWalletCreate2Factory.LoginAlreadyRegistered.selector);
        factory.deployWallet(login, p);
    }

    function test_empty_login_reverts() public {
        MERAWalletTypes.WalletInitParams memory p = _params();
        vm.expectRevert(MERAWalletCreate2Factory.EmptyLogin.selector);
        factory.deployWallet("", p);
    }

    function test_predict_empty_login_reverts() public {
        MERAWalletTypes.WalletInitParams memory p = _params();
        vm.expectRevert(MERAWalletCreate2Factory.EmptyLogin.selector);
        factory.predictWallet("", p);
    }

    function test_walletOf_empty_returns_zero() public view {
        assertEq(factory.walletOf(""), address(0));
    }

    function test_non_zero_value_reverts() public {
        MERAWalletTypes.WalletInitParams memory p = _params();
        vm.expectRevert(MERAWalletCreate2Factory.NonZeroValue.selector);
        factory.deployWallet{value: 1 wei}("dave", p);
    }

    function test_constructor_reverts_for_registry_without_code() public {
        vm.expectRevert(MERAWalletCreate2Factory.LoginRegistryNotDeployed.selector);
        new MERAWalletCreate2Factory(address(0x1234));
    }
}
