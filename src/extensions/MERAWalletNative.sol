// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {BaseMERAWallet} from "../BaseMERAWallet.sol";

abstract contract MERAWalletNative is BaseMERAWallet {
    function transferNative(address payable to, uint256 amount) external {
        bytes memory data = bytes("");
        _executeSingleCall(to, amount, data);
    }

    function callExternal(address target, uint256 value, bytes calldata data) external {
        _executeSingleCall(target, value, data);
    }
}
