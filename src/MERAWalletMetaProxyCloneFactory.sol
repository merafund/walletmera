// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {MERAWalletTypes} from "./types/MERAWalletTypes.sol";
import {BaseMERAWallet} from "./BaseMERAWallet.sol";
import {MERAWalletLoginRegistry} from "./MERAWalletLoginRegistry.sol";

/// @title MERAWalletMetaProxyCloneFactory
/// @notice Deploys deterministic `BaseMERAWallet` meta-proxy clones with init params embedded as immutable args.
contract MERAWalletMetaProxyCloneFactory {
    address public immutable WALLET_IMPLEMENTATION;
    MERAWalletLoginRegistry public immutable LOGIN_REGISTRY;

    event WalletDeployed(bytes32 indexed loginHash, string login, address wallet);

    error LoginAlreadyRegistered();
    error WalletImplementationNotDeployed();
    error LoginRegistryNotDeployed();

    constructor(address walletImplementation, address loginRegistry) {
        require(walletImplementation.code.length != 0, WalletImplementationNotDeployed());
        require(loginRegistry.code.length != 0, LoginRegistryNotDeployed());
        WALLET_IMPLEMENTATION = walletImplementation;
        LOGIN_REGISTRY = MERAWalletLoginRegistry(loginRegistry);
    }

    /// @notice Deploys a new `BaseMERAWallet` meta-proxy clone and stores `login` -> wallet.
    function deployWallet(
        string calldata login,
        MERAWalletTypes.WalletInitParams calldata params,
        bytes32 secret,
        uint256 deadline,
        bytes calldata authorization
    ) external payable returns (address wallet) {
        return _deployWallet(login, params, secret, deadline, authorization, "");
    }

    function deployWallet(
        string calldata login,
        MERAWalletTypes.WalletInitParams calldata params,
        bytes32 secret,
        uint256 deadline,
        bytes calldata authorization,
        string calldata referrerLogin
    ) external payable returns (address wallet) {
        return _deployWallet(login, params, secret, deadline, authorization, referrerLogin);
    }

    function _deployWallet(
        string calldata login,
        MERAWalletTypes.WalletInitParams calldata params,
        bytes32 secret,
        uint256 deadline,
        bytes calldata authorization,
        string memory referrerLogin
    ) private returns (address wallet) {
        bytes32 loginHash = _loginHash(login);
        require(LOGIN_REGISTRY.walletByLoginHash(loginHash) == address(0), LoginAlreadyRegistered());

        wallet = Clones.cloneDeterministicWithImmutableArgs(WALLET_IMPLEMENTATION, abi.encode(params), loginHash);
        BaseMERAWallet(payable(wallet)).initializeFromImmutableArgs();

        LOGIN_REGISTRY.registerLogin{value: msg.value}(login, wallet, secret, deadline, authorization, referrerLogin);
        emit WalletDeployed(loginHash, login, wallet);
    }

    /// @notice Counterfactual wallet address for `login` and `params` using this factory as CREATE2 deployer.
    function predictWallet(string calldata login, MERAWalletTypes.WalletInitParams calldata params)
        external
        view
        returns (address)
    {
        return Clones.predictDeterministicAddressWithImmutableArgs(
            WALLET_IMPLEMENTATION, abi.encode(params), _loginHash(login), address(this)
        );
    }

    function _loginHash(string calldata login) private pure returns (bytes32 loginHash) {
        assembly ("memory-safe") {
            let ptr := mload(0x40)
            calldatacopy(ptr, login.offset, login.length)
            loginHash := keccak256(ptr, login.length)
        }
    }
}
