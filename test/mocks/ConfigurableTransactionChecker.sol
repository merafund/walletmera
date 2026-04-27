// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {MERAWalletTypes} from "../../src/types/MERAWalletTypes.sol";
import {IMERAWalletTransactionChecker} from "../../src/interfaces/extensions/IMERAWalletTransactionChecker.sol";

contract ConfigurableTransactionChecker is IMERAWalletTransactionChecker {
    error BeforeCheckFailed();
    error AfterCheckFailed();
    error ApplyConfigNotAuthorized();

    /// @dev Fixed at deploy; wallet reads via `hookModes()` when whitelisting or requiring this checker.
    bool private immutable ENABLE_BEFORE_HOOK;
    bool private immutable ENABLE_AFTER_HOOK;

    /// @dev MERA wallet that may call {applyConfig} with non-empty payload (matches registration target).
    address public immutable MERA_WALLET;

    bool public revertBefore;
    bool public revertAfter;

    constructor(bool enableBefore, bool enableAfter, address merawallet_) {
        ENABLE_BEFORE_HOOK = enableBefore;
        ENABLE_AFTER_HOOK = enableAfter;
        MERA_WALLET = merawallet_;
    }

    function hookModes() external view override returns (bool enableBefore, bool enableAfter) {
        return (ENABLE_BEFORE_HOOK, ENABLE_AFTER_HOOK);
    }

    function configure(bool newRevertBefore, bool newRevertAfter) external {
        revertBefore = newRevertBefore;
        revertAfter = newRevertAfter;
    }

    /// @inheritdoc IMERAWalletTransactionChecker
    function applyConfig(bytes calldata config) external override {
        if (config.length == 0) {
            return;
        }
        require(msg.sender == MERA_WALLET && MERA_WALLET != address(0), ApplyConfigNotAuthorized());
        (bool newRevertBefore, bool newRevertAfter) = abi.decode(config, (bool, bool));
        revertBefore = newRevertBefore;
        revertAfter = newRevertAfter;
    }

    function checkBefore(MERAWalletTypes.Call calldata, bytes32, uint256) external override {
        require(!revertBefore, BeforeCheckFailed());
    }

    function checkAfter(MERAWalletTypes.Call calldata, bytes32, uint256) external override {
        require(!revertAfter, AfterCheckFailed());
    }
}
