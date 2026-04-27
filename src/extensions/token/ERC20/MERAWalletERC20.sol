// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {MERAWalletMemoryBatches} from "../../MERAWalletMemoryBatches.sol";

abstract contract MERAWalletERC20 is MERAWalletMemoryBatches {
    function transferERC20(
        address token,
        address to,
        uint256 amount,
        address checker,
        bytes calldata checkerData,
        uint256 salt
    ) external {
        bytes memory data = abi.encodeWithSelector(IERC20.transfer.selector, to, amount);
        _executeSingleCall(token, 0, data, checker, _bytesCalldataToMemory(checkerData), salt);
    }

    /// @notice Proposes a single ERC-20 transfer (uses wallet timelock policy). Pass checker `address(0)` to skip.
    function proposeTransferERC20(
        address token,
        address to,
        uint256 amount,
        address checker,
        bytes calldata checkerData,
        uint256 salt
    ) external returns (bytes32 operationId) {
        bytes memory data = abi.encodeWithSelector(IERC20.transfer.selector, to, amount);
        bytes memory checkerMem = checker == address(0) ? new bytes(0) : _bytesCalldataToMemory(checkerData);
        operationId = _proposeSingleCallMemory(token, 0, data, checker, checkerMem, salt);
    }

    /// @notice Proposes a single ERC-20 approve (uses wallet timelock policy). Pass checker `address(0)` to skip.
    function proposeApproveERC20(
        address token,
        address spender,
        uint256 amount,
        address checker,
        bytes calldata checkerData,
        uint256 salt
    ) external returns (bytes32 operationId) {
        bytes memory data = abi.encodeWithSelector(IERC20.approve.selector, spender, amount);
        bytes memory checkerMem = checker == address(0) ? new bytes(0) : _bytesCalldataToMemory(checkerData);
        operationId = _proposeSingleCallMemory(token, 0, data, checker, checkerMem, salt);
    }

    /// @notice Executes a pending ERC-20 transfer proposed earlier. Pass checker `address(0)` to skip.
    function executePendingTransferERC20(
        address token,
        address to,
        uint256 amount,
        address checker,
        bytes calldata checkerData,
        uint256 salt
    ) external payable {
        bytes memory data = abi.encodeWithSelector(IERC20.transfer.selector, to, amount);
        bytes memory checkerMem = checker == address(0) ? new bytes(0) : _bytesCalldataToMemory(checkerData);
        _executePendingSingleCallMemory(token, 0, data, checker, checkerMem, salt);
    }

    /// @notice Executes a pending ERC-20 approve proposed earlier. Pass checker `address(0)` to skip.
    function executePendingApproveERC20(
        address token,
        address spender,
        uint256 amount,
        address checker,
        bytes calldata checkerData,
        uint256 salt
    ) external payable {
        bytes memory data = abi.encodeWithSelector(IERC20.approve.selector, spender, amount);
        bytes memory checkerMem = checker == address(0) ? new bytes(0) : _bytesCalldataToMemory(checkerData);
        _executePendingSingleCallMemory(token, 0, data, checker, checkerMem, salt);
    }
}
