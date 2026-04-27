// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title MERAWalletLoginRegistry
/// @notice Stores MERA login ownership and the factories allowed to register new logins.
contract MERAWalletLoginRegistry is Ownable {
    mapping(address factory => bool allowed) public isFactory;
    mapping(bytes32 loginHash => address wallet) public walletByLoginHash;
    mapping(address wallet => bytes32 loginHash) public loginHashByWallet;
    mapping(bytes32 loginHash => string login) private _loginByHash;

    event FactoryUpdated(address indexed factory, bool allowed);
    event LoginRegistered(bytes32 indexed loginHash, string login, address indexed wallet, address indexed factory);
    event LoginTransferred(
        bytes32 indexed loginHash, string login, address indexed previousWallet, address indexed newWallet
    );

    error EmptyLogin();
    error InvalidAddress();
    error UnauthorizedFactory();
    error LoginAlreadyRegistered();
    error LoginNotOwned();
    error AddressAlreadyHasLogin();

    modifier onlyFactory() {
        require(isFactory[msg.sender], UnauthorizedFactory());
        _;
    }

    constructor(address initialOwner) Ownable(initialOwner) {}

    function setFactory(address factory, bool allowed) external onlyOwner {
        require(factory != address(0), InvalidAddress());
        isFactory[factory] = allowed;
        emit FactoryUpdated(factory, allowed);
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

    function transferLogin(string calldata login, address newWallet) external {
        require(newWallet != address(0), InvalidAddress());
        bytes32 loginHash = _requireLoginHash(login);
        require(walletByLoginHash[loginHash] == msg.sender, LoginNotOwned());
        require(loginHashByWallet[newWallet] == bytes32(0), AddressAlreadyHasLogin());

        address previousWallet = msg.sender;
        walletByLoginHash[loginHash] = newWallet;
        loginHashByWallet[previousWallet] = bytes32(0);
        loginHashByWallet[newWallet] = loginHash;

        emit LoginTransferred(loginHash, login, previousWallet, newWallet);
    }

    function walletOf(string calldata login) external view returns (address) {
        if (bytes(login).length == 0) {
            return address(0);
        }
        return walletByLoginHash[keccak256(bytes(login))];
    }

    function loginOf(address wallet) external view returns (string memory) {
        return _loginByHash[loginHashByWallet[wallet]];
    }

    function loginByHash(bytes32 loginHash) external view returns (string memory) {
        return _loginByHash[loginHash];
    }

    function _requireLoginHash(string calldata login) private pure returns (bytes32) {
        require(bytes(login).length != 0, EmptyLogin());
        return keccak256(bytes(login));
    }
}
