// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {MERAWalletTypes} from "../../types/MERAWalletTypes.sol";

/// @notice External checker invoked by wallet execution hooks.
interface IMERAWalletTransactionChecker {
    function checkBefore(MERAWalletTypes.Call[] memory calls, bytes32 operationId) external view;

    function checkAfter(MERAWalletTypes.Call[] memory calls, bytes32 operationId) external view;
}
