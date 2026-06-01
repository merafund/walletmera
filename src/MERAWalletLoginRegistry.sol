// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {MERAWalletLoginRegistryConstants} from "./constants/MERAWalletLoginRegistryConstants.sol";
import {MERAWalletLoginRegistryTypes} from "./types/MERAWalletLoginRegistryTypes.sol";
import {IBaseMERAWallet} from "./interfaces/IBaseMERAWallet.sol";
import {IMERALoginAuthorizationVerifier} from "./interfaces/IMERALoginAuthorizationVerifier.sol";
import {IMERAWalletLoginRegistry} from "./interfaces/IMERAWalletLoginRegistry.sol";
import {IMERAWalletLoginRegistryErrors} from "./interfaces/IMERAWalletLoginRegistryErrors.sol";
import {IMERAWalletLoginRegistryEvents} from "./interfaces/IMERAWalletLoginRegistryEvents.sol";

/// @title MERAWalletLoginRegistry
/// @notice Stores MERA login ownership and the factories allowed to register new logins.
contract MERAWalletLoginRegistry is
    IMERAWalletLoginRegistry,
    IMERAWalletLoginRegistryEvents,
    IMERAWalletLoginRegistryErrors,
    Ownable
{
    /// @notice Optional authorization verifier used for short-login registrations.
    address public override authorizationVerifier;
    /// @notice Whether short paid logins require verifier authorization.
    bool public immutable override REQUIRE_SHORT_LOGIN_AUTHORIZATION;
    /// @notice Whether a factory address may register logins.
    mapping(address factory => bool allowed) public override isFactory;
    /// @notice Stored registration commitments as `committedAt + 1`; zero means absent.
    mapping(bytes32 commitment => uint256 committedAt) public override commitments;
    /// @notice Wallet registered for each login hash.
    mapping(bytes32 loginHash => address wallet) public override walletByLoginHash;
    /// @notice Login hash registered for each wallet.
    mapping(address wallet => bytes32 loginHash) public override loginHashByWallet;
    /// @notice Referrer login hash recorded for each login hash.
    mapping(bytes32 loginHash => bytes32 referrerLoginHash) public override referrerLoginHashByLoginHash;
    /// @notice Pending migration data by old login hash.
    mapping(bytes32 oldLoginHash => MERAWalletLoginRegistryTypes.PendingLoginMigration migration)
        public
        override pendingLoginMigrationByOldLoginHash;
    /// @notice Expiry timestamp for each pending migration; zero means absent.
    mapping(bytes32 oldLoginHash => uint256 expiresAt) public override pendingLoginMigrationExpiresAtByOldLoginHash;
    mapping(bytes32 loginHash => string login) private _loginByHash;

    /// @notice Base paid-login price.
    uint256 public override baseLoginPrice = MERAWalletLoginRegistryConstants.DEFAULT_BASE_LOGIN_PRICE;
    /// @notice Multiplier applied to shorter paid logins.
    uint256 public override loginPriceMultiplier = MERAWalletLoginRegistryConstants.DEFAULT_LOGIN_PRICE_MULTIPLIER;

    modifier onlyFactory() {
        _onlyFactory();
        _;
    }

    constructor(address initialOwner, bool requireShortLoginAuthorization) Ownable(initialOwner) {
        REQUIRE_SHORT_LOGIN_AUTHORIZATION = requireShortLoginAuthorization;
    }

    /// @inheritdoc IMERAWalletLoginRegistry
    function addFactory(address factory) external override onlyOwner {
        require(factory != address(0), InvalidAddress());
        isFactory[factory] = true;
        emit FactoryAdded(factory);
    }

    /// @inheritdoc IMERAWalletLoginRegistry
    function setAuthorizationVerifier(address newVerifier) external override onlyOwner {
        if (newVerifier != address(0)) {
            require(newVerifier.code.length != 0, InvalidAddress());
        }
        address previousVerifier = authorizationVerifier;
        authorizationVerifier = newVerifier;
        emit AuthorizationVerifierUpdated(previousVerifier, newVerifier);
    }

    /// @inheritdoc IMERAWalletLoginRegistry
    function setBaseLoginPrice(uint256 newBaseLoginPrice) external override onlyOwner {
        require(
            newBaseLoginPrice >= MERAWalletLoginRegistryConstants.MIN_BASE_LOGIN_PRICE
                && newBaseLoginPrice <= MERAWalletLoginRegistryConstants.MAX_BASE_LOGIN_PRICE,
            InvalidBaseLoginPrice()
        );
        uint256 previousPrice = baseLoginPrice;
        baseLoginPrice = newBaseLoginPrice;
        emit BaseLoginPriceUpdated(previousPrice, newBaseLoginPrice);
    }

    /// @inheritdoc IMERAWalletLoginRegistry
    function setLoginPriceMultiplier(uint256 newMultiplier) external override onlyOwner {
        require(
            newMultiplier >= MERAWalletLoginRegistryConstants.MIN_LOGIN_PRICE_MULTIPLIER
                && newMultiplier <= MERAWalletLoginRegistryConstants.MAX_LOGIN_PRICE_MULTIPLIER,
            InvalidLoginPriceMultiplier()
        );
        uint256 previousMultiplier = loginPriceMultiplier;
        loginPriceMultiplier = newMultiplier;
        emit LoginPriceMultiplierUpdated(previousMultiplier, newMultiplier);
    }

    /// @inheritdoc IMERAWalletLoginRegistry
    function withdraw() external override onlyOwner {
        uint256 amount = address(this).balance;
        require(amount != 0, NothingToWithdraw());

        address to = owner();
        (bool ok,) = payable(to).call{value: amount}("");
        require(ok, WithdrawFailed());

        emit EthWithdrawn(to, amount);
    }

    /// @inheritdoc IMERAWalletLoginRegistry
    function commit(bytes32 commitment) external override {
        require(commitments[commitment] == 0, CommitmentAlreadyExists());
        commitments[commitment] = block.timestamp + 1;
        emit LoginCommitmentMade(commitment, block.timestamp);
    }

    /// @inheritdoc IMERAWalletLoginRegistry
    function registerLogin(
        string calldata login,
        address wallet,
        bytes32 secret,
        uint256 deadline,
        bytes calldata authorization,
        string calldata referrerLogin
    ) external payable override onlyFactory {
        require(wallet != address(0), InvalidAddress());
        bytes32 loginHash = _requireLoginHash(login);
        bytes32 referrerLoginHash = _requireReferrerLoginHash(loginHash, referrerLogin);
        require(walletByLoginHash[loginHash] == address(0), LoginAlreadyRegistered());
        require(loginHashByWallet[wallet] == bytes32(0), AddressAlreadyHasLogin());

        uint256 loginLength = bytes(login).length;
        if (loginLength > MERAWalletLoginRegistryConstants.PAID_LOGIN_MAX_LENGTH) {
            require(msg.value == 0, InvalidPayment());
        } else if (REQUIRE_SHORT_LOGIN_AUTHORIZATION) {
            require(msg.value == 0, InvalidPayment());
            address verifier = authorizationVerifier;
            require(verifier != address(0), AuthorizationVerifierNotSet());
            MERAWalletLoginRegistryTypes.RegistrationValidationParams memory registrationValidation =
                MERAWalletLoginRegistryTypes.RegistrationValidationParams({
                    registry: address(this),
                    factory: msg.sender,
                    loginHash: loginHash,
                    login: login,
                    wallet: wallet,
                    deadline: deadline,
                    authorization: authorization
                });
            IMERALoginAuthorizationVerifier(verifier).validateRegistration(registrationValidation);
        } else {
            require(msg.value == _priceOfValidatedLength(loginLength), InvalidPayment());
            bytes32 commitment = _makeCommitment(
                login, wallet, msg.sender, secret, deadline, keccak256(authorization), referrerLoginHash
            );
            uint256 committedAtPlusOne = commitments[commitment];
            require(committedAtPlusOne != 0, CommitmentNotFound());
            uint256 committedAt = committedAtPlusOne - 1;
            require(
                block.timestamp >= committedAt + MERAWalletLoginRegistryConstants.MIN_COMMITMENT_AGE, CommitmentTooNew()
            );
            require(
                block.timestamp <= committedAt + MERAWalletLoginRegistryConstants.MAX_COMMITMENT_AGE,
                CommitmentExpired()
            );
            delete commitments[commitment];
        }

        walletByLoginHash[loginHash] = wallet;
        loginHashByWallet[wallet] = loginHash;
        referrerLoginHashByLoginHash[loginHash] = referrerLoginHash;
        _loginByHash[loginHash] = login;

        emit LoginRegistered(loginHash, login, wallet, msg.sender);
        emit LoginReferralRecorded(loginHash, referrerLoginHash, referrerLogin);
    }

    /// @inheritdoc IMERAWalletLoginRegistry
    function setReferrer(string calldata referrerLogin) external override {
        bytes32 loginHash = loginHashByWallet[msg.sender];
        require(loginHash != bytes32(0), LoginNotOwned());
        require(referrerLoginHashByLoginHash[loginHash] == bytes32(0), ReferrerAlreadySet());

        // Reuses validation: non-empty, registered, not self-referral.
        bytes32 referrerLoginHash = _requireReferrerLoginHash(loginHash, referrerLogin);
        require(referrerLoginHash != bytes32(0), EmptyLogin());

        referrerLoginHashByLoginHash[loginHash] = referrerLoginHash;

        emit LoginReferralRecorded(loginHash, referrerLoginHash, referrerLogin);
    }

    /// @notice Requests migration of `oldLogin` to `newLogin` and `newWallet`.
    function requestLoginMigration(string calldata oldLogin, string calldata newLogin, address newWallet)
        external
        override
    {
        require(newWallet != address(0), InvalidAddress());
        require(newWallet != msg.sender, SameWallet());
        bytes32 oldLoginHash = _requireLoginHash(oldLogin);
        bytes32 newLoginHash = _requireLoginHash(newLogin);
        require(oldLoginHash != newLoginHash, LoginAlreadyRegistered());
        require( // LCOV_EXCL_BR_LINE
            walletByLoginHash[oldLoginHash] == msg.sender && walletByLoginHash[newLoginHash] == newWallet
                && loginHashByWallet[newWallet] == newLoginHash,
            LoginNotOwned()
        );
        MERAWalletLoginRegistryTypes.PendingLoginMigration memory pendingMigration =
            pendingLoginMigrationByOldLoginHash[oldLoginHash];
        require(
            pendingMigration.previousWallet == address(0) || _isLoginMigrationExpired(oldLoginHash),
            LoginMigrationAlreadyPending()
        );

        _requireMatchingGuardianAndEmergency(msg.sender, newWallet);

        pendingLoginMigrationByOldLoginHash[oldLoginHash] = MERAWalletLoginRegistryTypes.PendingLoginMigration({
            previousWallet: msg.sender, newWallet: newWallet, newLoginHash: newLoginHash
        });
        pendingLoginMigrationExpiresAtByOldLoginHash[oldLoginHash] =
            block.timestamp + MERAWalletLoginRegistryConstants.LOGIN_MIGRATION_TTL;

        emit LoginMigrationRequested(oldLoginHash, oldLogin, newLoginHash, newLogin, msg.sender, newWallet);
    }

    /// @notice Cancels a pending login migration as the requesting wallet.
    function cancelLoginMigration(string calldata oldLogin) external override {
        bytes32 oldLoginHash = _requireLoginHash(oldLogin);
        MERAWalletLoginRegistryTypes.PendingLoginMigration memory migration =
            pendingLoginMigrationByOldLoginHash[oldLoginHash];
        require(migration.previousWallet != address(0), LoginMigrationNotFound());
        require(msg.sender == migration.previousWallet, LoginMigrationNotRequester());

        _clearPendingLoginMigration(oldLoginHash);

        emit LoginMigrationCancelled(
            oldLoginHash, oldLogin, migration.newLoginHash, migration.previousWallet, migration.newWallet
        );
    }

    /// @notice Confirms a pending login migration as the new wallet.
    function confirmLoginMigration(string calldata oldLogin) external override {
        bytes32 oldLoginHash = _requireLoginHash(oldLogin);
        MERAWalletLoginRegistryTypes.PendingLoginMigration memory migration =
            pendingLoginMigrationByOldLoginHash[oldLoginHash];
        require(
            migration.previousWallet != address(0) && !_isLoginMigrationExpired(oldLoginHash), LoginMigrationNotFound()
        );
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

        _requireMatchingGuardianAndEmergency(previousWallet, newWallet);

        string memory newLogin = _loginByHash[newLoginHash];

        walletByLoginHash[oldLoginHash] = newWallet;
        walletByLoginHash[newLoginHash] = previousWallet;
        loginHashByWallet[previousWallet] = newLoginHash;
        loginHashByWallet[newWallet] = oldLoginHash;
        _clearPendingLoginMigration(oldLoginHash);

        emit LoginMigrationConfirmed(oldLoginHash, oldLogin, newLoginHash, newLogin, previousWallet, newWallet);
        emit LoginTransferred(oldLoginHash, oldLogin, previousWallet, newWallet);
        emit LoginTransferred(newLoginHash, newLogin, newWallet, previousWallet);
    }

    /// @inheritdoc IMERAWalletLoginRegistry
    function priceOf(string calldata login) external view override returns (uint256) {
        _requireLoginHash(login);
        return _priceOfValidatedLength(bytes(login).length);
    }

    /// @inheritdoc IMERAWalletLoginRegistry
    function walletOf(string calldata login) external view override returns (address) {
        if (bytes(login).length == 0) {
            return address(0);
        }
        return walletByLoginHash[_loginHash(login)];
    }

    /// @inheritdoc IMERAWalletLoginRegistry
    function loginOf(address wallet) external view override returns (string memory) {
        return _loginByHash[loginHashByWallet[wallet]];
    }

    /// @inheritdoc IMERAWalletLoginRegistry
    function loginByHash(bytes32 loginHash) external view override returns (string memory) {
        return _loginByHash[loginHash];
    }

    /// @inheritdoc IMERAWalletLoginRegistry
    function referrerLoginHashOf(string calldata login) external view override returns (bytes32) {
        if (bytes(login).length == 0) {
            return bytes32(0);
        }
        return referrerLoginHashByLoginHash[_loginHash(login)];
    }

    /// @inheritdoc IMERAWalletLoginRegistry
    function referrerLoginOf(string calldata login) external view override returns (string memory) {
        if (bytes(login).length == 0) {
            return "";
        }
        return _loginByHash[referrerLoginHashByLoginHash[_loginHash(login)]];
    }

    /// @inheritdoc IMERAWalletLoginRegistry
    function validateLogin(string calldata login) external pure override returns (bytes32) {
        return _requireLoginHash(login);
    }

    /// @inheritdoc IMERAWalletLoginRegistry
    function makeCommitment(
        string calldata login,
        address wallet,
        address factory,
        bytes32 secret,
        uint256 deadline,
        bytes32 authorizationHash,
        string calldata referrerLogin
    ) external pure override returns (bytes32) {
        return _makeCommitment(
            login, wallet, factory, secret, deadline, authorizationHash, _optionalLoginHash(referrerLogin)
        );
    }

    function _requireReferrerLoginHash(bytes32 loginHash, string calldata referrerLogin)
        private
        view
        returns (bytes32 referrerLoginHash)
    {
        referrerLoginHash = _optionalLoginHash(referrerLogin);
        if (referrerLoginHash == bytes32(0)) {
            return bytes32(0);
        }
        require(referrerLoginHash != loginHash, SelfReferral());
        require(walletByLoginHash[referrerLoginHash] != address(0), ReferrerLoginNotRegistered());
    }

    function _priceOfValidatedLength(uint256 length) private view returns (uint256) {
        if (length > MERAWalletLoginRegistryConstants.PAID_LOGIN_MAX_LENGTH) {
            return 0;
        }
        uint256 exponent = MERAWalletLoginRegistryConstants.PAID_LOGIN_MAX_LENGTH - length;
        return baseLoginPrice * (loginPriceMultiplier ** exponent);
    }

    function _onlyFactory() private view {
        require(isFactory[msg.sender], UnauthorizedFactory());
    }

    function _isLoginMigrationExpired(bytes32 oldLoginHash) private view returns (bool) {
        uint256 expiresAt = pendingLoginMigrationExpiresAtByOldLoginHash[oldLoginHash];
        return expiresAt != 0 && block.timestamp > expiresAt;
    }

    function _clearPendingLoginMigration(bytes32 oldLoginHash) private {
        delete pendingLoginMigrationByOldLoginHash[oldLoginHash];
        delete pendingLoginMigrationExpiresAtByOldLoginHash[oldLoginHash];
    }

    /// @dev Ensures both wallets share the same guardian and emergency roles before login migration.
    function _requireMatchingGuardianAndEmergency(address previousWallet, address newWallet) private view {
        IBaseMERAWallet prev = IBaseMERAWallet(payable(previousWallet));
        IBaseMERAWallet next = IBaseMERAWallet(payable(newWallet));
        require(
            prev.guardian() == next.guardian() && prev.emergency() == next.emergency(),
            LoginMigrationGuardianEmergencyMismatch()
        );
    }

    function _requireLoginHash(string calldata login) private pure returns (bytes32) {
        bytes calldata loginBytes = bytes(login);
        uint256 length = loginBytes.length;
        require(length != 0, EmptyLogin());
        require(
            length >= MERAWalletLoginRegistryConstants.MIN_LOGIN_LENGTH
                && length <= MERAWalletLoginRegistryConstants.MAX_LOGIN_LENGTH,
            InvalidLoginLength()
        );
        for (uint256 i = 0; i < length; ++i) {
            bytes1 char = loginBytes[i];
            if (char == "-") {
                require(i != 0 && i != length - 1 && loginBytes[i - 1] != "-", InvalidHyphen());
            } else if ((char < "a" || char > "z") && (char < "0" || char > "9")) {
                revert InvalidLoginCharacter();
            }
        }
        return _loginHash(login);
    }

    function _optionalLoginHash(string calldata login) private pure returns (bytes32) {
        if (bytes(login).length == 0) {
            return bytes32(0);
        }
        return _requireLoginHash(login);
    }

    function _makeCommitment(
        string calldata login,
        address wallet,
        address factory,
        bytes32 secret,
        uint256 deadline,
        bytes32 authorizationHash,
        bytes32 referrerLoginHash
    ) private pure returns (bytes32) {
        require(wallet != address(0) && factory != address(0), InvalidAddress());
        return keccak256(
            abi.encode(
                _requireLoginHash(login), wallet, factory, secret, deadline, authorizationHash, referrerLoginHash
            )
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
