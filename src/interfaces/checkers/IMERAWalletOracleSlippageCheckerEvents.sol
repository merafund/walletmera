// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {MERAWalletUniswapV2SlippageTypes} from "../../checkers/types/MERAWalletUniswapV2SlippageTypes.sol";

/// @notice Events emitted by MERAWalletOracleSlippageCheckerBase.
interface IMERAWalletOracleSlippageCheckerEvents {
    /// @notice Emitted when router allowlist state changes.
    event AllowedRouterUpdated(address indexed router, bool allowed, address indexed caller);
    /// @notice Emitted when pause-agent authorization changes.
    event PauseAgentUpdated(address indexed agent, bool allowed, address indexed caller);
    /// @notice Emitted after a wallet-specific slippage checker config is stored.
    /// @dev Emits full stored per-wallet config values.
    event WalletSlippageCheckerConfigUpdated(
        address indexed wallet, MERAWalletUniswapV2SlippageTypes.UniswapV2SlippageCheckerConfig config
    );
    /// @notice Emitted when the global fallback asset whitelist changes.
    event DefaultAssetWhitelistUpdated(
        address indexed previous, address indexed assetWhitelist, address indexed caller
    );
}
