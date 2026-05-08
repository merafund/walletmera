// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {MERAWalletWhitelistRouter} from "../../checkers/whitelists/MERAWalletWhitelistRouter.sol";

/// @notice Deploys {MERAWalletWhitelistRouter} instances.
contract MERAWalletWhitelistRouterFactory {
    event Deployed(address indexed instance);

    function deploy(address initialOwner) external returns (MERAWalletWhitelistRouter instance) {
        instance = new MERAWalletWhitelistRouter(initialOwner);
        emit Deployed(address(instance));
    }
}
