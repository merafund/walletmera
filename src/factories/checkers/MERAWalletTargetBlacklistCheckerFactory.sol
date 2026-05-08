// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {MERAWalletTargetBlacklistChecker} from "../../checkers/MERAWalletTargetBlacklistChecker.sol";

/// @notice Deploys {MERAWalletTargetBlacklistChecker} instances.
contract MERAWalletTargetBlacklistCheckerFactory {
    event Deployed(address indexed instance);

    function deploy(address initialOwner) external returns (MERAWalletTargetBlacklistChecker instance) {
        instance = new MERAWalletTargetBlacklistChecker(initialOwner);
        emit Deployed(address(instance));
    }
}
