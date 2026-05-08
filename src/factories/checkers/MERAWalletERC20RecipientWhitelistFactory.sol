// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {MERAWalletERC20RecipientWhitelist} from "../../checkers/whitelists/MERAWalletERC20RecipientWhitelist.sol";

/// @notice Deploys {MERAWalletERC20RecipientWhitelist} instances.
contract MERAWalletERC20RecipientWhitelistFactory {
    event Deployed(address indexed instance);

    function deploy(address initialOwner) external returns (MERAWalletERC20RecipientWhitelist instance) {
        instance = new MERAWalletERC20RecipientWhitelist(initialOwner);
        emit Deployed(address(instance));
    }
}
