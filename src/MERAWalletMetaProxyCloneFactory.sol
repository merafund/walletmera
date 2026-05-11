// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {MERAWalletTypes} from "./types/MERAWalletTypes.sol";
import {BaseMERAWallet} from "./BaseMERAWallet.sol";
import {IMERAWalletLoginRegistry} from "./interfaces/IMERAWalletLoginRegistry.sol";

/// @title MERAWalletMetaProxyCloneFactory
/// @notice Deploys deterministic `BaseMERAWallet` meta-proxy clones with init params embedded as immutable args.
contract MERAWalletMetaProxyCloneFactory {
    /// @notice Base wallet implementation cloned by this factory.
    address public immutable WALLET_IMPLEMENTATION;
    /// @notice Login registry used when registering deployed wallets.
    IMERAWalletLoginRegistry public immutable LOGIN_REGISTRY;

    /// @notice Emitted after a wallet clone is deployed and registered.
    event WalletDeployed(bytes32 indexed loginHash, string login, address wallet);

    /// @notice Reverts when the requested login is already registered.
    error LoginAlreadyRegistered();
    /// @notice Reverts when the wallet implementation address has no code.
    error WalletImplementationNotDeployed();
    /// @notice Reverts when the login registry address has no code.
    error LoginRegistryNotDeployed();

    /// @notice Creates the factory.
    /// @param walletImplementation Base wallet implementation to clone.
    /// @param loginRegistry Registry used for login registration.
    constructor(address walletImplementation, address loginRegistry) {
        require(walletImplementation.code.length != 0, WalletImplementationNotDeployed());
        require(loginRegistry.code.length != 0, LoginRegistryNotDeployed());
        WALLET_IMPLEMENTATION = walletImplementation;
        LOGIN_REGISTRY = IMERAWalletLoginRegistry(loginRegistry);
    }

    /// @notice Deploys a deterministic wallet clone and registers `login`.
    /// @param login Login to register for the new wallet.
    /// @param params Wallet initialization parameters embedded as immutable args.
    /// @param secret Commitment secret for paid registration.
    /// @param deadline Registration authorization deadline.
    /// @param authorization Optional authorization payload for short-login registration.
    /// @param referrerLogin Optional referrer login.
    /// @return wallet Deployed wallet clone address.
    function deployWallet(
        string calldata login,
        MERAWalletTypes.WalletInitParams calldata params,
        bytes32 secret,
        uint256 deadline,
        bytes calldata authorization,
        string calldata referrerLogin
    ) external payable returns (address wallet) {
        bytes32 loginHash = _loginHash(login);
        require(LOGIN_REGISTRY.walletByLoginHash(loginHash) == address(0), LoginAlreadyRegistered());

        wallet = Clones.cloneDeterministicWithImmutableArgs(WALLET_IMPLEMENTATION, abi.encode(params), loginHash);
        BaseMERAWallet(payable(wallet)).initializeFromImmutableArgs();

        LOGIN_REGISTRY.registerLogin{value: msg.value}(login, wallet, secret, deadline, authorization, referrerLogin);
        emit WalletDeployed(loginHash, login, wallet);
    }

    /// @notice Counterfactual wallet address for `login` and `params` using this factory as CREATE2 deployer.
    /// @param login Login used as the deterministic salt source.
    /// @param params Wallet initialization parameters embedded as immutable args.
    /// @return Counterfactual wallet address.
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
