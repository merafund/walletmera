// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {MERAWalletConstants} from "./constants/MERAWalletConstants.sol";
import {MERAWalletTypes} from "./types/MERAWalletTypes.sol";
import {MERAWalletFull} from "./extensions/MERAWalletFull.sol";

/// @title MERAWalletCreate2Factory
/// @notice Deploys `MERAWalletFull` via the global Nick deterministic CREATE2 proxy and records `login` → wallet.
contract MERAWalletCreate2Factory {
    /// @dev `salt` for CREATE2 is `keccak256(bytes(login))` (see {deployWallet}).
    mapping(bytes32 loginHash => address wallet) public walletByLoginHash;

    event WalletDeployed(bytes32 indexed loginHash, string login, address wallet);

    error EmptyLogin();
    error LoginAlreadyRegistered();
    error Create2DeployerNotDeployed();
    error FactoryCallFailed();
    error InvalidReturnData();
    error AddressMismatch(address expected, address actual);
    error NonZeroValue();

    /// @notice Deploys a new `MERAWalletFull` via the deterministic CREATE2 proxy and stores `login` → wallet.
    /// @dev Reverts if `login` was already used, if the proxy is missing on this chain, or if deployment fails.
    function deployWallet(string calldata login, MERAWalletTypes.WalletInitParams calldata params)
        external
        payable
        returns (address wallet)
    {
        require(msg.value == 0, NonZeroValue());

        require(MERAWalletConstants.DETERMINISTIC_CREATE2_DEPLOYER.code.length != 0, Create2DeployerNotDeployed());

        _requireNonEmptyLogin(login);
        (bytes32 salt, bytes memory initCode) = _saltAndInitCode(login, params);
        require(walletByLoginHash[salt] == address(0), LoginAlreadyRegistered());
        address predicted =
            Create2.computeAddress(salt, keccak256(initCode), MERAWalletConstants.DETERMINISTIC_CREATE2_DEPLOYER);

        bytes memory data = abi.encodePacked(salt, initCode);
        (bool ok, bytes memory ret) = MERAWalletConstants.DETERMINISTIC_CREATE2_DEPLOYER.call(data);
        require(ok, FactoryCallFailed());

        wallet = _parseReturnedAddress(ret);
        require(wallet != address(0), InvalidReturnData());
        require(wallet == predicted, AddressMismatch(predicted, wallet));

        walletByLoginHash[salt] = wallet;
        emit WalletDeployed(salt, login, wallet);
    }

    /// @notice Returns the wallet registered for `login`, or `address(0)` if none.
    function walletOf(string calldata login) external view returns (address) {
        if (bytes(login).length == 0) {
            return address(0);
        }
        return walletByLoginHash[keccak256(bytes(login))];
    }

    /// @notice Counterfactual wallet address for `login` and `params` using the Nick CREATE2 deployer.
    /// @dev Salt is `keccak256(bytes(login))` only; changing `params` changes init code and thus the address.
    function predictWallet(string calldata login, MERAWalletTypes.WalletInitParams calldata params)
        external
        pure
        returns (address)
    {
        _requireNonEmptyLogin(login);
        (bytes32 salt, bytes memory initCode) = _saltAndInitCode(login, params);
        return Create2.computeAddress(salt, keccak256(initCode), MERAWalletConstants.DETERMINISTIC_CREATE2_DEPLOYER);
    }

    function _requireNonEmptyLogin(string calldata login) private pure {
        require(bytes(login).length != 0, EmptyLogin());
    }

    /// @dev Salt scheme v1: `keccak256(bytes(login))` (documented, do not change without versioning).
    function _saltAndInitCode(string calldata login, MERAWalletTypes.WalletInitParams calldata params)
        private
        pure
        returns (bytes32 salt, bytes memory initCode)
    {
        salt = keccak256(bytes(login));
        initCode = abi.encodePacked(
            type(MERAWalletFull).creationCode,
            abi.encode(
                params.initialPrimary,
                params.initialBackup,
                params.initialEmergency,
                params.initialSigner,
                params.initialGuardian
            )
        );
    }

    /// @dev Nick proxy returns 20 bytes (raw address) or 32-byte ABI-encoded address.
    function _parseReturnedAddress(bytes memory ret) private pure returns (address addr) {
        uint256 len = ret.length;
        if (len == 20) {
            assembly ("memory-safe") {
                addr := shr(96, mload(add(ret, 0x20)))
            }
            return addr;
        }
        if (len >= 32) {
            return abi.decode(ret, (address));
        }
        return address(0);
    }
}
