// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {BaseMERAWallet} from "../BaseMERAWallet.sol";

abstract contract MERAWalletNative is BaseMERAWallet {
    function transferNative(address payable to, uint256 amount, uint256 nonce) external {
        _executeSingleCall(to, amount, "", address(0), "", nonce);
    }

    function callExternal(address target, uint256 value, bytes calldata data, uint256 nonce) external {
        bytes memory dataMem = data;
        _executeSingleCall(target, value, dataMem, address(0), "", nonce);
    }

    function callExternalWithChecker(
        address target,
        uint256 value,
        bytes calldata data,
        address checker,
        bytes calldata checkerData,
        uint256 nonce
    ) external {
        bytes memory dataMem = data;
        bytes memory checkerDataMem = checkerData;
        _executeSingleCall(target, value, dataMem, checker, checkerDataMem, nonce);
    }
}
