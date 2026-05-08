// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {MERAWalletERC20ApproveWhitelistChecker} from "../../checkers/MERAWalletERC20ApproveWhitelistChecker.sol";

/// @notice Deploys {MERAWalletERC20ApproveWhitelistChecker} instances.
contract MERAWalletERC20ApproveWhitelistCheckerFactory {
    event Deployed(address indexed instance);

    function deploy(address initialOwner) external returns (MERAWalletERC20ApproveWhitelistChecker instance) {
        instance = new MERAWalletERC20ApproveWhitelistChecker(initialOwner);
        emit Deployed(address(instance));
    }
}
