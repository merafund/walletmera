// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {MERAWalletUniswapV2OracleSlippageChecker} from "../../checkers/MERAWalletUniswapV2OracleSlippageChecker.sol";

/// @notice Deploys {MERAWalletUniswapV2OracleSlippageChecker} instances.
contract MERAWalletUniswapV2OracleSlippageCheckerFactory {
    event Deployed(address indexed instance);

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
