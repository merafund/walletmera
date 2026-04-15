// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {BaseMERAWallet} from "../BaseMERAWallet.sol";
import {MERAWalletTypes} from "../types/MERAWalletTypes.sol";
import {MERAWalletNative} from "./MERAWalletNative.sol";
import {MERAWalletERC20} from "./token/ERC20/MERAWalletERC20.sol";
import {MERAWalletTransactionChecks} from "./MERAWalletTransactionChecks.sol";

contract MERAWalletFull is MERAWalletNative, MERAWalletERC20, MERAWalletTransactionChecks {
    constructor(address initialPrimary, address initialBackup, address initialEmergency, address initialSigner)
        BaseMERAWallet(initialPrimary, initialBackup, initialEmergency, initialSigner)
    {}

    function _beforeExecute(MERAWalletTypes.Call[] memory calls, bytes32 operationId)
        internal
        override(BaseMERAWallet, MERAWalletTransactionChecks)
    {
        super._beforeExecute(calls, operationId);
    }

    function _afterExecute(MERAWalletTypes.Call[] memory calls, bytes32 operationId)
        internal
        override(BaseMERAWallet, MERAWalletTransactionChecks)
    {
        super._afterExecute(calls, operationId);
    }
}
