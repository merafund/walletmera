// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {BaseMERAWallet} from "../BaseMERAWallet.sol";

abstract contract MERAWalletNative is BaseMERAWallet {
    function transferNative(address payable to, uint256 amount, uint256 nonce) external {
        bytes memory data = bytes("");
        _executeSingleCall(to, amount, data, nonce);
    }

    function callExternal(address target, uint256 value, bytes calldata data, uint256 nonce) external {
        _executeSingleCall(target, value, data, nonce);
    }
}
