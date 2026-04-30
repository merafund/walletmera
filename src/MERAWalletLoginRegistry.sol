// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IMERALoginAuthorizationVerifier} from "./interfaces/IMERALoginAuthorizationVerifier.sol";

/// @title MERAWalletLoginRegistry
/// @notice Stores MERA login ownership and the factories allowed to register new logins.
contract MERAWalletLoginRegistry is Ownable {
    uint256 public constant MIN_COMMITMENT_AGE = 60 seconds;
    uint256 public constant MAX_COMMITMENT_AGE = 15 minutes;
    uint256 public constant MIN_LOGIN_LENGTH = 3;
    uint256 public constant MAX_LOGIN_LENGTH = 32;
    uint256 public constant PAID_LOGIN_MAX_LENGTH = 9;
    uint256 public constant BASE_LOGIN_PRICE = 0.005 ether;

    struct PendingLoginMigration {
        address previousWallet;
        address newWallet;
        bytes32 newLoginHash;
    }

    address public authorizationVerifier;
    mapping(address factory => bool allowed) public isFactory;
    mapping(bytes32 commitment => uint256 committedAt) public commitments;
    mapping(bytes32 loginHash => address wallet) public walletByLoginHash;
    mapping(address wallet => bytes32 loginHash) public loginHashByWallet;
    mapping(bytes32 oldLoginHash => PendingLoginMigration migration) public pendingLoginMigrationByOldLoginHash;
    mapping(bytes32 loginHash => string login) private _loginByHash;

    event FactoryAdded(address indexed factory);
    event AuthorizationVerifierUpdated(address indexed previousVerifier, address indexed newVerifier);
    event LoginCommitmentMade(bytes32 indexed commitment, uint256 committedAt);
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
    error InvalidPayment();
    error InvalidLoginLength();
    error InvalidLoginCharacter();
    error InvalidUnderscore();
    error InvalidHyphen();
    error UnauthorizedFactory();
    error LoginAlreadyRegistered();
    error LoginNotOwned();
    error AddressAlreadyHasLogin();
    error CommitmentAlreadyExists();
    error CommitmentNotFound();
    error CommitmentTooNew();
    error CommitmentExpired();
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

    function setAuthorizationVerifier(address newVerifier) external onlyOwner {
        if (newVerifier != address(0)) {
            require(newVerifier.code.length != 0, InvalidAddress());
        }
        address previousVerifier = authorizationVerifier;
        authorizationVerifier = newVerifier;
        emit AuthorizationVerifierUpdated(previousVerifier, newVerifier);
    }

    function priceOf(string calldata login) external pure returns (uint256) {
        _requireLoginHash(login);
        return _priceOfValidatedLength(bytes(login).length);
    }

    function validateLogin(string calldata login) external pure returns (bytes32) {
        return _requireLoginHash(login);
    }

    function makeCommitment(
        string calldata login,
        address wallet,
        address factory,
        bytes32 secret,
        uint256 deadline,
        bytes32 authorizationHash
    ) external pure returns (bytes32) {
        return _makeCommitment(login, wallet, factory, secret, deadline, authorizationHash);
    }

    function commit(bytes32 commitment) external {
        require(commitments[commitment] == 0, CommitmentAlreadyExists());
        commitments[commitment] = block.timestamp + 1;
        emit LoginCommitmentMade(commitment, block.timestamp);
    }

    function registerLogin(
        string calldata login,
        address wallet,
        bytes32 secret,
        uint256 deadline,
        bytes calldata authorization
    ) external payable onlyFactory {
        require(wallet != address(0), InvalidAddress());
        bytes32 loginHash = _requireLoginHash(login);
        require(walletByLoginHash[loginHash] == address(0), LoginAlreadyRegistered());
        require(loginHashByWallet[wallet] == bytes32(0), AddressAlreadyHasLogin());
        require(msg.value == _priceOfValidatedLength(bytes(login).length), InvalidPayment());

        bytes32 commitment = _makeCommitment(login, wallet, msg.sender, secret, deadline, keccak256(authorization));
        uint256 committedAtPlusOne = commitments[commitment];
        require(committedAtPlusOne != 0, CommitmentNotFound());
        uint256 committedAt = committedAtPlusOne - 1;
        require(block.timestamp >= committedAt + MIN_COMMITMENT_AGE, CommitmentTooNew());
        require(block.timestamp <= committedAt + MAX_COMMITMENT_AGE, CommitmentExpired());

        address verifier = authorizationVerifier;
        if (verifier != address(0)) {
            IMERALoginAuthorizationVerifier(verifier)
                .validateRegistration(address(this), msg.sender, loginHash, login, wallet, deadline, authorization);
        }
        delete commitments[commitment];

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
        bytes calldata loginBytes = bytes(login);
        uint256 length = loginBytes.length;
        require(length != 0, EmptyLogin());
        require(length >= MIN_LOGIN_LENGTH && length <= MAX_LOGIN_LENGTH, InvalidLoginLength());
        for (uint256 i; i < length; ++i) {
            bytes1 char = loginBytes[i];
            if (char == "_") {
                require(i == 0 || loginBytes[i - 1] == "_", InvalidUnderscore());
            } else if (char == "-") {
                if (i == 3 && loginBytes[2] == "-") {
                    revert InvalidHyphen();
                }
            } else if ((char < "a" || char > "z") && (char < "0" || char > "9")) {
                revert InvalidLoginCharacter();
            }
        }
        return _loginHash(login);
    }

    function _priceOfValidatedLength(uint256 length) private pure returns (uint256) {
        if (length > PAID_LOGIN_MAX_LENGTH) {
            return 0;
        }
        uint256 price = BASE_LOGIN_PRICE;
        for (uint256 i = length; i < PAID_LOGIN_MAX_LENGTH; ++i) {
            price *= 10;
        }
        return price;
    }

    function _makeCommitment(
        string calldata login,
        address wallet,
        address factory,
        bytes32 secret,
        uint256 deadline,
        bytes32 authorizationHash
    ) private pure returns (bytes32) {
        require(wallet != address(0) && factory != address(0), InvalidAddress());
        return keccak256(abi.encode(_requireLoginHash(login), wallet, factory, secret, deadline, authorizationHash));
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
