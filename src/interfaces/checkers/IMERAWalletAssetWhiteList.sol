// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

/// @notice ERC20 asset allowlist used by {MERAWalletUniswapV2OracleSlippageChecker}.
interface IMERAWalletAssetWhiteList {
    /// @notice Returns whether `asset` is allowed by this whitelist or its fallback.
    /// @param asset Asset address to check.
    /// @return allowed True when the asset may be used.
    function isAssetAllowed(address asset) external view returns (bool allowed);

    /// @notice Returns the Chainlink-style price feed configured for `asset`.
    /// @param asset Asset address whose source is requested.
    /// @return source Price feed address, or zero when unset.
    function assetSource(address asset) external view returns (address source);
}
