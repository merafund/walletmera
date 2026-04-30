// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title MERAWalletLoginRegistry
/// @notice Stores MERA login ownership and the factories allowed to register new logins.
contract MERAWalletLoginRegistry is Ownable {
    struct PendingLoginMigration {
        address previousWallet;
        address newWallet;
        bytes32 newLoginHash;
    }

    mapping(address factory => bool allowed) public isFactory;
    mapping(bytes32 loginHash => address wallet) public walletByLoginHash;
    mapping(address wallet => bytes32 loginHash) public loginHashByWallet;
    mapping(bytes32 oldLoginHash => PendingLoginMigration migration) public pendingLoginMigrationByOldLoginHash;
    mapping(bytes32 loginHash => string login) private _loginByHash;

    event FactoryAdded(address indexed factory);
    event LoginRegistered(bytes32 indexed loginHash, string login, address indexed wallet, address indexed factory);
    event LoginTransferred(
        bytes32 indexed loginHash, string login, address indexed previousWallet, address indexed newWallet
    );
    event LoginMigrationRequested(
        bytes32 indexed oldLoginHash,
        string oldLogin,
        bytes32 indexed newLoginHash,
        string newLogin,
        address indexed previousWallet,
        address newWallet
    );
    event LoginMigrationConfirmed(
        bytes32 indexed oldLoginHash,
        string oldLogin,
        bytes32 indexed newLoginHash,
        string newLogin,
        address indexed previousWallet,
        address newWallet
    );

    error EmptyLogin();
    error InvalidAddress();
    error UnauthorizedFactory();
    error LoginAlreadyRegistered();
    error LoginNotOwned();
    error AddressAlreadyHasLogin();
    error SameWallet();
    error LoginMigrationAlreadyPending();
    error LoginMigrationNotFound();
    error LoginMigrationNotConfirmingWallet();
    error LoginMigrationStale();

    modifier onlyFactory() {
        _onlyFactory();
        _;
    }

    constructor(address initialOwner) Ownable(initialOwner) {}

    /// @notice Whitelist a factory permanently; removal is not supported (avoids bricking deployed factories).
    function addFactory(address factory) external onlyOwner {
        require(factory != address(0), InvalidAddress());
        isFactory[factory] = true;
        emit FactoryAdded(factory);
    }

    function registerLogin(string calldata login, address wallet) external onlyFactory {
        require(wallet != address(0), InvalidAddress());
        bytes32 loginHash = _requireLoginHash(login);
        require(walletByLoginHash[loginHash] == address(0), LoginAlreadyRegistered());
        require(loginHashByWallet[wallet] == bytes32(0), AddressAlreadyHasLogin());

        walletByLoginHash[loginHash] = wallet;
        loginHashByWallet[wallet] = loginHash;
        _loginByHash[loginHash] = login;

        emit LoginRegistered(loginHash, login, wallet, msg.sender);
    }

    function requestLoginMigration(string calldata oldLogin, string calldata newLogin, address newWallet) external {
        require(newWallet != address(0), InvalidAddress());
        require(newWallet != msg.sender, SameWallet());
        bytes32 oldLoginHash = _requireLoginHash(oldLogin);
        bytes32 newLoginHash = _requireLoginHash(newLogin);
        require(oldLoginHash != newLoginHash, LoginAlreadyRegistered());
        require(walletByLoginHash[oldLoginHash] == msg.sender, LoginNotOwned());
        require(walletByLoginHash[newLoginHash] == newWallet, LoginNotOwned());
        require(loginHashByWallet[newWallet] == newLoginHash, LoginNotOwned());
        require(
            pendingLoginMigrationByOldLoginHash[oldLoginHash].previousWallet == address(0),
            LoginMigrationAlreadyPending()
        );

        pendingLoginMigrationByOldLoginHash[oldLoginHash] =
            PendingLoginMigration({previousWallet: msg.sender, newWallet: newWallet, newLoginHash: newLoginHash});

        emit LoginMigrationRequested(oldLoginHash, oldLogin, newLoginHash, newLogin, msg.sender, newWallet);
    }

    function confirmLoginMigration(string calldata oldLogin) external {
        bytes32 oldLoginHash = _requireLoginHash(oldLogin);
        PendingLoginMigration memory migration = pendingLoginMigrationByOldLoginHash[oldLoginHash];
        require(migration.previousWallet != address(0), LoginMigrationNotFound());
        require(msg.sender == migration.newWallet, LoginMigrationNotConfirmingWallet());

        address previousWallet = migration.previousWallet;
        address newWallet = migration.newWallet;
        bytes32 newLoginHash = migration.newLoginHash;
        // Both registrations must still match the request before the final login swap.
        require(
            walletByLoginHash[oldLoginHash] == previousWallet && walletByLoginHash[newLoginHash] == newWallet
                && loginHashByWallet[previousWallet] == oldLoginHash && loginHashByWallet[newWallet] == newLoginHash,
            LoginMigrationStale()
        );

        string memory newLogin = _loginByHash[newLoginHash];

        walletByLoginHash[oldLoginHash] = newWallet;
        walletByLoginHash[newLoginHash] = previousWallet;
        loginHashByWallet[previousWallet] = newLoginHash;
        loginHashByWallet[newWallet] = oldLoginHash;
        delete pendingLoginMigrationByOldLoginHash[oldLoginHash];

        emit LoginMigrationConfirmed(oldLoginHash, oldLogin, newLoginHash, newLogin, previousWallet, newWallet);
        emit LoginTransferred(oldLoginHash, oldLogin, previousWallet, newWallet);
        emit LoginTransferred(newLoginHash, newLogin, newWallet, previousWallet);
    }

    function walletOf(string calldata login) external view returns (address) {
        if (bytes(login).length == 0) {
            return address(0);
        }
        return walletByLoginHash[_loginHash(login)];
    }

    function loginOf(address wallet) external view returns (string memory) {
        return _loginByHash[loginHashByWallet[wallet]];
    }

    function loginByHash(bytes32 loginHash) external view returns (string memory) {
        return _loginByHash[loginHash];
    }

    function _requireLoginHash(string calldata login) private pure returns (bytes32) {
        require(bytes(login).length != 0, EmptyLogin());
        return _loginHash(login);
    }

    function _onlyFactory() private view {
        require(isFactory[msg.sender], UnauthorizedFactory());
    }

    function _loginHash(string calldata login) private pure returns (bytes32 loginHash) {
        assembly ("memory-safe") {
            let ptr := mload(0x40)
            calldatacopy(ptr, login.offset, login.length)
            loginHash := keccak256(ptr, login.length)
        }
    }
}
