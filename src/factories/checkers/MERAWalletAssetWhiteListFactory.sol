// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {MERAWalletAssetWhiteList} from "../../checkers/whitelists/MERAWalletAssetWhiteList.sol";

/// @notice Deploys {MERAWalletAssetWhiteList} instances.
contract MERAWalletAssetWhiteListFactory {
    /// @notice Emitted after a whitelist instance is deployed.
    event Deployed(address indexed instance);

    /// @notice Deploys a new {MERAWalletAssetWhiteList}.
    /// @param initialOwner Owner assigned to the deployed whitelist.
    /// @return instance Deployed whitelist instance.
    function deploy(address initialOwner) external returns (MERAWalletAssetWhiteList instance) {
        instance = new MERAWalletAssetWhiteList(initialOwner);
        emit Deployed(address(instance));
    }
}
