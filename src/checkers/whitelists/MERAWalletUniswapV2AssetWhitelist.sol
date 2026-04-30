// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IMERAWalletUniswapV2AssetWhitelist} from "../../interfaces/checkers/IMERAWalletUniswapV2AssetWhitelist.sol";
import {IMERAWalletUniswapV2AssetWhitelistErrors} from "../errors/IMERAWalletUniswapV2AssetWhitelistErrors.sol";

/// @title MERAWalletUniswapV2AssetWhitelist
/// @notice Ownable allowlist for swap path assets with optional fallback list contract.
/// @dev Avoid circular `fallbackWhitelist` graphs; resolution is unbounded recursion in the EVM.
contract MERAWalletUniswapV2AssetWhitelist is
    Ownable,
    IMERAWalletUniswapV2AssetWhitelist,
    IMERAWalletUniswapV2AssetWhitelistErrors
{
    event AssetAllowedUpdated(address indexed asset, bool allowed, address indexed caller);
    event FallbackWhitelistUpdated(
        address indexed previousFallback, address indexed newFallback, address indexed caller
    );

    mapping(address asset => bool allowed) public allowedAsset;

    /// @dev Secondary list consulted when `allowedAsset[asset]` is false.
    address public fallbackWhitelist;

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

    /// @notice Set optional fallback contract; pass address(0) to disable delegation.
    function setFallbackWhitelist(address newFallback) external onlyOwner {
        address previous = fallbackWhitelist;
        fallbackWhitelist = newFallback;
        emit FallbackWhitelistUpdated(previous, newFallback, msg.sender);
    }

    /// @inheritdoc IMERAWalletUniswapV2AssetWhitelist
    function isAssetAllowed(address asset) external view returns (bool) {
        if (allowedAsset[asset]) {
            return true;
        }
        address fb = fallbackWhitelist;
        if (fb != address(0)) {
            return IMERAWalletUniswapV2AssetWhitelist(fb).isAssetAllowed(asset);
        }
        return false;
    }
}
