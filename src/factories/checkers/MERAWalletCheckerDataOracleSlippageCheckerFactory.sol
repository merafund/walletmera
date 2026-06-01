// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {
    MERAWalletCheckerDataOracleSlippageChecker
} from "../../checkers/MERAWalletCheckerDataOracleSlippageChecker.sol";

/// @notice Deploys {MERAWalletCheckerDataOracleSlippageChecker} instances.
contract MERAWalletCheckerDataOracleSlippageCheckerFactory {
    /// @notice Emitted after a checker instance is deployed.
    event Deployed(address indexed instance);

    /// @notice Deploys a new {MERAWalletCheckerDataOracleSlippageChecker}.
    /// @param initialOwner Owner assigned to the deployed checker.
    /// @param maxOracleNegativeDeviationBps Max allowed oracle shortfall in BPS.
    /// @param maxOracleStaleSeconds Max age of Chainlink `updatedAt`.
    /// @param sequencerUptimeFeed Chainlink L2 sequencer uptime feed, or `address(0)` for no-op.
    /// @param sequencerGracePeriodSeconds Delay after sequencer recovery before oracle reads are accepted.
    /// @param requireRouterAllowlist Whether router targets must be explicitly allowed.
    /// @return instance Deployed checker instance.
    function deploy(
        address initialOwner,
        uint256 maxOracleNegativeDeviationBps,
        uint256 maxOracleStaleSeconds,
        address sequencerUptimeFeed,
        uint256 sequencerGracePeriodSeconds,
        bool requireRouterAllowlist
    ) external returns (MERAWalletCheckerDataOracleSlippageChecker instance) {
        instance = new MERAWalletCheckerDataOracleSlippageChecker(
            initialOwner,
            maxOracleNegativeDeviationBps,
            maxOracleStaleSeconds,
            sequencerUptimeFeed,
            sequencerGracePeriodSeconds,
            requireRouterAllowlist
        );
        emit Deployed(address(instance));
    }
}
