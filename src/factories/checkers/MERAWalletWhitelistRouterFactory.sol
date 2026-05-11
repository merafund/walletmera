// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {MERAWalletWhitelistRouter} from "../../checkers/whitelists/MERAWalletWhitelistRouter.sol";

/// @notice Deploys {MERAWalletWhitelistRouter} instances.
contract MERAWalletWhitelistRouterFactory {
    /// @notice Emitted after a router instance is deployed.
    event Deployed(address indexed instance);

    /// @notice Deploys a new {MERAWalletWhitelistRouter}.
    /// @param initialOwner Owner assigned to the deployed router.
    /// @return instance Deployed router instance.
    function deploy(address initialOwner) external returns (MERAWalletWhitelistRouter instance) {
        instance = new MERAWalletWhitelistRouter(initialOwner);
        emit Deployed(address(instance));
    }
}
