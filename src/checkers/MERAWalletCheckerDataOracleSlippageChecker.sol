// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {MERAWalletTypes} from "../types/MERAWalletTypes.sol";
import {MERAWalletOracleSlippageCheckerBase} from "./MERAWalletOracleSlippageCheckerBase.sol";
import {MERAWalletUniswapV2SlippageTypes} from "./types/MERAWalletUniswapV2SlippageTypes.sol";

/// @notice Validates swaps against Chainlink spot prices using endpoint tokens supplied in `call.checkerData`.
/// @dev This checker never decodes `call.data`; calldata path/deadline are intentionally ignored.
contract MERAWalletCheckerDataOracleSlippageChecker is MERAWalletOracleSlippageCheckerBase {
    /// @notice Creates a checker-data oracle slippage checker.
    /// @param initialOwner Admin for router allowlist when `requireRouterAllowlist` is true (see {Ownable}).
    /// @param maxOracleNegativeDeviationBps Max allowed oracle shortfall in BPS; must be `< BPS`.
    /// @param maxOracleStaleSeconds Max age of Chainlink `updatedAt`; must be `> 0`.
    /// @param sequencerUptimeFeed Chainlink L2 sequencer uptime feed, or `address(0)` on L1/no-op deployments.
    /// @param sequencerGracePeriodSeconds Delay after sequencer recovery before oracle reads are accepted.
    /// @param requireRouterAllowlist Enforce {MERAWalletOracleSlippageCheckerBase-allowedRouter} when true.
    constructor(
        address initialOwner,
        uint256 maxOracleNegativeDeviationBps,
        uint256 maxOracleStaleSeconds,
        address sequencerUptimeFeed,
        uint256 sequencerGracePeriodSeconds,
        bool requireRouterAllowlist
    )
        MERAWalletOracleSlippageCheckerBase(
            initialOwner,
            maxOracleNegativeDeviationBps,
            maxOracleStaleSeconds,
            sequencerUptimeFeed,
            sequencerGracePeriodSeconds,
            requireRouterAllowlist
        )
    {}

    /// @inheritdoc MERAWalletOracleSlippageCheckerBase
    function _decodeSwapCheckData(MERAWalletTypes.Call calldata call)
        internal
        pure
        override
        returns (MERAWalletUniswapV2SlippageTypes.CheckerDataSlippageCheckData memory)
    {
        return abi.decode(call.checkerData, (MERAWalletUniswapV2SlippageTypes.CheckerDataSlippageCheckData));
    }
}
