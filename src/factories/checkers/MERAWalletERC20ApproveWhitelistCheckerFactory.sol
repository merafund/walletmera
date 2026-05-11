// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {MERAWalletERC20ApproveWhitelistChecker} from "../../checkers/MERAWalletERC20ApproveWhitelistChecker.sol";

/// @notice Deploys {MERAWalletERC20ApproveWhitelistChecker} instances.
contract MERAWalletERC20ApproveWhitelistCheckerFactory {
    /// @notice Emitted after a checker instance is deployed.
    event Deployed(address indexed instance);

    /// @notice Deploys a new {MERAWalletERC20ApproveWhitelistChecker}.
    /// @param initialOwner Owner assigned to the deployed checker.
    /// @return instance Deployed checker instance.
    function deploy(address initialOwner) external returns (MERAWalletERC20ApproveWhitelistChecker instance) {
        instance = new MERAWalletERC20ApproveWhitelistChecker(initialOwner);
        emit Deployed(address(instance));
    }
}
