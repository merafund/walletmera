// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {MERAWalletTypes} from "../types/MERAWalletTypes.sol";
import {IMERAWalletTransactionChecker} from "../interfaces/checkers/IMERAWalletTransactionChecker.sol";
import {IMERAWalletERC20RecipientWhitelist} from "../interfaces/checkers/IMERAWalletERC20RecipientWhitelist.sol";
import {IMERAWalletAssetWhiteList} from "../interfaces/checkers/IMERAWalletAssetWhiteList.sol";
import {IMERAWalletWhitelistRouter} from "../interfaces/checkers/IMERAWalletWhitelistRouter.sol";
import {IMERAWalletERC20WhitelistCheckerErrors} from "./errors/IMERAWalletERC20WhitelistCheckerErrors.sol";
import {MERAWalletERC20WhitelistCheckerTypes} from "./types/MERAWalletERC20WhitelistCheckerTypes.sol";

/// @notice Shared logic for ERC20 `transfer` / `approve` whitelist checkers (separate deployed instances per operation).
abstract contract MERAWalletERC20WhitelistCheckerBase is
    Ownable,
    IMERAWalletTransactionChecker,
    IMERAWalletERC20WhitelistCheckerErrors
{
    /// @dev Minimum calldata length for standard ERC20 `transfer(address,uint256)` / `approve(address,uint256)`:
    /// selector (4) + ABI-encoded `to`/`spender` (32) + `amount` (32).
    uint256 internal constant _ERC20_TRANSFER_OR_APPROVE_BODY_LEN = 4 + 32 + 32;
    bytes32 internal constant _ASSET_WHITELIST_KEY = keccak256("MERA_ASSET_WHITELIST");
    bytes32 internal constant _RECIPIENT_WHITELIST_KEY = keccak256("MERA_RECIPIENT_WHITELIST");

    mapping(address agent => bool allowed) public isPauseAgent;

    mapping(address wallet => MERAWalletERC20WhitelistCheckerTypes.Erc20WhitelistCheckerConfig) public walletConfig;

    address public defaultAssetWhitelist;
    address public defaultRecipientWhitelist;

    event WalletErc20WhitelistCheckerConfigUpdated(
        address indexed wallet, MERAWalletERC20WhitelistCheckerTypes.Erc20WhitelistCheckerConfig config
    );
    event DefaultAssetWhitelistUpdated(address indexed previous, address indexed newWhitelist, address indexed caller);
    event DefaultRecipientWhitelistUpdated(
        address indexed previous, address indexed newWhitelist, address indexed caller
    );

    constructor(address initialOwner) Ownable(initialOwner) {}

    /// @dev Expected ERC20 selector (`IERC20.transfer` or `IERC20.approve`).
    function _expectedSelector() internal pure virtual returns (bytes4);

    /// @inheritdoc IMERAWalletTransactionChecker
    function applyConfig(bytes calldata config) external override {
        if (config.length == 0) {
            return;
        }
        MERAWalletERC20WhitelistCheckerTypes.Erc20WhitelistCheckerConfig memory decoded =
            abi.decode(config, (MERAWalletERC20WhitelistCheckerTypes.Erc20WhitelistCheckerConfig));
        walletConfig[msg.sender] = decoded;
        emit WalletErc20WhitelistCheckerConfigUpdated(msg.sender, decoded);
    }

    function setDefaultAssetWhitelist(address newWhitelist) external onlyOwner {
        address previous = defaultAssetWhitelist;
        defaultAssetWhitelist = newWhitelist;
        emit DefaultAssetWhitelistUpdated(previous, newWhitelist, msg.sender);
    }

    function setDefaultRecipientWhitelist(address newWhitelist) external onlyOwner {
        address previous = defaultRecipientWhitelist;
        defaultRecipientWhitelist = newWhitelist;
        emit DefaultRecipientWhitelistUpdated(previous, newWhitelist, msg.sender);
    }

    /// @inheritdoc IMERAWalletTransactionChecker
    function hookModes() external pure override returns (bool enableBefore, bool enableAfter) {
        return (true, false);
    }

    function checkBefore(MERAWalletTypes.Call calldata call, bytes32, uint256 callId) external override {
        require(call.value == 0, Erc20WhitelistNonZeroValue(callId));

        bytes calldata data = call.data;
        require(data.length >= _ERC20_TRANSFER_OR_APPROVE_BODY_LEN, Erc20WhitelistCalldataTooShort(callId));

        bytes4 functionSelector = bytes4(data[0:4]);
        require(functionSelector == _expectedSelector(), Erc20WhitelistUnexpectedSelector(functionSelector, callId));

        (address counterparty,) = abi.decode(data[4:], (address, uint256));

        address wallet = msg.sender;
        address token = call.target;

        _requireTokenAllowed(wallet, token, callId);
        _requireCounterpartyAllowed(wallet, counterparty, callId);
    }

    function checkAfter(MERAWalletTypes.Call calldata, bytes32, uint256) external override {}

    function _effectiveAssetWhitelist(address wallet) internal view returns (address) {
        MERAWalletERC20WhitelistCheckerTypes.Erc20WhitelistCheckerConfig storage walletCheckerConfig =
            walletConfig[wallet];
        address assetWhitelistAddress = walletCheckerConfig.assetWhitelist;
        if (assetWhitelistAddress != address(0)) {
            return assetWhitelistAddress;
        }
        assetWhitelistAddress = _routerWhitelist(walletCheckerConfig.whitelistRouter, _ASSET_WHITELIST_KEY);
        if (assetWhitelistAddress != address(0)) {
            return assetWhitelistAddress;
        }
        return defaultAssetWhitelist;
    }

    function _effectiveRecipientWhitelist(address wallet) internal view returns (address) {
        MERAWalletERC20WhitelistCheckerTypes.Erc20WhitelistCheckerConfig storage walletCheckerConfig =
            walletConfig[wallet];
        address recipientWhitelistAddress = walletCheckerConfig.recipientWhitelist;
        if (recipientWhitelistAddress != address(0)) {
            return recipientWhitelistAddress;
        }
        recipientWhitelistAddress = _routerWhitelist(walletCheckerConfig.whitelistRouter, _RECIPIENT_WHITELIST_KEY);
        if (recipientWhitelistAddress != address(0)) {
            return recipientWhitelistAddress;
        }
        return defaultRecipientWhitelist;
    }

    function _routerWhitelist(address whitelistRouter, bytes32 key) internal view returns (address) {
        if (whitelistRouter == address(0)) {
            return address(0);
        }
        return IMERAWalletWhitelistRouter(whitelistRouter).whitelistByHash(key);
    }

    /// @dev No-op when no asset list is configured for `wallet`.
    function _requireTokenAllowed(address wallet, address token, uint256 callId) internal view {
        address effectiveAssetWhitelist = _effectiveAssetWhitelist(wallet);
        if (effectiveAssetWhitelist == address(0)) {
            return;
        }
        require(
            IMERAWalletAssetWhiteList(effectiveAssetWhitelist).isAssetAllowed(token),
            Erc20WhitelistTokenNotAllowed(token, callId)
        );
    }

    /// @dev No-op when no counterparty list is configured for `wallet`; `account` is transfer `to` or approve `spender`.
    function _requireCounterpartyAllowed(address wallet, address account, uint256 callId) internal view {
        address effectiveRecipientWhitelist = _effectiveRecipientWhitelist(wallet);
        if (effectiveRecipientWhitelist == address(0)) {
            return;
        }
        require(
            IMERAWalletERC20RecipientWhitelist(effectiveRecipientWhitelist).isRecipientAllowed(account),
            Erc20WhitelistCounterpartyNotAllowed(account, callId)
        );
    }
}
