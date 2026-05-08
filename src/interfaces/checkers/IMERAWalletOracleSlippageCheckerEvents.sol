// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {MERAWalletUniswapV2SlippageTypes} from "../../checkers/types/MERAWalletUniswapV2SlippageTypes.sol";

/// @notice Events emitted by MERAWalletOracleSlippageCheckerBase.
interface IMERAWalletOracleSlippageCheckerEvents {
    event AllowedRouterUpdated(address indexed router, bool allowed, address indexed caller);
    event PauseAgentUpdated(address indexed agent, bool allowed, address indexed caller);
    /// @dev Emits full stored per-wallet config values.
    event WalletSlippageCheckerConfigUpdated(
        address indexed wallet, MERAWalletUniswapV2SlippageTypes.UniswapV2SlippageCheckerConfig config
    );
    event DefaultAssetWhitelistUpdated(
        address indexed previous, address indexed assetWhitelist, address indexed caller
    );
}
