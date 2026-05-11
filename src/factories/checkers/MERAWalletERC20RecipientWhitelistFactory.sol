// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {MERAWalletERC20RecipientWhitelist} from "../../checkers/whitelists/MERAWalletERC20RecipientWhitelist.sol";

/// @notice Deploys {MERAWalletERC20RecipientWhitelist} instances.
contract MERAWalletERC20RecipientWhitelistFactory {
    /// @notice Emitted after a whitelist instance is deployed.
    event Deployed(address indexed instance);

    /// @notice Deploys a new {MERAWalletERC20RecipientWhitelist}.
    /// @param initialOwner Owner assigned to the deployed whitelist.
    /// @return instance Deployed whitelist instance.
    function deploy(address initialOwner) external returns (MERAWalletERC20RecipientWhitelist instance) {
        instance = new MERAWalletERC20RecipientWhitelist(initialOwner);
        emit Deployed(address(instance));
    }
}
