// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {MERAWalletTypes} from "../../src/types/MERAWalletTypes.sol";
import {IMERAWalletTransactionChecker} from "../../src/interfaces/extensions/IMERAWalletTransactionChecker.sol";

contract ConfigurableTransactionChecker is IMERAWalletTransactionChecker {
    error BeforeCheckFailed();
    error AfterCheckFailed();

    /// @dev Fixed at deploy; wallet reads via `hookModes()` when whitelisting or requiring this checker.
    bool private immutable ENABLE_BEFORE_HOOK;
    bool private immutable ENABLE_AFTER_HOOK;

    bool public revertBefore;
    bool public revertAfter;

    constructor(bool enableBefore, bool enableAfter) {
        ENABLE_BEFORE_HOOK = enableBefore;
        ENABLE_AFTER_HOOK = enableAfter;
    }

    function hookModes() external view override returns (bool enableBefore, bool enableAfter) {
        return (ENABLE_BEFORE_HOOK, ENABLE_AFTER_HOOK);
    }

    function configure(bool newRevertBefore, bool newRevertAfter) external {
        revertBefore = newRevertBefore;
        revertAfter = newRevertAfter;
    }

    function checkBefore(MERAWalletTypes.Call calldata, bytes32, uint256) external view override {
        if (revertBefore) {
            revert BeforeCheckFailed();
        }
    }

    function checkAfter(MERAWalletTypes.Call calldata, bytes32, uint256) external view override {
        if (revertAfter) {
            revert AfterCheckFailed();
        }
    }
}
