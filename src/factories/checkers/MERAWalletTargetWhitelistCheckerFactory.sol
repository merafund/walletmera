// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {MERAWalletTargetWhitelistChecker} from "../../checkers/MERAWalletTargetWhitelistChecker.sol";

/// @notice Deploys {MERAWalletTargetWhitelistChecker} instances.
contract MERAWalletTargetWhitelistCheckerFactory {
    event Deployed(address indexed instance);

    function deploy(address initialOwner) external returns (MERAWalletTargetWhitelistChecker instance) {
        instance = new MERAWalletTargetWhitelistChecker(initialOwner);
        emit Deployed(address(instance));
    }
}
