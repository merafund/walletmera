// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {MERAWalletUniswapV2OracleSlippageChecker} from "../../checkers/MERAWalletUniswapV2OracleSlippageChecker.sol";

/// @notice Deploys {MERAWalletUniswapV2OracleSlippageChecker} instances.
contract MERAWalletUniswapV2OracleSlippageCheckerFactory {
    /// @notice Emitted after a checker instance is deployed.
    event Deployed(address indexed instance);

    /// @notice Deploys a new {MERAWalletUniswapV2OracleSlippageChecker}.
    /// @param initialOwner Owner assigned to the deployed checker.
    /// @param maxOracleNegativeDeviationBps Max allowed oracle shortfall in BPS.
    /// @param maxOracleStaleSeconds Max age of Chainlink `updatedAt`.
    /// @param requireRouterAllowlist Whether router targets must be explicitly allowed.
    /// @return instance Deployed checker instance.
    function deploy(
        address initialOwner,
        uint256 maxOracleNegativeDeviationBps,
        uint256 maxOracleStaleSeconds,
        bool requireRouterAllowlist
    ) external returns (MERAWalletUniswapV2OracleSlippageChecker instance) {
        instance = new MERAWalletUniswapV2OracleSlippageChecker(
            initialOwner, maxOracleNegativeDeviationBps, maxOracleStaleSeconds, requireRouterAllowlist
        );
        emit Deployed(address(instance));
    }
}
