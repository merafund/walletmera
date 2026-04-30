// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

/// @notice ERC20 asset allowlist used by {MERAWalletUniswapV2OracleSlippageChecker}.
interface IMERAWalletUniswapV2AssetWhitelist {
    function isAssetAllowed(address asset) external view returns (bool allowed);

    function assetSource(address asset) external view returns (address source);
}
