// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IMERAWalletAssetWhiteList} from "../../interfaces/checkers/IMERAWalletAssetWhiteList.sol";
import {IMERAWalletAssetWhiteListErrors} from "../errors/IMERAWalletAssetWhiteListErrors.sol";

/// @title MERAWalletAssetWhiteList
/// @notice Ownable allowlist for swap path assets with optional fallback list contract.
/// @dev Avoid circular `fallbackWhitelist` graphs; resolution is unbounded recursion in the EVM.
contract MERAWalletAssetWhiteList is Ownable, IMERAWalletAssetWhiteList, IMERAWalletAssetWhiteListErrors {
    /// @notice Emitted when an asset's local allow flag changes.
    event AssetAllowedUpdated(address indexed asset, bool allowed, address indexed caller);
    /// @notice Emitted when an asset's local oracle source changes.
    event AssetSourceUpdated(address indexed asset, address indexed source, address indexed caller);
    /// @notice Emitted when the fallback whitelist changes.
    event FallbackWhitelistUpdated(
        address indexed previousFallback, address indexed newFallback, address indexed caller
    );

    /// @notice Local allow flags by asset address.
    mapping(address asset => bool allowed) public allowedAsset;
    /// @notice Local price-feed sources by asset address.
    mapping(address asset => address source) public localAssetSource;

    /// @notice Secondary list consulted when local allow/source data is absent.
    address public fallbackWhitelist;

    /// @notice Creates an asset whitelist owned by `initialOwner`.
    constructor(address initialOwner) Ownable(initialOwner) {}

    /// @notice Batch-set local allow flags; pairs `assets[i]` with `allowed[i]`.
    function setAllowedAssets(address[] calldata assets, bool[] calldata allowed) external onlyOwner {
        uint256 n = assets.length;
        require(n == allowed.length, AssetWhitelistArrayLengthMismatch());
        for (uint256 i = 0; i < n;) {
            address asset = assets[i];
            require(asset != address(0), AssetWhitelistInvalidAddress());
            allowedAsset[asset] = allowed[i];
            emit AssetAllowedUpdated(asset, allowed[i], msg.sender);
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Batch-set local oracle sources; pairs `assets[i]` with `sources[i]`.
    /// @dev A zero source clears the local override and falls back to the base feed or fallback list.
    function setAssetSources(address[] calldata assets, address[] calldata sources) external onlyOwner {
        uint256 n = assets.length;
        require(n == sources.length, AssetWhitelistArrayLengthMismatch());
        for (uint256 i = 0; i < n;) {
            address asset = assets[i];
            require(asset != address(0), AssetWhitelistInvalidAddress());
            localAssetSource[asset] = sources[i];
            emit AssetSourceUpdated(asset, sources[i], msg.sender);
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Sets optional fallback contract; pass address(0) to disable delegation.
    function setFallbackWhitelist(address newFallback) external onlyOwner {
        address previous = fallbackWhitelist;
        fallbackWhitelist = newFallback;
        emit FallbackWhitelistUpdated(previous, newFallback, msg.sender);
    }

    /// @inheritdoc IMERAWalletAssetWhiteList
    function isAssetAllowed(address asset) external view returns (bool) {
        if (allowedAsset[asset]) {
            return true;
        }
        address fallbackWhitelistAddress = fallbackWhitelist;
        if (fallbackWhitelistAddress != address(0)) {
            return IMERAWalletAssetWhiteList(fallbackWhitelistAddress).isAssetAllowed(asset);
        }
        return false;
    }

    /// @inheritdoc IMERAWalletAssetWhiteList
    function assetSource(address asset) external view returns (address) {
        address source = localAssetSource[asset];
        if (source != address(0)) {
            return source;
        }
        address fallbackWhitelistAddress = fallbackWhitelist;
        if (fallbackWhitelistAddress != address(0)) {
            return IMERAWalletAssetWhiteList(fallbackWhitelistAddress).assetSource(asset);
        }
        return address(0);
    }
}
