// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {MERAWalletTargetBlacklistChecker} from "../../checkers/MERAWalletTargetBlacklistChecker.sol";

/// @notice Deploys {MERAWalletTargetBlacklistChecker} instances.
contract MERAWalletTargetBlacklistCheckerFactory {
    /// @notice Emitted after a checker instance is deployed.
    event Deployed(address indexed instance);

    /// @notice Deploys a new {MERAWalletTargetBlacklistChecker}.
    /// @param initialOwner Owner assigned to the deployed checker.
    /// @return instance Deployed checker instance.
    function deploy(address initialOwner) external returns (MERAWalletTargetBlacklistChecker instance) {
        instance = new MERAWalletTargetBlacklistChecker(initialOwner);
        emit Deployed(address(instance));
    }
}
