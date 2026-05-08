// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {MERAWalletAssetWhiteList} from "../../checkers/whitelists/MERAWalletAssetWhiteList.sol";

/// @notice Deploys {MERAWalletAssetWhiteList} instances.
contract MERAWalletAssetWhiteListFactory {
    event Deployed(address indexed instance);

    function deploy(address initialOwner) external returns (MERAWalletAssetWhiteList instance) {
        instance = new MERAWalletAssetWhiteList(initialOwner);
        emit Deployed(address(instance));
    }
}
