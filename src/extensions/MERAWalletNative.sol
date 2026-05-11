// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {MERAWalletMemoryBatches} from "./MERAWalletMemoryBatches.sol";

/// @notice Native ETH and arbitrary-call convenience entrypoints for MERA wallets.
abstract contract MERAWalletNative is MERAWalletMemoryBatches {
    /// @notice Transfers native ETH immediately without an optional checker.
    function transferNative(address payable to, uint256 amount, uint256 salt) external nonReentrant {
        _executeSingleCall(to, amount, "", address(0), "", salt);
    }

    /// @notice Transfers native ETH immediately with optional per-call checker data.
    function transferNative(
        address payable to,
        uint256 amount,
        address checker,
        bytes calldata checkerData,
        uint256 salt
    ) external nonReentrant {
        _executeSingleCall(to, amount, "", checker, _bytesCalldataToMemory(checkerData), salt);
    }

    /// @notice Executes one arbitrary external call immediately without an optional checker.
    function callExternal(address target, uint256 value, bytes calldata data, uint256 salt) external nonReentrant {
        _executeSingleCallCalldata(target, value, data, salt);
    }

    /// @notice Executes one arbitrary external call immediately with optional checker data.
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

    /// @notice Alias for {callExternal} with checker arguments.
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
