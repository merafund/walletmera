// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {MERAWalletMemoryBatches} from "./MERAWalletMemoryBatches.sol";

abstract contract MERAWalletNative is MERAWalletMemoryBatches {
    function transferNative(address payable to, uint256 amount, uint256 salt) external nonReentrant {
        _executeSingleCall(to, amount, "", address(0), "", salt);
    }

    function transferNative(
        address payable to,
        uint256 amount,
        address checker,
        bytes calldata checkerData,
        uint256 salt
    ) external nonReentrant {
        _executeSingleCall(to, amount, "", checker, _bytesCalldataToMemory(checkerData), salt);
    }

    function callExternal(address target, uint256 value, bytes calldata data, uint256 salt) external nonReentrant {
        _executeSingleCallCalldata(target, value, data, salt);
    }

    function callExternal(
        address target,
        uint256 value,
        bytes calldata data,
        address checker,
        bytes calldata checkerData,
        uint256 salt
    ) external nonReentrant {
        _executeSingleCallCalldata(target, value, data, checker, checkerData, salt);
    }

    function callExternalWithChecker(
        address target,
        uint256 value,
        bytes calldata data,
        address checker,
        bytes calldata checkerData,
        uint256 salt
    ) external nonReentrant {
        _executeSingleCallCalldata(target, value, data, checker, checkerData, salt);
    }
}
