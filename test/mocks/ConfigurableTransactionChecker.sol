// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {MERAWalletTypes} from "../../src/types/MERAWalletTypes.sol";
import {IMERAWalletTransactionChecker} from "../../src/interfaces/extensions/IMERAWalletTransactionChecker.sol";

contract ConfigurableTransactionChecker is IMERAWalletTransactionChecker {
    error BeforeCheckFailed();
    error AfterCheckFailed();

    bool public revertBefore;
    bool public revertAfter;

    function configure(bool newRevertBefore, bool newRevertAfter) external {
        revertBefore = newRevertBefore;
        revertAfter = newRevertAfter;
    }

    function checkBefore(MERAWalletTypes.Call[] memory, bytes32) external view override {
        if (revertBefore) {
            revert BeforeCheckFailed();
        }
    }

    function checkAfter(MERAWalletTypes.Call[] memory, bytes32) external view override {
        if (revertAfter) {
            revert AfterCheckFailed();
        }
    }
}
