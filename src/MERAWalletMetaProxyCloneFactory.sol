// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {MERAWalletTypes} from "./types/MERAWalletTypes.sol";
import {BaseMERAWallet} from "./BaseMERAWallet.sol";

/// @title MERAWalletMetaProxyCloneFactory
/// @notice Deploys deterministic `BaseMERAWallet` meta-proxy clones with init params embedded as immutable args.
contract MERAWalletMetaProxyCloneFactory {
    address public immutable WALLET_IMPLEMENTATION;

    /// @dev `salt` for CREATE2 is `keccak256(bytes(login))` (see {deployWallet}).
    mapping(bytes32 loginHash => address wallet) public walletByLoginHash;

    event WalletDeployed(bytes32 indexed loginHash, string login, address wallet);

    error EmptyLogin();
    error LoginAlreadyRegistered();
    error WalletImplementationNotDeployed();
    error NonZeroValue();

    constructor(address walletImplementation) {
        require(walletImplementation.code.length != 0, WalletImplementationNotDeployed());
        WALLET_IMPLEMENTATION = walletImplementation;
    }

    /// @notice Deploys a new `BaseMERAWallet` meta-proxy clone and stores `login` -> wallet.
    function deployWallet(string calldata login, MERAWalletTypes.WalletInitParams calldata params)
        external
        payable
        returns (address wallet)
    {
        require(msg.value == 0, NonZeroValue());
        _requireNonEmptyLogin(login);

        bytes32 salt = _salt(login);
        require(walletByLoginHash[salt] == address(0), LoginAlreadyRegistered());

        wallet = Clones.cloneDeterministicWithImmutableArgs(WALLET_IMPLEMENTATION, _immutableArgs(params), salt);
        BaseMERAWallet(payable(wallet)).initializeFromImmutableArgs();

        walletByLoginHash[salt] = wallet;
        emit WalletDeployed(salt, login, wallet);
    }

    /// @notice Returns the wallet registered for `login`, or `address(0)` if none.
    function walletOf(string calldata login) external view returns (address) {
        if (bytes(login).length == 0) {
            return address(0);
        }
        return walletByLoginHash[_salt(login)];
    }

    /// @notice Counterfactual wallet address for `login` and `params` using this factory as CREATE2 deployer.
    function predictWallet(string calldata login, MERAWalletTypes.WalletInitParams calldata params)
        external
        view
        returns (address)
    {
        _requireNonEmptyLogin(login);
        return Clones.predictDeterministicAddressWithImmutableArgs(
            WALLET_IMPLEMENTATION, _immutableArgs(params), _salt(login), address(this)
        );
    }

    function _requireNonEmptyLogin(string calldata login) private pure {
        require(bytes(login).length != 0, EmptyLogin());
    }

    function _salt(string calldata login) private pure returns (bytes32 salt) {
        assembly ("memory-safe") {
            let ptr := mload(0x40)
            calldatacopy(ptr, login.offset, login.length)
            salt := keccak256(ptr, login.length)
        }
    }

    function _immutableArgs(MERAWalletTypes.WalletInitParams calldata params) private pure returns (bytes memory) {
        return abi.encode(params);
    }
}
