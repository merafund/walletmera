// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {
    MERAWalletCheckerDataOracleSlippageChecker
} from "../../checkers/MERAWalletCheckerDataOracleSlippageChecker.sol";

/// @notice Deploys {MERAWalletCheckerDataOracleSlippageChecker} instances.
contract MERAWalletCheckerDataOracleSlippageCheckerFactory {
    event Deployed(address indexed instance);

    function deploy(
        address initialOwner,
        uint256 maxOracleNegativeDeviationBps,
        uint256 maxOracleStaleSeconds,
        bool requireRouterAllowlist
    ) external returns (MERAWalletCheckerDataOracleSlippageChecker instance) {
        instance = new MERAWalletCheckerDataOracleSlippageChecker(
            initialOwner, maxOracleNegativeDeviationBps, maxOracleStaleSeconds, requireRouterAllowlist
        );
        emit Deployed(address(instance));
    }
}
