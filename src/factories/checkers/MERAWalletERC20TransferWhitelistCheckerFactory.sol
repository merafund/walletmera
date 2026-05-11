// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {MERAWalletERC20TransferWhitelistChecker} from "../../checkers/MERAWalletERC20TransferWhitelistChecker.sol";

/// @notice Deploys {MERAWalletERC20TransferWhitelistChecker} instances.
contract MERAWalletERC20TransferWhitelistCheckerFactory {
    /// @notice Emitted after a checker instance is deployed.
    event Deployed(address indexed instance);

    /// @notice Deploys a new {MERAWalletERC20TransferWhitelistChecker}.
    /// @param initialOwner Owner assigned to the deployed checker.
    /// @return instance Deployed checker instance.
    function deploy(address initialOwner) external returns (MERAWalletERC20TransferWhitelistChecker instance) {
        instance = new MERAWalletERC20TransferWhitelistChecker(initialOwner);
        emit Deployed(address(instance));
    }
}
